-- q59 BEST -- 175.5s -> 4.8s at SF=4 / 32K pages, byte-identical output.
--
-- Two changes, in order of what they are worth:
--
--   1. split_materialized=off              175.5s -> 14.6s   (12.0x)
--   2. restrict the CTE to usable weeks     14.6s ->  4.8s    (3.0x)
--
-- WHY 1.  ANALYZE FORMAT=JSON showed one of the two references to `wss` being
-- re-materialised 7,665 times -- once per outer row -- for 164s of a 167s
-- query.  The optimizer's split-materialisation ("lateral derived") strategy
-- recomputes the CTE per outer row, which pays off for a selective lookup and
-- is catastrophic for a full aggregate like this one.  Turning it off makes
-- the CTE materialise once.
--
-- This is also why q59 looked bistable: measured at 15.3s in one run and
-- ~155s in a dozen others with identical output.  Those are the two plans.
-- Nothing about the cache, the statistics, join_cache_level, MRR or
-- use_stat_tables was involved; all six were eliminated by direct test.
--
-- WHY 2.  The CTE aggregates ALL of store_sales (15.5M rows) grouped by
-- (d_week_seq, ss_store_sk), but the outer query only reads two 12-month
-- windows of it -- 105 weeks of 262, 2,310 groups of 5,764.
--
-- The filter is on d_week_seq, NOT on dates, and that is what makes it safe:
-- a week is included or excluded whole, so every surviving group still
-- aggregates exactly the rows it did before, including days that fall outside
-- months 1192-1215.  Filtering by date would be WRONG -- a boundary week
-- would lose days and its seven sum(case...) values would change.
--
-- Indexes were tried and are not the answer: covering indexes on
-- date_dim(d_date_sk, d_week_seq, d_day_name) and (d_month_seq, d_week_seq)
-- moved it 4.8s -> 4.7s, inside noise, and were dropped.  store_sales already
-- has idx_ss_sold_date_sk_store_sales_price, which the plan uses as covering.

SET SESSION optimizer_switch = 'split_materialized=off';

with wss as
 (select d_week_seq,
        ss_store_sk,
        sum(case when (d_day_name='Sunday') then ss_sales_price else null end) sun_sales,
        sum(case when (d_day_name='Monday') then ss_sales_price else null end) mon_sales,
        sum(case when (d_day_name='Tuesday') then ss_sales_price else  null end) tue_sales,
        sum(case when (d_day_name='Wednesday') then ss_sales_price else null end) wed_sales,
        sum(case when (d_day_name='Thursday') then ss_sales_price else null end) thu_sales,
        sum(case when (d_day_name='Friday') then ss_sales_price else null end) fri_sales,
        sum(case when (d_day_name='Saturday') then ss_sales_price else null end) sat_sales
 from store_sales,date_dim
 where d_date_sk = ss_sold_date_sk
   and d_week_seq between (select min(d_week_seq) from date_dim
                            where d_month_seq between 1192 and 1192 + 23)
                      and (select max(d_week_seq) from date_dim
                            where d_month_seq between 1192 and 1192 + 23)
 group by d_week_seq,ss_store_sk
 )
  select  s_store_name1,s_store_id1,d_week_seq1
       ,sun_sales1/sun_sales2,mon_sales1/mon_sales2
       ,tue_sales1/tue_sales2,wed_sales1/wed_sales2,thu_sales1/thu_sales2
       ,fri_sales1/fri_sales2,sat_sales1/sat_sales2
 from
 (select s_store_name s_store_name1,wss.d_week_seq d_week_seq1
        ,s_store_id s_store_id1,sun_sales sun_sales1
        ,mon_sales mon_sales1,tue_sales tue_sales1
        ,wed_sales wed_sales1,thu_sales thu_sales1
        ,fri_sales fri_sales1,sat_sales sat_sales1
  from wss,store,date_dim d
  where d.d_week_seq = wss.d_week_seq and
        ss_store_sk = s_store_sk and
        d_month_seq between 1192 and 1192 + 11) y,
 (select s_store_name s_store_name2,wss.d_week_seq d_week_seq2
        ,s_store_id s_store_id2,sun_sales sun_sales2
        ,mon_sales mon_sales2,tue_sales tue_sales2
        ,wed_sales wed_sales2,thu_sales thu_sales2
        ,fri_sales fri_sales2,sat_sales sat_sales2
  from wss,store,date_dim d
  where d.d_week_seq = wss.d_week_seq and
        ss_store_sk = s_store_sk and
        d_month_seq between 1192+ 12 and 1192 + 23) x
 where s_store_id1=s_store_id2
   and d_week_seq1=d_week_seq2-52
 order by s_store_name1,s_store_id1,d_week_seq1
limit 100;
