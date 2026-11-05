CREATE TEMPORARY TABLE item (i_item_sk BIGINT PRIMARY KEY,i_manufact_id INT,i_category VARCHAR(20),KEY idx_nf_q33_item_cover(i_item_sk,i_manufact_id));
CREATE TEMPORARY TABLE date_dim (d_date_sk BIGINT PRIMARY KEY,d_year INT,d_moy INT);
CREATE TEMPORARY TABLE customer_address (ca_address_sk BIGINT PRIMARY KEY,ca_gmt_offset DECIMAL(5,2));
CREATE TEMPORARY TABLE store_sales (ss_item_sk BIGINT,ss_sold_date_sk BIGINT,ss_addr_sk BIGINT,ss_ext_sales_price DECIMAL(7,2));
CREATE TEMPORARY TABLE catalog_sales (cs_item_sk BIGINT,cs_sold_date_sk BIGINT,cs_bill_addr_sk BIGINT,cs_ext_sales_price DECIMAL(7,2));
CREATE TEMPORARY TABLE web_sales (ws_item_sk BIGINT,ws_sold_date_sk BIGINT,ws_bill_addr_sk BIGINT,ws_ext_sales_price DECIMAL(7,2));
INSERT INTO item VALUES (1,10,'Books'),(2,10,'Music'),(3,10,'Books'),(4,20,'Music'),(5,30,'Books'),(6,NULL,'Books'),(7,40,'Books'),(8,50,'Books');
INSERT INTO date_dim VALUES (2451727,2000,7),(2451757,2000,7),(2451726,2000,6),(2451758,2000,8),(999,2001,7);
INSERT INTO customer_address VALUES (1,-5),(2,-4),(3,NULL);
INSERT INTO store_sales VALUES (1,2451727,1,10.00),(2,2451727,1,5.00),(2,2451727,1,5.00),(4,2451727,1,999.00),(5,2451727,1,NULL),(6,2451727,1,999.00),(7,2451727,1,1.00),(8,2451727,1,0.00),(1,2451726,1,999.00),(1,2451727,2,999.00),(1,2451730,1,999.00),(999,2451727,1,999.00),(1,2451727,999,999.00);
INSERT INTO catalog_sales VALUES (2,2451757,1,7.00),(3,2451757,1,2.00),(5,2451757,1,NULL),(7,2451757,1,-1.00),(1,2451758,1,999.00),(1,NULL,1,999.00);
INSERT INTO web_sales VALUES (1,2451727,1,-3.00),(7,2451727,1,2.00),(1,999,1,999.00),(1,2451727,3,999.00);
with ss as (
 select
          i_manufact_id,sum(ss_ext_sales_price) total_sales
 from
 	store_sales,
 	date_dim,
         customer_address,
         item
 where
         i_manufact_id in (select
  i_manufact_id
from
 item
where i_category in ('Books'))
 and     ss_item_sk              = i_item_sk
 and     ss_sold_date_sk         = d_date_sk
 and     d_year                  = 2000
 and     d_moy                   = 7
 and     ss_addr_sk              = ca_address_sk
 and     ca_gmt_offset           = -5 
 group by i_manufact_id),
 cs as (
 select
          i_manufact_id,sum(cs_ext_sales_price) total_sales
 from
 	catalog_sales,
 	date_dim,
         customer_address,
         item
 where
         i_manufact_id               in (select
  i_manufact_id
from
 item
where i_category in ('Books'))
 and     cs_item_sk              = i_item_sk
 and     cs_sold_date_sk         = d_date_sk
 and     d_year                  = 2000
 and     d_moy                   = 7
 and     cs_bill_addr_sk         = ca_address_sk
 and     ca_gmt_offset           = -5 
 group by i_manufact_id),
 ws as (
 select
          i_manufact_id,sum(ws_ext_sales_price) total_sales
 from
 	web_sales,
 	date_dim,
         customer_address,
         item
 where
         i_manufact_id               in (select
  i_manufact_id
from
 item
where i_category in ('Books'))
 and     ws_item_sk              = i_item_sk
 and     ws_sold_date_sk         = d_date_sk
 and     d_year                  = 2000
 and     d_moy                   = 7
 and     ws_bill_addr_sk         = ca_address_sk
 and     ca_gmt_offset           = -5
 group by i_manufact_id)
  select  i_manufact_id ,sum(total_sales) total_sales
 from  (select * from ss 
        union all
        select * from cs 
        union all
        select * from ws) tmp1
 group by i_manufact_id
 order by total_sales
limit 100;
