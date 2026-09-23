-- ---------------------------------------------------------------------------
--  TPC-DS v4.0.0 referential integrity for MariaDB   (OPTIONAL)
--
--  Ported from tools/tpcds_ri.sql.  Clause 2.5.1.8 makes primary and foreign
--  keys optional; Clause 2.5.4.1 limits constraints to PK, FK and NOT NULL.
--
--  Two constraints in tpcds_ri.sql were DROPPED because they name columns that
--  do not exist in the Clause 2.3/2.4 schema:
--      cp_p   catalog_page(cp_promo_id) -> promotion(p_promo_sk)  --  column catalog_page.cp_promo_id does not exist in the schema
--      cr_d2  catalog_returns(cr_ship_date_sk) -> date_dim(d_date_sk)  --  column catalog_returns.cr_ship_date_sk does not exist in the schema
--
--  Three constraint names were duplicated within one table, which MariaDB
--  rejects.  The second use of each was suffixed with _2:
--      catalog_returns.cr_i -> cr_i_2   (on cr_returned_time_sk)
--      web_returns.wr_ret_cd -> wr_ret_cd_2   (on wr_returning_hdemo_sk)
--      web_sales.ws_b_cd -> ws_b_cd_2   (on ws_bill_hdemo_sk)
--
--  COST WARNING: InnoDB creates a secondary index for every foreign key that
--  does not already have one.  These 107 constraints add ~107 indexes and will
--  roughly double the size of the database and slow bulk loads considerably.
--  Load the data FIRST, then run this script.  Skip it entirely if you only
--  want to run the TPC-DS query set.
-- ---------------------------------------------------------------------------

USE tpcds;


-- call_center ------------------------------------------------------------
ALTER TABLE call_center ADD CONSTRAINT cc_d1 FOREIGN KEY (cc_closed_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE call_center ADD CONSTRAINT cc_d2 FOREIGN KEY (cc_open_date_sk) REFERENCES date_dim (d_date_sk);

-- catalog_page -----------------------------------------------------------
ALTER TABLE catalog_page ADD CONSTRAINT cp_d1 FOREIGN KEY (cp_end_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE catalog_page ADD CONSTRAINT cp_d2 FOREIGN KEY (cp_start_date_sk) REFERENCES date_dim (d_date_sk);

-- catalog_returns --------------------------------------------------------
ALTER TABLE catalog_returns ADD CONSTRAINT cr_cc FOREIGN KEY (cr_call_center_sk) REFERENCES call_center (cc_call_center_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_cp FOREIGN KEY (cr_catalog_page_sk) REFERENCES catalog_page (cp_catalog_page_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_i FOREIGN KEY (cr_item_sk) REFERENCES item (i_item_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_r FOREIGN KEY (cr_reason_sk) REFERENCES reason (r_reason_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_a1 FOREIGN KEY (cr_refunded_addr_sk) REFERENCES customer_address (ca_address_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_cd1 FOREIGN KEY (cr_refunded_cdemo_sk) REFERENCES customer_demographics (cd_demo_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_c1 FOREIGN KEY (cr_refunded_customer_sk) REFERENCES customer (c_customer_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_hd1 FOREIGN KEY (cr_refunded_hdemo_sk) REFERENCES household_demographics (hd_demo_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_d1 FOREIGN KEY (cr_returned_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_i_2 FOREIGN KEY (cr_returned_time_sk) REFERENCES time_dim (t_time_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_a2 FOREIGN KEY (cr_returning_addr_sk) REFERENCES customer_address (ca_address_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_cd2 FOREIGN KEY (cr_returning_cdemo_sk) REFERENCES customer_demographics (cd_demo_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_c2 FOREIGN KEY (cr_returning_customer_sk) REFERENCES customer (c_customer_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_hd2 FOREIGN KEY (cr_returning_hdemo_sk) REFERENCES household_demographics (hd_demo_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_sm FOREIGN KEY (cr_ship_mode_sk) REFERENCES ship_mode (sm_ship_mode_sk);
ALTER TABLE catalog_returns ADD CONSTRAINT cr_w2 FOREIGN KEY (cr_warehouse_sk) REFERENCES warehouse (w_warehouse_sk);

-- catalog_sales ----------------------------------------------------------
ALTER TABLE catalog_sales ADD CONSTRAINT cs_b_a FOREIGN KEY (cs_bill_addr_sk) REFERENCES customer_address (ca_address_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_b_cd FOREIGN KEY (cs_bill_cdemo_sk) REFERENCES customer_demographics (cd_demo_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_b_c FOREIGN KEY (cs_bill_customer_sk) REFERENCES customer (c_customer_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_b_hd FOREIGN KEY (cs_bill_hdemo_sk) REFERENCES household_demographics (hd_demo_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_cc FOREIGN KEY (cs_call_center_sk) REFERENCES call_center (cc_call_center_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_cp FOREIGN KEY (cs_catalog_page_sk) REFERENCES catalog_page (cp_catalog_page_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_i FOREIGN KEY (cs_item_sk) REFERENCES item (i_item_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_p FOREIGN KEY (cs_promo_sk) REFERENCES promotion (p_promo_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_s_a FOREIGN KEY (cs_ship_addr_sk) REFERENCES customer_address (ca_address_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_s_cd FOREIGN KEY (cs_ship_cdemo_sk) REFERENCES customer_demographics (cd_demo_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_s_c FOREIGN KEY (cs_ship_customer_sk) REFERENCES customer (c_customer_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_d1 FOREIGN KEY (cs_ship_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_s_hd FOREIGN KEY (cs_ship_hdemo_sk) REFERENCES household_demographics (hd_demo_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_sm FOREIGN KEY (cs_ship_mode_sk) REFERENCES ship_mode (sm_ship_mode_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_d2 FOREIGN KEY (cs_sold_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_t FOREIGN KEY (cs_sold_time_sk) REFERENCES time_dim (t_time_sk);
ALTER TABLE catalog_sales ADD CONSTRAINT cs_w FOREIGN KEY (cs_warehouse_sk) REFERENCES warehouse (w_warehouse_sk);

-- customer ---------------------------------------------------------------
ALTER TABLE customer ADD CONSTRAINT c_a FOREIGN KEY (c_current_addr_sk) REFERENCES customer_address (ca_address_sk);
ALTER TABLE customer ADD CONSTRAINT c_cd FOREIGN KEY (c_current_cdemo_sk) REFERENCES customer_demographics (cd_demo_sk);
ALTER TABLE customer ADD CONSTRAINT c_hd FOREIGN KEY (c_current_hdemo_sk) REFERENCES household_demographics (hd_demo_sk);
ALTER TABLE customer ADD CONSTRAINT c_fsd FOREIGN KEY (c_first_sales_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE customer ADD CONSTRAINT c_fsd2 FOREIGN KEY (c_first_shipto_date_sk) REFERENCES date_dim (d_date_sk);

-- household_demographics -------------------------------------------------
ALTER TABLE household_demographics ADD CONSTRAINT hd_ib FOREIGN KEY (hd_income_band_sk) REFERENCES income_band (ib_income_band_sk);

-- inventory --------------------------------------------------------------
ALTER TABLE inventory ADD CONSTRAINT inv_d FOREIGN KEY (inv_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE inventory ADD CONSTRAINT inv_i FOREIGN KEY (inv_item_sk) REFERENCES item (i_item_sk);
ALTER TABLE inventory ADD CONSTRAINT inv_w FOREIGN KEY (inv_warehouse_sk) REFERENCES warehouse (w_warehouse_sk);

-- promotion --------------------------------------------------------------
ALTER TABLE promotion ADD CONSTRAINT p_end_date FOREIGN KEY (p_end_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE promotion ADD CONSTRAINT p_i FOREIGN KEY (p_item_sk) REFERENCES item (i_item_sk);
ALTER TABLE promotion ADD CONSTRAINT p_start_date FOREIGN KEY (p_start_date_sk) REFERENCES date_dim (d_date_sk);

-- store ------------------------------------------------------------------
ALTER TABLE store ADD CONSTRAINT s_close_date FOREIGN KEY (s_closed_date_sk) REFERENCES date_dim (d_date_sk);

-- store_returns ----------------------------------------------------------
ALTER TABLE store_returns ADD CONSTRAINT sr_a FOREIGN KEY (sr_addr_sk) REFERENCES customer_address (ca_address_sk);
ALTER TABLE store_returns ADD CONSTRAINT sr_cd FOREIGN KEY (sr_cdemo_sk) REFERENCES customer_demographics (cd_demo_sk);
ALTER TABLE store_returns ADD CONSTRAINT sr_c FOREIGN KEY (sr_customer_sk) REFERENCES customer (c_customer_sk);
ALTER TABLE store_returns ADD CONSTRAINT sr_hd FOREIGN KEY (sr_hdemo_sk) REFERENCES household_demographics (hd_demo_sk);
ALTER TABLE store_returns ADD CONSTRAINT sr_i FOREIGN KEY (sr_item_sk) REFERENCES item (i_item_sk);
ALTER TABLE store_returns ADD CONSTRAINT sr_r FOREIGN KEY (sr_reason_sk) REFERENCES reason (r_reason_sk);
ALTER TABLE store_returns ADD CONSTRAINT sr_ret_d FOREIGN KEY (sr_returned_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE store_returns ADD CONSTRAINT sr_t FOREIGN KEY (sr_return_time_sk) REFERENCES time_dim (t_time_sk);
ALTER TABLE store_returns ADD CONSTRAINT sr_s FOREIGN KEY (sr_store_sk) REFERENCES store (s_store_sk);

-- store_sales ------------------------------------------------------------
ALTER TABLE store_sales ADD CONSTRAINT ss_a FOREIGN KEY (ss_addr_sk) REFERENCES customer_address (ca_address_sk);
ALTER TABLE store_sales ADD CONSTRAINT ss_cd FOREIGN KEY (ss_cdemo_sk) REFERENCES customer_demographics (cd_demo_sk);
ALTER TABLE store_sales ADD CONSTRAINT ss_c FOREIGN KEY (ss_customer_sk) REFERENCES customer (c_customer_sk);
ALTER TABLE store_sales ADD CONSTRAINT ss_hd FOREIGN KEY (ss_hdemo_sk) REFERENCES household_demographics (hd_demo_sk);
ALTER TABLE store_sales ADD CONSTRAINT ss_i FOREIGN KEY (ss_item_sk) REFERENCES item (i_item_sk);
ALTER TABLE store_sales ADD CONSTRAINT ss_p FOREIGN KEY (ss_promo_sk) REFERENCES promotion (p_promo_sk);
ALTER TABLE store_sales ADD CONSTRAINT ss_d FOREIGN KEY (ss_sold_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE store_sales ADD CONSTRAINT ss_t FOREIGN KEY (ss_sold_time_sk) REFERENCES time_dim (t_time_sk);
ALTER TABLE store_sales ADD CONSTRAINT ss_s FOREIGN KEY (ss_store_sk) REFERENCES store (s_store_sk);

-- web_page ---------------------------------------------------------------
ALTER TABLE web_page ADD CONSTRAINT wp_ad FOREIGN KEY (wp_access_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE web_page ADD CONSTRAINT wp_cd FOREIGN KEY (wp_creation_date_sk) REFERENCES date_dim (d_date_sk);

-- web_returns ------------------------------------------------------------
ALTER TABLE web_returns ADD CONSTRAINT wr_i FOREIGN KEY (wr_item_sk) REFERENCES item (i_item_sk);
ALTER TABLE web_returns ADD CONSTRAINT wr_r FOREIGN KEY (wr_reason_sk) REFERENCES reason (r_reason_sk);
ALTER TABLE web_returns ADD CONSTRAINT wr_ref_a FOREIGN KEY (wr_refunded_addr_sk) REFERENCES customer_address (ca_address_sk);
ALTER TABLE web_returns ADD CONSTRAINT wr_ref_cd FOREIGN KEY (wr_refunded_cdemo_sk) REFERENCES customer_demographics (cd_demo_sk);
ALTER TABLE web_returns ADD CONSTRAINT wr_ref_c FOREIGN KEY (wr_refunded_customer_sk) REFERENCES customer (c_customer_sk);
ALTER TABLE web_returns ADD CONSTRAINT wr_ref_hd FOREIGN KEY (wr_refunded_hdemo_sk) REFERENCES household_demographics (hd_demo_sk);
ALTER TABLE web_returns ADD CONSTRAINT wr_ret_d FOREIGN KEY (wr_returned_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE web_returns ADD CONSTRAINT wr_ret_t FOREIGN KEY (wr_returned_time_sk) REFERENCES time_dim (t_time_sk);
ALTER TABLE web_returns ADD CONSTRAINT wr_ret_a FOREIGN KEY (wr_returning_addr_sk) REFERENCES customer_address (ca_address_sk);
ALTER TABLE web_returns ADD CONSTRAINT wr_ret_cd FOREIGN KEY (wr_returning_cdemo_sk) REFERENCES customer_demographics (cd_demo_sk);
ALTER TABLE web_returns ADD CONSTRAINT wr_ret_c FOREIGN KEY (wr_returning_customer_sk) REFERENCES customer (c_customer_sk);
ALTER TABLE web_returns ADD CONSTRAINT wr_ret_cd_2 FOREIGN KEY (wr_returning_hdemo_sk) REFERENCES household_demographics (hd_demo_sk);
ALTER TABLE web_returns ADD CONSTRAINT wr_wp FOREIGN KEY (wr_web_page_sk) REFERENCES web_page (wp_web_page_sk);

-- web_sales --------------------------------------------------------------
ALTER TABLE web_sales ADD CONSTRAINT ws_b_a FOREIGN KEY (ws_bill_addr_sk) REFERENCES customer_address (ca_address_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_b_cd FOREIGN KEY (ws_bill_cdemo_sk) REFERENCES customer_demographics (cd_demo_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_b_c FOREIGN KEY (ws_bill_customer_sk) REFERENCES customer (c_customer_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_b_cd_2 FOREIGN KEY (ws_bill_hdemo_sk) REFERENCES household_demographics (hd_demo_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_i FOREIGN KEY (ws_item_sk) REFERENCES item (i_item_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_p FOREIGN KEY (ws_promo_sk) REFERENCES promotion (p_promo_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_s_a FOREIGN KEY (ws_ship_addr_sk) REFERENCES customer_address (ca_address_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_s_cd FOREIGN KEY (ws_ship_cdemo_sk) REFERENCES customer_demographics (cd_demo_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_s_c FOREIGN KEY (ws_ship_customer_sk) REFERENCES customer (c_customer_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_s_d FOREIGN KEY (ws_ship_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_s_hd FOREIGN KEY (ws_ship_hdemo_sk) REFERENCES household_demographics (hd_demo_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_sm FOREIGN KEY (ws_ship_mode_sk) REFERENCES ship_mode (sm_ship_mode_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_d2 FOREIGN KEY (ws_sold_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_t FOREIGN KEY (ws_sold_time_sk) REFERENCES time_dim (t_time_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_w2 FOREIGN KEY (ws_warehouse_sk) REFERENCES warehouse (w_warehouse_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_wp FOREIGN KEY (ws_web_page_sk) REFERENCES web_page (wp_web_page_sk);
ALTER TABLE web_sales ADD CONSTRAINT ws_ws FOREIGN KEY (ws_web_site_sk) REFERENCES web_site (web_site_sk);

-- web_site ---------------------------------------------------------------
ALTER TABLE web_site ADD CONSTRAINT web_d1 FOREIGN KEY (web_close_date_sk) REFERENCES date_dim (d_date_sk);
ALTER TABLE web_site ADD CONSTRAINT web_d2 FOREIGN KEY (web_open_date_sk) REFERENCES date_dim (d_date_sk);

-- customer ---------------------------------------------------------------
ALTER TABLE customer ADD CONSTRAINT c_d FOREIGN KEY (c_last_review_date_sk) REFERENCES date_dim (d_date_sk);

-- store_returns ----------------------------------------------------------
ALTER TABLE store_returns ADD CONSTRAINT sr_i_tn FOREIGN KEY (sr_item_sk, sr_ticket_number) REFERENCES store_sales (ss_item_sk, ss_ticket_number);

-- catalog_returns --------------------------------------------------------
ALTER TABLE catalog_returns ADD CONSTRAINT cr_i_on FOREIGN KEY (cr_item_sk, cr_order_number) REFERENCES catalog_sales (cs_item_sk, cs_order_number);

-- web_returns ------------------------------------------------------------
ALTER TABLE web_returns ADD CONSTRAINT wr_i_on FOREIGN KEY (wr_item_sk, wr_order_number) REFERENCES web_sales (ws_item_sk, ws_order_number);

-- web_page ---------------------------------------------------------------
ALTER TABLE web_page ADD CONSTRAINT wp_c FOREIGN KEY (wp_customer_sk) REFERENCES customer (c_customer_sk);
