# Shared configuration keys and functions for the host wrapper and entrypoint.
# Command-line overrides are applied by reproduce.sh before these defaults.
TPCDS_CONFIG_KEYS="SCALE PAGE_SIZE BUFFER_POOL SAMPLE_PAGES QUERYSET TUNED RNGSEED MARIADB_TAG KEPT_INDEXES PRUNE_INDEXES TMP_TABLE_SIZE MAX_HEAP_TABLE_SIZE ARIA_PAGECACHE_BUFFER_SIZE SORT_BUFFER_SIZE JOIN_BUFFER_SIZE JOIN_BUFFER_SPACE_LIMIT STATEMENT_TIMEOUT"
TPCDS_MEMORY_KEYS="BUFFER_POOL TMP_TABLE_SIZE MAX_HEAP_TABLE_SIZE ARIA_PAGECACHE_BUFFER_SIZE SORT_BUFFER_SIZE JOIN_BUFFER_SIZE JOIN_BUFFER_SPACE_LIMIT"

tpcds_profile_defaults() {
  case "$PROFILE" in
    quick|full)
      if [[ "$PROFILE" == full ]]; then : "${SCALE:=4}"; else : "${SCALE:=1}"; fi
      : "${BUFFER_POOL:=8G}" "${QUERYSET:=tuned}"
      : "${TMP_TABLE_SIZE:=1536M}" "${MAX_HEAP_TABLE_SIZE:=1536M}"
      : "${ARIA_PAGECACHE_BUFFER_SIZE:=1G}" "${SORT_BUFFER_SIZE:=64M}"
      : "${JOIN_BUFFER_SIZE:=64M}" "${JOIN_BUFFER_SPACE_LIMIT:=256M}"
      : "${STATEMENT_TIMEOUT:=3600}" ;;
    smoke)
      : "${SCALE:=1}" "${BUFFER_POOL:=1G}" "${QUERYSET:=smoke}"
      : "${TMP_TABLE_SIZE:=32M}" "${MAX_HEAP_TABLE_SIZE:=32M}"
      : "${ARIA_PAGECACHE_BUFFER_SIZE:=64M}" "${SORT_BUFFER_SIZE:=4M}"
      : "${JOIN_BUFFER_SIZE:=4M}" "${JOIN_BUFFER_SPACE_LIMIT:=32M}"
      : "${STATEMENT_TIMEOUT:=300}" ;;
    *) echo "unknown profile '$PROFILE' (use quick, full or smoke)" >&2; return 1 ;;
  esac
  : "${PAGE_SIZE:=32}" "${SAMPLE_PAGES:=160}" "${TUNED:=tuned}" "${RNGSEED:=10}"
  : "${MARIADB_TAG:=13.0.2}" "${KEPT_INDEXES:=0}" "${PRUNE_INDEXES:=0}"
}

tpcds_memory_bytes() {
  # MariaDB K/M/G units are powers of 1024. Reject fractions, zero and overflow.
  local value="$1" digits unit factor number
  if [[ ! "$value" =~ ^([0-9]+)([KkMmGg]?)$ ]]; then
    echo "invalid memory size '$value': use positive bytes or K/M/G (e.g. 1024M, 1G)" >&2
    return 1
  fi
  digits="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]}"
  while [[ ${#digits} -gt 1 && "$digits" == 0* ]]; do digits="${digits#0}"; done
  [[ ${#digits} -le 18 ]] || { echo "memory size '$value' is too large" >&2; return 1; }
  number=$((10#$digits))
  case "$unit" in
    k|K) factor=1024 ;; m|M) factor=1048576 ;; g|G) factor=1073741824 ;; *) factor=1 ;;
  esac
  if (( number == 0 || number > 9223372036854775807 / factor )); then
    echo "memory size '$value' must be positive and fit in a signed 64-bit integer" >&2
    return 1
  fi
  printf '%s\n' "$((number * factor))"
}

tpcds_validate_config() {
  local key value
  for key in SCALE SAMPLE_PAGES STATEMENT_TIMEOUT; do
    value="${!key}"
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo "$key must be a positive integer" >&2; return 1; }
  done
  [[ "$RNGSEED" =~ ^[0-9]+$ ]] || { echo "RNGSEED must be a nonnegative integer" >&2; return 1; }
  case "$PAGE_SIZE" in 4|8|16|32|64) ;; *) echo "PAGE_SIZE must be 4, 8, 16, 32 or 64" >&2; return 1 ;; esac
  case "$TUNED" in baseline|tuned|both) ;; *) echo "TUNED must be baseline, tuned or both" >&2; return 1 ;; esac
  case "$QUERYSET" in all|tier45|tuned|smoke) ;; *) echo "QUERYSET must be all, tier45, tuned or smoke" >&2; return 1 ;; esac
  if [[ "$PROFILE" == smoke && "$QUERYSET" != smoke ]]; then
    echo "smoke requires QUERYSET=smoke; use quick for other query sets" >&2
    return 1
  fi
  for key in KEPT_INDEXES PRUNE_INDEXES; do
    case "${!key}" in 0|1) ;; *) echo "$key must be 0 or 1" >&2; return 1 ;; esac
    if [[ "$PROFILE" == smoke && "${!key}" != 0 ]]; then
      echo "smoke skips secondary-index changes; $key must be 0" >&2
      return 1
    fi
  done
  for key in $TPCDS_MEMORY_KEYS; do
    tpcds_memory_bytes "${!key}" >/dev/null || return 1
    printf -v "$key" '%s' "$(printf '%s' "${!key}" | tr '[:lower:]' '[:upper:]')"
  done
}

tpcds_memory_budget() {
  # A screening estimate, NOT a maximum: several temporary tables may coexist.
  # Include both global caches, one temp table, execution buffers and overhead.
  local pool aria tmp heap sort joins join_one
  pool=$(tpcds_memory_bytes "$BUFFER_POOL") || return 1
  aria=$(tpcds_memory_bytes "$ARIA_PAGECACHE_BUFFER_SIZE") || return 1
  tmp=$(tpcds_memory_bytes "$TMP_TABLE_SIZE") || return 1
  heap=$(tpcds_memory_bytes "$MAX_HEAP_TABLE_SIZE") || return 1
  sort=$(tpcds_memory_bytes "$SORT_BUFFER_SIZE") || return 1
  joins=$(tpcds_memory_bytes "$JOIN_BUFFER_SPACE_LIMIT") || return 1
  join_one=$(tpcds_memory_bytes "$JOIN_BUFFER_SIZE") || return 1
  (( heap >= tmp )) || tmp=$heap
  (( joins >= join_one )) || joins=$join_one
  local total=536870912 amount
  for amount in "$pool" "$aria" "$tmp" "$sort" "$joins"; do
    if (( amount > 9223372036854775807 - total )); then
      echo "combined memory budget is too large" >&2; return 1
    fi
    total=$((total + amount))
  done
  printf '%s\n' "$total"
}

tpcds_memory_cnf() {
  cat <<EOF
tmp_table_size                 = $TMP_TABLE_SIZE
max_heap_table_size            = $MAX_HEAP_TABLE_SIZE
aria_pagecache_buffer_size     = $ARIA_PAGECACHE_BUFFER_SIZE
sort_buffer_size               = $SORT_BUFFER_SIZE
join_buffer_size               = $JOIN_BUFFER_SIZE
join_buffer_space_limit        = $JOIN_BUFFER_SPACE_LIMIT
EOF
}
