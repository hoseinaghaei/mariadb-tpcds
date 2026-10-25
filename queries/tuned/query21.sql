-- query21
-- source: queries/optimized/Aysha/q21/query21_optimized.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

SET SESSION optimizer_switch = 'derived_merge=off';
select  *
 from(select straight_join
             w_warehouse_name
            ,i_item_id
            ,sum(case when (cast(d_date as date) < cast ('1998-06-18' as date))
                      then inv_quantity_on_hand
                      else 0 end) as inv_before
            ,sum(case when (cast(d_date as date) >= cast ('1998-06-18' as date))
                      then inv_quantity_on_hand
                      else 0 end) as inv_after
   from (select d_date_sk, d_date
         from date_dim
         where d_date between (cast ('1998-06-18' as date) - interval 30 day)
                          and (cast ('1998-06-18' as date) + interval 30 day)) fd
   join inventory
        on inv_date_sk = fd.d_date_sk
   join (select i_item_sk, i_item_id
         from item
         where i_current_price between 0.99 and 1.49) fi
        on fi.i_item_sk = inventory.inv_item_sk
   join warehouse
        on inventory.inv_warehouse_sk = w_warehouse_sk
   group by w_warehouse_name, i_item_id) x
 where (case when inv_before > 0
             then inv_after / inv_before
             else null
             end) between 2.0/3.0 and 3.0/2.0
 order by w_warehouse_name
         ,i_item_id
 limit 100;
