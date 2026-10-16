-- CREATE INDEX idx_ss_date_cdemo_store_item
-- ON store_sales (ss_sold_date_sk, ss_cdemo_sk, ss_store_sk, ss_item_sk,
--                 ss_quantity, ss_list_price, ss_coupon_amt, ss_sales_price);
-- 

select * from (
select  i_item_id,
        s_state, (s_state is null) g_state,
        avg(ss_quantity) agg1,
        avg(ss_list_price) agg2,
        avg(ss_coupon_amt) agg3,
        avg(ss_sales_price) agg4
 from date_dim
 straight_join store_sales on ss_sold_date_sk = d_date_sk
 straight_join customer_demographics on ss_cdemo_sk = cd_demo_sk
 straight_join store on ss_store_sk = s_store_sk
 straight_join item on ss_item_sk = i_item_sk
 where cd_gender = 'F' and
       cd_marital_status = 'S' and
       cd_education_status = 'Unknown' and
       d_year = 1998 and
       s_state = 'TN'
 group by i_item_id, s_state with rollup
) tpcds_rollup
order by i_item_id, s_state
limit 100;