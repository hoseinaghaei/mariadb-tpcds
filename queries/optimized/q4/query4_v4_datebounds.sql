-- Candidate: v3 plus redundant fact-date bounds. The date join and year
-- predicate remain, so equivalence does not require dense/chronological keys.
-- The bounds come from date_dim, including in small semantic fixtures.
-- Candidate: push the existing positive first-year requirement into each
-- aggregate and require a non-NULL second-year total. Together these imply
-- that both year groups exist, so COUNT(DISTINCT d_year) is unnecessary.
-- Preserve the monetary expressions and the final guarded comparisons.
WITH date_bounds AS (
    SELECT MIN(d_date_sk) AS lo, MAX(d_date_sk) AS hi
    FROM date_dim WHERE d_year IN (2001,2002)
), s AS (
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
      AND ss_sold_date_sk BETWEEN (SELECT lo FROM date_bounds)
                                    AND (SELECT hi FROM date_bounds)
    GROUP BY ss_customer_sk
    HAVING y1 > 0 AND y2 IS NOT NULL
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
      AND cs_sold_date_sk BETWEEN (SELECT lo FROM date_bounds)
                                    AND (SELECT hi FROM date_bounds)
    GROUP BY cs_bill_customer_sk
    HAVING y1 > 0 AND y2 IS NOT NULL
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
      AND ws_sold_date_sk BETWEEN (SELECT lo FROM date_bounds)
                                    AND (SELECT hi FROM date_bounds)
    GROUP BY ws_bill_customer_sk
    HAVING y1 > 0 AND y2 IS NOT NULL
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
