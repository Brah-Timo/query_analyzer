// ignore_for_file: avoid_print

/// Web Server Integration Example
///
/// Shows how to integrate Query Analyzer with a Shelf / Dart HTTP server.
/// Every request handler shares the same DatabaseWrapper; slow queries
/// are sent to an AlertManager.
library;

import 'dart:async';
import 'package:query_analyzer/query_analyzer.dart';

// ── Minimal HTTP-like scaffold (no real Shelf dependency needed) ──────────

typedef Handler = Future<String> Function(Map<String, String> request);

class MockServer {
  final Map<String, Handler> _routes = {};

  void get(String path, Handler handler) => _routes[path] = handler;

  Future<String> handle(String path) async {
    final h = _routes[path];
    if (h == null) return '404 Not Found';
    return h({'path': path});
  }
}

// ── Database connection stub ──────────────────────────────────────────────

class AppDatabase implements DatabaseConnection {
  @override
  String? get tag => 'app-db';

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  }) async {
    // Simulate different latencies per table
    final delay = sql.contains('sessions')
        ? 1500
        : sql.contains('users')
            ? 200
            : 80;
    await Future.delayed(Duration(milliseconds: delay));
    return [
      {'id': 1, 'data': 'sample row'},
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

// ── Application setup ─────────────────────────────────────────────────────

class AppService {
  late DatabaseWrapper db;
  late QueryAnalyzerCore analyzer;
  final MockServer server = MockServer();

  Future<void> initialize() async {
    analyzer = QueryAnalyzerFacade.create(
      config: QueryAnalyzerConfig.custom(
        slowQueryThresholdMs: 500,
        detectNPlusOne: true,
        maskSensitiveValues: true,
        persistMetrics: false,
      ),
      schema: DatabaseSchema.empty('app-db'),
    );

    // Attach alerts
    final alerts = AlertManager(
      channels: [ConsoleAlertChannel(), LoggingAlertChannel()],
      thresholds: const ThresholdConfig(
        slowQueryMs: 500,
        alertCooldown: Duration(seconds: 30),
      ),
    );
    analyzer.addListener(alerts);

    db = DatabaseWrapper(connection: AppDatabase(), analyzer: analyzer);

    _registerRoutes();
    print('AppService initialized.');
  }

  void _registerRoutes() {
    server.get('/users', (req) async {
      final rows = await db.query(
          'SELECT id, email, name FROM users WHERE status = ?',
          arguments: ['active']);
      return '200 OK — ${rows.length} users';
    });

    server.get('/sessions', (req) async {
      // This is intentionally slow (1500ms)
      final rows = await db.query('SELECT * FROM sessions');
      return '200 OK — ${rows.length} sessions';
    });

    server.get('/report', (req) async {
      final report =
          QueryAnalyzerFacade.generateReport(analyzer);
      return report.summary;
    });

    server.get('/health', (req) async {
      final summary = analyzer.storage.getDailySummary();
      return '200 OK — queries: ${summary.totalQueries}, '
          'slow: ${summary.slowQueries.length}';
    });
  }

  Future<void> dispose() async {
    await analyzer.dispose();
  }
}

// ── Main ──────────────────────────────────────────────────────────────────

Future<void> main() async {
  QaLogger.enableConsoleOutput();

  final app = AppService();
  await app.initialize();

  // Simulate incoming HTTP requests
  print('\n--- Simulating 5 requests ---\n');

  for (var i = 0; i < 3; i++) {
    final resp = await app.server.handle('/users');
    print('GET /users → $resp');
  }

  final slowResp = await app.server.handle('/sessions');
  print('GET /sessions → ${slowResp.substring(0, 40)}...');

  print('\n--- Health check ---');
  print(await app.server.handle('/health'));

  print('\n--- Performance Report ---');
  print(await app.server.handle('/report'));

  await app.dispose();
  print('\nServer shut down.');
}
