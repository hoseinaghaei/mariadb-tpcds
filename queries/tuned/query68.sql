-- query68
-- source: queries/optimized/q68-sf4/query68_v1_datefirst.sql
-- split materialisation at default: -1.9s is inside this host's noise

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

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
