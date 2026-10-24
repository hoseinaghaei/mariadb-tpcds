#!/bin/bash
#
# run-all.sh [--tag TAG] [PAGE_KB ...]
#
# Benchmarks each page-size instance in turn: start it (cold buffer pool),
# run all 99 queries serially, stop it.  Never two at once -- each reserves
# an 8 GB pool on a 16 GB machine.
set -Eeuo pipefail

LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
TAG=""
if [[ "${1:-}" == "--tag" ]]; then TAG="$2"; shift 2; fi
if [[ $# -gt 0 ]]; then PAGES=("$@"); else PAGES=(8 16 32 64); fi

"$LAB/ctl.sh" stop-all

for P in "${PAGES[@]}"; do
  echo "=============================================== ${P}K"
  "$LAB/ctl.sh" start "$P"
  python3 "$LAB/run-bench.py" "$P" $TAG
  "$LAB/ctl.sh" stop "$P"
done

echo "=============================================== done"
