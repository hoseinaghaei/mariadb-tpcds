#!/bin/bash
#
# index-usage.sh <PAGE_KB> <SF>
#
# Runs the 99-query suite with userstat on and records which indexes were
# actually read.  INFORMATION_SCHEMA.INDEX_STATISTICS only lists indexes with
# a non-zero read count, so "unused" is the full index list minus that.
#
# Counters are zeroed with FLUSH INDEX_STATISTICS immediately before the run,
# so the numbers cover exactly these 99 queries and nothing else.
#
# Writes pagesize/results/idxuse-<P>k-sf<SF>.tsv  (every index, reads, used?)
set -Eeuo pipefail

P="${1:?usage: index-usage.sh <PAGE_KB> <SF>}"
SF="${2:?usage: index-usage.sh <PAGE_KB> <SF>}"
LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
ME=$(id -un)

if [[ "$SF" == "1" ]]; then
  CNF="$LAB/my-${P}k.cnf"; SOCK="$LAB/s${P}.sock"; TAG="idxuse"
else
  CNF="$LAB/my-${P}k-sf${SF}.cnf"; SOCK="$LAB/s${P}-sf${SF}.sock"; TAG="idxuse-sf${SF}"
fi
OUT="$LAB/results/idxuse-${P}k-sf${SF}.tsv"

stop_it() {
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || return 0
  mariadb-admin --socket="$SOCK" --user="$ME" shutdown
  for i in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || return 0
    sleep 1
  done
  return 1
}

# userstat is dynamic, but persist it so a restart keeps it
grep -q '^userstat' "$CNF" || printf 'userstat = 1\n' >> "$CNF"

stop_it
mariadbd --defaults-file="$CNF" >> "$LAB/${P}k-sf${SF}.err" 2>&1 &
for i in $(seq 1 300); do
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break
  sleep 1
done
mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 \
  || { echo "${P}K/sf${SF} did not start" >&2; exit 1; }

CLI="mariadb --socket=$SOCK --user=$ME"
$CLI -e "SET GLOBAL userstat=1; FLUSH INDEX_STATISTICS; FLUSH TABLE_STATISTICS;"
echo "${P}K/SF=${SF}: userstat=$($CLI -N -B -e 'select @@userstat'), counters zeroed"

python3 "$LAB/run-bench.py" "$P" "$TAG" --socket "$SOCK" --timeout 5400 | tail -2

# every index, left-joined onto what was actually read
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
