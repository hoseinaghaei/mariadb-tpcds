-- query14
-- source: queries/optimized/Aysha/q14/Query-14-A/q14_A_Optimized.sql, queries/optimized/Aysha/q14/Query-14-B/Q14-B-Optimized.sql
-- correction: typo i_braknd_id -> i_brand_id (part B would not run at all)
-- correction: part B emitted 8 columns; TPC-DS requires 12 (the ty_/ly_ key columns are repeated per year) - expanded, and its ORDER BY updated to the new aliases
-- split materialisation OFF: measured -17.0s at SF=4

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');
SET SESSION optimizer_switch = 'split_materialized=off';

select * from (
  select channel, i_brand_id, i_class_id, i_category_id, sum(sales), sum(number_sales)
  from (
    select u.channel, u.i_brand_id, u.i_class_id, u.i_category_id, u.sales, u.number_sales
    from (
      select 'store' channel, i.i_brand_id, i.i_class_id, i.i_category_id,
             sum(ss_quantity*ss_list_price) sales, count(*) number_sales
      from date_dim d
      straight_join store_sales on ss_sold_date_sk = d.d_date_sk
      straight_join item i on i.i_item_sk = ss_item_sk
      where d.d_year = 2000 and d.d_moy = 11
      group by i.i_brand_id, i.i_class_id, i.i_category_id
      union all
      select 'catalog', i.i_brand_id, i.i_class_id, i.i_category_id,
             sum(cs_quantity*cs_list_price), count(*)
      from date_dim d
      straight_join catalog_sales on cs_sold_date_sk = d.d_date_sk
      straight_join item i on i.i_item_sk = cs_item_sk
      where d.d_year = 2000 and d.d_moy = 11
      group by i.i_brand_id, i.i_class_id, i.i_category_id
      union all
      select 'web', i.i_brand_id, i.i_class_id, i.i_category_id,
             sum(ws_quantity*ws_list_price), count(*)
      from date_dim d
      straight_join web_sales on ws_sold_date_sk = d.d_date_sk
      straight_join item i on i.i_item_sk = ws_item_sk
      where d.d_year = 2000 and d.d_moy = 11
      group by i.i_brand_id, i.i_class_id, i.i_category_id
    ) u
    straight_join (
      select i.i_brand_id, i.i_class_id, i.i_category_id
      from item i,
           (select min(d_date_sk) lo, max(d_date_sk) hi from date_dim
            where d_year between 1998 and 1998 + 2) dr
      where exists (select 1 from store_sales
                    where ss_item_sk = i.i_item_sk
                      and ss_sold_date_sk between dr.lo and dr.hi)
      intersect
      select i.i_brand_id, i.i_class_id, i.i_category_id
      from item i,
           (select min(d_date_sk) lo, max(d_date_sk) hi from date_dim
            where d_year between 1998 and 1998 + 2) dr
      where exists (select 1 from catalog_sales
                    where cs_item_sk = i.i_item_sk
                      and cs_sold_date_sk between dr.lo and dr.hi)
      intersect
      select i.i_brand_id, i.i_class_id, i.i_category_id
      from item i,
           (select min(d_date_sk) lo, max(d_date_sk) hi from date_dim
            where d_year between 1998 and 1998 + 2) dr
      where exists (select 1 from web_sales
                    where ws_item_sk = i.i_item_sk
                      and ws_sold_date_sk between dr.lo and dr.hi)
    ) ct on  u.i_brand_id    = ct.i_brand_id
         and u.i_class_id    = ct.i_class_id
         and u.i_category_id = ct.i_category_id
    straight_join (
      select (s.sm + c.sm + w.sm) / (s.cn + c.cn + w.cn) average_sales
      from (select sum(ss_quantity*ss_list_price) sm, count(ss_quantity*ss_list_price) cn
            from store_sales,
                 (select min(d_date_sk) lo, max(d_date_sk) hi from date_dim
                  where d_year between 1998 and 1998 + 2) dr
            where ss_sold_date_sk between dr.lo and dr.hi) s,
           (select sum(cs_quantity*cs_list_price) sm, count(cs_quantity*cs_list_price) cn
            from catalog_sales,
                 (select min(d_date_sk) lo, max(d_date_sk) hi from date_dim
                  where d_year between 1998 and 1998 + 2) dr
            where cs_sold_date_sk between dr.lo and dr.hi) c,
           (select sum(ws_quantity*ws_list_price) sm, count(ws_quantity*ws_list_price) cn
            from web_sales,
                 (select min(d_date_sk) lo, max(d_date_sk) hi from date_dim
                  where d_year between 1998 and 1998 + 2) dr
            where ws_sold_date_sk between dr.lo and dr.hi) w
    ) av
    where u.sales > av.average_sales
  ) y
  group by channel, i_brand_id, i_class_id, i_category_id with rollup
) tpcds_rollup
order by channel, i_brand_id, i_class_id, i_category_id
limit 100;

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
    select item.i_brand_id,
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
select 'store' as ty_channel,
       weekly_sales.i_brand_id    as ty_brand,
       weekly_sales.i_class_id    as ty_class,
       weekly_sales.i_category_id as ty_category,
       weekly_sales.this_year_sales as ty_sales,
       weekly_sales.this_year_number_of_sales as ty_number_sales,
       'store' as ly_channel,
       weekly_sales.i_brand_id    as ly_brand,
       weekly_sales.i_class_id    as ly_class,
       weekly_sales.i_category_id as ly_category,
       weekly_sales.last_year_sales as ly_sales,
       weekly_sales.last_year_number_of_sales as ly_number_sales
from weekly_sales
straight_join groups_sold_in_all_channels as common_groups
       on  weekly_sales.i_brand_id    = common_groups.i_brand_id
       and weekly_sales.i_class_id    = common_groups.i_class_id
       and weekly_sales.i_category_id = common_groups.i_category_id
straight_join average_sale
where weekly_sales.this_year_sales > average_sale.average_sale_value
  and weekly_sales.last_year_sales > average_sale.average_sale_value
order by ty_brand, ty_class, ty_category
limit 100;
