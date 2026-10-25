-- query22
-- source: queries/optimized/q22/query22_BEST.sql
-- split materialisation at default: -1.3s is inside this host's noise

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

select *
from (select
          i_product_name
           , i_brand
           , i_class
           , i_category
           , avg(inv_quantity_on_hand) qoh
      from inventory
         , item
      where inv_item_sk = i_item_sk
        and inv_date_sk between (select min(d_date_sk) from date_dim
                                 where d_month_seq between 1176 and 1176 + 11)
                            and (select max(d_date_sk) from date_dim
                                 where d_month_seq between 1176 and 1176 + 11)
      group by i_product_name
             , i_brand
             , i_class
             , i_category
      with rollup) tpcds_rollup
order by qoh, i_product_name, i_brand, i_class, i_category
limit 100;
