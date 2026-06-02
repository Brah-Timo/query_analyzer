/// Global constants for the Query Analyzer package.
library query_analyzer.constants;

/// Current package version.
const String kPackageVersion = '1.0.0';

/// Default threshold (ms) above which a query is considered slow.
const int kDefaultSlowQueryThresholdMs = 1000;

/// Default number of recent queries kept in memory.
const int kDefaultMaxStoredQueries = 500;

/// Default time window (minutes) used in N+1 detection.
const int kNPlusOneWindowMs = 5000;

/// Minimum number of similar queries within the window to flag N+1.
const int kNPlusOneMinCount = 5;

/// Default row-count threshold to flag a "large result set".
const int kLargeResultRowThreshold = 10000;

/// Default maximum depth for sub-query nesting checks.
const int kMaxSubqueryDepth = 3;

/// Log tag used throughout the package.
const String kLogTag = 'QueryAnalyzer';

/// SQLite local metrics database name.
const String kLocalMetricsDbName = 'query_analyzer_metrics.db';

/// Metrics table name in local SQLite.
const String kMetricsTableName = 'analyzed_queries';

/// Maximum age (days) of stored metrics before auto-pruning.
const int kMetricsRetentionDays = 30;

/// HTTP timeout (seconds) for webhook alert delivery.
const int kWebhookTimeoutSeconds = 10;

/// Percentiles calculated for execution-time distribution.
const List<int> kTrackedPercentiles = [50, 75, 90, 95, 99];

/// Regex that matches SQL string literals (single-quoted).
const String kStrLiteralPattern = r"'(?:[^'\\]|\\.)*'";

/// Regex that matches SQL numeric literals.
const String kNumLiteralPattern = r'\b\d+(\.\d+)?\b';

/// Regex that matches email addresses for PII masking.
const String kEmailPattern =
    r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b';

/// Regex that matches IPv4 addresses for PII masking.
const String kIpv4Pattern =
    r'\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b';

/// SQL keywords that hint at a full-table scan when no WHERE clause is present.
const List<String> kFullScanKeywords = [
  'SELECT',
  'UPDATE',
  'DELETE',
  'FROM',
];

/// SQL aggregate functions tracked for expensive computation detection.
const List<String> kAggregateFunctions = [
  'COUNT',
  'SUM',
  'AVG',
  'MIN',
  'MAX',
  'GROUP_CONCAT',
  'STRING_AGG',
  'ARRAY_AGG',
  'JSONB_AGG',
];
