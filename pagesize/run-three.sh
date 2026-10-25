#!/bin/bash
#
# run-three.sh — the tuned tier-4/5 suite against three configurations:
#
#   A  SF=4, 32K, T1 tuning, sample 160   the best configuration found
#   B  SF=1, 32K, stock settings          page size changed, nothing else
#   C  SF=1, 32K, everything from A       does the SF=4 tuning transfer down?
#
# B and C differ only by the tuning block, so C-vs-B is what the SF=4 tuning
# is worth at SF=1, and A-vs-C is what the scale factor is worth with the
# configuration held constant.
#
# The live server is stopped for the duration: it reserves its own 8 GB pool,
# and two 8 GB pools on a 16 GB machine is what killed earlier runs.
set -Eeuo pipefail

LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
ME=$(id -un)

SERVICE=$(brew services list 2>/dev/null | awk 'NR>1 && $1 ~ /^mariadb(@|$)/ && $2=="started" {print $1; exit}')
restore() {
  local rc=$?
  if [[ -f "$LAB/KEEP-LIVE-OFF" ]]; then
    echo "--- leaving the live server stopped (pagesize/KEEP-LIVE-OFF present)"
  elif [[ -n "${SERVICE:-}" ]]; then
    brew services start "$SERVICE" >/dev/null 2>&1 || true
  fi
  exit $rc
}
trap restore EXIT INT TERM
[[ -n "$SERVICE" ]] && { echo "--- stopping live server"; brew services stop "$SERVICE" >/dev/null 2>&1; sleep 3; }

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
  mariadbd --defaults-file="$2" >>"$LAB/three.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$3" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
  mariadb-admin --socket="$3" --user="$ME" ping >/dev/null 2>&1 \
    || { echo "$1 did not start" >&2; exit 1; }
  python3 "$LAB/bench-tuned.py" "$3" "$1" --timeout 5400 | tail -3
  stop_all
}

run A-sf4-best   "$LAB/my-32k-sf4-t1exact.cnf" "$LAB/s32-sf4.sock"
run B-sf1-stock  "$LAB/my-32k.cnf"             "$LAB/s32.sock"
run C-sf1-sf4cfg "$LAB/my-32k-sf4cfg.cnf"      "$LAB/s32.sock"

echo "=== all three done"
