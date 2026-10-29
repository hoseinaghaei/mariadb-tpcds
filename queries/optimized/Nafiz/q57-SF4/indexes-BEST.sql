-- Optional Q57 covering index, additional to the agreed 167-index profile.
-- Build and ANALYZE outside query timing.
USE tpcds;
CREATE INDEX IF NOT EXISTS idx_nf_q57_catalog_cover ON catalog_sales (cs_sold_date_sk,cs_item_sk,cs_call_center_sk,cs_sales_price);
ALTER TABLE catalog_sales ALTER INDEX idx_nf_q57_catalog_cover NOT IGNORED;
ANALYZE TABLE catalog_sales;
