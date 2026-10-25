-- Q23: customer-first filtering plus one pass over store_sales for both
-- all-time and 1999-2002 customer totals. Date keys were verified against
-- date_dim: 2451180..2452640 equals exactly 1999-01-01..2002-12-31.
CREATE TEMPORARY TABLE q23_customer_sales AS
SELECT c_customer_sk,
       SUM(ss_quantity * ss_sales_price) AS all_sales,
       SUM(CASE WHEN ss_sold_date_sk BETWEEN 2451180 AND 2452640
                THEN ss_quantity * ss_sales_price END) AS period_sales
FROM store_sales
JOIN customer ON ss_customer_sk = c_customer_sk
GROUP BY c_customer_sk;

CREATE TEMPORARY TABLE q23_best_customers AS
SELECT c_customer_sk
FROM q23_customer_sales
WHERE all_sales > 0.95 * (SELECT MAX(period_sales) FROM q23_customer_sales);
DROP TEMPORARY TABLE q23_customer_sales;

CREATE TEMPORARY TABLE q23_candidate_items AS
SELECT DISTINCT item_sk
FROM (
  SELECT cs_item_sk AS item_sk
  FROM catalog_sales
  JOIN date_dim ON cs_sold_date_sk = d_date_sk
  WHERE d_year = 1999 AND d_moy = 7
    AND cs_bill_customer_sk IN (SELECT c_customer_sk FROM q23_best_customers)
  UNION ALL
  SELECT ws_item_sk AS item_sk
  FROM web_sales
  JOIN date_dim ON ws_sold_date_sk = d_date_sk
  WHERE d_year = 1999 AND d_moy = 7
    AND ws_bill_customer_sk IN (SELECT c_customer_sk FROM q23_best_customers)
) AS channel_items;

CREATE TEMPORARY TABLE q23_frequent_items AS
SELECT DISTINCT item_sk
FROM (
  SELECT i_item_sk AS item_sk
  FROM store_sales
  JOIN date_dim ON ss_sold_date_sk = d_date_sk
  JOIN item ON ss_item_sk = i_item_sk
  WHERE d_year IN (1999, 2000, 2001, 2002)
    AND ss_item_sk IN (SELECT item_sk FROM q23_candidate_items)
  GROUP BY SUBSTR(i_item_desc, 1, 30), i_item_sk, d_date
  HAVING COUNT(*) > 4
) AS frequent;

SELECT SUM(sales)
FROM (
  SELECT cs_quantity * cs_list_price AS sales
  FROM catalog_sales
  JOIN date_dim ON cs_sold_date_sk = d_date_sk
  WHERE d_year = 1999 AND d_moy = 7
    AND cs_item_sk IN (SELECT item_sk FROM q23_frequent_items)
    AND cs_bill_customer_sk IN (SELECT c_customer_sk FROM q23_best_customers)
  UNION ALL
  SELECT ws_quantity * ws_list_price AS sales
  FROM web_sales
  JOIN date_dim ON ws_sold_date_sk = d_date_sk
  WHERE d_year = 1999 AND d_moy = 7
    AND ws_item_sk IN (SELECT item_sk FROM q23_frequent_items)
    AND ws_bill_customer_sk IN (SELECT c_customer_sk FROM q23_best_customers)
) AS channel_sales
LIMIT 100;

SELECT c_last_name, c_first_name, sales
FROM (
  SELECT c_last_name, c_first_name, SUM(cs_quantity * cs_list_price) AS sales
  FROM catalog_sales
  JOIN customer ON cs_bill_customer_sk = c_customer_sk
  JOIN date_dim ON cs_sold_date_sk = d_date_sk
  WHERE d_year = 1999 AND d_moy = 7
    AND cs_item_sk IN (SELECT item_sk FROM q23_frequent_items)
    AND cs_bill_customer_sk IN (SELECT c_customer_sk FROM q23_best_customers)
  GROUP BY c_last_name, c_first_name
  UNION ALL
  SELECT c_last_name, c_first_name, SUM(ws_quantity * ws_list_price) AS sales
  FROM web_sales
  JOIN customer ON ws_bill_customer_sk = c_customer_sk
  JOIN date_dim ON ws_sold_date_sk = d_date_sk
  WHERE d_year = 1999 AND d_moy = 7
    AND ws_item_sk IN (SELECT item_sk FROM q23_frequent_items)
    AND ws_bill_customer_sk IN (SELECT c_customer_sk FROM q23_best_customers)
  GROUP BY c_last_name, c_first_name
) AS customer_channel_sales
ORDER BY c_last_name, c_first_name, sales
LIMIT 100;

DROP TEMPORARY TABLE q23_frequent_items;
DROP TEMPORARY TABLE q23_candidate_items;
DROP TEMPORARY TABLE q23_best_customers;
