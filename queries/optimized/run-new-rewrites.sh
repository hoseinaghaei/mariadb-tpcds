#!/bin/bash
#
# run-new-rewrites.sh -- validate and time every rewrite written for the
# tier-4/5 queries nobody had optimized, at SF=4.
#
# Sequential on purpose: two queries running at once share a buffer pool and
# would charge each other's I/O to the wrong measurement.
#
# Each query is compared against the adapted TPC-DS original by
# compare-rewrite.sh, which interleaves the passes and diffs the output.
set -Eeuo pipefail

HERE=/Users/hosseinaghaei/Desktop/projects/dw/queries/optimized
CMP="$HERE/compare-rewrite.sh"

# query number : rewrite file, cheapest first so a mistake surfaces quickly
SET="
58:q58-sf4/query58_v1_keydate.sql
82:q82-sf4/query82_v1_exists.sql
65:q65-sf4/query65_v1_sharedcte.sql
87:q87-sf4/query87_v1_keydate.sql
35:q35-sf4/query35_v1_keydate.sql
71:q71-sf4/query71_v1_keydate.sql
66:q66-sf4/query66_v1_keyagg.sql
70:q70-sf4/query70_v1_nosubquery.sql
38:q38-sf4/query38_v1_keydate.sql
77:q77-sf4/query77_v1_keydate.sql
"

for line in $SET; do
  n=${line%%:*}
  f=${line#*:}
  echo
  echo "================================================================"
  bash "$CMP" "$n" "$HERE/$f" 3 || echo "  !! q$n comparison failed"
done
echo
echo "=== all rewrites compared"
