-- v2: quarter pivot plus the equivalent 2001 Q1-Q3 date-key range.
WITH ss AS (
 SELECT ca_county,SUM(CASE WHEN d_qoy=1 THEN ss_ext_sales_price END) s1,SUM(CASE WHEN d_qoy=2 THEN ss_ext_sales_price END) s2,SUM(CASE WHEN d_qoy=3 THEN ss_ext_sales_price END) s3,
 COUNT(CASE WHEN d_qoy=1 THEN 1 END) a,COUNT(CASE WHEN d_qoy=2 THEN 1 END) b,COUNT(CASE WHEN d_qoy=3 THEN 1 END) c
 FROM store_sales JOIN date_dim ON ss_sold_date_sk=d_date_sk JOIN customer_address ON ss_addr_sk=ca_address_sk
 WHERE ss_sold_date_sk BETWEEN 2451911 AND 2452184 AND d_year=2001 AND d_qoy IN (1,2,3) GROUP BY ca_county
), ws AS (
 SELECT ca_county,SUM(CASE WHEN d_qoy=1 THEN ws_ext_sales_price END) w1,SUM(CASE WHEN d_qoy=2 THEN ws_ext_sales_price END) w2,SUM(CASE WHEN d_qoy=3 THEN ws_ext_sales_price END) w3,
 COUNT(CASE WHEN d_qoy=1 THEN 1 END) a,COUNT(CASE WHEN d_qoy=2 THEN 1 END) b,COUNT(CASE WHEN d_qoy=3 THEN 1 END) c
 FROM web_sales JOIN date_dim ON ws_sold_date_sk=d_date_sk JOIN customer_address ON ws_bill_addr_sk=ca_address_sk
 WHERE ws_sold_date_sk BETWEEN 2451911 AND 2452184 AND d_year=2001 AND d_qoy IN (1,2,3) GROUP BY ca_county
)
SELECT ss.ca_county,2001 d_year,ws.w2/ws.w1 web_q1_q2_increase,ss.s2/ss.s1 store_q1_q2_increase,ws.w3/ws.w2 web_q2_q3_increase,ss.s3/ss.s2 store_q2_q3_increase
FROM ss JOIN ws ON ss.ca_county=ws.ca_county
WHERE ss.a>0 AND ss.b>0 AND ss.c>0 AND ws.a>0 AND ws.b>0 AND ws.c>0 AND ws.w1>0 AND ss.s1>0 AND ws.w2/ws.w1>ss.s2/ss.s1 AND ws.w2>0 AND ss.s2>0 AND ws.w3/ws.w2>ss.s3/ss.s2
ORDER BY web_q2_q3_increase;
