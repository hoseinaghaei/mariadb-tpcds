#!/bin/bash
#
# run-sf4.sh [PAGE_KB ...]     default: 32 16
#
# Benchmarks the SF=4 instances in turn, one at a time, each started cold.
# Results go to pagesize/results/<P>k-sf4/.
set -Eeuo pipefail

LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
ME=$(id -un)
if [[ $# -gt 0 ]]; then PAGES=("$@"); else PAGES=(32 16); fi

stop_one() {
  local P=$1
  mariadb-admin --socket="$LAB/s${P}-sf4.sock" --user="$ME" ping >/dev/null 2>&1 || return 0
  mariadb-admin --socket="$LAB/s${P}-sf4.sock" --user="$ME" shutdown
  for i in $(seq 1 300); do
    mariadb-admin --socket="$LAB/s${P}-sf4.sock" --user="$ME" ping >/dev/null 2>&1 || return 0
    sleep 1
  done
  echo "${P}K/sf4 would not stop" >&2; return 1
}

# nothing else may be running: each instance reserves an 8 GB pool
"$LAB/ctl.sh" stop-all >/dev/null 2>&1 || true
for P in 4 8 16 32 64; do stop_one "$P" 2>/dev/null || true; done

for P in "${PAGES[@]}"; do
  echo "=============================================== ${P}K / SF=4"
  mariadbd --defaults-file="$LAB/my-${P}k-sf4.cnf" >> "$LAB/${P}k-sf4.err" 2>&1 &
  for i in $(seq 1 300); do
    mariadb-admin --socket="$LAB/s${P}-sf4.sock" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
  mariadb-admin --socket="$LAB/s${P}-sf4.sock" --user="$ME" ping >/dev/null 2>&1 \
    || { echo "${P}K/sf4 did not start" >&2; exit 1; }

  python3 "$LAB/run-bench.py" "$P" sf4 --socket "$LAB/s${P}-sf4.sock" --timeout 5400
  stop_one "$P"
done

echo "=============================================== SF=4 runs done"
