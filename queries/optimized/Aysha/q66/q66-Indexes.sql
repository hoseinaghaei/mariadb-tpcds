CREATE INDEX idx_ws_q66 ON web_sales
  (ws_ship_mode_sk, ws_sold_date_sk, ws_sold_time_sk, ws_warehouse_sk,
   ws_sales_price, ws_quantity, ws_net_paid_inc_ship);

CREATE INDEX idx_cs_q66 ON catalog_sales
  (cs_ship_mode_sk, cs_sold_date_sk, cs_sold_time_sk, cs_warehouse_sk,
   cs_ext_sales_price, cs_quantity, cs_net_paid_inc_tax);


SELECT
    TABLE_NAME,
    INDEX_NAME,
    ROUND(STAT_VALUE * @@innodb_page_size / 1024, 2) AS size_kb
FROM mysql.innodb_index_stats
WHERE DATABASE_NAME = DATABASE()
  AND TABLE_NAME IN ('web_sales', 'ship_mode')
  AND STAT_NAME = 'size';



-- CREATE INDEX idx_d_year_moy ON date_dim (d_year, d_date_sk, d_moy);
-- 
-- CREATE INDEX idx_sm_carrier ON ship_mode (sm_carrier);
-- 
-- DROP INDEX idx_d_year_moy ON date_dim;
-- 
-- DROP INDEX idx_sm_carrier ON ship_mode;


