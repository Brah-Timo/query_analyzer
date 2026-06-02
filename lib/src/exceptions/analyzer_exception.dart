/// Base exception for all Query Analyzer errors.
class AnalyzerException implements Exception {
  /// Human-readable message.
  final String message;

  /// Optional cause exception.
  final Object? cause;

  /// Stack trace at the point of creation.
  final StackTrace? stackTrace;

  /// Creates an [AnalyzerException].
  const AnalyzerException(
    this.message, {
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('AnalyzerException: $message');
    if (cause != null) buffer.write('\n  Caused by: $cause');
    if (stackTrace != null) buffer.write('\n$stackTrace');
    return buffer.toString();
  }
}

/// Thrown when the analyzer cannot connect to or introspect the database.
class DatabaseIntrospectionException extends AnalyzerException {
  /// Creates a [DatabaseIntrospectionException].
  const DatabaseIntrospectionException(
    super.message, {
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => 'DatabaseIntrospectionException: $message'
      '${cause != null ? "\n  Caused by: $cause" : ""}';
}

/// Thrown when the analyzer fails to parse a SQL statement.
class QueryParseException extends AnalyzerException {
  /// The raw SQL string that could not be parsed.
  final String sql;

  /// Creates a [QueryParseException].
  const QueryParseException(
    super.message, {
    required this.sql,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => 'QueryParseException: $message\n  SQL: $sql'
      '${cause != null ? "\n  Caused by: $cause" : ""}';
}

/// Thrown when the local metrics storage encounters an error.
class MetricsStorageException extends AnalyzerException {
  /// Creates a [MetricsStorageException].
  const MetricsStorageException(
    super.message, {
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => 'MetricsStorageException: $message'
      '${cause != null ? "\n  Caused by: $cause" : ""}';
}

/// Thrown when an alert cannot be delivered to its destination channel.
class AlertDeliveryException extends AnalyzerException {
  /// The alert channel identifier that failed.
  final String channel;

  /// Creates an [AlertDeliveryException].
  const AlertDeliveryException(
    super.message, {
    required this.channel,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() =>
      'AlertDeliveryException[$channel]: $message'
      '${cause != null ? "\n  Caused by: $cause" : ""}';
}

/// Thrown when a report export fails.
class ReportExportException extends AnalyzerException {
  /// The target format that failed (e.g. "pdf", "html").
  final String format;

  /// Creates a [ReportExportException].
  const ReportExportException(
    super.message, {
    required this.format,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() =>
      'ReportExportException[$format]: $message'
      '${cause != null ? "\n  Caused by: $cause" : ""}';
}
