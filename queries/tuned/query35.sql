-- query35
-- source: queries/optimized/q35-sf4/query35_v1_keydate.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

select
  ca_state,
  cd_gender,
  cd_marital_status,
  cd_dep_count,
  count(*) cnt1,
  min(cd_dep_count) aggone1,
  avg(cd_dep_count) aggtwo1,
  sum(cd_dep_count) aggthree1,
  cd_dep_employed_count,
  count(*) cnt2,
  min(cd_dep_employed_count) aggone2,
  avg(cd_dep_employed_count) aggtwo2,
  sum(cd_dep_employed_count) aggthree2,
  cd_dep_college_count,
  count(*) cnt3,
  min(cd_dep_college_count) aggone3,
  avg(cd_dep_college_count) aggtwo3,
  sum(cd_dep_college_count) aggthree3
 from
  customer c,customer_address ca,customer_demographics
 where
  c.c_current_addr_sk = ca.ca_address_sk and
  cd_demo_sk = c.c_current_cdemo_sk and
  exists (select *
          from store_sales
          where c.c_customer_sk = ss_customer_sk and
                ss_sold_date_sk between 2451180 and 2451453) and
   (exists (select *
            from web_sales
            where c.c_customer_sk = ws_bill_customer_sk and
                  ws_sold_date_sk between 2451180 and 2451453) or
    exists (select *
            from catalog_sales
            where c.c_customer_sk = cs_ship_customer_sk and
                  cs_sold_date_sk between 2451180 and 2451453))
 group by ca_state,
          cd_gender,
          cd_marital_status,
          cd_dep_count,
          cd_dep_employed_count,
          cd_dep_college_count
 order by ca_state,
          cd_gender,
          cd_marital_status,
          cd_dep_count,
          cd_dep_employed_count,
          cd_dep_college_count
 limit 100;
