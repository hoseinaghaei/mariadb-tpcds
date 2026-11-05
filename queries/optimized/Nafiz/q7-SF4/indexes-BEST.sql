-- Run outside query timing; additions to the shared 167-index profile.
USE tpcds;
CREATE INDEX IF NOT EXISTS idx_nf_q7_item_id ON item (i_item_id);
ALTER TABLE item ALTER INDEX idx_nf_q7_item_id NOT IGNORED;
CREATE INDEX IF NOT EXISTS idx_nf_q7_item_cover ON store_sales (ss_item_sk,ss_sold_date_sk,ss_cdemo_sk,ss_promo_sk,ss_quantity,ss_list_price,ss_coupon_amt,ss_sales_price);
ALTER TABLE store_sales ALTER INDEX idx_nf_q7_item_cover NOT IGNORED;
ANALYZE TABLE item,store_sales;
