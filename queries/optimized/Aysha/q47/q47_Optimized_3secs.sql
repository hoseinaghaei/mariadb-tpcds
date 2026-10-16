
--   SET SESSION tmp_table_size      = 512*1024*1024;
--   SET SESSION max_heap_table_size = 512*1024*1024;

WITH monthly AS (
  SELECT STRAIGHT_JOIN                         
         ss_item_sk, ss_store_sk,
         d_year, d_moy,
         SUM(ss_sales_price) AS sales
  FROM date_dim,
       store_sales FORCE INDEX (idx_ss_date_item_store_cover)
  WHERE ss_sold_date_sk = d_date_sk
    AND d_date BETWEEN '1999-12-01' AND '2001-01-31'
  GROUP BY ss_item_sk, ss_store_sk, d_year, d_moy
),
v1 AS (
  SELECT STRAIGHT_JOIN
         i_category, i_brand,
         s_store_name, s_company_name,
         d_year, d_moy,
         SUM(sales) AS sum_sales,
         AVG(SUM(sales)) OVER (
           PARTITION BY i_category, i_brand,
                        s_store_name, s_company_name, d_year
         ) AS avg_monthly_sales,
         LAG(SUM(sales))  OVER w AS psum,
         LEAD(SUM(sales)) OVER w AS nsum
  FROM monthly
  STRAIGHT_JOIN item  ON i_item_sk  = ss_item_sk
  STRAIGHT_JOIN store ON s_store_sk = ss_store_sk
  GROUP BY i_category, i_brand,
           s_store_name, s_company_name,
           d_year, d_moy
  WINDOW w AS (
    PARTITION BY i_category, i_brand, s_store_name, s_company_name
    ORDER BY d_year, d_moy
  )
)
SELECT *
FROM v1
WHERE d_year = 2000
  AND avg_monthly_sales > 0
  AND psum IS NOT NULL                        
  AND nsum IS NOT NULL
  AND ABS(sum_sales - avg_monthly_sales) / avg_monthly_sales > 0.1
ORDER BY sum_sales - avg_monthly_sales, psum
LIMIT 100;

