import 'analyzer_exception.dart';

/// Thrown when the [QueryAnalyzerConfig] is invalid or incomplete.
class ConfigurationException extends AnalyzerException {
  /// The name of the configuration field that caused the issue.
  final String? fieldName;

  /// The invalid value (as a string representation).
  final String? invalidValue;

  /// Creates a [ConfigurationException].
  const ConfigurationException(
    super.message, {
    this.fieldName,
    this.invalidValue,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('ConfigurationException: $message');
    if (fieldName != null) buffer.write('\n  Field : $fieldName');
    if (invalidValue != null) buffer.write('\n  Value : $invalidValue');
    if (cause != null) buffer.write('\n  Caused by: $cause');
    return buffer.toString();
  }
}
