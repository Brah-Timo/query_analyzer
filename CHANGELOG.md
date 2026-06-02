# Changelog

All notable changes to **Query Analyzer** will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] — 2026-06-01

### Added

#### Core
- `QueryAnalyzerCore` — central analysis engine with `StreamController<AnalyzedQuery>`
- `QueryAnalyzerFacade` — top-level convenience API (`create`, `wrap`, `generateReport`, `topSlowQueries`)
- `QueryAnalyzerConfig` / `QueryAnalyzerConfig.custom` with full `copyWith` and `validate()`

#### Models
- `AnalyzedQuery` — fully self-contained analysis record with computed `impactScore`
- `ParsedQuery` — structural breakdown of a SQL statement
- `DetectionResult` — aggregated detector output with `severityScore` and `maxSeverity`
- `QueryIssue` — individual problem with `IssueType` and `IssueSeverity`
- `QuerySuggestion` — concrete actionable fix with factory constructors
- `PerformanceMetric` — Welford's online variance, percentile map, error rate
- `DatabaseSchema` / `TableSchema` / `ColumnSchema` / `IndexSchema`
- `AnalysisReport` — aggregated time-boxed performance report

#### Detectors
- `FullTableScanDetector` — no-WHERE, un-indexed WHERE, leading-wildcard LIKE
- `MissingIndexDetector` — WHERE columns, JOIN columns (both sides)
- `NPlusOneDetector` — sliding-window fingerprint counter
- `LargeResultDetector` — actual row count feedback + structural heuristics
- `SubqueryDetector` — correlated sub-queries, deep nesting, SELECT-list sub-queries

#### Parser & Utilities
- `QueryParser` — regex-based lightweight SQL parser (type, tables, WHERE, JOIN, LIMIT, depth)
- `ParserUtils` — `normalize()`, `maskSensitiveValues()`, `fingerprint()`, `extractWhereColumns()`
- `PrecisionTimer` — high-resolution wall-clock timer with `measureWithResult()`
- `CacheManager<K,V>` — TTL-based in-memory cache
- `QaLogger` — configurable console output wrapper over `dart:logging`
- `QueryAnalyzerConfig` — full configuration with validation

#### Wrappers
- `DatabaseWrapper` — transparent query/execute interceptor
- `QueryWrapper.measure()` — single-call measurement utility
- `ConnectionPoolWrapper` — round-robin pool wrapper

#### Storage
- `MetricsStorage` — in-memory ring-buffer + `PerformanceMetric` aggregation
- `LocalDatabase` — JSON-Lines persistence stub (cross-platform)
- `DailySummary` — 24-hour snapshot DTO

#### Reporting
- `ReportGenerator` — time-windowed `AnalysisReport` with percentile computation
- `ReportExporter` — `toJson()`, `toCsv()`, `toHtml()`, `toMarkdown()`

#### Alerts
- `AlertManager` — `QueryListener` with per-channel cooldown enforcement
- `ConsoleAlertChannel` — stdout pretty-print
- `LoggingAlertChannel` — routes to `QaLogger`
- `SlackAlertChannel` — incoming webhook with rich attachment payload
- `WebhookAlertChannel` — generic HTTP POST with custom headers
- `ThresholdConfig` — production and development presets

#### Database Adapters
- `PostgresAdapter` — full schema introspection, `EXPLAIN ANALYZE` parsing
- `MySqlAdapter` — `information_schema` introspection, `EXPLAIN FORMAT=JSON`
- `SQLiteAdapter` — `PRAGMA`-based introspection, `EXPLAIN QUERY PLAN`

#### Exceptions
- `AnalyzerException` (base)
- `ConfigurationException`
- `DatabaseIntrospectionException`
- `QueryParseException`
- `MetricsStorageException`
- `AlertDeliveryException`
- `ReportExportException`

#### Tests
- 4 unit test suites: parser, detectors, analyzer+wrapper, suggestion engine
- 1 end-to-end integration suite with mock database
- Fixture library: `SampleQueries`, `MockDatabaseConnection`, `TestSchemas`

#### Examples
- `basic_usage.dart`
- `advanced_features.dart`
- `custom_alerts.dart`
- `report_generation.dart`
- `web_server_integration.dart`

---

## [Unreleased]

### Planned
- MongoDB adapter
- Prometheus / OpenMetrics export
- Predictive analytics (ML-based)
- Datadog / New Relic integration
- Full SQLite persistence via `sqflite_common_ffi`
