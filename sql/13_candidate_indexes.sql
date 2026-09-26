-- ---------------------------------------------------------------------------
--  Candidate indexes -- DRAFTED, NOT APPLIED, NOT MEASURED.
--
--  These were sketched while optimising query 72 and are kept here so they are
--  not lost. None has been created or benchmarked. Treat as a to-try list.
--
--  Test each with the three-pass method (measure / create / measure / drop /
--  measure) and diff query output before and after -- see report/18.
-- ---------------------------------------------------------------------------

USE tpcds;

-- Composite covering indexes on catalog_sales aimed at query 72's access
-- pattern: filter by sold date, then reach the demographic keys.
-- CREATE INDEX idx_cs_sold_date_bill_hdemo_sk ON catalog_sales (cs_sold_date_sk, cs_bill_hdemo_sk, cs_bill_cdemo_sk);
-- CREATE INDEX idx_cs_item_bill_hdemo_sk      ON catalog_sales (cs_item_sk, cs_bill_hdemo_sk);
-- CREATE INDEX idx_cs_item_bill_hdemo_quantity_sk ON catalog_sales (cs_item_sk, cs_bill_hdemo_sk, cs_quantity);

-- ANALYZE TABLE catalog_sales;

-- Note before trying these: query 72 already runs in 1.0s with
-- idx_dd_week_seq plus the JOIN_PREFIX hint (report/18), and its plan reaches
-- catalog_sales via idx_cs_sold_date_sk at ref rows=955. These composites may
-- add little on top -- measure before keeping.
