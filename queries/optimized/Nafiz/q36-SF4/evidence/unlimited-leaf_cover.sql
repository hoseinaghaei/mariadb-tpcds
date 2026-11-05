WITH leaf AS (SELECT i_category,i_class,SUM(ss_net_profit) profit,SUM(ss_ext_sales_price) price
FROM store_sales JOIN date_dim d1 ON d1.d_date_sk=ss_sold_date_sk
JOIN item ON i_item_sk=ss_item_sk JOIN store ON s_store_sk=ss_store_sk
WHERE d1.d_year=2001 AND s_state='TN'
GROUP BY i_category,i_class), levels AS (SELECT 0 lev UNION ALL SELECT 1 UNION ALL SELECT 2), hierarchy AS (
SELECT SUM(profit)/SUM(price) gross_margin,
CASE WHEN lev<2 THEN i_category END i_category,
CASE WHEN lev=0 THEN i_class END i_class,lev lochierarchy
FROM leaf CROSS JOIN levels
GROUP BY lev,CASE WHEN lev<2 THEN i_category END,CASE WHEN lev=0 THEN i_class END
) SELECT gross_margin,i_category,i_class,lochierarchy,
RANK() OVER(PARTITION BY lochierarchy,CASE WHEN lochierarchy=0 THEN i_category END ORDER BY gross_margin ASC) rank_within_parent
FROM hierarchy ORDER BY lochierarchy DESC,CASE WHEN lochierarchy=0 THEN i_category END,rank_within_parent;