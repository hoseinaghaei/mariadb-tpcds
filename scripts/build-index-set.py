#!/usr/bin/env python3
"""Write the index set a build should actually create, and a record of what
was left out and why.

    python3 scripts/build-index-set.py

Produces:

    sql/indexes_kept.sql     what to CREATE -- the default for a new database
    sql/dropped_indexes.md   what was left out, with sizes and provenance

WHY NOT CREATE EVERYTHING AND DROP.  The container used to build all 188
indexes and then drop 127 of them.  That works, but index creation is the
longest stage of a build -- most of an hour at SF=4 -- and three quarters of
it was being spent on indexes about to be thrown away.  Building the kept
set directly skips that.

WHAT IS KEPT.  An index survives if either scale factor read it during the
40 tier-4/5 queries (scripts/index-usefulness.sh at SF=1 and SF=4), plus an
explicit list below of indexes adopted on direct measurement.  Everything
else is read by neither scale and is left out.

WHAT IS NOT A REASON TO DROP.  "Unused" is a property of an index AND a
workload AND a configuration, not of the index.  This project measured the
same set at 16K and at 32K pages and disagreed with itself about which
members were idle (report/17, report/22).  The whole set is always one
command away -- `mariadb tpcds < sql/all_indexes.sql` -- which is what makes
leaving them out reasonable rather than reckless.
"""
import os, re, sys, collections, datetime

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANA = f"{REPO}/analysis"

# Adopted on direct measurement even though the usage reports cannot speak
# for them -- they were created after the SF=1 report was taken, so they show
# as "present in only one report" rather than used or unused.
#
#   idx_ws_q66 / idx_cs_q66   Aysha's covering indexes for q66.  Measured at
#                             SF=4 with the index toggled IGNORED/NOT IGNORED:
#                             9.3, 5.4, 6.1s against 0.4, 0.5, 0.4s (~13x),
#                             answers identical, and four alternating full
#                             suite passes found no cost to the other 39
#                             queries.  602 MB.
ADOPTED = {"idx_ws_q66", "idx_cs_q66"}

# Deliberately NOT adopted, and why.  Listed so the decision is visible
# rather than an omission someone has to notice.
WITHHELD = {
    "idx_ss_date_store_profit":
        "built for q77 and does nothing for q77; helps q5 (~2.4x) and q70 "
        "(~2.9x) reproducibly but costs 512 MB and more than doubles "
        "store_sales index storage. Left out pending a decision; "
        "sql/15_q77_covering_index.sql creates it.",
}

ORIGINS = [("sql/05_indexes.sql", "reference repo"),
           ("sql/11_optimizer_indexes.sql", "optimizer experiments"),
           ("sql/14_contributed_indexes.sql", "contributed by the team")]


def origins():
    """index name -> which file introduced it."""
    out = {}
    for rel, label in ORIGINS:
        p = f"{REPO}/{rel}"
        if not os.path.exists(p):
            continue
        for m in re.finditer(r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)',
                             open(p).read(), re.I):
            out.setdefault(m.group(1), label)
    return out


def usage(sf):
    # Prefer the container's own report.  The macOS files describe a
    # different machine -- at SF=1, with identical data and the same MariaDB
    # version, the two disagreed about 6 of 188 indexes, three of which the
    # container reads and macOS does not.  Pruning on the wrong machine's
    # evidence is what made SF=4 50% slower.
    cands = [f"{REPO}/results/usage-sf{sf}/index-usage-sf{sf}.tsv",
             f"{REPO}/results/sf{sf}/index-usage-sf{sf}.tsv",
             f"{ANA}/index-usage-sf{sf}.tsv"]
    found = [c for c in cands if os.path.exists(c)]
    if not found:
        sys.exit(f"no index usage report for SF={sf} -- run ./run-scales.sh {sf}")
    p = found[0]
    print(f"  SF={sf} usage from {os.path.relpath(p, REPO)}")
    out = {}
    for line in open(p):
        f = line.rstrip("\n").split("\t")
        if len(f) >= 5:
            out[(f[0], f[1])] = {"mb": float(f[2]), "reads": int(f[3]), "verdict": f[4]}
    return out


def main():
    allsql = f"{REPO}/sql/all_indexes.sql"
    if not os.path.exists(allsql):
        sys.exit("missing sql/all_indexes.sql -- run scripts/dump-indexes.py")
    creates = {}
    for line in open(allsql):
        m = re.match(r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS\s+(\w+)\s+ON\s+(\w+)',
                     line, re.I)
        if m:
            creates[(m.group(2), m.group(1))] = line.rstrip("\n")

    a, b = usage(1), usage(4)
    org = origins()

    kept, dropped = [], []
    for key, stmt in creates.items():
        tbl, idx = key
        reads = max(a.get(key, {}).get("reads", 0), b.get(key, {}).get("reads", 0))
        mb = max(a.get(key, {}).get("mb", 0), b.get(key, {}).get("mb", 0))
        if idx in WITHHELD:
            dropped.append((tbl, idx, mb, org.get(idx, "measured here"), WITHHELD[idx]))
        elif reads > 0 or idx in ADOPTED:
            kept.append((tbl, idx, stmt))
        else:
            dropped.append((tbl, idx, mb, org.get(idx, "measured here"),
                            "read by neither SF=1 nor SF=4"))

    by_tbl = collections.OrderedDict()
    for tbl, idx, stmt in sorted(kept):
        by_tbl.setdefault(tbl, []).append(stmt)

    L = ["-- " + "=" * 72,
         "--  The index set a new database should build.",
         "--",
         f"--  Generated {datetime.datetime.now():%Y-%m-%d %H:%M} by "
         "scripts/build-index-set.py.",
         f"--  {len(kept)} secondary indexes kept, {len(dropped)} left out.",
         "--",
         "--  An index is here if either scale factor read it while running the",
         "--  40 tier-4/5 queries, or if it was adopted on direct measurement.",
         "--  What was left out, and why, is in sql/dropped_indexes.md.",
         "--",
         "--  Nothing is lost: sql/all_indexes.sql still holds every index this",
         "--  project has ever built, and restores them in one command.",
         "-- " + "=" * 72,
         "",
         "SET SESSION alter_algorithm='INPLACE';",
         ""]
    for tbl, stmts in by_tbl.items():
        L.append(f"-- {tbl}  ({len(stmts)})")
        L += stmts
        L.append("")
    L.append("ANALYZE TABLE " + ", ".join(by_tbl) + ";")
    L.append("")
    open(f"{REPO}/sql/indexes_kept.sql", "w").write("\n".join(L))

    dropped.sort(key=lambda r: -r[2])
    total = sum(r[2] for r in dropped)
    M = [f"# Indexes we build without, and why",
         "",
         f"Generated {datetime.datetime.now():%Y-%m-%d %H:%M} by "
         "`scripts/build-index-set.py`.",
         "",
         f"A new database builds **{len(kept)} secondary indexes**. "
         f"**{len(dropped)} others — {total:,.0f} MB ({total/1024:.1f} GB) — "
         f"are not built.**",
         "",
         "These came from the reference repository, from our own optimizer "
         "experiments, and from indexes classmates contributed. They are not "
         "wrong; the 40 tier-4/5 queries simply never read them, at either "
         "scale factor, under this configuration — **as measured inside the "
         "container itself**. An earlier version of this list was derived "
         "from macOS measurements and was wrong: at SF=1, with identical "
         "data and the same MariaDB version, the two environments disagreed "
         "about 6 of 188 indexes, three of which the container reads and "
         "macOS does not.",
         "",
         "## It satisfies the usage rule and still costs SF=4 dearly",
         "",
         "Measured in the container with this exact set:",
         "",
         "| | SF=1 | SF=4 |",
         "|---|---:|---:|",
         "| full set (166) | 114.8–205.2s over five runs | **491.4s** |",
         "| this set (37) | **101.7s** | **1487.0s** |",
         "",
         "At SF=1 it is the best result measured. At SF=4 it is **3x worse**, "
         "and a second pruned set built from different evidence was also "
         "worse (738.3s), so the direction is not an accident.",
         "",
         "**Why a usage-derived set can still be wrong.** The counters were "
         "taken with all 166 indexes present, and they record which indexes "
         "the optimizer *chose* — not which ones it needed in order to choose "
         "well. Remove 129 of them and the cost estimates move, so the plans "
         "move. The proof is in this run's own report: **7 of the 37 kept "
         "indexes were never read**, and 8 at SF=1. If the plans had survived "
         "the pruning, all 37 would still be in use.",
         "",
         "At SF=1 the database nearly fits the 8 GB pool, so freeing 16 GB of "
         "index pages outweighs the worse plans. At SF=4 it does not fit "
         "either way, and the worse plans are all that is left.",
         "",
         "**On timing, this list makes no promise.** An earlier attempt "
         "claimed dropping indexes made the suite faster; that rested on two "
         "noisy measurements and is withdrawn. Five runs of the *unchanged* "
         "full set at SF=1 measured 114.8, 142.0, 191.6, 200.7 and 205.2s — "
         "a spread far wider than any index effect being looked for. What "
         "this list rests on instead is read counters, which are exact: an "
         "index was read or it was not.",
         "",
         "## Getting them back",
         "",
         "```bash",
         "mariadb tpcds < sql/all_indexes.sql     # every index, one command",
         "```",
         "",
         "Worth knowing before you decide they are gone for good: **\"unused\" "
         "is a property of an index *and* a workload *and* a configuration**, "
         "not of the index. This project measured the same set at 16K and at "
         "32K pages and got different answers about which members were idle "
         "(`report/17`, `report/22`).",
         "",
         "## What is not built",
         "",
         "| table | index | MB | came from | why |",
         "|---|---|---:|---|---|"]
    for tbl, idx, mb, src, why in dropped:
        M.append(f"| {tbl} | `{idx}` | {mb:,.0f} | {src} | {why} |")
    M.append("")
    open(f"{REPO}/sql/dropped_indexes.md", "w").write("\n".join(M))

    print(f"  sql/indexes_kept.sql    {len(kept)} indexes")
    print(f"  sql/dropped_indexes.md  {len(dropped)} left out, "
          f"{total:,.0f} MB ({total/1024:.1f} GB)")
    src_count = collections.Counter(r[3] for r in dropped)
    for s, n in src_count.most_common():
        print(f"      {n:>4} from {s}")


if __name__ == "__main__":
    main()
