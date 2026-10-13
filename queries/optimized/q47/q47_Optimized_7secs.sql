WITH v1 AS (
  SELECT STRAIGHT_JOIN                     
         i_category, i_brand,
         s_store_name, s_company_name,
         d_year, d_moy,
         SUM(ss_sales_price) AS sum_sales,
         AVG(SUM(ss_sales_price)) OVER (
           PARTITION BY i_category, i_brand,
                        s_store_name, s_company_name, d_year
         ) AS avg_monthly_sales,
         LAG(SUM(ss_sales_price))  OVER w AS psum,  
         LEAD(SUM(ss_sales_price)) OVER w AS nsum    
  FROM date_dim, store_sales, item, store
  WHERE ss_sold_date_sk = d_date_sk
    AND ss_item_sk      = i_item_sk
    AND ss_store_sk     = s_store_sk
   
    AND d_date BETWEEN '1999-12-01' AND '2001-01-31'
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