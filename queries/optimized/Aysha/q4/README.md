# TPC-DS Query 4: Optimization Notes (MariaDB)

## What the query asks, in one line

Which customers' **catalog** spending grew faster from 2001 to 2002 than **both** their **store** spending and their **web** spending?

---

## Results

| Where | Hossein's best (baseline) | Aysha optimized | Speedup |
|---|---|---|---|
| Docker, SF-1 data | 54.65 s | 0.22 s | about 250x |
| DBeaver, SF-1 DB | 50 s cold / 19 s warm | 0.006 s | see caveat below |
| DBeaver, SF-4 DB | 1 min 56 s cold / 30.38 s warm | 6.9 s | about 4.4x vs warm, about 17x vs cold |

Notes on reading these numbers:

- Compare **warm vs warm** where you can. Cold runs include loading data from disk, so cold-vs-warm comparisons flatter the new query.
- The 6.9 s at SF-4 is the `ANALYZE FORMAT=JSON` total. The baseline at SF-4 measured 36.0 s in `ANALYZE` (30.38 s warm in DBeaver), so both views show a roughly 4 to 5x gain.
- **Caveat on 0.006 s:** this is faster than a full scan of the SF-1 web table could plausibly take. Before quoting it, confirm the row count and the first rows match the baseline output, and check that you are not seeing a cached result. The SF-4 figure (6.9 s) is the one backed by a full plan.

---

## Summary of what changed

1. **Date range looked up once**, then used as a plain `BETWEEN` on the sales tables. The baseline joined `date_dim` for every sales row.
2. **Order of work reversed into a funnel.** Web first (smallest), then catalog for web survivors only, then store for catalog survivors only.
3. **Two new indexes** let catalog and store be read per customer instead of scanned in full.
4. **Growth tests applied at each step**, so customers who cannot qualify are dropped early.
5. **Simpler maths:** removed `COUNT(DISTINCT d_year) = 2` and replaced division with cross-multiplication.
6. **Customer names fetched last**, only for survivors.

---

## Required indexes

```sql
CREATE INDEX idx_cs_cust ON catalog_sales (cs_bill_customer_sk, cs_sold_date_sk) ALGORITHM=INPLACE LOCK=NONE;
CREATE INDEX idx_ss_cust ON store_sales   (ss_customer_sk,      ss_sold_date_sk) ALGORITHM=INPLACE LOCK=NONE;
ANALYZE TABLE catalog_sales, store_sales;
```

- Both are deliberately **narrow** (two columns, no price columns) to save disk. At larger scale factors, covering indexes get expensive.
- `idx_ss_customer_date` in the SF-4 script has the same columns as `idx_ss_cust`. It is a **duplicate** and can be dropped to save space: `DROP INDEX idx_ss_customer_date ON store_sales;`
- Remove the indexes when finished benchmarking:

```sql
DROP INDEX idx_cs_cust ON catalog_sales;
DROP INDEX idx_ss_cust ON store_sales;
```

---

## The final query

Run as one script in one tab (Alt+X in DBeaver). The session variables must live on the same connection as the query.

```sql
SET @start_2001 = (SELECT MIN(d_date_sk) FROM date_dim WHERE d_year = 2001);
SET @start_2002 = (SELECT MIN(d_date_sk) FROM date_dim WHERE d_year = 2002);
SET @end_2002   = (SELECT MAX(d_date_sk) FROM date_dim WHERE d_year = 2002);
WITH w AS (
    SELECT ws_bill_customer_sk AS customer_sk,
           SUM(CASE WHEN ws_sold_date_sk <  @start_2002 THEN ((ws_ext_list_price - ws_ext_wholesale_cost - ws_ext_discount_amt) + ws_ext_sales_price) / 2 END) AS w_y1,
           SUM(CASE WHEN ws_sold_date_sk >= @start_2002 THEN ((ws_ext_list_price - ws_ext_wholesale_cost - ws_ext_discount_amt) + ws_ext_sales_price) / 2 END) AS w_y2
    FROM web_sales
    WHERE ws_sold_date_sk BETWEEN @start_2001 AND @end_2002
      AND ws_bill_customer_sk IS NOT NULL
    GROUP BY ws_bill_customer_sk
    HAVING w_y1 > 0 AND w_y2 IS NOT NULL
),
c AS (
    SELECT cs.cs_bill_customer_sk AS customer_sk,
           SUM(CASE WHEN cs.cs_sold_date_sk <  @start_2002 THEN ((cs.cs_ext_list_price - cs.cs_ext_wholesale_cost - cs.cs_ext_discount_amt) + cs.cs_ext_sales_price) / 2 END) AS c_y1,
           SUM(CASE WHEN cs.cs_sold_date_sk >= @start_2002 THEN ((cs.cs_ext_list_price - cs.cs_ext_wholesale_cost - cs.cs_ext_discount_amt) + cs.cs_ext_sales_price) / 2 END) AS c_y2
    FROM w
    STRAIGHT_JOIN catalog_sales cs ON cs.cs_bill_customer_sk = w.customer_sk
    WHERE cs.cs_sold_date_sk BETWEEN @start_2001 AND @end_2002
    GROUP BY cs.cs_bill_customer_sk, w.w_y1, w.w_y2
    HAVING c_y1 > 0 AND c_y2 IS NOT NULL
       AND c_y2 * w.w_y1 > w.w_y2 * c_y1
),
s AS (
    SELECT c.customer_sk
    FROM c
    STRAIGHT_JOIN store_sales ss ON ss.ss_customer_sk = c.customer_sk
    WHERE ss.ss_sold_date_sk BETWEEN @start_2001 AND @end_2002
    GROUP BY c.customer_sk, c.c_y1, c.c_y2
    HAVING SUM(CASE WHEN ss.ss_sold_date_sk <  @start_2002 THEN ((ss.ss_ext_list_price - ss.ss_ext_wholesale_cost - ss.ss_ext_discount_amt) + ss.ss_ext_sales_price) / 2 END) > 0
       AND SUM(CASE WHEN ss.ss_sold_date_sk >= @start_2002 THEN ((ss.ss_ext_list_price - ss.ss_ext_wholesale_cost - ss.ss_ext_discount_amt) + ss.ss_ext_sales_price) / 2 END) IS NOT NULL
       AND c.c_y2 * SUM(CASE WHEN ss.ss_sold_date_sk <  @start_2002 THEN ((ss.ss_ext_list_price - ss.ss_ext_wholesale_cost - ss.ss_ext_discount_amt) + ss.ss_ext_sales_price) / 2 END)
         > SUM(CASE WHEN ss.ss_sold_date_sk >= @start_2002 THEN ((ss.ss_ext_list_price - ss.ss_ext_wholesale_cost - ss.ss_ext_discount_amt) + ss.ss_ext_sales_price) / 2 END) * c.c_y1
)
SELECT cu.c_customer_id AS customer_id,
       cu.c_first_name  AS customer_first_name,
       cu.c_last_name   AS customer_last_name,
       cu.c_login       AS customer_login
FROM s
JOIN customer cu ON cu.c_customer_sk = s.customer_sk
ORDER BY customer_id, customer_first_name, customer_last_name, customer_login
LIMIT 100;
```

---

## How it works (the funnel)

Numbers are from the SF-4 `ANALYZE` plan.

```
1. Find date range once              3 tiny lookups on date_dim
        |
2. WEB: scan, keep both-year buyers  2.9M rows read      ->  7,976 customers   (about 4.5 s)
        |
3. CATALOG: only those customers     78K rows via idx_cs_cust  ->  677 customers   (about 0.8 s)
        |   keep: catalog growth > web growth
4. STORE: only those customers       12.6K rows via idx_ss_cust ->  134 customers   (about 0.2 s)
        |   keep: catalog growth > store growth
5. CUSTOMER: add names, sort         reads 179K customers     (about 1.4 s)
        |
6. Top 100 rows
```

Each step only looks at customers that survived the previous one. The big tables are never aggregated for everyone.

---

## Detailed changes and reasoning

### 1. Date range found once instead of joining `date_dim` per row

- **Before:** every sales row was joined to `date_dim` to read `d_year`, then filtered to 2001/2002.
- **After:** three tiny queries compute `@start_2001`, `@start_2002`, `@end_2002`. The sales tables then use `ss_sold_date_sk BETWEEN ...`.
- **Why:** the baseline plan showed about 11M lookups for store, 5.7M for catalog and 2.9M for web, around 20M in total. The store lookups alone took about 8 s and touched 25.9M pages. Worse, the plan sorted every row **before** the year filter, so about 60% of sorted rows were thrown away afterwards.
- **Assumption:** `d_date_sk` is contiguous and increases with the date (true for standard TPC-DS). Check that these two counts are equal:

```sql
SELECT (SELECT COUNT(*) FROM date_dim WHERE d_date_sk BETWEEN @start_2001 AND @end_2002) AS in_range,
       (SELECT COUNT(*) FROM date_dim WHERE d_year IN (2001, 2002))                      AS by_year;
```

### 2. Lesson learned: filtering by date alone was not enough

A first rewrite (one `UNION ALL` flow with `BETWEEN`) made the sorts nearly free (9.9 s down to 95 ms for store), but the plan still did a **full table scan** of every sales table because the existing date-first indexes did not contain the price columns. Total time was unchanged (36.6 s vs 36.0 s). The cost simply moved from sorting to scanning.

The real saving only came from not reading most of the rows at all, which is changes 3 and 4.

### 3. Customer-first indexes, probed per customer

- **Before:** catalog and store were read in full (5.8M and 11.5M rows).
- **After:** with `idx_cs_cust` and `idx_ss_cust`, each surviving customer's rows are fetched directly (`ref` access).
- **Why:** after the web step only a few thousand customers matter. At about 10 catalog rows and about 19 store rows per customer, that is 78K and 12.6K rows instead of millions.
- **Evidence (catalog step):** access went from `ALL` (5.8M rows, about 8.6 s) to `ref` on `idx_cs_cust` (78K rows, about 0.8 to 1.4 s).
- **Why narrow indexes:** they cost far less disk than covering indexes. The extra row lookup per match is cheap when only thousands of customers are involved.

### 4. Web first, then catalog, then store (the funnel)

- **Before:** all three channels were fully aggregated for all customers, then compared at the end.
- **After:** web (smallest table) is scanned once. Catalog and store are only checked for survivors. `STRAIGHT_JOIN` forces this order, so the optimizer cannot switch back to scanning a big table first.
- **Why:** each step shrinks the list: 7,976, then 677, then 134, then about 100 results.
- **Order matters:** catalog first would be worse. Catalog is about twice the size of web, so the first full pass reads 5.8M rows instead of 2.9M, and the survivor list is longer.

### 5. Growth tests applied inside each step

- Catalog growth vs web growth is checked in step 3. Catalog growth vs store growth is checked in step 4.
- **Why:** customers that fail are dropped immediately and never carried forward. This is the same rule as the original (`catalog growth > store growth` and `catalog growth > web growth`), just checked earlier.

### 6. Removed `COUNT(DISTINCT d_year) = 2`

- **Why it was redundant:** the original already requires `y1 > 0` and a non-NULL ratio `y2/y1`. A customer missing a year has NULL there, so the comparison is NULL and the row is dropped anyway.
- `COUNT(DISTINCT ...)` is also one of the more expensive things inside a `GROUP BY`.
- Replaced by `HAVING w_y1 > 0 AND w_y2 IS NOT NULL` (and the same pattern for catalog and store).

### 7. Cross-multiplication instead of division

- **Before:** `CASE WHEN c.y1 > 0 THEN c.y2/c.y1 ELSE NULL END > CASE WHEN s.y1 > 0 THEN s.y2/s.y1 ...`
- **After:** `c_y2 * s_y1 > s_y2 * c_y1`
- **Why:** `y1 > 0` is already enforced, so the `CASE` wrappers do nothing. For positive `y1` values the two forms are equivalent, and multiplying avoids division and NULL branches.
- **Caveat:** decimal rounding in the division could differ from exact multiplication only on exact ties. Verify the output matches (see checklist).

### 8. NULL customers skipped early

`AND ws_bill_customer_sk IS NOT NULL` in the web scan. NULL customers form one huge group that can never join to anything.

### 9. Customer table joined on survivors

Names, login and id come from `customer` for the few customers that passed all tests. The optimizer currently reads and sorts all 233K customers (about 1.4 s) and then probes the results. See "Further ideas" below.

### 10. Removed the `sql_mode` line

`IGNORE_SPACE` and `PIPES_AS_CONCAT` do not affect this query, so the `SET SESSION sql_mode` line was dropped.

---

## Where the time goes now (SF-4, about 6.9 s)

| Step | Time |
|---|---|
| Web scan (2.9M rows) | about 4.5 s |
| Reading and sorting all 179K customers | about 1.4 s |
| Catalog (78K rows) | about 0.8 s |
| Store (12.6K rows) | about 0.2 s |

---

## Further ideas (not yet applied or measured)

- **Join customer last:** replace `JOIN customer cu` with `STRAIGHT_JOIN customer cu` so only the 134 survivors are looked up by primary key, instead of reading 233K customers. Likely saves most of the 1.4 s. Verify with `ANALYZE`.
- **Web scan (biggest piece):** uncertain. A narrow `(ws_bill_customer_sk, ws_sold_date_sk)` index would still need about 1.15M row lookups for the prices, so the optimizer may ignore it. A covering index with the four price columns would avoid that but costs disk. Only try it if about 6 s is not good enough, and compare `ANALYZE` before and after.
- **Sort buffer:** `SET SESSION sort_buffer_size = 64*1024*1024;` reduces merge passes on any remaining sort.
- **Drop the duplicate index** `idx_ss_customer_date` (same columns as `idx_ss_cust`).

---

## Gotchas we hit

- **Blank lines break DBeaver scripts.** DBeaver treats a blank line as the end of a statement. A `WITH` query split this way fails with errors like `near '' at line 46`. Remove blank lines, or turn off "Blank line is statement delimiter" in preferences. Run as a script with Alt+X.
- **Session variables and temporary tables are per connection.** `@start_2001` and `TEMPORARY` tables vanish if the next statement runs on another connection (error `Table ... doesn't exist`). Keep everything in one tab and one script run.
- **Check the index really exists** before benchmarking: `SHOW INDEX FROM store_sales WHERE Key_name = 'idx_ss_cust';` (should return 2 rows).
- **Run twice, time the second run.** The first run warms the cache.
- **Run `ANALYZE TABLE`** after creating indexes so the optimizer has fresh statistics.

---

## Verification checklist

1. Date keys contiguous: the two counts above are equal.
2. Same results as the baseline. Store both outputs without `LIMIT` and compare, then drop the helper tables:

```sql
CREATE TABLE q4_orig AS <baseline query without LIMIT>;
CREATE TABLE q4_new  AS <optimized query without LIMIT>;
SELECT COUNT(*) FROM q4_orig;
SELECT COUNT(*) FROM q4_new;
SELECT * FROM q4_orig EXCEPT SELECT * FROM q4_new;
SELECT * FROM q4_new  EXCEPT SELECT * FROM q4_orig;
DROP TABLE q4_orig;
DROP TABLE q4_new;
```

   Counts must match and both `EXCEPT` queries must return no rows. (If you cannot create tables, compare row counts and the first 100 rows by eye instead.)
3. `ANALYZE FORMAT=JSON` shows `idx_cs_cust` and `idx_ss_cust` used with `ref`, and no sales table with `access_type: ALL` except `web_sales`.
4. Investigate the SF-1 0.006 s result (row count, caching) before reporting it.