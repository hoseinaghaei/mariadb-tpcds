-- Additional Q11 revenue-covering indexes; create outside query timing.
USE tpcds;
CREATE INDEX IF NOT EXISTS idx_nf_q11_ss_cover ON store_sales (ss_sold_date_sk,ss_customer_sk,ss_ext_list_price,ss_ext_discount_amt);
ALTER TABLE store_sales ALTER INDEX idx_nf_q11_ss_cover NOT IGNORED;
CREATE INDEX IF NOT EXISTS idx_nf_q11_ws_cover ON web_sales (ws_sold_date_sk,ws_bill_customer_sk,ws_ext_list_price,ws_ext_discount_amt);
ALTER TABLE web_sales ALTER INDEX idx_nf_q11_ws_cover NOT IGNORED;
ANALYZE TABLE store_sales,web_sales;
