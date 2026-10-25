-- v2: UNION pivot plus the equivalent contiguous date-key range.
WITH web_v1 AS (
 SELECT ws_item_sk item_sk,d_date,SUM(SUM(ws_sales_price)) OVER(PARTITION BY ws_item_sk ORDER BY d_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) cume_sales
 FROM web_sales JOIN date_dim ON ws_sold_date_sk=d_date_sk
 WHERE ws_sold_date_sk BETWEEN 2450815 AND 2451179 AND d_month_seq BETWEEN 1176 AND 1187 AND ws_item_sk IS NOT NULL GROUP BY ws_item_sk,d_date
), store_v1 AS (
 SELECT ss_item_sk item_sk,d_date,SUM(SUM(ss_sales_price)) OVER(PARTITION BY ss_item_sk ORDER BY d_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) cume_sales
 FROM store_sales JOIN date_dim ON ss_sold_date_sk=d_date_sk
 WHERE ss_sold_date_sk BETWEEN 2450815 AND 2451179 AND d_month_seq BETWEEN 1176 AND 1187 AND ss_item_sk IS NOT NULL GROUP BY ss_item_sk,d_date
), combined AS (
 SELECT item_sk,d_date,cume_sales web_sales,NULL store_sales FROM web_v1 UNION ALL SELECT item_sk,d_date,NULL,cume_sales FROM store_v1
), paired AS (
 SELECT item_sk,d_date,MAX(web_sales) web_sales,MAX(store_sales) store_sales FROM combined GROUP BY item_sk,d_date
), cumulative AS (
 SELECT item_sk,d_date,web_sales,store_sales,MAX(web_sales) OVER(PARTITION BY item_sk ORDER BY d_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) web_cumulative,MAX(store_sales) OVER(PARTITION BY item_sk ORDER BY d_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) store_cumulative FROM paired
)
SELECT item_sk,d_date,web_sales,store_sales,web_cumulative,store_cumulative FROM cumulative WHERE web_cumulative>store_cumulative ORDER BY item_sk,d_date LIMIT 100;
