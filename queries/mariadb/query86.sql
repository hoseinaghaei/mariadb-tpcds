-- Explicit grouping levels distinguish genuine NULL values from subtotals.
-- UNION ALL preserves duplicate-looking leaf/subtotal rows. The grand-total
-- branch is suppressed on empty input, matching MariaDB WITH ROLLUP.
WITH source_rows AS (
    SELECT ws_net_paid, i_category, i_class
 from
    web_sales
   ,date_dim       d1
   ,item
 where
    d1.d_month_seq between 1176 and 1176+11
 and d1.d_date_sk = ws_sold_date_sk
 and i_item_sk  = ws_item_sk
), hierarchy AS (
    SELECT SUM(ws_net_paid) AS total_sum, i_category, i_class, 0 AS lochierarchy
    FROM source_rows GROUP BY i_category, i_class
    UNION ALL
    SELECT SUM(ws_net_paid) AS total_sum, i_category, NULL, 1
    FROM source_rows GROUP BY i_category
    UNION ALL
    SELECT SUM(ws_net_paid) AS total_sum, NULL, NULL, 2
    FROM source_rows HAVING COUNT(*) > 0
)
SELECT total_sum, i_category, i_class, lochierarchy,
       RANK() OVER (
           PARTITION BY lochierarchy,
                        CASE WHEN lochierarchy = 0 THEN i_category END
           ORDER BY total_sum DESC
       ) AS rank_within_parent
FROM hierarchy
ORDER BY lochierarchy DESC,
         CASE WHEN lochierarchy = 0 THEN i_category END,
         rank_within_parent
LIMIT 100;
