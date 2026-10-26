-- ========================================================================
--  Indexes that NEITHER scale factor read.
--
--  Generated 2026-10-26 21:00 by scripts/prune-indexes.py from
--  analysis/index-usage-sf1.tsv and index-usage-sf4.tsv.
--
--  127 indexes, 16,314 MB (15.9 GB).
--  Kept because at least one scale read them: 37.
--  Skipped because they are IGNORED (cannot be read, so a zero
--  count proves nothing): 0.
--
--  PUT THEM ALL BACK:
--      mariadb tpcds < sql/all_indexes.sql
--
--  The rule is intersection, not union: an index idle at one scale
--  may be busy at another, and this project has measured the same
--  index set at 16K and 32K pages and disagreed with itself about
--  which members were idle (report/17, report/22).  The evidence
--  here is 40 queries at two scale factors under one configuration.
--
--  To test the same decision reversibly first, use IGNORED instead:
--  metadata-only, about 0.15s each, and the index stays on disk.
-- ========================================================================

-- inventory: 3 indexes, 3,090 MB
DROP INDEX IF EXISTS idx_inv_date_sk ON inventory;   -- 1,030 MB
DROP INDEX IF EXISTS idx_inv_item_sk ON inventory;   -- 1,030 MB
DROP INDEX IF EXISTS idx_inv_warehouse_sk ON inventory;   -- 1,030 MB

-- store_sales: 17 indexes, 6,646 MB
DROP INDEX IF EXISTS idx_ss_q61 ON store_sales;   -- 640 MB
DROP INDEX IF EXISTS idx_ss_date_store_price ON store_sales;   -- 470 MB
DROP INDEX IF EXISTS idx_ss_qty_q28 ON store_sales;   -- 470 MB
DROP INDEX IF EXISTS idx_store_sales_quantity_2 ON store_sales;   -- 470 MB
DROP INDEX IF EXISTS idx_ss_cust_date ON store_sales;   -- 426 MB
DROP INDEX IF EXISTS idx_ss_qty_cover ON store_sales;   -- 426 MB
DROP INDEX IF EXISTS idx_store_sales_2 ON store_sales;   -- 426 MB
DROP INDEX IF EXISTS idx_ss_addr_sk ON store_sales;   -- 341 MB
DROP INDEX IF EXISTS idx_ss_cdemo_sk ON store_sales;   -- 341 MB
DROP INDEX IF EXISTS idx_ss_customer_sk ON store_sales;   -- 341 MB
DROP INDEX IF EXISTS idx_ss_hdemo_sk ON store_sales;   -- 341 MB
DROP INDEX IF EXISTS idx_ss_promo_sk ON store_sales;   -- 341 MB
DROP INDEX IF EXISTS idx_ss_sold_time_sk ON store_sales;   -- 341 MB
DROP INDEX IF EXISTS idx_ss_store_sk ON store_sales;   -- 341 MB
DROP INDEX IF EXISTS idx_store_sales_1 ON store_sales;   -- 341 MB
DROP INDEX IF EXISTS idx_store_sales_quantity_1 ON store_sales;   -- 341 MB
DROP INDEX IF EXISTS idx_ss_ticket_number ON store_sales;   -- 247 MB

-- catalog_sales: 20 indexes, 3,670 MB
DROP INDEX IF EXISTS idx_cs_cust_date_price ON catalog_sales;   -- 243 MB
DROP INDEX IF EXISTS idx_cs_price_date_cust ON catalog_sales;   -- 243 MB
DROP INDEX IF EXISTS idx_cs_cust_date ON catalog_sales;   -- 221 MB
DROP INDEX IF EXISTS idx_cs_bill_addr_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_bill_cdemo_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_bill_customer_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_bill_hdemo_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_call_center_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_catalog_page_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_promo_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_ship_addr_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_ship_cdemo_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_ship_customer_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_ship_date_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_ship_hdemo_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_ship_mode_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_sold_date_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_sold_time_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_warehouse_sk ON catalog_sales;   -- 177 MB
DROP INDEX IF EXISTS idx_cs_order_number ON catalog_sales;   -- 127 MB

-- web_sales: 21 indexes, 1,953 MB
DROP INDEX IF EXISTS idx_ws_cust_date ON web_sales;   -- 115 MB
DROP INDEX IF EXISTS idx_ws_date_item_paid ON web_sales;   -- 105 MB
DROP INDEX IF EXISTS idx_ws_sold_date_ext_price ON web_sales;   -- 105 MB
DROP INDEX IF EXISTS idx_ws_bill_addr_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_bill_cdemo_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_bill_customer_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_bill_hdemo_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_promo_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_ship_addr_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_ship_cdemo_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_ship_customer_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_ship_date_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_ship_hdemo_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_ship_mode_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_sold_date_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_sold_time_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_warehouse_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_web_page_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_web_site_sk ON web_sales;   -- 93 MB
DROP INDEX IF EXISTS idx_ws_item_sk ON web_sales;   -- 69 MB
DROP INDEX IF EXISTS idx_ws_order_number ON web_sales;   -- 69 MB

-- customer_demographics: 1 indexes, 77 MB
DROP INDEX IF EXISTS idx_customer_demographics_1 ON customer_demographics;   -- 77 MB

-- store_returns: 9 indexes, 342 MB
DROP INDEX IF EXISTS idx_sr_addr_sk ON store_returns;   -- 39 MB
DROP INDEX IF EXISTS idx_sr_cdemo_sk ON store_returns;   -- 39 MB
DROP INDEX IF EXISTS idx_sr_customer_sk ON store_returns;   -- 39 MB
DROP INDEX IF EXISTS idx_sr_hdemo_sk ON store_returns;   -- 39 MB
DROP INDEX IF EXISTS idx_sr_reason_sk ON store_returns;   -- 39 MB
DROP INDEX IF EXISTS idx_sr_return_time_sk ON store_returns;   -- 39 MB
DROP INDEX IF EXISTS idx_sr_returned_date_sk ON store_returns;   -- 39 MB
DROP INDEX IF EXISTS idx_sr_store_sk ON store_returns;   -- 39 MB
DROP INDEX IF EXISTS idx_sr_ticket_number ON store_returns;   -- 29 MB

-- catalog_returns: 16 indexes, 330 MB
DROP INDEX IF EXISTS idx_cr_call_center_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_catalog_page_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_reason_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_refunded_addr_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_refunded_cdemo_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_refunded_customer_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_refunded_hdemo_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_returned_date_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_returned_time_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_returning_addr_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_returning_cdemo_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_returning_customer_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_returning_hdemo_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_ship_mode_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_warehouse_sk ON catalog_returns;   -- 21 MB
DROP INDEX IF EXISTS idx_cr_order_number ON catalog_returns;   -- 15 MB

-- web_returns: 13 indexes, 139 MB
DROP INDEX IF EXISTS idx_wr_reason_sk ON web_returns;   -- 11 MB
DROP INDEX IF EXISTS idx_wr_refunded_addr_sk ON web_returns;   -- 11 MB
DROP INDEX IF EXISTS idx_wr_refunded_cdemo_sk ON web_returns;   -- 11 MB
DROP INDEX IF EXISTS idx_wr_refunded_customer_sk ON web_returns;   -- 11 MB
DROP INDEX IF EXISTS idx_wr_refunded_hdemo_sk ON web_returns;   -- 11 MB
DROP INDEX IF EXISTS idx_wr_returned_date_sk ON web_returns;   -- 11 MB
DROP INDEX IF EXISTS idx_wr_returned_time_sk ON web_returns;   -- 11 MB
DROP INDEX IF EXISTS idx_wr_returning_addr_sk ON web_returns;   -- 11 MB
DROP INDEX IF EXISTS idx_wr_returning_cdemo_sk ON web_returns;   -- 11 MB
DROP INDEX IF EXISTS idx_wr_returning_customer_sk ON web_returns;   -- 11 MB
DROP INDEX IF EXISTS idx_wr_returning_hdemo_sk ON web_returns;   -- 11 MB
DROP INDEX IF EXISTS idx_wr_web_page_sk ON web_returns;   -- 11 MB
DROP INDEX IF EXISTS idx_wr_order_number ON web_returns;   -- 7 MB

-- customer: 6 indexes, 42 MB
DROP INDEX IF EXISTS idx_c_addr ON customer;   -- 7 MB
DROP INDEX IF EXISTS idx_c_current_addr_sk ON customer;   -- 7 MB
DROP INDEX IF EXISTS idx_c_current_cdemo_sk ON customer;   -- 7 MB
DROP INDEX IF EXISTS idx_c_current_hdemo_sk ON customer;   -- 7 MB
DROP INDEX IF EXISTS idx_c_first_sales_date_sk ON customer;   -- 7 MB
DROP INDEX IF EXISTS idx_c_first_shipto_date_sk ON customer;   -- 7 MB

-- customer_address: 1 indexes, 5 MB
DROP INDEX IF EXISTS idx_customer_address_1 ON customer_address;   -- 5 MB

-- item: 4 indexes, 16 MB
DROP INDEX IF EXISTS idx_item_2 ON item;   -- 5 MB
DROP INDEX IF EXISTS idx_item_cat ON item;   -- 5 MB
DROP INDEX IF EXISTS idx_item_category_id ON item;   -- 5 MB
DROP INDEX IF EXISTS idx_item_price ON item;   -- 1 MB

-- date_dim: 1 indexes, 3 MB
DROP INDEX IF EXISTS idx_date_month_date_sk ON date_dim;   -- 3 MB

-- catalog_page: 2 indexes, 1 MB
DROP INDEX IF EXISTS idx_cp_end_date_sk ON catalog_page;   -- 0 MB
DROP INDEX IF EXISTS idx_cp_start_date_sk ON catalog_page;   -- 0 MB

-- household_demographics: 1 indexes, 0 MB
DROP INDEX IF EXISTS idx_hd_income_band_sk ON household_demographics;   -- 0 MB

-- call_center: 2 indexes, 0 MB
DROP INDEX IF EXISTS idx_cc_closed_date_sk ON call_center;   -- 0 MB
DROP INDEX IF EXISTS idx_cc_open_date_sk ON call_center;   -- 0 MB

-- promotion: 3 indexes, 0 MB
DROP INDEX IF EXISTS idx_p_end_date_sk ON promotion;   -- 0 MB
DROP INDEX IF EXISTS idx_p_item_sk ON promotion;   -- 0 MB
DROP INDEX IF EXISTS idx_p_start_date_sk ON promotion;   -- 0 MB

-- store: 2 indexes, 0 MB
DROP INDEX IF EXISTS idx_s_closed_date_sk ON store;   -- 0 MB
DROP INDEX IF EXISTS idx_store_gmt ON store;   -- 0 MB

-- web_page: 3 indexes, 0 MB
DROP INDEX IF EXISTS idx_wp_access_date_sk ON web_page;   -- 0 MB
DROP INDEX IF EXISTS idx_wp_creation_date_sk ON web_page;   -- 0 MB
DROP INDEX IF EXISTS idx_wp_customer_sk ON web_page;   -- 0 MB

-- web_site: 2 indexes, 0 MB
DROP INDEX IF EXISTS idx_web_close_date_sk ON web_site;   -- 0 MB
DROP INDEX IF EXISTS idx_web_open_date_sk ON web_site;   -- 0 MB

-- Not touched: present in only one report.
--   catalog_sales.idx_cs_q66  (absent from SF=1)
--   store_sales.idx_ss_date_store_profit  (absent from SF=1)
--   web_sales.idx_ws_q66  (absent from SF=1)
