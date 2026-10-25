-- q68 v1: drive the join from date_dim instead of store_sales.
--
-- ANALYZE FORMAT=JSON on the original at SF=4:
--
--   20,803 ms total
--   FULL SCAN store_sales   11,519,024 rows
--   FULL SCAN customer         233,000 rows
--   customer_address probed    233,000 times
--
-- store_sales is read whole, yet the query needs almost none of it.  The
-- date predicate is d_dom BETWEEN 1 AND 2 across three years -- about 18
-- days of roughly 1,095, or 1.6%.  Resolving those dates first and probing
-- idx_ss_sold_date_sk reads a fraction of the rows.
--
-- STRAIGHT_JOIN fixes the order: date_dim, then store_sales by date key,
-- then the small dimensions.  date_dim itself is ~73k rows, so scanning it
-- to find the 18 matching days costs nothing next to 11.5M fact rows.
--
-- Nothing about the result changes: same tables, same predicates, same
-- grouping.  Only the order in which they are visited.

select  c_last_name
       ,c_first_name
       ,ca_city
       ,bought_city
       ,ss_ticket_number
       ,extended_price
       ,extended_tax
       ,list_price
 from (select straight_join
              ss_ticket_number
             ,ss_customer_sk
             ,ca_city bought_city
             ,sum(ss_ext_sales_price) extended_price
             ,sum(ss_ext_list_price) list_price
             ,sum(ss_ext_tax) extended_tax
       from date_dim
       straight_join store_sales
              on store_sales.ss_sold_date_sk = date_dim.d_date_sk
       straight_join store
              on store_sales.ss_store_sk = store.s_store_sk
       straight_join household_demographics
              on store_sales.ss_hdemo_sk = household_demographics.hd_demo_sk
       straight_join customer_address
              on store_sales.ss_addr_sk = customer_address.ca_address_sk
       where date_dim.d_dom between 1 and 2
        and (household_demographics.hd_dep_count = 5 or
             household_demographics.hd_vehicle_count= 0)
        and date_dim.d_year in (1999,1999+1,1999+2)
        and store.s_city in ('Fairview','Midway')
       group by ss_ticket_number
               ,ss_customer_sk
               ,ss_addr_sk,ca_city) dn
      ,customer
      ,customer_address current_addr
 where ss_customer_sk = c_customer_sk
   and customer.c_current_addr_sk = current_addr.ca_address_sk
   and current_addr.ca_city <> bought_city
 order by c_last_name
         ,ss_ticket_number
 limit 100;
