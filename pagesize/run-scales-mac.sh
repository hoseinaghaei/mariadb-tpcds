#!/bin/bash
#
# run-scales-mac.sh [sf ...] -- benchmark the tier-4/5 tuned suite on the
# macOS host, one scale factor at a time, tagging results by environment.
#
# The host has exactly two instances built (pagesize/data-32k at SF=1 and
# data-32k-sf4 at SF=4), so only those two scale factors can be asked for
# here.  The professor's multi-scale run is the container one
# (./run-scales.sh), which builds whatever scale it is given.
#
# Results land in pagesize/results/mac-sf<N>/ so they sit alongside the
# container's results/sf<N>-tuned/ without either overwriting the other, and
# so analysis/collect.py can tell which environment produced which.
#
# Honours pagesize/KEEP-LIVE-OFF: the live 3306 server stays stopped.
#
# One instance at a time -- each reserves an 8 GB buffer pool.
set -Eeuo pipefail

# The local macOS databases were removed on 2026-10-26; see
# pagesize/require-local-db.sh.  Fail immediately and say so, rather than
# spending 300s in a start-up retry loop that ends in "did not start".
source /Users/hosseinaghaei/Desktop/projects/dw/pagesize/require-local-db.sh
require_local_db /Users/hosseinaghaei/Desktop/projects/dw/pagesize/data-32k-sf4 || exit 1

LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
ME=$(id -un)

# scale -> config, socket
cnf_for() { case "$1" in
  1) echo "$LAB/my-32k-sf4cfg.cnf" ;;
  4) echo "$LAB/my-32k-sf4-t1exact.cnf" ;;
  *) echo "" ;; esac; }
sock_for() { case "$1" in
  1) echo "$LAB/s32.sock" ;;
  4) echo "$LAB/s32-sf4.sock" ;;
  *) echo "" ;; esac; }

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

SFS=("$@")
if [ ${#SFS[@]} -eq 0 ]; then SFS=(1 4); fi

for SF in "${SFS[@]}"; do
  CNF=$(cnf_for "$SF"); SOCK=$(sock_for "$SF")
  if [[ -z "$CNF" ]]; then
    echo "no macOS instance for SF=$SF (only 1 and 4 are built); skipping" >&2
    continue
  fi

  echo "=============================================== macOS SF=$SF"
  stop_all
  mariadbd --defaults-file="$CNF" >>"$LAB/scales-mac.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 \
    || { echo "SF=$SF did not start" >&2; exit 1; }

  python3 "$LAB/bench-tuned.py" "$SOCK" "mac-sf$SF" --timeout 5400 | tail -2
  stop_all
done

echo "=============================================== done"
echo "results in $LAB/results/mac-sf*/"
