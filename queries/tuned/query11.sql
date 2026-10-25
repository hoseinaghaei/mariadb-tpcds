-- query11
-- source: queries/optimized/Nafiz/tier5/q11/query11_BEST.sql
-- split materialisation OFF: measured -5.6s at SF=4

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');
SET SESSION optimizer_switch = 'split_materialized=off';

WITH year_total AS (
 SELECT c_customer_id customer_id,c_first_name customer_first_name,c_last_name customer_last_name,c_login customer_login,d_year yr,SUM(ss_ext_list_price-ss_ext_discount_amt) total,'s' sale_type
 FROM customer JOIN store_sales ON c_customer_sk=ss_customer_sk JOIN date_dim ON ss_sold_date_sk=d_date_sk
 WHERE ss_sold_date_sk BETWEEN 2451911 AND 2452640 AND d_year IN (2001,2002) GROUP BY c_customer_id,c_first_name,c_last_name,c_login,d_year
 UNION ALL
 SELECT c_customer_id,c_first_name,c_last_name,c_login,d_year,SUM(ws_ext_list_price-ws_ext_discount_amt),'w'
 FROM customer JOIN web_sales ON c_customer_sk=ws_bill_customer_sk JOIN date_dim ON ws_sold_date_sk=d_date_sk
 WHERE ws_sold_date_sk BETWEEN 2451911 AND 2452640 AND d_year IN (2001,2002) GROUP BY c_customer_id,c_first_name,c_last_name,c_login,d_year
), p AS (
 SELECT customer_id,customer_first_name,customer_last_name,customer_login,
  MAX(CASE WHEN sale_type='s' AND yr=2001 THEN total END) s1,MAX(CASE WHEN sale_type='s' AND yr=2002 THEN total END) s2,
  MAX(CASE WHEN sale_type='w' AND yr=2001 THEN total END) w1,MAX(CASE WHEN sale_type='w' AND yr=2002 THEN total END) w2,
  COUNT(CASE WHEN sale_type='s' AND yr=2001 THEN 1 END) a,COUNT(CASE WHEN sale_type='s' AND yr=2002 THEN 1 END) b,COUNT(CASE WHEN sale_type='w' AND yr=2001 THEN 1 END) c,COUNT(CASE WHEN sale_type='w' AND yr=2002 THEN 1 END) d
 FROM year_total GROUP BY customer_id,customer_first_name,customer_last_name,customer_login
)
SELECT customer_id,customer_first_name,customer_last_name,customer_login FROM p
WHERE a>0 AND b>0 AND c>0 AND d>0 AND s1>0 AND w1>0 AND w2/w1>s2/s1
ORDER BY customer_id,customer_first_name,customer_last_name,customer_login LIMIT 100;
