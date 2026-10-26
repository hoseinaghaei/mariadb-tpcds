# Sourced guard: these scripts need a local macOS MariaDB datadir, and the
# project does not keep one any more.
#
# pagesize/data-32k (SF=1) and data-32k-sf4 (SF=4) were deleted on
# 2026-10-26, 42.8 GB, once the container could do everything they were for:
# run the suite at any scale, produce index-usage statistics, and apply the
# pruned index set.  Running benchmarks in one place removes a whole class of
# confusion -- two environments with different MariaDB versions, different
# O_DIRECT behaviour and, as it turned out, different dsdgen seeds.
#
# Everything these scripts measured is still in pagesize/results/ and
# analysis/; only the databases are gone.
#
# To use these scripts again, rebuild an instance:
#     pagesize/build-instance.sh 32        # SF=1
#     pagesize/build-sf4.sh                # SF=4   (hours)
#
# Or do the same work in the container, which is the supported path:
#     ./run-scales.sh 1 4                  # benchmark at both scales
#     ./run-scales.sh 4 PRUNE_INDEXES=1    # with the pruned index set
#     python3 analysis/analyze.py          # tables, charts, flagged queries
require_local_db() {   # $1 = datadir path
  [[ -d "$1" ]] && return 0
  cat >&2 <<EOF

ERROR: $1 does not exist.

  The local macOS databases were removed on 2026-10-26 (42.8 GB) once the
  container could do everything they were for.  Benchmarks now run there:

      ./run-scales.sh 1 4                  # both scales
      ./run-scales.sh 4 PRUNE_INDEXES=1    # with the pruned index set
      python3 analysis/analyze.py          # tables, charts, flagged queries

  To rebuild this instance instead:
      pagesize/build-instance.sh 32        # SF=1
      pagesize/build-sf4.sh                # SF=4, hours

EOF
  return 1
}
