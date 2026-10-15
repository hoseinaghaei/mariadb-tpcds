-- Daily channel groups are unique on (item_sk,d_date).
-- Combine those keys once, preserve channel presence, and retain both
-- the original running SUM and subsequent running MAX operations.
WITH channel_daily AS (
    SELECT ws_item_sk AS item_sk, d_date, 'w' AS channel,
           SUM(ws_sales_price) AS daily_sales
    FROM web_sales
    JOIN date_dim ON ws_sold_date_sk = d_date_sk
    WHERE d_month_seq BETWEEN 1176 AND 1176+11
      AND ws_item_sk IS NOT NULL
    GROUP BY ws_item_sk, d_date
    UNION ALL
    SELECT ss_item_sk AS item_sk, d_date, 's' AS channel,
           SUM(ss_sales_price) AS daily_sales
    FROM store_sales
    JOIN date_dim ON ss_sold_date_sk = d_date_sk
    WHERE d_month_seq BETWEEN 1176 AND 1176+11
      AND ss_item_sk IS NOT NULL
    GROUP BY ss_item_sk, d_date
),
daily AS (
    SELECT item_sk, d_date,
           MAX(CASE WHEN channel = 'w' THEN daily_sales END) AS web_daily,
           MAX(CASE WHEN channel = 's' THEN daily_sales END) AS store_daily,
           MAX(CASE WHEN channel = 'w' THEN 1 ELSE 0 END) AS has_web,
           MAX(CASE WHEN channel = 's' THEN 1 ELSE 0 END) AS has_store
    FROM channel_daily
    GROUP BY item_sk, d_date
),
running AS (
    SELECT item_sk, d_date, has_web, has_store,
           SUM(web_daily) OVER (
               PARTITION BY item_sk ORDER BY d_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS web_running,
           SUM(store_daily) OVER (
               PARTITION BY item_sk ORDER BY d_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS store_running
    FROM daily
),
masked AS (
    SELECT item_sk, d_date,
           CASE WHEN has_web = 1 THEN web_running END AS web_sales,
           CASE WHEN has_store = 1 THEN store_running END AS store_sales
    FROM running
),
y AS (
    SELECT item_sk, d_date, web_sales, store_sales,
           MAX(web_sales) OVER (
               PARTITION BY item_sk ORDER BY d_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS web_cumulative,
           MAX(store_sales) OVER (
               PARTITION BY item_sk ORDER BY d_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS store_cumulative
    FROM masked
)
SELECT item_sk, d_date, web_sales, store_sales, web_cumulative, store_cumulative
FROM y
WHERE web_cumulative > store_cumulative
ORDER BY item_sk, d_date
LIMIT 100;
