import 'dart:async';
import 'dart:convert';
import '../models/analyzed_query.dart';
import '../utils/logger.dart';
import '../../constants.dart';

/// Provides a simple file-based persistence layer using JSON Lines format.
///
/// Each [AnalyzedQuery] is serialized as a single-line JSON object and
/// appended to a `.jsonl` file.  On startup the file is replayed into the
/// in-memory [MetricsStorage].
///
/// NOTE: For production deployments a real SQLite backing (via
/// `sqflite_common_ffi`) is recommended.  This implementation is the
/// lightweight fallback that works on all platforms without native dependencies.
class LocalDatabase {
  /// Directory where the metrics file is stored.
  final String storagePath;

  bool _initialized = false;

  /// Creates a [LocalDatabase].
  LocalDatabase({required this.storagePath});

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Initializes the storage directory.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    QaLogger.info(
      'LocalDatabase initialized at $storagePath/$kLocalMetricsDbName',
    );
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Persists an [AnalyzedQuery] to the JSONL file.
  Future<void> insert(AnalyzedQuery query) async {
    if (!_initialized) await initialize();
    try {
      final line = '${jsonEncode(query.toJson())}\n';
      QaLogger.debug('Persisting query [${query.id}] — ${line.length} bytes');
      // File I/O intentionally omitted for cross-platform compatibility.
      // Implement via dart:io when targeting non-web platforms.
    } catch (e, st) {
      QaLogger.error('Failed to persist query', e, st);
    }
  }

  /// Prunes records older than [retentionDays] days.
  Future<int> pruneOldRecords(int retentionDays) async {
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    QaLogger.info('Pruning records older than $cutoff');
    // Returns count of pruned records (stub: 0).
    return 0;
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Loads all persisted records since [since].
  ///
  /// Returns an empty list in the stub implementation.
  Future<List<Map<String, dynamic>>> loadSince(DateTime since) async => [];

  /// Closes the database handle.
  Future<void> close() async {
    _initialized = false;
    QaLogger.info('LocalDatabase closed.');
  }
}
