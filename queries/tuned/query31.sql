-- query31
-- source: queries/optimized/q31/query31_BEST.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

WITH ss_quarter AS (
    SELECT ca_county, d_qoy, d_year,
           SUM(ss_ext_sales_price) AS store_sales
    FROM store_sales
    JOIN date_dim ON ss_sold_date_sk = d_date_sk
    JOIN customer_address ON ss_addr_sk = ca_address_sk
    WHERE d_year = 2001 AND d_qoy IN (1, 2, 3)
    GROUP BY ca_county, d_qoy, d_year
),
ws_quarter AS (
    SELECT ca_county, d_qoy, d_year,
           SUM(ws_ext_sales_price) AS web_sales
    FROM web_sales
    JOIN date_dim ON ws_sold_date_sk = d_date_sk
    JOIN customer_address ON ws_bill_addr_sk = ca_address_sk
    WHERE d_year = 2001 AND d_qoy IN (1, 2, 3)
    GROUP BY ca_county, d_qoy, d_year
),
ss AS (
    SELECT ca_county, d_year,
           MAX(CASE WHEN d_qoy = 1 THEN store_sales END) AS q1,
           MAX(CASE WHEN d_qoy = 2 THEN store_sales END) AS q2,
           MAX(CASE WHEN d_qoy = 3 THEN store_sales END) AS q3
    FROM ss_quarter
    GROUP BY ca_county, d_year
    HAVING COUNT(DISTINCT d_qoy) = 3
),
ws AS (
    SELECT ca_county, d_year,
           MAX(CASE WHEN d_qoy = 1 THEN web_sales END) AS q1,
           MAX(CASE WHEN d_qoy = 2 THEN web_sales END) AS q2,
           MAX(CASE WHEN d_qoy = 3 THEN web_sales END) AS q3
    FROM ws_quarter
    GROUP BY ca_county, d_year
    HAVING COUNT(DISTINCT d_qoy) = 3
)
SELECT ss.ca_county, ss.d_year,
       ws.q2 / ws.q1 AS web_q1_q2_increase,
       ss.q2 / ss.q1 AS store_q1_q2_increase,
       ws.q3 / ws.q2 AS web_q2_q3_increase,
       ss.q3 / ss.q2 AS store_q2_q3_increase
FROM ss
JOIN ws ON ss.ca_county = ws.ca_county AND ss.d_year = ws.d_year
WHERE CASE WHEN ws.q1 > 0 THEN ws.q2 / ws.q1 ELSE NULL END
        > CASE WHEN ss.q1 > 0 THEN ss.q2 / ss.q1 ELSE NULL END
  AND CASE WHEN ws.q2 > 0 THEN ws.q3 / ws.q2 ELSE NULL END
        > CASE WHEN ss.q2 > 0 THEN ss.q3 / ss.q2 ELSE NULL END
ORDER BY web_q2_q3_increase;
