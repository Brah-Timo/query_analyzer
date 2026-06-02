import '../models/analyzed_query.dart';
import '../models/database_schema.dart';

/// Detects queries that are likely to cause a full-table scan.
///
/// A full-table scan occurs when the query engine must read every row in a
/// table because no suitable index can be used.  This detector uses
/// heuristics on the parsed query structure — for exact plan analysis the
/// adapter's `EXPLAIN` integration should be used in addition.
class FullTableScanDetector {
  /// The database schema used for index awareness.
  final DatabaseSchema schema;

  /// Creates a [FullTableScanDetector].
  const FullTableScanDetector({required this.schema});

  /// Analyses [parsed] and returns any full-table-scan issues found.
  List<QueryIssue> detect(ParsedQuery parsed) {
    if (parsed.type != QueryType.select &&
        parsed.type != QueryType.update &&
        parsed.type != QueryType.delete) {
      return const [];
    }

    final issues = <QueryIssue>[];

    for (final table in parsed.tables) {
      final tableSchema = schema.findTable(table);

      // ── 1. No WHERE clause on a known large table ─────────────────────────
      if (parsed.type == QueryType.select && parsed.lacksWhereClause) {
        final approxRows = tableSchema?.approximateRowCount;
        if (approxRows == null || approxRows > 1000) {
          issues.add(
            QueryIssue(
              type: IssueType.fullTableScan,
              description:
                  'Query on "$table" has no WHERE clause — '
                  'all rows will be scanned.',
              severity: approxRows != null && approxRows > 100000
                  ? IssueSeverity.critical
                  : IssueSeverity.high,
              affectedElement: table,
            ),
          );
        }
      }

      // ── 2. WHERE column has no index ──────────────────────────────────────
      if (tableSchema != null) {
        for (final clause in parsed.whereClauses) {
          // Skip if the clause is on a parametrized value we can't evaluate
          if (!tableSchema.hasIndexOn(clause.column)) {
            issues.add(
              QueryIssue(
                type: IssueType.fullTableScan,
                description:
                    'Column "${clause.column}" in WHERE clause of '
                    '"$table" has no index — sequential scan likely.',
                severity: IssueSeverity.high,
                affectedElement: '${table}.${clause.column}',
              ),
            );
          }
        }
      }

      // ── 3. LIKE with leading wildcard defeats index ───────────────────────
      for (final clause in parsed.whereClauses) {
        if (clause.operator.toUpperCase() == 'LIKE') {
          issues.add(
            QueryIssue(
              type: IssueType.fullTableScan,
              description:
                  'LIKE operator on "${clause.column}" may prevent index '
                  'usage if the pattern starts with a wildcard (%).',
              severity: IssueSeverity.medium,
              affectedElement: clause.column,
            ),
          );
        }
      }
    }

    return issues;
  }
}
