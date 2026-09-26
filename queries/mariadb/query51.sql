WITH web_v1 as (
select
  ws_item_sk item_sk, d_date,
  sum(sum(ws_sales_price))
      over (partition by ws_item_sk order by d_date rows between unbounded preceding and current row) cume_sales
from web_sales
    ,date_dim
where ws_sold_date_sk=d_date_sk
  and d_month_seq between 1176 and 1176+11
  and ws_item_sk is not NULL
group by ws_item_sk, d_date),
store_v1 as (
select
  ss_item_sk item_sk, d_date,
  sum(sum(ss_sales_price))
      over (partition by ss_item_sk order by d_date rows between unbounded preceding and current row) cume_sales
from store_sales
    ,date_dim
where ss_sold_date_sk=d_date_sk
  and d_month_seq between 1176 and 1176+11
  and ss_item_sk is not NULL
group by ss_item_sk, d_date)
 select  *
from (select item_sk
     ,d_date
     ,web_sales
     ,store_sales
     ,max(web_sales)
         over (partition by item_sk order by d_date rows between unbounded preceding and current row) web_cumulative
     ,max(store_sales)
         over (partition by item_sk order by d_date rows between unbounded preceding and current row) store_cumulative
     from (
           -- MariaDB has no FULL OUTER JOIN: emulated as
           -- (A LEFT JOIN B) UNION ALL (A RIGHT JOIN B WHERE A keys IS NULL).
           -- The anti-join filter on the second branch keeps only the B rows
           -- that found no A match, so UNION ALL adds no duplicates and
           -- legitimate duplicate rows are preserved.
           (select case when web.item_sk is not null then web.item_sk else store.item_sk end item_sk
                  ,case when web.d_date is not null then web.d_date else store.d_date end d_date
                  ,web.cume_sales web_sales
                  ,store.cume_sales store_sales
            from web_v1 web left outer join store_v1 store on (web.item_sk = store.item_sk
                                                           and web.d_date = store.d_date))
           union all
           (select case when web.item_sk is not null then web.item_sk else store.item_sk end item_sk
                  ,case when web.d_date is not null then web.d_date else store.d_date end d_date
                  ,web.cume_sales web_sales
                  ,store.cume_sales store_sales
            from web_v1 web right outer join store_v1 store on (web.item_sk = store.item_sk
                                                            and web.d_date = store.d_date)
            where web.item_sk is null
              and web.d_date is null)
          )x )y
where web_cumulative > store_cumulative
order by item_sk
        ,d_date
limit 100;
