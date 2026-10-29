CREATE TEMPORARY TABLE customer (c_customer_sk BIGINT PRIMARY KEY,c_customer_id VARCHAR(16),c_first_name VARCHAR(20),c_last_name VARCHAR(20),KEY idx_nf_q74_customer_order(c_first_name,c_customer_id,c_last_name));
CREATE TEMPORARY TABLE date_dim (d_date_sk BIGINT PRIMARY KEY,d_year INT);
CREATE TEMPORARY TABLE store_sales (ss_customer_sk BIGINT,ss_sold_date_sk BIGINT,ss_net_paid DECIMAL(9,2),KEY idx_nf_q74_ss_top(ss_customer_sk,ss_net_paid,ss_sold_date_sk));
CREATE TEMPORARY TABLE web_sales (ws_bill_customer_sk BIGINT,ws_sold_date_sk BIGINT,ws_net_paid DECIMAL(9,2),KEY idx_nf_q74_ws_top(ws_bill_customer_sk,ws_net_paid,ws_sold_date_sk));
INSERT INTO date_dim VALUES (2451180,1999),(2451544,1999),(2451545,2000),(2451910,2000),(2451911,2001);
CREATE INDEX idx_nf_q74_customer_id ON customer(c_customer_id);
INSERT INTO customer VALUES (1,'C001','First1','Last'),(2,'C002','First2','Last'),(3,'C003','First3','Last'),(4,'C004','First4','Last'),(5,'C005','First5','Last'),(6,'DUP','First6','Last'),(7,'DUP','First7','Last'),(8,'DUP2','Same','Last'),(9,'DUP2','Same','Last'),(10,'C010','First10','Last'),(11,'C011','First11','Last'),(12,'C012','First12','Last'),(13,'C013',NULL,'Last'),(14,'C014','First14','Last'),(15,'C015','First15','Last');
INSERT INTO store_sales VALUES (1,2451180,100),(1,2451545,200),(2,2451180,100),(2,2451545,300),(3,2451180,0),(3,2451545,100),(4,2451180,100),(4,2451545,100),(5,2451180,100),(6,2451180,100),(6,2451545,100),(7,2451180,50),(7,2451545,100),(8,2451180,100),(8,2451545,100),(9,2451180,50),(9,2451545,100),(10,2451545,100),(11,2451180,NULL),(11,2451545,100),(12,2451180,100),(12,2451545,100),(13,2451180,100),(13,2451545,100),(14,2451180,100),(14,2451545,-100),(15,2451180,30000),(15,2451545,10000),(1,2451544,100),(1,2451180,50),(1,2451911,999999),(10,2451200,100),(999,2451180,999),(1,NULL,999);
INSERT INTO web_sales VALUES (1,2451180,100),(1,2451545,300),(2,2451180,100),(2,2451545,200),(3,2451180,100),(3,2451545,200),(4,2451180,-1),(4,2451545,200),(5,2451180,100),(5,2451545,200),(6,2451180,100),(6,2451545,200),(7,2451180,100),(7,2451545,150),(8,2451180,100),(8,2451545,200),(9,2451180,100),(9,2451545,150),(10,2451180,100),(10,2451545,200),(11,2451180,100),(11,2451545,200),(12,2451180,100),(12,2451545,NULL),(13,2451180,100),(13,2451545,200),(14,2451180,100),(14,2451545,0),(15,2451180,30000),(15,2451545,10000.01);
with year_total as (
 select c_customer_id customer_id
       ,c_first_name customer_first_name
       ,c_last_name customer_last_name
       ,d_year as year
       ,max(ss_net_paid) year_total
       ,'s' sale_type
 from customer
     ,store_sales
     ,date_dim
 where c_customer_sk = ss_customer_sk
   and ss_sold_date_sk = d_date_sk
   and d_year in (1999,1999+1)
 group by c_customer_id
         ,c_first_name
         ,c_last_name
         ,d_year
 union all
 select c_customer_id customer_id
       ,c_first_name customer_first_name
       ,c_last_name customer_last_name
       ,d_year as year
       ,max(ws_net_paid) year_total
       ,'w' sale_type
 from customer
     ,web_sales
     ,date_dim
 where c_customer_sk = ws_bill_customer_sk
   and ws_sold_date_sk = d_date_sk
   and d_year in (1999,1999+1)
 group by c_customer_id
         ,c_first_name
         ,c_last_name
         ,d_year
         )
  select 
        t_s_secyear.customer_id, t_s_secyear.customer_first_name, t_s_secyear.customer_last_name
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
         and t_s_firstyear.year = 1999
         and t_s_secyear.year = 1999+1
         and t_w_firstyear.year = 1999
         and t_w_secyear.year = 1999+1
         and t_s_firstyear.year_total > 0
         and t_w_firstyear.year_total > 0
         and case when t_w_firstyear.year_total > 0 then t_w_secyear.year_total / t_w_firstyear.year_total else null end
           > case when t_s_firstyear.year_total > 0 then t_s_secyear.year_total / t_s_firstyear.year_total else null end
 order by 2,1,3
limit 100;
