#!/bin/bash
#
# stats-sweep.sh <PAGE_KB> <SAMPLE_PAGES> [SAMPLE_PAGES ...]
#
# For each sample size: set innodb_stats_persistent_sample_pages in the
# instance's config, restart it cold, re-ANALYZE every table, and run the
# full 99-query suite.  Results land in pagesize/results/<P>k-stats<N>/.
#
# innodb_stats_persistent_sample_pages counts PAGES, not rows, so the bytes
# actually sampled are SAMPLE_PAGES * PAGE_KB.  That is the number to match
# when comparing across page sizes.
set -Eeuo pipefail

P="${1:?usage: stats-sweep.sh <PAGE_KB> <SAMPLE_PAGES>...}"; shift
LAB=/Users/hosseinaghaei/Desktop/projects/dw/pagesize
CNF="$LAB/my-${P}k.cnf"
ME=$(id -un)

# table list comes from the server, so a schema change cannot break the sweep
TABLES=""

for S in "$@"; do
  echo "=============================================== ${P}K sample=${S} pages ($((S * P)) KB)"
  "$LAB/ctl.sh" stop "$P" >/dev/null 2>&1 || true

  # replace any existing setting, then append the new one
  grep -v 'innodb_stats_persistent_sample_pages' "$CNF" > "$CNF.tmp"
  mv "$CNF.tmp" "$CNF"
  printf 'innodb_stats_persistent_sample_pages = %s\n' "$S" >> "$CNF"

  "$LAB/ctl.sh" start "$P" >/dev/null
  got=$(mariadb --socket="$LAB/s$P.sock" --user="$ME" -N -B \
        -e "select @@innodb_stats_persistent_sample_pages")
  [[ "$got" == "$S" ]] || { echo "setting did not take: got $got" >&2; exit 1; }

  echo "re-analyzing with sample=$S"
  TABLES=$(mariadb --socket="$LAB/s$P.sock" --user="$ME" -N -B \
    -e "select group_concat(table_name) from information_schema.tables
        where table_schema='tpcds'")
  mariadb --socket="$LAB/s$P.sock" --user="$ME" tpcds \
    -e "analyze table $TABLES" > /dev/null

  # restart so the pool is cold again, matching every other run
  "$LAB/ctl.sh" stop "$P" >/dev/null
  "$LAB/ctl.sh" start "$P" >/dev/null

  python3 "$LAB/run-bench.py" "$P" "stats$S" | tail -2
  "$LAB/ctl.sh" stop "$P" >/dev/null
done

echo "=============================================== sweep done"
