SET SESSION tmp_table_size      = 256*1024*1024;
SET SESSION max_heap_table_size = 256*1024*1024;
SET SESSION join_buffer_size    = 8*1024*1024;
SET SESSION optimizer_switch    = 'semijoin=on,materialization=on,firstmatch=on';

CREATE INDEX idx_ss_date_customer
ON store_sales (ss_sold_date_sk, ss_customer_sk);

CREATE INDEX idx_cs_date_customer
ON catalog_sales (cs_sold_date_sk, cs_bill_customer_sk);

CREATE INDEX idx_ws_date_customer
ON web_sales (ws_sold_date_sk, ws_bill_customer_sk);

CREATE INDEX idx_date_month_date_sk
ON date_dim (d_month_seq, d_date_sk);

-- 
-- DROP INDEX idx_ss_date_customer ON store_sales;
-- 
-- DROP INDEX idx_cs_date_customer ON catalog_sales;
-- 
-- DROP INDEX idx_ws_date_customer ON web_sales;
-- 
-- DROP INDEX idx_date_month_date_sk ON date_dim;v