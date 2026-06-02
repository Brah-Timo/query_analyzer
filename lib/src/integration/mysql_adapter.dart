import '../models/database_schema.dart';
import '../utils/logger.dart';
import '../wrapper/database_wrapper.dart';
import 'postgres_adapter.dart' show ExplainPlan;

/// Adapter that adapts a MySQL / MariaDB connection to [DatabaseConnection]
/// and provides schema introspection utilities.
abstract class MySqlAdapter implements DatabaseConnection {
  // ── Schema Introspection ──────────────────────────────────────────────────

  /// Introspects the MySQL database and returns a [DatabaseSchema].
  ///
  /// [databaseName] is the MySQL schema/database name to inspect.
  Future<DatabaseSchema> introspectSchema({
    required String databaseName,
  }) async {
    QaLogger.info('MySqlAdapter: introspecting database "$databaseName"...');

    final tablesResult = await query('''
      SELECT
        TABLE_NAME AS table_name,
        TABLE_ROWS AS approximate_row_count
      FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = '$databaseName'
        AND TABLE_TYPE = 'BASE TABLE'
      ORDER BY TABLE_NAME
    ''');

    final tables = <TableSchema>[];

    for (final row in tablesResult) {
      final tableName = row['table_name'] as String;
      final cols = await _loadColumns(tableName, databaseName);
      final idxs = await _loadIndexes(tableName, databaseName);

      tables.add(TableSchema(
        name: tableName,
        schema: databaseName,
        columns: cols,
        indexes: idxs,
        approximateRowCount: (row['approximate_row_count'] as num?)?.toInt(),
      ));
    }

    QaLogger.info('MySqlAdapter: introspected ${tables.length} tables.');

    return DatabaseSchema(
      tables: tables,
      engineName: 'mysql',
      engineVersion: await _getVersion(),
      loadedAt: DateTime.now(),
    );
  }

  /// Runs EXPLAIN on [sql] and returns an [ExplainPlan].
  Future<ExplainPlan> explainQuery(String sql) async {
    final rows = await query('EXPLAIN FORMAT=JSON $sql');
    final rawOutput = rows.isNotEmpty
        ? rows.first.values.first.toString()
        : '';

    return ExplainPlan(
      rawOutput: rawOutput,
      hasSeqScan: rawOutput.contains('"access_type": "ALL"') ||
          rawOutput.contains('"access_type": "index"'),
      estimatedCost: _extractJsonValue(rawOutput, 'query_cost'),
    );
  }

  // ── Private introspection helpers ─────────────────────────────────────────

  Future<List<ColumnSchema>> _loadColumns(
    String tableName,
    String dbName,
  ) async {
    final rows = await query('''
      SELECT
        COLUMN_NAME         AS column_name,
        DATA_TYPE           AS data_type,
        IS_NULLABLE         AS is_nullable,
        COLUMN_DEFAULT      AS column_default,
        COLUMN_KEY          AS column_key
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = '$dbName'
        AND TABLE_NAME   = '$tableName'
      ORDER BY ORDINAL_POSITION
    ''');

    // Fetch indexed columns
    final idxRows = await query('''
      SELECT DISTINCT COLUMN_NAME
      FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = '$dbName'
        AND TABLE_NAME   = '$tableName'
    ''');
    final indexedCols =
        idxRows.map((r) => r['COLUMN_NAME'] as String).toSet();

    return rows
        .map((r) => ColumnSchema(
              name: r['column_name'] as String,
              dataType: r['data_type'] as String,
              nullable: (r['is_nullable'] as String) == 'YES',
              isPrimaryKey: (r['column_key'] as String?) == 'PRI',
              hasIndex: indexedCols.contains(r['column_name'] as String),
              defaultValue: r['column_default'] as String?,
            ))
        .toList();
  }

  Future<List<IndexSchema>> _loadIndexes(
    String tableName,
    String dbName,
  ) async {
    final rows = await query('''
      SELECT
        INDEX_NAME,
        NON_UNIQUE,
        GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columns
      FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = '$dbName'
        AND TABLE_NAME   = '$tableName'
      GROUP BY INDEX_NAME, NON_UNIQUE
    ''');

    return rows
        .map((r) => IndexSchema(
              name: r['INDEX_NAME'] as String,
              tableName: tableName,
              columns: (r['columns'] as String).split(','),
              isUnique: (r['NON_UNIQUE'] as int?) == 0,
              isPrimary: (r['INDEX_NAME'] as String) == 'PRIMARY',
            ))
        .toList();
  }

  Future<String?> _getVersion() async {
    try {
      final rows = await query('SELECT VERSION() AS v');
      return rows.isNotEmpty ? rows.first['v'].toString() : null;
    } catch (_) {
      return null;
    }
  }

  double? _extractJsonValue(String json, String key) {
    final m = RegExp('"$key":\\s*"?([\\d.]+)"?').firstMatch(json);
    return m != null ? double.tryParse(m.group(1) ?? '') : null;
  }
}
