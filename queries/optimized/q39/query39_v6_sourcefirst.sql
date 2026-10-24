-- Keep each grouped inventory result before its dimension lookups in join order.
-- Late dimension lookups while retaining two independent SELECT statements.
-- No temporary results are shared between their snapshots.
WITH inv_raw AS (
    SELECT inv_warehouse_sk,inv_item_sk,d_moy,
           STDDEV_SAMP(inv_quantity_on_hand) AS stdev,
           AVG(inv_quantity_on_hand) AS mean
    FROM inventory
    JOIN date_dim ON inv_date_sk = d_date_sk
    WHERE d_year = 1998 AND d_moy IN (4,5)
    GROUP BY inv_warehouse_sk,inv_item_sk,d_moy
),
inv AS (
    SELECT w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy,stdev,mean,
           CASE mean WHEN 0 THEN NULL ELSE stdev/mean END AS cov
    FROM inv_raw
    STRAIGHT_JOIN item ON inv_item_sk = i_item_sk
    STRAIGHT_JOIN warehouse ON inv_warehouse_sk = w_warehouse_sk
    WHERE CASE mean WHEN 0 THEN 0 ELSE stdev/mean END > 1
)
select inv1.w_warehouse_sk,inv1.i_item_sk,inv1.d_moy,inv1.mean, inv1.cov
        ,inv2.w_warehouse_sk,inv2.i_item_sk,inv2.d_moy,inv2.mean, inv2.cov
from inv inv1,inv inv2
where inv1.i_item_sk = inv2.i_item_sk
  and inv1.w_warehouse_sk =  inv2.w_warehouse_sk
  and inv1.d_moy=4
  and inv2.d_moy=4+1
order by inv1.w_warehouse_sk,inv1.i_item_sk,inv1.d_moy,inv1.mean,inv1.cov
        ,inv2.d_moy,inv2.mean, inv2.cov
;

WITH inv_raw AS (
    SELECT inv_warehouse_sk,inv_item_sk,d_moy,
           STDDEV_SAMP(inv_quantity_on_hand) AS stdev,
           AVG(inv_quantity_on_hand) AS mean
    FROM inventory
    JOIN date_dim ON inv_date_sk = d_date_sk
    WHERE d_year = 1998 AND d_moy IN (4,5)
    GROUP BY inv_warehouse_sk,inv_item_sk,d_moy
),
inv AS (
    SELECT w_warehouse_name,w_warehouse_sk,i_item_sk,d_moy,stdev,mean,
           CASE mean WHEN 0 THEN NULL ELSE stdev/mean END AS cov
    FROM inv_raw
    STRAIGHT_JOIN item ON inv_item_sk = i_item_sk
    STRAIGHT_JOIN warehouse ON inv_warehouse_sk = w_warehouse_sk
    WHERE CASE mean WHEN 0 THEN 0 ELSE stdev/mean END > 1
)
select inv1.w_warehouse_sk,inv1.i_item_sk,inv1.d_moy,inv1.mean, inv1.cov
        ,inv2.w_warehouse_sk,inv2.i_item_sk,inv2.d_moy,inv2.mean, inv2.cov
from inv inv1,inv inv2
where inv1.i_item_sk = inv2.i_item_sk
  and inv1.w_warehouse_sk =  inv2.w_warehouse_sk
  and inv1.d_moy=4
  and inv2.d_moy=4+1
  and inv1.cov > 1.5
order by inv1.w_warehouse_sk,inv1.i_item_sk,inv1.d_moy,inv1.mean,inv1.cov
        ,inv2.d_moy,inv2.mean, inv2.cov
;
