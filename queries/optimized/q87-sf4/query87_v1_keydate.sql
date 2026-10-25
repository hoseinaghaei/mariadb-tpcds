-- q87 v1 -- except on the date key, not the date, and drop date_dim.
--
-- Same shape as q38, with EXCEPT in place of INTERSECT, and the same
-- reasoning applies: the query returns a single count(*), d_date is used only
-- to decide whether a row in one channel matches a row in another, and
-- d_date <-> d_date_sk is a bijection on date_dim (73,049 rows, 73,049
-- distinct dates).  Swapping the key in for the date in all three branches
-- preserves every match, so the set difference has the same cardinality.
--
-- EXCEPT is order-sensitive in a way INTERSECT is not -- (A except B) except C
-- -- but the substitution is applied uniformly to all three branches and the
-- order is untouched, so the chain evaluates over the same elements.
--
-- d_month_seq between 1176 and 1176+11 is the contiguous key range
-- 2450815..2451179 (365 rows, span 365; date_dim is dense over
-- 2415022..2488070), so each date_dim join becomes a BETWEEN on the fact
-- table's own foreign key.  That drops three per-row dimension probes and
-- lets each fact table be driven by its FK index.
--
-- The customer joins stay: names are not unique, and the original takes the
-- difference over names, so reducing to c_customer_sk would change the count.

select count(*)
from ((select distinct c_last_name, c_first_name, ss_sold_date_sk
       from store_sales, customer
       where store_sales.ss_customer_sk = customer.c_customer_sk
         and ss_sold_date_sk between 2450815 and 2451179)
       except
      (select distinct c_last_name, c_first_name, cs_sold_date_sk
       from catalog_sales, customer
       where catalog_sales.cs_bill_customer_sk = customer.c_customer_sk
         and cs_sold_date_sk between 2450815 and 2451179)
       except
      (select distinct c_last_name, c_first_name, ws_sold_date_sk
       from web_sales, customer
       where web_sales.ws_bill_customer_sk = customer.c_customer_sk
         and ws_sold_date_sk between 2450815 and 2451179)
) cool_cust
;
