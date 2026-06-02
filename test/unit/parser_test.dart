import 'package:test/test.dart';
import '../../lib/src/analyzer/query_parser.dart';
import '../../lib/src/models/analyzed_query.dart';
import '../fixtures/sample_queries.dart';

void main() {
  late QueryParser parser;

  setUp(() => parser = QueryParser());

  // ── Query type detection ──────────────────────────────────────────────────

  group('QueryType detection', () {
    test('detects SELECT', () {
      final p = parser.parse(SampleQueries.simpleSelect);
      expect(p.type, QueryType.select);
    });

    test('detects INSERT', () {
      final p = parser.parse(SampleQueries.insertUser);
      expect(p.type, QueryType.insert);
    });

    test('detects UPDATE', () {
      final p = parser.parse(SampleQueries.updateStatus);
      expect(p.type, QueryType.update);
    });

    test('detects DDL (CREATE INDEX)', () {
      final p = parser.parse(SampleQueries.ddlStatement);
      expect(p.type, QueryType.ddl);
    });
  });

  // ── Table extraction ──────────────────────────────────────────────────────

  group('Table extraction', () {
    test('extracts single table from SELECT', () {
      final p = parser.parse(SampleQueries.simpleSelect);
      expect(p.tables, contains('users'));
    });

    test('extracts multiple tables from JOIN query', () {
      final p = parser.parse(SampleQueries.joinWithoutIndex);
      expect(p.tables, containsAll(['users', 'orders']));
    });

    test('extracts table from full scan query', () {
      final p = parser.parse(SampleQueries.fullTableScan);
      expect(p.tables, contains('users'));
    });
  });

  // ── WHERE clause detection ────────────────────────────────────────────────

  group('WHERE clause detection', () {
    test('detects WHERE clause', () {
      final p = parser.parse(SampleQueries.simpleSelect);
      expect(p.whereClauses, isNotEmpty);
      expect(p.whereClauses.first.column, 'id');
    });

    test('lacksWhereClause is true for full scan', () {
      final p = parser.parse(SampleQueries.fullTableScan);
      expect(p.lacksWhereClause, isTrue);
    });

    test('lacksWhereClause is false for constrained query', () {
      final p = parser.parse(SampleQueries.simpleSelect);
      expect(p.lacksWhereClause, isFalse);
    });
  });

  // ── LIMIT / OFFSET ────────────────────────────────────────────────────────

  group('LIMIT / OFFSET', () {
    test('extracts LIMIT', () {
      final p = parser.parse(SampleQueries.paginatedSelect);
      expect(p.limit, 20);
    });

    test('extracts OFFSET', () {
      final p = parser.parse(SampleQueries.paginatedSelect);
      expect(p.offset, 0);
    });

    test('limit is null when absent', () {
      final p = parser.parse(SampleQueries.fullTableScan);
      expect(p.limit, isNull);
    });
  });

  // ── Sub-query detection ───────────────────────────────────────────────────

  group('Sub-query detection', () {
    test('detects sub-query in correlated query', () {
      final p = parser.parse(SampleQueries.correlatedSubquery);
      expect(p.hasSubquery, isTrue);
    });

    test('reports depth for deep sub-query', () {
      final p = parser.parse(SampleQueries.deepSubquery);
      expect(p.subqueryDepth, greaterThanOrEqualTo(2));
    });

    test('no sub-query for simple SELECT', () {
      final p = parser.parse(SampleQueries.simpleSelect);
      expect(p.hasSubquery, isFalse);
    });
  });

  // ── Aggregate detection ───────────────────────────────────────────────────

  group('Aggregate detection', () {
    test('detects COUNT, SUM, AVG', () {
      final p = parser.parse(SampleQueries.expensiveAggregate);
      expect(p.hasAggregates, isTrue);
    });

    test('no aggregate for simple SELECT', () {
      final p = parser.parse(SampleQueries.simpleSelect);
      expect(p.hasAggregates, isFalse);
    });
  });

  // ── SELECT * ──────────────────────────────────────────────────────────────

  group('SELECT *', () {
    test('detects SELECT *', () {
      final p = parser.parse(SampleQueries.fullTableScan);
      expect(p.selectsStar, isTrue);
    });

    test('does not flag explicit column list', () {
      final p = parser.parse(SampleQueries.simpleSelect);
      expect(p.selectsStar, isFalse);
    });
  });

  // ── Error handling ────────────────────────────────────────────────────────

  group('Error handling', () {
    test('throws ArgumentError on blank SQL', () {
      expect(
        () => parser.parse(SampleQueries.emptyQuery),
        throwsArgumentError,
      );
    });
  });

  // ── Normalization ─────────────────────────────────────────────────────────

  group('Normalization', () {
    test('normalized query replaces literals with ?', () {
      final p = parser.parse("SELECT * FROM users WHERE email = 'alice@test.com'");
      expect(p.normalizedQuery, contains("'?'"));
      expect(p.normalizedQuery, isNot(contains('alice@test.com')));
    });
  });
}
