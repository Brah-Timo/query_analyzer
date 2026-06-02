import '../../constants.dart';

/// Static helper functions used by the SQL parser and detectors.
abstract final class ParserUtils {
  // ── Normalization ─────────────────────────────────────────────────────────

  /// Replaces all string literals with `'?'` and numeric literals with `?`.
  ///
  /// Used to produce a stable *pattern key* for grouping queries.
  static String normalize(String sql) {
    var s = sql.trim();

    // Remove block comments  /* … */
    s = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ');

    // Remove line comments  -- …
    s = s.replaceAll(RegExp(r'--[^\n]*'), ' ');

    // Replace single-quoted string literals
    s = s.replaceAll(RegExp(kStrLiteralPattern), "'?'");

    // Replace numeric literals (but not inside identifiers)
    s = s.replaceAll(RegExp(kNumLiteralPattern), '?');

    // Collapse whitespace
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    return s;
  }

  // ── Keyword extraction ────────────────────────────────────────────────────

  /// Returns `true` if [sql] contains [keyword] as a whole word
  /// (case-insensitive).
  static bool containsKeyword(String sql, String keyword) {
    final pattern = RegExp(
      r'\b' + RegExp.escape(keyword) + r'\b',
      caseSensitive: false,
    );
    return pattern.hasMatch(sql);
  }

  /// Extracts all table names that appear after FROM or JOIN keywords.
  ///
  /// Does *not* handle CTEs or sub-queries — those are resolved by the
  /// full parser.
  static List<String> extractTableNames(String sql) {
    final pattern = RegExp(
      r'\b(?:FROM|JOIN)\s+([`"]?[a-zA-Z_][a-zA-Z0-9_]*[`"]?)',
      caseSensitive: false,
    );
    return pattern
        .allMatches(sql)
        .map((m) => m.group(1)!.replaceAll(RegExp('[`"]'), ''))
        .toSet()
        .toList();
  }

  /// Extracts column names referenced in a WHERE clause.
  ///
  /// Returns an empty list if no WHERE clause is found.
  static List<String> extractWhereColumns(String sql) {
    final whereMatch =
        RegExp(r'\bWHERE\b(.*?)(?:\bGROUP BY\b|\bORDER BY\b|\bHAVING\b|$)',
                caseSensitive: false, dotAll: true)
            .firstMatch(sql);
    if (whereMatch == null) return const [];

    final whereClause = whereMatch.group(1) ?? '';
    final colPattern = RegExp(
      r'([a-zA-Z_][a-zA-Z0-9_.]*)\s*(?:=|<>|!=|>=|<=|>|<|LIKE|IN|IS)',
      caseSensitive: false,
    );
    return colPattern
        .allMatches(whereClause)
        .map((m) => m.group(1)!.split('.').last) // strip table prefix
        .toSet()
        .toList();
  }

  /// Extracts the integer value of a LIMIT clause, or `null` if absent.
  static int? extractLimit(String sql) {
    final m =
        RegExp(r'\bLIMIT\s+(\d+)', caseSensitive: false).firstMatch(sql);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  /// Extracts the integer value of an OFFSET clause, or `null` if absent.
  static int? extractOffset(String sql) {
    final m =
        RegExp(r'\bOFFSET\s+(\d+)', caseSensitive: false).firstMatch(sql);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  /// Counts the nesting depth of sub-queries (SELECT inside parentheses).
  static int subqueryDepth(String sql) {
    var depth = 0;
    var maxDepth = 0;
    var inSelect = false;

    for (var i = 0; i < sql.length; i++) {
      final ch = sql[i];
      if (ch == '(') {
        // Peek ahead for SELECT keyword
        final ahead = sql.substring(i + 1).trimLeft().toUpperCase();
        if (ahead.startsWith('SELECT')) {
          depth++;
          if (depth > maxDepth) maxDepth = depth;
          inSelect = true;
        }
      } else if (ch == ')' && inSelect) {
        depth = (depth - 1).clamp(0, 9999);
        if (depth == 0) inSelect = false;
      }
    }
    return maxDepth;
  }

  // ── PII Masking ───────────────────────────────────────────────────────────

  /// Masks string-literal values and known PII patterns in a query.
  ///
  /// Suitable for safe logging — the masked query is NOT executable.
  static String maskSensitiveValues(String sql) {
    var s = sql;

    // Mask string literals
    s = s.replaceAll(RegExp(kStrLiteralPattern), "'***'");

    // Mask emails
    s = s.replaceAll(RegExp(kEmailPattern, caseSensitive: false), '***@***.***');

    // Mask IPv4
    s = s.replaceAll(RegExp(kIpv4Pattern), '***.***.***.***');

    return s;
  }

  // ── Fingerprinting ────────────────────────────────────────────────────────

  /// Produces a stable 8-char hex fingerprint for a normalized query.
  static String fingerprint(String normalizedSql) {
    var hash = 0xcbf29ce484222325;
    for (final byte in normalizedSql.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0').substring(0, 8);
  }
}
