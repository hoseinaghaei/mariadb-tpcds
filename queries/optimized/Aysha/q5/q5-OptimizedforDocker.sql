/*
CREATE INDEX idx_sr_date ON store_returns
    (sr_returned_date_sk, sr_store_sk, sr_return_amt, sr_net_loss);

CREATE INDEX idx_cr_date ON catalog_returns
    (cr_returned_date_sk, cr_catalog_page_sk, cr_return_amount, cr_net_loss);

CREATE INDEX idx_wr_date ON web_returns
    (wr_returned_date_sk, wr_item_sk, wr_order_number, wr_return_amt, wr_net_loss);
*/


select * from (
with
/*===================== STORE CHANNEL =====================*/
ssr as (
  select s_store_id,
         sum(sales_price) as sales,
         sum(profit)      as profit,
         sum(return_amt)  as returns,
         sum(net_loss)    as profit_loss
  from (
    /* group by store_sk first, so the store lookup runs only a few times*/
    select store_sk,
           sum(sales_price) as sales_price,
           sum(profit)      as profit,
           sum(return_amt)  as return_amt,
           sum(net_loss)    as net_loss
    from (
      -- A: date_dim + store_sales
      select ss_store_sk as store_sk,
             ss_ext_sales_price as sales_price,
             ss_net_profit      as profit,
             cast(0 as decimal(7,2)) as return_amt,
             cast(0 as decimal(7,2)) as net_loss
      from date_dim d
      straight_join store_sales on ss_sold_date_sk = d.d_date_sk
      where d.d_date between '1998-08-28' and '1998-09-11'
      union all
      /* B: date_dim + store_returns*/
      select sr_store_sk as store_sk,
             cast(0 as decimal(7,2)) as sales_price,
             cast(0 as decimal(7,2)) as profit,
             sr_return_amt as return_amt,
             sr_net_loss   as net_loss
      from date_dim d
      straight_join store_returns on sr_returned_date_sk = d.d_date_sk
      where d.d_date between '1998-08-28' and '1998-09-11'
    ) ab
    group by store_sk
  ) g
  join store on g.store_sk = s_store_sk
  group by s_store_id
),

/* ===================== CATALOG CHANNEL =====================*/
csr as (
  select cp_catalog_page_id,
         sum(sales_price) as sales,
         sum(profit)      as profit,
         sum(return_amt)  as returns,
         sum(net_loss)    as profit_loss
  from (
    select page_sk,
           sum(sales_price) as sales_price,
           sum(profit)      as profit,
           sum(return_amt)  as return_amt,
           sum(net_loss)    as net_loss
    from (
      -- A: date_dim + catalog_sales
      select cs_catalog_page_sk as page_sk,
             cs_ext_sales_price as sales_price,
             cs_net_profit      as profit,
             cast(0 as decimal(7,2)) as return_amt,
             cast(0 as decimal(7,2)) as net_loss
      from date_dim d
      straight_join catalog_sales on cs_sold_date_sk = d.d_date_sk
      where d.d_date between '1998-08-28' and '1998-09-11'
      union all
      -- B: date_dim + catalog_returns
      select cr_catalog_page_sk as page_sk,
             cast(0 as decimal(7,2)) as sales_price,
             cast(0 as decimal(7,2)) as profit,
             cr_return_amount as return_amt,
             cr_net_loss      as net_loss
      from date_dim d
      straight_join catalog_returns on cr_returned_date_sk = d.d_date_sk
      where d.d_date between '1998-08-28' and '1998-09-11'
    ) ab
    group by page_sk
  ) g
  join catalog_page on g.page_sk = cp_catalog_page_sk
  group by cp_catalog_page_id
),

/* ===================== WEB CHANNEL =====================*/
wsr as (
  select web_site_id,
         sum(sales_price) as sales,
         sum(profit)      as profit,
         sum(return_amt)  as returns,
         sum(net_loss)    as profit_loss
  from (
    select site_sk,
           sum(sales_price) as sales_price,
           sum(profit)      as profit,
           sum(return_amt)  as return_amt,
           sum(net_loss)    as net_loss
    from (
      /* A: date_dim + web_sales*/
      select ws_web_site_sk as site_sk,
             ws_ext_sales_price as sales_price,
             ws_net_profit      as profit,
             cast(0 as decimal(7,2)) as return_amt,
             cast(0 as decimal(7,2)) as net_loss
      from date_dim d
      straight_join web_sales on ws_sold_date_sk = d.d_date_sk
      where d.d_date between '1998-08-28' and '1998-09-11'
      union all
     /*B: date_dim + web_returns, then find the site through web_sales
         (inner join: returns with no matching sale have no site and
           were dropped by the old query anyway, so results are identical)*/
      select ws_web_site_sk as site_sk,
             cast(0 as decimal(7,2)) as sales_price,
             cast(0 as decimal(7,2)) as profit,
             wr_return_amt as return_amt,
             wr_net_loss   as net_loss
      from date_dim d
      straight_join web_returns on wr_returned_date_sk = d.d_date_sk
      straight_join web_sales   on ws_item_sk = wr_item_sk
                               and ws_order_number = wr_order_number
      where d.d_date between '1998-08-28' and '1998-09-11'
    ) ab
    group by site_sk
  ) g
  join web_site on g.site_sk = web_site_sk
  group by web_site_id
)

/* ===================== FINAL: 3 channels + rollup =====================*/
select channel,
       id,
       sum(sales)   as sales,
       sum(returns) as returns,
       sum(profit)  as profit
from (
  select 'store channel' as channel,
         concat('store', s_store_id) as id,
         sales, returns, (profit - profit_loss) as profit
  from ssr
  union all
  select 'catalog channel' as channel,
         concat('catalog_page', cp_catalog_page_id) as id,
         sales, returns, (profit - profit_loss) as profit
  from csr
  union all
  select 'web channel' as channel,
         concat('web_site', web_site_id) as id,
         sales, returns, (profit - profit_loss) as profit
  from wsr
) x
group by channel, id with rollup
) tpcds_rollup
order by channel, id
limit 100;