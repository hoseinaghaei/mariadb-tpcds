-- q38 v1 -- intersect on the date key, not the date, and drop date_dim.
--
-- The query intersects three sets of (c_last_name, c_first_name, d_date) and
-- then counts them.  d_date never reaches the output -- the whole query
-- returns a single count(*) -- and it is only ever used to decide whether a
-- row in one channel matches a row in another.
--
-- d_date and d_date_sk are a bijection on date_dim: 73,049 rows, 73,049
-- distinct d_date.  Substituting the key for the date in all three branches
-- therefore preserves every match and every non-match, so the intersection
-- has exactly the same cardinality and count(*) is unchanged.  It only works
-- because all three branches are rewritten together; mixing a date in one
-- branch with a key in another would match nothing.
--
-- With d_date gone, date_dim is only there for d_month_seq, and that filter
-- is the contiguous key range d_date_sk 2450815..2451179 (365 rows, span 365
-- -- it is calendar year 1998).  date_dim is dense over 2415022..2488070, so
-- any key inside the range exists and the join can be replaced outright by a
-- BETWEEN on each fact table's own foreign key.  That removes a per-row probe
-- into date_dim from all three branches and lets the range optimizer drive
-- each fact table by its FK index.  BETWEEN also drops the NULL
-- ss_sold_date_sk rows that the inner join dropped.
--
-- The customer joins stay.  Names are not unique -- two customers can share
-- one -- and the original intersects on names, so collapsing to c_customer_sk
-- would change the answer.

select  count(*) from (
    select distinct c_last_name, c_first_name, ss_sold_date_sk
    from store_sales, customer
          where store_sales.ss_customer_sk = customer.c_customer_sk
      and ss_sold_date_sk between 2450815 and 2451179
  intersect
    select distinct c_last_name, c_first_name, cs_sold_date_sk
    from catalog_sales, customer
          where catalog_sales.cs_bill_customer_sk = customer.c_customer_sk
      and cs_sold_date_sk between 2450815 and 2451179
  intersect
    select distinct c_last_name, c_first_name, ws_sold_date_sk
    from web_sales, customer
          where web_sales.ws_bill_customer_sk = customer.c_customer_sk
      and ws_sold_date_sk between 2450815 and 2451179
) hot_cust
limit 100;
