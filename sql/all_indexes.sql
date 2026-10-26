-- ========================================================================
--  Every secondary index in tpcds, in one file.
--
--  Generated 2026-10-26 20:18 by scripts/dump-indexes.py from the live schema.
--  167 indexes across 19 tables, 1 of them currently IGNORED.
--
--  RESTORE EVERYTHING:
--      mariadb tpcds < sql/all_indexes.sql
--
--  This is what makes dropping an index safe to try.  'Unused' is
--  not a property of an index: it is a property of an index AND a
--  workload AND a configuration.  The same index set measured at
--  16K and 32K pages disagreed about which members were idle
--  (report/17, report/22), so an index that looks dead today may
--  be read millions of times after a settings change.
--
--  Prefer ALTER TABLE <t> ALTER INDEX <i> IGNORED when the question
--  is whether an index earns its keep: it is metadata-only, takes
--  about 0.15s, reverses instantly, and leaves the index on disk.
--  Drop only when you actually need the space back.
-- ========================================================================

SET SESSION alter_algorithm='INPLACE';

-- call_center  (2 indexes)
CREATE INDEX IF NOT EXISTS idx_cc_closed_date_sk ON call_center (cc_closed_date_sk);
CREATE INDEX IF NOT EXISTS idx_cc_open_date_sk ON call_center (cc_open_date_sk);

-- catalog_page  (2 indexes)
CREATE INDEX IF NOT EXISTS idx_cp_end_date_sk ON catalog_page (cp_end_date_sk);
CREATE INDEX IF NOT EXISTS idx_cp_start_date_sk ON catalog_page (cp_start_date_sk);

-- catalog_returns  (17 indexes)
CREATE INDEX IF NOT EXISTS idx_cr_call_center_sk ON catalog_returns (cr_call_center_sk);
CREATE INDEX IF NOT EXISTS idx_cr_catalog_page_sk ON catalog_returns (cr_catalog_page_sk);
CREATE INDEX IF NOT EXISTS idx_cr_item_sk ON catalog_returns (cr_item_sk);
CREATE INDEX IF NOT EXISTS idx_cr_order_number ON catalog_returns (cr_order_number);
CREATE INDEX IF NOT EXISTS idx_cr_reason_sk ON catalog_returns (cr_reason_sk);
CREATE INDEX IF NOT EXISTS idx_cr_refunded_addr_sk ON catalog_returns (cr_refunded_addr_sk);
CREATE INDEX IF NOT EXISTS idx_cr_refunded_cdemo_sk ON catalog_returns (cr_refunded_cdemo_sk);
CREATE INDEX IF NOT EXISTS idx_cr_refunded_customer_sk ON catalog_returns (cr_refunded_customer_sk);
CREATE INDEX IF NOT EXISTS idx_cr_refunded_hdemo_sk ON catalog_returns (cr_refunded_hdemo_sk);
CREATE INDEX IF NOT EXISTS idx_cr_returned_date_sk ON catalog_returns (cr_returned_date_sk);
CREATE INDEX IF NOT EXISTS idx_cr_returned_time_sk ON catalog_returns (cr_returned_time_sk);
CREATE INDEX IF NOT EXISTS idx_cr_returning_addr_sk ON catalog_returns (cr_returning_addr_sk);
CREATE INDEX IF NOT EXISTS idx_cr_returning_cdemo_sk ON catalog_returns (cr_returning_cdemo_sk);
CREATE INDEX IF NOT EXISTS idx_cr_returning_customer_sk ON catalog_returns (cr_returning_customer_sk);
CREATE INDEX IF NOT EXISTS idx_cr_returning_hdemo_sk ON catalog_returns (cr_returning_hdemo_sk);
CREATE INDEX IF NOT EXISTS idx_cr_ship_mode_sk ON catalog_returns (cr_ship_mode_sk);
CREATE INDEX IF NOT EXISTS idx_cr_warehouse_sk ON catalog_returns (cr_warehouse_sk);

-- catalog_sales  (27 indexes)
CREATE INDEX IF NOT EXISTS idx_cs_bill_addr_sk ON catalog_sales (cs_bill_addr_sk);
CREATE INDEX IF NOT EXISTS idx_cs_bill_cdemo_sk ON catalog_sales (cs_bill_cdemo_sk);
CREATE INDEX IF NOT EXISTS idx_cs_bill_customer_sk ON catalog_sales (cs_bill_customer_sk);
CREATE INDEX IF NOT EXISTS idx_cs_bill_hdemo_sk ON catalog_sales (cs_bill_hdemo_sk);
CREATE INDEX IF NOT EXISTS idx_cs_call_center_sk ON catalog_sales (cs_call_center_sk);
CREATE INDEX IF NOT EXISTS idx_cs_catalog_page_sk ON catalog_sales (cs_catalog_page_sk);
CREATE INDEX IF NOT EXISTS idx_cs_cust_date ON catalog_sales (cs_ship_customer_sk, cs_sold_date_sk);
CREATE INDEX IF NOT EXISTS idx_cs_cust_date_price ON catalog_sales (cs_bill_customer_sk, cs_sold_date_sk, cs_sales_price);
CREATE INDEX IF NOT EXISTS idx_cs_date_addr_item_price ON catalog_sales (cs_sold_date_sk, cs_bill_addr_sk, cs_item_sk, cs_ext_sales_price);
CREATE INDEX IF NOT EXISTS idx_cs_date_cover ON catalog_sales (cs_sold_date_sk, cs_bill_cdemo_sk, cs_item_sk, cs_promo_sk, cs_quantity, cs_list_price, cs_coupon_amt, cs_sales_price);
CREATE INDEX IF NOT EXISTS idx_cs_date_cust ON catalog_sales (cs_sold_date_sk, cs_ship_customer_sk);
CREATE INDEX IF NOT EXISTS idx_cs_date_customer ON catalog_sales (cs_sold_date_sk, cs_bill_customer_sk);
CREATE INDEX IF NOT EXISTS idx_cs_item_sk ON catalog_sales (cs_item_sk);
CREATE INDEX IF NOT EXISTS idx_cs_order_number ON catalog_sales (cs_order_number);
CREATE INDEX IF NOT EXISTS idx_cs_price_date_cust ON catalog_sales (cs_sales_price, cs_sold_date_sk, cs_bill_customer_sk);
CREATE INDEX IF NOT EXISTS idx_cs_promo_sk ON catalog_sales (cs_promo_sk);
CREATE INDEX IF NOT EXISTS idx_cs_q66 ON catalog_sales (cs_ship_mode_sk, cs_sold_date_sk, cs_sold_time_sk, cs_warehouse_sk, cs_ext_sales_price, cs_quantity, cs_net_paid_inc_tax);
CREATE INDEX IF NOT EXISTS idx_cs_ship_addr_sk ON catalog_sales (cs_ship_addr_sk);
CREATE INDEX IF NOT EXISTS idx_cs_ship_cdemo_sk ON catalog_sales (cs_ship_cdemo_sk);
CREATE INDEX IF NOT EXISTS idx_cs_ship_customer_sk ON catalog_sales (cs_ship_customer_sk);
CREATE INDEX IF NOT EXISTS idx_cs_ship_date_sk ON catalog_sales (cs_ship_date_sk);
CREATE INDEX IF NOT EXISTS idx_cs_ship_hdemo_sk ON catalog_sales (cs_ship_hdemo_sk);
CREATE INDEX IF NOT EXISTS idx_cs_ship_mode_sk ON catalog_sales (cs_ship_mode_sk);
CREATE INDEX IF NOT EXISTS idx_cs_sold_date_ext_price ON catalog_sales (cs_sold_date_sk, cs_ext_sales_price);
CREATE INDEX IF NOT EXISTS idx_cs_sold_date_sk ON catalog_sales (cs_sold_date_sk);
CREATE INDEX IF NOT EXISTS idx_cs_sold_time_sk ON catalog_sales (cs_sold_time_sk);
CREATE INDEX IF NOT EXISTS idx_cs_warehouse_sk ON catalog_sales (cs_warehouse_sk);

-- customer  (6 indexes)
CREATE INDEX IF NOT EXISTS idx_c_addr ON customer (c_current_addr_sk);
CREATE INDEX IF NOT EXISTS idx_c_current_addr_sk ON customer (c_current_addr_sk);
CREATE INDEX IF NOT EXISTS idx_c_current_cdemo_sk ON customer (c_current_cdemo_sk);
CREATE INDEX IF NOT EXISTS idx_c_current_hdemo_sk ON customer (c_current_hdemo_sk);
CREATE INDEX IF NOT EXISTS idx_c_first_sales_date_sk ON customer (c_first_sales_date_sk);
CREATE INDEX IF NOT EXISTS idx_c_first_shipto_date_sk ON customer (c_first_shipto_date_sk);

-- customer_address  (2 indexes)
CREATE INDEX IF NOT EXISTS idx_ca_gmt ON customer_address (ca_gmt_offset);
CREATE INDEX IF NOT EXISTS idx_customer_address_1 ON customer_address (ca_state, ca_country);

-- customer_demographics  (3 indexes)
CREATE INDEX IF NOT EXISTS idx_cd_demo_sk_marital_status ON customer_demographics (cd_demo_sk, cd_marital_status);
CREATE INDEX IF NOT EXISTS idx_cd_filter_sk ON customer_demographics (cd_gender, cd_marital_status, cd_education_status, cd_demo_sk);
CREATE INDEX IF NOT EXISTS idx_customer_demographics_1 ON customer_demographics (cd_marital_status, cd_education_status);

-- date_dim  (11 indexes)
CREATE INDEX IF NOT EXISTS idx_date_dim_d_date ON date_dim (d_date);
CREATE INDEX IF NOT EXISTS idx_date_dim_d_date_year ON date_dim (d_date_sk, d_year, d_date);
CREATE INDEX IF NOT EXISTS idx_date_dim_d_month_seq ON date_dim (d_date_sk, d_month_seq);
CREATE INDEX IF NOT EXISTS idx_date_month_date_sk ON date_dim (d_month_seq, d_date_sk);
CREATE INDEX IF NOT EXISTS idx_date_year_moy ON date_dim (d_year, d_moy);
CREATE INDEX IF NOT EXISTS idx_date_year_sk ON date_dim (d_year, d_date_sk);
CREATE INDEX IF NOT EXISTS idx_date_year_sk_day ON date_dim (d_year, d_date_sk, d_day_name);
CREATE INDEX IF NOT EXISTS idx_date_ym ON date_dim (d_year, d_moy, d_date_sk);
CREATE INDEX IF NOT EXISTS idx_dd_month_seq ON date_dim (d_month_seq);
CREATE INDEX IF NOT EXISTS idx_dd_week_seq ON date_dim (d_week_seq);
CREATE INDEX IF NOT EXISTS inx_date_dim_year ON date_dim (d_year);

-- household_demographics  (2 indexes)
CREATE INDEX IF NOT EXISTS idx_hd_demo_sk_buy_potential ON household_demographics (hd_demo_sk, hd_buy_potential);
CREATE INDEX IF NOT EXISTS idx_hd_income_band_sk ON household_demographics (hd_income_band_sk);

-- inventory  (4 indexes)
CREATE INDEX IF NOT EXISTS idx_inv_date_sk ON inventory (inv_date_sk);
CREATE INDEX IF NOT EXISTS idx_inv_item_date_sk ON inventory (inv_item_sk, inv_date_sk, inv_quantity_on_hand);
CREATE INDEX IF NOT EXISTS idx_inv_item_sk ON inventory (inv_item_sk);
CREATE INDEX IF NOT EXISTS idx_inv_warehouse_sk ON inventory (inv_warehouse_sk);

-- item  (5 indexes)
CREATE INDEX IF NOT EXISTS idx_item_1 ON item (i_category);
CREATE INDEX IF NOT EXISTS idx_item_2 ON item (i_category, i_current_price);
CREATE INDEX IF NOT EXISTS idx_item_cat ON item (i_category);
CREATE INDEX IF NOT EXISTS idx_item_category_id ON item (i_category, i_item_id);
CREATE INDEX IF NOT EXISTS idx_item_price ON item (i_current_price);

-- promotion  (3 indexes)
CREATE INDEX IF NOT EXISTS idx_p_end_date_sk ON promotion (p_end_date_sk);
CREATE INDEX IF NOT EXISTS idx_p_item_sk ON promotion (p_item_sk);
CREATE INDEX IF NOT EXISTS idx_p_start_date_sk ON promotion (p_start_date_sk);

-- store  (2 indexes)
CREATE INDEX IF NOT EXISTS idx_store_gmt ON store (s_gmt_offset);
CREATE INDEX IF NOT EXISTS idx_s_closed_date_sk ON store (s_closed_date_sk);

-- store_returns  (10 indexes)
CREATE INDEX IF NOT EXISTS idx_sr_addr_sk ON store_returns (sr_addr_sk);
CREATE INDEX IF NOT EXISTS idx_sr_cdemo_sk ON store_returns (sr_cdemo_sk);
CREATE INDEX IF NOT EXISTS idx_sr_customer_sk ON store_returns (sr_customer_sk);
CREATE INDEX IF NOT EXISTS idx_sr_hdemo_sk ON store_returns (sr_hdemo_sk);
CREATE INDEX IF NOT EXISTS idx_sr_item_sk ON store_returns (sr_item_sk);
CREATE INDEX IF NOT EXISTS idx_sr_reason_sk ON store_returns (sr_reason_sk);
CREATE INDEX IF NOT EXISTS idx_sr_returned_date_sk ON store_returns (sr_returned_date_sk);
CREATE INDEX IF NOT EXISTS idx_sr_return_time_sk ON store_returns (sr_return_time_sk);
CREATE INDEX IF NOT EXISTS idx_sr_store_sk ON store_returns (sr_store_sk);
CREATE INDEX IF NOT EXISTS idx_sr_ticket_number ON store_returns (sr_ticket_number);

-- store_sales  (26 indexes)
CREATE INDEX IF NOT EXISTS idx_ss_addr_sk ON store_sales (ss_addr_sk);
CREATE INDEX IF NOT EXISTS idx_ss_cdemo_sk ON store_sales (ss_cdemo_sk);
CREATE INDEX IF NOT EXISTS idx_ss_customer_sk ON store_sales (ss_customer_sk);
CREATE INDEX IF NOT EXISTS idx_ss_cust_date ON store_sales (ss_customer_sk, ss_sold_date_sk);
CREATE INDEX IF NOT EXISTS idx_ss_date_addr_item_price ON store_sales (ss_sold_date_sk, ss_addr_sk, ss_item_sk, ss_ext_sales_price);
CREATE INDEX IF NOT EXISTS idx_ss_date_cust ON store_sales (ss_sold_date_sk, ss_customer_sk);
CREATE INDEX IF NOT EXISTS idx_ss_date_item_store_cover ON store_sales (ss_sold_date_sk, ss_item_sk, ss_store_sk, ss_sales_price);
CREATE INDEX IF NOT EXISTS idx_ss_date_store_price ON store_sales (ss_sold_date_sk, ss_store_sk, ss_sales_price);
CREATE INDEX IF NOT EXISTS idx_ss_date_store_profit ON store_sales (ss_sold_date_sk, ss_store_sk, ss_net_profit, ss_ext_sales_price);
CREATE INDEX IF NOT EXISTS idx_ss_hdemo_sk ON store_sales (ss_hdemo_sk);
CREATE INDEX IF NOT EXISTS idx_ss_item_sk ON store_sales (ss_item_sk);
CREATE INDEX IF NOT EXISTS idx_ss_promo_sk ON store_sales (ss_promo_sk);
CREATE INDEX IF NOT EXISTS idx_ss_q61 ON store_sales (ss_store_sk, ss_sold_date_sk, ss_item_sk, ss_customer_sk, ss_promo_sk, ss_ext_sales_price);
CREATE INDEX IF NOT EXISTS idx_ss_q78 ON store_sales (ss_sold_date_sk, ss_item_sk, ss_customer_sk, ss_ticket_number, ss_quantity, ss_wholesale_cost, ss_sales_price);
CREATE INDEX IF NOT EXISTS idx_ss_qty_cover ON store_sales (ss_quantity, ss_ext_list_price, ss_net_profit);
CREATE INDEX IF NOT EXISTS idx_ss_qty_q28 ON store_sales (ss_quantity, ss_list_price, ss_coupon_amt, ss_wholesale_cost);
CREATE INDEX IF NOT EXISTS idx_ss_sold_date_sk ON store_sales (ss_sold_date_sk);
CREATE INDEX IF NOT EXISTS idx_ss_sold_date_sk_store_sales_price ON store_sales (ss_sold_date_sk, ss_store_sk, ss_sales_price);
CREATE INDEX IF NOT EXISTS idx_ss_sold_time_sk ON store_sales (ss_sold_time_sk);
CREATE INDEX IF NOT EXISTS idx_ss_store_hdemo_time ON store_sales (ss_store_sk, ss_hdemo_sk, ss_sold_time_sk);
CREATE INDEX IF NOT EXISTS idx_ss_store_sk ON store_sales (ss_store_sk);
CREATE INDEX IF NOT EXISTS idx_ss_ticket_number ON store_sales (ss_ticket_number);
CREATE INDEX IF NOT EXISTS idx_store_sales_1 ON store_sales (ss_sales_price, ss_net_profit);
CREATE INDEX IF NOT EXISTS idx_store_sales_2 ON store_sales (ss_quantity, ss_ext_sales_price, ss_net_profit);
CREATE INDEX IF NOT EXISTS idx_store_sales_quantity_1 ON store_sales (ss_quantity);
CREATE INDEX IF NOT EXISTS idx_store_sales_quantity_2 ON store_sales (ss_quantity, ss_list_price, ss_coupon_amt, ss_wholesale_cost);

-- web_page  (3 indexes)
CREATE INDEX IF NOT EXISTS idx_wp_access_date_sk ON web_page (wp_access_date_sk);
CREATE INDEX IF NOT EXISTS idx_wp_creation_date_sk ON web_page (wp_creation_date_sk);
CREATE INDEX IF NOT EXISTS idx_wp_customer_sk ON web_page (wp_customer_sk);

-- web_returns  (14 indexes)
CREATE INDEX IF NOT EXISTS idx_wr_item_sk ON web_returns (wr_item_sk);
CREATE INDEX IF NOT EXISTS idx_wr_order_number ON web_returns (wr_order_number);
CREATE INDEX IF NOT EXISTS idx_wr_reason_sk ON web_returns (wr_reason_sk);
CREATE INDEX IF NOT EXISTS idx_wr_refunded_addr_sk ON web_returns (wr_refunded_addr_sk);
CREATE INDEX IF NOT EXISTS idx_wr_refunded_cdemo_sk ON web_returns (wr_refunded_cdemo_sk);
CREATE INDEX IF NOT EXISTS idx_wr_refunded_customer_sk ON web_returns (wr_refunded_customer_sk);
CREATE INDEX IF NOT EXISTS idx_wr_refunded_hdemo_sk ON web_returns (wr_refunded_hdemo_sk);
CREATE INDEX IF NOT EXISTS idx_wr_returned_date_sk ON web_returns (wr_returned_date_sk);
CREATE INDEX IF NOT EXISTS idx_wr_returned_time_sk ON web_returns (wr_returned_time_sk);
CREATE INDEX IF NOT EXISTS idx_wr_returning_addr_sk ON web_returns (wr_returning_addr_sk);
CREATE INDEX IF NOT EXISTS idx_wr_returning_cdemo_sk ON web_returns (wr_returning_cdemo_sk);
CREATE INDEX IF NOT EXISTS idx_wr_returning_customer_sk ON web_returns (wr_returning_customer_sk);
CREATE INDEX IF NOT EXISTS idx_wr_returning_hdemo_sk ON web_returns (wr_returning_hdemo_sk);
CREATE INDEX IF NOT EXISTS idx_wr_web_page_sk ON web_returns (wr_web_page_sk);

-- web_sales  (26 indexes)
CREATE INDEX IF NOT EXISTS idx_ws_bill_addr_sk ON web_sales (ws_bill_addr_sk);
CREATE INDEX IF NOT EXISTS idx_ws_bill_cdemo_sk ON web_sales (ws_bill_cdemo_sk);
CREATE INDEX IF NOT EXISTS idx_ws_bill_customer_sk ON web_sales (ws_bill_customer_sk);
CREATE INDEX IF NOT EXISTS idx_ws_bill_hdemo_sk ON web_sales (ws_bill_hdemo_sk);
CREATE INDEX IF NOT EXISTS idx_ws_cust_date ON web_sales (ws_bill_customer_sk, ws_sold_date_sk);
CREATE INDEX IF NOT EXISTS idx_ws_date_addr_item_price ON web_sales (ws_sold_date_sk, ws_bill_addr_sk, ws_item_sk, ws_ext_sales_price);
CREATE INDEX IF NOT EXISTS idx_ws_date_cust ON web_sales (ws_sold_date_sk, ws_bill_customer_sk);
CREATE INDEX IF NOT EXISTS idx_ws_date_item_cust ON web_sales (ws_sold_date_sk, ws_item_sk, ws_bill_customer_sk, ws_net_paid);
CREATE INDEX IF NOT EXISTS idx_ws_date_item_paid ON web_sales (ws_sold_date_sk, ws_item_sk, ws_net_paid);
CREATE INDEX IF NOT EXISTS idx_ws_date_item_price ON web_sales (ws_sold_date_sk, ws_item_sk, ws_ext_sales_price);
CREATE INDEX IF NOT EXISTS idx_ws_item_sk ON web_sales (ws_item_sk);
CREATE INDEX IF NOT EXISTS idx_ws_order_number ON web_sales (ws_order_number);
CREATE INDEX IF NOT EXISTS idx_ws_promo_sk ON web_sales (ws_promo_sk);
CREATE INDEX IF NOT EXISTS idx_ws_q66 ON web_sales (ws_ship_mode_sk, ws_sold_date_sk, ws_sold_time_sk, ws_warehouse_sk, ws_sales_price, ws_quantity, ws_net_paid_inc_ship);
CREATE INDEX IF NOT EXISTS idx_ws_ship_addr_sk ON web_sales (ws_ship_addr_sk);
CREATE INDEX IF NOT EXISTS idx_ws_ship_cdemo_sk ON web_sales (ws_ship_cdemo_sk);
CREATE INDEX IF NOT EXISTS idx_ws_ship_customer_sk ON web_sales (ws_ship_customer_sk);
CREATE INDEX IF NOT EXISTS idx_ws_ship_date_sk ON web_sales (ws_ship_date_sk);
CREATE INDEX IF NOT EXISTS idx_ws_ship_hdemo_sk ON web_sales (ws_ship_hdemo_sk);
CREATE INDEX IF NOT EXISTS idx_ws_ship_mode_sk ON web_sales (ws_ship_mode_sk);
CREATE INDEX IF NOT EXISTS idx_ws_sold_date_ext_price ON web_sales (ws_sold_date_sk, ws_ext_sales_price);
CREATE INDEX IF NOT EXISTS idx_ws_sold_date_sk ON web_sales (ws_sold_date_sk);
CREATE INDEX IF NOT EXISTS idx_ws_sold_time_sk ON web_sales (ws_sold_time_sk);
CREATE INDEX IF NOT EXISTS idx_ws_warehouse_sk ON web_sales (ws_warehouse_sk);
CREATE INDEX IF NOT EXISTS idx_ws_web_page_sk ON web_sales (ws_web_page_sk);
CREATE INDEX IF NOT EXISTS idx_ws_web_site_sk ON web_sales (ws_web_site_sk);

-- web_site  (2 indexes)
CREATE INDEX IF NOT EXISTS idx_web_close_date_sk ON web_site (web_close_date_sk);
CREATE INDEX IF NOT EXISTS idx_web_open_date_sk ON web_site (web_open_date_sk);

-- Indexes that were IGNORED when this file was generated.
-- Restoring reproduces that state rather than silently
-- re-enabling something switched off deliberately.

ALTER TABLE store_sales ALTER INDEX idx_ss_date_store_profit IGNORED;

ANALYZE TABLE call_center, catalog_page, catalog_returns, catalog_sales, customer, customer_address, customer_demographics, date_dim, household_demographics, inventory, item, promotion, store, store_returns, store_sales, web_page, web_returns, web_sales, web_site;
