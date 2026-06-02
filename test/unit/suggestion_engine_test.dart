import 'package:test/test.dart';
import '../../lib/src/analyzer/query_analyzer_core.dart';
import '../../lib/src/models/query_suggestion.dart';
import '../../lib/src/utils/config.dart';
import '../fixtures/sample_queries.dart';
import '../fixtures/test_schemas.dart';

void main() {
  late QueryAnalyzerCore core;

  setUp(() {
    core = QueryAnalyzerCore(
      config: QueryAnalyzerConfig.custom(
        slowQueryThresholdMs: 500,
        detectNPlusOne: true,
      ),
      schema: TestSchemas.ecommerce,
    );
  });

  tearDown(() => core.dispose());

  // ── Suggestion types ──────────────────────────────────────────────────────

  group('SuggestionEngine', () {
    test('produces addIndex suggestion for full-table scan', () async {
      final result = await core.analyzeQuery(
        SampleQueries.fullTableScan,
        executionTimeMs: 1000,
      );
      expect(
        result.suggestions.any((s) => s.type == SuggestionType.addIndex),
        isTrue,
      );
    });

    test('produces addIndex for WHERE on un-indexed column', () async {
      // orders.user_id has no index in test schema
      const sql = 'SELECT id, total FROM orders WHERE user_id = ?';
      final result = await core.analyzeQuery(sql, executionTimeMs: 800);
      expect(
        result.suggestions.any((s) => s.type == SuggestionType.addIndex),
        isTrue,
      );
    });

    test('addIndex suggestion contains CREATE INDEX statement', () async {
      const sql = 'SELECT id, total FROM orders WHERE user_id = ?';
      final result = await core.analyzeQuery(sql, executionTimeMs: 800);
      final indexSuggestion = result.suggestions
          .firstWhere((s) => s.type == SuggestionType.addIndex);
      expect(indexSuggestion.sqlStatement, isNotNull);
      expect(
        indexSuggestion.sqlStatement!.toUpperCase(),
        contains('CREATE INDEX'),
      );
    });

    test('produces addPagination for unbounded query', () async {
      final result = await core.analyzeQuery(
        SampleQueries.unboundedSelect,
        executionTimeMs: 100,
      );
      expect(
        result.suggestions.any((s) => s.type == SuggestionType.addPagination),
        isTrue,
      );
    });

    test('produces rewriteSubquery for correlated sub-query', () async {
      final result = await core.analyzeQuery(
        SampleQueries.correlatedSubquery,
        executionTimeMs: 2000,
      );
      expect(
        result.suggestions
            .any((s) => s.type == SuggestionType.rewriteSubquery),
        isTrue,
      );
    });

    test('suggestions are sorted by priority (critical first)', () async {
      final result = await core.analyzeQuery(
        SampleQueries.correlatedSubquery,
        executionTimeMs: 3000,
      );
      if (result.suggestions.length > 1) {
        final priorities =
            result.suggestions.map((s) => s.priority.index).toList();
        // Should be sorted descending (higher index = higher priority)
        for (var i = 0; i < priorities.length - 1; i++) {
          expect(priorities[i], greaterThanOrEqualTo(priorities[i + 1]));
        }
      }
    });

    test('estimatedImprovementPercent is in [1, 100]', () async {
      final result = await core.analyzeQuery(
        SampleQueries.fullTableScan,
        executionTimeMs: 1000,
      );
      for (final s in result.suggestions) {
        if (s.estimatedImprovementPercent != null) {
          expect(s.estimatedImprovementPercent!, inInclusiveRange(1, 100));
        }
      }
    });
  });

  // ── Generic suggestion ────────────────────────────────────────────────────

  group('QuerySuggestion.generic', () {
    test('creates a valid generic suggestion', () {
      final s = QuerySuggestion.generic('Review this query');
      expect(s.type, SuggestionType.other);
      expect(s.title, isNotEmpty);
      expect(s.description, contains('Review'));
    });
  });

  // ── Factory constructors ──────────────────────────────────────────────────

  group('QuerySuggestion factories', () {
    test('addIndex creates valid suggestion', () {
      final s = QuerySuggestion.addIndex(
        table: 'orders',
        column: 'user_id',
        estimatedImprovementPercent: 80,
      );
      expect(s.type, SuggestionType.addIndex);
      expect(s.sqlStatement, contains('orders'));
      expect(s.sqlStatement, contains('user_id'));
      expect(s.estimatedImprovementPercent, 80);
    });

    test('refactorNPlusOne creates valid suggestion', () {
      final s = QuerySuggestion.refactorNPlusOne(relatedTable: 'comments');
      expect(s.type, SuggestionType.refactorQuery);
      expect(s.priority, SuggestionPriority.critical);
    });
  });
}
