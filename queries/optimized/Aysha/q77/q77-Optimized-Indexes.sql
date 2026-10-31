CREATE INDEX idx_q77_ss ON store_sales (ss_sold_date_sk, ss_store_sk, ss_ext_sales_price, ss_net_profit);

CREATE INDEX idx_q77_cs ON catalog_sales (cs_sold_date_sk, cs_call_center_sk, cs_ext_sales_price, cs_net_profit);

CREATE INDEX idx_q77_ws ON web_sales (ws_sold_date_sk, ws_web_page_sk, ws_ext_sales_price, ws_net_profit);

CREATE INDEX idx_q77_cr ON catalog_returns (cr_returned_date_sk, cr_call_center_sk, cr_return_amount, cr_net_loss);

CREATE INDEX idx_q77_wr ON web_returns (wr_returned_date_sk, wr_web_page_sk, wr_return_amt, wr_net_loss);


SET SESSION optimizer_switch = 'mrr=on,mrr_sort_keys=on,mrr_cost_based=off';
SET SESSION mrr_buffer_size = 64*1024*1024;
SET SESSION join_cache_level = 8;