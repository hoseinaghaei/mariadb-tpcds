-- Index added and mycustomers nnow first fikters sales and catalogeus seperately (time and item) and later joins(UNION ALL)

create index idx_ws_date_item_cust on web_sales (ws_sold_date_sk, ws_item_sk, ws_bill_customer_sk);
create index idx_cs_date_item_cust on catalog_sales (cs_sold_date_sk, cs_item_sk, cs_bill_customer_sk);
create index idx_ss_cust_date_cover on store_sales (ss_customer_sk, ss_sold_date_sk, ss_ext_sales_price);

-- DROP INDEX idx_ws_date_item_cust ON web_sales;
-- DROP INDEX idx_cs_date_item_cust ON catalog_sales;
-- DROP INDEX idx_ss_cust_date_cover ON store_sales;


with my_customers as (
 select distinct c_customer_sk
        , c_current_addr_sk
 from  
 (
        select cs_bill_customer_sk as customer_sk
        from   catalog_sales, date_dim, item
        where  cs_sold_date_sk = d_date_sk
          and  cs_item_sk = i_item_sk
          and  d_year = 2000 and d_moy = 7
          and  i_category = 'Women' and i_class = 'swimwear'
        union all
        select ws_bill_customer_sk
        from   web_sales, date_dim, item
        where  ws_sold_date_sk = d_date_sk
          and  ws_item_sk = i_item_sk
          and  d_year = 2000 and d_moy = 7
          and  i_category = 'Women' and i_class = 'swimwear'
       ) cs_or_ws_sales,
       customer
  where c_customer_sk = cs_or_ws_sales.customer_sk
)
 , my_revenue as (
 select c_customer_sk,
        sum(ss_ext_sales_price) as revenue
 from   my_customers,
        store_sales,
        customer_address,
        store,
        date_dim
 where  c_current_addr_sk = ca_address_sk
        and ca_county = s_county
        and ca_state = s_state
        and ss_sold_date_sk = d_date_sk
        and c_customer_sk = ss_customer_sk
        and d_month_seq between (select distinct d_month_seq+1
                                 from   date_dim where d_year = 2000 and d_moy = 7)
                           and  (select distinct d_month_seq+3
                                 from   date_dim where d_year = 2000 and d_moy = 7)
 group by c_customer_sk
 )
 , segments as
 (select cast((revenue/50) as int) as segment
  from   my_revenue
 )
  select  segment, count(*) as num_customers, segment*50 as segment_base
 from segments
 group by segment
 order by segment, num_customers
 limit 100;
