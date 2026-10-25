#!/bin/bash
#
# End-to-end TPC-DS reproduction inside the container.
#
#   build dsdgen -> generate data -> init MariaDB at PAGE_SIZE -> load ->
#   index -> ANALYZE -> benchmark (baseline and/or tuned) -> write results
#
# The project is mounted READ-ONLY at /project.  Everything written goes to
# /data (scratch, discarded) and /results (bind-mounted to the host).
set -Eeuo pipefail

PROJECT=/project
DATA=/data
RESULTS=/results
DATADIR=$DATA/mysql
DSDATA=$DATA/tpcds-data
SOCK=$DATA/mysql.sock

say() { printf '\n\033[1m[%s] %s\033[0m\n' "$(date +%H:%M:%S)" "$*"; }
note() { printf '          %s\n' "$*"; }

# ---------------------------------------------------------------- profiles
# A profile only sets defaults; any explicit -e overrides it.
case "${PROFILE:-quick}" in
  quick)
    # 32K and sample 160 are the standing configuration (sql/tpcds-tuned.cnf);
    # stock settings were retired on 2026-10-25 after measuring 2.94x at SF=1.
    : "${SCALE:=1}" "${PAGE_SIZE:=32}" "${BUFFER_POOL:=2G}" "${SAMPLE_PAGES:=160}"
    : "${QUERYSET:=tier45}" "${TUNED:=tuned}" ;;
  full)
    # reproduces the shape of report 23: SF=4, 32K pages, 8G pool, sample 160
    : "${SCALE:=4}" "${PAGE_SIZE:=32}" "${BUFFER_POOL:=8G}" "${SAMPLE_PAGES:=160}"
    : "${QUERYSET:=tier45}" "${TUNED:=tuned}" ;;
  smoke)
    : "${SCALE:=1}" "${PAGE_SIZE:=32}" "${BUFFER_POOL:=1G}" "${SAMPLE_PAGES:=160}"
    : "${QUERYSET:=tier45}" "${TUNED:=tuned}" ;;
  *) echo "unknown PROFILE: $PROFILE (use quick, full or smoke)" >&2; exit 1 ;;
esac

case "$PAGE_SIZE" in 4|8|16|32|64) ;; *)
  echo "PAGE_SIZE must be 4, 8, 16, 32 or 64 (got $PAGE_SIZE)" >&2; exit 1 ;; esac

say "TPC-DS on MariaDB — reproduction run"
note "profile       $PROFILE"
note "scale factor  $SCALE"
note "page size     ${PAGE_SIZE}K"
note "buffer pool   $BUFFER_POOL"
note "sample pages  $SAMPLE_PAGES"
note "query set     $QUERYSET"
note "configs       $TUNED"
note "mariadb       $(mariadbd --version | head -1)"
note "cpus          $(nproc)   memory  $(free -g | awk '/^Mem:/{print $2}')G"

[[ -d "$PROJECT/sql" ]] || { echo "ERROR: /project does not look like the repo (no sql/)" >&2; exit 1; }
mkdir -p "$DSDATA" "$RESULTS"

# ---------------------------------------------------------------- 1. dsdgen
say "1/7  Building dsdgen"
BUILD=$DATA/tools
rm -rf "$BUILD"; mkdir -p "$BUILD"
cp -r "$PROJECT"/DSGen-software-code-4.0.0/tools/. "$BUILD"/
# The committed makefile targets macOS; Linux needs OS=LINUX, which selects
# gcc, lex, yacc and the LINUX block in config.h.
sed -i 's/^OS[[:space:]]*=.*/OS = LINUX/' "$BUILD/makefile"
( cd "$BUILD" && make -s dsdgen 2>&1 | tail -5 ) || {
  echo "ERROR: dsdgen build failed" >&2; exit 1; }
[[ -x "$BUILD/dsdgen" ]] || { echo "ERROR: dsdgen not produced" >&2; exit 1; }
note "built $("$BUILD/dsdgen" 2>&1 | head -1 || true)"

# ---------------------------------------------------------------- 2. data
say "2/7  Generating scale-factor-$SCALE data"
if [[ -f "$DSDATA/store_sales.dat" ]]; then
  note "data already present, skipping"
else
  # No -TERMINATE N: it drops the trailing '|' from each line, and
  # sql/04_load_data.sql reads these files with LINES TERMINATED BY '|\n'.
  ( cd "$BUILD" && ./dsdgen -SCALE "$SCALE" -DIR "$DSDATA" -FORCE ) \
    2>&1 | grep -vi 'warning' | tail -3 || true
  [[ -f "$DSDATA/store_sales.dat" ]] || { echo "ERROR: no data generated" >&2; exit 1; }
fi
note "$(du -sh "$DSDATA" | cut -f1) across $(ls "$DSDATA"/*.dat | wc -l) files"
chown -R mysql:mysql "$DSDATA"

# ---------------------------------------------------------------- 3. server
write_cnf() {   # $1 = extra settings block
  cat > "$DATA/my.cnf" <<EOF
[mysqld]
datadir                        = $DATADIR
socket                         = $SOCK
skip-networking
user                           = mysql
pid-file                       = $DATA/mysqld.pid
log-error                      = $DATA/mysqld.err

innodb_page_size               = ${PAGE_SIZE}K
innodb_buffer_pool_size        = $BUFFER_POOL
innodb_stats_persistent_sample_pages = $SAMPLE_PAGES

innodb_flush_log_at_trx_commit = 1
innodb_flush_method            = O_DIRECT
innodb_file_per_table          = ON
innodb_adaptive_hash_index     = OFF
character_set_server           = utf8mb4
collation_server               = utf8mb4_general_ci
local_infile                   = 1
max_statement_time             = 7200
secure_file_priv               =
$1
EOF
}

start_server() {
  mariadbd --defaults-file="$DATA/my.cnf" >>"$DATA/mysqld.err" 2>&1 &
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" -u root ping >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "ERROR: server did not start; last log lines:" >&2
  tail -20 "$DATA/mysqld.err" >&2
  return 1
}

stop_server() {
  mariadb-admin --socket="$SOCK" -u root ping >/dev/null 2>&1 || return 0
  mariadb-admin --socket="$SOCK" -u root shutdown
  for _ in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" -u root ping >/dev/null 2>&1 || return 0
    sleep 1
  done
  return 1
}

say "3/7  Initialising MariaDB with ${PAGE_SIZE}K pages"
if [[ -d "$DATADIR/mysql" ]]; then
  note "datadir already initialised, reusing"
  write_cnf ""
else
  write_cnf ""
  mariadb-install-db --defaults-file="$DATA/my.cnf" --user=mysql \
      --datadir="$DATADIR" --auth-root-authentication-method=normal \
      >"$DATA/install.log" 2>&1 || { tail -20 "$DATA/install.log" >&2; exit 1; }
fi
chown -R mysql:mysql "$DATA"
start_server
ACTUAL=$(mariadb --socket="$SOCK" -u root -N -B -e "select @@innodb_page_size/1024")
[[ "${ACTUAL%.*}" == "$PAGE_SIZE" ]] || {
  echo "ERROR: page size is ${ACTUAL%.*}K, expected ${PAGE_SIZE}K" >&2; exit 1; }
note "running, innodb_page_size = ${PAGE_SIZE}K"

CLI="mariadb --socket=$SOCK -u root"

# ---------------------------------------------------------------- 4. load
say "4/7  Creating schema and loading data"
if $CLI -N -B -e "select count(*) from information_schema.tables where table_schema='tpcds'" 2>/dev/null | grep -qx 25; then
  note "tpcds already has 25 tables, skipping"
else
  $CLI -e "drop database if exists tpcds; create database tpcds"
  $CLI tpcds < "$PROJECT/sql/01_schema.sql"
  t0=$SECONDS
  # the loader's paths are relative to the repo root; point them at /data
  sed "s#DSGen-software-code-4.0.0/data/#$DSDATA/#" "$PROJECT/sql/04_load_data.sql" \
    | $CLI --local-infile=1 tpcds
  note "loaded in $((SECONDS-t0))s"
fi

# A format mismatch makes LOAD DATA insert nothing without failing, which
# then looks like a benchmark where every query is instant and returns no
# rows.  Fail here instead.
ROWS=$($CLI -N -B -e "select count(*) from tpcds.store_sales")
if (( ROWS < 1000 )); then
  echo "ERROR: store_sales has $ROWS rows after loading -- the data did not load." >&2
  echo "       Check that the .dat lines end with '|' (dsdgen without -TERMINATE N)." >&2
  $CLI -N -B -e "show warnings" 2>/dev/null | head -5 >&2
  exit 1
fi
note "store_sales: $(printf "%'d" "$ROWS") rows"
note "$($CLI -N -B -e "select concat(format(sum(table_rows),0),' rows, ',round(sum(data_length+index_length)/1073741824,1),' GB') from information_schema.tables where table_schema='tpcds'")"

# ---------------------------------------------------------------- 5. indexes
say "5/7  Creating indexes"
NIDX=$($CLI -N -B -e "select count(distinct table_name,index_name) from information_schema.statistics where table_schema='tpcds'")
if (( NIDX >= 180 )); then
  note "already has $NIDX indexes, skipping"
else
  t0=$SECONDS
  for f in 05_indexes 11_optimizer_indexes 14_contributed_indexes; do
    [[ -f "$PROJECT/sql/$f.sql" ]] || continue
    sed 's/^CREATE INDEX /CREATE INDEX IF NOT EXISTS /i' "$PROJECT/sql/$f.sql" | $CLI tpcds
  done
  note "built in $((SECONDS-t0))s"
fi
note "$($CLI -N -B -e "select concat(count(distinct table_name,index_name),' indexes') from information_schema.statistics where table_schema='tpcds'")"

say "6/7  Refreshing optimizer statistics"
TBLS=$($CLI -N -B -e "select group_concat(table_name) from information_schema.tables where table_schema='tpcds'")
$CLI tpcds -e "analyze table $TBLS" >/dev/null
note "done"

# ---------------------------------------------------------------- 7. benchmark
say "7/7  Benchmarking"
run_one() {   # $1 = tag, $2 = extra cnf block
  stop_server
  write_cnf "$2"
  chown mysql:mysql "$DATA/my.cnf"
  start_server
  python3 /usr/local/bin/bench.py "$SOCK" "$RESULTS/$1" "$1" "$QUERYSET" \
    | tee "$RESULTS/$1.log"
}

TUNING_BLOCK='
# The tuning that measured 2.90x at SF=4 (report 23).  Item 1 -- temp tables
# off a 16M default -- is about two thirds of it on its own.
tmp_table_size                 = 1536M
max_heap_table_size            = 1536M
aria_pagecache_buffer_size     = 1G
innodb_read_io_threads         = 8
innodb_read_ahead_threshold    = 24
innodb_old_blocks_pct          = 25
sort_buffer_size               = 64M
join_cache_level               = 8
join_buffer_size               = 64M
join_buffer_space_limit        = 256M
optimizer_switch               = "mrr=on,mrr_cost_based=off"
key_buffer_size                = 16M
'

check_measured() {   # $1 = tag
  local tot
  tot=$(python3 -c "import json;print(json.load(open('$RESULTS/$1/_summary.json'))['total_seconds'])")
  # An `awk ... && { ... }` here would return awk's non-zero status on the
  # PASSING path and trip `set -e`.  Use an explicit if.
  if python3 -c "import sys;sys.exit(0 if float('$tot') < 5 else 1)"; then
    echo "ERROR: $1 finished in ${tot}s -- too fast to be real work." >&2
    echo "       The database is probably empty; check stage 4." >&2
    exit 1
  fi
  note "$1 measured ${tot}s"
}

case "$TUNED" in
  baseline) run_one baseline ""; check_measured baseline ;;   # stock: retired, kept for comparison
  tuned)    run_one tuned "$TUNING_BLOCK"; check_measured tuned ;;
  both)     run_one baseline ""; check_measured baseline
            run_one tuned "$TUNING_BLOCK"; check_measured tuned ;;
  *) echo "TUNED must be baseline, tuned or both (got $TUNED)" >&2; exit 1 ;;
esac

stop_server

# ---------------------------------------------------------------- report
say "Results"
python3 - "$RESULTS" "$PROFILE" <<'PY'
import json, sys, os, glob
res, profile = sys.argv[1], sys.argv[2]
runs = {}
for s in sorted(glob.glob(f"{res}/*/_summary.json")):
    d = json.load(open(s)); runs[d['tag']] = d

if not runs:
    sys.exit("no results produced")

print(f"{'config':<12} {'queries':>8} {'errors':>7} {'total':>11}")
print("-" * 42)
for tag, d in runs.items():
    print(f"{tag:<12} {d['queries']:>8} {d['errors']:>7} {d['total_seconds']:>10.1f}s")

if 'baseline' in runs and 'tuned' in runs:
    b, t = runs['baseline']['total_seconds'], runs['tuned']['total_seconds']
    print(f"\ntuned is {b/t:.2f}x faster than baseline  ({b:.1f}s -> {t:.1f}s)")

# answers must not change between configurations
def load(tag):
    return {json.load(open(f))['query']: json.load(open(f))
            for f in glob.glob(f"{res}/{tag}/query*.json")}
if 'baseline' in runs and 'tuned' in runs:
    a, c = load('baseline'), load('tuned')
    exact = [q for q in a if q in c and a[q].get('md5') == c[q].get('md5')]
    same  = [q for q in a if q in c and a[q].get('md5_sorted') == c[q].get('md5_sorted')]
    diff  = sorted(set(a) & set(c) - set(same))
    print(f"\nanswers: {len(exact)}/{len(a)} byte-identical, "
          f"{len(same)}/{len(a)} identical ignoring row order")
    if diff:
        print(f"  genuinely different: {diff}")
    elif len(exact) < len(same):
        order_only = sorted(set(same) - set(exact))
        print(f"  row-order only (ORDER BY is not a total order): {order_only}")

print(f"\nreference figures from our runs, for comparison:")
print("  report 23, SF=4 / 32K / 8G pool / sample 160 / tier4+5:")
print("     baseline 2403.4s   tuned 829.8s   2.90x")
print("  Hardware differs, so absolute times will not match; the ratio is")
print("  the comparable part.  See report/23-server-tuning-sf4.md.")
print(f"\nPer-query JSON and logs are in ./results/")
PY

say "Done"
