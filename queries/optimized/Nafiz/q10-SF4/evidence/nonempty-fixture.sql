CREATE TEMPORARY TABLE customer_address (ca_address_sk BIGINT PRIMARY KEY,ca_county VARCHAR(50));
CREATE TEMPORARY TABLE customer (c_customer_sk BIGINT PRIMARY KEY,c_current_addr_sk BIGINT,c_current_cdemo_sk BIGINT);
CREATE TEMPORARY TABLE customer_demographics (cd_demo_sk BIGINT PRIMARY KEY,cd_gender CHAR(1),cd_marital_status CHAR(1),cd_education_status VARCHAR(20),cd_purchase_estimate INT,cd_credit_rating VARCHAR(10),cd_dep_count INT,cd_dep_employed_count INT,cd_dep_college_count INT);
CREATE TEMPORARY TABLE date_dim (d_date_sk BIGINT PRIMARY KEY,d_year INT,d_moy INT);
CREATE TEMPORARY TABLE store_sales (ss_customer_sk BIGINT,ss_sold_date_sk BIGINT);
CREATE TEMPORARY TABLE web_sales (ws_bill_customer_sk BIGINT,ws_sold_date_sk BIGINT);
CREATE TEMPORARY TABLE catalog_sales (cs_ship_customer_sk BIGINT,cs_bill_customer_sk BIGINT,cs_sold_date_sk BIGINT);
INSERT INTO customer_address VALUES (1,'Madison County'),(2,'Wallowa County'),(3,'Calhoun County'),(4,'Broadwater County'),(5,'McCone County'),(6,'Other County');
INSERT INTO customer_demographics VALUES (1,'F','S','College',100,'Good',0,0,0),(2,'M','M','Unknown',200,'Low',1,0,0);
INSERT INTO date_dim VALUES (2452001,2001,4),(2452122,2001,7),(2452000,2001,3),(2452123,2001,8),(999,2002,4);
INSERT INTO customer VALUES (1,1,1),(2,2,1),(3,3,2),(4,4,2),(5,5,2),(6,6,2),(7,1,2),(8,1,2),(9,1,999),(10,999,2),(11,1,2),(12,1,2),(13,1,NULL),(14,1,2),(15,1,1),(16,1,1),(17,1,2);
INSERT INTO store_sales VALUES (1,2452001),(1,2452001),(2,2452001),(3,2452001),(4,2452001),(6,2452001),(7,2452000),(8,2452002),(9,2452001),(10,2452001),(11,2452001),(12,2452001),(13,2452001),(14,2452001),(15,2452001),(16,999),(17,2452001),(NULL,2452001);
INSERT INTO web_sales VALUES (1,2452001),(1,2452001),(3,2452122),(5,2452001),(6,2452001),(7,2452000),(8,2452002),(9,2452001),(10,2452001),(13,2452001),(14,NULL),(16,999),(17,2452001),(NULL,2452001);
INSERT INTO catalog_sales VALUES (2,999,2452122),(2,999,2452122),(3,999,2452001),(999,11,2452001),(15,999,2452122),(NULL,12,2452001);
select  
  cd_gender,
  cd_marital_status,
  cd_education_status,
  count(*) cnt1,
  cd_purchase_estimate,
  count(*) cnt2,
  cd_credit_rating,
  count(*) cnt3,
  cd_dep_count,
  count(*) cnt4,
  cd_dep_employed_count,
  count(*) cnt5,
  cd_dep_college_count,
  count(*) cnt6
 from
  customer c,customer_address ca,customer_demographics
 where
  c.c_current_addr_sk = ca.ca_address_sk and
  ca_county in ('Madison County','Wallowa County','Calhoun County','Broadwater County','McCone County') and
  cd_demo_sk = c.c_current_cdemo_sk and 
  exists (select *
          from store_sales,date_dim
          where c.c_customer_sk = ss_customer_sk and
                ss_sold_date_sk = d_date_sk and
                d_year = 2001 and
                d_moy between 4 and 4+3) and
   (exists (select *
            from web_sales,date_dim
            where c.c_customer_sk = ws_bill_customer_sk and
                  ws_sold_date_sk = d_date_sk and
                  d_year = 2001 and
                  d_moy between 4 ANd 4+3) or 
    exists (select * 
            from catalog_sales,date_dim
            where c.c_customer_sk = cs_ship_customer_sk and
                  cs_sold_date_sk = d_date_sk and
                  d_year = 2001 and
                  d_moy between 4 and 4+3))
 group by cd_gender,
          cd_marital_status,
          cd_education_status,
          cd_purchase_estimate,
          cd_credit_rating,
          cd_dep_count,
          cd_dep_employed_count,
          cd_dep_college_count
 order by cd_gender,
          cd_marital_status,
          cd_education_status,
          cd_purchase_estimate,
          cd_credit_rating,
          cd_dep_count,
          cd_dep_employed_count,
          cd_dep_college_count
limit 100;
