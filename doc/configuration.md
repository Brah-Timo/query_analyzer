# Configuration

`QueryAnalyzerConfig` is the single configuration object for the entire
package.  It is **immutable** — create it once and pass it to
`QueryAnalyzerCore` (or `QueryAnalyzerFacade.create`).

---

## Constructors

### Default config

```dart
const config = QueryAnalyzerConfig();
```

All fields take their documented default values.

### Custom config

```dart
final config = QueryAnalyzerConfig.custom(
  slowQueryThresholdMs: 200,
  detectNPlusOne: true,
  nPlusOneMinCount: 3,
  maskSensitiveValues: false,
  databaseTag: 'primary',
);
```

Only the fields you specify are overridden; everything else stays at its default.

### Copy-with

```dart
final prod = config.copyWith(
  persistMetrics: true,
  metricsStoragePath: '/var/data/metrics',
  metricsRetentionDays: 90,
);
```

---

## All Configuration Fields

### Slow-Query Detection

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `slowQueryThresholdMs` | `int` | `1000` | Queries whose execution time (ms) exceeds this value are flagged as slow and trigger `onSlowQuery` callbacks. Set lower in development (`200`) for earlier feedback. |

### Logging

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `logAllQueries` | `bool` | `false` | Log every query at DEBUG level, not just slow ones. Useful during development but very verbose in production. |
| `maskSensitiveValues` | `bool` | `true` | Replace string literals, email addresses, and IPv4 addresses in queries before logging. Keeps PII out of log files. |

### Storage

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `maxStoredQueries` | `int` | `500` | Maximum number of `AnalyzedQuery` objects kept in the in-memory ring-buffer. When the buffer is full the oldest entry is evicted. |
| `persistMetrics` | `bool` | `false` | If `true`, every stored query is also written to the local JSONL file. |
| `metricsStoragePath` | `String?` | `null` | Directory for the metrics JSONL file. Defaults to the current working directory. |
| `metricsRetentionDays` | `int` | `30` | Records older than this many days are pruned on the next maintenance cycle. |

### Detection Toggles

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `detectFullTableScan` | `bool` | `true` | Enable `FullTableScanDetector` — flags queries with no WHERE clause or WHERE on un-indexed columns. |
| `detectMissingIndex` | `bool` | `true` | Enable `MissingIndexDetector` — flags WHERE / JOIN columns that lack an index. |
| `detectNPlusOne` | `bool` | `true` | Enable `NPlusOneDetector` — flags repeated similar queries within a time window. |
| `detectLargeResult` | `bool` | `true` | Enable `LargeResultDetector` — flags queries likely to return huge result sets. |
| `detectSubqueryIssues` | `bool` | `true` | Enable `SubqueryDetector` — flags correlated or deeply nested sub-queries. |
| `detectSelectStar` | `bool` | `true` | Enable SELECT * detection inside `LargeResultDetector`. |

### N+1 Tuning

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `nPlusOneWindowMs` | `int` | `5000` | Sliding time window (milliseconds) in which repeated queries are counted. |
| `nPlusOneMinCount` | `int` | `5` | Number of identical fingerprint occurrences within the window before flagging. |

### Large-Result Tuning

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `largeResultRowThreshold` | `int` | `10000` | Row count above which a result is considered large (when actual row count is available post-execution). |

### Labelling

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `databaseTag` | `String?` | `null` | Arbitrary label attached to every `AnalyzedQuery.databaseTag`. Useful when monitoring multiple connections (`"primary"`, `"replica"`, `"reporting"`). |

### Schema

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `schemaRefreshIntervalMinutes` | `int` | `60` | How often (in minutes) to re-introspect the database schema. `0` disables automatic refresh. |

---

## Validation

`config.validate()` is called automatically by `QueryAnalyzerCore()`.
It throws `ConfigurationException` if any value is out of range:

| Field | Minimum |
|-------|---------|
| `slowQueryThresholdMs` | `>= 1` |
| `maxStoredQueries` | `>= 10` |
| `metricsRetentionDays` | `>= 1` |
| `nPlusOneWindowMs` | `>= 100` |
| `nPlusOneMinCount` | `>= 2` |
| `largeResultRowThreshold` | `>= 100` |

---

## Environment-Specific Presets

### Development

```dart
final devConfig = QueryAnalyzerConfig.custom(
  slowQueryThresholdMs: 100,   // catch even slightly slow queries
  logAllQueries: true,
  maskSensitiveValues: false,  // see actual values in logs
  detectNPlusOne: true,
  nPlusOneMinCount: 2,         // flag after just 2 repetitions
);
```

### Production

```dart
final prodConfig = QueryAnalyzerConfig.custom(
  slowQueryThresholdMs: 1000,
  logAllQueries: false,
  maskSensitiveValues: true,
  maxStoredQueries: 2000,
  persistMetrics: true,
  metricsStoragePath: '/var/data/query_analyzer',
  metricsRetentionDays: 90,
  databaseTag: 'primary',
);
```

### Read Replica

```dart
final replicaConfig = prodConfig.copyWith(
  databaseTag: 'replica',
  detectNPlusOne: false,      // N+1 is tracked on primary only
  slowQueryThresholdMs: 500,  // replicas should be faster
);
```

### Testing / CI

```dart
const testConfig = QueryAnalyzerConfig.custom(
  slowQueryThresholdMs: 9999,  // avoid false positives in tests
  maxStoredQueries: 100,
  logAllQueries: false,
  detectNPlusOne: false,
);
```

---

## ThresholdConfig (for AlertManager)

`ThresholdConfig` is separate from `QueryAnalyzerConfig` and controls when
alerts are dispatched:

```dart
const ThresholdConfig({
  int slowQueryMs = 1000,
  double slowQueryRatePercent = 10.0,
  double errorRatePercent = 5.0,
  Duration rollingWindow = const Duration(minutes: 5),
  Duration alertCooldown = const Duration(minutes: 15),
});
```

Pre-built options:

```dart
ThresholdConfig.production   // same as default
ThresholdConfig.development  // relaxed — slowQueryMs: 5000, cooldown: 30s
```
