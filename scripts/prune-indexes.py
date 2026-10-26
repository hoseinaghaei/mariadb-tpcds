#!/usr/bin/env python3
"""Find indexes no scale factor reads, and write the DROP statements.

    python3 scripts/prune-indexes.py            # after running both reports

Reads analysis/index-usage-sf1.tsv and index-usage-sf4.tsv (produced by
scripts/index-usefulness.sh) and writes sql/drop_unused_indexes.sql.

THE RULE IS INTERSECTION, NOT UNION.  An index idle at one scale factor can
be busy at another: the optimizer's choices move as table sizes and
statistics change, and this project has already measured the same index set
at 16K and at 32K pages and got different answers about which members were
idle (report/17, report/22).  So an index is only a candidate if **neither**
scale read it.  Anything read by either one is kept, however little.

Excluded from consideration entirely:

  PRIMARY   part of the table definition, not droppable
  IGNORED   the optimizer is not allowed to read these, so a zero read count
            is circular evidence -- they are listed for a human to decide

Even after all that, the evidence covers 40 queries under one configuration.
Everything dropped is recoverable from sql/all_indexes.sql, and
`ALTER TABLE t ALTER INDEX i IGNORED` is the reversible way to test the same
decision first.
"""
import os, sys, csv, datetime, collections

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANA = f"{REPO}/analysis"
OUT = f"{REPO}/sql/drop_unused_indexes.sql"


def load(sf):
    # Either environment can produce these.  The host writes to analysis/ via
    # scripts/index-usefulness.sh; the container writes the same shape to
    # results/sf<N>/ as a by-product of any run.  Prefer whichever is newer,
    # so a fresh container run supersedes a stale host one rather than being
    # silently ignored.
    cands = [f"{ANA}/index-usage-sf{sf}.tsv",
             f"{REPO}/results/sf{sf}/index-usage-sf{sf}.tsv",
             f"{REPO}/results/index-usage-sf{sf}.tsv"]
    found = [c for c in cands if os.path.exists(c)]
    if not found:
        sys.exit(f"no index usage report for SF={sf}.  Produce one with\n"
                 f"    ./scripts/index-usefulness.sh {sf}          (host)\n"
                 f"    ./run-scales.sh {sf}                        (container)")
    p = max(found, key=os.path.getmtime)
    print(f"  SF={sf}: {os.path.relpath(p, REPO)}")
    out = {}
    for line in open(p):
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 5:
            continue
        tbl, idx, mb, reads, verdict = parts[:5]
        out[(tbl, idx)] = {"mb": float(mb), "reads": int(reads), "verdict": verdict}
    return out


def main():
    a, b = load(1), load(4)
    keys = sorted(set(a) | set(b))

    drop, keep, ignored, missing = [], [], [], []
    for k in keys:
        tbl, idx = k
        if idx == "PRIMARY":
            continue
        ra, rb = a.get(k), b.get(k)
        if ra is None or rb is None:
            missing.append((k, "SF=1" if ra is None else "SF=4"))
            continue
        if "IGNORED" in (ra["verdict"], rb["verdict"]):
            ignored.append((k, max(ra["mb"], rb["mb"])))
            continue
        if ra["reads"] == 0 and rb["reads"] == 0:
            drop.append((k, max(ra["mb"], rb["mb"])))
        else:
            keep.append((k, max(ra["mb"], rb["mb"]), ra["reads"], rb["reads"]))

    drop.sort(key=lambda x: -x[1])
    mb = sum(d[1] for d in drop)

    L = [
        "-- " + "=" * 72,
        "--  Indexes that NEITHER scale factor read.",
        "--",
        f"--  Generated {datetime.datetime.now():%Y-%m-%d %H:%M} by "
        "scripts/prune-indexes.py from",
        "--  analysis/index-usage-sf1.tsv and index-usage-sf4.tsv.",
        "--",
        f"--  {len(drop)} indexes, {mb:,.0f} MB ({mb/1024:.1f} GB).",
        f"--  Kept because at least one scale read them: {len(keep)}.",
        f"--  Skipped because they are IGNORED (cannot be read, so a zero",
        f"--  count proves nothing): {len(ignored)}.",
        "--",
        "--  PUT THEM ALL BACK:",
        "--      mariadb tpcds < sql/all_indexes.sql",
        "--",
        "--  The rule is intersection, not union: an index idle at one scale",
        "--  may be busy at another, and this project has measured the same",
        "--  index set at 16K and 32K pages and disagreed with itself about",
        "--  which members were idle (report/17, report/22).  The evidence",
        "--  here is 40 queries at two scale factors under one configuration.",
        "--",
        "--  To test the same decision reversibly first, use IGNORED instead:",
        "--  metadata-only, about 0.15s each, and the index stays on disk.",
        "-- " + "=" * 72,
        "",
    ]
    by_tbl = collections.OrderedDict()
    for (tbl, idx), m in drop:
        by_tbl.setdefault(tbl, []).append((idx, m))
    for tbl, items in by_tbl.items():
        L.append(f"-- {tbl}: {len(items)} indexes, "
                 f"{sum(m for _, m in items):,.0f} MB")
        for idx, m in items:
            L.append(f"DROP INDEX IF EXISTS {idx} ON {tbl};   -- {m:,.0f} MB")
        L.append("")
    if ignored:
        L.append("-- Not touched: IGNORED, so their zero read count is circular.")
        for (tbl, idx), m in sorted(ignored, key=lambda x: -x[1]):
            L.append(f"--   {tbl}.{idx}  ({m:,.0f} MB)")
        L.append("")
    if missing:
        L.append("-- Not touched: present in only one report.")
        for (tbl, idx), which in missing:
            L.append(f"--   {tbl}.{idx}  (absent from {which})")
        L.append("")

    open(OUT, "w").write("\n".join(L))
    print(f"  wrote {OUT}")
    print(f"  drop      {len(drop):>4}  {mb:>9,.0f} MB  ({mb/1024:.1f} GB)")
    print(f"  keep      {len(keep):>4}")
    print(f"  ignored   {len(ignored):>4}  (not evidence)")
    if missing:
        print(f"  one-sided {len(missing):>4}  (in only one report)")
    print("\n  largest candidates:")
    for (tbl, idx), m in drop[:10]:
        print(f"    {tbl:<16} {idx:<34} {m:>8,.0f} MB")


if __name__ == "__main__":
    main()
