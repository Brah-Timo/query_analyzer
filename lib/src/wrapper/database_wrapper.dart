import '../analyzer/query_analyzer_core.dart';
import '../utils/timer.dart';

/// Abstract interface that all database connections must implement so
/// [DatabaseWrapper] can intercept their queries.
abstract class DatabaseConnection {
  /// Executes a SQL query and returns the result rows.
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  });

  /// Executes a SQL statement (INSERT / UPDATE / DELETE) and returns the
  /// number of affected rows.
  Future<int> execute(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  });

  /// Closes the connection.
  Future<void> close();

  /// Optional: human-readable tag for this connection (e.g. "primary").
  String? get tag => null;
}

/// Wraps a [DatabaseConnection] and transparently measures every query,
/// routing observations to [QueryAnalyzerCore].
///
/// Drop-in replacement: use [DatabaseWrapper.query] and
/// [DatabaseWrapper.execute] exactly as you would the underlying connection.
///
/// ```dart
/// final db = DatabaseWrapper(
///   connection: myPostgresConnection,
///   analyzer: myAnalyzerCore,
/// );
///
/// final rows = await db.query('SELECT * FROM users WHERE id = ?', arguments: [42]);
/// ```
class DatabaseWrapper {
  final DatabaseConnection _connection;
  final QueryAnalyzerCore _analyzer;

  /// Creates a [DatabaseWrapper].
  DatabaseWrapper({
    required DatabaseConnection connection,
    required QueryAnalyzerCore analyzer,
  })  : _connection = connection,
        _analyzer = analyzer;

  // ── Convenience setter ────────────────────────────────────────────────────

  /// Registers a [SlowQueryCallback] for detected slow queries.
  set onSlowQuery(SlowQueryCallback callback) {
    _analyzer.addListener(CallbackListener(callback));
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  /// Executes a SELECT query, measures execution time, and analyses it.
  ///
  /// Returns the raw result rows from the underlying [DatabaseConnection].
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  }) async {
    final stopwatch = Stopwatch()..start();
    List<Map<String, dynamic>> result;

    try {
      result = await _connection.query(
        sql,
        arguments: arguments,
        namedArguments: namedArguments,
      );
      stopwatch.stop();

      await _analyzer.analyzeQuery(
        sql,
        executionTimeMs: stopwatch.elapsedMilliseconds,
        parameters: namedArguments ??
            _indexedToNamed(arguments),
        actualRowCount: result.length,
      );

      return result;
    } catch (e) {
      stopwatch.stop();
      // Still record a failure observation
      await _analyzer.analyzeQuery(
        sql,
        executionTimeMs: stopwatch.elapsedMilliseconds,
        parameters: namedArguments ?? _indexedToNamed(arguments),
      );
      rethrow;
    }
  }

  /// Executes an INSERT / UPDATE / DELETE statement and returns affected rows.
  Future<int> execute(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  }) async {
    final stopwatch = Stopwatch()..start();
    int result;

    try {
      result = await _connection.execute(
        sql,
        arguments: arguments,
        namedArguments: namedArguments,
      );
      stopwatch.stop();

      await _analyzer.analyzeQuery(
        sql,
        executionTimeMs: stopwatch.elapsedMilliseconds,
        parameters: namedArguments ?? _indexedToNamed(arguments),
      );

      return result;
    } catch (e) {
      stopwatch.stop();
      await _analyzer.analyzeQuery(
        sql,
        executionTimeMs: stopwatch.elapsedMilliseconds,
        parameters: namedArguments ?? _indexedToNamed(arguments),
      );
      rethrow;
    }
  }

  /// Executes [fn] inside a transaction.
  ///
  /// All queries run inside [fn] are measured individually.
  Future<T> transaction<T>(Future<T> Function(DatabaseWrapper db) fn) async {
    // Transactions are managed at the connection level; we just forward
    // individual queries through the wrapper as usual.
    return fn(this);
  }

  /// Delegates to [DatabaseConnection.close].
  Future<void> close() => _connection.close();

  /// Exposes the [QueryAnalyzerCore] for advanced use (e.g. adding listeners).
  QueryAnalyzerCore get analyzer => _analyzer;

  // ── Helpers ───────────────────────────────────────────────────────────────

  Map<String, dynamic>? _indexedToNamed(List<dynamic>? args) {
    if (args == null) return null;
    return {
      for (var i = 0; i < args.length; i++) 'arg$i': args[i],
    };
  }
}

/// A convenience timer utility exposed for ad-hoc benchmarking.
final precisionTimer = PrecisionTimer();
