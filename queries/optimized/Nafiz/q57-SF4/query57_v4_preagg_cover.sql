WITH fact_month AS (
SELECT cs_item_sk,cs_call_center_sk,d_year,d_moy,SUM(cs_sales_price) sales FROM catalog_sales
JOIN date_dim ON cs_sold_date_sk=d_date_sk
WHERE (d_year=2000 OR (d_year=1999 AND d_moy=12) OR (d_year=2001 AND d_moy=1))
GROUP BY cs_item_sk,cs_call_center_sk,d_year,d_moy), monthly AS (
SELECT i_category,i_brand,cc_name,d_year,d_moy,SUM(sales) sum_sales FROM fact_month
JOIN item ON cs_item_sk=i_item_sk JOIN call_center ON cs_call_center_sk=cc_call_center_sk
WHERE i_category IS NOT NULL AND i_brand IS NOT NULL AND cc_name IS NOT NULL
GROUP BY i_category,i_brand,cc_name,d_year,d_moy), scored AS (
SELECT i_brand,d_year,d_moy,AVG(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name,d_year) avg_monthly_sales,
sum_sales,LAG(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name ORDER BY d_year,d_moy) psum,
LEAD(sum_sales) OVER (PARTITION BY i_category,i_brand,cc_name ORDER BY d_year,d_moy) nsum,
LAG(1) OVER (PARTITION BY i_category,i_brand,cc_name ORDER BY d_year,d_moy) has_prev,
LEAD(1) OVER (PARTITION BY i_category,i_brand,cc_name ORDER BY d_year,d_moy) has_next FROM monthly)
SELECT i_brand,d_year,d_moy,avg_monthly_sales,sum_sales,psum,nsum FROM scored
WHERE d_year=2000 AND avg_monthly_sales>0 AND has_prev=1 AND has_next=1
AND CASE WHEN avg_monthly_sales>0 THEN ABS(sum_sales-avg_monthly_sales)/avg_monthly_sales ELSE NULL END>0.1
ORDER BY sum_sales-avg_monthly_sales,psum LIMIT 100;