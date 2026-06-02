# Report Generation & Export

`query_analyzer` can produce comprehensive performance reports from the
queries stored in memory, and export them in multiple formats for dashboards,
email digests, or CI pipelines.

---

## Generating a Report

```dart
// Convenience method on the facade
final report = QueryAnalyzerFacade.generateReport(core);

// Or directly via ReportGenerator
final report = ReportGenerator(core.storage).generateReport(
  timeRange: const Duration(hours: 6),
);
```

`generateReport` looks back by `timeRange` from `DateTime.now()` and
aggregates all queries observed within that window.

---

## AnalysisReport Fields

| Field | Type | Description |
|-------|------|-------------|
| `generatedAt` | `DateTime` | When this report was generated. |
| `timeRange` | `Duration` | The window covered. |
| `totalQueries` | `int` | All queries observed in the window. |
| `slowQueries` | `List<AnalyzedQuery>` | Queries above the slow threshold. |
| `averageExecutionTimeMs` | `double` | Mean execution time. |
| `medianExecutionTimeMs` | `double` | p50 latency. |
| `p95ExecutionTimeMs` | `double` | 95th percentile latency. |
| `p99ExecutionTimeMs` | `double` | 99th percentile latency. |
| `topSlowQueries` | `List<AnalyzedQuery>` | Sorted by execution time (descending). |
| `commonIssues` | `Map<IssueType, int>` | Count of each issue type. |
| `patternMetrics` | `List<PerformanceMetric>` | Per-pattern aggregations. |
| `recommendations` | `List<String>` | Auto-generated action items. |
| `totalErrors` | `int` | Error count (tracking coming in future release). |
| `errorRate` | `double` | `totalErrors / totalQueries`. |

### Computed properties

| Property | Description |
|----------|-------------|
| `slowQueryRate` | `slowQueries.length / totalQueries * 100` |
| `topSuggestions` | Top-5 suggestions across all slow queries, sorted by estimated improvement. |
| `summary` | Plain-text ASCII-box summary (see below). |

---

## Plain-Text Summary

```dart
print(report.summary);
```

```
╔══════════════════════════════════════════════════════╗
║          Query Analyzer — Performance Report          ║
╚══════════════════════════════════════════════════════╝
Generated : 2025-06-01T10:00:00.000
Period    : 6h 0m

──────────────────  Overview  ───────────────────────
Total queries   : 4 821
Slow queries    : 47 (0.9%)
Avg exec time   : 123.4 ms
Median (p50)    : 45.0 ms
p95             : 892.0 ms
p99             : 2341.0 ms
Total errors    : 0  (rate: 0.00%)

──────────────  Top Slow Queries  ───────────────────
  1. [4823ms] SELECT * FROM audit_log WHERE created_at > …
  2. [2341ms] SELECT o.id, oi.product_id FROM orders o JOIN…
  3. [1892ms] SELECT COUNT(*) FROM events GROUP BY date…

─────────────  Common Issues  ────────────────────────
  • missingIndex: 31×
  • largeResult: 18×
  • selectStar: 12×
  • nPlusOne: 5×

───────────────  Recommendations  ───────────────────
  1. Add missing indexes — 31 queries hampered by un-indexed columns.
  2. Add pagination — 18 queries return unbounded result sets.
  3. Replace SELECT * — 12 queries fetch unnecessary columns.
  4. Fix N+1 patterns — 5 occurrences. Use JOINs or batch fetching.
```

---

## Export Formats

All export methods are static on `ReportExporter`:

```dart
import 'package:query_analyzer/query_analyzer.dart';
```

### JSON

```dart
final json = ReportExporter.toJson(report);
// Writes the full report as a pretty-printed JSON string.
// Contains: generatedAt, totalQueries, slowQueryRate, percentiles,
//           topSlowQueries[], commonIssues{}, patternMetrics[], recommendations[]
```

### CSV

```dart
final csv = ReportExporter.toCsv(report);
// Columns: id, executedAt, executionTimeMs, isSlowQuery, impactScore,
//          issueCount, firstTable, normalizedQuery
// Suitable for import into Excel, Google Sheets, or BI tools.
```

### HTML

```dart
final html = ReportExporter.toHtml(report);
// Full standalone HTML page with:
// - KPI cards (total queries, slow count, avg/p95/p99, error rate)
// - Top 20 slow queries table with severity badges
// - Recommendations list
```

Save to a file:

```dart
import 'dart:io';
File('report.html').writeAsStringSync(ReportExporter.toHtml(report));
```

### Markdown

```dart
final md = ReportExporter.toMarkdown(report);
// GitHub-flavored Markdown with:
// - Overview table (avg, median, p95, p99, etc.)
// - Top 10 slow queries with SQL code blocks and suggestions
// - Recommendations list
```

---

## Scheduling Reports

A common pattern is to generate a report on a periodic timer:

```dart
Timer.periodic(const Duration(hours: 1), (_) async {
  final report = QueryAnalyzerFacade.generateReport(
    core,
    timeRange: const Duration(hours: 1),
  );

  if (report.slowQueries.isNotEmpty) {
    // Send HTML report via email
    await emailClient.send(
      to: 'team@example.com',
      subject: 'Hourly Query Report — ${report.slowQueries.length} slow queries',
      html: ReportExporter.toHtml(report),
    );
  }
});
```

---

## PerformanceMetric (Per-Pattern Stats)

Each unique normalized query pattern gets its own `PerformanceMetric` entry in
`report.patternMetrics`:

```dart
for (final m in report.patternMetrics) {
  print('${m.queryPattern}: avg=${m.averageExecutionTimeMs.toStringAsFixed(0)}ms '
        'count=${m.executionCount} p99=${m.percentiles[99]?.toStringAsFixed(0)}ms');
}
```

Fields:

| Field | Description |
|-------|-------------|
| `queryPattern` | Normalized SQL (parameters → `?`). |
| `totalExecutionTimeMs` | Cumulative execution time. |
| `executionCount` | Times this pattern was observed. |
| `minExecutionTimeMs` | Fastest execution. |
| `maxExecutionTimeMs` | Slowest execution. |
| `averageExecutionTimeMs` | Running Welford mean. |
| `stdDevMs` | Sample standard deviation. |
| `percentiles` | `{50: p50, 75: p75, 90: p90, 95: p95, 99: p99}` |
| `errorCount` | Execution errors for this pattern. |
| `errorRate` | `errorCount / executionCount`. |
| `firstSeenAt` | First observation timestamp. |
| `lastSeenAt` | Latest observation timestamp. |

---

## DailySummary

A lightweight snapshot of the last 24 hours:

```dart
final summary = core.storage.getDailySummary();
print('Today: ${summary.totalQueries} queries, '
      '${summary.slowQueries.length} slow, '
      '${summary.averageExecutionTimeMs.toStringAsFixed(1)}ms avg');
```

---

## Exporting Raw Metrics

Dump the current in-memory ring-buffer to JSON:

```dart
final jsonStr = core.storage.exportJson();
// { "exportedAt": "…", "queries": [...], "metrics": {...} }
```
