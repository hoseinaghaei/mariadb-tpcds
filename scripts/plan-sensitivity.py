#!/usr/bin/env python3
"""Which indexes does the optimizer actually consult?

    python3 scripts/plan-sensitivity.py --container tpcds-run-1234

THE PROBLEM.  Read counters (INDEX_STATISTICS.ROWS_READ) say which indexes
were *read while executing*.  They do not say which indexes the optimizer
*looked at while choosing a plan*.  Dropping 129 indexes that no scale factor
read made SF=4 roughly twice as slow, so the difference is not academic: the
optimizer costs alternatives using indexes it then does not use, and taking
them away makes it cost badly.

THE TEST.  `ALTER TABLE t ALTER INDEX i IGNORED` hides one index from the
optimizer while leaving it on disk.  Hide it, EXPLAIN every query, compare.
A plan that does not move cannot have depended on the index.

THE COMPLICATION, and it is a big one.  ALTER TABLE ... ALTER INDEX is a
metadata-only change, but InnoDB still RE-SAMPLES the persistent statistics
for the whole table -- with innodb_stats_auto_recalc=OFF, and there is no
way to suppress it.  Sampling reads innodb_stats_persistent_sample_pages
(160 here) random pages, so every ALTER produces slightly different
cardinalities, which move the cost estimates, which flip plans in queries
that have nothing to do with the hidden index.  Writing the old values back
into mysql.innodb_index_stats does not help: InnoDB keeps the re-sampled
numbers in memory and neither FLUSH TABLE, FLUSH TABLES nor ALTER ...
STATS_PERSISTENT=1 makes it re-read them.

Measured on catalog_sales, hiding ONE index appeared to move 37 of 44 query
plans.  Almost all of that was the re-sampling, not the index.

So a single hide/compare is worthless here.  Instead each index is measured
REPLICATED and PAIRED:

    repeat R times:  hide it,   EXPLAIN everything  -> H[r]
                     un-hide it, EXPLAIN everything -> V[r]

A statement counts only if it is stable across all H[r] AND across all V[r]
-- that is the noise filter.  Among the stable ones, a statement whose plan
differs between H and V is real evidence.  A query is additionally only
eligible if it references the index's table at all.

On catalog_sales this correctly collapses the apparent 37 to 0: the noise
(hidden-vs-hidden, 19 queries) is as large as the signal.  On inventory,
where sampling is steadier, noise is 0-2 and idx_inv_date_sk shows a stable
6-query effect, 4 of which survive every filter.

VERDICTS
    used        read during execution                 -> keep
    consulted   never read, but hiding it stably
                moves a plan in a query that uses
                its table                             -> keep
    dead        never read, and no plan moves that
                survives the noise filter             -> safe to drop

VERDICTS
    used        read during execution                 -> keep
    consulted   never read, but hiding it moves plans -> keep
    dead        never read and hiding it moves nothing -> safe to drop

CAVEATS worth stating in the report.  A plan change is not proof the index
HELPS -- the alternative plan might be as good or better.  This tool is
conservative in that direction: anything that stably moves a plan is kept.
The negative result is the solid one: nothing the optimizer decides about
this query set depends on a "dead" index.

And "dead" is relative to THIS query set at THIS scale factor.  An index that
no tier-4/5 query consults may still matter to query 39 or to a different
scale.  The claim is not "useless", it is "nothing in the measured workload
consults it".
"""
import argparse, json, os, re, subprocess, sys, time

# Unbuffered: this runs for tens of minutes and the progress lines are the
# only way to see where it is.
sys.stdout.reconfigure(line_buffering=True)

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOCK = "/data/mysql.sock"


def split_statements(sql):
    """Split on semicolons that are not inside a string or a comment."""
    out, cur, i, n = [], [], 0, len(sql)
    while i < n:
        c = sql[i]
        if c in "'\"":
            q = c; cur.append(c); i += 1
            while i < n:
                if sql[i] == "\\":
                    cur.append(sql[i:i+2]); i += 2; continue
                cur.append(sql[i])
                if sql[i] == q:
                    i += 1; break
                i += 1
            continue
        if sql.startswith("--", i) or sql.startswith("#", i):
            j = sql.find("\n", i)
            i = n if j < 0 else j + 1
            continue
        if sql.startswith("/*", i):
            j = sql.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == ";":
            out.append("".join(cur).strip()); cur = []; i += 1; continue
        cur.append(c); i += 1
    tail = "".join(cur).strip()
    if tail:
        out.append(tail)
    return [s for s in out if s]


TABLES = ("store_sales", "store_returns", "catalog_sales", "catalog_returns",
          "web_sales", "web_returns", "inventory", "customer",
          "customer_address", "customer_demographics", "household_demographics",
          "date_dim", "time_dim", "item", "store", "call_center", "catalog_page",
          "web_site", "web_page", "warehouse", "ship_mode", "reason",
          "income_band", "promotion")


def build_plan_script(qdir):
    """One SQL script that EXPLAINs every statement of every tuned query.

    Each EXPLAIN is preceded by a SELECT naming it, so the output can be cut
    back apart into (query, statement index, plan) without guessing.
    """
    lines, labels, refs = [], [], {}
    for path in sorted(os.listdir(qdir)):
        if not path.endswith(".sql"):
            continue
        name = path[:-4]
        stmts = split_statements(open(os.path.join(qdir, path)).read())
        k = 0
        for s in stmts:
            head = s.lstrip("( \n\t").upper()
            if head.startswith("SET "):
                lines.append(s + ";")
                continue
            if not (head.startswith("SELECT") or head.startswith("WITH")):
                continue
            label = f"{name}#{k}"
            lines.append(f"SELECT '@@{label}';")
            lines.append(f"EXPLAIN FORMAT=JSON {s};")
            labels.append(label)
            # Which base tables the statement names.  Hiding an index on a
            # table a query never mentions cannot change that query's plan,
            # so a "change" there is noise by construction.
            low = s.lower()
            refs[label] = {t for t in TABLES if re.search(rf"\b{t}\b", low)}
            k += 1
    return "\n".join(lines) + "\n", labels, refs


def run_sql(container, script, timeout=1800):
    p = subprocess.run(
        ["docker", "exec", "-i", container, "sh", "-c",
         f"mariadb --socket={SOCK} -u root -B -N --unbuffered tpcds"],
        input=script, capture_output=True, text=True, timeout=timeout)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip()[:2000])
    return p.stdout


def parse_plans(out, labels):
    """Cut the batch output back into {label: plan}."""
    plans, cur, buf = {}, None, []
    for line in out.splitlines():
        m = re.match(r"^@@(\S+)$", line.strip())
        if m:
            if cur:
                plans[cur] = "\n".join(buf)
            cur, buf = m.group(1), []
            continue
        if cur:
            buf.append(line)
    if cur:
        plans[cur] = "\n".join(buf)
    missing = [l for l in labels if l not in plans]
    if missing:
        raise RuntimeError(f"no plan captured for {missing[:5]} ({len(missing)} total)")
    return plans


def write_out(path, results):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as fh:
        fh.write("table\tindex\tmb\trows_read\tverdict\tplans_changed\tnoisy_statements\n")
        for tbl, idx, mb, read, verdict, moved, noisy in results:
            fh.write(f"{tbl}\t{idx}\t{mb}\t{read}\t{verdict}\t"
                     f"{','.join(moved)}\t{noisy}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--container", required=True)
    ap.add_argument("--queries", default=f"{REPO}/queries/tuned")
    ap.add_argument("--out", default=f"{REPO}/analysis/plan-sensitivity.tsv")
    ap.add_argument("--only", help="comma-separated index names, for a quick check")
    ap.add_argument("--reps", type=int, default=3,
                    help="replicates per index; 1 is not enough -- re-sampling "
                         "noise alone moved 19 of 44 plans on catalog_sales")
    ap.add_argument("--unread-only", action="store_true",
                    help="only test indexes no measured run read; the ones "
                         "that were read are kept regardless")
    ap.add_argument("--resume", action="store_true",
                    help="keep rows already present in --out and measure the rest")
    ap.add_argument("--usage", action="append", default=[],
                    help="index-usage-sf<N>.tsv from a real benchmark run; "
                         "repeatable, and an index read at ANY scale counts as "
                         "used.  The live counters are near zero under "
                         "SKIP_BENCH=1, so pass the measured files instead.")
    a = ap.parse_args()

    script, labels, refs = build_plan_script(a.queries)
    print(f"  {len(labels)} statements across "
          f"{len({l.split('#')[0] for l in labels})} queries")

    # Everything visible first: a candidate that is already IGNORED would
    # otherwise be measured against a baseline that already excludes it.
    # Only touch the ones that are actually ignored -- ALTER INDEX is
    # metadata-only but still commits a table alter, about a second each on
    # this host, so replaying all 129 unconditionally cost two minutes of
    # nothing on every invocation.
    stale = run_sql(a.container, """
SELECT DISTINCT TABLE_NAME, INDEX_NAME FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA='tpcds' AND IGNORED='YES';""").split()
    if stale:
        pairs = list(zip(stale[0::2], stale[1::2]))
        print(f"  clearing {len(pairs)} leftover IGNORED indexes")
        run_sql(a.container, "\n".join(
            f"ALTER TABLE {t} ALTER INDEX {i} NOT IGNORED;" for t, i in pairs))

    t0 = time.time()
    parse_plans(run_sql(a.container, script), labels)   # warm the caches
    print(f"  one plan capture takes {time.time()-t0:.1f}s; "
          f"{a.reps} replicates per index "
          f"({2 * a.reps} captures, {2 * a.reps} ALTERs)")

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
    # Read counts come from the measured runs, not from this server: under
    # SKIP_BENCH=1 nothing has executed, so the live counters are all zero.
    # An index read at ANY scale factor counts as used -- the point is not to
    # hurt a query that only needs it at one size.
    measured = {}
    for path in a.usage:
        for line in open(path):
            f = line.rstrip("\n").split("\t")
            if len(f) >= 4 and f[3].isdigit():
                k = (f[0], f[1])
                measured[k] = max(measured.get(k, 0), int(f[3]))
    if a.usage:
        print(f"  read counts from {len(a.usage)} measured run(s), "
              f"{sum(1 for v in measured.values() if v)} indexes read somewhere")

    cands = []
    for line in rows.splitlines():
        f = line.split("\t")
        if len(f) == 4:
            read = measured.get((f[0], f[1]), int(f[3])) if a.usage else int(f[3])
            cands.append((f[0], f[1], float(f[2]), read))
    if a.unread_only:
        cands = [c for c in cands if c[3] == 0]
    if a.only:
        want = {x.strip() for x in a.only.split(",")}
        cands = [c for c in cands if c[1] in want]
    print(f"  {len(cands)} secondary indexes to test")

    results, done = [], {}
    if a.resume and os.path.exists(a.out):
        for line in list(open(a.out))[1:]:
            f = line.rstrip("\n").split("\t")
            if len(f) >= 7:
                done[(f[0], f[1])] = (f[0], f[1], float(f[2]), int(f[3]), f[4],
                                      [x for x in f[5].split(",") if x],
                                      int(f[6]))
        print(f"  resuming: {len(done)} indexes already measured")

    for i, (tbl, idx, mb, read) in enumerate(cands, 1):
        if (tbl, idx) in done:
            results.append(done[(tbl, idx)])
            continue
        # Replicated and paired.  Each capture is taken immediately after an
        # ALTER on this table, so both states carry the same re-sampling
        # disturbance; only a difference that survives every replicate counts.
        H, V = [], []
        try:
            for _ in range(a.reps):
                run_sql(a.container, f"ALTER TABLE {tbl} ALTER INDEX {idx} IGNORED;")
                H.append(parse_plans(run_sql(a.container, script), labels))
                run_sql(a.container, f"ALTER TABLE {tbl} ALTER INDEX {idx} NOT IGNORED;")
                V.append(parse_plans(run_sql(a.container, script), labels))
        finally:
            # Never leave an index hidden behind us, even on an exception.
            run_sql(a.container, f"ALTER TABLE {tbl} ALTER INDEX {idx} NOT IGNORED;")

        stable = [l for l in labels
                  if all(h[l] == H[0][l] for h in H)
                  and all(v[l] == V[0][l] for v in V)]
        noisy = len(labels) - len(stable)
        moved = sorted({l.split("#")[0] for l in stable
                        if H[0][l] != V[0][l] and tbl in refs[l]})
        verdict = ("used" if read > 0 else "consulted" if moved else "dead")
        results.append((tbl, idx, mb, read, verdict, moved, noisy))
        print(f"  [{i:3d}/{len(cands)}] {idx:<34} {mb:8.1f} MB  "
              f"read={read:<11} noise={noisy:<3} {verdict:<9} "
              f"{','.join(moved) or '-'}")
        write_out(a.out, results)

    write_out(a.out, results)
    dead = [r for r in results if r[4] == "dead"]
    print(f"\n  wrote {a.out}")
    for v in ("used", "consulted", "dead"):
        sel = [r for r in results if r[4] == v]
        print(f"    {v:<10} {len(sel):3d} indexes, {sum(r[2] for r in sel)/1024:6.2f} GB")
    if dead:
        print(f"\n  largest droppable:")
        for r in sorted(dead, key=lambda r: -r[2])[:15]:
            print(f"    {r[1]:<36} {r[2]:8.1f} MB  on {r[0]}")


if __name__ == "__main__":
    main()
