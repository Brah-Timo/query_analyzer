# Examples

Complete, runnable examples demonstrating the most common `query_analyzer`
use cases.  All examples assume the following import:

```dart
import 'package:query_analyzer/query_analyzer.dart';
```

See also the `example/` directory in the package root.

---

## 1. Minimal Setup

```dart
void main() async {
  // Create analyzer (schema-less mode)
  final core = QueryAnalyzerFacade.create(
    config: QueryAnalyzerConfig.custom(slowQueryThresholdMs: 200),
    onSlowQuery: (sql, ms, suggestions) {
      print('⚠️  Slow query (${ms}ms): $sql');
      for (final s in suggestions) {
        print('   → ${s.title} (~${s.estimatedImprovementPercent}% improvement)');
      }
    },
  );

  // Simulate a slow query
  await core.analyzeQuery(
    'SELECT * FROM orders WHERE status = ?',
    executionTimeMs: 450,
  );

  await core.dispose();
}
```

---

## 2. DatabaseWrapper Integration

```dart
// 1. Implement DatabaseConnection for your driver
class FakeDb implements DatabaseConnection {
  @override
  Future<List<Map<String, dynamic>>> query(String sql,
      {List? arguments, Map<String, dynamic>? namedArguments}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [{'id': 1, 'name': 'Alice'}];
  }

  @override
  Future<int> execute(String sql,
      {List? arguments, Map<String, dynamic>? namedArguments}) async => 1;

  @override
  Future<void> close() async {}
}

void main() async {
  final core = QueryAnalyzerFacade.create();
  final db = DatabaseWrapper(connection: FakeDb(), analyzer: core);

  db.onSlowQuery = (sql, ms, _) =>
      print('SLOW: ${ms}ms — $sql');

  // All queries measured automatically
  final rows = await db.query('SELECT id, name FROM users WHERE id = ?',
      arguments: [1]);
  print(rows);

  await core.dispose();
}
```

---

## 3. Schema-Aware Analysis

```dart
void main() async {
  final schema = DatabaseSchema(
    engineName: 'postgresql',
    tables: [
      TableSchema(
        name: 'orders',
        columns: [
          ColumnSchema(name: 'id',      dataType: 'INTEGER', isPrimaryKey: true),
          ColumnSchema(name: 'user_id', dataType: 'INTEGER', hasIndex: false), // no index!
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

  final result = await core.analyzeQuery(
    'SELECT id, total FROM orders WHERE user_id = ?',
    executionTimeMs: 800,
  );

  print('Impact score: ${result.impactScore}');
  for (final issue in result.detectionResult.issues) {
    print('Issue [${issue.severity.label}]: ${issue.description}');
  }
  for (final suggestion in result.suggestions) {
    print('Fix: ${suggestion.title}');
    if (suggestion.sqlStatement != null) {
      print('  SQL: ${suggestion.sqlStatement}');
    }
  }

  await core.dispose();
}
```

---

## 4. N+1 Detection

```dart
void main() async {
  final core = QueryAnalyzerCore(
    config: QueryAnalyzerConfig.custom(
      nPlusOneWindowMs: 2000,
      nPlusOneMinCount: 3,
    ),
    schema: DatabaseSchema.empty('sqlite'),
  );

  // Simulate a loop fetching orders per user
  final userIds = [1, 2, 3, 4, 5];
  for (final id in userIds) {
    final result = await core.analyzeQuery(
      'SELECT id, total FROM orders WHERE user_id = $id',
      executionTimeMs: 12,
    );

    if (result.detectionResult.hasIssues) {
      print('N+1 detected after $id iterations!');
      print('Suggestion: ${result.suggestions.first.title}');
      break;
    }
  }

  await core.dispose();
}
```

---

## 5. Real-Time Stream Monitoring

```dart
void main() async {
  final core = QueryAnalyzerFacade.create(
    config: QueryAnalyzerConfig.custom(slowQueryThresholdMs: 300),
  );

  // Subscribe to all queries
  core.queryStream.listen((q) {
    final bar = '█' * (q.impactScore ~/ 10);
    print('[${q.executionTimeMs.toString().padLeft(5)}ms] $bar ${q.impactScore}/100 '
        '— ${q.parsed.tables.join(", ")}');
  });

  // Subscribe to slow queries only
  core.slowQueryStream.listen((q) {
    print('🔴 SLOW: ${q.originalQuery.substring(0, 50)}…');
  });

  // Simulate queries
  for (var i = 0; i < 20; i++) {
    await core.analyzeQuery(
      i % 5 == 0
          ? 'SELECT * FROM audit_log'
          : 'SELECT id FROM users WHERE id = ?',
      executionTimeMs: i % 5 == 0 ? 1500 : 10,
    );
  }

  await core.dispose();
}
```

---

## 6. Alert Channels

```dart
void main() async {
  QaLogger.enableConsoleOutput();

  final core = QueryAnalyzerFacade.create();

  core.addListener(
    AlertManager(
      channels: [
        ConsoleAlertChannel(),
        LoggingAlertChannel(),
        // SlackAlertChannel(webhookUrl: '…'),
      ],
      thresholds: const ThresholdConfig(
        slowQueryMs: 500,
        alertCooldown: Duration(seconds: 10),
      ),
    ),
  );

  await core.analyzeQuery(
    'SELECT * FROM orders',   // no WHERE, no LIMIT
    executionTimeMs: 2300,
  );

  await core.dispose();
}
```

---

## 7. Generating & Exporting Reports

```dart
import 'dart:io';

void main() async {
  final core = QueryAnalyzerFacade.create();

  // Seed with simulated queries
  final queries = [
    ('SELECT * FROM orders', 4500),
    ('SELECT id FROM users WHERE email = ?', 120),
    ('SELECT COUNT(*) FROM events GROUP BY date', 8900),
    ('SELECT * FROM products', 3200),
    ('INSERT INTO logs (msg) VALUES (?)', 5),
  ];

  for (final (sql, ms) in queries) {
    await core.analyzeQuery(sql, executionTimeMs: ms);
  }

  // Generate report
  final report = QueryAnalyzerFacade.generateReport(
    core,
    timeRange: const Duration(hours: 1),
  );

  // Print plain-text summary
  print(report.summary);

  // Export to HTML
  File('report.html').writeAsStringSync(ReportExporter.toHtml(report));

  // Export to CSV
  File('slow_queries.csv').writeAsStringSync(ReportExporter.toCsv(report));

  // Export to Markdown
  File('report.md').writeAsStringSync(ReportExporter.toMarkdown(report));

  // Export to JSON
  File('report.json').writeAsStringSync(ReportExporter.toJson(report));

  print('Reports written to ./report.{html,csv,md,json}');

  await core.dispose();
}
```

---

## 8. QueryWrapper for Ad-Hoc Measurement

```dart
void main() async {
  final core = QueryAnalyzerFacade.create();

  // When you cannot wrap the entire connection
  final result = await QueryWrapper.measure(
    sql: 'SELECT COUNT(*) FROM events WHERE type = ?',
    analyzer: core,
    execute: () async {
      // call your db directly
      await Future.delayed(const Duration(milliseconds: 120));
      return {'count': 42};
    },
    parameters: {'type': 'click'},
  );

  print('Result: $result');

  await core.dispose();
}
```

---

## 9. ConnectionPoolWrapper

```dart
void main() async {
  final core = QueryAnalyzerFacade.create();

  // Create a pool of connections
  final pool = ConnectionPoolWrapper(
    connections: [
      FakeDb(),  // replica 1
      FakeDb(),  // replica 2
      FakeDb(),  // replica 3
    ],
    analyzer: core,
  );

  // Round-robin distribution
  for (var i = 0; i < 9; i++) {
    await pool.query('SELECT id FROM products LIMIT 100');
  }

  print('Pool size: ${pool.size}');
  await pool.closeAll();
  await core.dispose();
}
```

---

## 10. Custom QueryListener

```dart
class MetricsPipeline implements QueryListener {
  final List<Map<String, dynamic>> _events = [];

  @override
  Future<void> onQueryAnalyzed(AnalyzedQuery query) async {
    _events.add({
      'ts': query.executedAt.millisecondsSinceEpoch,
      'ms': query.executionTimeMs,
      'impact': query.impactScore,
      'slow': query.isSlowQuery,
      'issues': query.detectionResult.issues.length,
    });
  }

  void flush() {
    // send _events to your telemetry backend
    print('Flushing ${_events.length} events to telemetry');
    _events.clear();
  }
}

void main() async {
  final core = QueryAnalyzerFacade.create();
  final pipeline = MetricsPipeline();
  core.addListener(pipeline);

  // Run queries …
  await core.analyzeQuery('SELECT 1', executionTimeMs: 5);
  await core.analyzeQuery('SELECT * FROM big_table', executionTimeMs: 3000);

  pipeline.flush();
  await core.dispose();
}
```

---

## Running the Bundled Examples

```bash
cd query_analyzer

# Basic usage
dart example/basic_usage.dart

# Advanced features
dart example/advanced_features.dart

# Custom alerts
dart example/custom_alerts.dart

# Report generation
dart example/report_generation.dart

# Web server integration
dart example/web_server_integration.dart
```
