#!/bin/bash
#
# test-v3.sh -- validate and time the q23 v3 rewrite at SF=4.
#
# q23 returns one NULL row and then no rows at all at this scale, so diffing
# the final answer proves almost nothing.  The real check is on the three
# CTEs: each is rebuilt standalone, old form against new, and compared on
# cardinality and on an aggregate of the values.  If those match, the rewrite
# feeds the outer query exactly what it fed before.
set -Eeuo pipefail

REPO=/Users/hosseinaghaei/Desktop/projects/dw
LAB=$REPO/pagesize
SOCK="$LAB/s32-sf4.sock"
ME=$(id -un)
PRE="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');"

mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || {
  mariadbd --defaults-file="$LAB/my-32k-sf4-t1exact.cnf" >>"$LAB/32k-sf4.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
}
CLI=(mariadb --socket="$SOCK" --user="$ME" -B -N tpcds)

now() { python3 -c 'import time;print(time.time())'; }
el()  { python3 -c "print(f'{$2-$1:.1f}')"; }

# Each CTE, old form and new, reduced to a shape that is cheap to compare:
# a row count plus an aggregate over the values it produces.
probe() {   # $1 label   $2 full select to run
  local t0 t1
  t0=$(now)
  "${CLI[@]}" -e "$PRE $2" > "/tmp/q23c-$1.out" 2>&1 || true
  t1=$(now)
  printf '  %-10s %8ss   %s\n' "$1" "$(el "$t0" "$t1")" "$(tr '\n' ' ' < "/tmp/q23c-$1.out")"
}

echo "=== CTE equivalence: row count, distinct item_sk"
probe freq-old "select count(*), count(distinct item_sk) from (select substr(i_item_desc,1,30) itemdesc,i_item_sk item_sk,d_date solddate,count(*) cnt from store_sales,date_dim,item where ss_sold_date_sk = d_date_sk and ss_item_sk = i_item_sk and d_year in (1999,1999+1,1999+2,1999+3) group by substr(i_item_desc,1,30),i_item_sk,d_date having count(*) >4) z"
probe freq-new "select count(*), count(distinct item_sk) from (select ss_item_sk item_sk from store_sales where ss_sold_date_sk between 2451180 and 2452640 group by ss_sold_date_sk, ss_item_sk having count(*) > 4) z"

echo "=== CTE equivalence: max_store_sales scalar"
probe max-old "select max(csales) from (select c_customer_sk,sum(ss_quantity*ss_sales_price) csales from store_sales,customer,date_dim where ss_customer_sk = c_customer_sk and ss_sold_date_sk = d_date_sk and d_year in (1999,1999+1,1999+2,1999+3) group by c_customer_sk) t"
probe max-new "select max(csales) from (select sum(ss_quantity*ss_sales_price) csales from store_sales where ss_sold_date_sk between 2451180 and 2452640 and ss_customer_sk is not null group by ss_customer_sk) t"

echo "=== CTE equivalence: best_ss_customer pre-HAVING (count, sum, max)"
probe best-old "select count(*), round(sum(ssales),2), round(max(ssales),2) from (select c_customer_sk,sum(ss_quantity*ss_sales_price) ssales from store_sales,customer where ss_customer_sk = c_customer_sk group by c_customer_sk) z"
probe best-new "select count(*), round(sum(ssales),2), round(max(ssales),2) from (select ss_customer_sk c_customer_sk,sum(ss_quantity*ss_sales_price) ssales from store_sales where ss_customer_sk is not null group by ss_customer_sk) z"

echo
echo "=== full query, interleaved, 3 passes"
for p in 1 2 3; do
  for v in orig v3; do
    if [ "$v" = orig ]; then F="$REPO/queries/mariadb/query23.sql"
    else F="$REPO/queries/optimized/q23-sf4/query23_v3_densekeys.sql"; fi
    t0=$(now)
    rc=0
    { echo "$PRE"; cat "$F"; } | mariadb --socket="$SOCK" --user="$ME" -B tpcds \
      > "/tmp/q23-$v.out" 2>"/tmp/q23-$v.err" || rc=$?
    t1=$(now)
    printf '  pass %s  %-5s %8ss  rc=%s  lines=%s\n' \
      "$p" "$v" "$(el "$t0" "$t1")" "$rc" "$(wc -l < "/tmp/q23-$v.out")"
  done
done

echo
if cmp -s /tmp/q23-orig.out /tmp/q23-v3.out; then
  echo "  OUTPUT: IDENTICAL"
else
  echo "  OUTPUT: ** DIFFERS **"
  diff /tmp/q23-orig.out /tmp/q23-v3.out | head -20
fi
