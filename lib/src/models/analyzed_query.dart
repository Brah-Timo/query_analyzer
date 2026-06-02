import 'package:meta/meta.dart';
import 'query_suggestion.dart';

/// The type of a SQL statement.
enum QueryType {
  /// SELECT query.
  select,

  /// INSERT query.
  insert,

  /// UPDATE query.
  update,

  /// DELETE query.
  delete,

  /// DDL statement (CREATE, ALTER, DROP, …).
  ddl,

  /// Other / unknown statement.
  other,
}

/// A WHERE-clause condition extracted by the parser.
@immutable
class WhereClause {
  /// The column referenced in the condition.
  final String column;

  /// The operator used (=, >, <, LIKE, IN, …).
  final String operator;

  /// Whether the value is a parameter placeholder.
  final bool isParameterized;

  /// Creates a [WhereClause].
  const WhereClause({
    required this.column,
    required this.operator,
    required this.isParameterized,
  });

  Map<String, dynamic> toJson() => {
        'column': column,
        'operator': operator,
        'isParameterized': isParameterized,
      };
}

/// A JOIN clause extracted by the parser.
@immutable
class JoinClause {
  /// Type of join (INNER, LEFT, RIGHT, CROSS, …).
  final String joinType;

  /// The table being joined.
  final String table;

  /// The join condition columns (left side).
  final String? onLeftColumn;

  /// The join condition columns (right side).
  final String? onRightColumn;

  /// Creates a [JoinClause].
  const JoinClause({
    required this.joinType,
    required this.table,
    this.onLeftColumn,
    this.onRightColumn,
  });

  Map<String, dynamic> toJson() => {
        'joinType': joinType,
        'table': table,
        if (onLeftColumn != null) 'onLeftColumn': onLeftColumn,
        if (onRightColumn != null) 'onRightColumn': onRightColumn,
      };
}

/// The raw SQL query broken down into its structural components.
@immutable
class ParsedQuery {
  /// Statement type.
  final QueryType type;

  /// Primary tables referenced (FROM clause).
  final List<String> tables;

  /// Columns listed in the SELECT clause.
  final List<String> selectedColumns;

  /// WHERE conditions found.
  final List<WhereClause> whereClauses;

  /// JOIN clauses found.
  final List<JoinClause> joins;

  /// Whether a GROUP BY clause is present.
  final bool hasGroupBy;

  /// Whether an ORDER BY clause is present.
  final bool hasOrderBy;

  /// Whether the query contains at least one sub-query.
  final bool hasSubquery;

  /// Depth of sub-query nesting (0 = no sub-query).
  final int subqueryDepth;

  /// Whether a DISTINCT keyword is present.
  final bool hasDistinct;

  /// Whether aggregate functions (COUNT, SUM, …) are used.
  final bool hasAggregates;

  /// LIMIT value if present, otherwise `null`.
  final int? limit;

  /// OFFSET value if present, otherwise `null`.
  final int? offset;

  /// Normalized version (literals replaced with `?`).
  final String normalizedQuery;

  /// Creates a [ParsedQuery].
  const ParsedQuery({
    required this.type,
    required this.tables,
    required this.selectedColumns,
    required this.whereClauses,
    required this.joins,
    required this.hasGroupBy,
    required this.hasOrderBy,
    required this.hasSubquery,
    required this.subqueryDepth,
    required this.hasDistinct,
    required this.hasAggregates,
    this.limit,
    this.offset,
    required this.normalizedQuery,
  });

  /// Returns `true` if the query has no WHERE clause (potential full scan).
  bool get lacksWhereClause =>
      type == QueryType.select && whereClauses.isEmpty;

  /// Returns `true` if SELECT * is used.
  bool get selectsStar =>
      selectedColumns.contains('*') || selectedColumns.isEmpty;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'tables': tables,
        'selectedColumns': selectedColumns,
        'whereClauses': whereClauses.map((w) => w.toJson()).toList(),
        'joins': joins.map((j) => j.toJson()).toList(),
        'hasGroupBy': hasGroupBy,
        'hasOrderBy': hasOrderBy,
        'hasSubquery': hasSubquery,
        'subqueryDepth': subqueryDepth,
        'hasDistinct': hasDistinct,
        'hasAggregates': hasAggregates,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        'normalizedQuery': normalizedQuery,
      };
}

/// Severity levels for detected query issues.
enum IssueSeverity {
  /// Minor issue — minimal performance impact.
  low(value: 1, label: 'Low'),

  /// Moderate issue — noticeable impact under load.
  medium(value: 5, label: 'Medium'),

  /// Serious issue — significant degradation expected.
  high(value: 10, label: 'High'),

  /// Critical issue — production outage risk.
  critical(value: 20, label: 'Critical');

  /// Numeric weight used to compute an impact score.
  final int value;

  /// Display label.
  final String label;

  const IssueSeverity({required this.value, required this.label});
}

/// The category of a detected query issue.
enum IssueType {
  /// Query performs a sequential (full-table) scan.
  fullTableScan,

  /// A column used in WHERE / JOIN lacks an index.
  missingIndex,

  /// N+1 query pattern detected.
  nPlusOne,

  /// Query returns an excessively large number of rows.
  largeResult,

  /// Correlated or deeply nested sub-query detected.
  subqueryIssue,

  /// Inefficient JOIN (cross join, missing ON condition, …).
  inefficientJoin,

  /// SELECT * used — fetches unnecessary columns.
  selectStar,

  /// ORDER BY on an un-indexed column with no LIMIT.
  unindexedOrderBy,

  /// Aggregate without GROUP BY on a large table.
  expensiveAggregate,
}

/// A single problem found in a query by a detector.
@immutable
class QueryIssue {
  /// Issue category.
  final IssueType type;

  /// Human-readable description.
  final String description;

  /// Severity level.
  final IssueSeverity severity;

  /// The specific SQL element (table, column, …) affected.
  final String affectedElement;

  /// Creates a [QueryIssue].
  const QueryIssue({
    required this.type,
    required this.description,
    required this.severity,
    required this.affectedElement,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'description': description,
        'severity': severity.name,
        'affectedElement': affectedElement,
      };

  @override
  String toString() =>
      'QueryIssue[${severity.label}] ${type.name}: $description';
}

/// Aggregated result of all detectors running on a single query.
@immutable
class DetectionResult {
  /// All issues found.
  final List<QueryIssue> issues;

  /// Creates a [DetectionResult].
  const DetectionResult({required this.issues});

  /// Empty result (no issues).
  const DetectionResult.clean() : issues = const [];

  /// Returns `true` if at least one issue was found.
  bool get hasIssues => issues.isNotEmpty;

  /// Composite severity score (sum of all issue weights).
  int get severityScore =>
      issues.fold(0, (sum, i) => sum + i.severity.value);

  /// Highest severity among all issues.
  IssueSeverity? get maxSeverity {
    if (issues.isEmpty) return null;
    return issues
        .map((i) => i.severity)
        .reduce((a, b) => a.value >= b.value ? a : b);
  }

  Map<String, dynamic> toJson() => {
        'hasIssues': hasIssues,
        'severityScore': severityScore,
        'issues': issues.map((i) => i.toJson()).toList(),
      };
}

/// The complete result of analyzing one SQL query execution.
@immutable
class AnalyzedQuery {
  /// Unique identifier for this analysis record.
  final String id;

  /// The original SQL string (possibly with PII masked).
  final String originalQuery;

  /// Execution time measured by the wrapper.
  final int executionTimeMs;

  /// When the query was executed.
  final DateTime executedAt;

  /// Parsed structure of the query.
  final ParsedQuery parsed;

  /// All issues found by the detectors.
  final DetectionResult detectionResult;

  /// Actionable suggestions produced by the suggestion engine.
  final List<QuerySuggestion> suggestions;

  /// Whether this query exceeded the slow-query threshold.
  final bool isSlowQuery;

  /// The database / connection tag this query was run on.
  final String? databaseTag;

  /// Optional parameters that were bound to the query (masked).
  final Map<String, String>? maskedParameters;

  /// Computed impact score in [0, 100].
  late final int impactScore;

  /// Creates an [AnalyzedQuery] and computes [impactScore].
  AnalyzedQuery({
    required this.id,
    required this.originalQuery,
    required this.executionTimeMs,
    required this.executedAt,
    required this.parsed,
    required this.detectionResult,
    required this.suggestions,
    required this.isSlowQuery,
    this.databaseTag,
    this.maskedParameters,
  }) {
    impactScore = _computeImpactScore();
  }

  int _computeImpactScore() {
    var score = 0;
    if (isSlowQuery) score += 30;
    score += detectionResult.severityScore;
    if (parsed.hasSubquery) score += parsed.subqueryDepth * 5;
    if (parsed.selectsStar) score += 5;
    return score.clamp(0, 100);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'originalQuery': originalQuery,
        'executionTimeMs': executionTimeMs,
        'executedAt': executedAt.toIso8601String(),
        'parsed': parsed.toJson(),
        'detectionResult': detectionResult.toJson(),
        'suggestions': suggestions.map((s) => s.toJson()).toList(),
        'isSlowQuery': isSlowQuery,
        'impactScore': impactScore,
        if (databaseTag != null) 'databaseTag': databaseTag,
        if (maskedParameters != null) 'maskedParameters': maskedParameters,
      };

  @override
  String toString() =>
      'AnalyzedQuery(${executionTimeMs}ms, impact: $impactScore, '
      'issues: ${detectionResult.issues.length}, slow: $isSlowQuery)';
}
