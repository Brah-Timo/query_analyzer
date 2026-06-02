import '../models/analyzed_query.dart';
import '../models/database_schema.dart';
import '../utils/config.dart';
import '../detectors/full_table_scan_detector.dart';
import '../detectors/missing_index_detector.dart';
import '../detectors/n_plus_one_detector.dart';
import '../detectors/large_result_detector.dart';
import '../detectors/subquery_detector.dart';

/// Orchestrates all detectors and produces a unified [DetectionResult].
class PatternDetector {
  final FullTableScanDetector _scanDetector;
  final MissingIndexDetector _indexDetector;
  final NPlusOneDetector _nPlusOneDetector;
  final LargeResultDetector _largeResultDetector;
  final SubqueryDetector _subqueryDetector;
  final QueryAnalyzerConfig _config;

  /// Creates a [PatternDetector] from a [schema] and [config].
  PatternDetector({
    required DatabaseSchema schema,
    required QueryAnalyzerConfig config,
  })  : _scanDetector = FullTableScanDetector(schema: schema),
        _indexDetector = MissingIndexDetector(schema: schema),
        _nPlusOneDetector = NPlusOneDetector(
          windowMs: config.nPlusOneWindowMs,
          minCount: config.nPlusOneMinCount,
        ),
        _largeResultDetector =
            LargeResultDetector(rowThreshold: config.largeResultRowThreshold),
        _subqueryDetector = const SubqueryDetector(),
        _config = config;

  /// Runs all enabled detectors on [parsed] / [rawSql] and returns
  /// aggregated results.
  ///
  /// [actualRowCount] is optionally supplied after query execution for
  /// precise large-result detection.
  DetectionResult detect(
    ParsedQuery parsed,
    String rawSql, {
    int? actualRowCount,
  }) {
    final issues = <QueryIssue>[];

    if (_config.detectFullTableScan) {
      issues.addAll(_scanDetector.detect(parsed));
    }

    if (_config.detectMissingIndex) {
      issues.addAll(_indexDetector.detect(parsed));
    }

    if (_config.detectNPlusOne) {
      final nPlusOneIssue = _nPlusOneDetector.observe(rawSql);
      if (nPlusOneIssue != null) issues.add(nPlusOneIssue);
    }

    if (_config.detectLargeResult) {
      issues.addAll(
        _largeResultDetector.detect(parsed, actualRowCount: actualRowCount),
      );
    }

    if (_config.detectSubqueryIssues) {
      issues.addAll(_subqueryDetector.detect(parsed, rawSql));
    }

    // Deduplicate issues with identical type + affectedElement
    final seen = <String>{};
    final unique = issues
        .where((i) => seen.add('${i.type.name}::${i.affectedElement}'))
        .toList();

    return DetectionResult(issues: unique);
  }

  /// Resets the N+1 detector's observation window (useful in tests).
  void resetNPlusOneHistory() => _nPlusOneDetector.reset();
}
