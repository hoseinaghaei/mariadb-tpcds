# TPC-DS Query 5 Optimization on MariaDB

Optimizing TPC-DS **query 5** (sales, returns and profit by channel, with `ROLLUP`) on MariaDB at scale factor 4 (`tpcds_sf4`).
Result: **519 s down to 6.44 s in Docker** and **87 s (cold) down to 0.63 s in DBeaver**, with identical output.

---

## Results

### Docker

| Version | Time | Speedup vs original |
|---|---|---|
| Original | 519 s | 1x |
| Original + indexes | 18.74 s | about 28x |
| Optimized + indexes | **6.44 s** | **about 81x** |

### DBeaver

| Version | Time | Speedup vs original (cold) |
|---|---|---|
| Original, cold cache | 1 min 27 s (87 s) | 1x |
| Original, warm cache | 12 s | about 7x |
| Original + indexes | 1.02 s | about 85x |
| Optimized + indexes | **0.63 s** | **about 138x** |

### What the numbers say

- **Indexes give the biggest jump.** Docker goes 519 s to 18.74 s (about 28x) and DBeaver 87 s to 1.02 s (about 85x), with no change to the SQL.
- **The rewrite adds a smaller, still real gain.** It is about 2.9x in Docker (18.74 s to 6.44 s) and about 1.6x in DBeaver (1.02 s to 0.63 s).
- **Cold versus warm matters a lot.** The original takes 87 s cold and 12 s warm, so most of the original's cost is disk reads. Always report which one you measured.
- Docker and DBeaver numbers are from different setups. Compare versions within one environment, not across them.

---

## What the query does

A sales report for a retailer with three channels: **store**, **catalog** and **web**.

- It covers 15 days: 1998-08-28 to 1998-09-11.
- For every store, catalog page and web site it reports **sales**, **returns** and **profit** (profit minus return losses).
- It then adds subtotals per channel and a grand total with `GROUP BY ... WITH ROLLUP`.
- The output is 7 rows (after `LIMIT 100`).

A **return** is a customer sending an item back for a refund. Each channel has a sales table and a returns table.

### Tables

| Table | Meaning |
|---|---|
| `store_sales`, `catalog_sales`, `web_sales` | Items sold, per channel |
| `store_returns`, `catalog_returns`, `web_returns` | Items returned, per channel |
| `date_dim` | Calendar table, one row per day |
| `store`, `catalog_page`, `web_site` | Lookup tables that give ids readable names |

---

## Why the original was slow

The query plan (`ANALYZE FORMAT=JSON`, `tpcds_sf4`) showed that almost all of the time sat in the six leaf branches. The grouping, rollup and sort cost under one second.

**1. The returns tables were read in full.** The optimizer started from the returns table and checked the date last:

| Branch | What happened |
|---|---|
| `store_returns` | Full scan of 1.15M rows, then 1.1M lookups into `date_dim`; only 0.58% of rows matched |
| `catalog_returns` | Full scan of 577k rows, then 575k lookups into `date_dim` |
| `web_returns` | Full scan of 288k rows, then 275k primary-key lookups into `web_sales` (about 18 s of random I/O) |

There was no index on the returned-date columns, so the optimizer had no cheap way to start from the 15 days.

**2. The sales branches were I/O bound.** The existing indexes held the date, store and price, but not `profit`. Every matching row needed an extra random read from the table (about 62k page reads for `store_sales` alone).

**3. Smaller waste.**

- `date_dim` was joined twice per channel (inside each branch and again after the union).
- Every row was joined to the name table before grouping (about 122k, 64k and 32k lookups).
- Statistics were off: the optimizer expected 507 rows per date in `store_sales` and got 7,903.

---

## What changed

### 1. Indexes (the biggest win)

```sql
-- Returns: start from the date
CREATE INDEX idx_sr_date ON store_returns
  (sr_returned_date_sk, sr_store_sk, sr_return_amt, sr_net_loss);
CREATE INDEX idx_cr_date ON catalog_returns
  (cr_returned_date_sk, cr_catalog_page_sk, cr_return_amount, cr_net_loss);
CREATE INDEX idx_wr_date ON web_returns
  (wr_returned_date_sk, wr_item_sk, wr_order_number, wr_return_amt, wr_net_loss);

-- Sales: covering indexes, no table row reads
CREATE INDEX idx_ss_cov ON store_sales
  (ss_sold_date_sk, ss_store_sk, ss_ext_sales_price, ss_net_profit);
CREATE INDEX idx_cs_cov ON catalog_sales
  (cs_sold_date_sk, cs_catalog_page_sk, cs_ext_sales_price, cs_net_profit);
CREATE INDEX idx_ws_cov ON web_sales
  (ws_sold_date_sk, ws_web_site_sk, ws_ext_sales_price, ws_net_profit);

ANALYZE TABLE store_sales, catalog_sales, web_sales,
              store_returns, catalog_returns, web_returns,
              date_dim PERSISTENT FOR ALL;
```

The "with index" runs use these. If your index set differs, update this section to match.

### 2. Date table first

Every branch starts from `date_dim` and is forced in that order with `STRAIGHT_JOIN`:

```sql
from date_dim d
straight_join store_returns on sr_returned_date_sk = d.d_date_sk
where d.d_date between '1998-08-28' and '1998-09-11'
```

`STRAIGHT_JOIN` only fixes the order. It needs the indexes above, otherwise it would re-read the returns table once per day.

### 3. Redundant date join removed

The original joined `date_dim` a second time after the union (`salesreturns, date_dim ... where date_sk = d_date_sk`). Both union branches were already filtered by date, so the second join and the `date_sk` column were removed.

### 4. Group early, then add names

Rows are grouped by `store_sk`, `page_sk` or `site_sk` first, and only then joined to `store`, `catalog_page` or `web_site`. That cuts the lookups from about 122k, 64k and 32k to a few hundred. A second `GROUP BY` on the readable id keeps results identical, because one `s_store_id` can map to several `store_sk` values.

### 5. Web returns: inner join instead of `LEFT JOIN`

A web return row does not know its web site, so it looks up the original sale in `web_sales` by item and order number.

- The original used `LEFT OUTER JOIN`, which keeps returns even when no sale is found. Those rows get an empty site and are dropped later when joining `web_site`, so keeping them was wasted work.
- The new query uses a normal join with the date first. The result is the same, and the optimizer can choose a better order.

### 6. `CONCAT()` instead of `||`

In MariaDB's default mode `||` means `OR`, so `'store' || s_store_id` returns wrong rows. The original needed `PIPES_AS_CONCAT` (and `IGNORE_SPACE`). `CONCAT()` works in every mode, so no session setting is required.

### 7. `split_materialized`

The original always ran with `split_materialized=off`. With the new plan, test with and without it, since the plan is now very different.

---

## Join order (new query)

For each channel:

1. **Sales (A):** `date_dim` then the sales table.
2. **Returns (B):** `date_dim` then the returns table (for web: then `web_sales` to find the site).
3. `UNION ALL` of A and B.
4. `GROUP BY` the surrogate key (`store_sk`, `page_sk`, `site_sk`).
5. Join the name table (`store`, `catalog_page`, `web_site`).
6. `GROUP BY` the readable id.

Then, once: `UNION ALL` of the three channels, `WITH ROLLUP`, `ORDER BY`, `LIMIT 100`.

---

## Reproduce

1. Load TPC-DS at SF=4 into a database named `tpcds_sf4`.
2. Time the original with no extra indexes (note cold or warm).
3. Run the index block above and `ANALYZE TABLE`, then time the original again.
4. Time `query5_optimized.sql` (run it twice and record the second run as warm).
5. Compare plans with `ANALYZE FORMAT=JSON <query>`. In the optimized version, `date_dim` should be the first table in every branch and the sales and returns reads should show `Using index`.

### Check the results match

```sql
-- both queries return the same rows when this returns nothing
(<original query>) EXCEPT (<optimized query>);
(<optimized query>) EXCEPT (<original query>);
```

Use the final `select` of each version (without the `limit`) for an exact comparison.

---

## Files

| File | Content |
|---|---|
| `query5_original.sql` | Original query (needs `PIPES_AS_CONCAT`) |
| `query5_optimized.sql` | Rewritten query plus index setup |

---

## Takeaways

- **Check the plan before rewriting SQL.** Here the cost was not in the clever parts (rollup, unions) but in six table reads.
- **A missing index on the filtered column can mean a full scan plus millions of lookups.** One index per returns table removed most of the time.
- **Covering indexes turn random reads into sequential ones.**
- **Report cold and warm runs separately.** The same query took 87 s and 12 s.
- **Make joins start from the smallest filtered table.** 15 rows of `date_dim` should drive millions of fact rows, not the other way round.
- **Prefer `CONCAT()` over `||`** when the same SQL has to run under different `sql_mode` settings.