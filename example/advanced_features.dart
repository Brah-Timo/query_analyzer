// ignore_for_file: avoid_print

/// Advanced Features Example
///
/// Demonstrates: schema-aware analysis, connection pool, custom listeners,
/// metrics inspection, and real-time streaming.
library;

import 'dart:async';
import 'package:query_analyzer/query_analyzer.dart';

// ── Demo connection (reuse from basic_usage) ──────────────────────────────

class DemoConnection implements DatabaseConnection {
  final String _tag;
  final int _latencyMs;

  DemoConnection({String tag = 'primary', int latencyMs = 100})
      : _tag = tag,
        _latencyMs = latencyMs;

  @override
  String get tag => _tag;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  }) async {
    await Future.delayed(Duration(milliseconds: _latencyMs));
    return [
      {'id': 1, 'name': 'Demo Row'},
    ];
  }

  @override
  Future<int> execute(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  }) async {
    await Future.delayed(Duration(milliseconds: _latencyMs));
    return 1;
  }

  @override
  Future<void> close() async {}
}

// ── Custom listener ───────────────────────────────────────────────────────

class MetricsDashboardListener implements QueryListener {
  final List<AnalyzedQuery> _alerts = [];

  @override
  Future<void> onQueryAnalyzed(AnalyzedQuery query) async {
    if (query.isSlowQuery || query.impactScore > 50) {
      _alerts.add(query);
      print('  📊 Dashboard alert #${_alerts.length}: '
          '${query.executionTimeMs}ms, impact=${query.impactScore}');
    }
  }

  List<AnalyzedQuery> get alerts => List.unmodifiable(_alerts);
}

// ── Main ──────────────────────────────────────────────────────────────────

Future<void> main() async {
  QaLogger.enableConsoleOutput();

  // ── 1. Build a rich schema ────────────────────────────────────────────────
  final schema = DatabaseSchema(
    engineName: 'postgresql',
    engineVersion: '16.0',
    loadedAt: DateTime.now(),
    tables: [
      TableSchema(
        name: 'users',
        schema: 'public',
        approximateRowCount: 100000,
        columns: [
          const ColumnSchema(name: 'id', dataType: 'INTEGER', isPrimaryKey: true, hasIndex: true),
          const ColumnSchema(name: 'email', dataType: 'TEXT', hasIndex: true),
          const ColumnSchema(name: 'status', dataType: 'TEXT'),
        ],
        indexes: [
          const IndexSchema(name: 'users_pkey', tableName: 'users', columns: ['id'], isPrimary: true),
          const IndexSchema(name: 'idx_email', tableName: 'users', columns: ['email'], isUnique: true),
        ],
      ),
      TableSchema(
        name: 'orders',
        schema: 'public',
        approximateRowCount: 2000000, // 2M rows
        columns: [
          const ColumnSchema(name: 'id', dataType: 'INTEGER', isPrimaryKey: true, hasIndex: true),
          const ColumnSchema(name: 'user_id', dataType: 'INTEGER'), // no index!
          const ColumnSchema(name: 'total', dataType: 'DECIMAL'),
          const ColumnSchema(name: 'status', dataType: 'TEXT'),
        ],
        indexes: [
          const IndexSchema(name: 'orders_pkey', tableName: 'orders', columns: ['id'], isPrimary: true),
        ],
      ),
    ],
  );

  // ── 2. Create core with full config ───────────────────────────────────────
  final core = QueryAnalyzerFacade.create(
    config: QueryAnalyzerConfig.custom(
      slowQueryThresholdMs: 200,
      detectNPlusOne: true,
      nPlusOneMinCount: 3,
      nPlusOneWindowMs: 10000,
      largeResultRowThreshold: 5000,
      maskSensitiveValues: true,
    ),
    schema: schema,
  );

  // ── 3. Register custom listener ───────────────────────────────────────────
  final dashboardListener = MetricsDashboardListener();
  core.addListener(dashboardListener);

  // ── 4. Subscribe to real-time stream ─────────────────────────────────────
  final streamSub = core.queryStream.listen((q) {
    if (q.detectionResult.hasIssues) {
      print('  🔍 Stream event: ${q.detectionResult.issues.length} issues '
          'in ${q.executionTimeMs}ms');
    }
  });

  // ── 5. Connection pool ────────────────────────────────────────────────────
  final pool = ConnectionPoolWrapper(
    connections: [
      DemoConnection(tag: 'primary', latencyMs: 300),
      DemoConnection(tag: 'replica-1', latencyMs: 50),
      DemoConnection(tag: 'replica-2', latencyMs: 80),
    ],
    analyzer: core,
  );

  print('=== Pool has ${pool.size} connections ===\n');

  // ── 6. Execute various queries ────────────────────────────────────────────

  print('--- Fast queries ---');
  await pool.query('SELECT id FROM users WHERE id = ?', arguments: [1]);
  await pool.query('SELECT email FROM users WHERE email = ?',
      arguments: ['alice@test.com']);

  print('\n--- Slow / problematic queries ---');
  // Full-table scan on large table
  await pool.query('SELECT * FROM orders');

  // N+1 simulation (same query 4×)
  for (var i = 0; i < 4; i++) {
    await pool.query(
        'SELECT * FROM orders WHERE user_id = ?', arguments: [i]);
  }

  // ── 7. Manual single-query measurement ───────────────────────────────────
  print('\n--- Manual QueryWrapper.measure() ---');
  final result = await QueryWrapper.measure(
    sql: 'SELECT COUNT(*) FROM orders',
    analyzer: core,
    execute: () async {
      await Future.delayed(const Duration(milliseconds: 250));
      return [
        {'count': 1999999},
      ];
    },
  );
  print('Count result: ${result.first}');

  // ── 8. Metrics inspection ─────────────────────────────────────────────────
  await Future.delayed(const Duration(milliseconds: 50));

  print('\n=== Aggregated Metrics ===');
  for (final m in core.storage.getAllMetrics().take(3)) {
    print(
      '  pattern: ${m.queryPattern.substring(0, m.queryPattern.length.clamp(0, 60))}...\n'
      '  count: ${m.executionCount}, avg: ${m.averageExecutionTimeMs.toStringAsFixed(1)}ms',
    );
  }

  // ── 9. Report ─────────────────────────────────────────────────────────────
  print('\n=== Final Report ===');
  final report = QueryAnalyzerFacade.generateReport(core);
  print(report.summary);

  print(
    '\nDashboard listener captured ${dashboardListener.alerts.length} alert(s).',
  );

  await streamSub.cancel();
  await pool.closeAll();
  await core.dispose();
  print('\nDone.');
}
