#!/bin/bash
#
# test-odirect.sh — is a mariadbd restart actually a cold start on this host?
#
# MariaDB's docs list unbuffered I/O as unsupported on macOS.  If that applies
# here, InnoDB reads go through the macOS file cache, restarting the server
# empties only the buffer pool, and a "cold" run is served from the OS cache.
#
# The test runs one large scan three times:
#
#   A  after a restart, pool cold          -- baseline
#   B  immediately again, pool warm        -- the fully-cached time
#   C  after another restart, pool cold    -- but the OS cache is now hot
#
# C ~ B  => the OS cache is serving the reads; restarts are NOT cold.
# C ~ A  => direct I/O is working; restarts are genuinely cold.
set -Eeuo pipefail

# The local macOS databases were removed on 2026-10-26; see
# pagesize/require-local-db.sh.  Fail immediately and say so, rather than
# spending 300s in a start-up retry loop that ends in "did not start".
source /Users/hosseinaghaei/Desktop/projects/dw/pagesize/require-local-db.sh
require_local_db /Users/hosseinaghaei/Desktop/projects/dw/pagesize/data-32k-sf4 || exit 1

LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
CNF="$LAB/my-32k-sf4.cnf"
SOCK="$LAB/s32-sf4.sock"
ME=$(id -un)
Q="select count(*), sum(ss_sales_price) from store_sales"

stop_it() {
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || return 0
  mariadb-admin --socket="$SOCK" --user="$ME" shutdown
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || return 0
    sleep 1
  done
}
start_it() {
  mariadbd --defaults-file="$CNF" >>"$LAB/32k-sf4.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "server did not start" >&2; exit 1
}
timed() {   # prints elapsed seconds and InnoDB physical reads for one run
  local t0 t1 r0 r1
  r0=$(mariadb --socket="$SOCK" --user="$ME" -N -B -e \
       "select variable_value from information_schema.global_status where variable_name='Innodb_buffer_pool_reads'")
  t0=$(python3 -c 'import time;print(time.time())')
  mariadb --socket="$SOCK" --user="$ME" -N -B tpcds -e "$Q" >/dev/null
  t1=$(python3 -c 'import time;print(time.time())')
  r1=$(mariadb --socket="$SOCK" --user="$ME" -N -B -e \
       "select variable_value from information_schema.global_status where variable_name='Innodb_buffer_pool_reads'")
  python3 -c "print(f'{$t1-$t0:7.1f}s   InnoDB physical reads: {$r1-$r0:,}')"
}

echo "flush method: $(mariadb --socket=$SOCK --user=$ME -N -B -e 'select @@innodb_flush_method' 2>/dev/null || echo '(server down)')"

stop_it; start_it
echo -n "A  restart, pool cold, OS cache cold-ish : "; timed
echo -n "B  immediately again, pool warm          : "; timed
stop_it; start_it
echo -n "C  restart, pool cold, OS cache HOT      : "; timed
stop_it

cat <<'EOF'

Reading it:
  C close to B  -> the macOS file cache is serving the reads.  Restarts are
                   not cold, and every "cold start" number in the reports is
                   partly warm.  `sudo purge` before each run would be needed.
  C close to A  -> direct I/O is in effect and restarts are genuinely cold.
EOF
