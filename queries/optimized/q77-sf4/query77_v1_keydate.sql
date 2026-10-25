-- q77 v1 -- replace six date_dim joins with one range each.
--
-- q77 builds six CTEs (store/catalog/web sales and returns), and every one of
-- them joins date_dim purely to apply the same 31-day window:
--
--   d_date between cast('1998-08-28' as date)
--             and (cast('1998-08-28' as date) + interval 30 day)
--
-- Those 31 days are the contiguous key range d_date_sk 2451054..2451084
-- (31 rows, span 31), and date_dim is dense over 2415022..2488070, so a key
-- inside the range always exists.  The join can therefore be replaced by a
-- BETWEEN on each fact table's own foreign key.  d_date is not read anywhere
-- else in the query -- only the window is wanted -- so nothing else depends
-- on date_dim being present.
--
-- What this buys: the original has to resolve the 31 qualifying date_dim rows
-- and then probe the fact table once per day, six times over.  One range
-- predicate is a single contiguous scan of the fact table's FK index instead,
-- and removes the dimension from the join order altogether.  BETWEEN also
-- excludes NULL foreign keys, which is what the inner joins did.
--
-- The store and web_page joins stay.  They supply the grouping key that
-- becomes `id` in the output, and unlike date_dim their surrogate keys were
-- not checked for density, so dropping them could admit fact rows the
-- original rejected.
--
-- Not fixable from here: the plan reaches store_sales through
-- idx_ss_date_cust (ss_sold_date_sk, ss_customer_sk), which does not carry
-- ss_store_sk, ss_ext_sales_price or ss_net_profit, so every qualifying row
-- still costs a base-table fetch.  A covering index on
-- (ss_sold_date_sk, ss_store_sk, ss_net_profit, ss_ext_sales_price) would
-- make the ss CTE index-only, but adding indexes is out of scope here -- and
-- the last time six were added to this schema, 16K/SF=1 got 40% slower.

select * from (
with ss as
 (select s_store_sk,
         sum(ss_ext_sales_price) as sales,
         sum(ss_net_profit) as profit
 from store_sales,
      store
 where ss_sold_date_sk between 2451054 and 2451084
       and ss_store_sk = s_store_sk
 group by s_store_sk)
 ,
 sr as
 (select s_store_sk,
         sum(sr_return_amt) as returns,
         sum(sr_net_loss) as profit_loss
 from store_returns,
      store
 where sr_returned_date_sk between 2451054 and 2451084
       and sr_store_sk = s_store_sk
 group by s_store_sk),
 cs as
 (select cs_call_center_sk,
        sum(cs_ext_sales_price) as sales,
        sum(cs_net_profit) as profit
 from catalog_sales
 where cs_sold_date_sk between 2451054 and 2451084
 group by cs_call_center_sk
 ),
 cr as
 (select cr_call_center_sk,
         sum(cr_return_amount) as returns,
         sum(cr_net_loss) as profit_loss
 from catalog_returns
 where cr_returned_date_sk between 2451054 and 2451084
 group by cr_call_center_sk
 ),
 ws as
 ( select wp_web_page_sk,
        sum(ws_ext_sales_price) as sales,
        sum(ws_net_profit) as profit
 from web_sales,
      web_page
 where ws_sold_date_sk between 2451054 and 2451084
       and ws_web_page_sk = wp_web_page_sk
 group by wp_web_page_sk),
 wr as
 (select wp_web_page_sk,
        sum(wr_return_amt) as returns,
        sum(wr_net_loss) as profit_loss
 from web_returns,
      web_page
 where wr_returned_date_sk between 2451054 and 2451084
       and wr_web_page_sk = wp_web_page_sk
 group by wp_web_page_sk)
  select  channel
        , id
        , sum(sales) as sales
        , sum(returns) as returns
        , sum(profit) as profit
 from
 (select 'store channel' as channel
        , ss.s_store_sk as id
        , sales
        , coalesce(returns, 0) as returns
        , (profit - coalesce(profit_loss,0)) as profit
 from   ss left join sr
        on  ss.s_store_sk = sr.s_store_sk
 union all
 select 'catalog channel' as channel
        , cs_call_center_sk as id
        , sales
        , returns
        , (profit - profit_loss) as profit
 from  cs
       , cr
 union all
 select 'web channel' as channel
        , ws.wp_web_page_sk as id
        , sales
        , coalesce(returns, 0) returns
        , (profit - coalesce(profit_loss,0)) as profit
 from   ws left join wr
        on  ws.wp_web_page_sk = wr.wp_web_page_sk
 ) x
 group by channel, id with rollup
) tpcds_rollup
order by channel
         ,id
 limit 100;
