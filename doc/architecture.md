# Architecture

This document describes the internal architecture of `query_analyzer` — how
the components fit together, the data flow from a raw SQL string to an
actionable suggestion, and the extension points available to library users.

---

## High-Level Diagram

```
Application code
      │
      │  db.query('SELECT …')
      ▼
┌─────────────────────────┐
│     DatabaseWrapper     │  ← intercepts query + measures wall time
│  (or QueryWrapper)      │
└─────────┬───────────────┘
          │ analyzeQuery(sql, executionTimeMs)
          ▼
┌─────────────────────────┐
│   QueryAnalyzerCore     │  ← orchestrates parse → detect → suggest → store
└──┬──────┬───────┬───────┘
   │      │       │
   │      │       │
   ▼      │       │
┌──────┐  │       │
│Parse │  │       │   QueryParser
└──────┘  │       │   → normalized SQL, tables, WHERE clauses, JOINs, …
          │       │
          ▼       │
   ┌─────────┐    │
   │ Detect  │    │   PatternDetector
   └─────────┘    │   → FullTableScanDetector
          │       │   → MissingIndexDetector
          │       │   → NPlusOneDetector
          │       │   → LargeResultDetector
          │       │   → SubqueryDetector
          │       │
          ▼       │
   ┌─────────┐    │
   │ Suggest │    │   SuggestionEngine
   └─────────┘    │   → maps IssueType → QuerySuggestion
                  │
          ─ ─ ─ ─▼─ ─ ─ ─
          AnalyzedQuery assembled
          ─ ─ ─ ─ ─ ─ ─ ─ ─

┌─────────────────────────┐
│     MetricsStorage      │  ← ring-buffer + per-pattern aggregation
└─────────────────────────┘

┌─────────────────────────┐
│    StreamController     │  ← broadcast stream of AnalyzedQuery objects
└───────────┬─────────────┘
            │
   ┌─────────────────┐
   │  QueryListeners  │  ← AlertManager, CallbackListener, custom
   └─────────────────┘
```

---

## Layer Descriptions

### Layer 1 — Wrapper Layer

**`DatabaseWrapper`** is the entry point for application code.  It:

1. Delegates the query to the underlying `DatabaseConnection`.
2. Measures wall-clock time using Dart's `Stopwatch`.
3. Calls `QueryAnalyzerCore.analyzeQuery()` with the SQL and timing.
4. Returns the result to the caller — fully transparent.

**`QueryWrapper.measure()`** is a lightweight alternative for cases where
you only want to measure a single ad-hoc query without replacing a whole
connection.

**`ConnectionPoolWrapper`** manages a pool of `DatabaseWrapper`s and uses
round-robin selection to distribute load.

---

### Layer 2 — Analysis Core

**`QueryAnalyzerCore`** is the heart of the package.  On every call to
`analyzeQuery()` it performs five sequential steps:

| Step | Component | Output |
|------|-----------|--------|
| 1. Parse | `QueryParser` | `ParsedQuery` |
| 2. Detect | `PatternDetector` | `DetectionResult` |
| 3. Suggest | `SuggestionEngine` | `List<QuerySuggestion>` |
| 4. Assemble | — | `AnalyzedQuery` |
| 5. Distribute | `MetricsStorage` + `StreamController` + `QueryListener`s | — |

---

### Layer 3 — Parser

**`QueryParser`** uses regex-based heuristics to extract:
- Statement type (SELECT / INSERT / UPDATE / DELETE / DDL / other)
- Table names (`FROM` and `JOIN` clauses)
- Selected columns
- WHERE clause conditions (column, operator, value, parameterized?)
- JOIN clauses (type, table, left/right ON columns)
- Structural flags: `hasGroupBy`, `hasOrderBy`, `hasSubquery`, `hasAggregates`, `hasDistinct`
- `LIMIT` / `OFFSET` values
- Normalized query (literals replaced with `?`)

**`ParserUtils`** provides reusable static helpers used by both the parser and the detectors.

---

### Layer 4 — Detectors

Each detector is a small, focused class with a single `detect()` method.
All detectors are orchestrated by `PatternDetector`.

| Detector | Flags |
|----------|-------|
| `FullTableScanDetector` | No WHERE clause; WHERE column has no index; LIKE with potential leading wildcard. |
| `MissingIndexDetector` | WHERE / JOIN columns missing from schema's index list. |
| `NPlusOneDetector` | Same query fingerprint repeated ≥ N times within a sliding window. |
| `LargeResultDetector` | No LIMIT + no WHERE; actual row count ≥ threshold; unconstrained JOIN; SELECT *. |
| `SubqueryDetector` | Nesting depth > max; correlated sub-query heuristic; sub-query in SELECT list. |

Detectors are toggled individually via `QueryAnalyzerConfig` flags.  `PatternDetector` deduplicates issues by `(type, affectedElement)` before returning.

---

### Layer 5 — Suggestion Engine

**`SuggestionEngine`** maps each `QueryIssue` to a concrete `QuerySuggestion`.
Suggestions include:
- A short **title** (one line).
- A detailed **description** explaining the problem.
- An optional **SQL statement** the user can execute directly.
- An estimated **improvement percent**.
- A **priority** (low / medium / high / critical).
- An optional **documentation URL**.

Suggestions are deduplicated by title and sorted by descending priority.

---

### Layer 6 — Storage

**`MetricsStorage`** maintains:
- A ring-buffer (`Queue<AnalyzedQuery>`) capped at `config.maxStoredQueries`.
- A `Map<String, PerformanceMetric>` keyed by normalized query fingerprint.
  Per-pattern aggregation uses Welford's online algorithm for a numerically
  stable running mean and variance.

**`LocalDatabase`** provides an optional JSON-Lines persistence layer.
For production use, the `sqflite_common_ffi` backend is recommended.

**`CacheManager<K, V>`** is a generic TTL-based in-memory cache used for
schema introspection results and other expensive computations.

---

### Layer 7 — Alert System

**`AlertManager`** implements `QueryListener` and dispatches alerts when
queries cross configured thresholds.  It supports per-channel cooldown
periods to prevent alert storms.

Built-in channels: `ConsoleAlertChannel`, `LoggingAlertChannel`,
`SlackAlertChannel`, `WebhookAlertChannel`.

Custom channels implement the single-method `AlertChannel` interface:

```dart
abstract class AlertChannel {
  String get name;
  Future<void> sendAlert(AnalyzedQuery query);
}
```

---

## Data Flow (Complete)

```
db.query(sql, arguments: [...])
  │
  ├─ _connection.query(sql, ...)       ← actual DB call
  │     returns rows
  │
  ├─ stopwatch.stop()
  │
  └─ core.analyzeQuery(sql, ms, ...)
       │
       ├─ _parser.parse(sql)
       │      └─ ParsedQuery
       │
       ├─ _detector.detect(parsed, sql)
       │      ├─ FullTableScanDetector.detect(parsed)
       │      ├─ MissingIndexDetector.detect(parsed)
       │      ├─ NPlusOneDetector.observe(sql)
       │      ├─ LargeResultDetector.detect(parsed, actualRowCount)
       │      └─ SubqueryDetector.detect(parsed, sql)
       │         └─ DetectionResult (deduplicated issues)
       │
       ├─ _suggestionEngine.generateSuggestions(parsed, issues)
       │      └─ List<QuerySuggestion> (sorted by priority)
       │
       ├─ AnalyzedQuery assembled (impactScore computed)
       │
       ├─ storage.store(analyzed)
       │
       ├─ _streamController.add(analyzed)
       │
       └─ _notifyListeners(analyzed)
              └─ AlertManager, CallbackListener, …
```

---

## Extension Points

### Custom Detector

Implement your own detector and inject it by subclassing `PatternDetector`
or by pre-processing the query before passing it to `analyzeQuery()`.

### Custom Listener

```dart
class MyListener implements QueryListener {
  @override
  Future<void> onQueryAnalyzed(AnalyzedQuery query) async {
    // send to your telemetry pipeline
  }
}

core.addListener(MyListener());
```

### Custom Alert Channel

```dart
class PagerDutyChannel implements AlertChannel {
  @override
  String get name => 'pagerduty';

  @override
  Future<void> sendAlert(AnalyzedQuery query) async {
    // call PagerDuty API
  }
}
```

### Schema Providers

Implement `DatabaseConnection` and call `introspectSchema()` on the
appropriate adapter (`PostgresAdapter`, `MySqlAdapter`, `SQLiteAdapter`)
to build a live `DatabaseSchema` at startup.

---

## Threading & Concurrency

The package is designed for single-isolate use.  All internal state
(`MetricsStorage`, `NPlusOneDetector`, `AlertManager`) is not
thread-safe across isolates.  If you run multiple isolates, create
a separate `QueryAnalyzerCore` instance per isolate.

The `queryStream` and `slowQueryStream` streams are broadcast streams
and may be listened to by multiple subscribers simultaneously.
