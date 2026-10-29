CREATE TEMPORARY TABLE item (i_item_sk BIGINT PRIMARY KEY,i_category VARCHAR(20),i_brand VARCHAR(20));
CREATE TEMPORARY TABLE call_center (cc_call_center_sk BIGINT PRIMARY KEY,cc_name VARCHAR(20));
CREATE TEMPORARY TABLE date_dim (d_date_sk BIGINT PRIMARY KEY,d_year INT,d_moy INT);
CREATE TEMPORARY TABLE catalog_sales (cs_item_sk BIGINT,cs_sold_date_sk BIGINT,cs_call_center_sk BIGINT,cs_sales_price DECIMAL(7,2));
INSERT INTO item VALUES (1,'Books','Brand'),(2,'Books','Brand'),(3,NULL,'Null category'),(4,'Books',NULL),(5,'Books','Null center'),(6,'Books','Zero average');
INSERT INTO call_center VALUES (1,'Center'),(2,'Center'),(3,NULL);
INSERT INTO date_dim VALUES (2451514,1999,12),(2451545,2000,1),(2451605,2000,3),(2451636,2000,4),(2451880,2000,12),(2451911,2001,1),(2451484,1999,11),(2451942,2001,2);
INSERT INTO catalog_sales VALUES (1,2451514,1,10),(1,2451545,1,80),(1,2451545,1,20),(2,2451545,2,5),(1,2451605,1,NULL),(1,2451636,1,1),(1,2451880,1,0),(1,2451911,1,20),(1,2451484,1,999),(1,2451942,1,999),(1,2451700,1,999),(999,2451545,1,999),(1,2451545,999,999);
INSERT INTO catalog_sales VALUES (3,2451514,1,10);
INSERT INTO catalog_sales VALUES (3,2451545,1,100);
INSERT INTO catalog_sales VALUES (3,2451636,1,1);
INSERT INTO catalog_sales VALUES (3,2451911,1,20);
INSERT INTO catalog_sales VALUES (4,2451514,1,10);
INSERT INTO catalog_sales VALUES (4,2451545,1,100);
INSERT INTO catalog_sales VALUES (4,2451636,1,1);
INSERT INTO catalog_sales VALUES (4,2451911,1,20);
INSERT INTO catalog_sales VALUES (5,2451514,3,10);
INSERT INTO catalog_sales VALUES (5,2451545,3,100);
INSERT INTO catalog_sales VALUES (5,2451636,3,1);
INSERT INTO catalog_sales VALUES (5,2451911,3,20);
INSERT INTO catalog_sales VALUES (6,2451514,1,0);
INSERT INTO catalog_sales VALUES (6,2451545,1,0);
INSERT INTO catalog_sales VALUES (6,2451636,1,0);
INSERT INTO catalog_sales VALUES (6,2451911,1,0);
with v1 as(
 select i_category, i_brand,
        cc_name,
        d_year, d_moy,
        sum(cs_sales_price) sum_sales,
        avg(sum(cs_sales_price)) over
          (partition by i_category, i_brand,
                     cc_name, d_year)
          avg_monthly_sales,
        rank() over
          (partition by i_category, i_brand,
                     cc_name
           order by d_year, d_moy) rn
 from item, catalog_sales, date_dim, call_center
 where cs_item_sk = i_item_sk and
       cs_sold_date_sk = d_date_sk and
       cc_call_center_sk= cs_call_center_sk and
       (
         d_year = 2000 or
         ( d_year = 2000-1 and d_moy =12) or
         ( d_year = 2000+1 and d_moy =1)
       )
 group by i_category, i_brand,
          cc_name , d_year, d_moy),
 v2 as(
 select v1.i_brand
        ,v1.d_year, v1.d_moy
        ,v1.avg_monthly_sales
        ,v1.sum_sales, v1_lag.sum_sales psum, v1_lead.sum_sales nsum
 from v1, v1 v1_lag, v1 v1_lead
 where v1.i_category = v1_lag.i_category and
       v1.i_category = v1_lead.i_category and
       v1.i_brand = v1_lag.i_brand and
       v1.i_brand = v1_lead.i_brand and
       v1. cc_name = v1_lag. cc_name and
       v1. cc_name = v1_lead. cc_name and
       v1.rn = v1_lag.rn + 1 and
       v1.rn = v1_lead.rn - 1)
  select  *
 from v2
 where  d_year = 2000 and
        avg_monthly_sales > 0 and
        case when avg_monthly_sales > 0 then abs(sum_sales - avg_monthly_sales) / avg_monthly_sales else null end > 0.1
 order by sum_sales - avg_monthly_sales, psum
 limit 100;
