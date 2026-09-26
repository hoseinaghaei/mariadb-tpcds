-- ---------------------------------------------------------------------------
--  Hide every index that no query read, from the optimizer.
--
--  Derived from INFORMATION_SCHEMA.INDEX_STATISTICS after the serial indexed
--  run: 117 secondary indexes defined, 36 read, 81 never touched.
--
--  IGNORED rather than DROP: metadata-only, ~0.15s per index, the index stays
--  fully built and maintained on disk, and 10_unignore_unused_indexes.sql puts
--  them back just as fast. Requires MariaDB 10.6+.
--
--  CAVEAT: "unused" means unused by THESE 99 queries at scale factor 1 with
--  seed 10. A different scale factor, different substitution parameters, or
--  the data-maintenance workload could use some of them.
-- ---------------------------------------------------------------------------

USE tpcds;

ALTER TABLE call_center ALTER INDEX idx_cc_closed_date_sk IGNORED;
ALTER TABLE call_center ALTER INDEX idx_cc_open_date_sk IGNORED;
ALTER TABLE catalog_page ALTER INDEX idx_cp_end_date_sk IGNORED;
ALTER TABLE catalog_page ALTER INDEX idx_cp_start_date_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_call_center_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_catalog_page_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_order_number IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_reason_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_refunded_addr_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_refunded_cdemo_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_refunded_customer_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_refunded_hdemo_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_returned_date_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_returned_time_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_returning_cdemo_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_returning_hdemo_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_ship_mode_sk IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_warehouse_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_bill_addr_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_bill_cdemo_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_call_center_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_catalog_page_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_item_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_promo_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_ship_cdemo_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_ship_customer_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_ship_hdemo_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_ship_mode_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_sold_date_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_sold_time_sk IGNORED;
ALTER TABLE catalog_sales ALTER INDEX idx_cs_warehouse_sk IGNORED;
ALTER TABLE customer ALTER INDEX idx_c_current_cdemo_sk IGNORED;
ALTER TABLE customer ALTER INDEX idx_c_first_sales_date_sk IGNORED;
ALTER TABLE customer ALTER INDEX idx_c_first_shipto_date_sk IGNORED;
ALTER TABLE customer_demographics ALTER INDEX idx_customer_demographics_1 IGNORED;
ALTER TABLE inventory ALTER INDEX idx_inv_date_sk IGNORED;
ALTER TABLE promotion ALTER INDEX idx_p_end_date_sk IGNORED;
ALTER TABLE promotion ALTER INDEX idx_p_item_sk IGNORED;
ALTER TABLE promotion ALTER INDEX idx_p_start_date_sk IGNORED;
ALTER TABLE store ALTER INDEX idx_s_closed_date_sk IGNORED;
ALTER TABLE store_returns ALTER INDEX idx_sr_addr_sk IGNORED;
ALTER TABLE store_returns ALTER INDEX idx_sr_customer_sk IGNORED;
ALTER TABLE store_returns ALTER INDEX idx_sr_hdemo_sk IGNORED;
ALTER TABLE store_returns ALTER INDEX idx_sr_returned_date_sk IGNORED;
ALTER TABLE store_returns ALTER INDEX idx_sr_return_time_sk IGNORED;
ALTER TABLE store_returns ALTER INDEX idx_sr_ticket_number IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_cdemo_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_hdemo_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_promo_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_sold_time_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_store_sk IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_ss_ticket_number IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_store_sales_1 IGNORED;
ALTER TABLE store_sales ALTER INDEX idx_store_sales_2 IGNORED;
ALTER TABLE web_page ALTER INDEX idx_wp_access_date_sk IGNORED;
ALTER TABLE web_page ALTER INDEX idx_wp_creation_date_sk IGNORED;
ALTER TABLE web_page ALTER INDEX idx_wp_customer_sk IGNORED;
ALTER TABLE web_returns ALTER INDEX idx_wr_reason_sk IGNORED;
ALTER TABLE web_returns ALTER INDEX idx_wr_refunded_cdemo_sk IGNORED;
ALTER TABLE web_returns ALTER INDEX idx_wr_refunded_customer_sk IGNORED;
ALTER TABLE web_returns ALTER INDEX idx_wr_refunded_hdemo_sk IGNORED;
ALTER TABLE web_returns ALTER INDEX idx_wr_returned_date_sk IGNORED;
ALTER TABLE web_returns ALTER INDEX idx_wr_returned_time_sk IGNORED;
ALTER TABLE web_returns ALTER INDEX idx_wr_returning_cdemo_sk IGNORED;
ALTER TABLE web_returns ALTER INDEX idx_wr_returning_hdemo_sk IGNORED;
ALTER TABLE web_returns ALTER INDEX idx_wr_web_page_sk IGNORED;
ALTER TABLE web_sales ALTER INDEX idx_ws_bill_addr_sk IGNORED;
ALTER TABLE web_sales ALTER INDEX idx_ws_bill_cdemo_sk IGNORED;
ALTER TABLE web_sales ALTER INDEX idx_ws_bill_customer_sk IGNORED;
ALTER TABLE web_sales ALTER INDEX idx_ws_bill_hdemo_sk IGNORED;
ALTER TABLE web_sales ALTER INDEX idx_ws_item_sk IGNORED;
ALTER TABLE web_sales ALTER INDEX idx_ws_promo_sk IGNORED;
ALTER TABLE web_sales ALTER INDEX idx_ws_ship_cdemo_sk IGNORED;
ALTER TABLE web_sales ALTER INDEX idx_ws_ship_customer_sk IGNORED;
ALTER TABLE web_sales ALTER INDEX idx_ws_ship_mode_sk IGNORED;
ALTER TABLE web_sales ALTER INDEX idx_ws_sold_date_sk IGNORED;
ALTER TABLE web_sales ALTER INDEX idx_ws_sold_time_sk IGNORED;
ALTER TABLE web_sales ALTER INDEX idx_ws_web_site_sk IGNORED;
ALTER TABLE web_site ALTER INDEX idx_web_close_date_sk IGNORED;
ALTER TABLE web_site ALTER INDEX idx_web_open_date_sk IGNORED;
