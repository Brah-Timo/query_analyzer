import '../models/analyzed_query.dart';
import '../utils/parser_utils.dart';

/// A lightweight in-memory record used by [NPlusOneDetector].
class _QueryRecord {
  final String fingerprint;
  final DateTime seenAt;
  _QueryRecord(this.fingerprint, this.seenAt);
}

/// Detects N+1 query patterns by tracking similar queries executed within a
/// short time window.
///
/// An N+1 pattern is flagged when the same *normalized* query fingerprint
/// appears [minCount] or more times within [windowMs] milliseconds.
class NPlusOneDetector {
  /// Sliding time window in milliseconds.
  final int windowMs;

  /// Minimum occurrences to flag a pattern.
  final int minCount;

  final List<_QueryRecord> _history = [];

  /// Creates an [NPlusOneDetector].
  NPlusOneDetector({
    required this.windowMs,
    required this.minCount,
  });

  /// Records an observation and returns a [QueryIssue] if N+1 is detected,
  /// or `null` otherwise.
  QueryIssue? observe(String sql) {
    final fp = ParserUtils.fingerprint(ParserUtils.normalize(sql));
    final now = DateTime.now();

    // Prune old records outside the window
    _history.removeWhere(
      (r) => now.difference(r.seenAt).inMilliseconds > windowMs,
    );

    _history.add(_QueryRecord(fp, now));

    // Count occurrences of this fingerprint in the current window
    final count = _history.where((r) => r.fingerprint == fp).length;

    if (count >= minCount) {
      return QueryIssue(
        type: IssueType.nPlusOne,
        description:
            'Query fingerprint "$fp" has been executed $count times '
            'within ${windowMs}ms — this looks like an N+1 pattern.',
        severity: count > minCount * 3
            ? IssueSeverity.critical
            : IssueSeverity.high,
        affectedElement: fp,
      );
    }

    return null;
  }

  /// Clears the observation history (useful in tests).
  void reset() => _history.clear();
}
