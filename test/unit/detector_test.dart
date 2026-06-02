import 'package:test/test.dart';
import '../../lib/src/analyzer/pattern_detector.dart';
import '../../lib/src/analyzer/query_parser.dart';
import '../../lib/src/models/analyzed_query.dart';
import '../../lib/src/utils/config.dart';
import '../fixtures/sample_queries.dart';
import '../fixtures/test_schemas.dart';

void main() {
  late QueryParser parser;
  late PatternDetector detector;

  setUp(() {
    parser = QueryParser();
    detector = PatternDetector(
      schema: TestSchemas.ecommerce,
      config: const QueryAnalyzerConfig(),
    );
  });

  // ── Full table scan ───────────────────────────────────────────────────────

  group('FullTableScanDetector', () {
    test('flags SELECT without WHERE', () {
      final parsed = parser.parse(SampleQueries.fullTableScan);
      final result = detector.detect(parsed, SampleQueries.fullTableScan);

      expect(result.hasIssues, isTrue);
      expect(
        result.issues.any((i) => i.type == IssueType.fullTableScan),
        isTrue,
      );
    });

    test('does not flag SELECT with WHERE on indexed column', () {
      final sql =
          'SELECT id, email FROM users WHERE id = ?';
      final parsed = parser.parse(sql);
      final result = detector.detect(parsed, sql);

      expect(
        result.issues.where((i) => i.type == IssueType.fullTableScan),
        isEmpty,
      );
    });
  });

  // ── Missing index ─────────────────────────────────────────────────────────

  group('MissingIndexDetector', () {
    test('flags WHERE on un-indexed column', () {
      // orders.user_id has no index in the test schema
      final sql =
          'SELECT * FROM orders WHERE user_id = ?';
      final parsed = parser.parse(sql);
      final result = detector.detect(parsed, sql);

      expect(
        result.issues.any((i) =>
            i.type == IssueType.missingIndex &&
            i.affectedElement.contains('user_id')),
        isTrue,
      );
    });

    test('does not flag WHERE on indexed column', () {
      final sql = 'SELECT * FROM users WHERE email = ?';
      final parsed = parser.parse(sql);
      final result = detector.detect(parsed, sql);

      expect(
        result.issues.where((i) =>
            i.type == IssueType.missingIndex &&
            i.affectedElement.contains('email')),
        isEmpty,
      );
    });
  });

  // ── N+1 detection ─────────────────────────────────────────────────────────

  group('NPlusOneDetector', () {
    late PatternDetector freshDetector;

    setUp(() {
      freshDetector = PatternDetector(
        schema: TestSchemas.empty,
        config: QueryAnalyzerConfig.custom(
          nPlusOneWindowMs: 60000,
          nPlusOneMinCount: 3,
        ),
      );
    });

    test('flags after minCount repetitions', () {
      const sql = 'SELECT * FROM comments WHERE post_id = ?';
      final parsed = parser.parse(sql);

      // Observe 3 times
      for (var i = 0; i < 3; i++) {
        freshDetector.detect(parsed, sql);
      }
      final result = freshDetector.detect(parsed, sql);

      expect(
        result.issues.any((i) => i.type == IssueType.nPlusOne),
        isTrue,
      );
    });

    test('does not flag below minCount', () {
      const sql = 'SELECT * FROM products WHERE id = ?';
      final parsed = parser.parse(sql);

      // Observe only twice
      for (var i = 0; i < 2; i++) {
        freshDetector.detect(parsed, sql);
      }

      expect(
        freshDetector
            .detect(parsed, sql)
            .issues
            .where((i) => i.type == IssueType.nPlusOne),
        isEmpty,
      );
    });
  });

  // ── Large result ──────────────────────────────────────────────────────────

  group('LargeResultDetector', () {
    test('flags unbounded SELECT without LIMIT', () {
      final parsed = parser.parse(SampleQueries.fullTableScan);
      final result = detector.detect(
        parsed,
        SampleQueries.fullTableScan,
        actualRowCount: 100000,
      );

      expect(
        result.issues.any((i) => i.type == IssueType.largeResult),
        isTrue,
      );
    });

    test('does not flag paginated query', () {
      final parsed = parser.parse(SampleQueries.paginatedSelect);
      final result = detector.detect(
        parsed,
        SampleQueries.paginatedSelect,
        actualRowCount: 20,
      );

      expect(
        result.issues.where((i) => i.type == IssueType.largeResult),
        isEmpty,
      );
    });
  });

  // ── Sub-query ─────────────────────────────────────────────────────────────

  group('SubqueryDetector', () {
    test('flags correlated sub-query', () {
      final parsed = parser.parse(SampleQueries.correlatedSubquery);
      final result =
          detector.detect(parsed, SampleQueries.correlatedSubquery);

      expect(
        result.issues.any((i) => i.type == IssueType.subqueryIssue),
        isTrue,
      );
    });

    test('flags deeply nested sub-query', () {
      final parsed = parser.parse(SampleQueries.deepSubquery);
      final result = detector.detect(parsed, SampleQueries.deepSubquery);

      expect(
        result.issues.any((i) => i.type == IssueType.subqueryIssue),
        isTrue,
      );
    });
  });

  // ── Severity score ────────────────────────────────────────────────────────

  group('Severity scoring', () {
    test('critical issues raise severityScore', () {
      final parsed = parser.parse(SampleQueries.fullTableScan);
      final result = detector.detect(parsed, SampleQueries.fullTableScan);

      expect(result.severityScore, greaterThan(0));
    });

    test('clean query has zero severityScore', () {
      final sql = 'SELECT id FROM users WHERE id = ?';
      final parsed = parser.parse(sql);
      final result = detector.detect(parsed, sql);

      // id is indexed, WHERE is present — should have no issues from scan/index detectors
      final score = result.issues
          .where((i) =>
              i.type == IssueType.fullTableScan ||
              i.type == IssueType.missingIndex)
          .fold(0, (s, i) => s + i.severity.value);
      expect(score, 0);
    });
  });
}
