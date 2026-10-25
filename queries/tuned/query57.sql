-- query57
-- source: queries/optimized/Nafiz/tier5/q57/query57_BEST.sql
-- split materialisation left ON: disabling it measured +3.2s (slower)

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

WITH monthly AS (
  SELECT /*+ JOIN_PREFIX(date_dim, catalog_sales) */ i_category, i_brand, cc_name, d_year, d_moy, SUM(cs_sales_price) AS sum_sales
  FROM date_dim JOIN catalog_sales ON cs_sold_date_sk=d_date_sk
  JOIN item ON cs_item_sk=i_item_sk JOIN call_center ON cc_call_center_sk=cs_call_center_sk
  WHERE cs_sold_date_sk BETWEEN 2451514 AND 2451941
    AND (d_year=2000 OR (d_year=1999 AND d_moy=12) OR (d_year=2001 AND d_moy=1))
  GROUP BY i_category,i_brand,cc_name,d_year,d_moy
), scored AS (
  SELECT i_brand,d_year,d_moy,AVG(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name,d_year) avg_monthly_sales,
    sum_sales,LAG(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name ORDER BY d_year,d_moy) psum,
    LEAD(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name ORDER BY d_year,d_moy) nsum FROM monthly
)
SELECT i_brand,d_year,d_moy,avg_monthly_sales,sum_sales,psum,nsum FROM scored
WHERE d_year=2000 AND avg_monthly_sales>0 AND psum IS NOT NULL AND nsum IS NOT NULL
  AND ABS(sum_sales-avg_monthly_sales)/avg_monthly_sales>0.1
ORDER BY sum_sales-avg_monthly_sales, psum LIMIT 100;
