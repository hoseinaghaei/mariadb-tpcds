with date_window as (
    select min(d_date_sk) as first_date_sk,
           max(d_date_sk) as last_date_sk
    from date_dim
    where d_year between 1998 and 2000
),
target_weeks as (
    select max(case when d_year = 1999 then d_week_seq end) as this_year_week,
           max(case when d_year = 1998 then d_week_seq end) as last_year_week
    from date_dim
    where d_year in (1998, 1999)
      and d_moy = 12
      and d_dom = 15
),
weekly_sales as (
    select item.i_braknd_id,
           item.i_class_id,
           item.i_category_id,
           sum(case when calendar.d_week_seq = target_weeks.this_year_week
                    then ss_quantity * ss_list_price end)   as this_year_sales,
           count(case when calendar.d_week_seq = target_weeks.this_year_week
                      then 1 end)                           as this_year_number_of_sales,
           sum(case when calendar.d_week_seq = target_weeks.last_year_week
                    then ss_quantity * ss_list_price end)   as last_year_sales,
           count(case when calendar.d_week_seq = target_weeks.last_year_week
                      then 1 end)                           as last_year_number_of_sales
    from target_weeks
    straight_join date_dim as calendar
           on calendar.d_week_seq in (target_weeks.this_year_week, target_weeks.last_year_week)
    straight_join store_sales
           on ss_sold_date_sk = calendar.d_date_sk
    straight_join item
           on item.i_item_sk = ss_item_sk
    group by item.i_brand_id, item.i_class_id, item.i_category_id
),
groups_sold_in_all_channels as (
    select item.i_brand_id, item.i_class_id, item.i_category_id
    from item, date_window
    where exists (select 1 from store_sales
                  where ss_item_sk = item.i_item_sk
                    and ss_sold_date_sk between date_window.first_date_sk
                                            and date_window.last_date_sk)
    intersect
    select item.i_brand_id, item.i_class_id, item.i_category_id
    from item, date_window
    where exists (select 1 from catalog_sales
                  where cs_item_sk = item.i_item_sk
                    and cs_sold_date_sk between date_window.first_date_sk
                                            and date_window.last_date_sk)
    intersect
    select item.i_brand_id, item.i_class_id, item.i_category_id
    from item, date_window
    where exists (select 1 from web_sales
                  where ws_item_sk = item.i_item_sk
                    and ws_sold_date_sk between date_window.first_date_sk
                                            and date_window.last_date_sk)
),
average_sale as (
    select (store_totals.total_value + catalog_totals.total_value + web_totals.total_value)
         / (store_totals.sale_count  + catalog_totals.sale_count  + web_totals.sale_count)
           as average_sale_value
    from (select sum(ss_quantity * ss_list_price)   as total_value,
                 count(ss_quantity * ss_list_price) as sale_count
          from store_sales, date_window
          where ss_sold_date_sk between date_window.first_date_sk
                                    and date_window.last_date_sk) as store_totals,
         (select sum(cs_quantity * cs_list_price)   as total_value,
                 count(cs_quantity * cs_list_price) as sale_count
          from catalog_sales, date_window
          where cs_sold_date_sk between date_window.first_date_sk
                                    and date_window.last_date_sk) as catalog_totals,
         (select sum(ws_quantity * ws_list_price)   as total_value,
                 count(ws_quantity * ws_list_price) as sale_count
          from web_sales, date_window
          where ws_sold_date_sk between date_window.first_date_sk
                                    and date_window.last_date_sk) as web_totals
)
select 'store' as channel,
       weekly_sales.i_brand_id    as brand_id,
       weekly_sales.i_class_id    as class_id,
       weekly_sales.i_category_id as category_id,
       weekly_sales.this_year_sales,
       weekly_sales.this_year_number_of_sales,
       weekly_sales.last_year_sales,
       weekly_sales.last_year_number_of_sales
from weekly_sales
straight_join groups_sold_in_all_channels as common_groups
       on  weekly_sales.i_brand_id    = common_groups.i_brand_id
       and weekly_sales.i_class_id    = common_groups.i_class_id
       and weekly_sales.i_category_id = common_groups.i_category_id
straight_join average_sale
where weekly_sales.this_year_sales > average_sale.average_sale_value
  and weekly_sales.last_year_sales > average_sale.average_sale_value
order by brand_id, class_id, category_id
limit 100;