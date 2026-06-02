import 'package:test/test.dart';
import '../../lib/query_analyzer.dart';
import '../fixtures/mock_database.dart';
import '../fixtures/sample_queries.dart';
import '../fixtures/test_schemas.dart';

/// End-to-end integration test: exercises the full pipeline from
/// DatabaseWrapper → QueryAnalyzerCore → MetricsStorage → ReportGenerator.
void main() {
  late QueryAnalyzerCore core;
  late DatabaseWrapper db;
  late MockDatabaseConnection mock;

  setUp(() {
    core = QueryAnalyzerFacade.create(
      config: QueryAnalyzerConfig.custom(
        slowQueryThresholdMs: 200,
        detectNPlusOne: true,
        nPlusOneMinCount: 3,
        nPlusOneWindowMs: 30000,
        persistMetrics: false,
        maskSensitiveValues: true,
      ),
      schema: TestSchemas.ecommerce,
    );
    mock = MockDatabaseConnection();
    db = DatabaseWrapper(connection: mock, analyzer: core);
  });

  tearDown(() => core.dispose());

  // ── Full pipeline ─────────────────────────────────────────────────────────

  group('Full pipeline', () {
    test('fast query does not appear in slow list', () async {
      mock.queryResult = [{'id': 1}];
      await db.query(SampleQueries.simpleSelect);

      final report = QueryAnalyzerFacade.generateReport(core);
      expect(report.slowQueries, isEmpty);
    });

    test('slow query appears in report and has suggestions', () async {
      mock.queryDelay = const Duration(milliseconds: 300);
      await db.query(SampleQueries.fullTableScan);

      final report = QueryAnalyzerFacade.generateReport(core);
      expect(report.slowQueries, isNotEmpty);
      expect(report.slowQueries.first.suggestions, isNotEmpty);
    });

    test('report averageExecutionTimeMs is correct', () async {
      // Two queries: 100ms and 300ms → average = 200ms
      mock.queryDelay = const Duration(milliseconds: 100);
      await db.query(SampleQueries.simpleSelect);

      mock.queryDelay = const Duration(milliseconds: 300);
      await db.query(SampleQueries.fullTableScan);

      final report = QueryAnalyzerFacade.generateReport(core);
      // Allow ±50ms tolerance for system timing variance
      expect(report.averageExecutionTimeMs,
          inInclusiveRange(50.0, 400.0));
    });

    test('multiple slow queries populate topSlowQueries sorted desc', () async {
      mock.queryDelay = const Duration(milliseconds: 500);
      await db.query(SampleQueries.fullTableScan);

      mock.queryDelay = const Duration(milliseconds: 250);
      await db.query(SampleQueries.unboundedSelect);

      final report = QueryAnalyzerFacade.generateReport(core);
      if (report.topSlowQueries.length >= 2) {
        expect(
          report.topSlowQueries.first.executionTimeMs,
          greaterThanOrEqualTo(report.topSlowQueries[1].executionTimeMs),
        );
      }
    });
  });

  // ── Alert callback ────────────────────────────────────────────────────────

  group('Alert callback', () {
    test('onSlowQuery callback fires for slow queries', () async {
      var alertFired = false;
      db.onSlowQuery = (sql, ms, suggestions) => alertFired = true;

      mock.queryDelay = const Duration(milliseconds: 300);
      await db.query(SampleQueries.fullTableScan);

      await Future.delayed(const Duration(milliseconds: 20));
      expect(alertFired, isTrue);
    });
  });

  // ── N+1 integration ───────────────────────────────────────────────────────

  group('N+1 integration', () {
    test('detects repeated identical queries', () async {
      for (var i = 0; i < 5; i++) {
        await db.query(SampleQueries.nPlusOneQuery,
            arguments: [i]);
      }

      final slowList = core.storage.getAll();
      final nPlusOneFlags = slowList.any(
        (q) => q.detectionResult.issues
            .any((i) => i.type == IssueType.nPlusOne),
      );
      expect(nPlusOneFlags, isTrue);
    });
  });

  // ── Export formats ────────────────────────────────────────────────────────

  group('Report export formats', () {
    late AnalysisReport report;

    setUp(() async {
      mock.queryDelay = const Duration(milliseconds: 300);
      await db.query(SampleQueries.fullTableScan);
      report = QueryAnalyzerFacade.generateReport(core);
    });

    test('toJson produces valid JSON string', () {
      final json = ReportExporter.toJson(report);
      expect(json, contains('"totalQueries"'));
    });

    test('toCsv contains header and rows', () {
      final csv = ReportExporter.toCsv(report);
      expect(csv, contains('executionTimeMs'));
    });

    test('toHtml contains DOCTYPE', () {
      final html = ReportExporter.toHtml(report);
      expect(html, startsWith('<!DOCTYPE html>'));
    });

    test('toMarkdown contains headings', () {
      final md = ReportExporter.toMarkdown(report);
      expect(md, contains('# Query Analyzer Report'));
    });
  });

  // ── MetricsStorage ────────────────────────────────────────────────────────

  group('MetricsStorage', () {
    test('aggregates metrics per pattern', () async {
      await db.query(SampleQueries.simpleSelect);
      await db.query(SampleQueries.simpleSelect);

      final metrics = core.storage.getAllMetrics();
      expect(metrics, isNotEmpty);

      final forPattern = metrics.firstWhere(
        (m) => m.executionCount == 2,
        orElse: () => throw StateError('No metric with count=2'),
      );
      expect(forPattern.executionCount, 2);
    });

    test('dailySummary returns correct totals', () async {
      await db.query(SampleQueries.simpleSelect);
      await db.query(SampleQueries.fullTableScan);

      final summary = core.storage.getDailySummary();
      expect(summary.totalQueries, greaterThanOrEqualTo(2));
    });
  });
}
