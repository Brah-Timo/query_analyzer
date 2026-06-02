/// Query Analyzer — Ultra Pro
///
/// A professional Dart package for automatic monitoring, profiling, and
/// intelligent diagnosis of slow database queries.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:query_analyzer/query_analyzer.dart';
///
/// // 1. Create a schema (or use DatabaseSchema.empty for schema-less mode)
/// final schema = DatabaseSchema.empty('postgresql');
///
/// // 2. Create the core analyzer
/// final core = QueryAnalyzerCore(
///   config: QueryAnalyzerConfig.custom(
///     slowQueryThresholdMs: 500,
///     detectNPlusOne: true,
///   ),
///   schema: schema,
/// );
///
/// // 3. Wrap your database connection
/// final db = DatabaseWrapper(
///   connection: myConnection, // implements DatabaseConnection
///   analyzer: core,
/// );
///
/// // 4. Register a slow-query callback
/// db.onSlowQuery = (sql, ms, suggestions) {
///   print('Slow query (${ms}ms): $sql');
///   for (final s in suggestions) {
///     print('  → ${s.title}');
///   }
/// };
///
/// // 5. Use db normally
/// final users = await db.query('SELECT * FROM users WHERE email = ?',
///     arguments: ['alice@example.com']);
///
/// // 6. Generate a report
/// final report = QueryAnalyzerFacade.generateReport(core);
/// print(report.summary);
/// ```
library query_analyzer;

// ── Public constants ──────────────────────────────────────────────────────
export 'constants.dart';

// ── Exceptions ────────────────────────────────────────────────────────────
export 'src/exceptions/analyzer_exception.dart';
export 'src/exceptions/configuration_exception.dart';

// ── Models ────────────────────────────────────────────────────────────────
export 'src/models/analyzed_query.dart';
export 'src/models/analysis_report.dart';
export 'src/models/database_schema.dart';
export 'src/models/performance_metric.dart';
export 'src/models/query_suggestion.dart';

// ── Configuration ─────────────────────────────────────────────────────────
export 'src/utils/config.dart';
export 'src/utils/logger.dart';
export 'src/utils/parser_utils.dart';
export 'src/utils/timer.dart';

// ── Core analyzer ─────────────────────────────────────────────────────────
export 'src/analyzer/query_analyzer_core.dart';
export 'src/analyzer/query_parser.dart';
export 'src/analyzer/pattern_detector.dart';
export 'src/analyzer/suggestion_engine.dart';

// ── Detectors ─────────────────────────────────────────────────────────────
export 'src/detectors/full_table_scan_detector.dart';
export 'src/detectors/missing_index_detector.dart';
export 'src/detectors/n_plus_one_detector.dart';
export 'src/detectors/large_result_detector.dart';
export 'src/detectors/subquery_detector.dart';

// ── Wrappers ──────────────────────────────────────────────────────────────
export 'src/wrapper/database_wrapper.dart';
export 'src/wrapper/query_wrapper.dart';
export 'src/wrapper/connection_pool_wrapper.dart';

// ── Storage ───────────────────────────────────────────────────────────────
export 'src/storage/metrics_storage.dart';
export 'src/storage/cache_manager.dart';
export 'src/storage/local_database.dart';

// ── Reporting ─────────────────────────────────────────────────────────────
export 'src/reporting/report_generator.dart';
export 'src/reporting/export_formats.dart';

// ── Alerts ────────────────────────────────────────────────────────────────
export 'src/alerts/alert_manager.dart';
export 'src/alerts/alert_channels.dart';
export 'src/alerts/threshold_config.dart';

// ── Integrations ─────────────────────────────────────────────────────────
export 'src/integration/postgres_adapter.dart';
export 'src/integration/mysql_adapter.dart';
export 'src/integration/sqlite_adapter.dart';

// ── Facade ────────────────────────────────────────────────────────────────

import 'src/analyzer/query_analyzer_core.dart';
import 'src/models/analysis_report.dart';
import 'src/models/analyzed_query.dart';
import 'src/models/database_schema.dart';
import 'src/reporting/report_generator.dart';
import 'src/utils/config.dart';
import 'src/wrapper/database_wrapper.dart';

/// Top-level convenience facade for the most common use cases.
abstract final class QueryAnalyzerFacade {
  /// Current package version.
  static const String version = '1.0.0';

  /// Creates a [QueryAnalyzerCore] with the given [config] and optional
  /// [schema].
  ///
  /// If [schema] is omitted, schema-less mode is used (detectors that
  /// require schema knowledge are disabled automatically).
  static QueryAnalyzerCore create({
    QueryAnalyzerConfig config = const QueryAnalyzerConfig(),
    DatabaseSchema? schema,
    SlowQueryCallback? onSlowQuery,
  }) {
    final core = QueryAnalyzerCore(
      config: config,
      schema: schema ?? DatabaseSchema.empty('unknown'),
    );

    if (onSlowQuery != null) {
      core.addListener(CallbackListener(onSlowQuery));
    }

    return core;
  }

  /// Wraps [connection] with a [DatabaseWrapper] backed by a new
  /// [QueryAnalyzerCore] using the given [config].
  static DatabaseWrapper wrap(
    DatabaseConnection connection, {
    QueryAnalyzerConfig config = const QueryAnalyzerConfig(),
    DatabaseSchema? schema,
    SlowQueryCallback? onSlowQuery,
  }) {
    final core = create(
      config: config,
      schema: schema,
      onSlowQuery: onSlowQuery,
    );
    return DatabaseWrapper(connection: connection, analyzer: core);
  }

  /// Generates an [AnalysisReport] from the [core]'s current storage.
  static AnalysisReport generateReport(
    QueryAnalyzerCore core, {
    Duration timeRange = const Duration(hours: 24),
  }) {
    return ReportGenerator(core.storage).generateReport(timeRange: timeRange);
  }

  /// Returns the top [n] slow [AnalyzedQuery]s from [core]'s storage.
  static List<AnalyzedQuery> topSlowQueries(
    QueryAnalyzerCore core, {
    int n = 10,
  }) {
    return core.storage
        .getSlowQueries()
        .take(n)
        .toList();
  }
}
