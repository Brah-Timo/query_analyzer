import '../models/analyzed_query.dart';
import '../../constants.dart';

/// Detects problematic sub-query usage in SQL statements.
///
/// Correlated sub-queries, deeply nested sub-queries, and sub-queries in
/// SELECT lists are common performance anti-patterns.
class SubqueryDetector {
  /// Maximum allowed nesting depth before flagging as an issue.
  final int maxDepth;

  /// Creates a [SubqueryDetector].
  const SubqueryDetector({this.maxDepth = kMaxSubqueryDepth});

  /// Returns a list of [QueryIssue] for any sub-query problems found.
  List<QueryIssue> detect(ParsedQuery parsed, String rawSql) {
    if (!parsed.hasSubquery) return const [];

    final issues = <QueryIssue>[];

    // ── 1. Deeply nested sub-queries ──────────────────────────────────────
    if (parsed.subqueryDepth > maxDepth) {
      issues.add(
        QueryIssue(
          type: IssueType.subqueryIssue,
          description:
              'Sub-query nesting depth ${parsed.subqueryDepth} exceeds '
              'the recommended maximum of $maxDepth. '
              'Consider using CTEs (WITH … AS) or temporary tables.',
          severity: IssueSeverity.high,
          affectedElement: 'subquery depth ${parsed.subqueryDepth}',
        ),
      );
    }

    // ── 2. Correlated sub-query heuristic ─────────────────────────────────
    // A correlated sub-query references a column from the outer query.
    // Heuristic: outer table name appears inside a sub-query SELECT.
    final correlatedPattern = RegExp(
      r'\(\s*SELECT\b.*\bWHERE\b.*\b(' +
          parsed.tables.map(RegExp.escape).join('|') +
          r')\.',
      caseSensitive: false,
      dotAll: true,
    );
    if (parsed.tables.isNotEmpty && correlatedPattern.hasMatch(rawSql)) {
      issues.add(
        QueryIssue(
          type: IssueType.subqueryIssue,
          description:
              'Correlated sub-query detected — it is re-executed for '
              'every row of the outer query. Rewrite as a JOIN or use '
              'a lateral join.',
          severity: IssueSeverity.critical,
          affectedElement: 'correlated sub-query',
        ),
      );
    }

    // ── 3. Sub-query in SELECT list ───────────────────────────────────────
    final selectSubRe =
        RegExp(r'SELECT\s+.*\(\s*SELECT\b', caseSensitive: false, dotAll: true);
    if (selectSubRe.hasMatch(rawSql)) {
      issues.add(
        QueryIssue(
          type: IssueType.subqueryIssue,
          description:
              'Sub-query found in the SELECT column list — this is '
              'evaluated once per output row. Move it to the FROM clause '
              'or use a JOIN.',
          severity: IssueSeverity.high,
          affectedElement: 'sub-query in SELECT list',
        ),
      );
    }

    return issues;
  }
}
