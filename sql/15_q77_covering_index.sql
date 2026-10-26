-- ==========================================================================
--  One covering index for q77 (and q70), the last diagnosed defect with no
--  query-level fix.
--
--  WHY.  q77's `ss` CTE aggregates a 31-day window of store_sales:
--
--      select s_store_sk, sum(ss_ext_sales_price), sum(ss_net_profit)
--      from store_sales, store
--      where ss_sold_date_sk between 2451054 and 2451084
--        and ss_store_sk = s_store_sk
--      group by s_store_sk
--
--  The plan reaches store_sales through idx_ss_date_cust
--  (ss_sold_date_sk, ss_customer_sk), which carries neither ss_store_sk nor
--  either measure, so every qualifying row costs a base-table fetch --
--  `Using join buffer (flat, BKAH join); Rowid-ordered scan`.  Rewriting the
--  query cannot fix that; the columns simply are not in any index.
--
--  This index holds exactly what that CTE reads, in the order it reads it,
--  so the aggregation becomes index-only.  q70's aggregate
--  (same date range, group by ss_store_sk, sum(ss_net_profit)) is covered by
--  its first three columns and should benefit too.
--
--  COST.  Roughly 400-500 MB at SF=4 (11.5M rows, four columns plus the
--  clustered-key suffix).  Existing store_sales index storage is ~340 MB, so
--  this more than doubles it.  That is the trade being measured.
--
--  THIS IS NOT YET ADOPTED.  Adding indexes to this schema has backfired
--  before: six added at once made 16K/SF=1 40% SLOWER, because they displaced
--  data pages from the buffer pool.  Run pagesize/test-q77-index.sh, which
--  measures the whole tier-4/5 suite with the index IGNORED and then NOT
--  IGNORED, before believing it helps.
--
--  If it does not pay, leave it IGNORED rather than dropping it:
--  ALTER INDEX ... IGNORED is metadata-only and reverses in ~0.15s, and
--  "unused" depends on the configuration (report/17, report/22).
-- ==========================================================================
SET SESSION alter_algorithm='INPLACE';

CREATE INDEX idx_ss_date_store_profit
    ON store_sales (ss_sold_date_sk, ss_store_sk, ss_net_profit,
                    ss_ext_sales_price);

-- Created IGNORED so the first measurement is the honest "before": the index
-- exists and costs its storage, but the optimizer may not use it.
ALTER TABLE store_sales ALTER INDEX idx_ss_date_store_profit IGNORED;

ANALYZE TABLE store_sales;
