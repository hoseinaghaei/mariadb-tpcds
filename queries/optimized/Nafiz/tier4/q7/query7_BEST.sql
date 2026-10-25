-- v3: add a date-first join hint to the equivalent 1998 date-key range.
SELECT /*+ JOIN_PREFIX(date_dim, store_sales) */ i_item_id, AVG(ss_quantity) agg1, AVG(ss_list_price) agg2,
       AVG(ss_coupon_amt) agg3, AVG(ss_sales_price) agg4
FROM date_dim, store_sales, customer_demographics, item, promotion
WHERE ss_sold_date_sk = d_date_sk
  AND ss_sold_date_sk BETWEEN 2450815 AND 2451179
  AND ss_item_sk = i_item_sk AND ss_cdemo_sk = cd_demo_sk AND ss_promo_sk = p_promo_sk
  AND cd_gender = 'F' AND cd_marital_status = 'S' AND cd_education_status = 'Unknown'
  AND (p_channel_email = 'N' OR p_channel_event = 'N') AND d_year = 1998
GROUP BY i_item_id ORDER BY i_item_id LIMIT 100;
