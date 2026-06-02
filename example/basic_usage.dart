// ignore_for_file: avoid_print

/// Basic Usage Example
///
/// Demonstrates the simplest integration of Query Analyzer:
/// wrap a database connection and receive slow-query alerts.
library;

import 'package:query_analyzer/query_analyzer.dart';

// ---------------------------------------------------------------------------
// Minimal concrete DatabaseConnection for demonstration
// (In a real app, this would be your postgres / mysql / sqlite adapter)
// ---------------------------------------------------------------------------
class DemoConnection implements DatabaseConnection {
  @override
  String get tag => 'demo';

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  }) async {
    // Simulate variable latency
    final ms = sql.contains('users') ? 1500 : 50;
    await Future.delayed(Duration(milliseconds: ms));
    return [
      {'id': 1, 'email': 'alice@example.com', 'name': 'Alice'},
      {'id': 2, 'email': 'bob@example.com', 'name': 'Bob'},
    ];
  }

  @override
  Future<int> execute(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  }) async {
    await Future.delayed(const Duration(milliseconds: 30));
    return 1;
  }

  @override
  Future<void> close() async {}
}

// ---------------------------------------------------------------------------

Future<void> main() async {
  QaLogger.enableConsoleOutput();

  // 1. Create the analyzer core
  final core = QueryAnalyzerFacade.create(
    config: QueryAnalyzerConfig.custom(
      slowQueryThresholdMs: 500, // flag anything > 500 ms
      logAllQueries: false,
      maskSensitiveValues: true,
      detectNPlusOne: true,
    ),
    schema: DatabaseSchema.empty('demo'),
    onSlowQuery: (sql, ms, suggestions) {
      print('\n🚨  SLOW QUERY DETECTED!');
      print('  Duration : ${ms}ms');
      print('  SQL      : $sql');
      print('  Fixes    :');
      for (final s in suggestions) {
        print('    → [${s.priority.name.toUpperCase()}] ${s.title}');
        if (s.sqlStatement != null) {
          print('      SQL: ${s.sqlStatement}');
        }
      }
    },
  );

  // 2. Wrap the connection
  final db = DatabaseWrapper(
    connection: DemoConnection(),
    analyzer: core,
  );

  print('=== Running sample queries ===\n');

  // Fast query
  final users = await db.query(
    'SELECT id, name FROM products WHERE id = ?',
    arguments: [42],
  );
  print('Products fetched: ${users.length}');

  // Slow query (simulated ~1500ms)
  await db.query('SELECT * FROM users');

  // Write query
  await db.execute(
    'UPDATE users SET last_login = ? WHERE id = ?',
    arguments: [DateTime.now().toIso8601String(), 1],
  );

  // 3. Print summary report
  print('\n=== Performance Report ===');
  final report = QueryAnalyzerFacade.generateReport(core);
  print(report.summary);

  // 4. Print recommendations
  if (report.recommendations.isNotEmpty) {
    print('\n📋 Recommendations:');
    for (final rec in report.recommendations) {
      print('  • $rec');
    }
  }

  await core.dispose();
  print('\nDone.');
}
