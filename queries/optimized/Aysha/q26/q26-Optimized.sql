-- Filter dates to 1998 and join to catalog_sales
-- CREATE INDEX idx_date_year_sk
-- ON date_dim (d_year, d_date_sk);

-- Filter customer demographics
-- CREATE INDEX idx_cd_filter_sk
-- ON customer_demographics (
--     cd_gender,
--     cd_marital_status,
--     cd_education_status,
--     cd_demo_sk
-- );

-- CREATE INDEX idx_cs_date_cover
-- ON catalog_sales (
--     cs_sold_date_sk,
--     cs_bill_cdemo_sk,
--     cs_item_sk,
--     cs_promo_sk,
--     cs_quantity,
--     cs_list_price,
--     cs_coupon_amt,
--     cs_sales_price
-- );


SELECT
    i_item_id,
    AVG(cs_quantity) AS agg1,
    AVG(cs_list_price) AS agg2,
    AVG(cs_coupon_amt) AS agg3,
    AVG(cs_sales_price) AS agg4
FROM date_dim
STRAIGHT_JOIN catalog_sales
STRAIGHT_JOIN customer_demographics
STRAIGHT_JOIN item
STRAIGHT_JOIN promotion
WHERE cs_sold_date_sk = d_date_sk
  AND cs_item_sk = i_item_sk
  AND cs_bill_cdemo_sk = cd_demo_sk
  AND cs_promo_sk = p_promo_sk
  AND cd_gender = 'F'
  AND cd_marital_status = 'S'
  AND cd_education_status = 'Unknown'
  AND (p_channel_email = 'N' OR p_channel_event = 'N')
  AND d_year = 1998
GROUP BY i_item_id
ORDER BY i_item_id
LIMIT 100;