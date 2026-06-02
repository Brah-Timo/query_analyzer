import 'dart:math';
import '../models/analysis_report.dart';
import '../models/analyzed_query.dart';
import '../storage/metrics_storage.dart';

/// Builds [AnalysisReport] objects from [MetricsStorage] data.
class ReportGenerator {
  final MetricsStorage _storage;

  /// Creates a [ReportGenerator].
  const ReportGenerator(this._storage);

  // ── Report generation ─────────────────────────────────────────────────────

  /// Generates a comprehensive [AnalysisReport] for the given [timeRange].
  AnalysisReport generateReport({
    Duration timeRange = const Duration(hours: 24),
  }) {
    final since = DateTime.now().subtract(timeRange);
    final queries = _storage.getSince(since);

    if (queries.isEmpty) {
      return _emptyReport(timeRange);
    }

    final slowQueries = queries.where((q) => q.isSlowQuery).toList();
    final times = queries.map((q) => q.executionTimeMs).toList()..sort();

    return AnalysisReport(
      generatedAt: DateTime.now(),
      timeRange: timeRange,
      totalQueries: queries.length,
      slowQueries: slowQueries,
      averageExecutionTimeMs: _mean(times),
      medianExecutionTimeMs: _percentile(times, 50),
      p95ExecutionTimeMs: _percentile(times, 95),
      p99ExecutionTimeMs: _percentile(times, 99),
      topSlowQueries: slowQueries
          .toList()
        ..sort((a, b) => b.executionTimeMs.compareTo(a.executionTimeMs)),
      commonIssues: _countIssues(queries),
      patternMetrics: _storage.getAllMetrics(),
      recommendations: _buildRecommendations(queries, slowQueries),
      totalErrors: 0, // errors tracked via MetricsStorage in future version
      errorRate: 0,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  double _mean(List<int> sorted) {
    if (sorted.isEmpty) return 0;
    return sorted.reduce((a, b) => a + b) / sorted.length;
  }

  double _percentile(List<int> sorted, int p) {
    if (sorted.isEmpty) return 0;
    final idx = ((p / 100) * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return sorted[idx].toDouble();
  }

  Map<IssueType, int> _countIssues(List<AnalyzedQuery> queries) {
    final counts = <IssueType, int>{};
    for (final q in queries) {
      for (final issue in q.detectionResult.issues) {
        counts[issue.type] = (counts[issue.type] ?? 0) + 1;
      }
    }
    return counts;
  }

  List<String> _buildRecommendations(
    List<AnalyzedQuery> all,
    List<AnalyzedQuery> slow,
  ) {
    final recs = <String>[];

    if (slow.isEmpty) {
      recs.add('No slow queries detected — keep up the great work!');
      return recs;
    }

    final slowRate = slow.length / max(all.length, 1) * 100;
    if (slowRate > 20) {
      recs.add(
        '${slowRate.toStringAsFixed(1)}% of queries are slow — '
        'consider a global query optimisation pass.',
      );
    }

    // Count issues
    final issues = _countIssues(slow);

    if ((issues[IssueType.missingIndex] ?? 0) > 0) {
      recs.add(
        'Add missing indexes — ${issues[IssueType.missingIndex]} queries '
        'are hampered by un-indexed columns.',
      );
    }

    if ((issues[IssueType.nPlusOne] ?? 0) > 0) {
      recs.add(
        'Fix N+1 patterns — ${issues[IssueType.nPlusOne]} occurrences '
        'detected. Use JOINs or batch fetching.',
      );
    }

    if ((issues[IssueType.largeResult] ?? 0) > 0) {
      recs.add(
        'Add pagination — ${issues[IssueType.largeResult]} queries '
        'return unbounded result sets.',
      );
    }

    if ((issues[IssueType.selectStar] ?? 0) > 0) {
      recs.add(
        'Replace SELECT * — ${issues[IssueType.selectStar]} queries '
        'fetch unnecessary columns.',
      );
    }

    if ((issues[IssueType.subqueryIssue] ?? 0) > 0) {
      recs.add(
        'Refactor sub-queries — ${issues[IssueType.subqueryIssue]} '
        'correlated / deep sub-queries found.',
      );
    }

    return recs;
  }

  AnalysisReport _emptyReport(Duration timeRange) => AnalysisReport(
        generatedAt: DateTime.now(),
        timeRange: timeRange,
        totalQueries: 0,
        slowQueries: const [],
        averageExecutionTimeMs: 0,
        medianExecutionTimeMs: 0,
        p95ExecutionTimeMs: 0,
        p99ExecutionTimeMs: 0,
        topSlowQueries: const [],
        commonIssues: const {},
        patternMetrics: const [],
        recommendations: const ['No data available for the selected time range.'],
        totalErrors: 0,
        errorRate: 0,
      );
}
