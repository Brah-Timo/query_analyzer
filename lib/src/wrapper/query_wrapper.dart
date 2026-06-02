import '../analyzer/query_analyzer_core.dart';
import '../utils/timer.dart';

/// Wraps a single SQL string execution (for use cases where you cannot
/// replace the whole database connection but want to measure one query).
///
/// ```dart
/// final result = await QueryWrapper.measure(
///   sql: 'SELECT COUNT(*) FROM orders',
///   analyzer: analyzer,
///   execute: () => db.rawQuery('SELECT COUNT(*) FROM orders'),
/// );
/// ```
class QueryWrapper {
  QueryWrapper._();

  /// Measures the execution time of [execute], records the query in
  /// [analyzer], and returns the result of [execute].
  static Future<T> measure<T>({
    required String sql,
    required QueryAnalyzerCore analyzer,
    required Future<T> Function() execute,
    Map<String, dynamic>? parameters,
  }) async {
    final (result, elapsed) =
        await PrecisionTimer.measureWithResult(execute);

    await analyzer.analyzeQuery(
      sql,
      executionTimeMs: elapsed,
      parameters: parameters,
    );

    return result;
  }
}
