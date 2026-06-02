# Database Integrations

`query_analyzer` is database-agnostic.  The `DatabaseWrapper` intercepts
queries at the Dart level — no native drivers are modified or replaced.

The package ships three adapter base classes that provide schema introspection
helpers for the most popular databases.

---

## How Adapters Work

An adapter is an **abstract mixin class** that:

1. Extends `DatabaseConnection` (your driver's connection class must
   implement this interface).
2. Adds introspection methods (`introspectSchema()`, `explainAnalyze()`, etc.)
   that query the database's system tables.

You implement the concrete driver bridge; the adapter provides the SQL.

---

## PostgreSQL — `PostgresAdapter`

```dart
import 'package:query_analyzer/query_analyzer.dart';

class MyPostgresConnection extends PostgresAdapter {
  final PostgreSQLConnection _pg;  // from package:postgres
  MyPostgresConnection(this._pg);

  @override
  Future<List<Map<String, dynamic>>> query(String sql,
      {List? arguments, Map<String, dynamic>? namedArguments}) async {
    final result = await _pg.mappedResultsQuery(sql,
        substitutionValues: namedArguments?.cast());
    return result.map((r) => r.values.first).toList();
  }

  @override
  Future<int> execute(String sql,
      {List? arguments, Map<String, dynamic>? namedArguments}) async {
    return _pg.execute(sql, substitutionValues: namedArguments?.cast());
  }

  @override
  Future<void> close() => _pg.close();
}
```

### Schema Introspection

```dart
final conn = MyPostgresConnection(pgConn);
final schema = await conn.introspectSchema(schema: 'public');

final core = QueryAnalyzerCore(
  config: const QueryAnalyzerConfig(),
  schema: schema,
);
```

`introspectSchema()` queries:
- `information_schema.tables` — table list + approximate row count from `pg_stat_user_tables`
- `information_schema.columns` — column metadata + primary-key detection
- `pg_index` — index membership per column
- `pg_am` — index type (BTREE, HASH, GIN, …)

### EXPLAIN ANALYZE

```dart
final plan = await conn.explainAnalyze(
  'SELECT * FROM orders WHERE user_id = 42',
);

print('Has seq scan: ${plan.hasSeqScan}');
print('Estimated cost: ${plan.estimatedCost}');
print('Actual time: ${plan.actualTimeMs}ms');
```

---

## MySQL / MariaDB — `MySqlAdapter`

```dart
class MyMySqlConnection extends MySqlAdapter {
  final MySqlConnection _mysql;
  MyMySqlConnection(this._mysql);

  @override
  Future<List<Map<String, dynamic>>> query(String sql, {...}) async {
    final results = await _mysql.query(sql);
    return results.map((r) => r.fields).toList();
  }

  // ... execute, close
}
```

### Schema Introspection

```dart
final schema = await conn.introspectSchema(databaseName: 'my_app_db');
```

Queries `information_schema.TABLES`, `information_schema.COLUMNS`,
and `information_schema.STATISTICS` for index information.

### EXPLAIN (MySQL FORMAT=JSON)

```dart
final plan = await conn.explainQuery('SELECT * FROM orders WHERE status = ?');
print('Has seq scan: ${plan.hasSeqScan}');
```

---

## SQLite — `SQLiteAdapter`

```dart
class MySQLiteConnection extends SQLiteAdapter {
  final Database _db;  // from package:sqflite_common_ffi
  MySQLiteConnection(this._db);

  @override
  Future<List<Map<String, dynamic>>> query(String sql, {...}) =>
      _db.rawQuery(sql, arguments);

  @override
  Future<int> execute(String sql, {...}) =>
      _db.rawDelete(sql, arguments);  // or rawInsert / rawUpdate

  @override
  Future<void> close() => _db.close();
}
```

### Schema Introspection

```dart
final schema = await conn.introspectSchema();
```

Uses `sqlite_master`, `PRAGMA table_info(…)`, `PRAGMA index_list(…)`,
and `PRAGMA index_info(…)`.

### EXPLAIN QUERY PLAN

```dart
final plan = await conn.explainQueryPlan(
  'SELECT * FROM products WHERE category = ?',
);
print('Uses index: ${!plan.hasSeqScan}');
```

---

## ExplainPlan

All three adapters return an `ExplainPlan` object:

```dart
class ExplainPlan {
  final String rawOutput;    // full EXPLAIN output text
  final bool hasSeqScan;     // true if sequential scan detected
  final double? estimatedCost;
  final double? actualTimeMs;  // PostgreSQL ANALYZE only
}
```

---

## Schema-Less Mode

If schema introspection is not feasible (e.g. the application has no
permission to query system tables), use `DatabaseSchema.empty`:

```dart
final core = QueryAnalyzerCore(
  config: const QueryAnalyzerConfig(),
  schema: DatabaseSchema.empty('postgresql'),
);
```

In schema-less mode:
- `MissingIndexDetector` cannot check column indexes and produces no issues.
- `FullTableScanDetector` only checks for missing WHERE clauses (rule 1 and 3).
- `LargeResultDetector` uses `actualRowCount` if provided.

---

## Manual Schema Definition

If you know your schema but cannot introspect it at runtime:

```dart
final schema = DatabaseSchema(
  engineName: 'postgresql',
  tables: [
    TableSchema(
      name: 'orders',
      schema: 'public',
      columns: [
        ColumnSchema(name: 'id',          dataType: 'INTEGER', isPrimaryKey: true),
        ColumnSchema(name: 'customer_id', dataType: 'INTEGER', hasIndex: true),
        ColumnSchema(name: 'status',      dataType: 'TEXT',    hasIndex: false),
        ColumnSchema(name: 'total',       dataType: 'NUMERIC', hasIndex: false),
        ColumnSchema(name: 'created_at',  dataType: 'TIMESTAMPTZ', hasIndex: true),
      ],
      indexes: [
        IndexSchema(name: 'idx_orders_customer', tableName: 'orders',
            columns: ['customer_id']),
        IndexSchema(name: 'idx_orders_created',  tableName: 'orders',
            columns: ['created_at']),
      ],
      approximateRowCount: 5_000_000,
    ),
  ],
  loadedAt: DateTime.now(),
);
```

---

## Periodic Schema Refresh

When `config.schemaRefreshIntervalMinutes > 0`, your application should
re-introspect the schema periodically and update the `QueryAnalyzerCore`.
The simplest approach is to recreate the core:

```dart
Timer.periodic(
  Duration(minutes: config.schemaRefreshIntervalMinutes),
  (_) async {
    final newSchema = await myConn.introspectSchema();
    // Create a new core with refreshed schema
    // (existing listeners are re-registered)
    final newCore = QueryAnalyzerCore(config: config, schema: newSchema);
    dbWrapper = DatabaseWrapper(connection: myConn, analyzer: newCore);
  },
);
```

---

## Supported Databases

| Database | Adapter | Introspection | EXPLAIN |
|----------|---------|---------------|---------|
| PostgreSQL | `PostgresAdapter` | ✅ | EXPLAIN (ANALYZE, FORMAT TEXT) |
| MySQL / MariaDB | `MySqlAdapter` | ✅ | EXPLAIN FORMAT=JSON |
| SQLite | `SQLiteAdapter` | ✅ | EXPLAIN QUERY PLAN |
| Any SQL DB | Manual `DatabaseConnection` impl | Manual `DatabaseSchema` | — |
