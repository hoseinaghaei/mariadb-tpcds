-- ---------------------------------------------------------------------------
--  Drop the indexes that no TPC-DS query actually read.
--
--  Derived from INFORMATION_SCHEMA.INDEX_STATISTICS after running all 99
--  queries against the indexed database with userstat=1 and the statistics
--  flushed to zero beforehand. See report/15-index-statistics.md.
--
--  117 secondary indexes defined, 36 read, 81 never touched.
--
--  Snapshot caveat: query 72 had not completed when this was generated, so its
--  index usage is not reflected. The list can only shrink, never grow --
--  regenerate with the query at the end of report/15-index-statistics.md
--  before relying on it.
--
--  These cost storage, cost time on every insert and update, and enlarge the
--  optimizer's search space, while contributing nothing to this query set.
--
--  CAVEAT: "unused" means unused BY THESE 99 QUERIES AT SCALE FACTOR 1 with
--  this parameter set. A different scale factor, different substitution
--  parameters, or the data-maintenance workload could use some of them.

-- ###########################################################################
-- ##  WARNING - DO NOT RUN THIS WITHOUT READING report/17.
-- ##
-- ##  Hiding these indexes with ALTER INDEX ... IGNORED was tested, and
-- ##  query 78 went from 73s to not completing within 300s. The indexes it
-- ##  needs are never READ -- they appear only in possible_keys -- but their
-- ##  availability changes the optimizer's cost estimates and join order.
-- ##
-- ##  ROWS_READ does not measure whether an index influences a plan.
-- ##
-- ##  Test with sql/09_ignore_unused_indexes.sql first (reversible in 17s),
-- ##  run the WHOLE query set, and check every query individually -- the
-- ##  aggregate moved only -0.8% while query 78 blew up 12x.
-- ###########################################################################

USE tpcds;

ALTER TABLE call_center DROP INDEX idx_cc_closed_date_sk;
ALTER TABLE call_center DROP INDEX idx_cc_open_date_sk;
ALTER TABLE catalog_page DROP INDEX idx_cp_end_date_sk;
ALTER TABLE catalog_page DROP INDEX idx_cp_start_date_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_call_center_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_catalog_page_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_order_number;
ALTER TABLE catalog_returns DROP INDEX idx_cr_reason_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_refunded_addr_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_refunded_cdemo_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_refunded_customer_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_refunded_hdemo_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_returned_date_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_returned_time_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_returning_cdemo_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_returning_hdemo_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_ship_mode_sk;
ALTER TABLE catalog_returns DROP INDEX idx_cr_warehouse_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_bill_addr_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_bill_cdemo_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_call_center_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_catalog_page_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_item_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_promo_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_ship_cdemo_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_ship_customer_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_ship_hdemo_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_ship_mode_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_sold_date_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_sold_time_sk;
ALTER TABLE catalog_sales DROP INDEX idx_cs_warehouse_sk;
ALTER TABLE customer DROP INDEX idx_c_current_cdemo_sk;
ALTER TABLE customer DROP INDEX idx_c_first_sales_date_sk;
ALTER TABLE customer DROP INDEX idx_c_first_shipto_date_sk;
ALTER TABLE customer_demographics DROP INDEX idx_customer_demographics_1;
ALTER TABLE inventory DROP INDEX idx_inv_date_sk;
ALTER TABLE promotion DROP INDEX idx_p_end_date_sk;
ALTER TABLE promotion DROP INDEX idx_p_item_sk;
ALTER TABLE promotion DROP INDEX idx_p_start_date_sk;
ALTER TABLE store DROP INDEX idx_s_closed_date_sk;
ALTER TABLE store_returns DROP INDEX idx_sr_addr_sk;
ALTER TABLE store_returns DROP INDEX idx_sr_customer_sk;
ALTER TABLE store_returns DROP INDEX idx_sr_hdemo_sk;
ALTER TABLE store_returns DROP INDEX idx_sr_returned_date_sk;
ALTER TABLE store_returns DROP INDEX idx_sr_return_time_sk;
ALTER TABLE store_returns DROP INDEX idx_sr_ticket_number;
ALTER TABLE store_sales DROP INDEX idx_ss_cdemo_sk;
ALTER TABLE store_sales DROP INDEX idx_ss_hdemo_sk;
ALTER TABLE store_sales DROP INDEX idx_ss_item_sk;
ALTER TABLE store_sales DROP INDEX idx_ss_promo_sk;
ALTER TABLE store_sales DROP INDEX idx_ss_sold_time_sk;
ALTER TABLE store_sales DROP INDEX idx_ss_store_sk;
ALTER TABLE store_sales DROP INDEX idx_ss_ticket_number;
ALTER TABLE store_sales DROP INDEX idx_store_sales_1;
ALTER TABLE store_sales DROP INDEX idx_store_sales_2;
ALTER TABLE web_page DROP INDEX idx_wp_access_date_sk;
ALTER TABLE web_page DROP INDEX idx_wp_creation_date_sk;
ALTER TABLE web_page DROP INDEX idx_wp_customer_sk;
ALTER TABLE web_returns DROP INDEX idx_wr_reason_sk;
ALTER TABLE web_returns DROP INDEX idx_wr_refunded_cdemo_sk;
ALTER TABLE web_returns DROP INDEX idx_wr_refunded_customer_sk;
ALTER TABLE web_returns DROP INDEX idx_wr_refunded_hdemo_sk;
ALTER TABLE web_returns DROP INDEX idx_wr_returned_date_sk;
ALTER TABLE web_returns DROP INDEX idx_wr_returned_time_sk;
ALTER TABLE web_returns DROP INDEX idx_wr_returning_cdemo_sk;
ALTER TABLE web_returns DROP INDEX idx_wr_returning_hdemo_sk;
ALTER TABLE web_returns DROP INDEX idx_wr_web_page_sk;
ALTER TABLE web_sales DROP INDEX idx_ws_bill_addr_sk;
ALTER TABLE web_sales DROP INDEX idx_ws_bill_cdemo_sk;
ALTER TABLE web_sales DROP INDEX idx_ws_bill_customer_sk;
ALTER TABLE web_sales DROP INDEX idx_ws_bill_hdemo_sk;
ALTER TABLE web_sales DROP INDEX idx_ws_item_sk;
ALTER TABLE web_sales DROP INDEX idx_ws_promo_sk;
ALTER TABLE web_sales DROP INDEX idx_ws_ship_cdemo_sk;
ALTER TABLE web_sales DROP INDEX idx_ws_ship_customer_sk;
ALTER TABLE web_sales DROP INDEX idx_ws_ship_mode_sk;
ALTER TABLE web_sales DROP INDEX idx_ws_sold_date_sk;
ALTER TABLE web_sales DROP INDEX idx_ws_sold_time_sk;
ALTER TABLE web_sales DROP INDEX idx_ws_web_site_sk;
ALTER TABLE web_site DROP INDEX idx_web_close_date_sk;
ALTER TABLE web_site DROP INDEX idx_web_open_date_sk;
