-- query65
-- source: queries/optimized/q65/query65_BEST.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

WITH item_revenue AS (
    SELECT
        ss.ss_store_sk,
        ss.ss_item_sk,
        SUM(ss.ss_sales_price) AS revenue
    FROM store_sales ss
    JOIN date_dim d
      ON d.d_date_sk = ss.ss_sold_date_sk
    WHERE d.d_month_seq BETWEEN 1176 AND 1187
      AND ss.ss_sold_date_sk BETWEEN
          (SELECT MIN(d_date_sk) FROM date_dim WHERE d_month_seq BETWEEN 1176 AND 1187)
          AND
          (SELECT MAX(d_date_sk) FROM date_dim WHERE d_month_seq BETWEEN 1176 AND 1187)
    GROUP BY ss.ss_store_sk, ss.ss_item_sk
),
scored AS (
    SELECT
        ss_store_sk,
        ss_item_sk,
        revenue,
        AVG(revenue) OVER (
            PARTITION BY ss_store_sk
            ORDER BY ss_item_sk
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS ave
    FROM item_revenue
)
SELECT
    s.s_store_name,
    i.i_item_desc,
    sc.revenue,
    i.i_current_price,
    i.i_wholesale_cost,
    i.i_brand
FROM scored sc
JOIN store s
  ON s.s_store_sk = sc.ss_store_sk
JOIN item i
  ON i.i_item_sk = sc.ss_item_sk
WHERE sc.revenue <= 0.1 * sc.ave
ORDER BY s.s_store_name, i.i_item_desc
LIMIT 100;
