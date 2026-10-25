#!/bin/bash
# Interleaved A/B: global split-off vs the per-query tuned files, back to back
# in one pass so both see the same OS cache state.  Comparing runs made hours
# apart is what produced the unexplained 8.6% gap.
set -Eeuo pipefail
LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
ME=$(id -un); SOCK="$LAB/s32-sf4.sock"
SERVICE=$(brew services list 2>/dev/null | awk 'NR>1 && $1 ~ /^mariadb(@|$)/ && $2=="started" {print $1; exit}')
restore(){ local rc=$?; [[ -n "${SERVICE:-}" ]] && brew services start "$SERVICE" >/dev/null 2>&1 || true; exit $rc; }
trap restore EXIT INT TERM
[[ -n "$SERVICE" ]] && { brew services stop "$SERVICE" >/dev/null 2>&1; sleep 3; }
stop_it(){ mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || return 0
  mariadb-admin --socket="$SOCK" --user="$ME" shutdown
  for _ in $(seq 1 300); do mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || return 0; sleep 1; done; }
start_it(){ mariadbd --defaults-file="$1" >>"$LAB/ab.err" 2>&1 &
  for _ in $(seq 1 300); do mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && return 0; sleep 1; done
  echo "no start" >&2; exit 1; }
for pass in 1 2; do
  stop_it; start_it "$LAB/my-32k-sf4-t6.cnf"
  python3 "$LAB/bench-tuned.py" "$SOCK" "ab${pass}-globaloff" --timeout 5400 | tail -1
  stop_it; start_it "$LAB/my-32k-sf4-t1exact.cnf"
  python3 "$LAB/bench-tuned.py" "$SOCK" "ab${pass}-perquery" --timeout 5400 | tail -1
done
stop_it
