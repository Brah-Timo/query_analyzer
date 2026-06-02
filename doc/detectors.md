# Detectors

`query_analyzer` ships five built-in detectors.  Each one analyses
a `ParsedQuery` (and optionally the raw SQL string) and returns a list
of `QueryIssue` objects.  All detectors are orchestrated by `PatternDetector`,
which deduplicates issues before returning them to `QueryAnalyzerCore`.

---

## FullTableScanDetector

**Config toggle:** `detectFullTableScan`

Detects queries that will force the database engine to read every row in a
table.

### Rule 1 — No WHERE clause on a potentially large table

```sql
-- flagged: no WHERE on a table that may have many rows
SELECT * FROM orders
```

Severity: `high` (or `critical` if the table has > 100 000 rows in schema).

### Rule 2 — WHERE column has no index

Requires a `DatabaseSchema` with index information.

```sql
-- flagged if orders.status has no index
SELECT id FROM orders WHERE status = 'pending'
```

Severity: `high`.

### Rule 3 — LIKE operator (potential leading wildcard)

```sql
-- flagged because LIKE on a column may negate index usage
SELECT id FROM users WHERE email LIKE '%@example.com'
```

Severity: `medium`.

---

## MissingIndexDetector

**Config toggle:** `detectMissingIndex`

Detects columns referenced in WHERE or JOIN conditions that are not indexed.
Requires a `DatabaseSchema` with index metadata.

### WHERE columns

```sql
-- flagged if orders.created_at has no index
SELECT id FROM orders WHERE created_at > '2025-01-01'
```

Severity: based on approximate row count (low < medium < high < critical
at 10k / 100k / 1M rows).

### JOIN columns

```sql
-- flagged if order_items.order_id has no index on the joined table
SELECT o.id, oi.product_id
FROM orders o
JOIN order_items oi ON o.id = oi.order_id
```

Severity: `high` (JOIN column) or `medium` (left-side JOIN column).

### Foreign-key heuristic

Columns ending in `_id` or `Id` are flagged as foreign keys and receive a
specialized suggestion with `CREATE INDEX CONCURRENTLY` and a
`documentationUrl`.

---

## NPlusOneDetector

**Config toggle:** `detectNPlusOne`  
**Tuning:** `nPlusOneWindowMs`, `nPlusOneMinCount`

Detects the classic ORM anti-pattern where the same query is executed N+1
times in a loop.

The detector maintains a sliding time window of recent query fingerprints.
A fingerprint is the 8-char hex hash of the normalized SQL (literals replaced
with `?`).  When the same fingerprint appears `nPlusOneMinCount` or more
times within `nPlusOneWindowMs` milliseconds, an issue is flagged.

```dart
// This triggers N+1 detection (assuming nPlusOneMinCount: 5):
for (final userId in userIds) {
  await db.query('SELECT * FROM orders WHERE user_id = ?', arguments: [userId]);
}
```

Severity: `high` if count == minCount, escalates to `critical` when
count > `minCount * 3`.

**Fix:** Use a single JOIN query or batch-load all orders in one
`WHERE user_id IN (?)` query.

### Resetting the window

```dart
core.storage; // MetricsStorage reset clears the window
// or:
// Access the PatternDetector via subclass / custom integration
```

In tests you can call `core.reset()` between test cases to start fresh.

---

## LargeResultDetector

**Config toggle:** `detectLargeResult`  
**Tuning:** `largeResultRowThreshold`

Detects queries likely to return an excessively large number of rows.

### Rule 1 — Actual row count ≥ threshold (post-execution)

When `DatabaseWrapper` passes `actualRowCount` to `analyzeQuery`, and that
count exceeds `largeResultRowThreshold`:

```sql
-- flagged if 15 000 rows were returned and threshold is 10 000
SELECT * FROM audit_log
```

Severity: `high` (or `critical` if count ≥ threshold × 10).

### Rule 2 — No LIMIT and no WHERE

```sql
SELECT id, name FROM products   -- no LIMIT, no WHERE
```

Severity: `high`.

### Rule 3 — Unconstrained JOIN with no LIMIT

```sql
SELECT * FROM orders JOIN customers ON orders.customer_id = customers.id
```

Severity: `critical` (Cartesian explosion risk).

### Rule 4 — SELECT * with no LIMIT

```sql
SELECT * FROM large_table
```

Produces a `selectStar` issue (severity: `medium`).

---

## SubqueryDetector

**Config toggle:** `detectSubqueryIssues`  
**Tuning:** `kMaxSubqueryDepth` (constant, currently `3`)

Detects problematic sub-query usage.

### Rule 1 — Deeply nested sub-queries

```sql
SELECT * FROM a WHERE id IN (
  SELECT id FROM b WHERE id IN (
    SELECT id FROM c WHERE id IN (
      SELECT id FROM d   -- depth 3, flagged at depth > 3
    )
  )
)
```

Severity: `high`.

### Rule 2 — Correlated sub-query

A correlated sub-query references a column from the outer query and is
re-executed for every outer row.

```sql
SELECT o.id,
  (SELECT MAX(amount) FROM payments p WHERE p.order_id = o.id) AS max_payment
FROM orders o
```

Severity: `critical`.

### Rule 3 — Sub-query in SELECT list

```sql
SELECT id, name,
  (SELECT COUNT(*) FROM orders WHERE customer_id = c.id) AS order_count
FROM customers c
```

Severity: `high`.

---

## Custom Detectors

The five built-in detectors cover the most common patterns.  If your use
case requires additional rules, you have two options:

### Option A — Pre-processing hook

Implement a `QueryListener` that inspects `AnalyzedQuery` objects after the
fact and emits additional signals to your monitoring system.

### Option B — Subclass PatternDetector

```dart
class MyDetector extends PatternDetector {
  MyDetector({required super.schema, required super.config});

  @override
  DetectionResult detect(ParsedQuery parsed, String rawSql, {int? actualRowCount}) {
    final base = super.detect(parsed, rawSql, actualRowCount: actualRowCount);

    // Add custom issues
    final extra = <QueryIssue>[];
    if (rawSql.contains('SLEEP(')) {
      extra.add(const QueryIssue(
        type: IssueType.other,
        description: 'SLEEP() detected — remove before production',
        severity: IssueSeverity.critical,
        affectedElement: 'SLEEP',
      ));
    }

    return DetectionResult(issues: [...base.issues, ...extra]);
  }
}
```

Then pass `MyDetector` to your own `QueryAnalyzerCore` subclass.

---

## Issue Deduplication

`PatternDetector` deduplicates issues with the same `(type, affectedElement)`
pair before returning `DetectionResult`.  This prevents multiple detectors
from reporting the same issue on the same column.

## Severity Reference

| Severity | Weight | Meaning |
|----------|--------|---------|
| `low` | 1 | Minor — minimal impact. |
| `medium` | 5 | Moderate — noticeable under load. |
| `high` | 10 | Serious — significant degradation. |
| `critical` | 20 | Production outage risk. |

The `AnalyzedQuery.impactScore` is computed as:

```
impactScore = clamp(
  (isSlow ? 30 : 0)
  + sum(issue.severity.value)
  + subqueryDepth * 5
  + (selectsStar ? 5 : 0),
  0, 100
)
```
