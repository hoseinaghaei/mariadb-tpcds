-- ==========================================================================
--  Every index prescribed by the three optimization efforts, in one place.
--
--  Collected from the .sql and .md files under queries/optimized/ by
--  scanning for live (non-commented) CREATE INDEX statements.
--  Applied together for report/19-three-way-comparison.md, so that all three
--  contributors' queries are measured against one identical index set.
--
--  29 of these existed only on Aysha's machine before this run.
--  Build time: 2m54s at scale factor 1.  Run ANALYZE TABLE afterwards.
--
--  NOTE: idx_ss_date_item_store_cover is INFERRED.  Aysha's q47 does
--  FORCE INDEX on that name but no CREATE for it exists anywhere in the
--  repo; the definition here is what the query needs to be covering.
-- ==========================================================================
SET SESSION alter_algorithm='INPLACE';

CREATE INDEX idx_cs_cust_date_price ON catalog_sales (cs_bill_customer_sk,cs_sold_date_sk,cs_sales_price);
CREATE INDEX idx_cs_price_date_cust ON catalog_sales (cs_sales_price,cs_sold_date_sk,cs_bill_customer_sk);
CREATE INDEX idx_cs_cust_date ON catalog_sales (cs_ship_customer_sk,cs_sold_date_sk);
CREATE INDEX idx_cs_date_addr_item_price ON catalog_sales (cs_sold_date_sk,cs_bill_addr_sk,cs_item_sk,cs_ext_sales_price);
CREATE INDEX idx_cs_date_cover ON catalog_sales (cs_sold_date_sk,cs_bill_cdemo_sk,cs_item_sk,cs_promo_sk,cs_quantity,cs_list_price,cs_coupon_amt,cs_sales_price);
CREATE INDEX idx_cs_date_customer ON catalog_sales (cs_sold_date_sk,cs_bill_customer_sk);
CREATE INDEX idx_cs_sold_date_ext_price ON catalog_sales (cs_sold_date_sk,cs_ext_sales_price);
CREATE INDEX idx_cs_date_cust ON catalog_sales (cs_sold_date_sk,cs_ship_customer_sk);
CREATE INDEX idx_c_addr ON customer (c_current_addr_sk);
CREATE INDEX idx_ca_gmt ON customer_address (ca_gmt_offset);
CREATE INDEX idx_cd_filter_sk ON customer_demographics (cd_gender,cd_marital_status,cd_education_status,cd_demo_sk);
CREATE INDEX idx_date_dim_d_date ON date_dim (d_date);
CREATE INDEX idx_date_dim_d_month_seq ON date_dim (d_date_sk,d_month_seq);
CREATE INDEX idx_dd_month_seq ON date_dim (d_month_seq);
CREATE INDEX idx_date_month_date_sk ON date_dim (d_month_seq,d_date_sk);
CREATE INDEX idx_dd_week_seq ON date_dim (d_week_seq);
CREATE INDEX idx_date_year_sk ON date_dim (d_year,d_date_sk);
CREATE INDEX idx_date_year_sk_day ON date_dim (d_year,d_date_sk,d_day_name);
CREATE INDEX idx_date_ym ON date_dim (d_year,d_moy,d_date_sk);
CREATE INDEX idx_inv_item_date_sk ON inventory (inv_item_sk,inv_date_sk,inv_quantity_on_hand);
CREATE INDEX idx_item_cat ON item (i_category);
CREATE INDEX idx_item_category_id ON item (i_category,i_item_id);
CREATE INDEX idx_item_price ON item (i_current_price);
CREATE INDEX idx_store_gmt ON store (s_gmt_offset);
CREATE INDEX idx_ss_cust_date ON store_sales (ss_customer_sk,ss_sold_date_sk);
CREATE INDEX idx_ss_qty_cover ON store_sales (ss_quantity,ss_ext_list_price,ss_net_profit);
CREATE INDEX idx_ss_qty_q28 ON store_sales (ss_quantity,ss_list_price,ss_coupon_amt,ss_wholesale_cost);
CREATE INDEX idx_ss_date_addr_item_price ON store_sales (ss_sold_date_sk,ss_addr_sk,ss_item_sk,ss_ext_sales_price);
CREATE INDEX idx_ss_date_cust ON store_sales (ss_sold_date_sk,ss_customer_sk);
CREATE INDEX idx_ss_q78 ON store_sales (ss_sold_date_sk,ss_item_sk,ss_customer_sk,ss_ticket_number,ss_quantity,ss_wholesale_cost,ss_sales_price);
CREATE INDEX idx_ss_date_store_price ON store_sales (ss_sold_date_sk,ss_store_sk,ss_sales_price);
CREATE INDEX idx_ss_store_hdemo_time ON store_sales (ss_store_sk,ss_hdemo_sk,ss_sold_time_sk);
CREATE INDEX idx_ss_q61 ON store_sales (ss_store_sk,ss_sold_date_sk,ss_item_sk,ss_customer_sk,ss_promo_sk,ss_ext_sales_price);
CREATE INDEX idx_ws_cust_date ON web_sales (ws_bill_customer_sk,ws_sold_date_sk);
CREATE INDEX idx_ws_date_addr_item_price ON web_sales (ws_sold_date_sk,ws_bill_addr_sk,ws_item_sk,ws_ext_sales_price);
CREATE INDEX idx_ws_date_cust ON web_sales (ws_sold_date_sk,ws_bill_customer_sk);
CREATE INDEX idx_ws_sold_date_ext_price ON web_sales (ws_sold_date_sk,ws_ext_sales_price);
CREATE INDEX idx_ws_date_item_cust ON web_sales (ws_sold_date_sk,ws_item_sk,ws_bill_customer_sk,ws_net_paid);
CREATE INDEX idx_ws_date_item_price ON web_sales (ws_sold_date_sk,ws_item_sk,ws_ext_sales_price);
CREATE INDEX idx_ws_date_item_paid ON web_sales (ws_sold_date_sk,ws_item_sk,ws_net_paid);
CREATE INDEX idx_ss_date_item_store_cover ON store_sales (ss_sold_date_sk,ss_item_sk,ss_store_sk,ss_sales_price);
