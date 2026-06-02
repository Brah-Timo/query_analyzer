# API Reference

Complete reference for all public types, methods, and constants exported by
`package:query_analyzer/query_analyzer.dart`.

---

## QueryAnalyzerFacade

Top-level convenience facade. Import once and use these static helpers for
the most common workflows.

```dart
abstract final class QueryAnalyzerFacade
```

### Static members

| Member | Signature | Description |
|--------|-----------|-------------|
| `version` | `static const String` | Package version string (`'1.0.0'`). |
| `create` | `static QueryAnalyzerCore create({config, schema, onSlowQuery})` | Creates a configured `QueryAnalyzerCore`. |
| `wrap` | `static DatabaseWrapper wrap(connection, {config, schema, onSlowQuery})` | Creates a `DatabaseWrapper` in one call. |
| `generateReport` | `static AnalysisReport generateReport(core, {timeRange})` | Builds a report from stored metrics. |
| `topSlowQueries` | `static List<AnalyzedQuery> topSlowQueries(core, {n})` | Returns top-N slowest queries. |

---

## QueryAnalyzerCore

The central processing unit.  Receives query observations from wrappers,
runs all detectors, generates suggestions, stores results, and broadcasts
events.

```dart
class QueryAnalyzerCore
```

### Constructor

```dart
QueryAnalyzerCore({
  required QueryAnalyzerConfig config,
  required DatabaseSchema schema,
})
```

### Public API

| Member | Type | Description |
|--------|------|-------------|
| `config` | `QueryAnalyzerConfig` | The configuration snapshot. |
| `storage` | `MetricsStorage` | The in-memory ring-buffer storage. |
| `analyzeQuery(sql, {executionTimeMs, parameters, actualRowCount})` | `Future<AnalyzedQuery>` | Analyze one query execution. |
| `isSlowQuery(executionTimeMs)` | `bool` | `true` if above threshold. |
| `addListener(listener)` | `void` | Register a `QueryListener`. |
| `removeListener(listener)` | `void` | Unregister a listener. |
| `queryStream` | `Stream<AnalyzedQuery>` | Broadcast stream of all analyzed queries. |
| `slowQueryStream` | `Stream<AnalyzedQuery>` | Broadcast stream filtered to slow queries only. |
| `reset()` | `void` | Clears storage and N+1 history. |
| `dispose()` | `Future<void>` | Closes the stream controller. |

---

## DatabaseWrapper

Wraps a `DatabaseConnection`, intercepts every call, and forwards observations
to `QueryAnalyzerCore`.

```dart
class DatabaseWrapper
```

### Constructor

```dart
DatabaseWrapper({
  required DatabaseConnection connection,
  required QueryAnalyzerCore analyzer,
})
```

### Public API

| Member | Type | Description |
|--------|------|-------------|
| `onSlowQuery=` | `set` | Shortcut for registering a `SlowQueryCallback`. |
| `query(sql, {arguments, namedArguments})` | `Future<List<Map<String, dynamic>>>` | Measured SELECT. |
| `execute(sql, {arguments, namedArguments})` | `Future<int>` | Measured DML. |
| `transaction(fn)` | `Future<T>` | Runs `fn(this)` inside a conceptual transaction. |
| `close()` | `Future<void>` | Closes the underlying connection. |
| `analyzer` | `QueryAnalyzerCore` | The backing analyzer instance. |

---

## DatabaseConnection (interface)

```dart
abstract class DatabaseConnection {
  Future<List<Map<String, dynamic>>> query(String sql, {List? arguments, Map<String, dynamic>? namedArguments});
  Future<int> execute(String sql, {List? arguments, Map<String, dynamic>? namedArguments});
  Future<void> close();
  String? get tag => null;  // optional label
}
```

---

## QueryWrapper

Measures a single ad-hoc query without replacing an entire connection.

```dart
class QueryWrapper {
  static Future<T> measure<T>({
    required String sql,
    required QueryAnalyzerCore analyzer,
    required Future<T> Function() execute,
    Map<String, dynamic>? parameters,
  });
}
```

---

## ConnectionPoolWrapper

Round-robin distribution across a pool of `DatabaseWrapper` connections.

```dart
class ConnectionPoolWrapper {
  ConnectionPoolWrapper({
    required List<DatabaseConnection> connections,
    required QueryAnalyzerCore analyzer,
  });

  DatabaseWrapper get next;
  Future<List<Map<String, dynamic>>> query(String sql, {...});
  Future<int> execute(String sql, {...});
  int get size;
  Future<void> closeAll();
}
```

---

## QueryAnalyzerConfig

Immutable configuration value object.

```dart
const QueryAnalyzerConfig()                   // all defaults
const QueryAnalyzerConfig.custom({...})       // override specific fields
QueryAnalyzerConfig copyWith({...})           // copy with overrides
```

### Key fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `slowQueryThresholdMs` | `int` | `1000` | Queries above this are "slow". |
| `logAllQueries` | `bool` | `false` | Log every query, not just slow ones. |
| `maskSensitiveValues` | `bool` | `true` | Replace string literals with `***` in logs. |
| `maxStoredQueries` | `int` | `500` | Ring-buffer capacity. |
| `persistMetrics` | `bool` | `false` | Write to local JSONL file. |
| `detectFullTableScan` | `bool` | `true` | Enable full-table-scan detector. |
| `detectMissingIndex` | `bool` | `true` | Enable missing-index detector. |
| `detectNPlusOne` | `bool` | `true` | Enable N+1 detector. |
| `detectLargeResult` | `bool` | `true` | Enable large-result detector. |
| `detectSubqueryIssues` | `bool` | `true` | Enable sub-query detector. |
| `detectSelectStar` | `bool` | `true` | Enable SELECT * detector. |
| `nPlusOneWindowMs` | `int` | `5000` | Sliding window for N+1 detection (ms). |
| `nPlusOneMinCount` | `int` | `5` | Repetitions before N+1 is flagged. |
| `largeResultRowThreshold` | `int` | `10000` | Rows above which result is "large". |
| `databaseTag` | `String?` | `null` | Label attached to every `AnalyzedQuery`. |
| `schemaRefreshIntervalMinutes` | `int` | `60` | How often to re-introspect the schema. |

---

## AnalyzedQuery

The complete record of one query execution.

```dart
@immutable
class AnalyzedQuery {
  final String id;                        // UUID v4
  final String originalQuery;             // possibly masked
  final int executionTimeMs;
  final DateTime executedAt;
  final ParsedQuery parsed;               // structural breakdown
  final DetectionResult detectionResult;  // all issues found
  final List<QuerySuggestion> suggestions;
  final bool isSlowQuery;
  final String? databaseTag;
  final Map<String, String>? maskedParameters;
  late final int impactScore;             // 0-100 composite score

  Map<String, dynamic> toJson();
}
```

---

## ParsedQuery

Structural breakdown of a SQL statement.

```dart
@immutable
class ParsedQuery {
  final QueryType type;
  final List<String> tables;
  final List<String> selectedColumns;
  final List<WhereClause> whereClauses;
  final List<JoinClause> joins;
  final bool hasGroupBy;
  final bool hasOrderBy;
  final bool hasSubquery;
  final int subqueryDepth;
  final bool hasDistinct;
  final bool hasAggregates;
  final int? limit;
  final int? offset;
  final String normalizedQuery;

  bool get lacksWhereClause;  // SELECT with no WHERE
  bool get selectsStar;       // columns is ['*'] or empty
}
```

### QueryType

`select` | `insert` | `update` | `delete` | `ddl` | `other`

---

## DetectionResult

Aggregated output from all detectors.

```dart
@immutable
class DetectionResult {
  final List<QueryIssue> issues;

  bool get hasIssues;
  int get severityScore;          // sum of issue weights
  IssueSeverity? get maxSeverity;
  Map<String, dynamic> toJson();
}
```

---

## QueryIssue

A single detected problem.

```dart
@immutable
class QueryIssue {
  final IssueType type;
  final String description;
  final IssueSeverity severity;
  final String affectedElement;
}
```

### IssueType

| Value | Description |
|-------|-------------|
| `fullTableScan` | Sequential scan on a large table. |
| `missingIndex` | WHERE / JOIN column lacks an index. |
| `nPlusOne` | Same query repeated N times in a short window. |
| `largeResult` | Unbounded / huge result set. |
| `subqueryIssue` | Correlated or deeply nested sub-query. |
| `inefficientJoin` | Cartesian product or missing ON condition. |
| `selectStar` | `SELECT *` fetches unnecessary columns. |
| `unindexedOrderBy` | ORDER BY on un-indexed column. |
| `expensiveAggregate` | Aggregate without GROUP BY on large table. |

### IssueSeverity

`low` (weight 1) | `medium` (5) | `high` (10) | `critical` (20)

---

## QuerySuggestion

An actionable recommendation.

```dart
@immutable
class QuerySuggestion {
  final SuggestionType type;
  final String title;
  final String description;
  final String? sqlStatement;
  final int? estimatedImprovementPercent;
  final SuggestionPriority priority;
  final String? documentationUrl;

  // Factory constructors
  factory QuerySuggestion.addIndex({required String table, required String column, int? estimatedImprovementPercent});
  factory QuerySuggestion.addPagination({String? table});
  factory QuerySuggestion.refactorNPlusOne({String? relatedTable});
  factory QuerySuggestion.generic(String message, {SuggestionPriority priority});
}
```

### SuggestionType

`addIndex` | `removeRedundantColumns` | `refactorQuery` | `addPagination` |
`optimizeJoin` | `rewriteSubquery` | `addCaching` | `partitionTable` |
`useCoveringIndex` | `updateStatistics` | `other`

### SuggestionPriority

`low` | `medium` | `high` | `critical`

---

## AnalysisReport

Time-boxed aggregated report produced by `ReportGenerator`.

```dart
@immutable
class AnalysisReport {
  final DateTime generatedAt;
  final Duration timeRange;
  final int totalQueries;
  final List<AnalyzedQuery> slowQueries;
  final double averageExecutionTimeMs;
  final double medianExecutionTimeMs;
  final double p95ExecutionTimeMs;
  final double p99ExecutionTimeMs;
  final List<AnalyzedQuery> topSlowQueries;
  final Map<IssueType, int> commonIssues;
  final List<PerformanceMetric> patternMetrics;
  final List<String> recommendations;
  final int totalErrors;
  final double errorRate;

  double get slowQueryRate;
  List<QuerySuggestion> get topSuggestions;  // top 5
  String get summary;                         // plain-text summary
  Map<String, dynamic> toJson();
}
```

---

## ReportGenerator

```dart
class ReportGenerator {
  const ReportGenerator(MetricsStorage storage);

  AnalysisReport generateReport({Duration timeRange = const Duration(hours: 24)});
}
```

---

## ReportExporter

Static export methods for `AnalysisReport`.

```dart
abstract final class ReportExporter {
  static String toJson(AnalysisReport report);
  static String toCsv(AnalysisReport report);
  static String toHtml(AnalysisReport report);
  static String toMarkdown(AnalysisReport report);
}
```

---

## PerformanceMetric

Aggregated statistics per normalized query pattern.

```dart
@immutable
class PerformanceMetric {
  final String queryPattern;
  final double totalExecutionTimeMs;
  final int executionCount;
  final int minExecutionTimeMs;
  final int maxExecutionTimeMs;
  final double averageExecutionTimeMs;
  final Map<int, double> percentiles;   // keys: 50, 75, 90, 95, 99
  final int errorCount;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;

  double get stdDevMs;
  double get errorRate;

  factory PerformanceMetric.fromFirstObservation({required String queryPattern, required int executionTimeMs, bool isError});
  PerformanceMetric withNewObservation(int executionTimeMs, {bool isError});
}
```

---

## MetricsStorage

In-memory ring-buffer for `AnalyzedQuery` records.

```dart
class MetricsStorage {
  MetricsStorage(QueryAnalyzerConfig config);

  Future<void> store(AnalyzedQuery query);
  List<AnalyzedQuery> getAll();
  List<AnalyzedQuery> getSlowQueries();
  List<AnalyzedQuery> getSince(DateTime since);
  PerformanceMetric? getMetricForPattern(String normalizedPattern);
  List<PerformanceMetric> getAllMetrics();
  DailySummary getDailySummary();
  String exportJson();
  void reset();
  int get size;
}
```

---

## AlertManager

```dart
class AlertManager implements QueryListener {
  AlertManager({
    required List<AlertChannel> channels,
    ThresholdConfig thresholds = const ThresholdConfig(),
  });

  void addChannel(AlertChannel channel);
  void removeChannel(String channelName);
  List<String> get channelNames;
}
```

---

## Alert Channels

| Class | Description |
|-------|-------------|
| `ConsoleAlertChannel` | Prints to stdout. |
| `LoggingAlertChannel` | Routes to `QaLogger.warn()`. |
| `SlackAlertChannel({webhookUrl, channel?})` | Posts to a Slack webhook. |
| `WebhookAlertChannel({url, headers, name})` | Posts JSON to any HTTP endpoint. |

---

## ThresholdConfig

```dart
const ThresholdConfig({
  int slowQueryMs = 1000,
  double slowQueryRatePercent = 10.0,
  double errorRatePercent = 5.0,
  Duration rollingWindow = const Duration(minutes: 5),
  Duration alertCooldown = const Duration(minutes: 15),
});

static const ThresholdConfig production;
static const ThresholdConfig development;
```

---

## Constants (`lib/constants.dart`)

| Constant | Value | Description |
|----------|-------|-------------|
| `kPackageVersion` | `'1.0.0'` | Package version. |
| `kDefaultSlowQueryThresholdMs` | `1000` | Default slow-query threshold. |
| `kDefaultMaxStoredQueries` | `500` | Default ring-buffer size. |
| `kNPlusOneWindowMs` | `5000` | Default N+1 detection window. |
| `kNPlusOneMinCount` | `5` | Default N+1 min repetitions. |
| `kLargeResultRowThreshold` | `10000` | Default large-result threshold. |
| `kMaxSubqueryDepth` | `3` | Max allowed sub-query nesting. |
| `kTrackedPercentiles` | `[50, 75, 90, 95, 99]` | Percentiles tracked per pattern. |
| `kWebhookTimeoutSeconds` | `10` | HTTP timeout for alert webhooks. |
| `kLogTag` | `'QueryAnalyzer'` | Logger tag. |

---

## Exceptions

| Class | Description |
|-------|-------------|
| `AnalyzerException` | Base class for all package exceptions. |
| `ConfigurationException` | Invalid `QueryAnalyzerConfig`. |
| `DatabaseIntrospectionException` | Schema introspection failure. |
| `QueryParseException` | SQL parsing failure. |
| `MetricsStorageException` | Storage read/write failure. |
| `AlertDeliveryException` | Alert delivery failure. |
| `ReportExportException` | Report export failure. |

---

## ParserUtils

Static SQL parsing helpers (used internally and available publicly).

```dart
abstract final class ParserUtils {
  static String normalize(String sql);                        // replace literals with ?
  static bool containsKeyword(String sql, String keyword);
  static List<String> extractTableNames(String sql);
  static List<String> extractWhereColumns(String sql);
  static int? extractLimit(String sql);
  static int? extractOffset(String sql);
  static int subqueryDepth(String sql);
  static String maskSensitiveValues(String sql);
  static String fingerprint(String normalizedSql);            // 8-char hex hash
}
```

---

## QaLogger

```dart
class QaLogger {
  static void enableConsoleOutput({Level level = Level.INFO});
  static void debug(String message);
  static void info(String message);
  static void warn(String message);
  static void error(String message, [Object? error, StackTrace? stackTrace]);
  static void slowQuery(String query, int ms);
  static Logger get logger;
}
```

---

## PrecisionTimer

```dart
class PrecisionTimer {
  void start();
  int lap();
  void stop();
  int get elapsedMs;
  int get elapsedUs;
  int get elapsedNs;
  List<int> get laps;
  void reset();

  static Future<int> measure(Future<void> Function() fn);
  static Future<(T result, int elapsedMs)> measureWithResult<T>(Future<T> Function() fn);
}
```
