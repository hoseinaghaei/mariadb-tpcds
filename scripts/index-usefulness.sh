#!/bin/bash
#
# index-usefulness.sh [sf] -- which indexes does the tier-4/5 suite actually
# read, and what do the idle ones cost in disk?
#
#   ./scripts/index-usefulness.sh 4      # default
#   ./scripts/index-usefulness.sh 1
#
# Method: zero the counters with FLUSH INDEX_STATISTICS, run queries/tuned/
# once, then read INFORMATION_SCHEMA.INDEX_STATISTICS.  That view only lists
# indexes with a non-zero read count, so "unused" is the full index list
# minus what it reports.  Sizes come from mysql.innodb_index_stats.
#
# Writes:
#   analysis/index-usage-sf<N>.tsv   table, index, MB, reads, used/unused
#   analysis/index-usage-sf<N>.md    the same with totals and drop candidates
#
# READ THE RESULT CAREFULLY.  "Unused" here means "not read by these 40
# queries, at this scale factor, under this configuration".  It is not a
# property of the index.  This project has measured the same index set at
# 16K and at 32K pages and got DIFFERENT answers about which members were
# idle (report/17, report/22), and six indexes added at once once made
# 16K/SF=1 40% slower -- the converse mistake.
#
# So: prefer `ALTER TABLE t ALTER INDEX i IGNORED` to DROP.  It is
# metadata-only, about 0.15s, instantly reversible, and leaves the index on
# disk so you can change your mind after measuring.  If you do drop, every
# index is in sql/all_indexes.sql and comes back with one command:
#
#     mariadb tpcds < sql/all_indexes.sql
set -Eeuo pipefail

REPO=/Users/hosseinaghaei/Desktop/projects/dw
LAB=$REPO/pagesize
SF="${1:-4}"
ME=$(id -un)
case "$SF" in
  1) CNF="$LAB/my-32k-sf4cfg.cnf";      SOCK="$LAB/s32.sock" ;;
  4) CNF="$LAB/my-32k-sf4-t1exact.cnf"; SOCK="$LAB/s32-sf4.sock" ;;
  *) echo "only SF=1 and SF=4 are built on this host (got $SF)" >&2; exit 1 ;;
esac
OUT=$REPO/analysis
mkdir -p "$OUT"

mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 || {
  mariadbd --defaults-file="$CNF" >>"$LAB/32k-sf4.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
}
CLI="mariadb --socket=$SOCK --user=$ME"

[[ "$($CLI -N -B -e 'select @@userstat')" == "1" ]] || {
  echo "ERROR: userstat is OFF, so INDEX_STATISTICS records nothing." >&2
  echo "       Set userstat=1 in $CNF and restart the instance." >&2
  exit 1; }

echo "=== SF=$SF: zeroing counters and running the 40 tuned queries"
$CLI -e "FLUSH INDEX_STATISTICS" >/dev/null
python3 "$LAB/bench-tuned.py" "$SOCK" "idxuse-sf$SF" --timeout 5400 | tail -1

echo "=== collecting"
$CLI -B -N tpcds > "$OUT/index-usage-sf$SF.tsv" <<'SQL'
-- Three states, not two.  An index that is IGNORED cannot be read however
-- useful it would be, so counting it as "never read" and proposing to drop
-- it is circular -- idx_ss_date_store_profit (512 MB) was listed as a drop
-- candidate on exactly that basis.  It is reported separately instead.
SELECT s.TABLE_NAME, s.INDEX_NAME,
       ROUND(IFNULL(z.stat_value,0) * @@innodb_page_size / 1048576, 1) AS mb,
       IFNULL(u.ROWS_READ, 0) AS rows_read,
       CASE WHEN s.IGNORED = 'YES'          THEN 'IGNORED'
            WHEN IFNULL(u.ROWS_READ,0) > 0  THEN 'used'
            ELSE 'UNUSED' END AS verdict
FROM (SELECT DISTINCT TABLE_SCHEMA, TABLE_NAME, INDEX_NAME, IGNORED
      FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='tpcds') s
LEFT JOIN information_schema.INDEX_STATISTICS u
       ON u.TABLE_SCHEMA = s.TABLE_SCHEMA
      AND u.TABLE_NAME   = s.TABLE_NAME
      AND u.INDEX_NAME   = s.INDEX_NAME
LEFT JOIN mysql.innodb_index_stats z
       ON z.database_name = s.TABLE_SCHEMA
      AND z.table_name    = s.TABLE_NAME
      AND z.index_name    = s.INDEX_NAME
      AND z.stat_name     = 'size'
ORDER BY verdict DESC, mb DESC, s.TABLE_NAME, s.INDEX_NAME;
SQL

python3 - "$OUT/index-usage-sf$SF.tsv" "$SF" > "$OUT/index-usage-sf$SF.md" <<'PY'
import sys, collections
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
sf = sys.argv[2]
used    = [r for r in rows if r[4] == 'used']
unused  = [r for r in rows if r[4] == 'UNUSED']
ignored = [r for r in rows if r[4] == 'IGNORED']
mb = lambda rs: sum(float(r[2]) for r in rs)
print(f"# Index usefulness at SF={sf}\n")
print("Counters zeroed, then the 40 tier-4/5 queries in `queries/tuned/` run "
      "once. `UNUSED` means **not read by those 40 queries at this scale "
      "under this configuration** — it is not a property of the index.\n")
print(f"| | indexes | disk |")
print(f"|---|---:|---:|")
print(f"| read at least once | {len(used)} | {mb(used):,.0f} MB |")
print(f"| enabled but never read | {len(unused)} | **{mb(unused):,.0f} MB** |")
if ignored:
    print(f"| currently IGNORED | {len(ignored)} | {mb(ignored):,.0f} MB |")
print(f"| total | {len(rows)} | {mb(rows):,.0f} MB |\n")
if ignored:
    print("The IGNORED ones are listed separately because they **cannot** be "
          "read — the optimizer is not allowed to use them — so a zero read "
          "count says nothing about whether they are worth keeping. Counting "
          "them as dead weight would be circular.\n")
    print("| table | index | MB |")
    print("|---|---|---:|")
    for r in sorted(ignored, key=lambda r: -float(r[2])):
        print(f"| {r[0]} | `{r[1]}` | {float(r[2]):,.1f} |")
    print()
if unused:
    print("## Never read, largest first\n")
    print("| table | index | MB |")
    print("|---|---|---:|")
    for r in sorted(unused, key=lambda r: -float(r[2]))[:30]:
        print(f"| {r[0]} | `{r[1]}` | {float(r[2]):,.1f} |")
    print()
    print("### Turning them off\n")
    print("Reversible, metadata-only, about 0.15s each — measure before dropping:\n")
    print("```sql")
    for r in sorted(unused, key=lambda r: -float(r[2]))[:30]:
        print(f"ALTER TABLE {r[0]} ALTER INDEX {r[1]} IGNORED;")
    print("```\n")
    print("Restore everything with `mariadb tpcds < sql/all_indexes.sql`.\n")
print("## Most read\n")
print("| table | index | rows read | MB |")
print("|---|---|---:|---:|")
for r in sorted(used, key=lambda r: -int(r[3]))[:15]:
    print(f"| {r[0]} | `{r[1]}` | {int(r[3]):,} | {float(r[2]):,.1f} |")
PY

echo "=== wrote $OUT/index-usage-sf$SF.tsv and .md"
grep -c "UNUSED" "$OUT/index-usage-sf$SF.tsv" | sed 's/^/  never read: /'
