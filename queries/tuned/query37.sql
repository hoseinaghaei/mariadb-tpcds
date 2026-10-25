-- query37
-- source: queries/optimized/Nafiz/tier4/q37/query37_BEST.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

select i_item_id, i_item_desc, i_current_price
from item, inventory, date_dim
where i_current_price between 25 and 25 + 30
  and inv_item_sk = i_item_sk
  and inv_date_sk between 2452340 and 2452400
  and d_date_sk = inv_date_sk
  and d_date between cast('2002-03-06' as date)
                 and (cast('2002-03-06' as date) + interval 60 day)
  and i_manufact_id in (677,739,684,867)
  and inv_quantity_on_hand between 100 and 500
  and exists (select 1 from catalog_sales where cs_item_sk = i_item_sk)
group by i_item_id, i_item_desc, i_current_price
order by i_item_id
limit 100;
