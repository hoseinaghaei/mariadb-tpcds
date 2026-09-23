with ssci as (
select ss_customer_sk customer_sk
      ,ss_item_sk item_sk
from store_sales,date_dim
where ss_sold_date_sk = d_date_sk
  and d_month_seq between 1212 and 1212 + 11
group by ss_customer_sk
        ,ss_item_sk),
csci as(
 select cs_bill_customer_sk customer_sk
      ,cs_item_sk item_sk
from catalog_sales,date_dim
where cs_sold_date_sk = d_date_sk
  and d_month_seq between 1212 and 1212 + 11
group by cs_bill_customer_sk
        ,cs_item_sk)
 select  sum(case when ssci_customer_sk is not null and csci_customer_sk is null then 1 else 0 end) store_only
      ,sum(case when ssci_customer_sk is null and csci_customer_sk is not null then 1 else 0 end) catalog_only
      ,sum(case when ssci_customer_sk is not null and csci_customer_sk is not null then 1 else 0 end) store_and_catalog
from (
      -- MariaDB has no FULL OUTER JOIN: emulated as
      -- (A LEFT JOIN B) UNION ALL (A RIGHT JOIN B WHERE A keys IS NULL).
      -- The anti-join filter on the second branch keeps only the B rows that
      -- found no A match, so UNION ALL adds no duplicates and legitimate
      -- duplicate rows are preserved.
      (select ssci.customer_sk ssci_customer_sk
             ,csci.customer_sk csci_customer_sk
       from ssci left outer join csci on (ssci.customer_sk=csci.customer_sk
                                      and ssci.item_sk = csci.item_sk))
      union all
      (select ssci.customer_sk ssci_customer_sk
             ,csci.customer_sk csci_customer_sk
       from ssci right outer join csci on (ssci.customer_sk=csci.customer_sk
                                       and ssci.item_sk = csci.item_sk)
       where ssci.customer_sk is null
         and ssci.item_sk is null)
     ) fj
limit 100;
