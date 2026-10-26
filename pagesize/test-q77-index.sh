#!/bin/bash
#
# test-q77-index.sh -- does the q77 covering index pay for itself?
#
# q77 is the one query left with a diagnosed cause and no query-level fix:
# its plan reaches store_sales through idx_ss_date_cust, which carries
# neither ss_store_sk nor the two measures, so every qualifying row costs a
# base-table fetch.  sql/15_q77_covering_index.sql adds an index that holds
# exactly what the CTE reads.
#
# The question is not whether q77 gets faster -- it should -- but whether the
# whole suite does.  Six indexes added to this schema at once once made
# 16K/SF=1 40% SLOWER, because index pages displaced data pages from the
# buffer pool.  One index is a smaller bet, but it is the same bet.
#
# METHOD.  The index is created once, then toggled with ALTER INDEX
# IGNORED / NOT IGNORED, which is metadata-only and takes ~0.15s.  That beats
# creating and dropping it: identical storage and identical cache state on
# both sides, so the only thing that changes is whether the optimizer may use
# it.  Never DROP it -- "unused" depends on the configuration.
#
# Order is IGNORED, NOT IGNORED, IGNORED, NOT IGNORED so that drift over the
# run cancels instead of being charged to whichever side ran second.
#
# RUN THIS YOURSELF.  The session that wrote it is restricted to read-only
# statements and cannot issue CREATE INDEX or ALTER TABLE.
#
#   ./pagesize/test-q77-index.sh
#
# BUDGET: index build a few minutes, then four full tier-4/5 passes at SF=4
# of roughly 8 minutes each -- about 35-40 minutes in total.  It reserves an
# 8 GB buffer pool, so do not run anything else heavy alongside it; the last
# measurements in this project were distorted by an unrelated process holding
# the machine at load 11.
#
set -Eeuo pipefail

# The local macOS databases were removed on 2026-10-26; see
# pagesize/require-local-db.sh.  Fail immediately and say so, rather than
# spending 300s in a start-up retry loop that ends in "did not start".
source /Users/hosseinaghaei/Desktop/projects/dw/pagesize/require-local-db.sh
require_local_db /Users/hosseinaghaei/Desktop/projects/dw/pagesize/data-32k-sf4 || exit 1

REPO=/Users/hosseinaghaei/Desktop/projects/dw
LAB=$REPO/pagesize
CNF="$LAB/my-32k-sf4-t1exact.cnf"
SOCK="$LAB/s32-sf4.sock"
ME=$(id -un)
IDX=idx_ss_date_store_profit

start() {
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && return
  mariadbd --defaults-file="$CNF" >>"$LAB/32k-sf4.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && return
    sleep 1
  done
  echo "server did not start" >&2; exit 1
}
sql() { mariadb --socket="$SOCK" --user="$ME" -B -N tpcds -e "$1"; }

start

# ---------------------------------------------------------------- create
if [ -z "$(sql "select 1 from information_schema.statistics
                where table_schema='tpcds' and table_name='store_sales'
                  and index_name='$IDX' limit 1")" ]; then
  echo "=== creating $IDX (several minutes, ~400-500 MB)"
  time mariadb --socket="$SOCK" --user="$ME" tpcds < "$REPO/sql/15_q77_covering_index.sql"
else
  echo "=== $IDX already exists"
fi

size=$(sql "select round(stat_value*@@innodb_page_size/1048576)
            from mysql.innodb_index_stats
            where database_name='tpcds' and table_name='store_sales'
              and index_name='$IDX' and stat_name='size'")
echo "=== $IDX occupies ${size:-?} MB"

# ---------------------------------------------------------------- measure
toggle() {   # $1 = IGNORED | 'NOT IGNORED'
  mariadb --socket="$SOCK" --user="$ME" tpcds \
    -e "ALTER TABLE store_sales ALTER INDEX $IDX $1"
}

run() {      # $1 = tag
  python3 "$LAB/bench-tuned.py" "$SOCK" "$1" --timeout 5400 | tail -2
}

for pass in 1 2; do
  echo
  echo "=== pass $pass: index IGNORED (the 'before')"
  toggle IGNORED
  run "q77idx-off-$pass"
  echo "=== pass $pass: index NOT IGNORED (the 'after')"
  toggle "NOT IGNORED"
  run "q77idx-on-$pass"
done

# Leave it IGNORED: that is the state matching every result committed so far.
# Flip it on deliberately once the numbers say it is worth it.
toggle IGNORED
echo
echo "=== left IGNORED; compare with:"
echo "    python3 $LAB/consolidate.py  (or read pagesize/results/q77idx-*/_summary.json)"
