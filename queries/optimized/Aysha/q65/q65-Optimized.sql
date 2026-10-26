-- the new index makes the old one redundant (same first columns), so replace it to save storage
drop index idx_ss_date_store_item on store_sales;
create index idx_ss_date_store_item_price
  on store_sales (ss_sold_date_sk, ss_store_sk, ss_item_sk, ss_sales_price);


set session sort_buffer_size    = 64*1024*1024;
set session tmp_table_size      = 512*1024*1024;
set session max_heap_table_size = 512*1024*1024;


analyze format=json
select s_store_name, i_item_desc, lo.revenue,
       i_current_price, i_wholesale_cost, i_brand
from (
    select straight_join
           ss_store_sk, ss_item_sk,
           sum(ss_sales_price) as revenue,
           avg(sum(ss_sales_price)) over (partition by ss_store_sk) as ave
    from date_dim
    join store_sales on ss_sold_date_sk = d_date_sk
    where d_month_seq between 1176 and 1176+11
    group by ss_store_sk, ss_item_sk
) lo
join store on s_store_sk = lo.ss_store_sk
join item  on i_item_sk  = lo.ss_item_sk
where lo.revenue <= 0.1 * lo.ave
order by s_store_name, i_item_desc
limit 100;