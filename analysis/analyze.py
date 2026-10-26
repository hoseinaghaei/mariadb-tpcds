#!/usr/bin/env python3
"""Compare benchmark runs across scale factors and environments.

    python3 analysis/analyze.py            # everything it can find
    python3 analysis/analyze.py --open     # and open the HTML report

Reads whatever ./run-scales.sh and pagesize/run-scales-mac.sh have produced
and writes:

    analysis/results.csv    one row per query per run, for your own analysis
    analysis/report.md      the same findings as text
    analysis/report.html    with charts, openable offline

WHAT IT LOOKS FOR, and why each one is worth flagging:

  ANSWER MISMATCH   Two environments at the SAME scale factor returned
                    different answers.  This is a defect, not a performance
                    observation, and it is listed first because nothing else
                    on the page means anything if it fires.  (Across
                    DIFFERENT scale factors answers differ legitimately --
                    dsdgen builds a different database at each scale -- so
                    that comparison is never made.)
  ERROR             The query did not complete.
  SUPER-LINEAR      Time grew faster than the data did.  Four times the data
                    taking more than ~6x the time usually means a working set
                    that stopped fitting in the buffer pool, or a plan that
                    changed for the worse once the statistics moved.
  SUB-LINEAR        Four times the data taking less than ~2x the time.  Often
                    a query whose cost is dominated by something that does not
                    scale, but sometimes a sign the query is not doing the
                    work you think it is -- check the row count.
  NON-MONOTONIC     Slower at a smaller scale factor than a larger one.  On a
                    quiet machine this should not happen; it usually means the
                    measurement was disturbed.
  ENVIRONMENT GAP   The same query at the same scale differs by a large factor
                    between macOS and the container.  Expected to some degree
                    -- O_DIRECT works on Linux and does nothing on macOS -- but
                    a big outlier is worth a look.
  DOMINATES         One query is a large share of a run's total.  Not a fault,
                    but it is where optimization effort pays.
  EMPTY             Returned no rows.  The query ran, but at this scale the
                    answer set is empty, so it is not really exercising
                    anything.  q8, q54 and q23 do this at SF=4.

Thresholds are the constants below; they are deliberately loose, because this
host has shown 16-34% run-to-run variation on identical configurations and a
tighter rule would report noise as findings.
"""
import json, os, sys, csv, statistics, datetime, webbrowser

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from collect import collect                      # noqa: E402
import charts                                    # noqa: E402

SUPERLINEAR = 1.5      # time ratio / data ratio above this
SUBLINEAR = 0.5        # ... and below this
NONMONOTONIC = 0.80    # a later scale this much faster than an earlier one
ENV_GAP = 3.0          # factor between environments at the same scale
DOMINATES = 0.10       # share of a run's total
FLOOR = 0.5            # ignore queries faster than this; ratios are noise


def fmt(v, suffix="s"):
    return "—" if v is None else f"{v:,.1f}{suffix}"


def build(rows):
    runs = {}
    for r in rows:
        runs.setdefault((r["environment"], r["scale"]), {})[r["query"]] = r
    return runs


def totals(runs):
    out = {}
    for k, qs in runs.items():
        out[k] = {
            "seconds": sum(q["seconds"] or 0 for q in qs.values()),
            "queries": len(qs),
            "errors": sum(1 for q in qs.values() if q["status"] != "OK"),
        }
    return out


def find_anomalies(runs, tot):
    a = []

    # --- correctness first -------------------------------------------------
    #
    # A scale factor does NOT identify a database -- (scale, seed) does.
    # dsdgen with a different -RNGSEED builds different data at the same
    # scale, and then every answer differs legitimately.  That is not a
    # hypothetical: the macOS SF=4 dataset here was generated with
    # `dsdgen -SCALE 4` and no seed (report/21), while the container uses
    # seed 10, and comparing them reported 37 "mismatches" that were nothing
    # of the kind.
    #
    # The runs do not all record their seed, so it is inferred from the data
    # instead: if several queries return DIFFERENT ROW COUNTS, the databases
    # differ, and no per-query answer comparison between them means anything.
    # One differing row count could be a genuine bug; several cannot be.
    scales = sorted({s for _, s in runs})
    for s in scales:
        envs = sorted(e for e, sc in runs if sc == s)
        if len(envs) < 2:
            continue
        qs = sorted(set().union(*[set(runs[(e, s)]) for e in envs]))

        differing_rows = [q for q in qs
                          if len({runs[(e, s)][q]["rows"] for e in envs
                                  if q in runs[(e, s)]
                                  and runs[(e, s)][q]["status"] == "OK"}) > 1]
        if len(differing_rows) > 1:
            a.append(("DIFFERENT DATASET", "—",
                      f"SF={s}: {' and '.join(envs)} disagree on the row count for "
                      f"{len(differing_rows)} queries "
                      f"({', '.join('q%d' % q for q in differing_rows[:6])}"
                      f"{', ...' if len(differing_rows) > 6 else ''}). "
                      f"These are different databases -- almost certainly a "
                      f"different dsdgen -RNGSEED -- so their answers are not "
                      f"comparable and no per-query check was made. Timings "
                      f"remain broadly indicative.", "critical"))
            continue      # answers are meaningless; do not flag them one by one

        for q in qs:
            hashes = {}
            for e in envs:
                rec = runs[(e, s)].get(q)
                if rec and rec["status"] == "OK" and rec["md5_sorted"]:
                    hashes[e] = rec["md5_sorted"]
            if len(set(hashes.values())) > 1:
                detail = ", ".join(f"{e} rows={runs[(e,s)][q]['rows']}" for e in hashes)
                a.append(("ANSWER MISMATCH", q, f"SF={s}: {detail}", "critical"))

    for (e, s), qs in sorted(runs.items()):
        for q, rec in sorted(qs.items()):
            if rec["status"] != "OK":
                a.append(("ERROR", q, f"{e} SF={s}: {rec['status']}", "critical"))

    # --- scaling, per environment -----------------------------------------
    for env in sorted({e for e, _ in runs}):
        ss = sorted(s for e, s in runs if e == env)
        if len(ss) < 2:
            continue
        lo, hi = ss[0], ss[-1]
        data_ratio = hi / lo
        for q in sorted(set(runs[(env, lo)]) & set(runs[(env, hi)])):
            a_s = runs[(env, lo)][q]["seconds"]
            b_s = runs[(env, hi)][q]["seconds"]
            if not a_s or not b_s or a_s < FLOOR:
                continue
            ratio = b_s / a_s
            rel = ratio / data_ratio
            if rel > SUPERLINEAR:
                a.append(("SUPER-LINEAR", q,
                          f"{env}: {fmt(a_s)} at SF={lo} -> {fmt(b_s)} at SF={hi} "
                          f"= {ratio:.1f}x for {data_ratio:g}x the data", "warn"))
            elif rel < SUBLINEAR:
                a.append(("SUB-LINEAR", q,
                          f"{env}: {fmt(a_s)} at SF={lo} -> {fmt(b_s)} at SF={hi} "
                          f"= {ratio:.1f}x for {data_ratio:g}x the data", "info"))
            for i in range(len(ss) - 1):
                x, y = runs[(env, ss[i])][q]["seconds"], runs[(env, ss[i + 1])][q]["seconds"]
                if x and y and x > FLOOR and y < x * NONMONOTONIC:
                    a.append(("NON-MONOTONIC", q,
                              f"{env}: {fmt(x)} at SF={ss[i]} but {fmt(y)} at SF={ss[i+1]}",
                              "warn"))

    # --- environment gap at equal scale -----------------------------------
    for s in scales:
        envs = sorted(e for e, sc in runs if sc == s)
        if len(envs) < 2:
            continue
        for q in sorted(set().union(*[set(runs[(e, s)]) for e in envs])):
            vals = {e: runs[(e, s)][q]["seconds"] for e in envs
                    if q in runs[(e, s)] and runs[(e, s)][q]["seconds"]}
            vals = {e: v for e, v in vals.items() if v and v >= FLOOR}
            if len(vals) < 2:
                continue
            slow = max(vals, key=vals.get); fast = min(vals, key=vals.get)
            if vals[slow] / vals[fast] >= ENV_GAP:
                a.append(("ENVIRONMENT GAP", q,
                          f"SF={s}: {fast} {fmt(vals[fast])} vs {slow} {fmt(vals[slow])} "
                          f"= {vals[slow]/vals[fast]:.1f}x", "info"))

    # --- shape of the workload --------------------------------------------
    for (e, s), qs in sorted(runs.items()):
        T = tot[(e, s)]["seconds"] or 1
        for q, rec in sorted(qs.items()):
            if rec["seconds"] and rec["seconds"] / T >= DOMINATES:
                a.append(("DOMINATES", q,
                          f"{e} SF={s}: {fmt(rec['seconds'])}, "
                          f"{rec['seconds']/T*100:.0f}% of the run", "info"))
            if rec["status"] == "OK" and rec["rows"] == 0:
                a.append(("EMPTY", q, f"{e} SF={s}: returned no rows", "info"))
    return a


def report(runs, tot, anoms):
    envs = sorted({e for e, _ in runs})
    scales = sorted({s for _, s in runs})
    allq = sorted(set().union(*[set(v) for v in runs.values()])) if runs else []

    md = ["# Benchmark results across scale factors",
          "",
          f"Generated {datetime.datetime.now():%Y-%m-%d %H:%M}. "
          f"{len(runs)} runs, {len(allq)} queries.", ""]

    md += ["## Totals", "",
           "| environment | scale | queries | errors | total |",
           "|---|---:|---:|---:|---:|"]
    for (e, s) in sorted(tot):
        t = tot[(e, s)]
        md.append(f"| {e} | {s} | {t['queries']} | {t['errors']} | {fmt(t['seconds'])} |")
    md.append("")

    # scaling table
    if len(scales) > 1:
        md += ["## Scaling", "",
               "Per-query response time at each scale factor.", ""]
        for e in envs:
            ss = [s for s in scales if (e, s) in runs]
            if len(ss) < 2:
                continue
            md += [f"### {e}", "",
                   "| query | " + " | ".join(f"SF={s}" for s in ss) +
                   f" | SF{ss[-1]}/SF{ss[0]} |",
                   "|---" * (len(ss) + 2) + "|"]
            for q in allq:
                cells = []
                for s in ss:
                    rec = runs[(e, s)].get(q)
                    cells.append(fmt(rec["seconds"]) if rec else "—")
                a_s = (runs[(e, ss[0])].get(q) or {}).get("seconds")
                b_s = (runs[(e, ss[-1])].get(q) or {}).get("seconds")
                r = f"{b_s/a_s:.1f}x" if a_s and b_s and a_s >= FLOOR else "—"
                md.append(f"| q{q} | " + " | ".join(cells) + f" | {r} |")
            md.append("")

    # environment comparison
    for s in scales:
        es = [e for e in envs if (e, s) in runs]
        if len(es) < 2:
            continue
        md += [f"## macOS against the container at SF={s}", "",
               "| query | " + " | ".join(es) + " | ratio |",
               "|---" * (len(es) + 2) + "|"]
        for q in allq:
            vals = [(runs[(e, s)].get(q) or {}).get("seconds") for e in es]
            # `is not None` and not a truth test: a query that measured 0.0s
            # really was measured, and treating it as missing would quietly
            # drop it.  The ratio is still undefined when the faster side is
            # zero, which is what the dash means here.
            got = [v for v in vals if v is not None]
            r = (f"{max(got)/min(got):.1f}x"
                 if len(got) == len(es) and min(got) > 0 else "—")
            md.append(f"| q{q} | " + " | ".join(fmt(v) for v in vals) + f" | {r} |")
        md.append("")

    md += ["## Flagged", ""]
    if not anoms:
        md += ["Nothing tripped the thresholds.", ""]
    else:
        for level in ("critical", "warn", "info"):
            got = [x for x in anoms if x[3] == level]
            if not got:
                continue
            md += [f"### {level}", "",
                   "| kind | query | detail |", "|---|---|---|"]
            for kind, q, detail, _ in got:
                md.append(f"| {kind} | q{q} | {detail} |")
            md.append("")

    # ---- charts ----------------------------------------------------------
    svgs = []
    groups = [f"SF={s}" for s in scales]
    series = envs
    vals = [[tot.get((e, s), {}).get("seconds") for s in scales] for e in envs]
    svgs.append(charts.grouped_bars(groups, series, vals,
                                    title="Total suite time", ylabel="seconds"))

    for e in envs:
        ss = [s for s in scales if (e, s) in runs]
        if len(ss) < 2:
            continue
        top = sorted(allq, key=lambda q: -((runs[(e, ss[-1])].get(q) or {}).get("seconds") or 0))[:8]
        line_series = [(f"q{q}", [(runs[(e, s)].get(q) or {}).get("seconds") for s in ss])
                       for q in top]
        svgs.append(charts.lines([f"SF={s}" for s in ss], line_series,
                                 title=f"{e}: the eight slowest queries as the data grows",
                                 ylabel="seconds (log)", logy=True))

    for s in scales:
        es = [e for e in envs if (e, s) in runs]
        if len(es) < 2:
            continue
        top = sorted(allq, key=lambda q: -((runs[(es[0], s)].get(q) or {}).get("seconds") or 0))[:14]
        vals = [[(runs[(e, s)].get(q) or {}).get("seconds") for q in top] for e in es]
        svgs.append(charts.grouped_bars([f"q{q}" for q in top], es, vals,
                                        title=f"Per query at SF={s}", ylabel="seconds"))

    return "\n".join(md), svgs


HTML = """<!doctype html><meta charset="utf-8"><title>TPC-DS results</title>
<style>
 body{{font:14px/1.55 system-ui,sans-serif;margin:0 auto;padding:28px 20px;max-width:900px;color:#1b1b1b}}
 h1{{font-size:24px;margin:0 0 4px}} h2{{font-size:18px;margin:30px 0 8px;border-bottom:1px solid #e3e3e3;padding-bottom:4px}}
 h3{{font-size:15px;margin:20px 0 6px}}
 table{{border-collapse:collapse;margin:10px 0;font-size:13px;width:100%}}
 th,td{{border:1px solid #e0e0e0;padding:4px 8px;text-align:right}}
 th:first-child,td:first-child{{text-align:left}} th{{background:#f6f6f6}}
 tr:nth-child(even) td{{background:#fbfbfb}}
 .critical td{{background:#fdecea!important}} .warn td{{background:#fff6e5!important}}
 figure{{margin:16px 0;overflow-x:auto}} .sub{{color:#666}}
 code{{background:#f3f3f3;padding:1px 4px;border-radius:3px}}
</style>
<h1>TPC-DS on MariaDB — results across scale factors</h1>
<p class="sub">{sub}</p>
{charts}
{body}
<p class="sub">Generated by <code>analysis/analyze.py</code>. Figures from a
single run each unless stated; this project has measured 16–34% run-to-run
variation on identical configurations, so treat ordering as more reliable
than any individual number.</p>
"""


def md_to_html(md):
    out, in_tbl = [], False
    for line in md.splitlines():
        if line.startswith("|"):
            cells = [c.strip() for c in line.strip("|").split("|")]
            if set("".join(cells)) <= set("-: "):
                continue
            tag = "th" if not in_tbl else "td"
            if not in_tbl:
                out.append("<table>")
                in_tbl = True
            cls = ""
            out.append(f'<tr class="{cls}">' + "".join(f"<{tag}>{c}</{tag}>" for c in cells) + "</tr>")
            continue
        if in_tbl:
            out.append("</table>")
            in_tbl = False
        if line.startswith("### "):
            out.append(f"<h3>{line[4:]}</h3>")
        elif line.startswith("## "):
            out.append(f"<h2>{line[3:]}</h2>")
        elif line.startswith("# "):
            continue
        elif line.strip():
            out.append(f"<p>{line}</p>")
    if in_tbl:
        out.append("</table>")
    return "\n".join(out)


def main():
    rows = collect(verbose=True)
    if not rows:
        sys.exit("no results found")
    with open(f"{HERE}/results.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)

    runs = build(rows)
    tot = totals(runs)
    anoms = find_anomalies(runs, tot)
    md, svgs = report(runs, tot, anoms)

    open(f"{HERE}/report.md", "w").write(md + "\n")
    sub = (f"{len(runs)} runs &middot; "
           + ", ".join(f"{e} SF={s}" for e, s in sorted(runs))
           + f" &middot; {datetime.datetime.now():%Y-%m-%d %H:%M}")
    html = HTML.format(sub=sub,
                       charts="".join(f"<figure>{s}</figure>" for s in svgs),
                       body=md_to_html(md))
    open(f"{HERE}/report.html", "w").write(html)

    print(f"\n  analysis/results.csv   {len(rows)} rows")
    print(f"  analysis/report.md")
    print(f"  analysis/report.html")
    crit = [a for a in anoms if a[3] == "critical"]
    warn = [a for a in anoms if a[3] == "warn"]
    print(f"\n  flagged: {len(crit)} critical, {len(warn)} warnings, "
          f"{len(anoms)-len(crit)-len(warn)} informational")
    for kind, q, detail, _ in crit[:10]:
        print(f"    !! {kind} q{q}: {detail}")
    if "--open" in sys.argv:
        webbrowser.open("file://" + f"{HERE}/report.html")


if __name__ == "__main__":
    main()
