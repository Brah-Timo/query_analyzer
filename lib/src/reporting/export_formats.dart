import 'dart:convert';
import '../models/analysis_report.dart';
import '../exceptions/analyzer_exception.dart';

/// Exports [AnalysisReport] data to various formats.
abstract final class ReportExporter {
  // ── JSON ──────────────────────────────────────────────────────────────────

  /// Serializes the [report] to a pretty-printed JSON string.
  static String toJson(AnalysisReport report) {
    try {
      return const JsonEncoder.withIndent('  ').convert(report.toJson());
    } catch (e, st) {
      throw ReportExportException(
        'JSON serialization failed: $e',
        format: 'json',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ── CSV ───────────────────────────────────────────────────────────────────

  /// Exports slow queries as a CSV string.
  static String toCsv(AnalysisReport report) {
    final buf = StringBuffer();

    // Header
    buf.writeln(
      'id,executedAt,executionTimeMs,isSlowQuery,impactScore,'
      'issueCount,firstTable,normalizedQuery',
    );

    for (final q in report.slowQueries) {
      final firstTable = q.parsed.tables.isNotEmpty
          ? q.parsed.tables.first
          : '';
      final normalized =
          '"${q.parsed.normalizedQuery.replaceAll('"', '""').substring(0, q.parsed.normalizedQuery.length.clamp(0, 200))}"';
      buf.writeln(
        '${q.id},'
        '${q.executedAt.toIso8601String()},'
        '${q.executionTimeMs},'
        '${q.isSlowQuery},'
        '${q.impactScore},'
        '${q.detectionResult.issues.length},'
        '$firstTable,'
        '$normalized',
      );
    }

    return buf.toString();
  }

  // ── HTML ──────────────────────────────────────────────────────────────────

  /// Renders an HTML performance report page.
  static String toHtml(AnalysisReport report) {
    final buf = StringBuffer();

    buf.writeln('''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Query Analyzer Report — ${_fmt(report.generatedAt)}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: system-ui, sans-serif; background: #f8fafc; color: #1e293b; }
    header { background: #1e40af; color: #fff; padding: 1.5rem 2rem; }
    header h1 { font-size: 1.5rem; font-weight: 700; }
    header p { opacity: .8; font-size: .875rem; margin-top: .25rem; }
    main { max-width: 1100px; margin: 2rem auto; padding: 0 1rem; }
    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
    .card { background: #fff; border-radius: .5rem; padding: 1.25rem; box-shadow: 0 1px 3px rgba(0,0,0,.1); }
    .card .label { font-size: .75rem; text-transform: uppercase; letter-spacing: .05em; color: #64748b; }
    .card .value { font-size: 2rem; font-weight: 700; margin-top: .25rem; }
    .card.danger .value { color: #dc2626; }
    .card.warn .value { color: #d97706; }
    .card.ok .value { color: #16a34a; }
    table { width: 100%; border-collapse: collapse; background: #fff;
            box-shadow: 0 1px 3px rgba(0,0,0,.1); border-radius: .5rem; overflow: hidden; }
    th { background: #1e40af; color: #fff; text-align: left; padding: .75rem 1rem; font-size: .8rem; }
    td { padding: .65rem 1rem; font-size: .85rem; border-bottom: 1px solid #f1f5f9; word-break: break-all; }
    tr:last-child td { border-bottom: none; }
    tr:hover td { background: #f8fafc; }
    .badge { display: inline-block; padding: .15rem .5rem; border-radius: 9999px;
             font-size: .7rem; font-weight: 600; }
    .badge.critical { background: #fee2e2; color: #dc2626; }
    .badge.high     { background: #ffedd5; color: #ea580c; }
    .badge.medium   { background: #fef9c3; color: #ca8a04; }
    .badge.low      { background: #dcfce7; color: #16a34a; }
    h2 { font-size: 1.125rem; font-weight: 600; margin: 2rem 0 .75rem; }
    ul.recs { list-style: none; }
    ul.recs li::before { content: "→ "; color: #1e40af; font-weight: 700; }
    ul.recs li { margin-bottom: .4rem; font-size: .9rem; }
    footer { text-align: center; padding: 2rem; color: #94a3b8; font-size: .75rem; }
  </style>
</head>
<body>
<header>
  <h1>⚡ Query Analyzer — Performance Report</h1>
  <p>Generated: ${_fmt(report.generatedAt)} &nbsp;|&nbsp; Period: ${_fmtDur(report.timeRange)}</p>
</header>
<main>
  <div class="cards">
    <div class="card"><div class="label">Total Queries</div><div class="value">${report.totalQueries}</div></div>
    <div class="card ${report.slowQueries.isEmpty ? "ok" : "danger"}">
      <div class="label">Slow Queries</div>
      <div class="value">${report.slowQueries.length}</div>
    </div>
    <div class="card"><div class="label">Avg Time (ms)</div><div class="value">${report.averageExecutionTimeMs.toStringAsFixed(1)}</div></div>
    <div class="card"><div class="label">p95 (ms)</div><div class="value">${report.p95ExecutionTimeMs.toStringAsFixed(1)}</div></div>
    <div class="card"><div class="label">p99 (ms)</div><div class="value">${report.p99ExecutionTimeMs.toStringAsFixed(1)}</div></div>
    <div class="card ${report.errorRate > 0 ? "warn" : "ok"}">
      <div class="label">Error Rate</div>
      <div class="value">${(report.errorRate * 100).toStringAsFixed(2)}%</div>
    </div>
  </div>
''');

    // Top slow queries table
    if (report.topSlowQueries.isNotEmpty) {
      buf.writeln('<h2>Top Slow Queries</h2>');
      buf.writeln('<table><thead><tr>'
          '<th>#</th><th>Time (ms)</th><th>Impact</th>'
          '<th>Issues</th><th>Query</th></tr></thead><tbody>');
      for (var i = 0; i < report.topSlowQueries.take(20).length; i++) {
        final q = report.topSlowQueries[i];
        final severity =
            q.detectionResult.maxSeverity?.name.toLowerCase() ?? 'low';
        final snippet = q.originalQuery.length > 120
            ? '${q.originalQuery.substring(0, 117)}…'
            : q.originalQuery;
        buf.writeln('<tr>'
            '<td>${i + 1}</td>'
            '<td><strong>${q.executionTimeMs}</strong></td>'
            '<td>${q.impactScore}/100</td>'
            '<td><span class="badge $severity">$severity</span></td>'
            '<td><code>$snippet</code></td>'
            '</tr>');
      }
      buf.writeln('</tbody></table>');
    }

    // Recommendations
    if (report.recommendations.isNotEmpty) {
      buf.writeln('<h2>Recommendations</h2><ul class="recs">');
      for (final rec in report.recommendations) {
        buf.writeln('<li>$rec</li>');
      }
      buf.writeln('</ul>');
    }

    buf.writeln('''</main>
<footer>Query Analyzer v1.0.0 — Generated ${_fmt(report.generatedAt)}</footer>
</body></html>''');

    return buf.toString();
  }

  // ── Markdown ──────────────────────────────────────────────────────────────

  /// Renders the report as a Markdown document.
  static String toMarkdown(AnalysisReport report) {
    final buf = StringBuffer()
      ..writeln('# Query Analyzer Report')
      ..writeln()
      ..writeln('**Generated:** ${_fmt(report.generatedAt)}  ')
      ..writeln('**Period:** ${_fmtDur(report.timeRange)}')
      ..writeln()
      ..writeln('## Overview')
      ..writeln()
      ..writeln('| Metric | Value |')
      ..writeln('|---|---|')
      ..writeln('| Total Queries | ${report.totalQueries} |')
      ..writeln('| Slow Queries | ${report.slowQueries.length} (${report.slowQueryRate.toStringAsFixed(1)}%) |')
      ..writeln('| Avg Execution | ${report.averageExecutionTimeMs.toStringAsFixed(1)} ms |')
      ..writeln('| Median (p50) | ${report.medianExecutionTimeMs.toStringAsFixed(1)} ms |')
      ..writeln('| p95 | ${report.p95ExecutionTimeMs.toStringAsFixed(1)} ms |')
      ..writeln('| p99 | ${report.p99ExecutionTimeMs.toStringAsFixed(1)} ms |')
      ..writeln()
      ..writeln('## Top Slow Queries')
      ..writeln();

    for (var i = 0; i < report.topSlowQueries.take(10).length; i++) {
      final q = report.topSlowQueries[i];
      buf
        ..writeln('### ${i + 1}. ${q.executionTimeMs} ms (impact: ${q.impactScore}/100)')
        ..writeln()
        ..writeln('```sql')
        ..writeln(q.originalQuery)
        ..writeln('```')
        ..writeln();
      for (final s in q.suggestions.take(3)) {
        buf.writeln('- **${s.title}**: ${s.description}');
        if (s.sqlStatement != null) {
          buf
            ..writeln()
            ..writeln('  ```sql')
            ..writeln('  ${s.sqlStatement}')
            ..writeln('  ```');
        }
        buf.writeln();
      }
    }

    buf
      ..writeln('## Recommendations')
      ..writeln();
    for (final rec in report.recommendations) {
      buf.writeln('- $rec');
    }

    return buf.toString();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _fmt(DateTime dt) =>
      dt.toIso8601String().replaceFirst('T', ' ').substring(0, 19);

  static String _fmtDur(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }
}
