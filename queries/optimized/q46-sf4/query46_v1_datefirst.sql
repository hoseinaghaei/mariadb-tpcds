-- q46 v1: drive the join from date_dim instead of store_sales.
--
-- Structurally the same query as q68 -- the same five tables joined the same
-- way -- and ANALYZE FORMAT=JSON shows the same defect at SF=4:
--
--   12,537 ms total
--   FULL SCAN store_sales   11,519,024 rows
--   FULL SCAN customer         233,000 rows
--   customer_address probed    233,000 times
--
-- The same fix applies: STRAIGHT_JOIN from date_dim so the fact table is
-- reached through idx_ss_sold_date_sk rather than scanned.
--
-- One honest caveat.  q68's date predicate (d_dom BETWEEN 1 AND 2 over three
-- years) selects about 1.6% of dates, and the rewrite is worth 4.9x there.
-- q46 filters d_dow IN (6,0) -- weekends -- which is about 28% of dates, so
-- the same change has far less to save and may not help at all.  It is
-- measured, not assumed.

select  c_last_name
       ,c_first_name
       ,ca_city
       ,bought_city
       ,ss_ticket_number
       ,amt,profit 
 from
   (select straight_join ss_ticket_number
          ,ss_customer_sk
          ,ca_city bought_city
          ,sum(ss_coupon_amt) amt
          ,sum(ss_net_profit) profit
    from date_dim
    straight_join store_sales
           on store_sales.ss_sold_date_sk = date_dim.d_date_sk
    straight_join store
           on store_sales.ss_store_sk = store.s_store_sk
    straight_join household_demographics
           on store_sales.ss_hdemo_sk = household_demographics.hd_demo_sk
    straight_join customer_address
           on store_sales.ss_addr_sk = customer_address.ca_address_sk
    where (household_demographics.hd_dep_count = 5 or
         household_demographics.hd_vehicle_count= 0)
    and date_dim.d_dow in (6,0)
    and date_dim.d_year in (1999,1999+1,1999+2) 
    and store.s_city in ('Fairview','Midway','Fairview','Fairview','Fairview') 
    group by ss_ticket_number,ss_customer_sk,ss_addr_sk,ca_city) dn,customer,customer_address current_addr
    where ss_customer_sk = c_customer_sk
      and customer.c_current_addr_sk = current_addr.ca_address_sk
      and current_addr.ca_city <> bought_city
  order by c_last_name
          ,c_first_name
          ,ca_city
          ,bought_city
          ,ss_ticket_number
  limit 100;
