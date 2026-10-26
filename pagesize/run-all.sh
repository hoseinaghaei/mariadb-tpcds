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
# Default is 32 alone, because 32 is the only page size still built.  The
# 8K, 16K and 64K datadirs were deleted on 2026-10-26 once the page-size
# comparison was finished and reported (report/20, report/21) -- they were
# 28 GB of SF=1 instances plus a 31 GB 16K/SF=4 one, and only their results
# are needed now, which are kept under pagesize/results/.
#
# To run the comparison again, rebuild first:  ./build-instance.sh 8 16 64
# and ./build-sf4.sh for the SF=4 side.  Passing a page size whose datadir
# does not exist will fail at ctl.sh start.
if [[ $# -gt 0 ]]; then PAGES=("$@"); else PAGES=(32); fi

"$LAB/ctl.sh" stop-all

for P in "${PAGES[@]}"; do
  echo "=============================================== ${P}K"
  "$LAB/ctl.sh" start "$P"
  python3 "$LAB/run-bench.py" "$P" $TAG
  "$LAB/ctl.sh" stop "$P"
done

echo "=============================================== done"
