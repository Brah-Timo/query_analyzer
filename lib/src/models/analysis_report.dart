import 'package:meta/meta.dart';
import 'analyzed_query.dart';
import 'performance_metric.dart';
import 'query_suggestion.dart';

/// A time-boxed, aggregated performance report.
@immutable
class AnalysisReport {
  /// When this report was generated.
  final DateTime generatedAt;

  /// The time window covered by this report.
  final Duration timeRange;

  /// Total number of queries observed in the window.
  final int totalQueries;

  /// Queries that exceeded the slow-query threshold.
  final List<AnalyzedQuery> slowQueries;

  /// Mean execution time across all observed queries (ms).
  final double averageExecutionTimeMs;

  /// Median execution time (p50) in ms.
  final double medianExecutionTimeMs;

  /// 95th-percentile execution time in ms.
  final double p95ExecutionTimeMs;

  /// 99th-percentile execution time in ms.
  final double p99ExecutionTimeMs;

  /// Top slow queries, sorted descending by execution time.
  final List<AnalyzedQuery> topSlowQueries;

  /// Count of each detected issue type across all queries.
  final Map<IssueType, int> commonIssues;

  /// Aggregated performance metrics per normalized pattern.
  final List<PerformanceMetric> patternMetrics;

  /// Prioritized list of general recommendations.
  final List<String> recommendations;

  /// Total number of errors encountered during query execution.
  final int totalErrors;

  /// Error rate (errors / totalQueries).
  final double errorRate;

  /// Creates an [AnalysisReport].
  const AnalysisReport({
    required this.generatedAt,
    required this.timeRange,
    required this.totalQueries,
    required this.slowQueries,
    required this.averageExecutionTimeMs,
    required this.medianExecutionTimeMs,
    required this.p95ExecutionTimeMs,
    required this.p99ExecutionTimeMs,
    required this.topSlowQueries,
    required this.commonIssues,
    required this.patternMetrics,
    required this.recommendations,
    required this.totalErrors,
    required this.errorRate,
  });

  /// Percentage of slow queries relative to total.
  double get slowQueryRate =>
      totalQueries == 0 ? 0 : slowQueries.length / totalQueries * 100;

  /// Top 5 most impactful suggestions across all slow queries.
  List<QuerySuggestion> get topSuggestions {
    final all = slowQueries
        .expand((q) => q.suggestions)
        .toList()
      ..sort((a, b) {
        final pa = (b.estimatedImprovementPercent ?? 0)
            .compareTo(a.estimatedImprovementPercent ?? 0);
        if (pa != 0) return pa;
        return b.priority.index.compareTo(a.priority.index);
      });
    return all.take(5).toList();
  }

  /// A compact plain-text summary of this report.
  String get summary {
    final buf = StringBuffer()
      ..writeln('╔══════════════════════════════════════════════════════╗')
      ..writeln('║          Query Analyzer — Performance Report          ║')
      ..writeln('╚══════════════════════════════════════════════════════╝')
      ..writeln('Generated : ${generatedAt.toIso8601String()}')
      ..writeln('Period    : ${_formatDuration(timeRange)}')
      ..writeln()
      ..writeln('──────────────────  Overview  ───────────────────────')
      ..writeln('Total queries   : $totalQueries')
      ..writeln('Slow queries    : ${slowQueries.length} '
          '(${slowQueryRate.toStringAsFixed(1)}%)')
      ..writeln('Avg exec time   : ${averageExecutionTimeMs.toStringAsFixed(1)} ms')
      ..writeln('Median (p50)    : ${medianExecutionTimeMs.toStringAsFixed(1)} ms')
      ..writeln('p95             : ${p95ExecutionTimeMs.toStringAsFixed(1)} ms')
      ..writeln('p99             : ${p99ExecutionTimeMs.toStringAsFixed(1)} ms')
      ..writeln('Total errors    : $totalErrors  '
          '(rate: ${(errorRate * 100).toStringAsFixed(2)}%)')
      ..writeln()
      ..writeln('──────────────  Top Slow Queries  ───────────────────');

    for (var i = 0; i < topSlowQueries.take(5).length; i++) {
      final q = topSlowQueries[i];
      final snippet = q.originalQuery.length > 60
          ? '${q.originalQuery.substring(0, 57)}…'
          : q.originalQuery;
      buf.writeln('  ${i + 1}. [${q.executionTimeMs}ms] $snippet');
    }

    buf
      ..writeln()
      ..writeln('─────────────  Common Issues  ────────────────────────');
    commonIssues.entries
        .toList()
        .sort((a, b) => b.value.compareTo(a.value));
    for (final entry in commonIssues.entries) {
      buf.writeln('  • ${entry.key.name}: ${entry.value}×');
    }

    buf
      ..writeln()
      ..writeln('───────────────  Recommendations  ───────────────────');
    for (var i = 0; i < recommendations.length; i++) {
      buf.writeln('  ${i + 1}. ${recommendations[i]}');
    }

    return buf.toString();
  }

  String _formatDuration(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }

  /// Serializes this report to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt.toIso8601String(),
        'timeRangeSeconds': timeRange.inSeconds,
        'totalQueries': totalQueries,
        'slowQueryCount': slowQueries.length,
        'slowQueryRate': slowQueryRate,
        'averageExecutionTimeMs': averageExecutionTimeMs,
        'medianExecutionTimeMs': medianExecutionTimeMs,
        'p95ExecutionTimeMs': p95ExecutionTimeMs,
        'p99ExecutionTimeMs': p99ExecutionTimeMs,
        'topSlowQueries':
            topSlowQueries.take(10).map((q) => q.toJson()).toList(),
        'commonIssues': commonIssues
            .map((k, v) => MapEntry(k.name, v)),
        'patternMetrics':
            patternMetrics.map((m) => m.toJson()).toList(),
        'recommendations': recommendations,
        'totalErrors': totalErrors,
        'errorRate': errorRate,
      };

  @override
  String toString() =>
      'AnalysisReport(queries: $totalQueries, slow: ${slowQueries.length}, '
      'avg: ${averageExecutionTimeMs.toStringAsFixed(1)}ms)';
}
