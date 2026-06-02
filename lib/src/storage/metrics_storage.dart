import 'dart:collection';
import 'dart:convert';
import '../models/analyzed_query.dart';
import '../models/performance_metric.dart';
import '../utils/config.dart';
import '../utils/logger.dart';

/// In-memory ring-buffer storage for [AnalyzedQuery] records, augmented with
/// aggregated [PerformanceMetric]s keyed by query fingerprint.
///
/// When [config.persistMetrics] is `true` the [LocalDatabase] companion is
/// used for durable storage; otherwise everything lives in RAM.
class MetricsStorage {
  final QueryAnalyzerConfig _config;

  /// Ring-buffer of the most recent analyzed queries.
  final Queue<AnalyzedQuery> _recentQueries = Queue();

  /// Aggregated metrics keyed by normalized query fingerprint.
  final Map<String, PerformanceMetric> _metrics = {};

  /// Creates a [MetricsStorage].
  MetricsStorage(this._config);

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Stores an [AnalyzedQuery] and updates its aggregate [PerformanceMetric].
  Future<void> store(AnalyzedQuery query) async {
    // Maintain ring-buffer size
    _recentQueries.addLast(query);
    while (_recentQueries.length > _config.maxStoredQueries) {
      _recentQueries.removeFirst();
    }

    // Update aggregate metric
    final fp = query.parsed.normalizedQuery;
    final existing = _metrics[fp];
    _metrics[fp] = existing == null
        ? PerformanceMetric.fromFirstObservation(
            queryPattern: fp,
            executionTimeMs: query.executionTimeMs,
          )
        : existing.withNewObservation(query.executionTimeMs);

    QaLogger.debug(
      'Stored query [${query.id}] '
      '${query.executionTimeMs}ms '
      '(total stored: ${_recentQueries.length})',
    );
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns all stored [AnalyzedQuery] records, newest first.
  List<AnalyzedQuery> getAll() =>
      _recentQueries.toList().reversed.toList();

  /// Returns only the slow queries, newest first.
  List<AnalyzedQuery> getSlowQueries() =>
      getAll().where((q) => q.isSlowQuery).toList();

  /// Returns queries executed since [since], newest first.
  List<AnalyzedQuery> getSince(DateTime since) =>
      getAll()
          .where((q) => q.executedAt.isAfter(since))
          .toList();

  /// Returns the aggregated [PerformanceMetric] for a given fingerprint.
  PerformanceMetric? getMetricForPattern(String normalizedPattern) =>
      _metrics[normalizedPattern];

  /// Returns all aggregated [PerformanceMetric]s sorted by average execution
  /// time descending.
  List<PerformanceMetric> getAllMetrics() =>
      _metrics.values.toList()
        ..sort(
          (a, b) => b.averageExecutionTimeMs
              .compareTo(a.averageExecutionTimeMs),
        );

  /// Returns a daily summary snapshot.
  DailySummary getDailySummary() {
    final since = DateTime.now().subtract(const Duration(hours: 24));
    final daily = getSince(since);
    return DailySummary(
      totalQueries: daily.length,
      slowQueries: daily.where((q) => q.isSlowQuery).toList(),
      averageExecutionTimeMs: daily.isEmpty
          ? 0
          : daily.map((q) => q.executionTimeMs).reduce((a, b) => a + b) /
              daily.length,
    );
  }

  // ── Persistence helpers (stub — plugged in by LocalDatabase) ──────────────

  /// Serializes the current in-memory state to JSON.
  String exportJson() {
    return jsonEncode({
      'exportedAt': DateTime.now().toIso8601String(),
      'queries': getAll().map((q) => q.toJson()).toList(),
      'metrics': _metrics.map((k, v) => MapEntry(k, v.toJson())),
    });
  }

  // ── Housekeeping ──────────────────────────────────────────────────────────

  /// Clears all in-memory data.
  void reset() {
    _recentQueries.clear();
    _metrics.clear();
    QaLogger.info('MetricsStorage reset.');
  }

  /// Total number of queries currently in the ring-buffer.
  int get size => _recentQueries.length;
}

/// A lightweight snapshot of the last 24 hours.
class DailySummary {
  /// Total queries observed in the last 24 h.
  final int totalQueries;

  /// Slow queries observed in the last 24 h.
  final List<AnalyzedQuery> slowQueries;

  /// Average execution time in ms over the last 24 h.
  final double averageExecutionTimeMs;

  /// Creates a [DailySummary].
  const DailySummary({
    required this.totalQueries,
    required this.slowQueries,
    required this.averageExecutionTimeMs,
  });

  @override
  String toString() =>
      'DailySummary(total: $totalQueries, slow: ${slowQueries.length}, '
      'avg: ${averageExecutionTimeMs.toStringAsFixed(1)}ms)';
}
