#!/usr/bin/env python3
"""Compare benchmark runs across scale factors and environments.

    python3 analysis/analyze.py            # the container runs (what to share)
    python3 analysis/analyze.py --all      # plus macOS and the pruned run
    python3 analysis/analyze.py --open     # and open the HTML report

Reads whatever ./run-scales.sh and pagesize/run-scales-mac.sh have produced
and writes:

    analysis/results.csv    one row per query per run, for your own analysis
    analysis/report.md      the same findings as text
    analysis/report.html    with charts, openable offline

WHAT IT LOOKS FOR, and why each one is worth flagging:

  ANSWER MISMATCH   Same scale, recorded data seed and hash format, different
                    saved answer hashes. Requires SQL/ordering review.
  ANSWER CHECK SKIPPED
                    Missing or incompatible seed/hash metadata. Legacy runs
                    remain readable; their hashes cannot verify new answers.
  TIMING PROTOCOL CHANGE
                    Runs use different timing protocols. Raw observations
                    remain visible, but cross-protocol ratios are suppressed.
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
from itertools import combinations

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from collect import collect, DEFAULT_ONLY        # noqa: E402
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


def answer_comparison_problem(a, b):
    seeds = [str(r.get('rngseed')) for r in (a, b)]
    if not all(s.isdecimal() for s in seeds):
        return 'data seed not recorded'
    if int(seeds[0]) != int(seeds[1]):
        return 'different data seeds'
    formats = [r.get('result_format') for r in (a, b)]
    if any(f in (None, '', 'legacy/unknown') for f in formats):
        return 'result hash format not recorded'
    if formats[0] != formats[1]:
        return 'different result hash formats'
    return None


def timing_compatible(a, b):
    # Historical observations stay usable with each other. A new protocol
    # must not be silently presented as comparable with an unlabelled run.
    return (a.get('timing_protocol') or 'legacy/unknown') == (b.get('timing_protocol') or 'legacy/unknown')


def find_anomalies(runs, tot):
    a = []

    # --- correctness first -------------------------------------------------
    #
    # Require declared metadata. Several different row counts can indicate
    # several SQL bugs; they cannot justify inferring a different data seed
    # and suppressing every correctness check.
    scales = sorted({s for _, s in runs})
    for s in scales:
        envs = sorted(e for e, sc in runs if sc == s)
        if len(envs) < 2:
            continue
        protocols = {r.get('timing_protocol') or 'legacy/unknown'
                     for e in envs for r in runs[(e, s)].values()}
        if len(protocols) > 1:
            a.append(("TIMING PROTOCOL CHANGE", "—",
                      f"SF={s}: {', '.join(sorted(protocols))}; cross-protocol environment ratios are suppressed.",
                      "warn"))
        for left, right in combinations(envs, 2):
            x, y = runs[(left, s)], runs[(right, s)]
            skipped = {}
            for q in sorted(set(x) & set(y)):
                r, t = x[q], y[q]
                if not all(v['status'] == 'OK' and v['md5_sorted'] for v in (r, t)):
                    continue
                problem = answer_comparison_problem(r, t)
                if problem:
                    skipped[problem] = skipped.get(problem, 0) + 1
                elif r['md5_sorted'] != t['md5_sorted']:
                    detail = f"{left} rows={r['rows']}, {right} rows={t['rows']}"
                    a.append(("ANSWER MISMATCH", q,
                              f"SF={s}: {detail}; saved hashes differ, SQL/ordering review required", "critical"))
            for reason, count in sorted(skipped.items()):
                a.append(("ANSWER CHECK SKIPPED", "—",
                          f"SF={s}: {left} versus {right}: {reason} ({count} shared queries).", "warn"))

    for (e, s), qs in sorted(runs.items()):
        for q, rec in sorted(qs.items()):
            if rec["status"] != "OK":
                a.append(("ERROR", q, f"{e} SF={s}: {rec['status']}", "critical"))

    # --- scaling, per environment -----------------------------------------
    for env in sorted({e for e, _ in runs}):
        ss = sorted(s for e, s in runs if e == env)
        if len(ss) < 2:
            continue
        protocols = {r.get('timing_protocol') or 'legacy/unknown'
                     for s in ss for r in runs[(env, s)].values()}
        if len(protocols) > 1:
            a.append(("TIMING PROTOCOL CHANGE", "—",
                      f"{env}: {', '.join(sorted(protocols))}; cross-protocol scaling ratios are suppressed. "
                      "Rerun the scales with the same harness for a comparable campaign.", "warn"))
        lo, hi = ss[0], ss[-1]
        data_ratio = hi / lo
        for q in sorted(set(runs[(env, lo)]) & set(runs[(env, hi)])):
            if not timing_compatible(runs[(env, lo)][q], runs[(env, hi)][q]):
                continue
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
                first = runs[(env, ss[i])].get(q)
                second = runs[(env, ss[i + 1])].get(q)
                if not first or not second or not timing_compatible(first, second):
                    continue
                x, y = first['seconds'], second['seconds']
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
            records = [runs[(e, s)][q] for e in envs if q in runs[(e, s)]]
            if any(not timing_compatible(x, y) for x, y in combinations(records, 2)):
                continue
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
           "| environment | scale | queries | errors | total | timing protocol |",
           "|---|---:|---:|---:|---:|---|"]
    for (e, s) in sorted(tot):
        t = tot[(e, s)]
        protocols = ', '.join(sorted({r.get('timing_protocol') or 'legacy/unknown'
                                      for r in runs[(e, s)].values()}))
        md.append(f"| {e} | {s} | {t['queries']} | {t['errors']} | {fmt(t['seconds'])} | {protocols} |")
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
                comparable = timing_compatible(runs[(e, ss[0])].get(q, {}), runs[(e, ss[-1])].get(q, {}))
                r = f"{b_s/a_s:.1f}x" if a_s and b_s and a_s >= FLOOR and comparable else "—"
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
            records = [(runs[(e, s)].get(q) or {}) for e in es]
            comparable = all(timing_compatible(x, y) for x, y in combinations(records, 2))
            r = (f"{max(got)/min(got):.1f}x"
                 if len(got) == len(es) and min(got) > 0 and comparable else "—")
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
    # Default to the canonical container runs.  --all adds the macOS runs and
    # the pruned experiment, which are useful to us and only confusing in a
    # document someone else has to read.
    everything = "--all" in sys.argv
    rows = collect(verbose=True, only=None if everything else DEFAULT_ONLY)
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
