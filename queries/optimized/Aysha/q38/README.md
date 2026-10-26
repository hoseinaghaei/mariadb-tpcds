# TPC-DS Query 38 – MariaDB Optimization (SF4)

**Query:** TPC-DS Hot Customers (query 38)

**Objective:** Count the distinct (last name, first name, date) combinations that appear in
store, catalog **and** web sales during a 12-month period (`d_month_seq` 1176 to 1187).

> All measurements below are from the **SF4** dataset (`tpcds_sf4`), MariaDB, warm cache,
> using `ANALYZE FORMAT=JSON`. Row counts, timings and memory settings are specific to SF4.

## Results

| Version | Runtime | Speedup vs. baseline |
|---|---|---|
| Original, no indexes, default settings | 75 s | 1× |
| Original + indexes + session settings | 29 s | ~2.6× |
| **Rewritten query + indexes** | **4.1 s** | **~18×** |

The rewrite alone takes the indexed query from 29 s to 4.1 s (~7×).

---

## 1. Why the original was slow (SF4 plan)

The original query builds three `SELECT DISTINCT` sets and intersects them.

| Branch | Branch time | Rows reaching `DISTINCT` |
|---|---|---|
| store | 18.2 s | 2.12M |
| catalog | 9.0 s | 1.14M |
| web | 3.8 s | 0.57M |

- **Reading was already cheap.** The three index scans plus the `customer` lookups took about
  1.6 s in total. The sales indexes were covering (`using_index`) and the join order was
  already date, then sales, then `customer` by primary key.
- **Deduplication was the cost.** Most of the remaining ~29 s went into inserting millions of
  wide `(last_name, first_name, d_date)` rows into temporary tables for `DISTINCT`.
- **Most of that work was thrown away.** The three sets intersect down to only **316 rows**.

Join reordering alone could not fix this, because the problem was how many rows were
deduplicated, not how they were read.

## 2. What changed

### Query rewrite (the main gain)

Instead of three independent sets plus `INTERSECT`, the query is a chain:

1. **Web (smallest channel)** is built once and deduplicated, giving set `w`.
2. **Catalog** keeps only rows that match `w`, giving set `cw`.
3. **Store** keeps only rows that match `cw`, then `COUNT(*)`.

Probing a small set costs far less than inserting millions of rows into a dedup table.
Other details:

- `STRAIGHT_JOIN` fixes the join order: `date_dim` → sales table → `customer` → previous set.
- **Null-safe joins (`<=>`) on the names.** `INTERSECT` treats `NULL` as equal to `NULL`,
  but a plain `=` join drops those rows. An earlier version using `=` returned a different
  count than the original for this reason. `<=>` makes the semantics match.
- The outer `LIMIT 100` was dropped. `COUNT(*)` returns one row, so it did nothing.

### Indexes

| Table | Index | Columns | Purpose |
|---|---|---|---|
| `store_sales` | `idx_ss_date_customer` | `ss_sold_date_sk, ss_customer_sk` | covering date + customer scan |
| `catalog_sales` | `idx_cs_date_customer` | `cs_sold_date_sk, cs_bill_customer_sk` | covering date + customer scan |
| `web_sales` | `idx_ws_date_customer` | `ws_sold_date_sk, ws_bill_customer_sk` | covering date + customer scan |
| `date_dim` | `idx_date_month_date_sk` | `d_month_seq, d_date_sk` | range on month, index-only |

Index sizes on the sales tables were not measured. Check them with:

```sql
SELECT table_name, index_name,
       ROUND(stat_value * @@innodb_page_size / 1024 / 1024, 1) AS size_mb
FROM mysql.innodb_index_stats
WHERE database_name = 'tpcds_sf4' AND stat_name = 'size'
  AND index_name IN ('idx_ss_date_customer','idx_cs_date_customer',
                     'idx_ws_date_customer','idx_date_month_date_sk')
ORDER BY size_mb DESC;
```

The three sales-table indexes grow with the fact tables, so their cost scales with the scale
factor. The `date_dim` index is tiny and fixed (73,049 rows at every scale factor).

### Session settings

| Setting | Value | Role |
|---|---|---|
| `tmp_table_size` | 256 MB | keeps `w` and `cw` in memory |
| `max_heap_table_size` | 256 MB | must match `tmp_table_size` to take effect |

`join_buffer_size` and the `optimizer_switch` line from the earlier version are not needed
by the rewritten query: it has no block-nested-loop joins and no `IN`/`EXISTS` subqueries.
Those settings can be removed.

---

## 3. Setup

```sql
CREATE INDEX idx_ss_date_customer ON store_sales   (ss_sold_date_sk, ss_customer_sk);
CREATE INDEX idx_cs_date_customer ON catalog_sales (cs_sold_date_sk, cs_bill_customer_sk);
CREATE INDEX idx_ws_date_customer ON web_sales     (ws_sold_date_sk, ws_bill_customer_sk);
CREATE INDEX idx_date_month_date_sk ON date_dim    (d_month_seq, d_date_sk);

ANALYZE TABLE store_sales, catalog_sales, web_sales, date_dim, customer;

SET SESSION tmp_table_size      = 256*1024*1024;
SET SESSION max_heap_table_size = 256*1024*1024;
```

Rollback:

```sql
DROP INDEX idx_ss_date_customer   ON store_sales;
DROP INDEX idx_cs_date_customer   ON catalog_sales;
DROP INDEX idx_ws_date_customer   ON web_sales;
DROP INDEX idx_date_month_date_sk ON date_dim;
```

## 4. Optimized query

```sql
WITH
w AS (   -- smallest channel first
  SELECT DISTINCT c.c_last_name, c.c_first_name, d.d_date
  FROM date_dim d
  STRAIGHT_JOIN web_sales ws ON ws.ws_sold_date_sk = d.d_date_sk
  STRAIGHT_JOIN customer c   ON c.c_customer_sk = ws.ws_bill_customer_sk
  WHERE d.d_month_seq BETWEEN 1176 AND 1176 + 11
),
cw AS (  -- catalog rows that also exist in web
  SELECT DISTINCT c.c_last_name, c.c_first_name, d.d_date
  FROM date_dim d
  STRAIGHT_JOIN catalog_sales cs ON cs.cs_sold_date_sk = d.d_date_sk
  STRAIGHT_JOIN customer c       ON c.c_customer_sk = cs.cs_bill_customer_sk
  STRAIGHT_JOIN w ON w.c_last_name  <=> c.c_last_name
                 AND w.c_first_name <=> c.c_first_name
                 AND w.d_date       =   d.d_date
  WHERE d.d_month_seq BETWEEN 1176 AND 1176 + 11
)
SELECT COUNT(*) FROM (  -- store rows that exist in catalog and web
  SELECT DISTINCT c.c_last_name, c.c_first_name, d.d_date
  FROM date_dim d
  STRAIGHT_JOIN store_sales ss ON ss.ss_sold_date_sk = d.d_date_sk
  STRAIGHT_JOIN customer c     ON c.c_customer_sk = ss.ss_customer_sk
  STRAIGHT_JOIN cw ON cw.c_last_name  <=> c.c_last_name
                  AND cw.c_first_name <=> c.c_first_name
                  AND cw.d_date       =   d.d_date
  WHERE d.d_month_seq BETWEEN 1176 AND 1176 + 11
) hot_cust;
```

## 5. Execution flow

```
date_dim (365 days, d_month_seq 1176-1187)
   |
   |-- 1. web_sales     -> customer -> DISTINCT ------------------> w   (up to 567k rows)
   |
   |-- 2. catalog_sales -> customer -> probe w  (match only) -> DISTINCT -> cw
   |
   '-- 3. store_sales   -> customer -> probe cw (match only) -> DISTINCT -> COUNT(*)
```

## 6. Verifying correctness

The original plan's intersect produced **316 rows**, so `COUNT(*)` should match the original
query's result exactly. Always compare the two counts after any change.

Check whether NULL names matter in your data:

```sql
SELECT COUNT(*) FROM customer WHERE c_last_name IS NULL OR c_first_name IS NULL;
```

If this returns 0, plain `=` would also work. If it is non-zero, keep `<=>`.

In `ANALYZE FORMAT=JSON`, confirm for the `w` and `cw` probes that the access type is `ref`
(or `ref_or_null`) on an auto key, not `ALL`.

## 7. Notes

- Session settings apply only to the current connection. Indexes persist until dropped.
- Timings are SF4 and warm cache. Re-measure at other scale factors. The filter chain should
  help more as the sales tables grow, but the memory settings may need to be raised so the
  intermediate sets stay in memory.
- If `Created_tmp_disk_tables` rises (`SHOW SESSION STATUS LIKE 'Created_tmp%'`), increase
  `tmp_table_size` and `max_heap_table_size`.
- Further tuning is probably not worthwhile at 4.1 s unless the query runs very often.