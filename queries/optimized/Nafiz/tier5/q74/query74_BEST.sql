-- v2: pivot rewrite with source date-key ranges for 1999-2000.
WITH year_total AS (
 SELECT c_customer_id customer_id,c_first_name customer_first_name,c_last_name customer_last_name,d_year yr,MAX(ss_net_paid) year_total,'s' sale_type
 FROM customer JOIN store_sales ON c_customer_sk=ss_customer_sk JOIN date_dim ON ss_sold_date_sk=d_date_sk
 WHERE ss_sold_date_sk BETWEEN 2451180 AND 2451910 AND d_year IN (1999,2000) GROUP BY c_customer_id,c_first_name,c_last_name,d_year
 UNION ALL
 SELECT c_customer_id,c_first_name,c_last_name,d_year,MAX(ws_net_paid),'w'
 FROM customer JOIN web_sales ON c_customer_sk=ws_bill_customer_sk JOIN date_dim ON ws_sold_date_sk=d_date_sk
 WHERE ws_sold_date_sk BETWEEN 2451180 AND 2451910 AND d_year IN (1999,2000) GROUP BY c_customer_id,c_first_name,c_last_name,d_year
), p AS (
 SELECT customer_id,customer_first_name,customer_last_name,
  MAX(CASE WHEN sale_type='s' AND yr=1999 THEN year_total END) s1999,MAX(CASE WHEN sale_type='s' AND yr=2000 THEN year_total END) s2000,
  MAX(CASE WHEN sale_type='w' AND yr=1999 THEN year_total END) w1999,MAX(CASE WHEN sale_type='w' AND yr=2000 THEN year_total END) w2000,
  COUNT(CASE WHEN sale_type='s' AND yr=1999 THEN 1 END) a,COUNT(CASE WHEN sale_type='s' AND yr=2000 THEN 1 END) b,COUNT(CASE WHEN sale_type='w' AND yr=1999 THEN 1 END) c,COUNT(CASE WHEN sale_type='w' AND yr=2000 THEN 1 END) d
 FROM year_total GROUP BY customer_id,customer_first_name,customer_last_name
)
SELECT customer_id,customer_first_name,customer_last_name FROM p
WHERE a>0 AND b>0 AND c>0 AND d>0 AND s1999>0 AND w1999>0 AND w2000/w1999>s2000/s1999
ORDER BY customer_first_name,customer_id,customer_last_name LIMIT 100;
