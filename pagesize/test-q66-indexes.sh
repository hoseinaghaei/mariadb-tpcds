#!/bin/bash
#
# test-q66-indexes.sh -- do Aysha's two q66 covering indexes pay for
# themselves, and does her rewrite add anything on top?
#
#   queries/optimized/Aysha/q66/q66-Indexes.sql
#     idx_ws_q66 ON web_sales     (ws_ship_mode_sk, ws_sold_date_sk,
#                                  ws_sold_time_sk, ws_warehouse_sk,
#                                  ws_sales_price, ws_quantity,
#                                  ws_net_paid_inc_ship)
#     idx_cs_q66 ON catalog_sales (cs_ship_mode_sk, cs_sold_date_sk,
#                                  cs_sold_time_sk, cs_warehouse_sk,
#                                  cs_ext_sales_price, cs_quantity,
#                                  cs_net_paid_inc_tax)
#
# Both lead with ship_mode_sk, which is the right call: q66 filters
# sm_carrier in ('ORIENTAL','ZHOU'), two carriers out of twenty.
#
# WHY RE-MEASURE.  Her README reports 11.9s -> 0.46s (25.9x), most of it from
# the indexes alone (11.9 -> 1.54).  Two reasons that cannot be carried over:
#
#   1. Her committed baseline, query66-Original.sql, is the adapted original
#      prefixed with ANALYZE FORMAT=JSON, which EXECUTES the query under
#      instrumentation.  q23 measured 208.1s that way against ~175s plain, so
#      a baseline measured under ANALYZE is inflated and the ratio with it.
#   2. This project runs 188 indexes, 32K pages and an 8 GB pool; a gain
#      earned against a thinner schema may already be available here.
#
# And one reason to be careful: these are two SEVEN-COLUMN indexes on the two
# largest non-store fact tables.  Adding six indexes to this schema once made
# 16K/SF=1 40% SLOWER by displacing data pages from the buffer pool, and the
# q77 covering index (512 MB) helped two queries and nothing else.  So the
# suite is measured as a whole, not just q66.
#
# RUN THIS YOURSELF: the analysis session is restricted to read-only
# statements and cannot issue CREATE INDEX or ALTER TABLE.
#
#   ./pagesize/test-q66-indexes.sh
#
# BUDGET: index build a few minutes, then four full tier-4/5 passes at SF=4
# of roughly 8 minutes each -- about 45 minutes.  Keep the machine quiet; the
# last measurements taken at load average 8.95 drifted q23 by 2x.
set -Eeuo pipefail

REPO=/Users/hosseinaghaei/Desktop/projects/dw
LAB=$REPO/pagesize
CNF="$LAB/my-32k-sf4-t1exact.cnf"
SOCK="$LAB/s32-sf4.sock"
ME=$(id -un)
PRE="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');"
IDX=(idx_ws_q66 idx_cs_q66)

start() {
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && return
  mariadbd --defaults-file="$CNF" >>"$LAB/32k-sf4.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && return
    sleep 1
  done
  echo "server did not start" >&2; exit 1
}
sql() { mariadb --socket="$SOCK" --user="$ME" -B -N tpcds -e "$1"; }
now() { python3 -c 'import time;print(time.time())'; }
el()  { python3 -c "print(f'{$2-$1:.1f}')"; }

start

# ---------------------------------------------------------------- create
for i in "${IDX[@]}"; do
  if [ -z "$(sql "select 1 from information_schema.statistics
                  where table_schema='tpcds' and index_name='$i' limit 1")" ]; then
    echo "=== creating $i"
    case "$i" in
      idx_ws_q66) ddl="CREATE INDEX idx_ws_q66 ON web_sales
          (ws_ship_mode_sk, ws_sold_date_sk, ws_sold_time_sk, ws_warehouse_sk,
           ws_sales_price, ws_quantity, ws_net_paid_inc_ship)" ;;
      idx_cs_q66) ddl="CREATE INDEX idx_cs_q66 ON catalog_sales
          (cs_ship_mode_sk, cs_sold_date_sk, cs_sold_time_sk, cs_warehouse_sk,
           cs_ext_sales_price, cs_quantity, cs_net_paid_inc_tax)" ;;
    esac
    time mariadb --socket="$SOCK" --user="$ME" tpcds \
      -e "SET SESSION alter_algorithm='INPLACE'; $ddl"
  else
    echo "=== $i already exists"
  fi
done
mariadb --socket="$SOCK" --user="$ME" tpcds -e "ANALYZE TABLE web_sales, catalog_sales" >/dev/null

toggle() {   # $1 = IGNORED | 'NOT IGNORED'
  mariadb --socket="$SOCK" --user="$ME" tpcds \
    -e "ALTER TABLE web_sales ALTER INDEX idx_ws_q66 $1"
  mariadb --socket="$SOCK" --user="$ME" tpcds \
    -e "ALTER TABLE catalog_sales ALTER INDEX idx_cs_q66 $1"
}
toggle IGNORED

for i in "${IDX[@]}"; do
  s=$(sql "select round(stat_value*@@innodb_page_size/1048576)
           from mysql.innodb_index_stats where database_name='tpcds'
             and index_name='$i' and stat_name='size'")
  echo "=== $i occupies ${s:-?} MB"
done

# ------------------------------------------------- 1. q66, indexes off/on
runq() {  # $1 = file -> prints seconds
  local t0 t1
  t0=$(now)
  { echo "$PRE"; cat "$1"; } | mariadb --socket="$SOCK" --user="$ME" -B tpcds \
    > "/tmp/q66-$2.out" 2>"/tmp/q66-$2.err" || true
  t1=$(now); el "$t0" "$t1"
}

echo
echo "=== q66 as it runs today (queries/tuned/query66.sql), indexes off vs on"
for p in 1 2 3; do
  toggle IGNORED       >/dev/null; a=$(runq "$REPO/queries/tuned/query66.sql" off)
  toggle "NOT IGNORED" >/dev/null; b=$(runq "$REPO/queries/tuned/query66.sql" on)
  printf '  pass %s   IGNORED %7ss   NOT IGNORED %7ss\n' "$p" "$a" "$b"
done
cmp -s /tmp/q66-off.out /tmp/q66-on.out \
  && echo "  answers identical with and without the indexes" \
  || echo "  ** ANSWERS DIFFER with the indexes -- investigate before anything else **"

# --------------------------------- 2. her rewrite on top, indexes enabled
echo
echo "=== with both indexes enabled: current query vs Aysha's rewrite"
toggle "NOT IGNORED" >/dev/null
for p in 1 2 3; do
  a=$(runq "$REPO/queries/tuned/query66.sql" ours)
  b=$(runq "$REPO/queries/optimized/Aysha/q66/q66-Optimized.sql" hers)
  printf '  pass %s   ours %7ss   hers %7ss\n' "$p" "$a" "$b"
done
if cmp -s /tmp/q66-ours.out /tmp/q66-hers.out; then echo "  OUTPUT: IDENTICAL"
elif diff -q <(sort /tmp/q66-ours.out) <(sort /tmp/q66-hers.out) >/dev/null; then
  echo "  OUTPUT: same rows, different order"
else echo "  OUTPUT: ** DIFFERS **"; diff /tmp/q66-ours.out /tmp/q66-hers.out | head -10; fi

# ----------------------------------------- 3. collateral damage, whole suite
echo
echo "=== whole tier-4/5 suite, alternating, to catch what the indexes cost elsewhere"
for pass in 1 2; do
  toggle IGNORED       >/dev/null
  python3 "$LAB/bench-tuned.py" "$SOCK" "q66idx-off-$pass" --timeout 5400 | tail -1
  toggle "NOT IGNORED" >/dev/null
  python3 "$LAB/bench-tuned.py" "$SOCK" "q66idx-on-$pass" --timeout 5400 | tail -1
done

toggle IGNORED >/dev/null
echo
echo "=== left IGNORED, which is the state every committed result was measured in."
echo "    To enable deliberately:"
echo "      ALTER TABLE web_sales     ALTER INDEX idx_ws_q66 NOT IGNORED;"
echo "      ALTER TABLE catalog_sales ALTER INDEX idx_cs_q66 NOT IGNORED;"
