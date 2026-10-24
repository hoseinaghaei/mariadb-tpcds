-- v1: calculate all three quarters per county in one pass per sales table.
WITH ss AS (
  SELECT ca_county,
         SUM(CASE WHEN d_qoy = 1 THEN ss_ext_sales_price END) AS s_q1,
         SUM(CASE WHEN d_qoy = 2 THEN ss_ext_sales_price END) AS s_q2,
         SUM(CASE WHEN d_qoy = 3 THEN ss_ext_sales_price END) AS s_q3,
         COUNT(CASE WHEN d_qoy = 1 THEN 1 END) AS has_q1,
         COUNT(CASE WHEN d_qoy = 2 THEN 1 END) AS has_q2,
         COUNT(CASE WHEN d_qoy = 3 THEN 1 END) AS has_q3
  FROM store_sales
  JOIN date_dim ON ss_sold_date_sk = d_date_sk
  JOIN customer_address ON ss_addr_sk = ca_address_sk
  WHERE d_year = 2001 AND d_qoy IN (1, 2, 3)
  GROUP BY ca_county
), ws AS (
  SELECT ca_county,
         SUM(CASE WHEN d_qoy = 1 THEN ws_ext_sales_price END) AS w_q1,
         SUM(CASE WHEN d_qoy = 2 THEN ws_ext_sales_price END) AS w_q2,
         SUM(CASE WHEN d_qoy = 3 THEN ws_ext_sales_price END) AS w_q3,
         COUNT(CASE WHEN d_qoy = 1 THEN 1 END) AS has_q1,
         COUNT(CASE WHEN d_qoy = 2 THEN 1 END) AS has_q2,
         COUNT(CASE WHEN d_qoy = 3 THEN 1 END) AS has_q3
  FROM web_sales
  JOIN date_dim ON ws_sold_date_sk = d_date_sk
  JOIN customer_address ON ws_bill_addr_sk = ca_address_sk
  WHERE d_year = 2001 AND d_qoy IN (1, 2, 3)
  GROUP BY ca_county
)
SELECT ss.ca_county, 2001 AS d_year,
       ws.w_q2 / ws.w_q1 AS web_q1_q2_increase,
       ss.s_q2 / ss.s_q1 AS store_q1_q2_increase,
       ws.w_q3 / ws.w_q2 AS web_q2_q3_increase,
       ss.s_q3 / ss.s_q2 AS store_q2_q3_increase
FROM ss JOIN ws ON ss.ca_county = ws.ca_county
WHERE ss.has_q1 > 0 AND ss.has_q2 > 0 AND ss.has_q3 > 0
  AND ws.has_q1 > 0 AND ws.has_q2 > 0 AND ws.has_q3 > 0
  AND ws.w_q1 > 0 AND ss.s_q1 > 0
  AND ws.w_q2 / ws.w_q1 > ss.s_q2 / ss.s_q1
  AND ws.w_q2 > 0 AND ss.s_q2 > 0
  AND ws.w_q3 / ws.w_q2 > ss.s_q3 / ss.s_q2
ORDER BY web_q2_q3_increase;
