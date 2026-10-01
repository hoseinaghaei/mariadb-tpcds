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
--
-- Only d_week_seq is declared. InnoDB appends the primary key (d_date_sk) to
-- every secondary index leaf, so declaring it explicitly is redundant --
-- verified: both forms give an identical 161-page index, identical key_len=9,
-- and the plan reports "Using index" either way, which proves d_date_sk is
-- served from the index despite not being declared.
CREATE INDEX idx_dd_week_seq ON date_dim (d_week_seq);

-- Covering index for query 59's weekly store aggregation: the CTE sums
-- ss_sales_price grouped by (d_week_seq, ss_store_sk), and this serves the
-- whole scan from the index with no row lookups.
--   query59: 7.3s -> 3.0s
CREATE INDEX idx_ss_sold_date_sk_store_sales_price
    ON store_sales (ss_sold_date_sk, ss_store_sk, ss_sales_price);

-- Covering index for query 22: carries every inventory column the aggregation
-- reads, so the scan runs "Using index" with no row lookups.
--   query22: 23.0s -> 4.3s (with the query rewrite; see report/18)
CREATE INDEX idx_inv_item_date_sk
    ON inventory (inv_item_sk, inv_date_sk, inv_quantity_on_hand);

-- Serves query 22's min/max date-range subqueries. NOTE the COMPOSITE form --
-- a plain date_dim(d_month_seq) is rejected below.
CREATE INDEX idx_date_dim_d_month_seq ON date_dim (d_date_sk, d_month_seq);

-- ---------------------------------------------------------------------------
--  REJECTED: date_dim(d_month_seq)   -- the PLAIN single-column form
--
--  Looks obviously useful -- several queries filter on d_month_seq ranges --
--  but it makes query 59 TEN TIMES SLOWER. Confirmed by three-pass:
--      visible  12.7s  |  IGNORED  1.2s  |  visible again  12.6s
--  Do not add it without re-measuring the whole query set.
-- ---------------------------------------------------------------------------
-- CREATE INDEX idx_dd_month_seq ON date_dim (d_month_seq);   -- DO NOT

ANALYZE TABLE date_dim, household_demographics, customer_demographics;
