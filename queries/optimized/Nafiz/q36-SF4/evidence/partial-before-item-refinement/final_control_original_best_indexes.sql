-- Explicit grouping levels distinguish genuine NULL values from subtotals.
-- UNION ALL preserves duplicate-looking leaf/subtotal rows. The grand-total
-- branch is suppressed on empty input, matching MariaDB WITH ROLLUP.
WITH source_rows AS (
    SELECT ss_net_profit, ss_ext_sales_price, i_category, i_class
 from
    store_sales
   ,date_dim       d1
   ,item
   ,store
 where
    d1.d_year = 2001 
 and d1.d_date_sk = ss_sold_date_sk
 and i_item_sk  = ss_item_sk 
 and s_store_sk  = ss_store_sk
 and s_state in ('TN','TN','TN','TN',
                 'TN','TN','TN','TN')
), hierarchy AS (
    SELECT SUM(ss_net_profit)/SUM(ss_ext_sales_price) AS gross_margin, i_category, i_class, 0 AS lochierarchy
    FROM source_rows GROUP BY i_category, i_class
    UNION ALL
    SELECT SUM(ss_net_profit)/SUM(ss_ext_sales_price) AS gross_margin, i_category, NULL, 1
    FROM source_rows GROUP BY i_category
    UNION ALL
    SELECT SUM(ss_net_profit)/SUM(ss_ext_sales_price) AS gross_margin, NULL, NULL, 2
    FROM source_rows HAVING COUNT(*) > 0
)
SELECT gross_margin, i_category, i_class, lochierarchy,
       RANK() OVER (
           PARTITION BY lochierarchy,
                        CASE WHEN lochierarchy = 0 THEN i_category END
           ORDER BY gross_margin ASC
       ) AS rank_within_parent
FROM hierarchy
ORDER BY lochierarchy DESC,
         CASE WHEN lochierarchy = 0 THEN i_category END,
         rank_within_parent
LIMIT 100;
