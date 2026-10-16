-- Finds 1998 easily and The day name is included so doensot ened to read date_dim table
create index idx_date_year_sk_day
    on date_dim (d_year, d_date_sk, d_day_name);

-- reads store and price from the index alone.
create index idx_ss_date_store_price
    on store_sales (ss_sold_date_sk, ss_store_sk, ss_sales_price);

-- analyze table date_dim, store_sales;
-- 
-- drop index idx_date_year_sk_day on date_dim;
-- drop index idx_ss_date_store_price on store_sales;

analyze table date_dim, store_sales;

select s_store_name, s_store_id,
       sum(case when d_day_name='Sunday'    then ss_sales_price else null end) sun_sales,
       sum(case when d_day_name='Monday'    then ss_sales_price else null end) mon_sales,
       sum(case when d_day_name='Tuesday'   then ss_sales_price else null end) tue_sales,
       sum(case when d_day_name='Wednesday' then ss_sales_price else null end) wed_sales,
       sum(case when d_day_name='Thursday'  then ss_sales_price else null end) thu_sales,
       sum(case when d_day_name='Friday'    then ss_sales_price else null end) fri_sales,
       sum(case when d_day_name='Saturday'  then ss_sales_price else null end) sat_sales
from date_dim
straight_join store_sales on d_date_sk = ss_sold_date_sk
straight_join store on s_store_sk = ss_store_sk
where s_gmt_offset = -5
  and d_year = 1998
group by s_store_name, s_store_id
order by s_store_name, s_store_id, sun_sales, mon_sales, tue_sales,
         wed_sales, thu_sales, fri_sales, sat_sales
limit 100;