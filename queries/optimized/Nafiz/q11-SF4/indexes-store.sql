-- Additional Q11 revenue-covering indexes; create outside query timing.
USE tpcds;
CREATE INDEX IF NOT EXISTS idx_nf_q11_ss_cover ON store_sales (ss_sold_date_sk,ss_customer_sk,ss_ext_list_price,ss_ext_discount_amt);
ALTER TABLE store_sales ALTER INDEX idx_nf_q11_ss_cover NOT IGNORED;
ANALYZE TABLE store_sales;
