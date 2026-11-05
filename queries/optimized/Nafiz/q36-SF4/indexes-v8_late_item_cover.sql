-- Optional additions to the pinned team95 recipe; build outside timed batches.
-- Do not toggle visibility or run ANALYZE between paired timings.
USE tpcds;
CREATE INDEX IF NOT EXISTS idx_nf_q36_date_cover ON store_sales (ss_sold_date_sk,ss_item_sk,ss_store_sk,ss_net_profit,ss_ext_sales_price);
