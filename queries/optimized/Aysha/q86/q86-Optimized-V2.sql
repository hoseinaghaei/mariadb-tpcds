analyze format=json
SELECT *
FROM (
    SELECT
        SUM(s.item_net_paid) AS total_sum,
        i.i_category,
        i.i_class,
        (i.i_category IS NULL)
          + (i.i_class IS NULL) AS lochierarchy,
        RANK() OVER (
            PARTITION BY
                (i.i_category IS NULL) + (i.i_class IS NULL),
                CASE
                    WHEN (i.i_class IS NULL) = 0
                    THEN i.i_category
                END
            ORDER BY SUM(s.item_net_paid) DESC
        ) AS rank_within_parent
    FROM (
        SELECT
            ws.ws_item_sk,
            SUM(ws.ws_net_paid) AS item_net_paid
        FROM date_dim d
        STRAIGHT_JOIN web_sales ws
            ON ws.ws_sold_date_sk = d.d_date_sk
        WHERE d.d_month_seq BETWEEN 1176 AND 1187
        GROUP BY ws.ws_item_sk
    ) s
    STRAIGHT_JOIN item i
        ON i.i_item_sk = s.ws_item_sk
    GROUP BY
        i.i_category,
        i.i_class WITH ROLLUP
) tpcds_rollup
ORDER BY
    lochierarchy DESC,
    CASE
        WHEN lochierarchy = 0 THEN i_category
    END,
    rank_within_parent
LIMIT 100;