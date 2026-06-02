import '../analyzer/query_analyzer_core.dart';
import 'database_wrapper.dart';

/// Wraps a pool of [DatabaseConnection]s, distributing query measurements
/// across all pool members.
///
/// Use this when your application manages multiple connections (e.g. a
/// read-replica pool).
class ConnectionPoolWrapper {
  final List<DatabaseWrapper> _wrappers;
  int _roundRobinIndex = 0;

  /// Creates a [ConnectionPoolWrapper] from a list of [DatabaseConnection]s
  /// and a shared [QueryAnalyzerCore].
  ConnectionPoolWrapper({
    required List<DatabaseConnection> connections,
    required QueryAnalyzerCore analyzer,
  }) : _wrappers = connections
            .map((c) => DatabaseWrapper(connection: c, analyzer: analyzer))
            .toList();

  /// Returns the next [DatabaseWrapper] using round-robin selection.
  DatabaseWrapper get next {
    final wrapper = _wrappers[_roundRobinIndex % _wrappers.length];
    _roundRobinIndex++;
    return wrapper;
  }

  /// Executes a query on the next wrapper in the rotation.
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  }) =>
      next.query(sql, arguments: arguments, namedArguments: namedArguments);

  /// Executes a write statement on the next wrapper.
  Future<int> execute(
    String sql, {
    List<dynamic>? arguments,
    Map<String, dynamic>? namedArguments,
  }) =>
      next.execute(sql, arguments: arguments, namedArguments: namedArguments);

  /// Number of connections in the pool.
  int get size => _wrappers.length;

  /// Closes all connections.
  Future<void> closeAll() async {
    for (final w in _wrappers) {
      await w.close();
    }
  }
}
