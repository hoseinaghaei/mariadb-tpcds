#!/bin/bash
#
# build-sf4.sh <PAGE_KB>
#
# Same as build-instance.sh but for the SF=4 dataset: separate data directory,
# separate datadir, separate port, so nothing at SF=1 is touched.
#
# At SF=4 the database is roughly 38 GB against an 8 GB buffer pool, so unlike
# SF=1 the data genuinely does not fit in memory and page size governs real
# I/O rather than just the optimizer's statistics.
#
#   port   = 3500 + PAGE_KB      (SF=1 lab uses 3400 + PAGE_KB)
#   datadir= pagesize/data-<P>k-sf4
#   socket = pagesize/s<P>-sf4.sock

set -Eeuo pipefail

PAGE_KB="${1:?usage: build-sf4.sh <4|8|16|32|64>}"
case "$PAGE_KB" in 4|8|16|32|64) ;; *) echo "bad page size: $PAGE_KB" >&2; exit 1 ;; esac

REPO=/Users/hosseinaghaei/Desktop/projects/dw
LAB=$REPO/pagesize
DATA=$REPO/DSGen-software-code-4.0.0/data-sf4
DD=$LAB/data-${PAGE_KB}k-sf4
CNF=$LAB/my-${PAGE_KB}k-sf4.cnf
SOCK=$LAB/s${PAGE_KB}-sf4.sock
PORT=$((3500 + PAGE_KB))
BASEDIR=$(/opt/homebrew/bin/mariadb -N -B -e "select @@basedir" | sed 's:/$::')
ME=$(id -un)

say() { printf '[%s] %sK/sf4: %s\n' "$(date +%H:%M:%S)" "$PAGE_KB" "$*"; }

[[ -d "$DATA" ]] || { echo "no SF=4 data at $DATA -- run dsdgen first" >&2; exit 1; }
mkdir -p "$LAB"

cat > "$CNF" <<EOF
# SF=4 instance.  innodb_page_size is fixed at datadir initialization.
[mysqld]
datadir                        = $DD
socket                         = $SOCK
port                           = $PORT
pid-file                       = $LAB/${PAGE_KB}k-sf4.pid
log-error                      = $LAB/${PAGE_KB}k-sf4.err

innodb_page_size               = ${PAGE_KB}K

innodb_buffer_pool_size        = 8G
innodb_log_file_size           = 96M
innodb_flush_log_at_trx_commit = 1
innodb_flush_method            = O_DIRECT
innodb_io_capacity             = 200
innodb_read_io_threads         = 4
innodb_write_io_threads        = 4
innodb_doublewrite             = ON
innodb_file_per_table          = ON
innodb_adaptive_hash_index     = OFF
innodb_old_blocks_pct          = 37

character_set_server           = utf8mb4
collation_server               = utf8mb4_general_ci
local_infile                   = 1

# At SF=1 this was 300s.  At SF=4 several queries legitimately exceed that,
# and a query killed by the cap records a censored time that would corrupt
# the comparison.  Raised so it never binds; the runner keeps its own
# client-side timeout.
max_statement_time             = 3600

tmp_table_size                 = 16M
max_heap_table_size            = 16M
join_buffer_size               = 256K
sort_buffer_size               = 2M

skip_name_resolve
EOF

if [[ -d "$DD" ]]; then
  say "datadir exists, skipping init"
else
  say "initializing datadir with ${PAGE_KB}K pages"
  mariadb-install-db --defaults-file="$CNF" --user="$ME" \
      --basedir="$BASEDIR" --datadir="$DD" --auth-root-socket-user="$ME" \
      > "$LAB/install-${PAGE_KB}k-sf4.log" 2>&1 \
    || { echo "init failed, see $LAB/install-${PAGE_KB}k-sf4.log" >&2; exit 1; }
fi

if ! mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1; then
  say "starting on port $PORT"
  mariadbd --defaults-file="$CNF" >> "$LAB/${PAGE_KB}k-sf4.err" 2>&1 &
  for i in $(seq 1 300); do
    mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 && break
    sleep 1
  done
  mariadb-admin --socket="$SOCK" --user="$ME" ping >/dev/null 2>&1 \
    || { echo "did not start, see $LAB/${PAGE_KB}k-sf4.err" >&2; exit 1; }
fi

CLI="mariadb --socket=$SOCK --user=$ME"
ACTUAL=$($CLI -N -B -e "select @@innodb_page_size/1024")
[[ "${ACTUAL%.*}" == "$PAGE_KB" ]] || { echo "page size mismatch" >&2; exit 1; }
say "running, page size ${PAGE_KB}K, max_statement_time=$($CLI -N -B -e 'select @@max_statement_time')"

cd "$REPO"
if $CLI -N -B -e "select count(*) from information_schema.tables where table_schema='tpcds'" 2>/dev/null | grep -qx 25; then
  say "tpcds already populated, skipping schema+load"
else
  say "creating schema"
  $CLI -e "drop database if exists tpcds; create database tpcds"
  $CLI tpcds < sql/01_schema.sql
  say "loading SF=4 data"
  t0=$SECONDS
  # same loader, pointed at the SF=4 directory
  sed 's#DSGen-software-code-4.0.0/data/#DSGen-software-code-4.0.0/data-sf4/#' \
      sql/04_load_data.sql | $CLI --local-infile=1 tpcds
  say "load took $((SECONDS - t0))s"
fi

NIDX=$($CLI -N -B -e "select count(distinct table_name,index_name) from information_schema.statistics where table_schema='tpcds'")
if (( NIDX >= 180 )); then
  say "already has $NIDX indexes"
else
  say "creating indexes (have $NIDX)"
  t0=$SECONDS
  for f in sql/05_indexes.sql sql/11_optimizer_indexes.sql sql/14_contributed_indexes.sql; do
    sed 's/^CREATE INDEX /CREATE INDEX IF NOT EXISTS /i' "$f" | $CLI tpcds
  done
  say "indexes took $((SECONDS - t0))s"
fi

say "analyzing"
$CLI tpcds -e "$($CLI -N -B -e "select group_concat(concat('analyze table ',table_name) separator '; ') from information_schema.tables where table_schema='tpcds'")" > /dev/null

$CLI -N -B -e "
select concat('indexes=', (select count(distinct table_name,index_name)
                           from information_schema.statistics where table_schema='tpcds'),
              ' data_mb=', round(sum(data_length)/1048576),
              ' index_mb=', round(sum(index_length)/1048576),
              ' total_mb=', round(sum(data_length+index_length)/1048576))
from information_schema.tables where table_schema='tpcds'" \
  | sed "s|^|[$(date +%H:%M:%S)] ${PAGE_KB}K/sf4: |"

say "ready on $SOCK (port $PORT)"
