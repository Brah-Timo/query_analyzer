import 'package:meta/meta.dart';
import '../../constants.dart';

/// Holds aggregated performance statistics for a group of queries
/// (typically grouped by normalized SQL pattern).
@immutable
class PerformanceMetric {
  /// Normalized query pattern (parameters replaced with `?`).
  final String queryPattern;

  /// Total cumulative execution time in milliseconds.
  final double totalExecutionTimeMs;

  /// Number of times this pattern has been executed.
  final int executionCount;

  /// Fastest recorded execution in milliseconds.
  final int minExecutionTimeMs;

  /// Slowest recorded execution in milliseconds.
  final int maxExecutionTimeMs;

  /// Running mean (Welford's algorithm) for numerically stable average.
  final double averageExecutionTimeMs;

  /// Running variance (used to derive standard deviation).
  final double _variance;

  /// Pre-computed percentile buckets.
  /// Key = percentile (e.g. 50, 95, 99), value = latency in ms.
  final Map<int, double> percentiles;

  /// Total error count for this pattern.
  final int errorCount;

  /// Timestamp of the first recorded execution.
  final DateTime firstSeenAt;

  /// Timestamp of the most recent execution.
  final DateTime lastSeenAt;

  /// Creates a [PerformanceMetric].
  const PerformanceMetric({
    required this.queryPattern,
    required this.totalExecutionTimeMs,
    required this.executionCount,
    required this.minExecutionTimeMs,
    required this.maxExecutionTimeMs,
    required this.averageExecutionTimeMs,
    required double variance,
    required this.percentiles,
    required this.errorCount,
    required this.firstSeenAt,
    required this.lastSeenAt,
  }) : _variance = variance;

  /// Sample standard deviation in milliseconds.
  double get stdDevMs =>
      executionCount > 1 ? _variance / (executionCount - 1) : 0.0;

  /// Error rate as a value in [0.0, 1.0].
  double get errorRate =>
      executionCount == 0 ? 0.0 : errorCount / executionCount;

  /// Returns a new metric initialized from a single observation.
  factory PerformanceMetric.fromFirstObservation({
    required String queryPattern,
    required int executionTimeMs,
    bool isError = false,
  }) {
    final now = DateTime.now();
    return PerformanceMetric(
      queryPattern: queryPattern,
      totalExecutionTimeMs: executionTimeMs.toDouble(),
      executionCount: 1,
      minExecutionTimeMs: executionTimeMs,
      maxExecutionTimeMs: executionTimeMs,
      averageExecutionTimeMs: executionTimeMs.toDouble(),
      variance: 0,
      percentiles: {
        for (final p in kTrackedPercentiles) p: executionTimeMs.toDouble(),
      },
      errorCount: isError ? 1 : 0,
      firstSeenAt: now,
      lastSeenAt: now,
    );
  }

  /// Returns an updated metric after recording a new [executionTimeMs].
  PerformanceMetric withNewObservation(
    int executionTimeMs, {
    bool isError = false,
  }) {
    final newCount = executionCount + 1;
    final delta = executionTimeMs - averageExecutionTimeMs;
    final newAvg = averageExecutionTimeMs + delta / newCount;
    final delta2 = executionTimeMs - newAvg;
    final newVariance = _variance + delta * delta2;

    return PerformanceMetric(
      queryPattern: queryPattern,
      totalExecutionTimeMs: totalExecutionTimeMs + executionTimeMs,
      executionCount: newCount,
      minExecutionTimeMs:
          executionTimeMs < minExecutionTimeMs ? executionTimeMs : minExecutionTimeMs,
      maxExecutionTimeMs:
          executionTimeMs > maxExecutionTimeMs ? executionTimeMs : maxExecutionTimeMs,
      averageExecutionTimeMs: newAvg,
      variance: newVariance,
      percentiles: percentiles, // updated externally via HdrHistogram or T-Digest
      errorCount: errorCount + (isError ? 1 : 0),
      firstSeenAt: firstSeenAt,
      lastSeenAt: DateTime.now(),
    );
  }

  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'queryPattern': queryPattern,
        'totalExecutionTimeMs': totalExecutionTimeMs,
        'executionCount': executionCount,
        'minExecutionTimeMs': minExecutionTimeMs,
        'maxExecutionTimeMs': maxExecutionTimeMs,
        'averageExecutionTimeMs': averageExecutionTimeMs,
        'stdDevMs': stdDevMs,
        'percentiles': percentiles.map((k, v) => MapEntry(k.toString(), v)),
        'errorCount': errorCount,
        'errorRate': errorRate,
        'firstSeenAt': firstSeenAt.toIso8601String(),
        'lastSeenAt': lastSeenAt.toIso8601String(),
      };

  @override
  String toString() =>
      'PerformanceMetric('
      'pattern: ${queryPattern.substring(0, queryPattern.length.clamp(0, 60))}, '
      'count: $executionCount, '
      'avg: ${averageExecutionTimeMs.toStringAsFixed(1)}ms, '
      'p99: ${percentiles[99]?.toStringAsFixed(1)}ms'
      ')';
}
