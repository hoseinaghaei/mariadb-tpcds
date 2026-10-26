# TPC-DS Query 58 – MariaDB Optimization (SF4)

Optimized version of TPC-DS query 58 (items whose store, catalog and web revenue
are within ±10% of each other in the week of 1998-03-14).

| Version | Runtime | Speedup |
|---|---|---|
| Original (`queries/mariadb/query58.sql`) | 43,393 ms | 1× |
| Rewrite (date first, `STRAIGHT_JOIN`) | 709 ms | ~61× |
| Rewrite + `date_dim` indexes | **365 ms** | **~119×** |

Measured with `ANALYZE FORMAT=JSON`, database `tpcds_sf4`, warm cache.

---

## 1. Why the original was slow

The three CTEs (`ss_items`, `cs_items`, `ws_items`) took 25.1 s, 10.9 s and 7.2 s.
The final join, sort and `LIMIT` took ~0.1 s.

The optimizer ran each CTE in the wrong order:

1. Full scan of `item` (46k rows)
2. For each item, probe the sales table by `ss_item_sk` (primary key)
3. For each sales row, look up `date_dim`
4. Apply the week filter last

So the filter that keeps ~0.2% of rows was applied at the very end.

| CTE | Sales rows read (original) | Rows actually needed |
|---|---|---|
| store_sales | 11.0M | ~24k |
| catalog_sales | 5.7M | ~12.8k |
| web_sales | 2.9M | ~5.8k |

The `d_date IN (subquery)` semi-join was also materialized and probed per row
(11M lookups in the store CTE alone), and `date_dim` was full-scanned 6 times (73k rows each).

## 2. What changed

1. **Filter first.** Resolve the week to its 7 `d_date_sk` values, then drive from
   those dates into the sales tables using the existing `(sold_date_sk, item_sk)` indexes.
2. **Subquery flattening.** The `d_date IN (...)` semi-join became a plain join on a
   7-row derived table (`wk`). `d_date` is unique in `date_dim`, so the result is identical.
3. **Join order forced with `STRAIGHT_JOIN`:** `wk` → sales table → `item` (primary key).
   The final join starts from the smallest CTE (`ws_items`, ~5k rows).
4. **Two small indexes on `date_dim`** so the week and date lookups are index lookups
   instead of 73k-row scans.
5. Inner joins were kept. LEFT/RIGHT joins would not be faster, since the WHERE
   conditions already require a match in every CTE.

## 3. Indexes

Run once:

```sql
CREATE INDEX idx_dd_week ON date_dim (d_week_seq);
CREATE INDEX idx_dd_date ON date_dim (d_date);
ANALYZE TABLE date_dim;
```

| Table | Index | Columns | Size | Status |
|---|---|---|---|---|
| `date_dim` | `idx_dd_week` | `d_week_seq` | 2.52 MB | new |
| `date_dim` | `idx_dd_date` | `d_date` | 1.52 MB | new |
| `date_dim` | `PRIMARY` | `d_date_sk` | 15.55 MB | existing (table data) |
| `store_sales` | `idx_ss_date_store_item_price` | `ss_sold_date_sk, ss_store_sk, ss_item_sk, ss_sales_price` | n/a | existing, used |
| `catalog_sales` | `idx_cs_date_item` | `cs_sold_date_sk, cs_item_sk` | n/a | existing, used |
| `web_sales` | `idx_ws_date_item` | `ws_sold_date_sk, ws_item_sk` | n/a | existing, used |

**Storage cost: 4.04 MB total** (26% on top of the 15.55 MB `date_dim` table).
`date_dim` is a fixed 73,049-row table at every TPC-DS scale factor, and it is
read-only, so the cost does not grow with scale and there is no write overhead.

No new indexes were needed on the sales tables.

Check index sizes:

```sql
SELECT table_name, index_name,
       ROUND(stat_value * @@innodb_page_size / 1024 / 1024, 2) AS size_mb
FROM mysql.innodb_index_stats
WHERE database_name = 'tpcds_sf4' AND stat_name = 'size'
  AND table_name IN ('date_dim','store_sales','catalog_sales','web_sales')
ORDER BY table_name, size_mb DESC;
```

## 4. Optimized query

```sql
SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');  -- optional, see notes

WITH
ss_items AS (
  SELECT i_item_id item_id, SUM(ss_ext_sales_price) ss_item_rev
  FROM (SELECT d_date_sk
        FROM date_dim
        WHERE d_week_seq = (SELECT d_week_seq FROM date_dim WHERE d_date = '1998-03-14')
       ) wk
  STRAIGHT_JOIN store_sales ss ON ss.ss_sold_date_sk = wk.d_date_sk
  STRAIGHT_JOIN item i         ON i.i_item_sk = ss.ss_item_sk
  GROUP BY i_item_id
),
cs_items AS (
  SELECT i_item_id item_id, SUM(cs_ext_sales_price) cs_item_rev
  FROM (SELECT d_date_sk
        FROM date_dim
        WHERE d_week_seq = (SELECT d_week_seq FROM date_dim WHERE d_date = '1998-03-14')
       ) wk
  STRAIGHT_JOIN catalog_sales cs ON cs.cs_sold_date_sk = wk.d_date_sk
  STRAIGHT_JOIN item i           ON i.i_item_sk = cs.cs_item_sk
  GROUP BY i_item_id
),
ws_items AS (
  SELECT i_item_id item_id, SUM(ws_ext_sales_price) ws_item_rev
  FROM (SELECT d_date_sk
        FROM date_dim
        WHERE d_week_seq = (SELECT d_week_seq FROM date_dim WHERE d_date = '1998-03-14')
       ) wk
  STRAIGHT_JOIN web_sales ws ON ws.ws_sold_date_sk = wk.d_date_sk
  STRAIGHT_JOIN item i       ON i.i_item_sk = ws.ws_item_sk
  GROUP BY i_item_id
)
SELECT ss_items.item_id, ss_item_rev,
       ss_item_rev/((ss_item_rev+cs_item_rev+ws_item_rev)/3)*100 ss_dev,
       cs_item_rev,
       cs_item_rev/((ss_item_rev+cs_item_rev+ws_item_rev)/3)*100 cs_dev,
       ws_item_rev,
       ws_item_rev/((ss_item_rev+cs_item_rev+ws_item_rev)/3)*100 ws_dev,
       (ss_item_rev+cs_item_rev+ws_item_rev)/3 average
FROM ws_items
STRAIGHT_JOIN cs_items ON cs_items.item_id = ws_items.item_id
STRAIGHT_JOIN ss_items ON ss_items.item_id = ws_items.item_id
WHERE ss_item_rev BETWEEN 0.9*cs_item_rev AND 1.1*cs_item_rev
  AND ss_item_rev BETWEEN 0.9*ws_item_rev AND 1.1*ws_item_rev
  AND cs_item_rev BETWEEN 0.9*ws_item_rev AND 1.1*ws_item_rev
ORDER BY item_id, ss_item_rev
LIMIT 100;
```

## 5. Before and after (per CTE)

| CTE | Original | Optimized | Sales rows read (before → after) |
|---|---|---|---|
| `ss_items` | 25,127 ms | 206 ms | 11.0M → 24k |
| `cs_items` | 10,948 ms | 91 ms | 5.7M → 12.8k |
| `ws_items` | 7,237 ms | 51 ms | 2.9M → 5.8k |
| Final join + sort | ~100 ms | ~17 ms | n/a |

`date_dim` access in each CTE went from a full scan (73,049 rows) to
`ref` on `idx_dd_week` (7 rows, `using_index`).

What to look for in `ANALYZE FORMAT=JSON` to confirm the good plan:

- `date_dim`: `access_type: ref`, `key: idx_dd_week`, `r_rows: 7`
- Sales table: `key: idx_*_date_*`, `r_rows` in the thousands
- `item`: `eq_ref` on `PRIMARY`
- Total `r_total_time_ms` of a few hundred ms

## 6. Notes and caveats

- **Empty result.** For `1998-03-14` the query returns 0 rows in both the original
  and the optimized plan (no item has all three revenues within ±10%). Correctness
  was therefore checked through identical intermediate row counts (15,037 / 9,876 / 5,160),
  not through result rows. To verify with real rows, run original and optimized for another
  date, or temporarily widen the 0.9 / 1.1 band, and compare outputs.
- **Redundant predicates.** The original had six `BETWEEN` conditions; this version keeps
  three. If you need a guaranteed identical result for every input, add back:
  `cs_item_rev BETWEEN 0.9*ss_item_rev AND 1.1*ss_item_rev`,
  `ws_item_rev BETWEEN 0.9*ss_item_rev AND 1.1*ss_item_rev`,
  `ws_item_rev BETWEEN 0.9*cs_item_rev AND 1.1*cs_item_rev`.
- **Warm cache.** Timings are from a warm buffer pool. Page counts are small
  (17k–74k pages per table, versus 33M for `date_dim` before), so cold-cache cost should stay low.
- **`sql_mode` line.** Not needed for query 58. See the explanation in the section below.
- **Run `ANALYZE TABLE`** on `date_dim` (and the other tables) after loading data so the
  optimizer keeps choosing these indexes.

## 7. Optional further tweaks (not needed at 365 ms)

| Idea | Expected gain | Cost |
|---|---|---|
| Aggregate by `item_sk` first, then join `item` and group by `i_item_id` | ~30–60 ms (estimate, unmeasured) | none |
| Covering index `(ss_sold_date_sk, ss_item_sk, ss_ext_sales_price)` on `store_sales` | ~50 ms | hundreds of MB |

Remaining time is real work: ~43k sales rows read and ~43k `item` primary-key lookups.

## 8. What the `sql_mode` line does

```sql
SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');
```

- `SET SESSION` applies to the current connection only.
- `CONCAT(@@sql_mode, ...)` adds modes to the existing ones instead of replacing them.
- `IGNORE_SPACE` allows a space between a function name and `(`, such as `SUM (x)`.
- `PIPES_AS_CONCAT` treats `||` as string concatenation instead of logical OR.

Some TPC-DS queries use `||` or `func (` spacing, so benchmark scripts set this once for every
query. Query 58 uses neither, so the line is harmless but unnecessary here.