-- Candidate: aggregate fact measures by item key, store key and month before
-- joining product/store descriptions. Keep the complete original descriptive
-- ROLLUP and ranking, including merges of equal descriptions across keys.
-- Dimension keys must be unique; the schema gives item/store primary keys.
-- Decimal SUMs retain the original expression and NULL-to-zero handling.
SET SESSION sort_buffer_size    = 64*1024*1024;
SET SESSION tmp_table_size      = 256*1024*1024;
SET SESSION max_heap_table_size = 256*1024*1024;
SELECT MIN(d_date_sk), MAX(d_date_sk) INTO @lo, @hi
FROM date_dim
WHERE d_month_seq BETWEEN 1176 AND 1176+11;
WITH monthly AS (
    SELECT ss.ss_item_sk AS item_sk, ss.ss_store_sk AS store_sk,
           d.d_year, d.d_qoy, d.d_moy,
           SUM(COALESCE(ss.ss_sales_price * ss.ss_quantity, 0)) AS sales
    FROM store_sales ss
    JOIN date_dim d ON d.d_date_sk = ss.ss_sold_date_sk
    WHERE d.d_month_seq BETWEEN 1176 AND 1176+11
      AND ss.ss_sold_date_sk BETWEEN @lo AND @hi
    GROUP BY ss.ss_item_sk, ss.ss_store_sk, d.d_year, d.d_qoy, d.d_moy
)
SELECT i_category, i_class, i_brand, i_product_name,
       d_year, d_qoy, d_moy, s_store_id, sumsales, rk
FROM (
    SELECT i_category, i_class, i_brand, i_product_name,
           d_year, d_qoy, d_moy, s_store_id, sumsales,
           RANK() OVER (PARTITION BY i_category ORDER BY sumsales DESC) AS rk
    FROM (
        SELECT i.i_category, i.i_class, i.i_brand, i.i_product_name,
               m.d_year, m.d_qoy, m.d_moy, s.s_store_id,
               SUM(m.sales) AS sumsales
        FROM monthly m
        JOIN item i  ON i.i_item_sk = m.item_sk
        JOIN store s ON s.s_store_sk = m.store_sk
        GROUP BY i.i_category, i.i_class, i.i_brand, i.i_product_name,
                 m.d_year, m.d_qoy, m.d_moy, s.s_store_id WITH ROLLUP
    ) dw1
) dw2
WHERE rk <= 100
ORDER BY i_category, i_class, i_brand, i_product_name,
         d_year, d_qoy, d_moy, s_store_id, sumsales, rk
LIMIT 100;
