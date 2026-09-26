-- ---------------------------------------------------------------------------
--  Indexes added beyond the reference repo's 117, for query optimisation.
--
--  Six were added manually during optimisation work; the seventh
--  (idx_dd_week_seq) was added to fix query 72 specifically and is the single
--  highest-value index found so far.
--
--  NOTE: Clause 2.5.3 of the TPC-DS specification restricts Explicit Auxiliary
--  Data Structures. These would need justifying against 2.5.3.2 for an audited
--  result. Fine for optimisation work.
-- ---------------------------------------------------------------------------

USE tpcds;

-- Covering indexes for the demographic filters: the join is satisfied from the
-- index alone, with no row lookup.
CREATE INDEX idx_hd_demo_sk_buy_potential  ON household_demographics (hd_demo_sk, hd_buy_potential);
CREATE INDEX idx_cd_demo_sk_marital_status ON customer_demographics  (cd_demo_sk, cd_marital_status);

-- date_dim access paths
CREATE INDEX inx_date_dim_year         ON date_dim (d_year);
CREATE INDEX idx_date_year_moy         ON date_dim (d_year, d_moy);
CREATE INDEX idx_date_dim_d_date       ON date_dim (d_date);
CREATE INDEX idx_date_dim_d_date_year  ON date_dim (d_date_sk, d_year, d_date);

-- THE BIG ONE for query 72. Its d1/d2 self-join correlates two date_dim rows
-- on d_week_seq, which had no index at all and was resolved by a full scan of
-- 72,124 rows per driving row. With this, d2 becomes ref rows=6, and inventory
-- can then be reached through its PRIMARY KEY (inv_date_sk, inv_item_sk)
-- instead of a secondary index.
--   query72 with the JOIN_PREFIX hint:  13.1s -> 1.0s
--   query72 unmodified:                719.3s -> 87.8s
CREATE INDEX idx_dd_week_seq ON date_dim (d_week_seq, d_date_sk);

ANALYZE TABLE date_dim, household_demographics, customer_demographics;
