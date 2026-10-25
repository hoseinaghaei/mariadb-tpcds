-- query27
-- source: queries/optimized/Aysha/q27/q27_Optimized.sql
-- split materialisation OFF: measured -3.7s at SF=4

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');
SET SESSION optimizer_switch = 'split_materialized=off';

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
