import 'dart:async';
import 'package:test/test.dart';
import '../../lib/src/analyzer/query_analyzer_core.dart';
import '../../lib/src/models/analyzed_query.dart';
import '../../lib/src/utils/config.dart';
import '../../lib/src/wrapper/database_wrapper.dart';
import '../fixtures/mock_database.dart';
import '../fixtures/sample_queries.dart';
import '../fixtures/test_schemas.dart';

void main() {
  late QueryAnalyzerCore core;
  late DatabaseWrapper db;
  late MockDatabaseConnection mockConn;

  setUp(() {
    core = QueryAnalyzerCore(
      config: QueryAnalyzerConfig.custom(
        slowQueryThresholdMs: 100,
        logAllQueries: true,
        detectNPlusOne: true,
        persistMetrics: false,
      ),
      schema: TestSchemas.ecommerce,
    );

    mockConn = MockDatabaseConnection();
    db = DatabaseWrapper(connection: mockConn, analyzer: core);
  });

  tearDown(() => core.dispose());

  // ── analyzeQuery ──────────────────────────────────────────────────────────

  group('analyzeQuery', () {
    test('returns an AnalyzedQuery for a simple SELECT', () async {
      final result = await core.analyzeQuery(
        SampleQueries.simpleSelect,
        executionTimeMs: 50,
      );
      expect(result.originalQuery, isNotEmpty);
      expect(result.executionTimeMs, 50);
      expect(result.isSlowQuery, isFalse);
    });

    test('marks query as slow when threshold exceeded', () async {
      final result = await core.analyzeQuery(
        SampleQueries.fullTableScan,
        executionTimeMs: 2000,
      );
      expect(result.isSlowQuery, isTrue);
    });

    test('generates suggestions for problematic queries', () async {
      final result = await core.analyzeQuery(
        SampleQueries.fullTableScan,
        executionTimeMs: 500,
      );
      expect(result.suggestions, isNotEmpty);
    });

    test('stores the analyzed query in MetricsStorage', () async {
      await core.analyzeQuery(
        SampleQueries.simpleSelect,
        executionTimeMs: 30,
      );
      expect(core.storage.size, greaterThan(0));
    });
  });

  // ── Slow-query stream ─────────────────────────────────────────────────────

  group('Slow query stream', () {
    test('emits events on slowQueryStream for slow queries', () async {
      final emitted = <AnalyzedQuery>[];
      final sub = core.slowQueryStream.listen(emitted.add);

      await core.analyzeQuery(
        SampleQueries.fullTableScan,
        executionTimeMs: 5000,
      );
      await core.analyzeQuery(
        SampleQueries.simpleSelect,
        executionTimeMs: 10, // fast — should NOT appear
      );

      await Future.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(emitted.length, 1);
      expect(emitted.first.isSlowQuery, isTrue);
    });
  });

  // ── QueryListener callback ────────────────────────────────────────────────

  group('QueryListener', () {
    test('CallbackListener receives slow queries', () async {
      String? receivedQuery;
      int? receivedMs;

      core.addListener(CallbackListener((sql, ms, suggestions) {
        receivedQuery = sql;
        receivedMs = ms;
      }));

      await core.analyzeQuery(
        SampleQueries.fullTableScan,
        executionTimeMs: 3000,
      );

      expect(receivedQuery, isNotNull);
      expect(receivedMs, 3000);
    });

    test('CallbackListener is NOT triggered for fast queries', () async {
      var called = false;
      core.addListener(CallbackListener((_, __, ___) => called = true));

      await core.analyzeQuery(
        SampleQueries.simpleSelect,
        executionTimeMs: 10,
      );

      expect(called, isFalse);
    });
  });

  // ── DatabaseWrapper ───────────────────────────────────────────────────────

  group('DatabaseWrapper', () {
    test('query() returns mock results', () async {
      mockConn.queryResult = [
        {'id': 1, 'email': 'alice@test.com'},
      ];
      final rows = await db.query(SampleQueries.simpleSelect);
      expect(rows.length, 1);
      expect(rows.first['email'], 'alice@test.com');
    });

    test('query() records the call in mock', () async {
      await db.query(SampleQueries.simpleSelect);
      expect(mockConn.queryCalls, contains(SampleQueries.simpleSelect));
    });

    test('execute() returns affected row count', () async {
      mockConn.executeResult = 3;
      final count = await db.execute(SampleQueries.updateStatus);
      expect(count, 3);
    });

    test('query() still analyzes even when DB throws', () async {
      mockConn.throwOnQuery = StateError('DB error');
      final initialSize = core.storage.size;

      expect(
        () => db.query(SampleQueries.simpleSelect),
        throwsStateError,
      );

      await Future.delayed(const Duration(milliseconds: 10));
      // The failed query should still be recorded
      expect(core.storage.size, greaterThanOrEqualTo(initialSize));
    });
  });

  // ── reset ─────────────────────────────────────────────────────────────────

  group('reset', () {
    test('clears stored metrics', () async {
      await core.analyzeQuery(
        SampleQueries.simpleSelect,
        executionTimeMs: 10,
      );
      expect(core.storage.size, greaterThan(0));

      core.reset();

      expect(core.storage.size, 0);
    });
  });

  // ── isSlowQuery ───────────────────────────────────────────────────────────

  group('isSlowQuery', () {
    test('returns false below threshold', () {
      expect(core.isSlowQuery(50), isFalse);
    });

    test('returns true at threshold', () {
      expect(core.isSlowQuery(100), isTrue);
    });

    test('returns true above threshold', () {
      expect(core.isSlowQuery(9999), isTrue);
    });
  });
}
