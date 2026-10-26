-- query87
-- source: queries/optimized/q87/query87_BEST.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

WITH store_visits AS (
    SELECT ss_sold_date_sk AS sold_date_sk, ss_customer_sk AS customer_sk
    FROM store_sales
    WHERE ss_sold_date_sk BETWEEN
        (SELECT MIN(d_date_sk) FROM date_dim WHERE d_month_seq BETWEEN 1176 AND 1187)
        AND
        (SELECT MAX(d_date_sk) FROM date_dim WHERE d_month_seq BETWEEN 1176 AND 1187)
      AND ss_customer_sk IS NOT NULL
    GROUP BY ss_sold_date_sk, ss_customer_sk
),
catalog_visits AS (
    SELECT cs_sold_date_sk AS sold_date_sk, cs_bill_customer_sk AS customer_sk
    FROM catalog_sales
    WHERE cs_sold_date_sk BETWEEN
        (SELECT MIN(d_date_sk) FROM date_dim WHERE d_month_seq BETWEEN 1176 AND 1187)
        AND
        (SELECT MAX(d_date_sk) FROM date_dim WHERE d_month_seq BETWEEN 1176 AND 1187)
      AND cs_bill_customer_sk IS NOT NULL
    GROUP BY cs_sold_date_sk, cs_bill_customer_sk
),
web_visits AS (
    SELECT ws_sold_date_sk AS sold_date_sk, ws_bill_customer_sk AS customer_sk
    FROM web_sales
    WHERE ws_sold_date_sk BETWEEN
        (SELECT MIN(d_date_sk) FROM date_dim WHERE d_month_seq BETWEEN 1176 AND 1187)
        AND
        (SELECT MAX(d_date_sk) FROM date_dim WHERE d_month_seq BETWEEN 1176 AND 1187)
      AND ws_bill_customer_sk IS NOT NULL
    GROUP BY ws_sold_date_sk, ws_bill_customer_sk
)
select count(*)
FROM (
    (
        SELECT STRAIGHT_JOIN c.c_last_name, c.c_first_name, d.d_date
        FROM store_visits v
        JOIN date_dim d
          ON d.d_date_sk = v.sold_date_sk
        JOIN customer c
          ON c.c_customer_sk = v.customer_sk
        WHERE d.d_month_seq BETWEEN 1176 AND 1187
    )
    EXCEPT
    (
        SELECT STRAIGHT_JOIN c.c_last_name, c.c_first_name, d.d_date
        FROM catalog_visits v
        JOIN date_dim d
          ON d.d_date_sk = v.sold_date_sk
        JOIN customer c
          ON c.c_customer_sk = v.customer_sk
        WHERE d.d_month_seq BETWEEN 1176 AND 1187
    )
    EXCEPT
    (
        SELECT STRAIGHT_JOIN c.c_last_name, c.c_first_name, d.d_date
        FROM web_visits v
        JOIN date_dim d
          ON d.d_date_sk = v.sold_date_sk
        JOIN customer c
          ON c.c_customer_sk = v.customer_sk
        WHERE d.d_month_seq BETWEEN 1176 AND 1187
    )
) cool_cust;
