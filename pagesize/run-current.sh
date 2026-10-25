#!/bin/bash
#
# run-current.sh — current response time of the tuned tier-4/5 suite, at both
# scale factors, under the standing configuration (sql/tpcds-tuned.cnf).
#
# queries/tuned/ now substitutes the team's optimized query for 19 of the 40,
# so the earlier A/C figures (942.1s and 157.8s) are superseded -- those were
# measured when it still held the bare TPC-DS queries.
#
# Honours pagesize/KEEP-LIVE-OFF: the live 3306 server stays stopped.
set -Eeuo pipefail

LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
ME=$(id -un)

stop_all() {
  for s in "$LAB"/s32.sock "$LAB"/s32-sf4.sock; do
    [[ -S "$s" ]] || continue
    mariadb-admin --socket="$s" --user="$ME" ping >/dev/null 2>&1 || continue
    mariadb-admin --socket="$s" --user="$ME" shutdown
    for _ in $(seq 1 300); do
      mariadb-admin --socket="$s" --user="$ME" ping >/dev/null 2>&1 || break
      sleep 1
    done
  done
}

run() {   # $1 label  $2 cnf  $3 socket
  stop_all
  mariadbd --defaults-file="$2" >>"$LAB/current.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$3" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
  mariadb-admin --socket="$3" --user="$ME" ping >/dev/null 2>&1 \
    || { echo "$1 did not start" >&2; exit 1; }
  python3 "$LAB/bench-tuned.py" "$3" "$1" --timeout 5400 | tail -2
  stop_all
}

run current-sf4 "$LAB/my-32k-sf4-t1exact.cnf" "$LAB/s32-sf4.sock"
run current-sf1 "$LAB/my-32k-sf4cfg.cnf"      "$LAB/s32.sock"
echo "=== done"
