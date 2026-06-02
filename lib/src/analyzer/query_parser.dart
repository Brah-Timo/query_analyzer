import '../models/analyzed_query.dart';
import '../utils/parser_utils.dart';

/// Parses a raw SQL string into a structured [ParsedQuery].
///
/// The parser is intentionally lightweight — it relies on regex-based
/// heuristics rather than a full grammar, which keeps it dependency-free
/// and fast enough to run synchronously on every query.
class QueryParser {
  /// Parses [sql] and returns a [ParsedQuery] describing its structure.
  ///
  /// Throws [ArgumentError] if [sql] is blank.
  ParsedQuery parse(String sql) {
    if (sql.trim().isEmpty) {
      throw ArgumentError.value(sql, 'sql', 'SQL string must not be blank');
    }

    final normalized = ParserUtils.normalize(sql);
    final upper = sql.toUpperCase().trim();

    return ParsedQuery(
      type: _detectType(upper),
      tables: ParserUtils.extractTableNames(sql),
      selectedColumns: _extractSelectedColumns(sql, upper),
      whereClauses: _extractWhereClauses(sql),
      joins: _extractJoins(sql),
      hasGroupBy: ParserUtils.containsKeyword(sql, 'GROUP BY'),
      hasOrderBy: ParserUtils.containsKeyword(sql, 'ORDER BY'),
      hasSubquery: _hasSubquery(sql),
      subqueryDepth: ParserUtils.subqueryDepth(sql),
      hasDistinct: ParserUtils.containsKeyword(sql, 'DISTINCT'),
      hasAggregates: _hasAggregates(upper),
      limit: ParserUtils.extractLimit(sql),
      offset: ParserUtils.extractOffset(sql),
      normalizedQuery: normalized,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  QueryType _detectType(String upper) {
    if (upper.startsWith('SELECT')) return QueryType.select;
    if (upper.startsWith('INSERT')) return QueryType.insert;
    if (upper.startsWith('UPDATE')) return QueryType.update;
    if (upper.startsWith('DELETE')) return QueryType.delete;
    if (RegExp(r'^(CREATE|ALTER|DROP|TRUNCATE|RENAME)').hasMatch(upper)) {
      return QueryType.ddl;
    }
    return QueryType.other;
  }

  List<String> _extractSelectedColumns(String sql, String upper) {
    if (!upper.startsWith('SELECT')) return const [];

    // Find content between SELECT and FROM
    final fromIdx = upper.indexOf('\nFROM ').let((i) => i == -1
        ? upper.indexOf(' FROM ')
        : i);
    if (fromIdx == -1) return const ['*'];

    final selectPart = sql.substring(6, fromIdx).trim(); // skip "SELECT"

    if (selectPart == '*' || selectPart.toUpperCase().startsWith('* ')) {
      return const ['*'];
    }

    return selectPart
        .split(',')
        .map((col) {
          // Strip table prefix and alias
          final stripped = col
              .trim()
              .replaceAll(RegExp(r'\bAS\b.*$', caseSensitive: false), '')
              .trim();
          final dotIdx = stripped.lastIndexOf('.');
          return dotIdx == -1
              ? stripped.trim()
              : stripped.substring(dotIdx + 1).trim();
        })
        .where((c) => c.isNotEmpty)
        .toList();
  }

  List<WhereClause> _extractWhereClauses(String sql) {
    final whereRe = RegExp(
      r'\bWHERE\b(.*?)(?:\bGROUP\s+BY\b|\bORDER\s+BY\b|\bHAVING\b|\bLIMIT\b|$)',
      caseSensitive: false,
      dotAll: true,
    );
    final match = whereRe.firstMatch(sql);
    if (match == null) return const [];

    final whereText = match.group(1) ?? '';
    final condRe = RegExp(
      r"([a-zA-Z_][a-zA-Z0-9_.]*)\s*(=|<>|!=|>=|<=|>|<|LIKE|NOT\s+LIKE|IN|NOT\s+IN|IS\s+NULL|IS\s+NOT\s+NULL)\s*(\?|:[a-zA-Z_]+|@[a-zA-Z_]+|'[^']*'|\d+)",
      caseSensitive: false,
    );

    final clauses = <WhereClause>[];
    for (final m in condRe.allMatches(whereText)) {
      final col = m.group(1)!.split('.').last;
      final op = m.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      final val = m.group(3) ?? '';
      final isParam =
          val.startsWith('?') || val.startsWith(':') || val.startsWith('@');
      clauses.add(
        WhereClause(column: col, operator: op, isParameterized: isParam),
      );
    }
    return clauses;
  }

  List<JoinClause> _extractJoins(String sql) {
    final joinRe = RegExp(
      r'\b(INNER\s+JOIN|LEFT\s+(?:OUTER\s+)?JOIN|RIGHT\s+(?:OUTER\s+)?JOIN|FULL\s+(?:OUTER\s+)?JOIN|CROSS\s+JOIN|JOIN)\s+'
      r'([a-zA-Z_][a-zA-Z0-9_]*)'
      r'(?:\s+(?:AS\s+)?[a-zA-Z_][a-zA-Z0-9_]*)?'
      r'(?:\s+ON\s+([a-zA-Z_][a-zA-Z0-9_.]*)\s*=\s*([a-zA-Z_][a-zA-Z0-9_.]*))?',
      caseSensitive: false,
    );

    return joinRe.allMatches(sql).map((m) {
      final type = m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      final table = m.group(2)!;
      final left = m.group(3)?.split('.').last;
      final right = m.group(4)?.split('.').last;
      return JoinClause(
        joinType: type.toUpperCase(),
        table: table,
        onLeftColumn: left,
        onRightColumn: right,
      );
    }).toList();
  }

  bool _hasSubquery(String sql) {
    // Look for SELECT inside parentheses
    return RegExp(r'\(\s*SELECT\b', caseSensitive: false).hasMatch(sql);
  }

  bool _hasAggregates(String upper) {
    const aggs = [
      'COUNT(',
      'SUM(',
      'AVG(',
      'MIN(',
      'MAX(',
      'GROUP_CONCAT(',
      'STRING_AGG(',
      'ARRAY_AGG(',
    ];
    return aggs.any(upper.contains);
  }
}

// Tiny extension to avoid re-assigning a local
extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}
