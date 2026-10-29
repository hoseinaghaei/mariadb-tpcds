#!/usr/bin/env python3
"""Test a GROUP of drop candidates together, largest first.

    python3 scripts/index-group-test.py --container tpcds-run-1 --top 20

Testing indexes one at a time answers "does removing this one change a
plan?".  It does not answer "does removing all of them change a plan?", and
that is the question, because two indexes can cover for each other: hide
either alone and the optimizer still has the other, hide both and the plan
moves.

So candidates are taken in descending size order and hidden TOGETHER, with
per-statement IGNORE INDEX hints applied to every reference to each
affected table.  Hints rather than ALTER INDEX because ALTER re-samples the
whole table's statistics and flips unrelated plans -- see report/29.

Two stages, cheap one first:

  1. EXPLAIN all 44 statements with the whole group hinted away.  Report
     every statement whose chosen key moves.
  2. If nothing moved, time the full query set both ways to confirm, and
     compare answer checksums.

A group that moves no plan cannot change execution time; all it can change
is the storage, the maintenance on every load, and the build time.
"""
import argparse, hashlib, importlib.util, os, re, subprocess, sys, time

sys.stdout.reconfigure(line_buffering=True)
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOCK = "/data/mysql.sock"
_spec = importlib.util.spec_from_file_location(
    "harm", f"{REPO}/scripts/index-harm-scan.py")
_h = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_h)
run, chosen_keys, explain_of = _h.run, _h.chosen_keys, _h.explain_of
add_hint = _h.add_hint


def hint_all(sql, by_table):
    """Hide every candidate index, per table, from one statement."""
    for tbl, idxs in by_table.items():
        sql = add_hint(sql, tbl, idxs)[0]
    return sql


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--container", required=True)
    ap.add_argument("--consulted", default=f"{REPO}/analysis/index-consulted-sf4.tsv")
    ap.add_argument("--harm", default=f"{REPO}/analysis/index-harm-sf4.tsv")
    ap.add_argument("--queries", default=f"{REPO}/queries/tuned")
    ap.add_argument("--top", type=int, default=0,
                    help="test only the N largest candidates (0 = all)")
    ap.add_argument("--time", action="store_true",
                    help="also time the whole query set both ways")
    a = ap.parse_args()

    # Candidates: never mentioned in any plan, or mentioned but proven not to
    # move one.  Anything whose removal moves a plan is excluded here and
    # handled by index-harm-scan.py, which times it.
    keep_out = set()
    if os.path.exists(a.harm):
        for line in list(open(a.harm))[1:]:
            f = line.rstrip("\n").split("\t")
            if len(f) >= 7:
                keep_out.add(f[1])          # every mover, whatever its verdict
    cands = []
    for line in list(open(a.consulted))[1:]:
        f = line.rstrip("\n").split("\t")
        if len(f) >= 6 and f[4] in ("unreferenced", "considered") and f[1] not in keep_out:
            cands.append((f[0], f[1], float(f[2])))
    cands.sort(key=lambda c: -c[2])
    if a.top:
        cands = cands[:a.top]
    by_table = {}
    for tbl, idx, _ in cands:
        by_table.setdefault(tbl, set()).add(idx)
    print(f"  {len(cands)} candidates, {sum(c[2] for c in cands)/1024:.2f} GB, "
          f"across {len(by_table)} tables")
    print(f"  largest: " + ", ".join(f"{c[1]} ({c[2]:.0f}MB)" for c in cands[:5]))

    names = sorted(f for f in os.listdir(a.queries) if f.endswith(".sql"))
    moved = []
    print(f"\n  stage 1: EXPLAIN {len(names)} queries with the group hidden")
    for fn in names:
        q = fn[:-4]
        sql = open(f"{a.queries}/{fn}").read()
        base = chosen_keys(run(a.container, explain_of(sql))[1])
        hid = chosen_keys(run(a.container, explain_of(hint_all(sql, by_table)))[1])
        if base != hid:
            moved.append(q)
            print(f"    {q:<10} PLAN MOVES")
            print(f"      with:    {base[:150]}")
            print(f"      without: {hid[:150]}")
    if not moved:
        print(f"    no plan moves in any of {len(names)} queries")

    if not a.time:
        return
    print(f"\n  stage 2: timing the full set both ways")
    for label, transform in (("as-is", lambda s: s),
                             ("group hidden", lambda s: hint_all(s, by_table))):
        tot = 0.0
        sums = []
        for fn in names:
            sql = transform(open(f"{a.queries}/{fn}").read())
            el, out = run(a.container, sql, timeout=3600)
            tot += el
            sums.append(hashlib.md5(out.encode()).hexdigest()[:6])
        print(f"    {label:<14} {tot:7.1f}s   answers {hashlib.md5(''.join(sums).encode()).hexdigest()[:8]}")


if __name__ == "__main__":
    main()
