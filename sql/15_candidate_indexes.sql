-- New candidate indexes from the 2026-10-29..11-02 contributions.
-- Collected by hand from each candidate's indexes-BEST.sql / *Indexes*.sql.
-- Staged separately from sql/14 until the candidates they serve are adopted.

-- q4.  Her file comments both of these out and her README notes that
-- idx_ss_cust and idx_ss_customer_date have identical columns, so only one
-- of the pair is created here.
CREATE INDEX IF NOT EXISTS idx_ss_customer_date ON store_sales (ss_customer_sk, ss_sold_date_sk);
CREATE INDEX IF NOT EXISTS idx_cs_cust ON catalog_sales (cs_bill_customer_sk, cs_sold_date_sk);

-- q5
CREATE INDEX IF NOT EXISTS idx_sr_date ON store_returns (sr_returned_date_sk, sr_store_sk, sr_return_amt, sr_net_loss);
CREATE INDEX IF NOT EXISTS idx_cr_date ON catalog_returns (cr_returned_date_sk, cr_catalog_page_sk, cr_return_amount, cr_net_loss);
CREATE INDEX IF NOT EXISTS idx_wr_date ON web_returns (wr_returned_date_sk, wr_item_sk, wr_order_number, wr_return_amt, wr_net_loss);

-- q7
CREATE INDEX IF NOT EXISTS idx_nf_q7_item_id ON item (i_item_id);
CREATE INDEX IF NOT EXISTS idx_nf_q7_item_cover ON store_sales (ss_item_sk,ss_sold_date_sk,ss_cdemo_sk,ss_promo_sk,ss_quantity,ss_list_price,ss_coupon_amt,ss_sales_price);

-- q8
CREATE INDEX IF NOT EXISTS idx_nf_q8_addr_pref ON customer (c_current_addr_sk,c_preferred_cust_flag);
CREATE INDEX IF NOT EXISTS idx_nf_q8_zip_cover ON customer_address (ca_zip);

-- q10
CREATE INDEX IF NOT EXISTS idx_nf_q10_county ON customer_address (ca_county);

-- q11
CREATE INDEX IF NOT EXISTS idx_nf_q11_ss_cover ON store_sales (ss_sold_date_sk,ss_customer_sk,ss_ext_list_price,ss_ext_discount_amt);
CREATE INDEX IF NOT EXISTS idx_nf_q11_ws_cover ON web_sales (ws_sold_date_sk,ws_bill_customer_sk,ws_ext_list_price,ws_ext_discount_amt);

-- q46
CREATE INDEX IF NOT EXISTS idx_q46_cover ON store_sales (ss_sold_date_sk, ss_store_sk, ss_hdemo_sk, ss_addr_sk, ss_ticket_number, ss_customer_sk, ss_coupon_amt, ss_net_profit);

-- q57
CREATE INDEX IF NOT EXISTS idx_nf_q57_catalog_cover ON catalog_sales (cs_sold_date_sk,cs_item_sk,cs_call_center_sk,cs_sales_price);

-- q74
CREATE INDEX IF NOT EXISTS idx_nf_q74_ss_top ON store_sales (ss_customer_sk,ss_net_paid,ss_sold_date_sk);
CREATE INDEX IF NOT EXISTS idx_nf_q74_ws_top ON web_sales (ws_bill_customer_sk,ws_net_paid,ws_sold_date_sk);
CREATE INDEX IF NOT EXISTS idx_nf_q74_customer_order ON customer (c_first_name,c_customer_id,c_last_name);
CREATE INDEX IF NOT EXISTS idx_nf_q74_customer_id ON customer (c_customer_id);

-- q77
CREATE INDEX IF NOT EXISTS idx_q77_ss ON store_sales (ss_sold_date_sk, ss_store_sk, ss_ext_sales_price, ss_net_profit);
CREATE INDEX IF NOT EXISTS idx_q77_cs ON catalog_sales (cs_sold_date_sk, cs_call_center_sk, cs_ext_sales_price, cs_net_profit);
CREATE INDEX IF NOT EXISTS idx_q77_ws ON web_sales (ws_sold_date_sk, ws_web_page_sk, ws_ext_sales_price, ws_net_profit);
CREATE INDEX IF NOT EXISTS idx_q77_cr ON catalog_returns (cr_returned_date_sk, cr_call_center_sk, cr_return_amount, cr_net_loss);
CREATE INDEX IF NOT EXISTS idx_q77_wr ON web_returns (wr_returned_date_sk, wr_web_page_sk, wr_return_amt, wr_net_loss);

