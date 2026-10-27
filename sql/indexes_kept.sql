-- ========================================================================
--  The index set a new database should build.
--
--  Generated 2026-10-27 01:12 by scripts/build-index-set.py.
--  37 secondary indexes kept, 130 left out.
--
--  An index is here if either scale factor read it while running the
--  40 tier-4/5 queries, or if it was adopted on direct measurement.
--  What was left out, and why, is in sql/dropped_indexes.md.
--
--  Nothing is lost: sql/all_indexes.sql still holds every index this
--  project has ever built, and restores them in one command.
-- ========================================================================

SET SESSION alter_algorithm='INPLACE';

-- catalog_returns  (1)
CREATE INDEX IF NOT EXISTS idx_cr_item_sk ON catalog_returns (cr_item_sk);

-- catalog_sales  (7)
CREATE INDEX IF NOT EXISTS idx_cs_date_addr_item_price ON catalog_sales (cs_sold_date_sk, cs_bill_addr_sk, cs_item_sk, cs_ext_sales_price);
CREATE INDEX IF NOT EXISTS idx_cs_date_cover ON catalog_sales (cs_sold_date_sk, cs_bill_cdemo_sk, cs_item_sk, cs_promo_sk, cs_quantity, cs_list_price, cs_coupon_amt, cs_sales_price);
CREATE INDEX IF NOT EXISTS idx_cs_date_cust ON catalog_sales (cs_sold_date_sk, cs_ship_customer_sk);
CREATE INDEX IF NOT EXISTS idx_cs_date_customer ON catalog_sales (cs_sold_date_sk, cs_bill_customer_sk);
CREATE INDEX IF NOT EXISTS idx_cs_item_sk ON catalog_sales (cs_item_sk);
CREATE INDEX IF NOT EXISTS idx_cs_q66 ON catalog_sales (cs_ship_mode_sk, cs_sold_date_sk, cs_sold_time_sk, cs_warehouse_sk, cs_ext_sales_price, cs_quantity, cs_net_paid_inc_tax);
CREATE INDEX IF NOT EXISTS idx_cs_sold_date_ext_price ON catalog_sales (cs_sold_date_sk, cs_ext_sales_price);

-- customer_address  (1)
CREATE INDEX IF NOT EXISTS idx_ca_gmt ON customer_address (ca_gmt_offset);

-- customer_demographics  (2)
CREATE INDEX IF NOT EXISTS idx_cd_demo_sk_marital_status ON customer_demographics (cd_demo_sk, cd_marital_status);
CREATE INDEX IF NOT EXISTS idx_cd_filter_sk ON customer_demographics (cd_gender, cd_marital_status, cd_education_status, cd_demo_sk);

-- date_dim  (8)
CREATE INDEX IF NOT EXISTS idx_date_dim_d_date ON date_dim (d_date);
CREATE INDEX IF NOT EXISTS idx_date_dim_d_date_year ON date_dim (d_date_sk, d_year, d_date);
CREATE INDEX IF NOT EXISTS idx_date_dim_d_month_seq ON date_dim (d_date_sk, d_month_seq);
CREATE INDEX IF NOT EXISTS idx_date_year_moy ON date_dim (d_year, d_moy);
CREATE INDEX IF NOT EXISTS idx_date_year_sk_day ON date_dim (d_year, d_date_sk, d_day_name);
CREATE INDEX IF NOT EXISTS idx_dd_month_seq ON date_dim (d_month_seq);
CREATE INDEX IF NOT EXISTS idx_dd_week_seq ON date_dim (d_week_seq);
CREATE INDEX IF NOT EXISTS inx_date_dim_year ON date_dim (d_year);

-- household_demographics  (1)
CREATE INDEX IF NOT EXISTS idx_hd_demo_sk_buy_potential ON household_demographics (hd_demo_sk, hd_buy_potential);

-- inventory  (1)
CREATE INDEX IF NOT EXISTS idx_inv_item_date_sk ON inventory (inv_item_sk, inv_date_sk, inv_quantity_on_hand);

-- item  (1)
CREATE INDEX IF NOT EXISTS idx_item_1 ON item (i_category);

-- store_returns  (1)
CREATE INDEX IF NOT EXISTS idx_sr_item_sk ON store_returns (sr_item_sk);

-- store_sales  (7)
CREATE INDEX IF NOT EXISTS idx_ss_date_addr_item_price ON store_sales (ss_sold_date_sk, ss_addr_sk, ss_item_sk, ss_ext_sales_price);
CREATE INDEX IF NOT EXISTS idx_ss_date_cust ON store_sales (ss_sold_date_sk, ss_customer_sk);
CREATE INDEX IF NOT EXISTS idx_ss_date_item_store_cover ON store_sales (ss_sold_date_sk, ss_item_sk, ss_store_sk, ss_sales_price);
CREATE INDEX IF NOT EXISTS idx_ss_item_sk ON store_sales (ss_item_sk);
CREATE INDEX IF NOT EXISTS idx_ss_q78 ON store_sales (ss_sold_date_sk, ss_item_sk, ss_customer_sk, ss_ticket_number, ss_quantity, ss_wholesale_cost, ss_sales_price);
CREATE INDEX IF NOT EXISTS idx_ss_sold_date_sk ON store_sales (ss_sold_date_sk);
CREATE INDEX IF NOT EXISTS idx_ss_store_hdemo_time ON store_sales (ss_store_sk, ss_hdemo_sk, ss_sold_time_sk);

-- web_returns  (1)
CREATE INDEX IF NOT EXISTS idx_wr_item_sk ON web_returns (wr_item_sk);

-- web_sales  (6)
CREATE INDEX IF NOT EXISTS idx_ws_date_addr_item_price ON web_sales (ws_sold_date_sk, ws_bill_addr_sk, ws_item_sk, ws_ext_sales_price);
CREATE INDEX IF NOT EXISTS idx_ws_date_cust ON web_sales (ws_sold_date_sk, ws_bill_customer_sk);
CREATE INDEX IF NOT EXISTS idx_ws_date_item_cust ON web_sales (ws_sold_date_sk, ws_item_sk, ws_bill_customer_sk, ws_net_paid);
CREATE INDEX IF NOT EXISTS idx_ws_date_item_price ON web_sales (ws_sold_date_sk, ws_item_sk, ws_ext_sales_price);
CREATE INDEX IF NOT EXISTS idx_ws_q66 ON web_sales (ws_ship_mode_sk, ws_sold_date_sk, ws_sold_time_sk, ws_warehouse_sk, ws_sales_price, ws_quantity, ws_net_paid_inc_ship);
CREATE INDEX IF NOT EXISTS idx_ws_sold_date_ext_price ON web_sales (ws_sold_date_sk, ws_ext_sales_price);

ANALYZE TABLE catalog_returns, catalog_sales, customer_address, customer_demographics, date_dim, household_demographics, inventory, item, store_returns, store_sales, web_returns, web_sales;
