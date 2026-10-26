
SET SESSION sort_buffer_size = 64 * 1024 * 1024;
SET SESSION tmp_table_size = 256 * 1024 * 1024;
SET SESSION max_heap_table_size = 256 * 1024 * 1024;

SELECT
    @@SESSION.sort_buffer_size,
    @@SESSION.tmp_table_size,
    @@SESSION.max_heap_table_size;

analyze format=json
select * from (
  select * from (
    select i_category, i_class, i_brand, i_product_name,
           d_year, d_qoy, d_moy, s_store_id, sumsales,
           rank() over (partition by i_category order by sumsales desc) rk
    from q67_rollup
  ) dw2
  where rk <= 100
) tpcds_rollup
order by i_category, i_class, i_brand, i_product_name,
         d_year, d_qoy, d_moy, s_store_id, sumsales, rk
limit 100;