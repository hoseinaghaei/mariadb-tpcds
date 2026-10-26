SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');


analyze format=json 
WITH
ss_items AS (
  SELECT i_item_id item_id, SUM(ss_ext_sales_price) ss_item_rev
  FROM (SELECT d_date_sk
        FROM date_dim
        WHERE d_week_seq = (SELECT d_week_seq FROM date_dim WHERE d_date = '1998-03-14')
       ) wk
  straight_join store_sales ss ON ss.ss_sold_date_sk = wk.d_date_sk
  straight_join item i         ON i.i_item_sk = ss.ss_item_sk
  GROUP BY i_item_id
),
cs_items AS (
  SELECT i_item_id item_id, SUM(cs_ext_sales_price) cs_item_rev
  FROM (SELECT d_date_sk
        FROM date_dim
        WHERE d_week_seq = (SELECT d_week_seq FROM date_dim WHERE d_date = '1998-03-14')
       ) wk
  straight_join catalog_sales cs ON cs.cs_sold_date_sk = wk.d_date_sk
  straight_join item i           ON i.i_item_sk = cs.cs_item_sk
  GROUP BY i_item_id
),
ws_items AS (
  SELECT i_item_id item_id, SUM(ws_ext_sales_price) ws_item_rev
  FROM (SELECT d_date_sk
        FROM date_dim
        WHERE d_week_seq = (SELECT d_week_seq FROM date_dim WHERE d_date = '1998-03-14')
       ) wk
  straight_join web_sales ws ON ws.ws_sold_date_sk = wk.d_date_sk
  straight_join item i       ON i.i_item_sk = ws.ws_item_sk
  GROUP BY i_item_id
)
SELECT ss_items.item_id, ss_item_rev,
       ss_item_rev/((ss_item_rev+cs_item_rev+ws_item_rev)/3)*100 ss_dev,
       cs_item_rev,
       cs_item_rev/((ss_item_rev+cs_item_rev+ws_item_rev)/3)*100 cs_dev,
       ws_item_rev,
       ws_item_rev/((ss_item_rev+cs_item_rev+ws_item_rev)/3)*100 ws_dev,
       (ss_item_rev+cs_item_rev+ws_item_rev)/3 average
FROM ws_items
straight_join cs_items ON cs_items.item_id = ws_items.item_id
straight_join ss_items ON ss_items.item_id = ws_items.item_id
WHERE ss_item_rev BETWEEN 0.9*cs_item_rev AND 1.1*cs_item_rev
  AND ss_item_rev BETWEEN 0.9*ws_item_rev AND 1.1*ws_item_rev
  AND cs_item_rev BETWEEN 0.9*ws_item_rev AND 1.1*ws_item_rev
ORDER BY item_id, ss_item_rev
LIMIT 100;