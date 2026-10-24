#!/bin/bash
#
# index-usage-sampled.sh <PAGE_KB> <SF> <SAMPLE_PAGES>
#
# As index-usage.sh, but sets innodb_stats_persistent_sample_pages first and
# re-ANALYZEs, so timing and index usage are both measured against the deeper
# statistics.
#
# Note on what the sample actually covers: the setting counts PAGES, so at a
# given page size it samples a fixed number of bytes regardless of how big the
# table is.  At SF=4 the tables are ~4x larger than at SF=1, so the default 20
# pages covers ~4x less of each table -- deeper sampling has more room to
# matter here than it did at SF=1.
#
# Writes pagesize/results/idxuse-<P>k-sf<SF>-stats<N>.tsv and the usual
# per-query JSON under results/<P>k-idxuse-sf<SF>-stats<N>/.
set -Eeuo pipefail

P="${1:?usage: index-usage-sampled.sh <PAGE_KB> <SF> <SAMPLE_PAGES>}"
SF="${2:?need scale factor}"
S="${3:?need sample pages}"
LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
ME=$(id -un)

if [[ "$SF" == "1" ]]; then
  CNF="$LAB/my-${P}k.cnf"; SOCK="$LAB/s${P}.sock"
else
  CNF="$LAB/my-${P}k-sf${SF}.cnf"; SOCK="$LAB/s${P}-sf${SF}.sock"
fi
TAG="idxuse-sf${SF}-stats${S}"
OUT="$LAB/results/idxuse-${P}k-sf${SF}-stats${S}.tsv"

stop_it() {
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || return 0
  mariadb-admin --socket="$SOCK" --user="$ME" shutdown
  for i in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || return 0
    sleep 1
  done
  return 1
}

start_it() {
  mariadbd --defaults-file="$CNF" >> "$LAB/${P}k-sf${SF}.err" 2>&1 &
  for i in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 \
    || { echo "${P}K/sf${SF} did not start" >&2; exit 1; }
}

grep -q '^userstat' "$CNF" || printf 'userstat = 1\n' >> "$CNF"
grep -v 'innodb_stats_persistent_sample_pages' "$CNF" > "$CNF.tmp" && mv "$CNF.tmp" "$CNF"
printf 'innodb_stats_persistent_sample_pages = %s\n' "$S" >> "$CNF"

stop_it
start_it
CLI="mariadb --socket=$SOCK --user=$ME"
got=$($CLI -N -B -e "select @@innodb_stats_persistent_sample_pages")
[[ "$got" == "$S" ]] || { echo "sample setting did not take: $got" >&2; exit 1; }
echo "${P}K/SF=${SF}: sample_pages=$got, re-analyzing"

T=$($CLI -N -B -e "select group_concat(table_name) from information_schema.tables where table_schema='tpcds'")
$CLI tpcds -e "analyze table $T" > /dev/null

# restart for a cold pool, matching every other run, then zero the counters
stop_it
start_it
$CLI -e "SET GLOBAL userstat=1; FLUSH INDEX_STATISTICS; FLUSH TABLE_STATISTICS;"
echo "${P}K/SF=${SF}/sample=${S}: counters zeroed, starting run"

python3 "$LAB/run-bench.py" "$P" "$TAG" --socket "$SOCK" --timeout 5400 | tail -2

$CLI -N -B -e "
select s.table_name, s.index_name,
       coalesce(i.rows_read, 0) as rows_read,
       case when i.rows_read is null or i.rows_read = 0 then 'UNUSED' else 'used' end
from (select table_name, index_name from information_schema.statistics
      where table_schema='tpcds' group by table_name, index_name) s
left join information_schema.index_statistics i
       on i.table_schema='tpcds' and i.table_name=s.table_name
      and i.index_name=s.index_name
order by coalesce(i.rows_read,0) desc, s.table_name, s.index_name" > "$OUT"

echo "wrote $OUT"
awk -F'\t' '{n++; if($4=="UNUSED") u++} END{printf "  %d indexes, %d unused, %d used\n", n, u, n-u}' "$OUT"
stop_it
