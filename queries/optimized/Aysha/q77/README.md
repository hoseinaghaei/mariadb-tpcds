# TPC-DS Query 77 Optimization (MariaDB)

Query 77 went from about 37 seconds to about 0.66 seconds by adding 5 covering indexes. The query itself is not changed.

## Files

| File | What it is |
|---|---|
| `query77-Original.sql` | The original TPC-DS query 77, unchanged |
| `q77-Optimized-Indexes.sql` | The 5 new covering indexes (the only change needed) |

## Result

Tested on TPC-DS SF4 in Docker MariaDB. The query returns 86 rows in every version.

| # | Version | Time |
|---|---|---|
| 1 | Original query, no new indexes (first run) | about 37 s |
| 2 | Original query + session settings (MRR) + new indexes | 0.786 s |
| 3 | `EXISTS` instead of joining `store` and `web_page` + new indexes | 0.808 s |
| 4 | **Original query + new indexes only** | **0.663 s (best)** |

That is about 56x faster than version 1.

## Decision

Keep the original query and add only the 5 indexes.

- The session settings (`mrr`, `mrr_buffer_size`, `join_cache_level`) made it slightly slower once the indexes cover the query.
- Replacing the `store` and `web_page` joins with `EXISTS` was also slightly slower, and it changes the query.
- Version 4 is the fastest and also the simplest. The query stays exactly as in the benchmark, so results can be compared fairly.

## Why the indexes help

Before, the query read the date range through indexes that did not hold all the needed columns. For every matching row, MariaDB had to go back to the main table.

- `store_sales`: about 720,000 page reads for 240,000 rows. This one step took about 23 s of the 37 s.
- The new indexes contain the date, the group-by key and the two summed columns. The plan now shows `"using_index": true` on all five tables, so the main table is not touched.
- In the analyzed run with the new indexes, `store_sales` page reads fell from about 720,000 to about 800.

## The 5 indexes

```sql
CREATE INDEX idx_q77_ss ON store_sales    (ss_sold_date_sk,     ss_store_sk,        ss_ext_sales_price, ss_net_profit);
CREATE INDEX idx_q77_cs ON catalog_sales  (cs_sold_date_sk,     cs_call_center_sk,  cs_ext_sales_price, cs_net_profit);
CREATE INDEX idx_q77_ws ON web_sales      (ws_sold_date_sk,     ws_web_page_sk,     ws_ext_sales_price, ws_net_profit);
CREATE INDEX idx_q77_cr ON catalog_returns(cr_returned_date_sk, cr_call_center_sk,  cr_return_amount,   cr_net_loss);
CREATE INDEX idx_q77_wr ON web_returns    (wr_returned_date_sk, wr_web_page_sk,     wr_return_amt,      wr_net_loss);
```

`store_returns` and `date_dim` already had covering indexes (`idx_sr_date` and `idx_dd_date`), so nothing was added there.

## Storage cost

Measured at SF4:

| Index | Size |
|---|---|
| `idx_q77_ss` | 511 MB |
| `idx_q77_cs` | 264 MB |
| `idx_q77_ws` | 134 MB |
| `idx_q77_cr` | 30 MB |
| `idx_q77_wr` | 15 MB |
| **Total** | **about 954 MB** |

For SF10, expect about 2.5x that, roughly 2.4 GB. Keep free disk space of about twice the index size while building.

## How to apply

1. Build the indexes (run `idx_q77_ss` first, since it gives the biggest gain):

   ```bash
   mysql tpcds_sf4 < q77-Optimized-Indexes.sql
   ```

2. Update the statistics (the full `ANALYZE TABLE ... PERSISTENT FOR ALL` can hit `max_statement_time`, so remove that limit for the session or limit it to the needed columns):

   ```sql
   SET SESSION max_statement_time = 0;
   ANALYZE TABLE store_sales, catalog_sales, web_sales, catalog_returns, web_returns
     PERSISTENT FOR ALL;
   ```

3. Run `query77-Original.sql` as it is.

## How to verify

Run the query with `ANALYZE FORMAT=JSON` and check:

- `"using_index": true` on `store_sales`, `catalog_sales`, `web_sales`, `catalog_returns` and `web_returns`.
- The keys used are the `idx_q77_*` indexes.
- 86 rows are returned and the totals match the original run.

## How to undo

```sql
DROP INDEX idx_q77_ss ON store_sales;
DROP INDEX idx_q77_cs ON catalog_sales;
DROP INDEX idx_q77_ws ON web_sales;
DROP INDEX idx_q77_cr ON catalog_returns;
DROP INDEX idx_q77_wr ON web_returns;
```

## Notes

- The 37 s run was the first run (cold cache), and the later runs were warm. Part of the gap is cache warm-up. The drop in page reads shows most of the gain comes from the indexes. For a fair comparison, run each version 2 or 3 times and compare the last run.
- The new indexes add some cost to inserts and bulk loads. For a fresh load, create them after loading the data.
- Do not drop the old indexes (for example `idx_ss_date_store_item_price`) unless you have checked that no other query uses them.
- The catalog part of the query joins `cs` and `cr` with no join condition, as in the standard TPC-DS query. It is left unchanged so results stay comparable.