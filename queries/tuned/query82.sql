-- query82
-- source: queries/optimized/q82-sf4/query82_v1_exists.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

select  i_item_id
       ,i_item_desc
       ,i_current_price
 from item
 where i_current_price between 33 and 33+30
 and i_manufact_id in (306,845,203,671)
 and exists (select 1
             from inventory
             where inv_item_sk = i_item_sk
               and inv_date_sk between 2451559 and 2451619
               and inv_quantity_on_hand between 100 and 500)
 and exists (select 1
             from store_sales
             where ss_item_sk = i_item_sk)
 group by i_item_id,i_item_desc,i_current_price
 order by i_item_id
 limit 100;
