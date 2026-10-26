#!/bin/bash
#
# compare-classmates.sh -- the five queries two people optimized independently.
#
# q37, q65, q70, q82 and q87 were rewritten here and then again by a
# classmate (commits c56bfbc, f871372).  Each pair is measured against the
# other IN THIS ENVIRONMENT, with the current queries/tuned/ file as the
# baseline and their BEST as the challenger.
#
# WHY RE-MEASURE RATHER THAN READ THEIR NUMBERS.  Their q65 README records
# the measurement environment honestly, and it is a different world:
#
#     Ryzen 5 3500U, ~6.7 GiB RAM, MariaDB 10.11.14,
#     2 GiB buffer pool, 16 MiB temp tables, PRIMARY KEYS ONLY
#
# against this project's 32K pages, 8 GB pool, 188 indexes and MariaDB
# 13.0.2.  Their q65 "original" takes 91.7s where ours takes 3.3s at SF=4 --
# almost all of that gap is the secondary indexes they do not have.  A
# speedup earned by hand-building an access path the optimizer already has
# here may be worth nothing, or may still win.  Only measuring says which.
#
# Their files are used as-is.  None carries a temporary table, index DDL or
# session settings; three use STRAIGHT_JOIN.
set -Eeuo pipefail

HERE=/Users/hosseinaghaei/Desktop/projects/dw/queries/optimized
CMP="$HERE/compare-rewrite.sh"
TUNED=/Users/hosseinaghaei/Desktop/projects/dw/queries/tuned
PASSES=${1:-3}

for n in 37 65 70 82 87; do
  theirs="$HERE/q$n/query${n}_BEST.sql"
  ours="$TUNED/query$n.sql"
  [[ -f "$theirs" ]] || { echo "missing $theirs"; continue; }
  echo
  echo "================================================================"
  echo "=== q$n   baseline = ours (queries/tuned/)   new = theirs"
  bash "$CMP" "$n" "$theirs" "$PASSES" "$ours" || echo "  !! q$n comparison failed"
done

echo
echo "=== done.  A 'SLOWDOWN' line means ours is faster and should stay."
