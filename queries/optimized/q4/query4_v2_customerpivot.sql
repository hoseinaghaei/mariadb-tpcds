-- Requires unique customer.c_customer_id; validate that assumption separately.
-- Aggregate the two years once per channel using narrow surrogate keys.
-- Keep both year groups, NULL totals, positive denominators and exact arithmetic.
WITH s AS (
    SELECT ss_customer_sk AS customer_sk,
           SUM(CASE WHEN d_year = 2001 THEN
               ((ss_ext_list_price-ss_ext_wholesale_cost-ss_ext_discount_amt)+ss_ext_sales_price)/2
           END) AS y1,
           SUM(CASE WHEN d_year = 2002 THEN
               ((ss_ext_list_price-ss_ext_wholesale_cost-ss_ext_discount_amt)+ss_ext_sales_price)/2
           END) AS y2
    FROM store_sales
    JOIN date_dim ON ss_sold_date_sk = d_date_sk
    WHERE d_year IN (2001,2002)
    GROUP BY ss_customer_sk
    HAVING COUNT(DISTINCT d_year) = 2
),
c AS (
    SELECT cs_bill_customer_sk AS customer_sk,
           SUM(CASE WHEN d_year = 2001 THEN
               ((cs_ext_list_price-cs_ext_wholesale_cost-cs_ext_discount_amt)+cs_ext_sales_price)/2
           END) AS y1,
           SUM(CASE WHEN d_year = 2002 THEN
               ((cs_ext_list_price-cs_ext_wholesale_cost-cs_ext_discount_amt)+cs_ext_sales_price)/2
           END) AS y2
    FROM catalog_sales
    JOIN date_dim ON cs_sold_date_sk = d_date_sk
    WHERE d_year IN (2001,2002)
    GROUP BY cs_bill_customer_sk
    HAVING COUNT(DISTINCT d_year) = 2
),
w AS (
    SELECT ws_bill_customer_sk AS customer_sk,
           SUM(CASE WHEN d_year = 2001 THEN
               ((ws_ext_list_price-ws_ext_wholesale_cost-ws_ext_discount_amt)+ws_ext_sales_price)/2
           END) AS y1,
           SUM(CASE WHEN d_year = 2002 THEN
               ((ws_ext_list_price-ws_ext_wholesale_cost-ws_ext_discount_amt)+ws_ext_sales_price)/2
           END) AS y2
    FROM web_sales
    JOIN date_dim ON ws_sold_date_sk = d_date_sk
    WHERE d_year IN (2001,2002)
    GROUP BY ws_bill_customer_sk
    HAVING COUNT(DISTINCT d_year) = 2
)
SELECT customer.c_customer_id AS customer_id,
       customer.c_first_name AS customer_first_name,
       customer.c_last_name AS customer_last_name,
       customer.c_login AS customer_login
FROM s
JOIN c ON s.customer_sk = c.customer_sk
JOIN w ON s.customer_sk = w.customer_sk
JOIN customer ON customer.c_customer_sk = s.customer_sk
WHERE s.y1 > 0 AND c.y1 > 0 AND w.y1 > 0
  AND CASE WHEN c.y1 > 0 THEN c.y2/c.y1 ELSE NULL END
      > CASE WHEN s.y1 > 0 THEN s.y2/s.y1 ELSE NULL END
  AND CASE WHEN c.y1 > 0 THEN c.y2/c.y1 ELSE NULL END
      > CASE WHEN w.y1 > 0 THEN w.y2/w.y1 ELSE NULL END
ORDER BY customer_id, customer_first_name, customer_last_name, customer_login
LIMIT 100;
