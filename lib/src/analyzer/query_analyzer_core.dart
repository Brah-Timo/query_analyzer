import 'dart:async';
import 'package:uuid/uuid.dart';

import '../models/analyzed_query.dart';
import '../models/database_schema.dart';
import '../storage/metrics_storage.dart';
import '../utils/config.dart';
import '../utils/logger.dart';
import '../utils/parser_utils.dart';
import 'query_parser.dart';
import 'pattern_detector.dart';
import 'suggestion_engine.dart';

/// Callback fired whenever a slow query is detected.
typedef SlowQueryCallback = void Function(
  String query,
  int executionTimeMs,
  List<dynamic> suggestions,
);

/// Abstract listener interface for query analysis events.
abstract class QueryListener {
  /// Called after every query is analyzed.
  Future<void> onQueryAnalyzed(AnalyzedQuery query);
}

/// The heart of the Query Analyzer package.
///
/// [QueryAnalyzerCore] receives raw execution observations from
/// [DatabaseWrapper], parses them, runs all detectors, generates
/// suggestions, and distributes the resulting [AnalyzedQuery] to
/// registered [QueryListener]s and the [MetricsStorage].
class QueryAnalyzerCore {
  final QueryAnalyzerConfig config;
  final MetricsStorage storage;
  final QueryParser _parser;
  final PatternDetector _detector;
  final SuggestionEngine _suggestionEngine;
  final List<QueryListener> _listeners = [];

  /// Stream controller that broadcasts every [AnalyzedQuery].
  final StreamController<AnalyzedQuery> _streamController =
      StreamController.broadcast();

  static const _uuid = Uuid();

  /// Creates a [QueryAnalyzerCore].
  ///
  /// Pass a [DatabaseSchema] for schema-aware analysis; use
  /// [DatabaseSchema.empty] when schema introspection is not available.
  QueryAnalyzerCore({
    required this.config,
    required DatabaseSchema schema,
  })  : storage = MetricsStorage(config),
        _parser = QueryParser(),
        _detector = PatternDetector(schema: schema, config: config),
        _suggestionEngine = SuggestionEngine(schema: schema) {
    config.validate();
    QaLogger.info('QueryAnalyzerCore v${kPackageVersion} initialized. '
        'Slow threshold: ${config.slowQueryThresholdMs}ms');
  }

  // ignore: undefined_identifier — kPackageVersion comes from constants.dart
  static const kPackageVersion = '1.0.0';

  // ── Public API ────────────────────────────────────────────────────────────

  /// Analyzes a single SQL query execution and returns the [AnalyzedQuery].
  ///
  /// This is the core entry-point called by [DatabaseWrapper] after every
  /// query execution.
  Future<AnalyzedQuery> analyzeQuery(
    String sql, {
    required int executionTimeMs,
    Map<String, dynamic>? parameters,
    int? actualRowCount,
  }) async {
    final id = _uuid.v4();
    final maskedSql =
        config.maskSensitiveValues ? ParserUtils.maskSensitiveValues(sql) : sql;

    // ── Parse ────────────────────────────────────────────────────────────
    late ParsedQuery parsed;
    try {
      parsed = _parser.parse(sql);
    } catch (e, st) {
      QaLogger.error('Failed to parse SQL', e, st);
      // Return a minimal AnalyzedQuery so the app keeps running
      return _buildFallbackQuery(
        id: id,
        sql: maskedSql,
        executionTimeMs: executionTimeMs,
      );
    }

    // ── Detect ───────────────────────────────────────────────────────────
    final detectionResult = _detector.detect(
      parsed,
      sql,
      actualRowCount: actualRowCount,
    );

    // ── Suggest ──────────────────────────────────────────────────────────
    final suggestions = _suggestionEngine.generateSuggestions(
      parsed,
      detectionResult.issues,
    );

    // ── Assemble ─────────────────────────────────────────────────────────
    final isSlow = executionTimeMs >= config.slowQueryThresholdMs;

    final analyzed = AnalyzedQuery(
      id: id,
      originalQuery: maskedSql,
      executionTimeMs: executionTimeMs,
      executedAt: DateTime.now(),
      parsed: parsed,
      detectionResult: detectionResult,
      suggestions: suggestions,
      isSlowQuery: isSlow,
      databaseTag: config.databaseTag,
      maskedParameters: parameters?.map(
        (k, v) => MapEntry(k, '***'),
      ),
    );

    // ── Log ──────────────────────────────────────────────────────────────
    if (isSlow) {
      QaLogger.slowQuery(maskedSql, executionTimeMs);
    } else if (config.logAllQueries) {
      QaLogger.debug('Query [${executionTimeMs}ms] $maskedSql');
    }

    // ── Store ────────────────────────────────────────────────────────────
    await storage.store(analyzed);

    // ── Notify ───────────────────────────────────────────────────────────
    _streamController.add(analyzed);
    await _notifyListeners(analyzed);

    return analyzed;
  }

  /// Returns `true` if [executionTimeMs] exceeds the slow-query threshold.
  bool isSlowQuery(int executionTimeMs) =>
      executionTimeMs >= config.slowQueryThresholdMs;

  /// Registers a [QueryListener].
  void addListener(QueryListener listener) {
    _listeners.add(listener);
    QaLogger.debug('Listener added: ${listener.runtimeType}');
  }

  /// Unregisters a [QueryListener].
  void removeListener(QueryListener listener) {
    _listeners.remove(listener);
  }

  /// A broadcast stream of every [AnalyzedQuery] as it is produced.
  Stream<AnalyzedQuery> get queryStream => _streamController.stream;

  /// A stream filtered to slow queries only.
  Stream<AnalyzedQuery> get slowQueryStream =>
      queryStream.where((q) => q.isSlowQuery);

  /// Resets all stored metrics and clears listener history.
  void reset() {
    storage.reset();
    _detector.resetNPlusOneHistory();
    QaLogger.info('QueryAnalyzerCore reset.');
  }

  /// Releases resources (closes the stream controller).
  Future<void> dispose() async {
    await _streamController.close();
    QaLogger.info('QueryAnalyzerCore disposed.');
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _notifyListeners(AnalyzedQuery query) async {
    for (final listener in List.of(_listeners)) {
      try {
        await listener.onQueryAnalyzed(query);
      } catch (e, st) {
        QaLogger.error(
          'Listener ${listener.runtimeType} threw an error',
          e,
          st,
        );
      }
    }
  }

  AnalyzedQuery _buildFallbackQuery({
    required String id,
    required String sql,
    required int executionTimeMs,
  }) {
    return AnalyzedQuery(
      id: id,
      originalQuery: sql,
      executionTimeMs: executionTimeMs,
      executedAt: DateTime.now(),
      parsed: ParsedQuery(
        type: QueryType.other,
        tables: const [],
        selectedColumns: const [],
        whereClauses: const [],
        joins: const [],
        hasGroupBy: false,
        hasOrderBy: false,
        hasSubquery: false,
        subqueryDepth: 0,
        hasDistinct: false,
        hasAggregates: false,
        normalizedQuery: sql,
      ),
      detectionResult: const DetectionResult.clean(),
      suggestions: const [],
      isSlowQuery: executionTimeMs >= config.slowQueryThresholdMs,
    );
  }
}

/// A [QueryListener] that forwards slow queries to a [SlowQueryCallback].
class CallbackListener implements QueryListener {
  final SlowQueryCallback callback;

  /// Creates a [CallbackListener].
  const CallbackListener(this.callback);

  @override
  Future<void> onQueryAnalyzed(AnalyzedQuery query) async {
    if (query.isSlowQuery) {
      callback(query.originalQuery, query.executionTimeMs, query.suggestions);
    }
  }
}
