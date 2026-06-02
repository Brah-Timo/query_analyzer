# Schema Introspection

Schema awareness dramatically improves the quality of `query_analyzer`'s
index detection.  Without a schema, the analyzer can only flag structural
issues (no WHERE clause, SELECT *, etc.).  With a schema, it knows which
specific columns lack indexes and how large each table is.

---

## Schema Model

```
DatabaseSchema
 └── tables: List<TableSchema>
       └── columns: List<ColumnSchema>
       └── indexes: List<IndexSchema>
```

### DatabaseSchema

```dart
class DatabaseSchema {
  final List<TableSchema> tables;
  final String engineName;       // 'postgresql', 'mysql', 'sqlite', 'unknown'
  final String? engineVersion;
  final DateTime loadedAt;

  factory DatabaseSchema.empty(String engineName);
  TableSchema? findTable(String tableName);   // case-insensitive
}
```

### TableSchema

```dart
class TableSchema {
  final String name;
  final String schema;           // namespace, e.g. 'public'
  final List<ColumnSchema> columns;
  final List<IndexSchema> indexes;
  final int? approximateRowCount;

  List<ColumnSchema> get indexedColumns;     // columns with index or PK
  List<ColumnSchema> get unindexedColumns;   // columns without any index
  bool hasIndexOn(String columnName);        // case-insensitive check
  ColumnSchema? findColumn(String name);     // throws StateError if missing
}
```

### ColumnSchema

```dart
class ColumnSchema {
  final String name;
  final String dataType;
  final bool nullable;           // default: true
  final bool isPrimaryKey;       // default: false
  final bool hasIndex;           // default: false
  final String? defaultValue;

  bool get looksLikeForeignKey;  // name ends in '_id' or 'Id'
}
```

### IndexSchema

```dart
class IndexSchema {
  final String name;
  final String tableName;
  final List<String> columns;    // in order
  final bool isUnique;
  final bool isPrimary;
  final String indexType;        // 'BTREE', 'HASH', 'GIN', …
}
```

---

## Using the Adapter Introspectors

Each database adapter provides an `introspectSchema()` method that queries
the database's system tables.  See [integrations.md](integrations.md) for
driver wiring details.

### PostgreSQL

```dart
// conn implements DatabaseConnection + PostgresAdapter
final schema = await conn.introspectSchema(schema: 'public');
```

Queries used:

| Table / View | Purpose |
|---|---|
| `information_schema.tables` | Table list |
| `pg_stat_user_tables` | Approximate row counts |
| `information_schema.columns` | Column metadata |
| `information_schema.key_column_usage` + `table_constraints` | Primary key detection |
| `pg_index` + `pg_attribute` | Index membership per column |
| `pg_am` | Index type name |

### MySQL

```dart
final schema = await conn.introspectSchema(databaseName: 'my_app');
```

Queries used:

| Table | Purpose |
|---|---|
| `information_schema.TABLES` | Table list + row count estimate |
| `information_schema.COLUMNS` | Column metadata + primary key |
| `information_schema.STATISTICS` | Per-column index membership |

### SQLite

```dart
final schema = await conn.introspectSchema();
```

Queries used:

| Source | Purpose |
|---|---|
| `sqlite_master` | Table list |
| `PRAGMA table_info(table)` | Column metadata |
| `PRAGMA index_list(table)` | Index list |
| `PRAGMA index_info(index)` | Columns per index |

---

## Manual Schema Definition

When introspection is not available at runtime, define the schema in code:

```dart
final schema = DatabaseSchema(
  engineName: 'postgresql',
  tables: [
    TableSchema(
      name: 'users',
      columns: [
        ColumnSchema(name: 'id',    dataType: 'SERIAL',  isPrimaryKey: true),
        ColumnSchema(name: 'email', dataType: 'TEXT',    hasIndex: true, nullable: false),
        ColumnSchema(name: 'name',  dataType: 'TEXT',    hasIndex: false),
        ColumnSchema(name: 'role',  dataType: 'TEXT',    hasIndex: false),
      ],
      indexes: [
        IndexSchema(name: 'users_pkey',        tableName: 'users', columns: ['id'],    isPrimary: true),
        IndexSchema(name: 'users_email_key',   tableName: 'users', columns: ['email'], isUnique: true),
      ],
      approximateRowCount: 150_000,
    ),
    TableSchema(
      name: 'orders',
      columns: [
        ColumnSchema(name: 'id',          dataType: 'SERIAL',      isPrimaryKey: true),
        ColumnSchema(name: 'user_id',     dataType: 'INTEGER',     hasIndex: true),
        ColumnSchema(name: 'status',      dataType: 'TEXT',        hasIndex: false),
        ColumnSchema(name: 'total',       dataType: 'NUMERIC(10,2)', hasIndex: false),
        ColumnSchema(name: 'created_at',  dataType: 'TIMESTAMPTZ', hasIndex: true),
      ],
      indexes: [
        IndexSchema(name: 'orders_pkey',         tableName: 'orders', columns: ['id'],         isPrimary: true),
        IndexSchema(name: 'idx_orders_user',     tableName: 'orders', columns: ['user_id']),
        IndexSchema(name: 'idx_orders_created',  tableName: 'orders', columns: ['created_at']),
      ],
      approximateRowCount: 8_000_000,
    ),
  ],
  loadedAt: DateTime.now(),
);
```

---

## Impact of Schema on Detection

| Detector | Schema-less | Schema-aware |
|----------|-------------|--------------|
| No WHERE clause | ✅ detected | ✅ detected + row-count severity |
| WHERE on un-indexed column | ❌ not detected | ✅ detected |
| JOIN on un-indexed column | ❌ not detected | ✅ detected |
| Missing foreign-key index | ❌ not detected | ✅ detected + FK suggestion |
| LIKE operator | ✅ detected | ✅ detected |
| Large result (row count) | Structural only | ✅ with row-count feedback |

---

## Schema Caching

If introspection is expensive, wrap it in a `CacheManager`:

```dart
final schemaCache = CacheManager<String, DatabaseSchema>(
  ttl: const Duration(hours: 1),
);

Future<DatabaseSchema> getSchema(String schemaName) async {
  return schemaCache.getOrCompute(
    schemaName,
    () => myConn.introspectSchema(schema: schemaName),
  );
}
```

`CacheManager` automatically prunes expired entries on a background timer
that fires every TTL period.  Call `schemaCache.dispose()` to cancel the timer.

---

## Column Naming Conventions

`query_analyzer` uses case-insensitive column comparisons throughout (via
`.toLowerCase()`).  Column names from the parser may include a table prefix
(`orders.user_id`) — the prefix is stripped before index lookup.

The **foreign-key heuristic** (`ColumnSchema.looksLikeForeignKey`) flags
columns whose names end in `_id` (e.g. `user_id`, `order_id`) or `Id`
(camelCase: `userId`, `orderId`).  This is purely a naming convention and
does not inspect actual FK constraints.
