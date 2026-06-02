import 'package:meta/meta.dart';

/// The category of a [QuerySuggestion].
enum SuggestionType {
  /// Add a missing index to speed up lookups.
  addIndex,

  /// Remove redundant or unused columns from SELECT.
  removeRedundantColumns,

  /// Refactor the query to avoid N+1 patterns.
  refactorQuery,

  /// Add LIMIT / OFFSET pagination to avoid huge result sets.
  addPagination,

  /// Optimise or rewrite a JOIN.
  optimizeJoin,

  /// Rewrite a correlated sub-query as a JOIN.
  rewriteSubquery,

  /// Cache this query result at application level.
  addCaching,

  /// Partition a table to improve large-table performance.
  partitionTable,

  /// Use a covering index to avoid a table lookup.
  useCoveringIndex,

  /// Run ANALYZE / VACUUM to update planner statistics.
  updateStatistics,

  /// Generic catch-all improvement.
  other,
}

/// Priority level of a [QuerySuggestion].
enum SuggestionPriority {
  /// Nice-to-have, minimal impact.
  low,

  /// Moderate improvement expected.
  medium,

  /// Significant improvement expected.
  high,

  /// Must-fix: production impact is severe.
  critical,
}

/// A concrete, actionable recommendation produced by the [SuggestionEngine].
@immutable
class QuerySuggestion {
  /// Category of the suggestion.
  final SuggestionType type;

  /// Short human-readable title (one line).
  final String title;

  /// Detailed explanation of the problem and the fix.
  final String description;

  /// Optional SQL statement the user can execute directly.
  final String? sqlStatement;

  /// Estimated performance gain in percent (0–100).
  /// `null` means unknown.
  final int? estimatedImprovementPercent;

  /// Priority / urgency of applying this suggestion.
  final SuggestionPriority priority;

  /// Link to documentation or further reading.
  final String? documentationUrl;

  /// Creates a [QuerySuggestion].
  const QuerySuggestion({
    required this.type,
    required this.title,
    required this.description,
    this.sqlStatement,
    this.estimatedImprovementPercent,
    this.priority = SuggestionPriority.medium,
    this.documentationUrl,
  });

  /// Convenience factory for a generic suggestion.
  factory QuerySuggestion.generic(
    String message, {
    SuggestionPriority priority = SuggestionPriority.low,
  }) =>
      QuerySuggestion(
        type: SuggestionType.other,
        title: 'General Improvement',
        description: message,
        priority: priority,
      );

  /// Factory: suggest adding an index on [column] of [table].
  factory QuerySuggestion.addIndex({
    required String table,
    required String column,
    int? estimatedImprovementPercent,
  }) =>
      QuerySuggestion(
        type: SuggestionType.addIndex,
        title: 'Add index on $table($column)',
        description:
            'The query performs a sequential scan on "$table". '
            'Adding an index on "$column" can dramatically reduce execution time.',
        sqlStatement:
            'CREATE INDEX CONCURRENTLY idx_${table}_$column ON $table($column);',
        estimatedImprovementPercent: estimatedImprovementPercent ?? 70,
        priority: SuggestionPriority.high,
        documentationUrl:
            'https://use-the-index-luke.com/sql/anatomy/the-tree',
      );

  /// Factory: suggest paginating a large result set.
  factory QuerySuggestion.addPagination({String? table}) => QuerySuggestion(
        type: SuggestionType.addPagination,
        title: 'Add pagination (LIMIT / OFFSET)',
        description:
            'The query returns an unbounded number of rows${table != null ? ' from "$table"' : ''}. '
            'Use LIMIT and OFFSET (or keyset pagination) to fetch results in pages.',
        sqlStatement: 'SELECT ... FROM ${table ?? "your_table"} '
            'WHERE id > :last_id ORDER BY id LIMIT 100;',
        estimatedImprovementPercent: 80,
        priority: SuggestionPriority.high,
        documentationUrl:
            'https://use-the-index-luke.com/no-offset',
      );

  /// Factory: suggest refactoring an N+1 pattern.
  factory QuerySuggestion.refactorNPlusOne({String? relatedTable}) =>
      QuerySuggestion(
        type: SuggestionType.refactorQuery,
        title: 'Resolve N+1 query pattern',
        description:
            'This query is being executed repeatedly inside a loop. '
            'Consider fetching all required data in a single query using a JOIN'
            '${relatedTable != null ? ' with "$relatedTable"' : ''}, '
            'or use a batch-load approach.',
        estimatedImprovementPercent: 90,
        priority: SuggestionPriority.critical,
        documentationUrl:
            'https://stackoverflow.com/questions/97197/what-is-the-n1-selects-problem-in-orm-object-relational-mapping',
      );

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'title': title,
        'description': description,
        if (sqlStatement != null) 'sqlStatement': sqlStatement,
        if (estimatedImprovementPercent != null)
          'estimatedImprovementPercent': estimatedImprovementPercent,
        'priority': priority.name,
        if (documentationUrl != null) 'documentationUrl': documentationUrl,
      };

  @override
  String toString() => 'QuerySuggestion[${type.name}]: $title '
      '(priority: ${priority.name}'
      '${estimatedImprovementPercent != null ? ', ~$estimatedImprovementPercent% improvement' : ''}'
      ')';
}
