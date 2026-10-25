-- v1: aggregate each sale type once, then pivot the required four years.
WITH year_total AS (
  SELECT c_customer_id AS customer_id, c_first_name AS customer_first_name,
         c_last_name AS customer_last_name, c_login AS customer_login,
         d_year AS yr, SUM(ss_ext_list_price - ss_ext_discount_amt) AS year_total,
         's' AS sale_type
  FROM customer
  JOIN store_sales ON c_customer_sk = ss_customer_sk
  JOIN date_dim ON ss_sold_date_sk = d_date_sk
  WHERE d_year IN (2001, 2002)
  GROUP BY c_customer_id, c_first_name, c_last_name, c_login, d_year
  UNION ALL
  SELECT c_customer_id, c_first_name, c_last_name, c_login, d_year,
         SUM(ws_ext_list_price - ws_ext_discount_amt), 'w'
  FROM customer
  JOIN web_sales ON c_customer_sk = ws_bill_customer_sk
  JOIN date_dim ON ws_sold_date_sk = d_date_sk
  WHERE d_year IN (2001, 2002)
  GROUP BY c_customer_id, c_first_name, c_last_name, c_login, d_year
), pivoted AS (
  SELECT customer_id, customer_first_name, customer_last_name, customer_login,
         MAX(CASE WHEN sale_type = 's' AND yr = 2001 THEN year_total END) AS s_2001,
         MAX(CASE WHEN sale_type = 's' AND yr = 2002 THEN year_total END) AS s_2002,
         MAX(CASE WHEN sale_type = 'w' AND yr = 2001 THEN year_total END) AS w_2001,
         MAX(CASE WHEN sale_type = 'w' AND yr = 2002 THEN year_total END) AS w_2002,
         COUNT(CASE WHEN sale_type = 's' AND yr = 2001 THEN 1 END) AS has_s_2001,
         COUNT(CASE WHEN sale_type = 's' AND yr = 2002 THEN 1 END) AS has_s_2002,
         COUNT(CASE WHEN sale_type = 'w' AND yr = 2001 THEN 1 END) AS has_w_2001,
         COUNT(CASE WHEN sale_type = 'w' AND yr = 2002 THEN 1 END) AS has_w_2002
  FROM year_total
  GROUP BY customer_id, customer_first_name, customer_last_name, customer_login
)
SELECT customer_id, customer_first_name, customer_last_name, customer_login
FROM pivoted
WHERE has_s_2001 > 0 AND has_s_2002 > 0 AND has_w_2001 > 0 AND has_w_2002 > 0
  AND s_2001 > 0 AND w_2001 > 0
  AND w_2002 / w_2001 > s_2002 / s_2001
ORDER BY customer_id, customer_first_name, customer_last_name, customer_login
LIMIT 100;
