SELECT ca_zip,ca_county,SUM(amount) FROM (
SELECT ca_zip,ca_county,SUM(ws_sales_price) amount FROM web_sales IGNORE INDEX (idx_nf_q45_customer_cover,idx_nf_q45_item_cover) JOIN customer ON ws_bill_customer_sk=c_customer_sk
JOIN customer_address IGNORE INDEX (idx_nf_q45_zip) ON c_current_addr_sk=ca_address_sk
JOIN date_dim ON ws_sold_date_sk=d_date_sk JOIN item ON ws_item_sk=i_item_sk
WHERE d_year=2001 AND d_qoy=1 AND ws_sold_date_sk BETWEEN 2451911 AND 2452001 AND SUBSTR(ca_zip,1,5) IN ('85669','86197','88274','83405','86475','85392','85460','80348','81792') GROUP BY ca_zip,ca_county
UNION ALL
SELECT ca_zip,ca_county,SUM(ws_sales_price) amount FROM web_sales IGNORE INDEX (idx_nf_q45_customer_cover,idx_nf_q45_item_cover) JOIN customer ON ws_bill_customer_sk=c_customer_sk
JOIN customer_address IGNORE INDEX (idx_nf_q45_zip) ON c_current_addr_sk=ca_address_sk
JOIN date_dim ON ws_sold_date_sk=d_date_sk JOIN item ON ws_item_sk=i_item_sk
WHERE d_year=2001 AND d_qoy=1 AND ws_sold_date_sk BETWEEN 2451911 AND 2452001 AND i_item_id IN(SELECT i_item_id FROM item WHERE i_item_sk IN (2,3,5,7,11,13,17,19,23,29)) AND (SUBSTR(ca_zip,1,5) IN ('85669','86197','88274','83405','86475','85392','85460','80348','81792')) IS NOT TRUE GROUP BY ca_zip,ca_county
) branches GROUP BY ca_zip,ca_county ORDER BY ca_zip,ca_county LIMIT 100;