-- TPC-DS Query 15: two-branch rewrite

-- Indexes used:
-- create index idx_cs_cust_date_price on catalog_sales (cs_bill_customer_sk, cs_sold_date_sk, cs_sales_price);
-- create index idx_c_addr on customer (c_current_addr_sk);
-- create index idx_cs_price_date_cust on catalog_sales (cs_sales_price, cs_sold_date_sk, cs_bill_customer_sk);

select ca_zip, sum(zip_total) as sum_sales
from (
  -- Branch 1: address conditions are true (any price)
  select straight_join ca_zip, sum(cs_sales_price) as zip_total
  from customer_address
       join customer on c_current_addr_sk = ca_address_sk
       join catalog_sales on cs_bill_customer_sk = c_customer_sk
  where (substr(ca_zip,1,5) in ('85669','86197','88274','83405','86475',
                                '85392','85460','80348','81792')
         or ca_state in ('CA','WA','GA'))
    and cs_sold_date_sk between (select min(d_date_sk) from date_dim where d_year = 2001 and d_qoy = 1)
                            and (select max(d_date_sk) from date_dim where d_year = 2001 and d_qoy = 1)
  group by ca_zip

  union all

  -- Branch 2: price over 500, address conditions NOT true
  select straight_join ca_zip, sum(cs_sales_price)
  from catalog_sales
       join customer on c_customer_sk = cs_bill_customer_sk
       join customer_address on ca_address_sk = c_current_addr_sk
  where cs_sales_price > 500
    and cs_sold_date_sk between (select min(d_date_sk) from date_dim where d_year = 2001 and d_qoy = 1)
                            and (select max(d_date_sk) from date_dim where d_year = 2001 and d_qoy = 1)
    and (substr(ca_zip,1,5) in ('85669','86197','88274','83405','86475',
                                '85392','85460','80348','81792')
         or ca_state in ('CA','WA','GA')) is not true
) t
group by ca_zip
order by ca_zip
limit 100;