WITH channel_totals AS (SELECT i.i_manufact_id,SUM(f.ss_ext_sales_price) total_sales
FROM store_sales f JOIN date_dim d ON f.ss_sold_date_sk=d.d_date_sk
JOIN customer_address a ON f.ss_addr_sk=a.ca_address_sk JOIN item i ON f.ss_item_sk=i.i_item_sk

WHERE d.d_year=2000 AND d.d_moy=7 AND a.ca_gmt_offset=-5 GROUP BY i.i_manufact_id
UNION ALL
SELECT i.i_manufact_id,SUM(f.cs_ext_sales_price) total_sales
FROM catalog_sales f JOIN date_dim d ON f.cs_sold_date_sk=d.d_date_sk
JOIN customer_address a ON f.cs_bill_addr_sk=a.ca_address_sk JOIN item i ON f.cs_item_sk=i.i_item_sk

WHERE d.d_year=2000 AND d.d_moy=7 AND a.ca_gmt_offset=-5 GROUP BY i.i_manufact_id
UNION ALL
SELECT i.i_manufact_id,SUM(f.ws_ext_sales_price) total_sales
FROM web_sales f JOIN date_dim d ON f.ws_sold_date_sk=d.d_date_sk
JOIN customer_address a ON f.ws_bill_addr_sk=a.ca_address_sk JOIN item i ON f.ws_item_sk=i.i_item_sk

WHERE d.d_year=2000 AND d.d_moy=7 AND a.ca_gmt_offset=-5 GROUP BY i.i_manufact_id) SELECT i_manufact_id,SUM(total_sales) total_sales FROM channel_totals WHERE i_manufact_id IN (SELECT i_manufact_id FROM item WHERE i_category='Books') GROUP BY i_manufact_id ORDER BY total_sales LIMIT 100;