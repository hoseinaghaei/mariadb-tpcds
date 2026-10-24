-- v1: aggregate each sale type once, then pivot the four required values.
WITH year_total AS (
  SELECT c_customer_id AS customer_id, c_first_name AS customer_first_name,
         c_last_name AS customer_last_name, d_year AS yr,
         MAX(ss_net_paid) AS year_total, 's' AS sale_type
  FROM customer
  JOIN store_sales ON c_customer_sk = ss_customer_sk
  JOIN date_dim ON ss_sold_date_sk = d_date_sk
  WHERE d_year IN (1999, 2000)
  GROUP BY c_customer_id, c_first_name, c_last_name, d_year
  UNION ALL
  SELECT c_customer_id, c_first_name, c_last_name, d_year,
         MAX(ws_net_paid), 'w'
  FROM customer
  JOIN web_sales ON c_customer_sk = ws_bill_customer_sk
  JOIN date_dim ON ws_sold_date_sk = d_date_sk
  WHERE d_year IN (1999, 2000)
  GROUP BY c_customer_id, c_first_name, c_last_name, d_year
), pivoted AS (
  SELECT customer_id, customer_first_name, customer_last_name,
         MAX(CASE WHEN sale_type = 's' AND yr = 1999 THEN year_total END) AS s_1999,
         MAX(CASE WHEN sale_type = 's' AND yr = 2000 THEN year_total END) AS s_2000,
         MAX(CASE WHEN sale_type = 'w' AND yr = 1999 THEN year_total END) AS w_1999,
         MAX(CASE WHEN sale_type = 'w' AND yr = 2000 THEN year_total END) AS w_2000,
         COUNT(CASE WHEN sale_type = 's' AND yr = 1999 THEN 1 END) AS has_s_1999,
         COUNT(CASE WHEN sale_type = 's' AND yr = 2000 THEN 1 END) AS has_s_2000,
         COUNT(CASE WHEN sale_type = 'w' AND yr = 1999 THEN 1 END) AS has_w_1999,
         COUNT(CASE WHEN sale_type = 'w' AND yr = 2000 THEN 1 END) AS has_w_2000
  FROM year_total
  GROUP BY customer_id, customer_first_name, customer_last_name
)
SELECT customer_id, customer_first_name, customer_last_name
FROM pivoted
WHERE has_s_1999 > 0 AND has_s_2000 > 0 AND has_w_1999 > 0 AND has_w_2000 > 0
  AND s_1999 > 0 AND w_1999 > 0
  AND w_2000 / w_1999 > s_2000 / s_1999
ORDER BY customer_first_name, customer_id, customer_last_name
LIMIT 100;
