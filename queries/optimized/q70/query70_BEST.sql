WITH profit_by_store AS (
    SELECT
        ss.ss_store_sk,
        SUM(ss.ss_net_profit) AS profit
    FROM store_sales ss
    JOIN date_dim d
      ON d.d_date_sk = ss.ss_sold_date_sk
    WHERE d.d_month_seq BETWEEN 1176 AND 1187
      AND ss.ss_sold_date_sk BETWEEN
          (SELECT MIN(d_date_sk) FROM date_dim WHERE d_month_seq BETWEEN 1176 AND 1187)
          AND
          (SELECT MAX(d_date_sk) FROM date_dim WHERE d_month_seq BETWEEN 1176 AND 1187)
    GROUP BY ss.ss_store_sk
)
SELECT
    total_sum,
    s_state,
    s_county,
    lochierarchy,
    rank_within_parent
FROM (
    SELECT
        SUM(p.profit) AS total_sum,
        s.s_state,
        s.s_county,
        (s.s_state IS NULL) + (s.s_county IS NULL) AS lochierarchy,
        RANK() OVER (
            PARTITION BY
                (s.s_state IS NULL) + (s.s_county IS NULL),
                CASE WHEN (s.s_county IS NULL) = 0 THEN s.s_state END
            ORDER BY SUM(p.profit) DESC
        ) AS rank_within_parent
    FROM profit_by_store p
    JOIN store s
      ON s.s_store_sk = p.ss_store_sk
    WHERE s.s_state IS NOT NULL
    GROUP BY s.s_state, s.s_county WITH ROLLUP
) tpcds_rollup
ORDER BY
    lochierarchy DESC,
    CASE WHEN lochierarchy = 0 THEN s_state END,
    rank_within_parent
LIMIT 100;
