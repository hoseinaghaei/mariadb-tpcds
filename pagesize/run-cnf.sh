#!/bin/bash
#
# run-cnf.sh <CNF> <TAG>
#
# Runs the tier-4/5 suite on the 32K / SF=4 datadir using an arbitrary config,
# so individual settings can be bisected.  Prints the memory-relevant values
# first: a config that exceeds RAM gets killed mid-run rather than returning a
# slow number, so the budget is worth seeing before the run starts.
set -Eeuo pipefail

CNF="${1:?usage: run-cnf.sh <CNF> <TAG>}"
TAG="${2:?usage: run-cnf.sh <CNF> <TAG>}"
LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
SOCK="$LAB/s32-sf4.sock"
ME=$(id -un)

stop_it() {
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || return 0
  mariadb-admin --socket="$SOCK" --user="$ME" shutdown
  for i in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || return 0
    sleep 1
  done
  return 1
}

stop_it
mariadbd --defaults-file="$CNF" >> "$LAB/32k-sf4.err" 2>&1 &
for i in $(seq 1 300); do
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break
  sleep 1
done
mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 \
  || { echo "did not start -- see $LAB/32k-sf4.err" >&2; exit 1; }

CLI="mariadb --socket=$SOCK --user=$ME"
echo "=== $TAG  ($(basename "$CNF"))"
$CLI -N -B -e "
select concat('  ', rpad(variable_name,38), variable_value)
from information_schema.global_variables
where variable_name in ('innodb_buffer_pool_size','tmp_table_size','max_heap_table_size',
 'aria_pagecache_buffer_size','sort_buffer_size','join_buffer_size','join_cache_level',
 'join_buffer_space_limit','innodb_read_io_threads','innodb_read_ahead_threshold',
 'innodb_old_blocks_pct','key_buffer_size','innodb_buffer_pool_dump_pct','use_stat_tables')
order by variable_name"
$CLI -N -B -e "select concat('  peak memory budget ~',
  round((@@innodb_buffer_pool_size + @@tmp_table_size + @@aria_pagecache_buffer_size
         + @@sort_buffer_size + @@join_buffer_space_limit + @@key_buffer_size)/1073741824,1),
  'G of 16G')"

python3 "$LAB/run-bench.py" 32 "$TAG" --socket "$SOCK" --timeout 5400 | tail -2
stop_it
