import '../models/database_schema.dart';
import '../utils/logger.dart';
import '../wrapper/database_wrapper.dart';

/// Simulates an EXPLAIN plan result.
class ExplainPlan {
  /// Raw text output from EXPLAIN ANALYZE.
  final String rawOutput;

  /// Whether the planner chose a sequential scan.
  final bool hasSeqScan;

  /// Estimated total cost.
  final double? estimatedCost;

  /// Actual execution time in ms (from EXPLAIN ANALYZE).
  final double? actualTimeMs;

  /// Creates an [ExplainPlan].
  const ExplainPlan({
    required this.rawOutput,
    required this.hasSeqScan,
    this.estimatedCost,
    this.actualTimeMs,
  });

  @override
  String toString() =>
      'ExplainPlan(seqScan: $hasSeqScan, cost: $estimatedCost, '
      'actualMs: $actualTimeMs)';
}

/// Adapter that adapts a PostgreSQL connection to [DatabaseConnection] and
/// provides schema introspection utilities.
///
/// **Usage:**
/// Implement [DatabaseConnection] for your specific `postgres` package version
/// and pass it to [DatabaseWrapper].  This class shows the introspection
/// queries to use.
abstract class PostgresAdapter implements DatabaseConnection {
  // ── Schema Introspection ──────────────────────────────────────────────────

  /// Introspects the PostgreSQL database and returns a [DatabaseSchema].
  Future<DatabaseSchema> introspectSchema({
    String schema = 'public',
  }) async {
    QaLogger.info('PostgresAdapter: introspecting schema "$schema"...');

    final tablesResult = await query('''
      SELECT
        t.table_name,
        t.table_schema,
        COALESCE(s.n_live_tup, 0) AS approximate_row_count
      FROM information_schema.tables t
      LEFT JOIN pg_stat_user_tables s
        ON s.schemaname = t.table_schema
        AND s.relname    = t.table_name
      WHERE t.table_schema = '$schema'
        AND t.table_type = 'BASE TABLE'
      ORDER BY t.table_name
    ''');

    final tables = <TableSchema>[];

    for (final row in tablesResult) {
      final tableName = row['table_name'] as String;

      final cols = await _loadColumns(tableName, schema);
      final idxs = await _loadIndexes(tableName, schema);

      tables.add(TableSchema(
        name: tableName,
        schema: schema,
        columns: cols,
        indexes: idxs,
        approximateRowCount: (row['approximate_row_count'] as num?)?.toInt(),
      ));
    }

    QaLogger.info(
        'PostgresAdapter: introspected ${tables.length} tables.');

    return DatabaseSchema(
      tables: tables,
      engineName: 'postgresql',
      engineVersion: await _getVersion(),
      loadedAt: DateTime.now(),
    );
  }

  /// Runs EXPLAIN ANALYZE on [sql] and parses the result.
  Future<ExplainPlan> explainAnalyze(String sql) async {
    final rows = await query('EXPLAIN (ANALYZE, FORMAT TEXT) $sql');
    final output = rows.map((r) => r.values.first.toString()).join('\n');

    return ExplainPlan(
      rawOutput: output,
      hasSeqScan: output.contains('Seq Scan'),
      estimatedCost: _extractCost(output),
      actualTimeMs: _extractActualTime(output),
    );
  }

  // ── Private introspection helpers ─────────────────────────────────────────

  Future<List<ColumnSchema>> _loadColumns(
    String tableName,
    String schema,
  ) async {
    final rows = await query('''
      SELECT
        c.column_name,
        c.data_type,
        c.is_nullable,
        c.column_default,
        CASE WHEN pk.column_name IS NOT NULL THEN TRUE ELSE FALSE END AS is_pk,
        CASE WHEN idx.column_name IS NOT NULL THEN TRUE ELSE FALSE END AS has_index
      FROM information_schema.columns c
      LEFT JOIN (
        SELECT ku.column_name
        FROM information_schema.key_column_usage ku
        JOIN information_schema.table_constraints tc
          ON tc.constraint_name = ku.constraint_name
          AND tc.constraint_type = 'PRIMARY KEY'
          AND tc.table_name = '$tableName'
          AND tc.table_schema = '$schema'
      ) pk ON pk.column_name = c.column_name
      LEFT JOIN (
        SELECT DISTINCT a.attname AS column_name
        FROM pg_index i
        JOIN pg_class c2 ON c2.oid = i.indrelid
        JOIN pg_attribute a ON a.attrelid = c2.oid AND a.attnum = ANY(i.indkey)
        JOIN pg_namespace n ON n.oid = c2.relnamespace
        WHERE c2.relname = '$tableName' AND n.nspname = '$schema'
      ) idx ON idx.column_name = c.column_name
      WHERE c.table_name = '$tableName'
        AND c.table_schema = '$schema'
      ORDER BY c.ordinal_position
    ''');

    return rows
        .map((r) => ColumnSchema(
              name: r['column_name'] as String,
              dataType: r['data_type'] as String,
              nullable: (r['is_nullable'] as String) == 'YES',
              isPrimaryKey: (r['is_pk'] as bool?) ?? false,
              hasIndex: (r['has_index'] as bool?) ?? false,
              defaultValue: r['column_default'] as String?,
            ))
        .toList();
  }

  Future<List<IndexSchema>> _loadIndexes(
    String tableName,
    String schema,
  ) async {
    final rows = await query('''
      SELECT
        i.relname AS index_name,
        ix.indisunique AS is_unique,
        ix.indisprimary AS is_primary,
        am.amname AS index_type,
        ARRAY(
          SELECT a.attname
          FROM pg_attribute a
          WHERE a.attrelid = t.oid
            AND a.attnum = ANY(ix.indkey)
          ORDER BY array_position(ix.indkey, a.attnum)
        ) AS columns
      FROM pg_class t
      JOIN pg_index ix ON ix.indrelid = t.oid
      JOIN pg_class i  ON i.oid = ix.indexrelid
      JOIN pg_am am    ON am.oid = i.relam
      JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE t.relname = '$tableName' AND n.nspname = '$schema'
    ''');

    return rows
        .map((r) => IndexSchema(
              name: r['index_name'] as String,
              tableName: tableName,
              columns: List<String>.from(r['columns'] as List),
              isUnique: (r['is_unique'] as bool?) ?? false,
              isPrimary: (r['is_primary'] as bool?) ?? false,
              indexType: (r['index_type'] as String).toUpperCase(),
            ))
        .toList();
  }

  Future<String?> _getVersion() async {
    try {
      final rows = await query('SELECT version()');
      return rows.isNotEmpty ? rows.first.values.first.toString() : null;
    } catch (_) {
      return null;
    }
  }

  double? _extractCost(String explainOutput) {
    final m =
        RegExp(r'cost=[\d.]+\.\.([\d.]+)').firstMatch(explainOutput);
    return m != null ? double.tryParse(m.group(1) ?? '') : null;
  }

  double? _extractActualTime(String explainOutput) {
    final m =
        RegExp(r'actual time=[\d.]+\.\.([\d.]+)').firstMatch(explainOutput);
    return m != null ? double.tryParse(m.group(1) ?? '') : null;
  }
}
