-- query88
-- source: queries/optimized/q88/query88_BEST.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

select
    sum(case when time_dim.t_hour =  8 and time_dim.t_minute >= 30 then 1 else 0 end) h8_30_to_9
  , sum(case when time_dim.t_hour =  9 and time_dim.t_minute <  30 then 1 else 0 end) h9_to_9_30
  , sum(case when time_dim.t_hour =  9 and time_dim.t_minute >= 30 then 1 else 0 end) h9_30_to_10
  , sum(case when time_dim.t_hour = 10 and time_dim.t_minute <  30 then 1 else 0 end) h10_to_10_30
  , sum(case when time_dim.t_hour = 10 and time_dim.t_minute >= 30 then 1 else 0 end) h10_30_to_11
  , sum(case when time_dim.t_hour = 11 and time_dim.t_minute <  30 then 1 else 0 end) h11_to_11_30
  , sum(case when time_dim.t_hour = 11 and time_dim.t_minute >= 30 then 1 else 0 end) h11_30_to_12
  , sum(case when time_dim.t_hour = 12 and time_dim.t_minute <  30 then 1 else 0 end) h12_to_12_30
from store_sales, household_demographics, time_dim, store
where ss_sold_time_sk = time_dim.t_time_sk
  and ss_hdemo_sk = household_demographics.hd_demo_sk
  and ss_store_sk = s_store_sk
  and ((household_demographics.hd_dep_count = 0 and household_demographics.hd_vehicle_count<=0+2) or
       (household_demographics.hd_dep_count = 1 and household_demographics.hd_vehicle_count<=1+2) or
       (household_demographics.hd_dep_count = 4 and household_demographics.hd_vehicle_count<=4+2))
  and store.s_store_name = 'ese'
  and time_dim.t_hour between 8 and 12;
