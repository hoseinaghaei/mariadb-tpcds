-- query22: disabling split materialisation measured -1.3s, inside this host's run-to-run noise,
-- so it is left at the default.

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

select * from (
select  i_product_name
             ,i_brand
             ,i_class
             ,i_category
             ,avg(inv_quantity_on_hand) qoh
       from inventory
           ,date_dim
           ,item
       where inv_date_sk=d_date_sk
              and inv_item_sk=i_item_sk
              and d_month_seq between 1176 and 1176 + 11
       group by i_product_name
                       ,i_brand
                       ,i_class
                       ,i_category with rollup
) tpcds_rollup
order by qoh, i_product_name, i_brand, i_class, i_category
limit 100;
