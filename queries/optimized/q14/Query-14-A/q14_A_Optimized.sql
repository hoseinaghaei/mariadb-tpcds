-- SET SESSION join_buffer_size = 268435456;
-- SET SESSION tmp_table_size = 536870912;
-- SET SESSION max_heap_table_size = 536870912;
-- ANALYZE FORMAT=JSON
explain
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