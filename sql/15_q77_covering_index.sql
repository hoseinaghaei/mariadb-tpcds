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
--  MEASURED 2026-10-26, SF=4, four full tier-4/5 passes alternating
--  IGNORED / NOT IGNORED (pagesize/test-q77-index.sh).  Actual size: 512 MB.
--
--  Only two queries show a CONSISTENT effect -- both passes with the index
--  beating both passes without it:
--
--      q70   3.5, 4.2s  ->  1.4, 1.3s      ~2.9x
--      q5   10.1, 13.1s ->  5.8, 3.9s      ~2.4x
--
--  Nothing regressed consistently.  The apparent losses -- q22 +13.6s,
--  q14 +11.0s, q67 +6.6s -- are all one bad pass: the first NOT IGNORED run
--  totalled 591.8s against 371.5s for the second, and inflated every long
--  query in it.  Suite totals cannot resolve this at all (IGNORED 380.0 and
--  509.9s, NOT IGNORED 591.8 and 371.5s).
--
--  THE IRONY: q77, which this index was built for, shows NO consistent
--  benefit (11.0, 7.3s -> 15.3, 5.7s).  Its `ss` CTE does read exactly these
--  four columns, but it is one of six CTEs -- the other five hit
--  store_returns, catalog_sales, catalog_returns, web_sales and web_returns
--  -- so making a sixth of the query index-only is lost in the noise.  q5 and
--  q70 benefit because this access pattern is nearly all of what they do.
--  q5 reads ss_store_sk, ss_sold_date_sk, ss_ext_sales_price and
--  ss_net_profit and nothing else from store_sales.
--
--  VERDICT: worth enabling.  Two reproducible multiples, no reproducible
--  regression, for 512 MB -- which does more than double store_sales's ~340 MB
--  of existing index storage.  But the suite-level gain is NOT demonstrable
--  on this host; do not claim one.
--
--  It is left IGNORED by the test script, which is the state every committed
--  result was measured in.  To enable it deliberately:
--
--      ALTER TABLE store_sales ALTER INDEX idx_ss_date_store_profit NOT IGNORED;
--
--  Never DROP it: ALTER INDEX ... IGNORED is metadata-only, reverses in
--  ~0.15s, and "unused" depends on the configuration (report/17, report/22).
-- ==========================================================================
SET SESSION alter_algorithm='INPLACE';

CREATE INDEX idx_ss_date_store_profit
    ON store_sales (ss_sold_date_sk, ss_store_sk, ss_net_profit,
                    ss_ext_sales_price);

-- Created IGNORED so the first measurement is the honest "before": the index
-- exists and costs its storage, but the optimizer may not use it.
ALTER TABLE store_sales ALTER INDEX idx_ss_date_store_profit IGNORED;

ANALYZE TABLE store_sales;
