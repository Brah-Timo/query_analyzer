import '../../lib/src/models/database_schema.dart';

/// Pre-built [DatabaseSchema] objects used across tests.
abstract final class TestSchemas {
  /// A simple e-commerce schema with users, products, orders, and reviews.
  static DatabaseSchema get ecommerce {
    final usersTable = TableSchema(
      name: 'users',
      schema: 'public',
      columns: [
        const ColumnSchema(name: 'id', dataType: 'INTEGER', isPrimaryKey: true, hasIndex: true),
        const ColumnSchema(name: 'email', dataType: 'TEXT', hasIndex: true),
        const ColumnSchema(name: 'name', dataType: 'TEXT'),
        const ColumnSchema(name: 'status', dataType: 'TEXT'),
        const ColumnSchema(name: 'created_at', dataType: 'TIMESTAMP'),
      ],
      indexes: [
        const IndexSchema(name: 'users_pkey', tableName: 'users', columns: ['id'], isPrimary: true),
        const IndexSchema(name: 'idx_users_email', tableName: 'users', columns: ['email'], isUnique: true),
      ],
      approximateRowCount: 50000,
    );

    final productsTable = TableSchema(
      name: 'products',
      schema: 'public',
      columns: [
        const ColumnSchema(name: 'id', dataType: 'INTEGER', isPrimaryKey: true, hasIndex: true),
        const ColumnSchema(name: 'name', dataType: 'TEXT'),
        const ColumnSchema(name: 'category_id', dataType: 'INTEGER', hasIndex: true),
        const ColumnSchema(name: 'price', dataType: 'DECIMAL'),
        const ColumnSchema(name: 'stock', dataType: 'INTEGER'),
      ],
      indexes: [
        const IndexSchema(name: 'products_pkey', tableName: 'products', columns: ['id'], isPrimary: true),
        const IndexSchema(name: 'idx_products_category', tableName: 'products', columns: ['category_id']),
      ],
      approximateRowCount: 10000,
    );

    final ordersTable = TableSchema(
      name: 'orders',
      schema: 'public',
      columns: [
        const ColumnSchema(name: 'id', dataType: 'INTEGER', isPrimaryKey: true, hasIndex: true),
        // user_id intentionally NOT indexed to trigger missing-index detection
        const ColumnSchema(name: 'user_id', dataType: 'INTEGER'),
        const ColumnSchema(name: 'total', dataType: 'DECIMAL'),
        const ColumnSchema(name: 'status', dataType: 'TEXT'),
        const ColumnSchema(name: 'created_at', dataType: 'TIMESTAMP'),
      ],
      indexes: [
        const IndexSchema(name: 'orders_pkey', tableName: 'orders', columns: ['id'], isPrimary: true),
      ],
      approximateRowCount: 500000,
    );

    final reviewsTable = TableSchema(
      name: 'reviews',
      schema: 'public',
      columns: [
        const ColumnSchema(name: 'id', dataType: 'INTEGER', isPrimaryKey: true, hasIndex: true),
        const ColumnSchema(name: 'product_id', dataType: 'INTEGER', hasIndex: true),
        const ColumnSchema(name: 'user_id', dataType: 'INTEGER'),
        const ColumnSchema(name: 'rating', dataType: 'INTEGER'),
        const ColumnSchema(name: 'body', dataType: 'TEXT'),
      ],
      indexes: [
        const IndexSchema(name: 'reviews_pkey', tableName: 'reviews', columns: ['id'], isPrimary: true),
        const IndexSchema(name: 'idx_reviews_product', tableName: 'reviews', columns: ['product_id']),
      ],
      approximateRowCount: 200000,
    );

    return DatabaseSchema(
      tables: [usersTable, productsTable, ordersTable, reviewsTable],
      engineName: 'postgresql',
      engineVersion: '16.0',
      loadedAt: DateTime.now(),
    );
  }

  /// Minimal empty schema for tests that don't need schema awareness.
  static DatabaseSchema get empty => DatabaseSchema.empty('postgresql');
}
