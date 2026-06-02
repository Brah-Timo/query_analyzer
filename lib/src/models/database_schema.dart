import 'package:meta/meta.dart';

/// Represents a single column within a [TableSchema].
@immutable
class ColumnSchema {
  /// Column name (case-insensitive comparison recommended).
  final String name;

  /// SQL data type as reported by the database (e.g. `TEXT`, `INTEGER`).
  final String dataType;

  /// Whether the column allows NULL values.
  final bool nullable;

  /// Whether this column is (part of) the primary key.
  final bool isPrimaryKey;

  /// Whether the column has a standalone index.
  final bool hasIndex;

  /// Default value expression (nullable).
  final String? defaultValue;

  /// Creates a [ColumnSchema].
  const ColumnSchema({
    required this.name,
    required this.dataType,
    this.nullable = true,
    this.isPrimaryKey = false,
    this.hasIndex = false,
    this.defaultValue,
  });

  /// Returns `true` if the column is likely a foreign key (heuristic).
  bool get looksLikeForeignKey =>
      name.endsWith('_id') || name.endsWith('Id');

  Map<String, dynamic> toJson() => {
        'name': name,
        'dataType': dataType,
        'nullable': nullable,
        'isPrimaryKey': isPrimaryKey,
        'hasIndex': hasIndex,
        if (defaultValue != null) 'defaultValue': defaultValue,
      };

  @override
  String toString() =>
      'ColumnSchema($name $dataType${isPrimaryKey ? " PK" : ""}${hasIndex ? " IDX" : ""})';
}

/// Represents a database index.
@immutable
class IndexSchema {
  /// Index name.
  final String name;

  /// The table this index belongs to.
  final String tableName;

  /// Indexed columns in order.
  final List<String> columns;

  /// Whether this is a unique index.
  final bool isUnique;

  /// Whether this is the primary-key index.
  final bool isPrimary;

  /// Index type (e.g. `BTREE`, `HASH`, `GIN`).
  final String indexType;

  /// Creates an [IndexSchema].
  const IndexSchema({
    required this.name,
    required this.tableName,
    required this.columns,
    this.isUnique = false,
    this.isPrimary = false,
    this.indexType = 'BTREE',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'tableName': tableName,
        'columns': columns,
        'isUnique': isUnique,
        'isPrimary': isPrimary,
        'indexType': indexType,
      };

  @override
  String toString() =>
      'IndexSchema($name on $tableName(${columns.join(", ")})'
      '${isUnique ? " UNIQUE" : ""})';
}

/// Represents a single table in the database.
@immutable
class TableSchema {
  /// Table name.
  final String name;

  /// Schema / namespace (e.g. `public` in PostgreSQL).
  final String schema;

  /// All columns of this table.
  final List<ColumnSchema> columns;

  /// All indexes defined on this table.
  final List<IndexSchema> indexes;

  /// Approximate row count (from statistics, may be stale).
  final int? approximateRowCount;

  /// Creates a [TableSchema].
  const TableSchema({
    required this.name,
    this.schema = 'public',
    required this.columns,
    this.indexes = const [],
    this.approximateRowCount,
  });

  /// Returns columns that have an index (including PK).
  List<ColumnSchema> get indexedColumns =>
      columns.where((c) => c.hasIndex || c.isPrimaryKey).toList();

  /// Returns columns without any index.
  List<ColumnSchema> get unindexedColumns =>
      columns.where((c) => !c.hasIndex && !c.isPrimaryKey).toList();

  /// Finds a column by name (case-insensitive).
  ColumnSchema? findColumn(String columnName) => columns.firstWhere(
        (c) => c.name.toLowerCase() == columnName.toLowerCase(),
        orElse: () => throw StateError('Column "$columnName" not found in "$name"'),
      );

  /// Returns `true` if the given column name has an index.
  bool hasIndexOn(String columnName) =>
      columns.any(
        (c) =>
            c.name.toLowerCase() == columnName.toLowerCase() &&
            (c.hasIndex || c.isPrimaryKey),
      ) ||
      indexes.any(
        (i) => i.columns
            .map((c) => c.toLowerCase())
            .contains(columnName.toLowerCase()),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'schema': schema,
        'columns': columns.map((c) => c.toJson()).toList(),
        'indexes': indexes.map((i) => i.toJson()).toList(),
        if (approximateRowCount != null)
          'approximateRowCount': approximateRowCount,
      };

  @override
  String toString() =>
      'TableSchema($schema.$name, ${columns.length} cols, ${indexes.length} idx)';
}

/// The full schema of a monitored database.
@immutable
class DatabaseSchema {
  /// All tables discovered during introspection.
  final List<TableSchema> tables;

  /// Database engine name (e.g. `postgresql`, `mysql`, `sqlite`).
  final String engineName;

  /// Database version string.
  final String? engineVersion;

  /// When the schema was last refreshed.
  final DateTime loadedAt;

  /// Creates a [DatabaseSchema].
  const DatabaseSchema({
    required this.tables,
    required this.engineName,
    this.engineVersion,
    required this.loadedAt,
  });

  /// Returns an empty / unknown schema.
  factory DatabaseSchema.empty(String engineName) => DatabaseSchema(
        tables: const [],
        engineName: engineName,
        loadedAt: DateTime.now(),
      );

  /// Finds a table by name (case-insensitive).
  TableSchema? findTable(String tableName) {
    final lower = tableName.toLowerCase();
    try {
      return tables.firstWhere((t) => t.name.toLowerCase() == lower);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'engineName': engineName,
        if (engineVersion != null) 'engineVersion': engineVersion,
        'loadedAt': loadedAt.toIso8601String(),
        'tables': tables.map((t) => t.toJson()).toList(),
      };

  @override
  String toString() =>
      'DatabaseSchema($engineName, ${tables.length} tables, '
      'loaded: ${loadedAt.toIso8601String()})';
}
