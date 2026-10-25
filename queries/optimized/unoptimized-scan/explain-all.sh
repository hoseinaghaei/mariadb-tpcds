#!/bin/bash
# explain-all.sh — access paths for the queries still on the original.
# Looks for fact tables reached by scan rather than index, and for the
# date_dim-last join order that cost q68 and q46 their 4.9x and 1.9x.
set -Eeuo pipefail
REPO=/Users/hosseinaghaei/Desktop/projects/dw
LAB=$REPO/pagesize; SOCK="$LAB/s32-sf4.sock"; ME=$(id -un)
PRE="SET SESSION sql_mode=CONCAT(@@sql_mode,',IGNORE_SPACE,PIPES_AS_CONCAT');"
mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || {
  mariadbd --defaults-file="$LAB/my-32k-sf4-t1exact.cnf" >>"$LAB/32k-sf4.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break; sleep 1; done
}
CLI="mariadb --socket=$SOCK --user=$ME"
QS=("$@"); if [ ${#QS[@]} -eq 0 ]; then QS=(77 70 66 71 87 65 82 58 35 38); fi
for n in "${QS[@]}"; do
  SQL=$(grep -v '^[[:space:]]*--' "$REPO/queries/mariadb/query$n.sql" | tr '\n' ' ' | sed 's/;[[:space:]]*$//')
  echo "=== q$n"
  $CLI -B tpcds -e "$PRE EXPLAIN $SQL" 2>/dev/null \
    | awk -F'\t' 'NR>1 {printf "   %-22s %-9s %-26s %-10s %s\n",$3,$4,$6,$9,$10}' \
    | grep -E "store_sales|catalog_sales|web_sales|store_returns|catalog_returns|web_returns|inventory|ALL " \
    | head -8
done
