/// Sample SQL queries used across unit and integration tests.
abstract final class SampleQueries {
  // ── Good queries (should not trigger issues) ──────────────────────────────

  /// Simple parametrized SELECT with indexed column.
  static const String simpleSelect =
      "SELECT id, email, name FROM users WHERE id = ?";

  /// Paginated SELECT.
  static const String paginatedSelect =
      "SELECT id, title FROM posts WHERE published = 1 ORDER BY created_at DESC LIMIT 20 OFFSET 0";

  /// INSERT with named parameters.
  static const String insertUser =
      "INSERT INTO users (email, name, created_at) VALUES (?, ?, ?)";

  /// UPDATE with WHERE.
  static const String updateStatus =
      "UPDATE jobs SET status = 'completed' WHERE id = ? AND worker_id = ?";

  // ── Problematic queries ───────────────────────────────────────────────────

  /// Full table scan — no WHERE clause.
  static const String fullTableScan = "SELECT * FROM users";

  /// Full table scan — no WHERE, no LIMIT on large table.
  static const String unboundedSelect =
      "SELECT id, email, status FROM orders";

  /// SELECT * without LIMIT.
  static const String selectStar =
      "SELECT * FROM products WHERE category = 'electronics'";

  /// N+1 prone — would be executed in a loop.
  static const String nPlusOneQuery =
      "SELECT * FROM comments WHERE post_id = ?";

  /// Correlated sub-query.
  static const String correlatedSubquery = """
    SELECT u.id, u.name,
           (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) AS order_count
    FROM users u
    WHERE u.status = 'active'
  """;

  /// Deeply nested sub-query.
  static const String deepSubquery = """
    SELECT *
    FROM users
    WHERE id IN (
      SELECT user_id FROM orders
      WHERE total > (
        SELECT AVG(total) FROM orders
        WHERE created_at > DATE('now', '-30 days')
      )
    )
  """;

  /// JOIN without index on join column.
  static const String joinWithoutIndex = """
    SELECT u.name, o.total
    FROM users u
    INNER JOIN orders o ON u.email = o.user_email
    WHERE o.status = 'pending'
  """;

  /// No LIMIT on a multi-table JOIN.
  static const String cartesianRisk = """
    SELECT p.name, c.name AS category_name
    FROM products p
    INNER JOIN categories c ON p.category_id = c.id
  """;

  /// Aggregate on large table.
  static const String expensiveAggregate =
      "SELECT COUNT(*), SUM(total), AVG(total) FROM orders";

  // ── Edge cases ────────────────────────────────────────────────────────────

  /// Empty / whitespace query.
  static const String emptyQuery = '   ';

  /// DDL statement.
  static const String ddlStatement =
      "CREATE INDEX idx_users_email ON users(email)";

  /// Very long query.
  static final String longQuery =
      'SELECT ' + List.generate(50, (i) => 'col$i').join(', ') + ' FROM big_table';
}
