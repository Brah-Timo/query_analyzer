import '../models/analyzed_query.dart';
import '../models/database_schema.dart';

/// Detects columns that are used in WHERE, ORDER BY, or JOIN conditions
/// but lack an index.
class MissingIndexDetector {
  /// The database schema used for index awareness.
  final DatabaseSchema schema;

  /// Creates a [MissingIndexDetector].
  const MissingIndexDetector({required this.schema});

  /// Returns a list of [QueryIssue] for every unindexed column found.
  List<QueryIssue> detect(ParsedQuery parsed) {
    final issues = <QueryIssue>[];

    for (final table in parsed.tables) {
      final tableSchema = schema.findTable(table);
      if (tableSchema == null) continue;

      // ── WHERE columns ─────────────────────────────────────────────────────
      for (final clause in parsed.whereClauses) {
        if (!tableSchema.hasIndexOn(clause.column)) {
          issues.add(
            QueryIssue(
              type: IssueType.missingIndex,
              description:
                  'Column "${clause.column}" used in WHERE clause on '
                  '"$table" has no index.',
              severity: _severityForTable(tableSchema),
              affectedElement: '${table}.${clause.column}',
            ),
          );
        }
      }

      // ── JOIN columns ──────────────────────────────────────────────────────
      for (final join in parsed.joins) {
        final joinedTable = schema.findTable(join.table);
        if (join.onRightColumn != null && joinedTable != null) {
          if (!joinedTable.hasIndexOn(join.onRightColumn!)) {
            issues.add(
              QueryIssue(
                type: IssueType.missingIndex,
                description:
                    'JOIN column "${join.onRightColumn}" on '
                    '"${join.table}" lacks an index — '
                    'hash or nested-loop join will be used.',
                severity: IssueSeverity.high,
                affectedElement: '${join.table}.${join.onRightColumn}',
              ),
            );
          }
        }
        if (join.onLeftColumn != null) {
          final leftTable = parsed.tables.isNotEmpty ? parsed.tables.first : '';
          final leftSchema = schema.findTable(leftTable);
          if (leftSchema != null &&
              !leftSchema.hasIndexOn(join.onLeftColumn!)) {
            issues.add(
              QueryIssue(
                type: IssueType.missingIndex,
                description:
                    'JOIN column "${join.onLeftColumn}" on '
                    '"$leftTable" lacks an index.',
                severity: IssueSeverity.medium,
                affectedElement: '$leftTable.${join.onLeftColumn}',
              ),
            );
          }
        }
      }
    }

    // Deduplicate by affectedElement
    final seen = <String>{};
    return issues.where((i) => seen.add(i.affectedElement)).toList();
  }

  IssueSeverity _severityForTable(TableSchema tableSchema) {
    final rows = tableSchema.approximateRowCount;
    if (rows == null) return IssueSeverity.medium;
    if (rows > 1000000) return IssueSeverity.critical;
    if (rows > 100000) return IssueSeverity.high;
    if (rows > 10000) return IssueSeverity.medium;
    return IssueSeverity.low;
  }
}
