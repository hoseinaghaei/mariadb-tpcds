-- query70
-- source: queries/optimized/q70-sf4/query70_v1_nosubquery.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

WITH ss_by_store AS (
    SELECT ss_store_sk, SUM(ss_net_profit) AS np
    FROM store_sales
    JOIN date_dim ON d_date_sk = ss_sold_date_sk
    WHERE d_month_seq BETWEEN 1176 AND 1176+11
    GROUP BY ss_store_sk
), source_rows AS (
    SELECT np, s_state, s_county
    FROM ss_by_store
    JOIN store ON s_store_sk = ss_store_sk
    WHERE s_state IS NOT NULL
), hierarchy AS (
    SELECT SUM(np) AS total_sum, s_state, s_county, 0 AS lochierarchy
    FROM source_rows GROUP BY s_state, s_county
    UNION ALL
    SELECT SUM(np) AS total_sum, s_state, NULL, 1
    FROM source_rows GROUP BY s_state
    UNION ALL
    SELECT SUM(np) AS total_sum, NULL, NULL, 2
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
