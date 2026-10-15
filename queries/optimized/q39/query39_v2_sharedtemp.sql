-- Compute the qualifying two-month inventory groups once for both statements.
-- All temporary-table creation, population, reads and cleanup are timed.
CREATE TEMPORARY TABLE riccio_q39_pairs ENGINE=InnoDB AS
WITH inv AS (
    SELECT w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy,
           stdev,mean,CASE mean WHEN 0 THEN NULL ELSE stdev/mean END AS cov
    FROM (
        SELECT w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy,
               STDDEV_SAMP(inv_quantity_on_hand) AS stdev,
               AVG(inv_quantity_on_hand) AS mean
        FROM inventory
        JOIN item ON inv_item_sk = i_item_sk
        JOIN warehouse ON inv_warehouse_sk = w_warehouse_sk
        JOIN date_dim ON inv_date_sk = d_date_sk
        WHERE d_year = 1998 AND d_moy IN (4,5)
        GROUP BY w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy
    ) foo
    WHERE CASE mean WHEN 0 THEN 0 ELSE stdev/mean END > 1
)
SELECT w_warehouse_sk,i_item_sk,
       MAX(CASE WHEN d_moy = 4 THEN mean END) AS mean_4,
       MAX(CASE WHEN d_moy = 4 THEN cov END) AS cov_4,
       MAX(CASE WHEN d_moy = 5 THEN mean END) AS mean_5,
       MAX(CASE WHEN d_moy = 5 THEN cov END) AS cov_5
FROM inv
GROUP BY w_warehouse_sk,i_item_sk
HAVING COUNT(DISTINCT d_moy) = 2;

SELECT w_warehouse_sk,i_item_sk,4 AS d_moy,mean_4 AS mean,cov_4 AS cov,
       w_warehouse_sk,i_item_sk,5 AS d_moy,mean_5 AS mean,cov_5 AS cov
FROM riccio_q39_pairs
ORDER BY w_warehouse_sk,i_item_sk,mean_4,cov_4,mean_5,cov_5;

SELECT w_warehouse_sk,i_item_sk,4 AS d_moy,mean_4 AS mean,cov_4 AS cov,
       w_warehouse_sk,i_item_sk,5 AS d_moy,mean_5 AS mean,cov_5 AS cov
FROM riccio_q39_pairs
WHERE cov_4 > 1.5
ORDER BY w_warehouse_sk,i_item_sk,mean_4,cov_4,mean_5,cov_5;

DROP TEMPORARY TABLE riccio_q39_pairs;
