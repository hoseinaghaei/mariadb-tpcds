-- Optional Q74 lookup profile; build outside query timing.
USE tpcds;
CREATE INDEX IF NOT EXISTS idx_nf_q74_ss_top ON store_sales (ss_customer_sk,ss_net_paid,ss_sold_date_sk);
ALTER TABLE store_sales ALTER INDEX idx_nf_q74_ss_top NOT IGNORED;
CREATE INDEX IF NOT EXISTS idx_nf_q74_ws_top ON web_sales (ws_bill_customer_sk,ws_net_paid,ws_sold_date_sk);
ALTER TABLE web_sales ALTER INDEX idx_nf_q74_ws_top NOT IGNORED;
CREATE INDEX IF NOT EXISTS idx_nf_q74_customer_order ON customer (c_first_name,c_customer_id,c_last_name);
ALTER TABLE customer ALTER INDEX idx_nf_q74_customer_order NOT IGNORED;
ANALYZE TABLE store_sales,web_sales,customer;
