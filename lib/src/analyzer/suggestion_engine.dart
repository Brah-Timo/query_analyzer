import '../models/analyzed_query.dart';
import '../models/database_schema.dart';
import '../models/query_suggestion.dart';

/// Translates [QueryIssue] objects into actionable [QuerySuggestion]s.
class SuggestionEngine {
  final DatabaseSchema _schema;

  /// Creates a [SuggestionEngine] with the given [schema].
  const SuggestionEngine({required DatabaseSchema schema}) : _schema = schema;

  /// Produces a list of suggestions for [issues] found in [parsed].
  ///
  /// Suggestions are ordered by descending priority.
  List<QuerySuggestion> generateSuggestions(
    ParsedQuery parsed,
    List<QueryIssue> issues,
  ) {
    final suggestions = <QuerySuggestion>[];

    for (final issue in issues) {
      final s = _suggest(parsed, issue);
      if (s != null) suggestions.add(s);
    }

    // Deduplicate by title
    final seen = <String>{};
    final unique =
        suggestions.where((s) => seen.add(s.title)).toList();

    // Sort: critical first
    unique.sort((a, b) => b.priority.index.compareTo(a.priority.index));

    return unique;
  }

  // ── Private dispatch ──────────────────────────────────────────────────────

  QuerySuggestion? _suggest(ParsedQuery parsed, QueryIssue issue) {
    switch (issue.type) {
      case IssueType.fullTableScan:
        return _suggestForFullScan(parsed, issue);
      case IssueType.missingIndex:
        return _suggestForMissingIndex(issue);
      case IssueType.nPlusOne:
        return _suggestForNPlusOne(parsed);
      case IssueType.largeResult:
        return _suggestForLargeResult(parsed);
      case IssueType.subqueryIssue:
        return _suggestForSubquery(issue);
      case IssueType.selectStar:
        return _suggestForSelectStar(parsed);
      case IssueType.inefficientJoin:
        return _suggestForInefficientJoin(issue);
      case IssueType.unindexedOrderBy:
        return _suggestForUnindexedOrderBy(issue);
      case IssueType.expensiveAggregate:
        return _suggestForExpensiveAggregate(parsed);
    }
  }

  // ── Individual suggestion factories ──────────────────────────────────────

  QuerySuggestion _suggestForFullScan(ParsedQuery parsed, QueryIssue issue) {
    final parts = issue.affectedElement.split('.');
    final table = parts.first;
    final column = parts.length > 1 ? parts.last : null;

    if (column != null) {
      return QuerySuggestion.addIndex(
        table: table,
        column: column,
        estimatedImprovementPercent: 75,
      );
    }

    // No column identified — generic suggestion
    return QuerySuggestion(
      type: SuggestionType.addIndex,
      title: 'Add a WHERE clause or index to "$table"',
      description:
          'The query on "$table" scans every row. '
          'Add a selective WHERE condition and ensure the filtered '
          'columns are indexed.',
      priority: SuggestionPriority.high,
      estimatedImprovementPercent: 60,
    );
  }

  QuerySuggestion _suggestForMissingIndex(QueryIssue issue) {
    final parts = issue.affectedElement.split('.');
    final table = parts.first;
    final column = parts.length > 1 ? parts.last : issue.affectedElement;

    // Check if this is a foreign-key column — recommend FK index
    final tableSchema = _schema.findTable(table);
    final colSchema = tableSchema != null
        ? _tryFindColumn(tableSchema, column)
        : null;

    if (colSchema?.looksLikeForeignKey == true) {
      return QuerySuggestion(
        type: SuggestionType.addIndex,
        title: 'Add foreign-key index on $table($column)',
        description:
            '"$column" looks like a foreign key but has no index. '
            'This makes JOIN operations and lookups by this key very slow.',
        sqlStatement:
            'CREATE INDEX CONCURRENTLY idx_${table}_$column ON $table($column);',
        estimatedImprovementPercent: 80,
        priority: SuggestionPriority.critical,
        documentationUrl: 'https://use-the-index-luke.com/sql/where-clause/the-equals-operator/primary-keys',
      );
    }

    return QuerySuggestion.addIndex(
      table: table,
      column: column,
      estimatedImprovementPercent: 70,
    );
  }

  QuerySuggestion _suggestForNPlusOne(ParsedQuery parsed) =>
      QuerySuggestion.refactorNPlusOne(
        relatedTable:
            parsed.tables.length > 1 ? parsed.tables[1] : null,
      );

  QuerySuggestion _suggestForLargeResult(ParsedQuery parsed) =>
      QuerySuggestion.addPagination(
        table: parsed.tables.isNotEmpty ? parsed.tables.first : null,
      );

  QuerySuggestion _suggestForSubquery(QueryIssue issue) {
    if (issue.description.contains('Correlated')) {
      return QuerySuggestion(
        type: SuggestionType.rewriteSubquery,
        title: 'Rewrite correlated sub-query as a JOIN',
        description:
            'A correlated sub-query is re-evaluated for every outer row. '
            'Replacing it with an INNER JOIN or a lateral join typically '
            'reduces execution time by an order of magnitude.',
        estimatedImprovementPercent: 85,
        priority: SuggestionPriority.critical,
        documentationUrl:
            'https://use-the-index-luke.com/sql/where-clause/obfuscated-conditions/correlated-subqueries',
      );
    }

    return QuerySuggestion(
      type: SuggestionType.rewriteSubquery,
      title: 'Replace sub-query with a CTE or JOIN',
      description:
          'Deep or repeated sub-queries can usually be refactored into '
          'Common Table Expressions (WITH … AS) or JOIN operations, '
          'which the query planner can optimise more effectively.',
      estimatedImprovementPercent: 50,
      priority: SuggestionPriority.high,
    );
  }

  QuerySuggestion _suggestForSelectStar(ParsedQuery parsed) =>
      QuerySuggestion(
        type: SuggestionType.removeRedundantColumns,
        title: 'Replace SELECT * with explicit column list',
        description:
            'Selecting all columns transfers unnecessary data over the '
            'network and prevents the optimizer from using covering indexes. '
            'List only the columns your application actually uses.',
        estimatedImprovementPercent: 30,
        priority: SuggestionPriority.medium,
      );

  QuerySuggestion _suggestForInefficientJoin(QueryIssue issue) =>
      QuerySuggestion(
        type: SuggestionType.optimizeJoin,
        title: 'Optimise JOIN on "${issue.affectedElement}"',
        description:
            'The JOIN on "${issue.affectedElement}" may produce a '
            'Cartesian product or use an inefficient algorithm. '
            'Verify ON conditions are correct and that join columns '
            'are indexed on both sides.',
        estimatedImprovementPercent: 65,
        priority: SuggestionPriority.high,
      );

  QuerySuggestion _suggestForUnindexedOrderBy(QueryIssue issue) =>
      QuerySuggestion(
        type: SuggestionType.addIndex,
        title: 'Index ORDER BY column "${issue.affectedElement}"',
        description:
            'Sorting by an un-indexed column requires a full sort of the '
            'result set. Adding an index on "${issue.affectedElement}" '
            'allows the engine to return rows in order without sorting.',
        sqlStatement:
            'CREATE INDEX CONCURRENTLY idx_sort ON '
            '${issue.affectedElement.replaceAll('.', '(')})',
        estimatedImprovementPercent: 55,
        priority: SuggestionPriority.medium,
      );

  QuerySuggestion _suggestForExpensiveAggregate(ParsedQuery parsed) =>
      QuerySuggestion(
        type: SuggestionType.addCaching,
        title: 'Cache aggregate result or use a materialized view',
        description:
            'Aggregate functions on large tables are expensive. '
            'Consider caching the result at application level, '
            'scheduling a pre-aggregation job, or using a '
            'PostgreSQL MATERIALIZED VIEW.',
        estimatedImprovementPercent: 90,
        priority: SuggestionPriority.high,
      );

  // ── Helpers ───────────────────────────────────────────────────────────────

  ColumnSchema? _tryFindColumn(TableSchema table, String column) {
    try {
      return table.findColumn(column);
    } catch (_) {
      return null;
    }
  }
}
