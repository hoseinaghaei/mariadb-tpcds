-- Optional additions to the pinned team95 recipe; build outside timed batches.
-- Do not toggle visibility or run ANALYZE between paired timings.
USE tpcds;
CREATE INDEX IF NOT EXISTS idx_nf_q45_date_cover ON web_sales (ws_sold_date_sk,ws_bill_customer_sk,ws_item_sk,ws_sales_price);
