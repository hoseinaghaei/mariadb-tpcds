CREATE INDEX idx_ws_cust_date ON web_sales     (ws_bill_customer_sk, ws_sold_date_sk);
CREATE INDEX idx_cs_cust_date ON catalog_sales (cs_ship_customer_sk, cs_sold_date_sk);
CREATE INDEX idx_ss_cust_date ON store_sales   (ss_customer_sk,      ss_sold_date_sk);


CREATE INDEX idx_ss_date_cust ON store_sales (ss_sold_date_sk, ss_customer_sk);
CREATE INDEX idx_ws_date_cust ON web_sales   (ws_sold_date_sk, ws_bill_customer_sk);
CREATE INDEX idx_cs_date_cust ON catalog_sales (cs_sold_date_sk, cs_ship_customer_sk);


DROP INDEX IF EXISTS idx_ws_cust_date ON web_sales;
DROP INDEX IF EXISTS idx_cs_cust_date ON catalog_sales;
DROP INDEX IF EXISTS idx_ss_cust_date ON store_sales;

DROP INDEX IF EXISTS idx_ss_date_cust ON store_sales;
DROP INDEX IF EXISTS idx_ws_date_cust ON web_sales;
DROP INDEX IF EXISTS idx_cs_date_cust ON catalog_sales;