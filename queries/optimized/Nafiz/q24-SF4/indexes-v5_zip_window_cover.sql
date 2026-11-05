-- Optional additions to the pinned team95 recipe; build outside timed batches.
-- Do not toggle visibility or run ANALYZE between paired timings.
USE tpcds;
CREATE INDEX IF NOT EXISTS idx_nf_q24_zip ON customer_address (ca_zip);
CREATE INDEX IF NOT EXISTS idx_nf_q24_cust_store_cover ON store_sales (ss_customer_sk,ss_store_sk,ss_ext_sales_price);
