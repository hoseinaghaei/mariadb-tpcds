select STRAIGHT_JOIN  i_item_id, 
        avg(ss_quantity) agg1,
        avg(ss_list_price) agg2,
        avg(ss_coupon_amt) agg3,
        avg(ss_sales_price) agg4 
 from item FORCE INDEX (idx_nf_q7_item_id), store_sales FORCE INDEX (idx_nf_q7_item_cover), customer_demographics, date_dim, promotion
 where ss_sold_date_sk = d_date_sk and
       ss_item_sk = i_item_sk and
       ss_cdemo_sk = cd_demo_sk and
       ss_promo_sk = p_promo_sk and
       cd_gender = 'F' and 
       cd_marital_status = 'S' and
       cd_education_status = 'Unknown' and
       (p_channel_email = 'N' or p_channel_event = 'N') and
       d_year = 1998 AND ss_sold_date_sk BETWEEN 2450815 AND 2451179 
 group by i_item_id
 order by i_item_id
 limit 100;
