-- query27: split materialisation disabled for this query.
-- Measured -3.7s at SF=4 / 32K / tier 4+5 (see queries/tuned/README.md).
-- The setting is session-scoped, so it affects only this query.

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

SET SESSION optimizer_switch = 'split_materialized=off';

select * from (
select  i_item_id,
        s_state, (s_state is null) g_state,
        avg(ss_quantity) agg1,
        avg(ss_list_price) agg2,
        avg(ss_coupon_amt) agg3,
        avg(ss_sales_price) agg4
 from store_sales, customer_demographics, date_dim, store, item
 where ss_sold_date_sk = d_date_sk and
       ss_item_sk = i_item_sk and
       ss_store_sk = s_store_sk and
       ss_cdemo_sk = cd_demo_sk and
       cd_gender = 'F' and
       cd_marital_status = 'S' and
       cd_education_status = 'Unknown' and
       d_year = 1998 and
       s_state in ('TN','TN', 'TN', 'TN', 'TN', 'TN')
 group by i_item_id, s_state with rollup
) tpcds_rollup
order by i_item_id
         ,s_state
 limit 100;
