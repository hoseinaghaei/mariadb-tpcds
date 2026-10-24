#!/bin/bash
#
# run-exclusive.sh <CNF> <TAG> [<CNF> <TAG> ...]
#
# Stops the live Homebrew MariaDB (port 3306) for the duration, runs the given
# configs one at a time on the 32K/SF=4 datadir, then restarts it.
#
# Why: the live server reserves an 8 GB buffer pool of its own.  With a lab
# instance also reserving 8 GB on a 16 GB machine, runs get killed mid-pass by
# memory pressure rather than returning a number.  Two runs were lost that way.
#
# The restart is in a trap, so the live server comes back even if a run fails,
# the script is interrupted, or a config is rejected.
set -Eeuo pipefail

LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
ME=$(id -un)
SERVICE=$(brew services list 2>/dev/null | awk 'NR>1 && $1 ~ /^mariadb(@|$)/ && $2=="started" {print $1; exit}')

restore() {
  local rc=$?
  if [[ -n "${SERVICE:-}" ]]; then
    echo "--- restarting live server ($SERVICE)"
    brew services start "$SERVICE" >/dev/null 2>&1 || \
      echo "    WARNING: could not restart $SERVICE -- run: brew services start $SERVICE" >&2
    for i in $(seq 1 120); do
      mariadb -N -B -e "select 1" >/dev/null 2>&1 && { echo "    live 3306 is back up"; break; }
      sleep 1
    done
  fi
  exit $rc
}
trap restore EXIT INT TERM

if [[ -n "$SERVICE" ]]; then
  echo "--- stopping live server ($SERVICE) to free its 8 GB pool"
  brew services stop "$SERVICE" >/dev/null 2>&1
  for i in $(seq 1 120); do
    mariadb -N -B -e "select 1" >/dev/null 2>&1 || break
    sleep 1
  done
  sleep 3
  top -l 1 -n 0 | awk '/PhysMem/{print "    after stopping: " $0}'
else
  echo "--- no running Homebrew mariadb service found; continuing"
fi

while [[ $# -gt 0 ]]; do
  "$LAB/run-cnf.sh" "$1" "$2"
  shift 2
done
