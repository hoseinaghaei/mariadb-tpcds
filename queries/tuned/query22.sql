-- query22
-- source: queries/optimized/q22/query22_BEST.sql
-- split materialisation at default: -1.3s is inside this host's noise
--
-- FORCE INDEX (idx_inv_item_date_sk): 39.0s -> 10.4s at SF=4, same answer
-- (md5 dd6e2fc5), and far steadier -- 10.4-11.3s against 39.0-46.3s.
--
-- Left to itself the optimizer picks inventory:PRIMARY here, and whether it
-- does depends on the statistics sample rather than on the index set.
-- idx_inv_date_sk was making it pick PRIMARY, so dropping that index fixed
-- q22 -- until OPTIMIZE TABLE re-sampled the statistics and PRIMARY won
-- again with idx_inv_date_sk already gone.  At
-- innodb_stats_persistent_sample_pages=160 the choice between PRIMARY and
-- idx_inv_item_date_sk is close enough that any ANALYZE can flip it, which
-- is a 28s swing on a ~430s suite decided by which pages got sampled.
-- Pinning the access path is the only thing that makes it reproducible.
-- See report/28 section 1.

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

select *
from (select
          i_product_name
           , i_brand
           , i_class
           , i_category
           , avg(inv_quantity_on_hand) qoh
      from inventory FORCE INDEX (idx_inv_item_date_sk)
         , item
      where inv_item_sk = i_item_sk
        and inv_date_sk between (select min(d_date_sk) from date_dim
                                 where d_month_seq between 1176 and 1176 + 11)
                            and (select max(d_date_sk) from date_dim
                                 where d_month_seq between 1176 and 1176 + 11)
      group by i_product_name
             , i_brand
             , i_class
             , i_category
      with rollup) tpcds_rollup
order by qoh, i_product_name, i_brand, i_class, i_category
limit 100;
