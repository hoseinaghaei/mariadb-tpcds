-- ---------------------------------------------------------------------------
--  Step-by-step test: does hiding the "unused" indexes affect query 78?
--
--  Run each STEP in order with:
--      mariadb tpcds < this-file            (or paste step by step)
--
--  Timing a query from the mariadb client: the client prints elapsed time
--  after each statement. For a cleaner number use:
--      cd queries && python3 run_query.py 78 <tag>
--
--  ANSWER (measured on this machine, 8 GB pool, seed-10 data, serial):
--      all 117 visible   45.4s / 44.2s
--      6 candidates hidden 43.8s
--      all 80 hidden     43.7s
--  -> hiding them makes NO measurable difference.
-- ---------------------------------------------------------------------------

USE tpcds;
SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE');


-- === STEP 0 - confirm the starting state ==================================
SELECT COUNT(DISTINCT TABLE_NAME, INDEX_NAME) AS ignored_now
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA='tpcds' AND IGNORED='YES';
-- expect 0


-- === STEP 1 - baseline plan, all indexes visible ==========================
-- Note `possible_keys` and `key` for store_returns, web_sales,
-- catalog_sales and catalog_returns.
EXPLAIN
SELECT * FROM (
  -- paste the body of queries/mariadb/query78.sql here, or run:
  --   mariadb tpcds -e "SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE');
  --                     EXPLAIN $(cat queries/mariadb/query78.sql)"
  SELECT 1
) x;


-- === STEP 2 - baseline timing =============================================
--   cd queries && python3 run_query.py 78 before
-- expect about 45s


-- === STEP 3 - hide ONLY the 6 indexes that appear in q78's possible_keys ==
ALTER TABLE store_returns   ALTER INDEX idx_sr_ticket_number IGNORED;
ALTER TABLE web_sales       ALTER INDEX idx_ws_sold_date_sk  IGNORED;
ALTER TABLE web_sales       ALTER INDEX idx_ws_item_sk       IGNORED;
ALTER TABLE catalog_sales   ALTER INDEX idx_cs_sold_date_sk  IGNORED;
ALTER TABLE catalog_sales   ALTER INDEX idx_cs_item_sk       IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_order_number  IGNORED;

SELECT COUNT(DISTINCT TABLE_NAME, INDEX_NAME) AS ignored_now
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA='tpcds' AND IGNORED='YES';
-- expect 6

--   cd queries && python3 run_query.py 78 six_hidden
-- MEASURED: 43.8s -- no change


-- === STEP 4 - restore those 6 =============================================
ALTER TABLE store_returns   ALTER INDEX idx_sr_ticket_number NOT IGNORED;
ALTER TABLE web_sales       ALTER INDEX idx_ws_sold_date_sk  NOT IGNORED;
ALTER TABLE web_sales       ALTER INDEX idx_ws_item_sk       NOT IGNORED;
ALTER TABLE catalog_sales   ALTER INDEX idx_cs_sold_date_sk  NOT IGNORED;
ALTER TABLE catalog_sales   ALTER INDEX idx_cs_item_sk       NOT IGNORED;
ALTER TABLE catalog_returns ALTER INDEX idx_cr_order_number  NOT IGNORED;


-- === STEP 5 - hide ALL 80 never-read indexes ==============================
--   mariadb tpcds < sql/09_ignore_unused_indexes.sql
-- takes about 17s for all 80; nothing is rebuilt

SELECT COUNT(DISTINCT TABLE_NAME, INDEX_NAME) AS ignored_now
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA='tpcds' AND IGNORED='YES';
-- expect 80

--   cd queries && python3 run_query.py 78 all80_hidden
-- MEASURED: 43.7s -- still no change


-- === STEP 6 - compare the plans ===========================================
-- The chosen `key` does not change. Only `possible_keys` shrinks.
EXPLAIN SELECT 1;   -- replace with the q78 body as in STEP 1


-- === STEP 7 - restore everything ==========================================
--   mariadb tpcds < sql/10_unignore_unused_indexes.sql

SELECT COUNT(DISTINCT TABLE_NAME, INDEX_NAME) AS ignored_now
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA='tpcds' AND IGNORED='YES';
-- expect 0


-- ---------------------------------------------------------------------------
--  A ONE-LINER for the whole thing, from the shell:
--
--    cd queries
--    python3 run_query.py 78 before
--    mariadb tpcds < ../sql/09_ignore_unused_indexes.sql
--    python3 run_query.py 78 hidden
--    mariadb tpcds < ../sql/10_unignore_unused_indexes.sql
--    python3 run_query.py 78 after
--    grep -h seconds results/{before,hidden,after}/query78.json
-- ---------------------------------------------------------------------------
