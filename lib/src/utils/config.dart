import 'package:meta/meta.dart';
import '../../constants.dart';
import '../exceptions/configuration_exception.dart';

/// Configuration for the Query Analyzer.
///
/// All fields have sensible defaults that work out-of-the-box.
/// Use [QueryAnalyzerConfig.custom] to override individual options.
@immutable
class QueryAnalyzerConfig {
  // ── Slow-query detection ──────────────────────────────────────────────────

  /// Queries whose execution time exceeds this value are flagged as slow.
  ///
  /// Defaults to [kDefaultSlowQueryThresholdMs] (1 000 ms).
  final int slowQueryThresholdMs;

  // ── Logging ───────────────────────────────────────────────────────────────

  /// If `true`, every query (not just slow ones) is logged.
  final bool logAllQueries;

  /// If `true`, sensitive values in query strings are masked before logging.
  final bool maskSensitiveValues;

  // ── Storage ───────────────────────────────────────────────────────────────

  /// Maximum number of [AnalyzedQuery] objects kept in the in-memory ring
  /// buffer.
  ///
  /// Defaults to [kDefaultMaxStoredQueries] (500).
  final int maxStoredQueries;

  /// If `true`, metrics are persisted to a local SQLite database
  /// ([kLocalMetricsDbName]).
  final bool persistMetrics;

  /// Directory where the local metrics SQLite file is stored.
  /// Defaults to the current working directory.
  final String? metricsStoragePath;

  /// How many days of metrics to retain before auto-pruning.
  final int metricsRetentionDays;

  // ── Detection toggles ─────────────────────────────────────────────────────

  /// Enable full-table-scan detection.
  final bool detectFullTableScan;

  /// Enable missing-index detection.
  final bool detectMissingIndex;

  /// Enable N+1 query-pattern detection.
  final bool detectNPlusOne;

  /// Enable large-result-set detection.
  final bool detectLargeResult;

  /// Enable sub-query issue detection.
  final bool detectSubqueryIssues;

  /// Enable SELECT * detection.
  final bool detectSelectStar;

  // ── N+1 tuning ────────────────────────────────────────────────────────────

  /// Time window (ms) in which repeated similar queries are counted for N+1.
  final int nPlusOneWindowMs;

  /// Minimum occurrences of a similar query within the window to flag N+1.
  final int nPlusOneMinCount;

  // ── Large-result tuning ───────────────────────────────────────────────────

  /// Row count above which a result set is considered "large".
  final int largeResultRowThreshold;

  // ── Database tag ─────────────────────────────────────────────────────────

  /// Optional label attached to every [AnalyzedQuery] produced by a
  /// [DatabaseWrapper] using this config (e.g. `"primary"`, `"replica"`).
  final String? databaseTag;

  // ── Schema refresh ────────────────────────────────────────────────────────

  /// How often (minutes) the database schema is re-introspected.
  /// `0` means "never refresh after the initial load".
  final int schemaRefreshIntervalMinutes;

  /// Creates a [QueryAnalyzerConfig] with all default values.
  const QueryAnalyzerConfig()
      : slowQueryThresholdMs = kDefaultSlowQueryThresholdMs,
        logAllQueries = false,
        maskSensitiveValues = true,
        maxStoredQueries = kDefaultMaxStoredQueries,
        persistMetrics = false,
        metricsStoragePath = null,
        metricsRetentionDays = kMetricsRetentionDays,
        detectFullTableScan = true,
        detectMissingIndex = true,
        detectNPlusOne = true,
        detectLargeResult = true,
        detectSubqueryIssues = true,
        detectSelectStar = true,
        nPlusOneWindowMs = kNPlusOneWindowMs,
        nPlusOneMinCount = kNPlusOneMinCount,
        largeResultRowThreshold = kLargeResultRowThreshold,
        databaseTag = null,
        schemaRefreshIntervalMinutes = 60;

  /// Creates a customised config by specifying only the fields to override.
  const QueryAnalyzerConfig.custom({
    this.slowQueryThresholdMs = kDefaultSlowQueryThresholdMs,
    this.logAllQueries = false,
    this.maskSensitiveValues = true,
    this.maxStoredQueries = kDefaultMaxStoredQueries,
    this.persistMetrics = false,
    this.metricsStoragePath,
    this.metricsRetentionDays = kMetricsRetentionDays,
    this.detectFullTableScan = true,
    this.detectMissingIndex = true,
    this.detectNPlusOne = true,
    this.detectLargeResult = true,
    this.detectSubqueryIssues = true,
    this.detectSelectStar = true,
    this.nPlusOneWindowMs = kNPlusOneWindowMs,
    this.nPlusOneMinCount = kNPlusOneMinCount,
    this.largeResultRowThreshold = kLargeResultRowThreshold,
    this.databaseTag,
    this.schemaRefreshIntervalMinutes = 60,
  });

  /// Validates the config and throws [ConfigurationException] if invalid.
  void validate() {
    if (slowQueryThresholdMs < 1) {
      throw ConfigurationException(
        'slowQueryThresholdMs must be >= 1',
        fieldName: 'slowQueryThresholdMs',
        invalidValue: slowQueryThresholdMs.toString(),
      );
    }
    if (maxStoredQueries < 10) {
      throw ConfigurationException(
        'maxStoredQueries must be >= 10',
        fieldName: 'maxStoredQueries',
        invalidValue: maxStoredQueries.toString(),
      );
    }
    if (metricsRetentionDays < 1) {
      throw ConfigurationException(
        'metricsRetentionDays must be >= 1',
        fieldName: 'metricsRetentionDays',
        invalidValue: metricsRetentionDays.toString(),
      );
    }
    if (nPlusOneWindowMs < 100) {
      throw ConfigurationException(
        'nPlusOneWindowMs must be >= 100',
        fieldName: 'nPlusOneWindowMs',
        invalidValue: nPlusOneWindowMs.toString(),
      );
    }
    if (nPlusOneMinCount < 2) {
      throw ConfigurationException(
        'nPlusOneMinCount must be >= 2',
        fieldName: 'nPlusOneMinCount',
        invalidValue: nPlusOneMinCount.toString(),
      );
    }
    if (largeResultRowThreshold < 100) {
      throw ConfigurationException(
        'largeResultRowThreshold must be >= 100',
        fieldName: 'largeResultRowThreshold',
        invalidValue: largeResultRowThreshold.toString(),
      );
    }
  }

  /// Returns a copy with the given fields overridden.
  QueryAnalyzerConfig copyWith({
    int? slowQueryThresholdMs,
    bool? logAllQueries,
    bool? maskSensitiveValues,
    int? maxStoredQueries,
    bool? persistMetrics,
    String? metricsStoragePath,
    int? metricsRetentionDays,
    bool? detectFullTableScan,
    bool? detectMissingIndex,
    bool? detectNPlusOne,
    bool? detectLargeResult,
    bool? detectSubqueryIssues,
    bool? detectSelectStar,
    int? nPlusOneWindowMs,
    int? nPlusOneMinCount,
    int? largeResultRowThreshold,
    String? databaseTag,
    int? schemaRefreshIntervalMinutes,
  }) =>
      QueryAnalyzerConfig.custom(
        slowQueryThresholdMs:
            slowQueryThresholdMs ?? this.slowQueryThresholdMs,
        logAllQueries: logAllQueries ?? this.logAllQueries,
        maskSensitiveValues: maskSensitiveValues ?? this.maskSensitiveValues,
        maxStoredQueries: maxStoredQueries ?? this.maxStoredQueries,
        persistMetrics: persistMetrics ?? this.persistMetrics,
        metricsStoragePath: metricsStoragePath ?? this.metricsStoragePath,
        metricsRetentionDays:
            metricsRetentionDays ?? this.metricsRetentionDays,
        detectFullTableScan: detectFullTableScan ?? this.detectFullTableScan,
        detectMissingIndex: detectMissingIndex ?? this.detectMissingIndex,
        detectNPlusOne: detectNPlusOne ?? this.detectNPlusOne,
        detectLargeResult: detectLargeResult ?? this.detectLargeResult,
        detectSubqueryIssues:
            detectSubqueryIssues ?? this.detectSubqueryIssues,
        detectSelectStar: detectSelectStar ?? this.detectSelectStar,
        nPlusOneWindowMs: nPlusOneWindowMs ?? this.nPlusOneWindowMs,
        nPlusOneMinCount: nPlusOneMinCount ?? this.nPlusOneMinCount,
        largeResultRowThreshold:
            largeResultRowThreshold ?? this.largeResultRowThreshold,
        databaseTag: databaseTag ?? this.databaseTag,
        schemaRefreshIntervalMinutes:
            schemaRefreshIntervalMinutes ?? this.schemaRefreshIntervalMinutes,
      );

  @override
  String toString() => 'QueryAnalyzerConfig('
      'threshold: ${slowQueryThresholdMs}ms, '
      'persist: $persistMetrics, '
      'n+1: $detectNPlusOne)';
}
