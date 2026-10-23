-- Uses the new Indexes, Changed order of joins,store sales is only read once
select promotions, total,
       cast(promotions as decimal(15,4)) / cast(total as decimal(15,4)) * 100
from (
  select straight_join
    sum(case when p.p_channel_dmail = 'Y' or p.p_channel_email = 'Y' or p.p_channel_tv = 'Y'
             then ss.ss_ext_sales_price end) as promotions,
    sum(ss.ss_ext_sales_price) as total
  from store s
  join date_dim d          on d.d_year = 2000 and d.d_moy = 12
  join store_sales ss      on ss.ss_store_sk = s.s_store_sk
                          and ss.ss_sold_date_sk = d.d_date_sk
  join item i              on i.i_item_sk = ss.ss_item_sk
  join customer c          on c.c_customer_sk = ss.ss_customer_sk
  join customer_address ca on ca.ca_address_sk = c.c_current_addr_sk
  left join promotion p    on p.p_promo_sk = ss.ss_promo_sk
  where s.s_gmt_offset = -7
    and i.i_category = 'Books'
    and ca.ca_gmt_offset = -7
) x;