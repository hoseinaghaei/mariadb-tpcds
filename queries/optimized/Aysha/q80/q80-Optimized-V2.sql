select * from (
with ssr as (
  select s_store_id as store_id,
         sum(ss_ext_sales_price) as sales,
         sum(coalesce(sr_return_amt,0)) as returns,
         sum(ss_net_profit - coalesce(sr_net_loss,0)) as profit
  from store_sales
  join item      on i_item_sk = ss_item_sk and i_current_price > 50
  join promotion on p_promo_sk = ss_promo_sk and p_channel_tv = 'N'
  join store     on s_store_sk = ss_store_sk
  left join store_returns on sr_item_sk = ss_item_sk
                         and sr_ticket_number = ss_ticket_number
  where ss_sold_date_sk between
        (select min(d_date_sk) from date_dim
          where d_date between '1998-08-28' and '1998-08-28' + interval 30 day)
    and (select max(d_date_sk) from date_dim
          where d_date between '1998-08-28' and '1998-08-28' + interval 30 day)
  group by s_store_id),
csr as (
  select cp_catalog_page_id as catalog_page_id,
         sum(cs_ext_sales_price) as sales,
         sum(coalesce(cr_return_amount,0)) as returns,
         sum(cs_net_profit - coalesce(cr_net_loss,0)) as profit
  from catalog_sales
  join item         on i_item_sk = cs_item_sk and i_current_price > 50
  join promotion    on p_promo_sk = cs_promo_sk and p_channel_tv = 'N'
  join catalog_page on cp_catalog_page_sk = cs_catalog_page_sk
  left join catalog_returns on cr_item_sk = cs_item_sk
                           and cr_order_number = cs_order_number
  where cs_sold_date_sk between
        (select min(d_date_sk) from date_dim
          where d_date between '1998-08-28' and '1998-08-28' + interval 30 day)
    and (select max(d_date_sk) from date_dim
          where d_date between '1998-08-28' and '1998-08-28' + interval 30 day)
  group by cp_catalog_page_id),
wsr as (
  select web_site_id,
         sum(ws_ext_sales_price) as sales,
         sum(coalesce(wr_return_amt,0)) as returns,
         sum(ws_net_profit - coalesce(wr_net_loss,0)) as profit
  from web_sales
  join item      on i_item_sk = ws_item_sk and i_current_price > 50
  join promotion on p_promo_sk = ws_promo_sk and p_channel_tv = 'N'
  join web_site  on web_site_sk = ws_web_site_sk
  left join web_returns on wr_item_sk = ws_item_sk
                       and wr_order_number = ws_order_number
  where ws_sold_date_sk between
        (select min(d_date_sk) from date_dim
          where d_date between '1998-08-28' and '1998-08-28' + interval 30 day)
    and (select max(d_date_sk) from date_dim
          where d_date between '1998-08-28' and '1998-08-28' + interval 30 day)
  group by web_site_id)
select channel, id,
       sum(sales) as sales, sum(returns) as returns, sum(profit) as profit
from (
  select 'store channel' as channel, concat('store', store_id) as id,
         sales, returns, profit from ssr
  union all
  select 'catalog channel', concat('catalog_page', catalog_page_id),
         sales, returns, profit from csr
  union all
  select 'web channel', concat('web_site', web_site_id),
         sales, returns, profit from wsr
) x
group by channel, id with rollup
) tpcds_rollup
order by channel, id
limit 100;