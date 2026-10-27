#!/usr/bin/env python3
"""Which indexes does the optimizer CONSIDER?  One EXPLAIN pass, no noise.

    python3 scripts/index-consulted.py --container tpcds-run-1234

BACKGROUND.  Read counters (INDEX_STATISTICS.ROWS_READ) say which indexes
were read while EXECUTING.  They say nothing about which indexes the
optimizer looked at while CHOOSING a plan, and that distinction is not
academic: dropping the 129 indexes that no scale factor read made SF=4
twice as slow.

The obvious experiment -- hide an index with ALTER INDEX ... IGNORED and see
whether plans move -- turns out to be almost unusable here, and the reason is
worth knowing.  ALTER TABLE ... ALTER INDEX is metadata-only, but InnoDB
still re-samples the whole table's persistent statistics, with
innodb_stats_auto_recalc=OFF and no way to suppress it.  Sampling reads
random pages, so every ALTER shifts cardinalities, moves costs, and flips
plans in queries that never mention the hidden index.  Measured on
store_sales: hiding and immediately re-showing one index -- a net no-op --
changed 31 of 44 query plans.  Raising
innodb_stats_persistent_sample_pages from 160 to 4000 made ANALYZE 10x
slower and left the noise at 31 of 44, so it is not a precision problem.
See scripts/plan-sensitivity.py for that route and its noise filtering.

THIS IS THE BETTER INSTRUMENT.  EXPLAIN already reports, per table access,
the `possible_keys` the optimizer considered and the `key` it chose.  An
index that appears nowhere in any plan for the whole query set was never a
candidate for anything, so removing it cannot change any plan.  That needs
one EXPLAIN pass, costs no ALTER, and is perfectly deterministic -- two
captures of all 44 statements are byte-identical.

Matching is deliberately crude: an index counts as consulted if its name
appears anywhere in the plan JSON, as a whole word.  That over-counts rather
than under-counts, which is the safe direction when the cost of a wrong
"droppable" is a slower query.

VERDICTS
    used        read during execution              -> keep
    considered  never read, but the optimizer
                weighed it for some query          -> keep (this is the
                                                      category read counters
                                                      cannot see)
    unreferenced  never read and never mentioned
                in any plan                        -> safe to drop

"unreferenced" is relative to THIS query set at THIS scale factor.  Run it at
every scale that matters and keep an index consulted by any of them.
"""
import argparse, json, os, re, subprocess, sys

sys.stdout.reconfigure(line_buffering=True)
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import importlib.util
_spec = importlib.util.spec_from_file_location(
    "plan_sensitivity", f"{REPO}/scripts/plan-sensitivity.py")
_ps = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ps)
build_plan_script, run_sql, parse_plans = (
    _ps.build_plan_script, _ps.run_sql, _ps.parse_plans)


def plan_index_names(plan_text, known):
    """Index names mentioned anywhere in one plan, as whole words."""
    return {n for n in known if re.search(rf'(?<![\w]){re.escape(n)}(?![\w])',
                                          plan_text)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--container", required=True)
    ap.add_argument("--queries", default=f"{REPO}/queries/tuned")
    ap.add_argument("--out", default=f"{REPO}/analysis/index-consulted-sf4.tsv")
    ap.add_argument("--usage", action="append", default=[],
                    help="index-usage-sf<N>.tsv from a measured benchmark run; "
                         "repeatable. An index read at ANY scale counts as used.")
    a = ap.parse_args()

    # Nothing hidden, or the capture would describe a different database.
    hidden = run_sql(a.container, """
SELECT DISTINCT TABLE_NAME, INDEX_NAME FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA='tpcds' AND IGNORED='YES';""").split()
    if hidden:
        pairs = list(zip(hidden[0::2], hidden[1::2]))
        print(f"  un-hiding {len(pairs)} leftover IGNORED indexes first")
        run_sql(a.container, "\n".join(
            f"ALTER TABLE {t} ALTER INDEX {i} NOT IGNORED;" for t, i in pairs))

    rows = run_sql(a.container, """
SELECT s.TABLE_NAME, s.INDEX_NAME,
       ROUND(IFNULL(z.stat_value,0) * @@innodb_page_size / 1048576, 1),
       IFNULL(u.ROWS_READ, 0)
FROM (SELECT DISTINCT TABLE_SCHEMA, TABLE_NAME, INDEX_NAME
      FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA='tpcds' AND INDEX_NAME<>'PRIMARY') s
LEFT JOIN information_schema.INDEX_STATISTICS u
       ON u.TABLE_SCHEMA=s.TABLE_SCHEMA AND u.TABLE_NAME=s.TABLE_NAME
      AND u.INDEX_NAME=s.INDEX_NAME
LEFT JOIN mysql.innodb_index_stats z
       ON z.database_name=s.TABLE_SCHEMA AND z.table_name=s.TABLE_NAME
      AND z.index_name=s.INDEX_NAME AND z.stat_name='size'
ORDER BY 3 DESC, 1, 2;""")
    idx = [(f[0], f[1], float(f[2]), int(f[3]))
           for f in (l.split("\t") for l in rows.splitlines()) if len(f) == 4]

    measured = {}
    for path in a.usage:
        for line in open(path):
            f = line.rstrip("\n").split("\t")
            if len(f) >= 4 and f[3].isdigit():
                k = (f[0], f[1])
                measured[k] = max(measured.get(k, 0), int(f[3]))
    if measured:
        print(f"  read counts from {len(a.usage)} measured run(s)")

    script, labels, _ = build_plan_script(a.queries)
    plans = parse_plans(run_sql(a.container, script), labels)
    # Determinism check: the whole argument rests on this.
    again = parse_plans(run_sql(a.container, script), labels)
    drift = [l for l in labels if plans[l] != again[l]]
    print(f"  {len(labels)} statements captured twice; {len(drift)} differ"
          f"{' -- NOT deterministic, results unsafe' if drift else ''}")

    known = {i[1] for i in idx}
    where = {}
    for l in labels:
        for name in plan_index_names(plans[l], known):
            where.setdefault(name, set()).add(l.split("#")[0])

    results = []
    for tbl, name, mb, read in idx:
        read = measured.get((tbl, name), read)
        qs = sorted(where.get(name, ()), key=lambda q: int(q[5:]))
        verdict = "used" if read > 0 else "considered" if qs else "unreferenced"
        results.append((tbl, name, mb, read, verdict, qs))

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w") as fh:
        fh.write("table\tindex\tmb\trows_read\tverdict\tconsidered_by\n")
        for tbl, name, mb, read, verdict, qs in results:
            fh.write(f"{tbl}\t{name}\t{mb}\t{read}\t{verdict}\t{','.join(qs)}\n")
    print(f"  wrote {a.out}\n")

    for v in ("used", "considered", "unreferenced"):
        sel = [r for r in results if r[4] == v]
        print(f"    {v:<13} {len(sel):3d} indexes, {sum(r[2] for r in sel)/1024:6.2f} GB")
    drop = sorted((r for r in results if r[4] == "unreferenced"),
                  key=lambda r: -r[2])
    print(f"\n  largest never read and never mentioned in any plan:")
    for r in drop[:20]:
        print(f"    {r[1]:<40} {r[2]:8.1f} MB  on {r[0]}")


if __name__ == "__main__":
    main()
