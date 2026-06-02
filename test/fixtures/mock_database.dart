import 'dart:async';
import '../../lib/src/wrapper/database_wrapper.dart';

/// A mock [DatabaseConnection] for testing.
///
/// Records all calls and allows configuring artificial delays and results.
class MockDatabaseConnection implements DatabaseConnection {
  /// Configurable delay applied to every query (default: 0ms).
  Duration queryDelay;

  /// Configurable delay applied to execute calls.
  Duration executeDelay;

  /// Fixed result returned by [query].
  List<Map<String, dynamic>> queryResult;

  /// Fixed affected-row count returned by [execute].
  int executeResult;

  /// If set, [query] throws this error.
  Object? throwOnQuery;

  /// If set, [execute] throws this error.
  Object? throwOnExecute;

  /// All SQL strings passed to [query], in order.
  final List<String> queryCalls = [];

  /// All SQL strings passed to [execute], in order.
  final List<String> executeCalls = [];

  bool _closed = false;

  /// Creates a [MockDatabaseConnection].
  MockDatabaseConnection({
    this.queryDelay = Duration.zero,
    this.executeDelay = Duration.zero,
    this.queryResult = const [],
    this.executeResult = 1,
    this.throwOnQuery,
    this.throwOnExecute,
  });

  @override
  String? get tag => 'mock';

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  }) async {
    queryCalls.add(sql);
    if (queryDelay > Duration.zero) await Future.delayed(queryDelay);
    if (throwOnQuery != null) throw throwOnQuery!;
    return List.of(queryResult);
  }

  @override
  Future<int> execute(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  }) async {
    executeCalls.add(sql);
    if (executeDelay > Duration.zero) await Future.delayed(executeDelay);
    if (throwOnExecute != null) throw throwOnExecute!;
    return executeResult;
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  /// Resets call history.
  void reset() {
    queryCalls.clear();
    executeCalls.clear();
    _closed = false;
  }
}

/// Creates a [MockDatabaseConnection] pre-configured to simulate a slow query
/// of [delayMs] milliseconds.
MockDatabaseConnection slowMock({int delayMs = 2000}) =>
    MockDatabaseConnection(
      queryDelay: Duration(milliseconds: delayMs),
    );

/// Creates a [MockDatabaseConnection] that always throws [StateError].
MockDatabaseConnection failingMock() => MockDatabaseConnection(
      throwOnQuery: StateError('Simulated DB error'),
    );
