import '../models/database_schema.dart';
import '../utils/logger.dart';
import '../wrapper/database_wrapper.dart';
import 'postgres_adapter.dart' show ExplainPlan;

/// Adapter that adapts a SQLite connection to [DatabaseConnection] and
/// provides lightweight schema introspection.
///
/// SQLite has limited metadata compared to PostgreSQL / MySQL.
/// Index detection is based on `sqlite_master` and `PRAGMA index_list`.
abstract class SQLiteAdapter implements DatabaseConnection {
  // ── Schema Introspection ──────────────────────────────────────────────────

  /// Introspects the SQLite database and returns a [DatabaseSchema].
  Future<DatabaseSchema> introspectSchema() async {
    QaLogger.info('SQLiteAdapter: introspecting schema...');

    final tablesResult = await query('''
      SELECT name FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
      ORDER BY name
    ''');

    final tables = <TableSchema>[];

    for (final row in tablesResult) {
      final tableName = row['name'] as String;
      final cols = await _loadColumns(tableName);
      final idxs = await _loadIndexes(tableName);

      tables.add(TableSchema(
        name: tableName,
        schema: 'main',
        columns: cols,
        indexes: idxs,
        // SQLite does not provide row-count statistics easily
      ));
    }

    QaLogger.info('SQLiteAdapter: introspected ${tables.length} tables.');

    return DatabaseSchema(
      tables: tables,
      engineName: 'sqlite',
      engineVersion: await _getVersion(),
      loadedAt: DateTime.now(),
    );
  }

  /// Runs EXPLAIN QUERY PLAN on [sql] and returns an [ExplainPlan].
  Future<ExplainPlan> explainQueryPlan(String sql) async {
    final rows = await query('EXPLAIN QUERY PLAN $sql');
    final output =
        rows.map((r) => r.values.join(' | ')).join('\n');

    return ExplainPlan(
      rawOutput: output,
      hasSeqScan:
          output.toLowerCase().contains('scan') &&
          !output.toLowerCase().contains('index'),
    );
  }

  // ── Private introspection helpers ─────────────────────────────────────────

  Future<List<ColumnSchema>> _loadColumns(String tableName) async {
    final rows = await query('PRAGMA table_info($tableName)');

    // Collect indexed columns
    final indexedCols = await _getIndexedColumnNames(tableName);

    return rows
        .map((r) => ColumnSchema(
              name: r['name'] as String,
              dataType: (r['type'] as String?) ?? 'TEXT',
              nullable: (r['notnull'] as int?) == 0,
              isPrimaryKey: (r['pk'] as int?) == 1,
              hasIndex: indexedCols.contains(r['name'] as String),
              defaultValue: r['dflt_value'] as String?,
            ))
        .toList();
  }

  Future<List<IndexSchema>> _loadIndexes(String tableName) async {
    final indexList = await query('PRAGMA index_list($tableName)');
    final indexes = <IndexSchema>[];

    for (final row in indexList) {
      final indexName = row['name'] as String;
      final infoRows = await query('PRAGMA index_info($indexName)');
      final cols =
          infoRows.map((r) => r['name'] as String).toList();

      indexes.add(IndexSchema(
        name: indexName,
        tableName: tableName,
        columns: cols,
        isUnique: (row['unique'] as int?) == 1,
      ));
    }

    return indexes;
  }

  Future<Set<String>> _getIndexedColumnNames(String tableName) async {
    final indexList = await query('PRAGMA index_list($tableName)');
    final cols = <String>{};

    for (final row in indexList) {
      final indexName = row['name'] as String;
      final infoRows = await query('PRAGMA index_info($indexName)');
      for (final info in infoRows) {
        cols.add(info['name'] as String);
      }
    }
    return cols;
  }

  Future<String?> _getVersion() async {
    try {
      final rows = await query('SELECT sqlite_version() AS v');
      return rows.isNotEmpty ? rows.first['v'].toString() : null;
    } catch (_) {
      return null;
    }
  }
}
