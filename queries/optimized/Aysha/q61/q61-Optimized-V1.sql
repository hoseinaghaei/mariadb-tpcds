-- tHE SQL is the same, but new indexes added

-- Most expensive Table
create index idx_ss_q61 ON store_sales
  (ss_store_sk, ss_sold_date_sk, ss_item_sk, ss_customer_sk, 
ss_promo_sk, ss_ext_sales_price);

-- Make indexes on teh dimensiosna dn those attributes that are filterable
create index idx_store_gmt  ON store (s_gmt_offset);
create index idx_date_ym    ON date_dim (d_year, d_moy, d_date_sk);
create index idx_item_cat   ON item (i_category);
create index idx_ca_gmt     ON customer_address (ca_gmt_offset);

analyze format=json
select  promotions,total,cast(promotions as decimal(15,4))/cast(total as decimal(15,4))*100
from
  (select sum(ss_ext_sales_price) promotions
   from  store_sales
        ,store
        ,promotion
        ,date_dim
        ,customer
        ,customer_address 
        ,item
   where ss_sold_date_sk = d_date_sk
   and   ss_store_sk = s_store_sk
   and   ss_promo_sk = p_promo_sk
   and   ss_customer_sk= c_customer_sk
   and   ca_address_sk = c_current_addr_sk
   and   ss_item_sk = i_item_sk 
   and   ca_gmt_offset = -7
   and   i_category = 'Books'
   and   (p_channel_dmail = 'Y' or p_channel_email = 'Y' or p_channel_tv = 'Y')
   and   s_gmt_offset = -7
   and   d_year = 2000
   and   d_moy  = 12) promotional_sales,
  (select sum(ss_ext_sales_price) total
   from  store_sales
        ,store
        ,date_dim
        ,customer
        ,customer_address
        ,item
   where ss_sold_date_sk = d_date_sk
   and   ss_store_sk = s_store_sk
   and   ss_customer_sk= c_customer_sk
   and   ca_address_sk = c_current_addr_sk
   and   ss_item_sk = i_item_sk
   and   ca_gmt_offset = -7
   and   i_category = 'Books'
   and   s_gmt_offset = -7
   and   d_year = 2000
   and   d_moy  = 12) all_sales
order by promotions, total
limit 100;
