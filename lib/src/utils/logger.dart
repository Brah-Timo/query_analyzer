import 'package:logging/logging.dart';
import '../../constants.dart';

/// Central logger for the Query Analyzer package.
///
/// Wraps Dart's [logging] package with a fixed tag and convenience methods.
/// Users can configure the root logger's level / output independently.
class QaLogger {
  QaLogger._();

  static final Logger _log = Logger(kLogTag);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Configures the package logger for standard console output.
  ///
  /// Call once during initialization if you want automatic printing.
  static void enableConsoleOutput({Level level = Level.INFO}) {
    Logger.root.level = level;
    Logger.root.onRecord.listen((record) {
      final prefix = '[${record.level.name}] ${record.time.toIso8601String()} '
          '[$kLogTag]';
      // ignore: avoid_print
      print('$prefix ${record.message}');
      if (record.error != null) {
        // ignore: avoid_print
        print('  ERROR: ${record.error}');
      }
      if (record.stackTrace != null) {
        // ignore: avoid_print
        print('  STACK: ${record.stackTrace}');
      }
    });
  }

  // ── Convenience wrappers ──────────────────────────────────────────────────

  /// Log a debug message.
  static void debug(String message) => _log.fine(message);

  /// Log an informational message.
  static void info(String message) => _log.info(message);

  /// Log a warning.
  static void warn(String message) => _log.warning(message);

  /// Log an error with optional exception and stack trace.
  static void error(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) =>
      _log.severe(message, error, stackTrace);

  /// Log a slow-query warning.
  static void slowQuery(String query, int ms) =>
      _log.warning('SLOW QUERY (${ms}ms): '
          '${query.length > 120 ? "${query.substring(0, 117)}..." : query}');

  /// Expose the underlying [Logger] for custom handlers.
  static Logger get logger => _log;
}
