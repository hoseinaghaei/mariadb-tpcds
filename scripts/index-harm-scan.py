#!/usr/bin/env python3
"""Find indexes that make the optimizer choose a WORSE plan.

    python3 scripts/index-harm-scan.py --container tpcds-run-1234

scripts/index-consulted.py splits indexes three ways: read while executing,
never read but weighed when costing, never mentioned at all.  That is not
enough.  An index can be weighed and push the optimizer towards a worse
plan than it would have chosen without it.

The worked case is idx_inv_date_sk on inventory, 1,030 MB, read by nothing
at either scale.  With it visible, query22 accesses inventory by PRIMARY and
takes 39.3s.  Hidden, the optimizer picks idx_inv_item_date_sk instead and
takes 10.3s -- same answer, 3.8x faster.  The index is not merely useless;
its presence mis-costs a choice between two OTHER access paths.

METHOD, in two stages so the expensive one runs rarely:

  1. EXPLAIN only.  For each index, re-EXPLAIN the queries that weigh it
     with IGNORE INDEX applied to its table.  If no chosen key moves, the
     index changes nothing and needs no timing.
  2. Time the survivors, best of two, and check the answer md5.

Index HINTS rather than ALTER INDEX ... IGNORED: a hint is per-statement, so
it perturbs nothing.  ALTER re-samples the whole table's statistics even
though it is a metadata-only change, and at this scale that alone flips
plans in unrelated queries -- see report/27.
"""
import argparse, hashlib, importlib.util, os, re, subprocess, sys, time

sys.stdout.reconfigure(line_buffering=True)
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOCK = "/data/mysql.sock"

_spec = importlib.util.spec_from_file_location(
    "plan_sensitivity", f"{REPO}/scripts/plan-sensitivity.py")
_ps = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ps)
split_statements = _ps.split_statements


def run(container, sql, timeout=1800):
    t0 = time.time()
    p = subprocess.run(["docker", "exec", "-i", container, "sh", "-c",
                        f"mariadb --socket={SOCK} -u root -B -N tpcds"],
                       input=sql, capture_output=True, text=True, timeout=timeout)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip()[:400])
    return time.time() - t0, p.stdout


def add_hint(sql, table, index):
    """Attach IGNORE INDEX to every FROM/JOIN reference to `table`.

    Skips `table.column` so column references are left alone, and skips a
    name already carrying a hint.
    """
    pat = rf"\b{table}\b(?!\s*\.)(?!\s+IGNORE)"
    return re.subn(pat, f"{table} IGNORE INDEX ({index})", sql)


def chosen_keys(out):
    """table:key for each row of a tabular EXPLAIN."""
    keys = []
    for line in out.splitlines():
        f = line.split("\t")
        if len(f) > 5 and f[5] not in ("NULL", ""):
            keys.append(f"{f[2]}:{f[5]}")
    return ",".join(keys)


def explain_of(sql):
    """EXPLAIN *every* statement, not just the first.

    query14, 23, 39 and 67 are two statements each -- TPC-DS asks for two
    result sets.  Prefixing only the first left the second to run for real,
    which turned the cheap EXPLAIN-only stage into a full benchmark: one
    part-B of query14 was observed executing for 58 seconds inside what was
    supposed to be a planning-only pass.
    """
    out = []
    for st in split_statements(sql):
        head = st.lstrip("( \n\t").upper()
        if head.startswith("SET "):
            out.append(st + ";")
        elif head.startswith("SELECT") or head.startswith("WITH"):
            out.append(f"EXPLAIN {st};")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--container", required=True)
    ap.add_argument("--consulted", default=f"{REPO}/analysis/index-consulted-sf4.tsv")
    ap.add_argument("--queries", default=f"{REPO}/queries/tuned")
    ap.add_argument("--out", default=f"{REPO}/analysis/index-harm-sf4.tsv")
    ap.add_argument("--min-mb", type=float, default=0.0,
                    help="skip indexes smaller than this (they are rarely worth a run)")
    a = ap.parse_args()

    cands = []
    for line in list(open(a.consulted))[1:]:
        f = line.rstrip("\n").split("\t")
        if len(f) >= 6 and f[4] == "considered" and float(f[2]) >= a.min_mb:
            cands.append((f[0], f[1], float(f[2]), [q for q in f[5].split(",") if q]))
    cands.sort(key=lambda c: -c[2])
    print(f"  {len(cands)} indexes weighed but never read, "
          f"{sum(c[2] for c in cands)/1024:.2f} GB")

    sqls = {q: open(f"{a.queries}/{q}.sql").read()
            for q in {q for c in cands for q in c[3]}}
    base_plan = {q: chosen_keys(run(a.container, explain_of(s))[1])
                 for q, s in sqls.items()}
    print(f"  baseline plans for {len(base_plan)} queries\n")

    print(f"  {'index':<34}{'MB':>8}  queries whose chosen key moves")
    movers = []
    for tbl, idx, mb, qs in cands:
        moved = []
        for q in qs:
            hinted, n = add_hint(sqls[q], tbl, idx)
            if not n:
                continue
            try:
                plan = chosen_keys(run(a.container, explain_of(hinted))[1])
            except RuntimeError:
                continue
            if plan and plan != base_plan[q]:
                moved.append(q)
        if moved:
            movers.append((tbl, idx, mb, moved))
            print(f"  {idx:<34}{mb:8.1f}  {','.join(moved)}")
    print(f"\n  {len(movers)} of {len(cands)} change a chosen key; timing those\n")

    results = []
    print(f"  {'index':<30}{'as-is':>9}{'hidden':>9}{'delta':>9}  verdict")
    for tbl, idx, mb, qs in movers:
        a_tot = b_tot = 0.0
        bad = False
        for q in qs:
            hinted, _ = add_hint(sqls[q], tbl, idx)
            ta = min(run(a.container, sqls[q])[0] for _ in range(2))
            _, oa = run(a.container, sqls[q])
            tb = min(run(a.container, hinted)[0] for _ in range(2))
            _, ob = run(a.container, hinted)
            if hashlib.md5(oa.encode()).digest() != hashlib.md5(ob.encode()).digest():
                bad = True
            a_tot += ta; b_tot += tb
        delta = (b_tot - a_tot) / a_tot * 100 if a_tot else 0
        verdict = ("ANSWER CHANGED" if bad else
                   "HARMFUL - drop it" if delta < -10 else
                   "helpful - keep" if delta > 10 else "neutral")
        results.append((tbl, idx, mb, qs, a_tot, b_tot, verdict))
        print(f"  {idx:<30}{a_tot:8.1f}s{b_tot:8.1f}s{delta:+8.0f}%  {verdict}")

    with open(a.out, "w") as fh:
        fh.write("table\tindex\tmb\tqueries\tas_is_s\thidden_s\tverdict\n")
        for tbl, idx, mb, qs, ta, tb, v in results:
            fh.write(f"{tbl}\t{idx}\t{mb}\t{','.join(qs)}\t{ta:.1f}\t{tb:.1f}\t{v}\n")
    harm = [r for r in results if r[6].startswith("HARMFUL")]
    print(f"\n  wrote {a.out}")
    print(f"  harmful: {len(harm)} indexes, {sum(r[2] for r in harm)/1024:.2f} GB, "
          f"{sum(r[4]-r[5] for r in harm):.1f}s to be gained")


if __name__ == "__main__":
    main()
