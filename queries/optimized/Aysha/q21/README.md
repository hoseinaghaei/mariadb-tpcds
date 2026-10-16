# TPC-DS Query 21 — Optimization

## Overview

This version optimizes the original TPC-DS Query 21 while preserving the query's intended result.

The optimization focuses on:

1. Preventing MariaDB from merging the derived table.
2. Controlling the join order using `STRAIGHT_JOIN`.
3. Filtering `date_dim` before joining with the larger `inventory` table.
4. Filtering `item` before joining it with `inventory`.
5. Using explicit `JOIN ... ON` syntax instead of implicit joins.

---

## Original Query Structure

The original query joins four tables:

```text
inventory
    ↓
warehouse
    ↓
item
    ↓
date_dim
```

The query first performs the joins and aggregation:

```sql
GROUP BY w_warehouse_name, i_item_id
```

and calculates:

* `inv_before` — inventory quantity before 1998-06-18
* `inv_after` — inventory quantity on or after 1998-06-18

The outer query then filters warehouses/items based on:

```sql
inv_after / inv_before
```

and returns the first 100 results.

---

# Optimizations Applied

## 1. Disable Derived Table Merging

```sql
SET SESSION optimizer_switch = 'derived_merge=off';
```

MariaDB can normally merge a derived table (a subquery in the `FROM` clause) into the outer query.

Disabling `derived_merge` forces the derived tables to remain separate instead of allowing MariaDB to flatten them into the surrounding query.

This is useful here because the optimized query intentionally creates filtered derived tables for `date_dim` and `item`.

### Scope

The setting is:

```sql
SET SESSION
```

so it only applies to the current MariaDB connection/session. It does not permanently change the server configuration.

---

## 2. Filter `date_dim` Before Joining

The optimized query first selects only the relevant dates:

```sql
(
    SELECT d_date_sk, d_date
    FROM date_dim
    WHERE d_date BETWEEN
        (CAST('1998-06-18' AS DATE) - INTERVAL 30 DAY)
        AND
        (CAST('1998-06-18' AS DATE) + INTERVAL 30 DAY)
) fd
```

Instead of joining the complete `date_dim` table and filtering afterward, only the required approximately 61-day date range is passed to the next join.

Conceptually:

```text
date_dim
   │
   │ filter to required dates
   ▼
filtered date_dim
   │
   ▼
inventory
```

This reduces the number of date rows participating in the subsequent join.

---

## 3. Filter `item` Before Joining

The optimized query also filters `item` first:

```sql
(
    SELECT i_item_sk, i_item_id
    FROM item
    WHERE i_current_price BETWEEN 0.99 AND 1.49
) fi
```

Only items whose current price is between `0.99` and `1.49` are passed to the join with `inventory`.

Conceptually:

```text
item
  │
  │ price filter
  ▼
filtered item
  │
  ▼
inventory
```

This avoids carrying irrelevant items into the subsequent join operations.

---

## 4. Control Join Order with `STRAIGHT_JOIN`

The optimized query uses:

```sql
SELECT STRAIGHT_JOIN
```

This tells MariaDB to follow the specified join order rather than freely reordering the joins using its optimizer.

The intended order is:

```text
filtered date_dim
        ↓
    inventory
        ↓
filtered item
        ↓
    warehouse
```

This is useful because `date_dim` and `item` are filtered before the large `inventory` table is processed.

The goal is to reduce the amount of data involved in the expensive joins.

---

## 5. Explicit JOIN Conditions

The original query uses implicit joins:

```sql
FROM inventory,
     warehouse,
     item,
     date_dim
WHERE ...
```

The optimized query uses explicit joins:

```sql
FROM filtered_date fd
JOIN inventory
    ON inv_date_sk = fd.d_date_sk
JOIN filtered_item fi
    ON fi.i_item_sk = inventory.inv_item_sk
JOIN warehouse
    ON inventory.inv_warehouse_sk = w_warehouse_sk
```

This makes the join relationships explicit and makes the intended execution structure easier to understand and control.

---

# Aggregation

The aggregation itself remains logically unchanged:

```sql
GROUP BY w_warehouse_name, i_item_id
```

The query calculates two quantities:

### Inventory before the reference date

```sql
SUM(
    CASE
        WHEN d_date < '1998-06-18'
        THEN inv_quantity_on_hand
        ELSE 0
    END
) AS inv_before
```

### Inventory after/on the reference date

```sql
SUM(
    CASE
        WHEN d_date >= '1998-06-18'
        THEN inv_quantity_on_hand
        ELSE 0
    END
) AS inv_after
```

The outer query then keeps groups where:

```text
2/3 <= inv_after / inv_before <= 3/2
```

when `inv_before > 0`.

---

# Query Execution Strategy

The optimized query attempts to reduce the amount of data processed by `inventory`, which is the large fact-like table in this query.

The intended execution flow is:

```text
             date_dim
                │
         filter 61-day range
                │
                ▼
        filtered dates
                │
                ▼
           inventory
                │
        ┌───────┴────────┐
        │                │
 filtered items       warehouse
        │                │
        └───────┬────────┘
                ▼
          GROUP BY
     warehouse + item
                │
                ▼
       inv_before /
        inv_after
                │
                ▼
          ratio filter
                │
                ▼
          ORDER BY
                │
                ▼
             LIMIT 100
```

---

# Why These Changes Can Improve Performance

The main idea is **early filtering**.

The original query allows the optimizer to determine the join order itself.

The optimized query explicitly provides:

* a restricted date set,
* a restricted item set,
* a specific join order.

This can reduce the number of rows participating in expensive joins and aggregation.

However, the effectiveness depends on the data distribution, indexes, MariaDB statistics, and optimizer decisions. Therefore, the optimized query should always be benchmarked against the original query on the same dataset.

---

# Result Preservation

The following parts of the original query are preserved:

* Date range: ±30 days around `1998-06-18`
* Item price range: `0.99` to `1.49`
* Join relationships
* `inv_before` calculation
* `inv_after` calculation
* Grouping by warehouse and item
* Ratio condition
* Ordering
* `LIMIT 100`

The optimization changes the **execution strategy**, not the intended analytical logic.

---

# Files

```text
q21/
├── query21 - original.sql
├── query21 - optimized.sql
└── README.md
```

The original query is retained for correctness and performance comparison.

The optimized query contains the execution-strategy changes described above.

---

# Benchmarking

To evaluate the optimization, execute both versions using the same:

* MariaDB version
* TPC-DS SF1 dataset
* indexes
* server configuration
* database state

Compare:

```text
Original execution time
vs.
Optimized execution time
```

The optimization should only be considered successful if it provides a measurable performance improvement while returning the same result set.
