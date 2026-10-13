SET SESSION sort_buffer_size    = 64*1024*1024;
SET SESSION tmp_table_size      = 256*1024*1024;
SET SESSION max_heap_table_size = 256*1024*1024;

SELECT MIN(d_date_sk), MAX(d_date_sk) INTO @lo, @hi
FROM date_dim
WHERE d_month_seq BETWEEN 1176 AND 1176+11;

SELECT i_category, i_class, i_brand, i_product_name,
       d_year, d_qoy, d_moy, s_store_id, sumsales, rk
FROM (
    SELECT i_category, i_class, i_brand, i_product_name,
           d_year, d_qoy, d_moy, s_store_id, sumsales,
           RANK() OVER (PARTITION BY i_category ORDER BY sumsales DESC) AS rk
    FROM (
        SELECT i.i_category, i.i_class, i.i_brand, i.i_product_name,
               d.d_year, d.d_qoy, d.d_moy, s.s_store_id,
               SUM(COALESCE(ss.ss_sales_price * ss.ss_quantity, 0)) AS sumsales
        FROM store_sales ss
        JOIN item i      ON i.i_item_sk  = ss.ss_item_sk
        JOIN date_dim d  ON d.d_date_sk  = ss.ss_sold_date_sk
        JOIN store s     ON s.s_store_sk = ss.ss_store_sk
        WHERE ss.ss_sold_date_sk BETWEEN @lo AND @hi
        GROUP BY i.i_category, i.i_class, i.i_brand, i.i_product_name,
                 d.d_year, d.d_qoy, d.d_moy, s.s_store_id WITH ROLLUP
    ) dw1
) dw2
WHERE rk <= 100
ORDER BY i_category, i_class, i_brand, i_product_name,
         d_year, d_qoy, d_moy, s_store_id, sumsales, rk
LIMIT 100;