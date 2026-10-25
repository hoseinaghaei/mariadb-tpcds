#!/bin/bash
#
# test-q59-stability.sh — is q59's plan decided by the random ANALYZE sample?
#
# q59 has been measured at both ~15s and ~155s with byte-identical output.
# Six causes have been eliminated by direct test: histograms, InnoDB
# persistent stats being stale, join_cache_level, MRR, cache residency and
# use_stat_tables.  T1's own configuration, rebuilt exactly, gives 166s.
#
# What is left is that InnoDB samples RANDOM pages when it recomputes
# persistent statistics, so each ANALYZE draws a different sample.  A query
# balanced between two plans an order of magnitude apart can flip on that
# alone.
#
# This re-ANALYZEs and re-times q59 several times.  Times that vary while
# nothing else changes confirm it.
set -Eeuo pipefail

LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
CNF="$LAB/my-32k-sf4-t1exact.cnf"
SOCK="$LAB/s32-sf4.sock"
ME=$(id -un)
N="${1:-5}"
Q="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');"
SQL=$(tr '\n' ' ' < /Users/hosseinaghaei/Desktop/projects/dw/queries/mariadb/query59.sql | sed 's/;[[:space:]]*$//')

mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || {
  mariadbd --defaults-file="$CNF" >>"$LAB/32k-sf4.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
}
CLI="mariadb --socket=$SOCK --user=$ME"
$CLI -N -B -e "select concat('sample_pages=', @@innodb_stats_persistent_sample_pages,
  '  use_stat_tables=', @@use_stat_tables,
  '  EITS=', (select count(*) from mysql.column_stats))"

echo
printf '%-6s %-10s %-12s %s\n' iter q59 plan-shape "n_diff_rows (store_sales stat)"
for i in $(seq 1 "$N"); do
  # fresh random sample for the tables q59 drives on
  $CLI tpcds -e "analyze table store_sales, date_dim, store" >/dev/null
  # a cardinality the plan choice is sensitive to
  CARD=$($CLI -N -B -e "select stat_value from mysql.innodb_index_stats
          where database_name='tpcds' and table_name='store_sales'
            and index_name='idx_ss_sold_date_sk_store_sales_price'
            and stat_name='n_diff_pfx01' limit 1" 2>/dev/null || echo '-')
  T=$( { /usr/bin/time -p $CLI -B tpcds -e "$Q $SQL" >/dev/null; } 2>&1 | awk '/real/{print $2}' )
  SHAPE=$($CLI -B tpcds -e "$Q EXPLAIN $SQL" 2>/dev/null \
          | awk -F'\t' 'NR>1 && $10 ~ /BKAH|Rowid-ordered/ {n++} END{print (n?"BKAH/ROR x"n:"plain")}')
  printf '%-6s %-10s %-12s %s\n' "$i" "${T}s" "$SHAPE" "$CARD"
done

cat <<'EOF'

Times that vary across iterations, with nothing changed but the ANALYZE
sample, mean q59's plan is decided by which random pages InnoDB happened to
read.  That makes any suite total containing it uncertain by the size of the
swing, regardless of the setting under test.
EOF
