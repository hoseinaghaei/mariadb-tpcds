-- ---------------------------------------------------------------------------
--  Drop the 7 indexes that duplicate a leading prefix of their own PRIMARY KEY.
--
--  Each of these indexes a column (or columns) that the table's PRIMARY KEY
--  already indexes in the same leading position, so InnoDB can satisfy every
--  lookup from the clustered index instead. They add nothing and cost 470 MB.
--
--  Verified:
--    SELECT ... FROM store_sales WHERE ss_item_sk = 100
--      with idx_ss_item_sk : key=idx_ss_item_sk  key_len=8  rows=129
--      with it IGNORED     : key=PRIMARY         key_len=8  rows=129
--    -> identical access path and cost.
--
--    For inventory the optimizer ALREADY prefers PRIMARY and never touches
--    idx_inv_date_sk, which is why it appears in the never-read set.
--
--  Unlike the "never read" set in sql/06 (see report/17), this is a structural
--  argument, not a usage observation: a leading prefix of the PRIMARY KEY is
--  redundant by definition, whatever the workload.
--
--  Test with IGNORED first if you want -- reversible in seconds:
--    ALTER TABLE store_sales ALTER INDEX idx_ss_item_sk IGNORED;
-- ---------------------------------------------------------------------------

USE tpcds;

--                                                          index size   PK
ALTER TABLE inventory       DROP INDEX idx_inv_date_sk;   -- 21759 pg  (inv_date_sk, inv_item_sk, inv_warehouse_sk)
ALTER TABLE store_sales     DROP INDEX idx_ss_item_sk;    --  4135 pg  (ss_item_sk, ss_ticket_number)
ALTER TABLE catalog_sales   DROP INDEX idx_cs_item_sk;    --  2212 pg  (cs_item_sk, cs_order_number)
ALTER TABLE web_sales       DROP INDEX idx_ws_item_sk;    --  1123 pg  (ws_item_sk, ws_order_number)
ALTER TABLE store_returns   DROP INDEX idx_sr_item_sk;    --   481 pg  (sr_item_sk, sr_ticket_number)
ALTER TABLE catalog_returns DROP INDEX idx_cr_item_sk;    --   225 pg  (cr_item_sk, cr_order_number)
ALTER TABLE web_returns     DROP INDEX idx_wr_item_sk;    --   161 pg  (wr_item_sk, wr_order_number)

ANALYZE TABLE inventory, store_sales, catalog_sales, web_sales,
              store_returns, catalog_returns, web_returns;
