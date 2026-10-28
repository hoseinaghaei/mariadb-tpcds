-- Explicit grouping levels distinguish genuine NULL values from subtotals.
-- UNION ALL preserves duplicate-looking leaf/subtotal rows. The grand-total
-- branch is suppressed on empty input, matching MariaDB WITH ROLLUP.
WITH source_rows AS (
    SELECT ss_net_profit, s_state, s_county
 from
    store_sales
   ,date_dim       d1
   ,store
 where
    d1.d_month_seq between 1176 and 1176+11
 and d1.d_date_sk = ss_sold_date_sk
 and s_store_sk  = ss_store_sk
 and s_state in
             ( select s_state
               from  (select s_state as s_state,
 			    rank() over ( partition by s_state order by sum(ss_net_profit) desc) as ranking
                      from   store_sales, store, date_dim
                      where  d_month_seq between 1176 and 1176+11
 			    and d_date_sk = ss_sold_date_sk
 			    and s_store_sk  = ss_store_sk
                      group by s_state
                     ) tmp1 
               where ranking <= 5
             )
), hierarchy AS (
    SELECT SUM(ss_net_profit) AS total_sum, s_state, s_county, 0 AS lochierarchy
    FROM source_rows GROUP BY s_state, s_county
    UNION ALL
    SELECT SUM(ss_net_profit) AS total_sum, s_state, NULL, 1
    FROM source_rows GROUP BY s_state
    UNION ALL
    SELECT SUM(ss_net_profit) AS total_sum, NULL, NULL, 2
    FROM source_rows HAVING COUNT(*) > 0
)
SELECT total_sum, s_state, s_county, lochierarchy,
       RANK() OVER (
           PARTITION BY lochierarchy,
                        CASE WHEN lochierarchy = 0 THEN s_state END
           ORDER BY total_sum DESC
       ) AS rank_within_parent
FROM hierarchy
ORDER BY lochierarchy DESC,
         CASE WHEN lochierarchy = 0 THEN s_state END,
         rank_within_parent
LIMIT 100;
