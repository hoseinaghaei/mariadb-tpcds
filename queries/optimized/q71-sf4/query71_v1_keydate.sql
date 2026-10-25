-- q71 v1 -- three date_dim joins become three ranges.
--
-- The union inside q71 has one branch per channel, and each one joins
-- date_dim only to apply `d_moy = 11 and d_year = 2001`.  Those 30 days are
-- the contiguous key range d_date_sk 2452215..2452244 (30 rows, span 30), and
-- date_dim is dense over 2415022..2488070, so each join becomes a BETWEEN on
-- the branch's own foreign key.
--
-- Nothing downstream reads a date_dim column: the branches project only
-- ext_price, the date key, the item key and the time key, and the outer query
-- groups by brand and by t_hour/t_minute from time_dim.  So removing
-- date_dim removes a per-row probe from all three branches and lets each
-- fact table be driven by one contiguous scan of its FK index.
--
-- `sold_date_sk` stays in the projection even though nothing consumes it,
-- because the original projects it and dropping a column from a UNION ALL
-- branch would change the shape of tmp.  It costs nothing to carry.
--
-- The item and time_dim joins are untouched.  item is reached by a full scan
-- of 45,135 rows to apply i_manager_id = 1; there is no index on
-- i_manager_id, and adding one is out of scope -- but item is small and
-- resident, and the scan happens once, not once per fact row.

select i_brand_id brand_id, i_brand brand,t_hour,t_minute,
 	sum(ext_price) ext_price
 from item, (select ws_ext_sales_price as ext_price,
                        ws_sold_date_sk as sold_date_sk,
                        ws_item_sk as sold_item_sk,
                        ws_sold_time_sk as time_sk
                 from web_sales
                 where ws_sold_date_sk between 2452215 and 2452244
                 union all
                 select cs_ext_sales_price as ext_price,
                        cs_sold_date_sk as sold_date_sk,
                        cs_item_sk as sold_item_sk,
                        cs_sold_time_sk as time_sk
                 from catalog_sales
                 where cs_sold_date_sk between 2452215 and 2452244
                 union all
                 select ss_ext_sales_price as ext_price,
                        ss_sold_date_sk as sold_date_sk,
                        ss_item_sk as sold_item_sk,
                        ss_sold_time_sk as time_sk
                 from store_sales
                 where ss_sold_date_sk between 2452215 and 2452244
                 ) tmp,time_dim
 where
   sold_item_sk = i_item_sk
   and i_manager_id=1
   and time_sk = t_time_sk
   and (t_meal_time = 'breakfast' or t_meal_time = 'dinner')
 group by i_brand, i_brand_id,t_hour,t_minute
 order by ext_price desc, i_brand_id
 ;
