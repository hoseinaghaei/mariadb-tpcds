CREATE TEMPORARY TABLE customer (c_customer_sk BIGINT PRIMARY KEY,c_customer_id VARCHAR(16),c_first_name VARCHAR(20),c_last_name VARCHAR(20),c_preferred_cust_flag CHAR(1),c_birth_country VARCHAR(20),c_login VARCHAR(20),c_email_address VARCHAR(50));
CREATE TEMPORARY TABLE date_dim (d_date_sk BIGINT PRIMARY KEY,d_year INT);
CREATE TEMPORARY TABLE store_sales (ss_customer_sk BIGINT,ss_sold_date_sk BIGINT,ss_ext_list_price DECIMAL(9,2),ss_ext_discount_amt DECIMAL(9,2));
CREATE TEMPORARY TABLE web_sales (ws_bill_customer_sk BIGINT,ws_sold_date_sk BIGINT,ws_ext_list_price DECIMAL(9,2),ws_ext_discount_amt DECIMAL(9,2));
INSERT INTO date_dim VALUES (2451911,2001),(2452275,2001),(2452276,2002),(2452640,2002),(2451545,2000);
INSERT INTO customer VALUES (1,'C001','First1','Last','Y','Country','login1','email1'),(2,'C002','First2','Last','Y','Country','login2','email2'),(3,'C003','First3','Last','Y','Country','login3','email3'),(4,'C004','First4','Last','Y','Country','login4','email4'),(5,'C005','First5','Last','Y','Country','login5','email5'),(6,'DUP','First6','Last','Y','Country','login6','email6'),(7,'DUP','First7','Last','Y','Country','login7','email7'),(8,'DUP2','Same','Last','Y','Country','same','email8'),(9,'DUP2','Same','Last','N','Country','same','email9'),(10,'C010','First10','Last','Y','Country','login10','email10'),(11,'C011','First11','Last','Y','Country','login11','email11'),(12,'C012','First12','Last','Y','Country','login12','email12'),(13,'C013','First13','Last','Y','Country','login13','email13');
INSERT INTO store_sales VALUES (1,2452276,110,0),(2,2451911,100,0),(2,2452276,200,0),(3,2451911,0,0),(3,2452276,110,0),(4,2451911,100,0),(4,2452276,110,0),(5,2451911,100,0),(6,2451911,100,0),(6,2452276,100,0),(7,2451911,50,0),(7,2452276,100,0),(8,2451911,100,0),(8,2452276,100,0),(9,2451911,50,0),(9,2452276,100,0),(10,2451911,100,0),(10,2452276,110,0),(11,2451911,NULL,0),(11,2452276,110,0),(12,2452276,110,0),(13,2451911,30000,0),(13,2452276,10000,0),(12,2452000,100,0),(999,2451911,999,0),(1,2451545,999,0),(1,2452276,NULL,0),(1,2451911,60,10),(1,2451911,60,10);
INSERT INTO web_sales VALUES (1,2451911,100,0),(1,2452276,150,0),(2,2451911,100,0),(2,2452276,150,0),(3,2451911,100,0),(3,2452276,150,0),(4,2451911,-1,0),(4,2452276,150,0),(5,2451911,100,0),(5,2452276,150,0),(6,2451911,100,0),(6,2452276,200,0),(7,2451911,100,0),(7,2452276,150,0),(8,2451911,100,0),(8,2452276,200,0),(9,2451911,100,0),(9,2452276,150,0),(10,2451911,100,0),(11,2451911,100,0),(11,2452276,150,0),(12,2451911,100,0),(12,2452276,150,0),(13,2451911,30000,0),(13,2452276,10000.01,0);
with year_total as (
 select c_customer_id customer_id
       ,c_first_name customer_first_name
       ,c_last_name customer_last_name
       ,c_preferred_cust_flag customer_preferred_cust_flag
       ,c_birth_country customer_birth_country
       ,c_login customer_login
       ,c_email_address customer_email_address
       ,d_year dyear
       ,sum(ss_ext_list_price-ss_ext_discount_amt) year_total
       ,'s' sale_type
 from customer
     ,store_sales
     ,date_dim
 where c_customer_sk = ss_customer_sk
   and ss_sold_date_sk = d_date_sk
 group by c_customer_id
         ,c_first_name
         ,c_last_name
         ,c_preferred_cust_flag 
         ,c_birth_country
         ,c_login
         ,c_email_address
         ,d_year 
 union all
 select c_customer_id customer_id
       ,c_first_name customer_first_name
       ,c_last_name customer_last_name
       ,c_preferred_cust_flag customer_preferred_cust_flag
       ,c_birth_country customer_birth_country
       ,c_login customer_login
       ,c_email_address customer_email_address
       ,d_year dyear
       ,sum(ws_ext_list_price-ws_ext_discount_amt) year_total
       ,'w' sale_type
 from customer
     ,web_sales
     ,date_dim
 where c_customer_sk = ws_bill_customer_sk
   and ws_sold_date_sk = d_date_sk
 group by c_customer_id
         ,c_first_name
         ,c_last_name
         ,c_preferred_cust_flag 
         ,c_birth_country
         ,c_login
         ,c_email_address
         ,d_year
         )
  select  
                  t_s_secyear.customer_id
                 ,t_s_secyear.customer_first_name
                 ,t_s_secyear.customer_last_name
                 ,t_s_secyear.customer_login
 from year_total t_s_firstyear
     ,year_total t_s_secyear
     ,year_total t_w_firstyear
     ,year_total t_w_secyear
 where t_s_secyear.customer_id = t_s_firstyear.customer_id
         and t_s_firstyear.customer_id = t_w_secyear.customer_id
         and t_s_firstyear.customer_id = t_w_firstyear.customer_id
         and t_s_firstyear.sale_type = 's'
         and t_w_firstyear.sale_type = 'w'
         and t_s_secyear.sale_type = 's'
         and t_w_secyear.sale_type = 'w'
         and t_s_firstyear.dyear = 2001
         and t_s_secyear.dyear = 2001+1
         and t_w_firstyear.dyear = 2001
         and t_w_secyear.dyear = 2001+1
         and t_s_firstyear.year_total > 0
         and t_w_firstyear.year_total > 0
         and case when t_w_firstyear.year_total > 0 then t_w_secyear.year_total / t_w_firstyear.year_total else 0.0 end
             > case when t_s_firstyear.year_total > 0 then t_s_secyear.year_total / t_s_firstyear.year_total else 0.0 end
 order by t_s_secyear.customer_id
         ,t_s_secyear.customer_first_name
         ,t_s_secyear.customer_last_name
         ,t_s_secyear.customer_login
limit 100;
