// ignore_for_file: avoid_print

/// Custom Alerts Example
///
/// Demonstrates: AlertManager with Console, Logging, and Webhook channels.
library;

import 'dart:async';
import 'package:query_analyzer/query_analyzer.dart';

class DemoConn implements DatabaseConnection {
  @override
  String? get tag => 'demo';
  @override
  Future<List<Map<String, dynamic>>> query(String sql,
      {List<dynamic>? arguments, Map<String, dynamic>? namedArguments}) async {
    await Future.delayed(const Duration(milliseconds: 1200));
    return [];
  }
  @override
  Future<int> execute(String sql,
      {List<dynamic>? arguments, Map<String, dynamic>? namedArguments}) async {
    return 1;
  }
  @override
  Future<void> close() async {}
}

Future<void> main() async {
  QaLogger.enableConsoleOutput();

  final core = QueryAnalyzerFacade.create(
    config: QueryAnalyzerConfig.custom(
      slowQueryThresholdMs: 500,
    ),
    schema: DatabaseSchema.empty('demo'),
  );

  // ── Build AlertManager with multiple channels ────────────────────────────

  final alertManager = AlertManager(
    channels: [
      // Print to stdout
      ConsoleAlertChannel(),

      // Route to the package logger
      LoggingAlertChannel(),

      // Webhook (disabled — replace with real URL)
      // WebhookAlertChannel(
      //   url: 'https://hooks.example.com/alerts',
      //   headers: {'Authorization': 'Bearer YOUR_TOKEN'},
      //   name: 'ops-webhook',
      // ),
    ],
    thresholds: const ThresholdConfig(
      slowQueryMs: 500,
      alertCooldown: Duration(seconds: 5),
    ),
  );

  core.addListener(alertManager);

  // ── Fire a slow query to trigger the alert pipeline ──────────────────────
  final db = DatabaseWrapper(connection: DemoConn(), analyzer: core);

  print('Running a slow query ...\n');
  await db.query('SELECT * FROM audit_logs');

  await Future.delayed(const Duration(milliseconds: 50));

  print('\nAlert channels: ${alertManager.channelNames}');

  await core.dispose();
  print('Done.');
}
