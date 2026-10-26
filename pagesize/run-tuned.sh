#!/bin/bash
#
# run-tuned.sh <TAG> [--analyze-persistent] [--dump-pct N]
#
# Runs the tier-4/5 suite on the 32K / SF=4 instance using the tuned config,
# against the 2403.4s baseline.  Verifies every setting actually took effect
# before measuring -- a config line that the server silently ignored would
# otherwise look like "no effect".
set -Eeuo pipefail

# The local macOS databases were removed on 2026-10-26; see
# pagesize/require-local-db.sh.  Fail immediately and say so, rather than
# spending 300s in a start-up retry loop that ends in "did not start".
source /Users/hosseinaghaei/Desktop/projects/dw/pagesize/require-local-db.sh
require_local_db /Users/hosseinaghaei/Desktop/projects/dw/pagesize/data-32k-sf4 || exit 1

TAG="${1:?usage: run-tuned.sh <TAG> [--analyze-persistent] [--dump-pct N]}"; shift
ANALYZE=0; DUMPPCT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --analyze-persistent) ANALYZE=1; shift ;;
    --dump-pct) DUMPPCT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
CNF="$LAB/my-32k-sf4-tuned.cnf"
SOCK="$LAB/s32-sf4.sock"
ME=$(id -un)

if [[ -n "$DUMPPCT" ]]; then
  grep -v 'innodb_buffer_pool_dump_pct' "$CNF" > "$CNF.tmp" && mv "$CNF.tmp" "$CNF"
  printf 'innodb_buffer_pool_dump_pct = %s\n' "$DUMPPCT" >> "$CNF"
fi

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
  mariadbd --defaults-file="$CNF" >> "$LAB/32k-sf4.err" 2>&1 &
  for i in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 \
    || { echo "did not start -- see $LAB/32k-sf4.err" >&2; exit 1; }
}

stop_it
start_it
CLI="mariadb --socket=$SOCK --user=$ME"

echo "=== settings in effect for $TAG"
$CLI -N -B -e "
select concat('  ', rpad(variable_name,38), variable_value)
from information_schema.global_variables
where variable_name in ('innodb_page_size','innodb_stats_persistent_sample_pages',
 'tmp_table_size','max_heap_table_size','aria_pagecache_buffer_size',
 'innodb_read_io_threads','innodb_read_ahead_threshold','innodb_old_blocks_pct',
 'sort_buffer_size','join_cache_level','join_buffer_size','join_buffer_space_limit',
 'key_buffer_size','innodb_buffer_pool_dump_pct')
order by variable_name"
echo -n "  mrr: "; $CLI -N -B -e "select substring_index(substring_index(@@optimizer_switch,'mrr=',-1),',',1)"

# fail loudly rather than measuring a setting that did not take
for chk in "tmp_table_size=1610612736" "join_cache_level=8" "sort_buffer_size=67108864" \
           "innodb_read_io_threads=8" "innodb_old_blocks_pct=25"; do
  v="${chk%%=*}"; want="${chk##*=}"
  got=$($CLI -N -B -e "select @@$v")
  [[ "$got" == "$want" ]] || { echo "SETTING DID NOT TAKE: $v is $got, expected $want" >&2; exit 1; }
done

if (( ANALYZE )); then
  echo "=== collecting engine-independent statistics and histograms"
  T=$($CLI -N -B -e "select group_concat(table_name) from information_schema.tables where table_schema='tpcds'")
  t0=$SECONDS
  for tbl in $(echo "$T" | tr ',' ' '); do
    $CLI tpcds -e "ANALYZE TABLE $tbl PERSISTENT FOR ALL" > /dev/null
  done
  echo "  took $((SECONDS - t0))s"
  $CLI -N -B -e "select concat('  table_stats=',(select count(*) from mysql.table_stats),
      '  column_stats=',(select count(*) from mysql.column_stats),
      '  index_stats=',(select count(*) from mysql.index_stats))"
  stop_it; start_it   # cold pool again
fi

python3 "$LAB/run-bench.py" 32 "$TAG" --socket "$SOCK" --timeout 5400 | tail -2
stop_it
