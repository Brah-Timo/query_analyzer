// ignore_for_file: avoid_print

/// Report Generation Example
///
/// Demonstrates generating JSON, CSV, HTML and Markdown reports.
library;

import 'dart:async';
import 'package:query_analyzer/query_analyzer.dart';

class DemoConn implements DatabaseConnection {
  final int ms;
  DemoConn(this.ms);
  @override
  String? get tag => 'demo';
  @override
  Future<List<Map<String, dynamic>>> query(String sql,
      {List<dynamic>? arguments, Map<String, dynamic>? namedArguments}) async {
    await Future.delayed(Duration(milliseconds: ms));
    return List.generate(ms > 500 ? 50000 : 10, (i) => {'id': i});
  }
  @override
  Future<int> execute(String sql,
      {List<dynamic>? arguments, Map<String, dynamic>? namedArguments}) async =>
      1;
  @override
  Future<void> close() async {}
}

Future<void> main() async {
  final core = QueryAnalyzerFacade.create(
    config: QueryAnalyzerConfig.custom(slowQueryThresholdMs: 300),
    schema: DatabaseSchema.empty('demo'),
  );

  // Simulate a mix of fast and slow queries
  final fastDb = DatabaseWrapper(connection: DemoConn(50), analyzer: core);
  final slowDb = DatabaseWrapper(connection: DemoConn(800), analyzer: core);

  // Fast queries
  for (var i = 0; i < 20; i++) {
    await fastDb.query('SELECT id FROM users WHERE id = ?', arguments: [i]);
  }

  // Slow queries
  await slowDb.query('SELECT * FROM orders');
  await slowDb.query('SELECT * FROM products');
  await slowDb.query('SELECT * FROM audit_logs WHERE created_at > ?',
      arguments: ['2024-01-01']);

  // Generate report
  final report = QueryAnalyzerFacade.generateReport(core,
      timeRange: const Duration(hours: 1));

  print('=== Plain-text Summary ===');
  print(report.summary);

  print('\n=== JSON (truncated to 500 chars) ===');
  final json = ReportExporter.toJson(report);
  print(json.substring(0, json.length.clamp(0, 500)));
  print('...');

  print('\n=== CSV (first 400 chars) ===');
  final csv = ReportExporter.toCsv(report);
  print(csv.substring(0, csv.length.clamp(0, 400)));

  print('\n=== HTML generated (length: ${ReportExporter.toHtml(report).length} chars) ===');
  print('=== Markdown generated (length: ${ReportExporter.toMarkdown(report).length} chars) ===');

  print('\n=== Top Suggestions ===');
  for (final s in report.topSuggestions) {
    print('  • [${s.priority.name}] ${s.title}');
  }

  await core.dispose();
  print('\nDone.');
}
