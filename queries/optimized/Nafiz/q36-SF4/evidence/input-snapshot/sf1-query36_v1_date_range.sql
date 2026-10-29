-- v1: retain the year predicate and add its equivalent 2001 date-key range.
SELECT * FROM (
 SELECT SUM(ss_net_profit)/SUM(ss_ext_sales_price) gross_margin, i_category, i_class,
        (i_category IS NULL)+(i_class IS NULL) lochierarchy,
        RANK() OVER (PARTITION BY (i_category IS NULL)+(i_class IS NULL),
          CASE WHEN (i_class IS NULL)=0 THEN i_category END
          ORDER BY SUM(ss_net_profit)/SUM(ss_ext_sales_price)) rank_within_parent
 FROM store_sales, date_dim d1, item, store
 WHERE d1.d_year=2001 AND ss_sold_date_sk BETWEEN 2451911 AND 2452275
   AND d1.d_date_sk=ss_sold_date_sk AND i_item_sk=ss_item_sk AND s_store_sk=ss_store_sk
   AND s_state IN ('TN','TN','TN','TN','TN','TN','TN','TN')
 GROUP BY i_category,i_class WITH ROLLUP
) tpcds_rollup
ORDER BY lochierarchy DESC,CASE WHEN lochierarchy=0 THEN i_category END,rank_within_parent LIMIT 100;
