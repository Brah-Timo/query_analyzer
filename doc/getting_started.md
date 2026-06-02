# Getting Started with query_analyzer

`query_analyzer` is a professional Dart package for automatic monitoring,
profiling, and intelligent diagnosis of slow database queries.  It works with
any database driver, requires zero configuration to get started, and ships
with built-in detectors for the most common SQL performance anti-patterns.

---

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  query_analyzer: ^1.0.0
```

Then run:

```bash
dart pub get
```

---

## Minimal Setup (5 minutes)

### 1. Import the package

```dart
import 'package:query_analyzer/query_analyzer.dart';
```

### 2. Create the analyzer

```dart
final core = QueryAnalyzerFacade.create(
  config: QueryAnalyzerConfig.custom(
    slowQueryThresholdMs: 500,   // flag queries > 500 ms
    detectNPlusOne: true,
  ),
);
```

### 3. Wrap your database connection

Implement `DatabaseConnection` for your driver:

```dart
class MyPostgresConnection implements DatabaseConnection {
  @override
  Future<List<Map<String, dynamic>>> query(String sql,
      {List? arguments, Map<String, dynamic>? namedArguments}) async {
    // delegate to your postgres driver
  }

  @override
  Future<int> execute(String sql,
      {List? arguments, Map<String, dynamic>? namedArguments}) async {
    // delegate to your postgres driver
  }

  @override
  Future<void> close() async { /* ... */ }
}
```

```dart
final db = DatabaseWrapper(
  connection: MyPostgresConnection(),
  analyzer: core,
);
```

### 4. Register a slow-query callback

```dart
db.onSlowQuery = (sql, ms, suggestions) {
  print('⚠️  Slow query (${ms}ms): $sql');
  for (final s in suggestions) {
    print('   → ${s.title}');
  }
};
```

### 5. Use `db` exactly as before

```dart
final rows = await db.query(
  'SELECT * FROM orders WHERE user_id = ?',
  arguments: [42],
);
```

### 6. Generate a report

```dart
final report = QueryAnalyzerFacade.generateReport(core);
print(report.summary);
```

---

## Schema-Aware Mode

For richer index-aware analysis, pass a `DatabaseSchema` when building the
core.  See [schema_introspection.md](schema_introspection.md) for details.

```dart
final schema = DatabaseSchema(
  engineName: 'postgresql',
  tables: [
    TableSchema(
      name: 'orders',
      columns: [
        ColumnSchema(name: 'id',      dataType: 'INTEGER', isPrimaryKey: true),
        ColumnSchema(name: 'user_id', dataType: 'INTEGER', hasIndex: false),
        ColumnSchema(name: 'total',   dataType: 'NUMERIC'),
      ],
      approximateRowCount: 2_000_000,
    ),
  ],
  loadedAt: DateTime.now(),
);

final core = QueryAnalyzerCore(
  config: const QueryAnalyzerConfig(),
  schema: schema,
);
```

---

## Next Steps

| Topic | File |
|-------|------|
| Full API reference | [api_reference.md](api_reference.md) |
| Architecture overview | [architecture.md](architecture.md) |
| Configuration options | [configuration.md](configuration.md) |
| Detectors & rules | [detectors.md](detectors.md) |
| Alerts & webhooks | [alerts.md](alerts.md) |
| Report generation | [reporting.md](reporting.md) |
| Database adapters | [integrations.md](integrations.md) |
| Schema introspection | [schema_introspection.md](schema_introspection.md) |
| Complete examples | [examples.md](examples.md) |
