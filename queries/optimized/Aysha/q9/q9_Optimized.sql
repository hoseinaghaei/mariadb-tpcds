-- CREATE INDEX idx_ss_quantity
-- ON store_sales (ss_quantity);
-- 
-- DROP INDEX idx_ss_quantity ON store_sales;  replaced by the below index


CREATE INDEX idx_ss_qty_cover
ON store_sales (ss_quantity, ss_ext_list_price, ss_net_profit);

DROP INDEX idx_ss_quantity ON store_sales;  -- now redundant



select case when c1.cnt > 46486 then c1.avg_list else c1.avg_profit end bucket1,
       case when c2.cnt > 30986 then c2.avg_list else c2.avg_profit end bucket2,
       case when c3.cnt > 16616 then c3.avg_list else c3.avg_profit end bucket3,
       case when c4.cnt > 4804  then c4.avg_list else c4.avg_profit end bucket4,
       case when c5.cnt > 7474  then c5.avg_list else c5.avg_profit end bucket5
from reason,
     (select count(*) cnt,
             avg(ss_ext_list_price) avg_list,
             avg(ss_net_profit) avg_profit
      from store_sales
      where ss_quantity between 1 and 20) c1,
     (select count(*) cnt,
             avg(ss_ext_list_price) avg_list,
             avg(ss_net_profit) avg_profit
      from store_sales
      where ss_quantity between 21 and 40) c2,
     (select count(*) cnt,
             avg(ss_ext_list_price) avg_list,
             avg(ss_net_profit) avg_profit
      from store_sales
      where ss_quantity between 41 and 60) c3,
     (select count(*) cnt,
             avg(ss_ext_list_price) avg_list,
             avg(ss_net_profit) avg_profit
      from store_sales
      where ss_quantity between 61 and 80) c4,
     (select count(*) cnt,
             avg(ss_ext_list_price) avg_list,
             avg(ss_net_profit) avg_profit
      from store_sales
      where ss_quantity between 81 and 100) c5
where r_reason_sk = 1;