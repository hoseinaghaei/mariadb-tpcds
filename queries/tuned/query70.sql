-- query70
-- source: queries/optimized/q70-sf4/query70_v1_nosubquery.sql

SET SESSION sql_mode = CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');

with ss_by_store as (
  select ss_store_sk, sum(ss_net_profit) as np
  from store_sales
  where ss_sold_date_sk between 2450815 and 2451179
  group by ss_store_sk
)
select * from (
select
    sum(np) as total_sum
   ,s_state
   ,s_county
   ,(s_state is null)+(s_county is null) as lochierarchy
   ,rank() over (
 	partition by (s_state is null)+(s_county is null),
 	case when (s_county is null) = 0 then s_state end
 	order by sum(np) desc) as rank_within_parent
 from
    ss_by_store
   ,store
 where
    s_store_sk = ss_store_sk
 group by s_state,s_county with rollup
) tpcds_rollup
order by
   lochierarchy desc
  ,case when lochierarchy = 0 then s_state end
  ,rank_within_parent
 limit 100;
