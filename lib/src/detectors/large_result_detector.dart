import '../models/analyzed_query.dart';

/// Detects queries that are likely to return an excessively large number of
/// rows.
///
/// The heuristic checks structural properties of the parsed query rather
/// than actual row counts (which are only available after execution).
class LargeResultDetector {
  /// Row count above which the result is considered large.
  /// Used to estimate risk when schema statistics are unavailable.
  final int rowThreshold;

  /// Creates a [LargeResultDetector].
  const LargeResultDetector({required this.rowThreshold});

  /// Returns issues if the query might return an unbounded or huge result.
  List<QueryIssue> detect(
    ParsedQuery parsed, {
    int? actualRowCount,
  }) {
    if (parsed.type != QueryType.select) return const [];

    final issues = <QueryIssue>[];

    // ── 1. Actual row count provided (post-execution feedback) ────────────
    if (actualRowCount != null && actualRowCount >= rowThreshold) {
      issues.add(
        QueryIssue(
          type: IssueType.largeResult,
          description:
              'Query returned $actualRowCount rows — consider adding '
              'pagination (LIMIT / OFFSET or keyset pagination).',
          severity: actualRowCount >= rowThreshold * 10
              ? IssueSeverity.critical
              : IssueSeverity.high,
          affectedElement: parsed.tables.join(', '),
        ),
      );
    }

    // ── 2. No LIMIT clause and no WHERE clause ────────────────────────────
    if (parsed.limit == null && parsed.lacksWhereClause) {
      issues.add(
        QueryIssue(
          type: IssueType.largeResult,
          description:
              'SELECT on ${parsed.tables.join(", ")} has no LIMIT and '
              'no WHERE clause — could return millions of rows.',
          severity: IssueSeverity.high,
          affectedElement: parsed.tables.join(', '),
        ),
      );
    }

    // ── 3. No LIMIT on a JOIN query ───────────────────────────────────────
    if (parsed.limit == null &&
        parsed.joins.isNotEmpty &&
        parsed.lacksWhereClause) {
      issues.add(
        QueryIssue(
          type: IssueType.largeResult,
          description:
              'Unconstrained JOIN across ${parsed.tables.join(", ")} '
              'with no LIMIT — Cartesian explosion risk.',
          severity: IssueSeverity.critical,
          affectedElement: parsed.tables.join(', '),
        ),
      );
    }

    // ── 4. SELECT * with no LIMIT ─────────────────────────────────────────
    if (parsed.selectsStar && parsed.limit == null) {
      issues.add(
        QueryIssue(
          type: IssueType.selectStar,
          description:
              'SELECT * fetches every column — specify only the columns '
              'you need to reduce network I/O and memory usage.',
          severity: IssueSeverity.medium,
          affectedElement: parsed.tables.join(', '),
        ),
      );
    }

    return issues;
  }
}
