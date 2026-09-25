#!/bin/bash
#
# change-innodb-page-size-macos.sh
#
# macOS + Homebrew version. Rebuilds a MariaDB instance with a new innodb_page_size:
#   pre-checks -> full dump -> write config -> stop -> move datadir aside
#   -> reinitialize -> start -> restore -> verify
#
# If anything fails after the server is stopped, the script rolls back
# automatically: the original data directory and config are put back and
# the service is started again. The dump and the old data directory are
# never deleted by this script.
#
# Compatible with the bash 3.2 that ships with macOS (no Homebrew bash needed).
# Run it as your normal user, NOT with sudo (Homebrew services run as your user).

set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")
TS=$(date +%Y%m%d-%H%M%S)

# ---------------------------------------------------------------- defaults
PAGE_KB=""
BACKUP_DIR=""
CONFIG_FILE=""
EXTRA_DEFAULTS=""
SERVICE=""
EXACT_COUNTS=0
ASSUME_YES=0
DRY_RUN=0

# ---------------------------------------------------------------- state
STAGE="precheck"      # precheck -> backup -> config -> stopped -> moved -> initialized -> started -> restored -> verified -> done
MOVED=0
CONFIG_WRITTEN=0
CONFIG_BACKUP=""
FAILING=0
DATADIR=""
OLD_DATADIR=""
DUMP_FILE=""
CURRENT_PAGE_KB=""
SOCKET=""
DB_USER="$(id -un)"

EXCLUDED_SCHEMAS="'information_schema','performance_schema','sys','mysql'"

# ---------------------------------------------------------------- helpers
log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <PAGE_SIZE> [options]

  PAGE_SIZE   New InnoDB page size: 4, 8, 16, 32 or 64 (a trailing K is optional, e.g. 8K)

Run as your normal macOS user (not sudo). Requires MariaDB installed with
Homebrew and running via "brew services".

Options:
  --backup-dir DIR            Where to put the dump, snapshots and log
                              (default: ~/mariadb-pagesize-<timestamp>)
  --config-file FILE          Dedicated drop-in file to write innodb_page_size into
                              (default: \$(brew --prefix)/etc/my.cnf.d/99-innodb-page-size.cnf).
                              This file is overwritten; the original is backed up.
  --defaults-extra-file FILE  Client credentials for the CURRENT server.
                              Not needed if your macOS user can log in via unix_socket
                              (the Homebrew default).
  --service NAME              Homebrew service name, e.g. mariadb or mariadb@11.4
                              (default: auto-detect the running one)
  --exact-counts              Also compare exact row counts of every table (slow on large data)
  --yes                       Don't ask for confirmation
  --dry-run                   Run all pre-checks and show the plan without changing anything
  -h, --help                  Show this help

Examples:
  ./$SCRIPT_NAME 8K --dry-run
  ./$SCRIPT_NAME 8K --exact-counts
EOF
}

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

human() {
  awk -v b="$1" 'BEGIN { split("B KB MB GB TB", u, " "); i = 1
                         while (b >= 1024 && i < 5) { b /= 1024; i++ }
                         printf "%.1f %s", b, u[i] }'
}

avail_bytes()     { df -Pk "$1" | awk 'NR==2 { printf "%.0f", $4 * 1024 }'; }
existing_parent() { local p="$1"; while [[ ! -d "$p" ]]; do p=$(dirname "$p"); done; echo "$p"; }

normalize_page_size() {
  local raw
  raw=$(upper "$1")
  raw="${raw%KB}"; raw="${raw%K}"
  case "$raw" in
    4|8|16|32|64) echo "$raw" ;;
    4096)  echo 4 ;;
    8192)  echo 8 ;;
    16384) echo 16 ;;
    32768) echo 32 ;;
    65536) echo 64 ;;
    *) return 1 ;;
  esac
}

server_running() {
  pgrep -x mariadbd >/dev/null 2>&1 || pgrep -x mysqld >/dev/null 2>&1
}

wait_for_stop() {
  local i
  for ((i = 0; i < 120; i++)); do
    server_running || return 0
    sleep 1
  done
  return 1
}

# Client wrappers.
#   *_old : log in the way you normally do (your ~/.my.cnf, or --defaults-extra-file).
#           Used on the original server, and again after the restore (users are restored).
#   *_new : your macOS user via unix_socket on the freshly initialized server.
cli_old() {
  if [[ -n "$EXTRA_DEFAULTS" ]]; then "$CLIENT" --defaults-extra-file="$EXTRA_DEFAULTS" "$@"
  else "$CLIENT" "$@"; fi
}
dump_old() {
  if [[ -n "$EXTRA_DEFAULTS" ]]; then "$DUMP_BIN" --defaults-extra-file="$EXTRA_DEFAULTS" "$@"
  else "$DUMP_BIN" "$@"; fi
}
cli_new()   { "$CLIENT"    --no-defaults --user="$DB_USER" --socket="$SOCKET" "$@"; }
admin_new() { "$ADMIN_BIN" --no-defaults --user="$DB_USER" --socket="$SOCKET" "$@"; }

q_old() { cli_old -N -B -e "$1"; }
q_new() { cli_new -N -B -e "$1"; }

wait_for_server() {
  local i
  for ((i = 0; i < 180; i++)); do
    if admin_new ping >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

snapshot() {   # $1 = cli_old | cli_new
  "$1" -N -B -e "
    SELECT 'schema' AS k, schema_name AS s, 1 AS n FROM information_schema.SCHEMATA
      WHERE schema_name NOT IN ($EXCLUDED_SCHEMAS)
    UNION ALL
    SELECT 'tables', table_schema, COUNT(*) FROM information_schema.TABLES
      WHERE table_type = 'BASE TABLE' AND table_schema NOT IN ($EXCLUDED_SCHEMAS) GROUP BY table_schema
    UNION ALL
    SELECT 'views', table_schema, COUNT(*) FROM information_schema.VIEWS
      WHERE table_schema NOT IN ($EXCLUDED_SCHEMAS) GROUP BY table_schema
    UNION ALL
    SELECT 'routines', routine_schema, COUNT(*) FROM information_schema.ROUTINES
      WHERE routine_schema NOT IN ($EXCLUDED_SCHEMAS) GROUP BY routine_schema
    UNION ALL
    SELECT 'triggers', trigger_schema, COUNT(*) FROM information_schema.TRIGGERS
      WHERE trigger_schema NOT IN ($EXCLUDED_SCHEMAS) GROUP BY trigger_schema
    UNION ALL
    SELECT 'events', event_schema, COUNT(*) FROM information_schema.EVENTS
      WHERE event_schema NOT IN ($EXCLUDED_SCHEMAS) GROUP BY event_schema
    UNION ALL
    SELECT 'users', 'mysql', COUNT(*) FROM mysql.user
    ORDER BY k, s"
}

exact_counts() {   # $1 = cli_old | cli_new
  local gen
  gen="SELECT CONCAT('SELECT ', QUOTE(CONCAT(table_schema, '.', table_name)), ', COUNT(*) FROM \`',
                     REPLACE(table_schema, '\`', '\`\`'), '\`.\`', REPLACE(table_name, '\`', '\`\`'), '\`;')
       FROM information_schema.TABLES
       WHERE table_type = 'BASE TABLE' AND table_schema NOT IN ($EXCLUDED_SCHEMAS)
       ORDER BY table_schema, table_name"
  "$1" -N -B -r -e "$gen" | "$1" -N -B
}

restore_config() {
  [[ "$CONFIG_WRITTEN" == 1 ]] || return 0
  if [[ -n "$CONFIG_BACKUP" && -f "$CONFIG_BACKUP" ]]; then
    cp -p "$CONFIG_BACKUP" "$CONFIG_FILE"
  else
    rm -f "$CONFIG_FILE"
  fi
  CONFIG_WRITTEN=0
  log "Reverted config file $CONFIG_FILE"
}

rollback() {
  set +e
  warn "Rolling back to the original data directory..."
  brew services stop "$SERVICE" >/dev/null 2>&1
  wait_for_stop || err "MariaDB is still running; stop it manually (brew services stop $SERVICE) and check the paths below."

  if [[ "$MOVED" == 1 ]]; then
    if [[ -e "$DATADIR" ]]; then
      if mv "$DATADIR" "${DATADIR}.failed-${TS}"; then
        warn "Kept the failed new data directory at ${DATADIR}.failed-${TS} for inspection."
      else
        err "Could not move the new data directory out of the way."
      fi
    fi
    if mv "$OLD_DATADIR" "$DATADIR"; then
      log "Original data directory restored to $DATADIR"
    else
      err "Could not move $OLD_DATADIR back to $DATADIR. Do this manually before starting MariaDB!"
    fi
  fi

  restore_config

  if brew services start "$SERVICE" >/dev/null 2>&1; then
    log "Started $SERVICE again on the original data (page size ${CURRENT_PAGE_KB}K)."
  else
    err "Could not start $SERVICE after rollback. Check the error log in $DATADIR (*.err)."
  fi
  if [[ -n "$DUMP_FILE" && -f "$DUMP_FILE" ]]; then log "The dump is still available at: $DUMP_FILE"; fi
}

handle_failure() {
  if [[ "$FAILING" == 1 ]]; then return 0; fi
  FAILING=1
  trap - ERR INT TERM
  case "$STAGE" in
    precheck) ;;
    backup)   warn "Failed during backup. The running server was not changed." ;;
    config)   restore_config; warn "The running server was not changed." ;;
    *)        rollback ;;
  esac
}

die() { err "$*"; handle_failure; exit 1; }

on_error() {
  local rc=$? line=$1
  err "Command failed (exit $rc) at line $line during stage '$STAGE'."
  handle_failure
  exit "$rc"
}
trap 'on_error $LINENO' ERR
trap 'err "Interrupted."; handle_failure; exit 130' INT TERM

write_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  if [[ -e "$CONFIG_FILE" ]]; then
    CONFIG_BACKUP="$BACKUP_DIR/$(basename "$CONFIG_FILE").orig"
    cp -p "$CONFIG_FILE" "$CONFIG_BACKUP"
  fi
  cat > "$CONFIG_FILE" <<EOF
# Written by $SCRIPT_NAME on $(date '+%Y-%m-%dT%H:%M:%S%z')
# innodb_page_size is fixed when the data directory is initialized.
# Do NOT change or remove this without rebuilding the data directory.
[mysqld]
innodb_page_size = ${PAGE_KB}K
EOF
  chmod 644 "$CONFIG_FILE"
  CONFIG_WRITTEN=1
  log "Wrote innodb_page_size = ${PAGE_KB}K to $CONFIG_FILE"

  if [[ -n "$PRINT_DEFAULTS" ]]; then
    local out effective
    out=$("$PRINT_DEFAULTS" --mysqld 2>/dev/null) \
      || out=$("$PRINT_DEFAULTS" mysqld server mariadb mariadbd 2>/dev/null) \
      || out=""
    effective=$(grep -E '^--innodb[-_]page[-_]size=' <<<"$out" | tail -n 1 | cut -d= -f2 || true)
    if [[ -z "$effective" ]]; then
      die "The server does not read $CONFIG_FILE. Make sure your my.cnf has '!includedir $(dirname "$CONFIG_FILE")', or use --config-file."
    elif [[ "$(upper "$effective")" != "${PAGE_KB}K" ]]; then
      die "Effective innodb_page_size is '$effective', not ${PAGE_KB}K. Another config file overrides $CONFIG_FILE."
    else
      log "Confirmed: the server will read innodb_page_size=${PAGE_KB}K"
    fi
  fi
}

# ---------------------------------------------------------------- arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-dir)            BACKUP_DIR="${2:?--backup-dir needs a value}"; shift 2 ;;
    --backup-dir=*)          BACKUP_DIR="${1#*=}"; shift ;;
    --config-file)           CONFIG_FILE="${2:?--config-file needs a value}"; shift 2 ;;
    --config-file=*)         CONFIG_FILE="${1#*=}"; shift ;;
    --defaults-extra-file)   EXTRA_DEFAULTS="${2:?--defaults-extra-file needs a value}"; shift 2 ;;
    --defaults-extra-file=*) EXTRA_DEFAULTS="${1#*=}"; shift ;;
    --service)               SERVICE="${2:?--service needs a value}"; shift 2 ;;
    --service=*)             SERVICE="${1#*=}"; shift ;;
    --exact-counts)          EXACT_COUNTS=1; shift ;;
    --yes|-y)                ASSUME_YES=1; shift ;;
    --dry-run)               DRY_RUN=1; shift ;;
    -h|--help)               usage; exit 0 ;;
    -*)                      usage >&2; die "Unknown option: $1" ;;
    *)
      [[ -z "$PAGE_KB" ]] || die "Page size given more than once."
      PAGE_KB="$1"; shift ;;
  esac
done

[[ -n "$PAGE_KB" ]] || { usage >&2; die "Missing PAGE_SIZE."; }
PAGE_KB=$(normalize_page_size "$PAGE_KB") || die "Invalid page size. Use 4, 8, 16, 32 or 64 (K)."

# ---------------------------------------------------------------- pre-checks
log "Running pre-checks..."

[[ "$(uname -s)" == "Darwin" ]] || die "This version is for macOS. Use the Linux script on Linux."
[[ $EUID -ne 0 ]] || die "Don't run this with sudo. Run it as the macOS user that owns the Homebrew MariaDB service."

BREW=$(command -v brew || true)
if [[ -z "$BREW" ]]; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$b" ]]; then BREW="$b"; break; fi
  done
fi
[[ -n "$BREW" ]] || die "Homebrew not found. This script expects MariaDB installed via Homebrew."
brew() { "$BREW" "$@"; }
BREW_PREFIX=$(brew --prefix)

# Find the running MariaDB service (mariadb or a versioned mariadb@X.Y).
SERVICES_LIST=$(brew services list 2>/dev/null || true)
if [[ -z "$SERVICE" ]]; then
  SERVICE=$(awk 'NR > 1 && $1 ~ /^mariadb(@|$)/ && $2 == "started" { print $1; exit }' <<<"$SERVICES_LIST")
  [[ -n "$SERVICE" ]] || die "No running Homebrew MariaDB service found. Start it with: brew services start mariadb"
fi
SERVICE_LINE=$(awk -v s="$SERVICE" 'NR > 1 && $1 == s' <<<"$SERVICES_LIST")
[[ -n "$SERVICE_LINE" ]] || die "Homebrew service '$SERVICE' not found (see: brew services list)."
[[ "$(awk '{ print $2 }' <<<"$SERVICE_LINE")" == "started" ]] || die "Service '$SERVICE' is not running. Start it with: brew services start $SERVICE"
SERVICE_USER=$(awk '{ print $3 }' <<<"$SERVICE_LINE")
if [[ -n "$SERVICE_USER" && "$SERVICE_USER" != "$DB_USER" ]]; then
  die "Service '$SERVICE' runs as '$SERVICE_USER', not '$DB_USER'. Run this script as that user."
fi

# Versioned formulas are keg-only, so put the service's own binaries first on PATH.
FORMULA_PREFIX=$(brew --prefix "$SERVICE" 2>/dev/null || true)
if [[ -n "$FORMULA_PREFIX" && -d "$FORMULA_PREFIX/bin" ]]; then PATH="$FORMULA_PREFIX/bin:$PATH"; fi

pick_bin() {
  local b
  for b in "$@"; do
    if command -v "$b" >/dev/null 2>&1; then command -v "$b"; return 0; fi
  done
  return 1
}
CLIENT=$(pick_bin mariadb mysql)                            || die "MariaDB client (mariadb/mysql) not found."
DUMP_BIN=$(pick_bin mariadb-dump mysqldump)                 || die "mariadb-dump/mysqldump not found."
ADMIN_BIN=$(pick_bin mariadb-admin mysqladmin)              || die "mariadb-admin/mysqladmin not found."
INSTALL_BIN=$(pick_bin mariadb-install-db mysql_install_db) || die "mariadb-install-db/mysql_install_db not found."
PRINT_DEFAULTS=$(pick_bin my_print_defaults || true)

if [[ -n "$EXTRA_DEFAULTS" ]]; then
  [[ -r "$EXTRA_DEFAULTS" ]] || die "Cannot read $EXTRA_DEFAULTS"
fi

q_old "SELECT 1" >/dev/null 2>&1 \
  || die "Cannot log in to MariaDB as '$DB_USER'. Use --defaults-extra-file with credentials."

VERSION=$(q_old "SELECT VERSION()")
CURRENT_PAGE_KB=$(( $(q_old "SELECT @@innodb_page_size") / 1024 ))
DATADIR=$(q_old "SELECT @@datadir"); DATADIR="${DATADIR%/}"
BASEDIR=$(q_old "SELECT @@basedir"); BASEDIR="${BASEDIR%/}"
SOCKET=$(q_old "SELECT @@socket")
[[ -n "$DATADIR" && -d "$DATADIR" ]] || die "Could not determine the data directory."
[[ -n "$SOCKET" && "$SOCKET" != "NULL" ]] || die "Could not determine the server socket path."

if [[ "$CURRENT_PAGE_KB" == "$PAGE_KB" ]]; then
  log "innodb_page_size is already ${PAGE_KB}K. Nothing to do."
  exit 0
fi

# InnoDB files must all live inside the datadir, otherwise moving it isn't enough.
for v in innodb_data_home_dir innodb_log_group_home_dir innodb_undo_directory; do
  val=$(q_old "SELECT @@$v" 2>/dev/null || true)
  val="${val%/}"
  if [[ -n "$val" && "$val" != "NULL" && "$val" != "." && "$val" != "$DATADIR" ]]; then
    die "$v is set to '$val' (outside the datadir). This script only handles a self-contained datadir."
  fi
done

WSREP=$(q_old "SELECT @@wsrep_on" 2>/dev/null || echo 0)
if [[ "$WSREP" == "1" || "$(upper "$WSREP")" == "ON" ]]; then
  die "Galera (wsrep_on) is enabled. This script doesn't handle Galera nodes."
fi

LOG_BIN=$(q_old "SELECT @@log_bin")
IS_REPLICA=$(q_old "SHOW SLAVE STATUS" 2>/dev/null | head -c 1 || true)
NON_TX=$(q_old "SELECT COUNT(*) FROM information_schema.TABLES
                WHERE table_type = 'BASE TABLE' AND engine NOT IN ('InnoDB')
                AND table_schema NOT IN ($EXCLUDED_SCHEMAS)")

DATA_PARENT=$(dirname "$DATADIR")
if [[ "$(stat -f %d "$DATADIR")" != "$(stat -f %d "$DATA_PARENT")" ]]; then
  die "$DATADIR is a mount point (separate volume), so it can't be moved aside."
fi

DATADIR_OWNER=$(stat -f %Su "$DATADIR")
[[ "$DATADIR_OWNER" == "$DB_USER" ]] || die "$DATADIR is owned by '$DATADIR_OWNER', not '$DB_USER'."
DATADIR_PERMS=$(stat -f %Lp "$DATADIR")
OLD_DATADIR="${DATADIR}.old-${TS}"

[[ -n "$BACKUP_DIR" ]] || BACKUP_DIR="$HOME/mariadb-pagesize-${TS}"
BACKUP_DIR="${BACKUP_DIR%/}"
case "$BACKUP_DIR/" in "$DATADIR"/*) die "The backup directory must not be inside the datadir." ;; esac
DUMP_FILE="$BACKUP_DIR/all-databases.sql"

[[ -n "$CONFIG_FILE" ]] || CONFIG_FILE="$BREW_PREFIX/etc/my.cnf.d/99-innodb-page-size.cnf"

EXISTING=""
for p in /etc/my.cnf /etc/mysql "$BREW_PREFIX/etc/my.cnf" "$BREW_PREFIX/etc/my.cnf.d" "$HOME/.my.cnf"; do
  if [[ -e "$p" ]]; then
    hits=$(grep -rEHn '^[[:space:]]*innodb[-_]page[-_]size[[:space:]]*=' "$p" 2>/dev/null \
             | grep -vF "$CONFIG_FILE:" || true)
    if [[ -n "$hits" ]]; then EXISTING="${EXISTING}${hits}
"; fi
  fi
done
[[ -z "$EXISTING" ]] || die "innodb_page_size is already set elsewhere. Remove or comment it out first:
$EXISTING"

# Disk space: dump + new datadir, the old datadir stays where it is.
DATA_BYTES=$(q_old "SELECT COALESCE(SUM(data_length + index_length), 0) FROM information_schema.TABLES
                    WHERE table_schema NOT IN ('information_schema','performance_schema')")
NEED=$(( DATA_BYTES * 12 / 10 + 268435456 ))
BACKUP_PARENT=$(existing_parent "$BACKUP_DIR")
if [[ "$(stat -f %d "$BACKUP_PARENT")" == "$(stat -f %d "$DATA_PARENT")" ]]; then
  AVAIL=$(avail_bytes "$DATA_PARENT")
  (( AVAIL >= NEED * 2 )) || die "Not enough disk space: need ~$(human $((NEED * 2))), have $(human "$AVAIL")."
else
  AVAIL=$(avail_bytes "$BACKUP_PARENT")
  (( AVAIL >= NEED )) || die "Not enough space for the dump in $BACKUP_PARENT: need ~$(human "$NEED"), have $(human "$AVAIL")."
  AVAIL=$(avail_bytes "$DATA_PARENT")
  (( AVAIL >= NEED )) || die "Not enough space for the new datadir: need ~$(human "$NEED"), have $(human "$AVAIL")."
fi

# ---------------------------------------------------------------- plan
cat <<EOF

================ Plan ================
Server version     : $VERSION
Homebrew service   : $SERVICE (user $DB_USER)
Current page size  : ${CURRENT_PAGE_KB}K
New page size      : ${PAGE_KB}K
Data directory     : $DATADIR  (mode $DATADIR_PERMS)
Old datadir kept at: $OLD_DATADIR
Data size (approx) : $(human "$DATA_BYTES")
Backup directory   : $BACKUP_DIR
Config file        : $CONFIG_FILE
Exact row counts   : $( [[ "$EXACT_COUNTS" == 1 ]] && echo yes || echo no )
======================================
EOF

if (( PAGE_KB < 16 )); then
  warn "With ${PAGE_KB}K pages the max index key length and row size shrink. Tables with long indexes"
  warn "(e.g. utf8mb4 VARCHAR(255) keys) may fail to restore; if so the script rolls back automatically."
elif (( PAGE_KB > 16 )); then
  warn "With ${PAGE_KB}K pages each page uses more memory; make sure innodb_buffer_pool_size is adequate."
fi
if [[ "$LOG_BIN" == "1" ]]; then
  warn "Binary logging is on. Binlogs start fresh after the rebuild; any replicas of this server will need re-seeding."
fi
if [[ -n "$IS_REPLICA" ]]; then
  warn "This server is a replica. Replication settings are not re-established; set it up again afterwards."
fi
if (( NON_TX > 0 )); then
  warn "$NON_TX non-InnoDB table(s) found. They are not dumped transactionally."
fi
warn "Stop all applications writing to this database first. Writes after the dump starts will be LOST."
echo

if [[ "$DRY_RUN" == 1 ]]; then
  log "Dry run: all pre-checks passed. No changes were made."
  exit 0
fi

if [[ "$ASSUME_YES" != 1 ]]; then
  printf 'Type "yes" to continue: '
  read -r answer </dev/tty || answer=""
  [[ "$answer" == "yes" ]] || { log "Aborted by user. No changes were made."; exit 0; }
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"   # the dump contains password hashes
LOG_FILE="$BACKUP_DIR/run.log"
exec > >(tee -a "$LOG_FILE") 2>&1
log "Logging to $LOG_FILE"
SECONDS=0

# ---------------------------------------------------------------- 1. backup
STAGE="backup"
log "Taking object snapshot of the current server..."
snapshot cli_old > "$BACKUP_DIR/objects-before.txt"
HAD_TEST_DB=0
if awk -F'\t' '$1 == "schema" && $2 == "test" { f = 1 } END { exit !f }' "$BACKUP_DIR/objects-before.txt"; then
  HAD_TEST_DB=1
fi

if [[ "$EXACT_COUNTS" == 1 ]]; then
  log "Counting rows in every table (this can take a while)..."
  exact_counts cli_old > "$BACKUP_DIR/rows-before.txt"
fi

log "Dumping all databases to $DUMP_FILE ..."
dump_old --all-databases --single-transaction --routines --triggers --events \
         --hex-blob --flush-privileges --max-allowed-packet=1G \
         > "$DUMP_FILE"
tail -n 1 "$DUMP_FILE" | grep -q 'Dump completed' || die "The dump looks incomplete (no 'Dump completed' marker)."
chmod 600 "$DUMP_FILE"
log "Dump finished: $(human "$(stat -f %z "$DUMP_FILE")")"

# ---------------------------------------------------------------- 2. config
STAGE="config"
write_config

# ---------------------------------------------------------------- 3. stop + move
STAGE="stopped"
log "Stopping $SERVICE ..."
brew services stop "$SERVICE"
wait_for_stop || die "MariaDB is still running after 'brew services stop'."

log "Moving $DATADIR -> $OLD_DATADIR"
mv "$DATADIR" "$OLD_DATADIR"
MOVED=1
STAGE="moved"
mkdir "$DATADIR"
chmod "$DATADIR_PERMS" "$DATADIR"

# ---------------------------------------------------------------- 4. initialize
log "Initializing a new data directory with ${PAGE_KB}K pages..."
"$INSTALL_BIN" --user="$DB_USER" --basedir="$BASEDIR" --datadir="$DATADIR" \
  > "$BACKUP_DIR/install-db.log" 2>&1 \
  || die "Initialization failed. See $BACKUP_DIR/install-db.log"
STAGE="initialized"

# ---------------------------------------------------------------- 5. start
log "Starting $SERVICE ..."
brew services start "$SERVICE" || die "Could not start $SERVICE."
wait_for_server || die "Server did not become ready in time. Check the *.err log in $DATADIR."
STAGE="started"

NEW_PAGE=$(( $(q_new "SELECT @@innodb_page_size") / 1024 ))
[[ "$NEW_PAGE" == "$PAGE_KB" ]] || die "New server reports ${NEW_PAGE}K pages, expected ${PAGE_KB}K."
log "New server is running with innodb_page_size=${NEW_PAGE}K"

if [[ "$HAD_TEST_DB" != 1 ]]; then
  q_new "DROP DATABASE IF EXISTS test"
fi

# ---------------------------------------------------------------- 6. restore
log "Restoring the dump (binary logging disabled for this session)..."
ORIG_FLUSH=$(q_new "SELECT @@innodb_flush_log_at_trx_commit")
q_new "SET GLOBAL innodb_flush_log_at_trx_commit = 2"

if command -v pv >/dev/null 2>&1 && { : >/dev/tty; } 2>/dev/null; then
  pv -pterb "$DUMP_FILE" 2>/dev/tty \
    | cli_new --max-allowed-packet=1G --init-command="SET SESSION sql_log_bin = 0"
else
  cli_new --max-allowed-packet=1G --init-command="SET SESSION sql_log_bin = 0" < "$DUMP_FILE"
fi
STAGE="restored"

# Users and grants are now the original ones again.
q_old "SET GLOBAL innodb_flush_log_at_trx_commit = $ORIG_FLUSH"
log "Restore finished."

# ---------------------------------------------------------------- 7. verify
log "Verifying schemas, tables, views, routines, triggers, events and users..."
snapshot cli_old > "$BACKUP_DIR/objects-after.txt"
if ! diff -u "$BACKUP_DIR/objects-before.txt" "$BACKUP_DIR/objects-after.txt" > "$BACKUP_DIR/objects.diff"; then
  die "Object counts differ after restore. See $BACKUP_DIR/objects.diff"
fi

if [[ "$EXACT_COUNTS" == 1 ]]; then
  log "Verifying exact row counts..."
  exact_counts cli_old > "$BACKUP_DIR/rows-after.txt"
  if ! diff -u "$BACKUP_DIR/rows-before.txt" "$BACKUP_DIR/rows-after.txt" > "$BACKUP_DIR/rows.diff"; then
    die "Row counts differ after restore. See $BACKUP_DIR/rows.diff"
  fi
fi
STAGE="verified"

# ---------------------------------------------------------------- done
STAGE="done"
trap - ERR INT TERM
CHECK_BIN=$(pick_bin mariadb-check mysqlcheck || echo mariadb-check)

cat <<EOF

================ Done ================
innodb_page_size changed: ${CURRENT_PAGE_KB}K -> ${PAGE_KB}K  (took $((SECONDS / 60))m $((SECONDS % 60))s)
All checks passed.

Kept for safety (delete once you're satisfied):
  Old data directory : $OLD_DATADIR
                       rm -rf "$OLD_DATADIR"
  Dump               : $DUMP_FILE
  Log and snapshots  : $BACKUP_DIR

Recommended next steps:
  - Refresh optimizer statistics:  $(basename "$CHECK_BIN") --analyze --all-databases
  - Re-seed any replicas of this server if you use replication.
======================================
EOF