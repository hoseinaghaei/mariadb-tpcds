-- query33
-- source: queries/optimized/Nafiz/tier4/q33/query33_BEST.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

WITH ss AS (
 SELECT i_manufact_id, SUM(ss_ext_sales_price) total_sales
 FROM store_sales, date_dim, customer_address, item
 WHERE i_manufact_id IN (
   SELECT i_manufact_id FROM item WHERE i_category IN ('Books')
 )
   AND ss_item_sk = i_item_sk
   AND ss_sold_date_sk = d_date_sk
   AND d_year = 2000
   AND d_moy = 7
   AND ss_sold_date_sk BETWEEN 2451727 AND 2451757
   AND ss_addr_sk = ca_address_sk
   AND ca_gmt_offset = -5
 GROUP BY i_manufact_id
),
cs AS (
 SELECT i_manufact_id, SUM(cs_ext_sales_price) total_sales
 FROM catalog_sales, date_dim, customer_address, item
 WHERE i_manufact_id IN (
   SELECT i_manufact_id FROM item WHERE i_category IN ('Books')
 )
   AND cs_item_sk = i_item_sk
   AND cs_sold_date_sk = d_date_sk
   AND d_year = 2000
   AND d_moy = 7
   AND cs_sold_date_sk BETWEEN 2451727 AND 2451757
   AND cs_bill_addr_sk = ca_address_sk
   AND ca_gmt_offset = -5
 GROUP BY i_manufact_id
),
ws AS (
 SELECT i_manufact_id, SUM(ws_ext_sales_price) total_sales
 FROM web_sales, date_dim, customer_address, item
 WHERE i_manufact_id IN (
   SELECT i_manufact_id FROM item WHERE i_category IN ('Books')
 )
   AND ws_item_sk = i_item_sk
   AND ws_sold_date_sk = d_date_sk
   AND d_year = 2000
   AND d_moy = 7
   AND ws_sold_date_sk BETWEEN 2451727 AND 2451757
   AND ws_bill_addr_sk = ca_address_sk
   AND ca_gmt_offset = -5
 GROUP BY i_manufact_id
)
SELECT i_manufact_id, SUM(total_sales) total_sales
FROM (
 SELECT * FROM ss
 UNION ALL
 SELECT * FROM cs
 UNION ALL
 SELECT * FROM ws
) tmp1
GROUP BY i_manufact_id
ORDER BY total_sales
LIMIT 100;
