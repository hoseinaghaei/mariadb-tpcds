-- ---------------------------------------------------------------------------
--  Restore the three `inventory` secondary indexes from the optimizer.
--
--  These are the measured cause of the worst remaining regressions. Restoring
--  them is metadata-only and instant; they were never dropped.
--  built on disk, and 08_unignore_inventory_indexes.sql restores it just as
--  fast. Nothing is rebuilt in either direction.
--
--  Requires MariaDB 10.6+.
--
--  Measured effect (serial, quiet server, 2 GB buffer pool):
--      query39   146.5s -> 1.7s     (86x faster)
--      query21    24.0s -> 0.3s     (80x faster)
--      query22    29.0s -> 11.5s    (2.5x faster)
--  Row counts were identical before and after, so results do not change.
-- ---------------------------------------------------------------------------

USE tpcds;

ALTER TABLE inventory ALTER INDEX idx_inv_item_sk      NOT IGNORED;
ALTER TABLE inventory ALTER INDEX idx_inv_warehouse_sk NOT IGNORED;
ALTER TABLE inventory ALTER INDEX idx_inv_date_sk      NOT IGNORED;

ANALYZE TABLE inventory;

SELECT TABLE_NAME, INDEX_NAME, IGNORED
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA='tpcds' AND TABLE_NAME='inventory' AND INDEX_NAME<>'PRIMARY'
GROUP BY TABLE_NAME, INDEX_NAME, NOT IGNORED;
