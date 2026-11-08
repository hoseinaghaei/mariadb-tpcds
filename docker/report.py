#!/usr/bin/env python3
"""Write the run's report: every query's time, and the total.

    python3 report.py <results-dir> <tag> <scale>

Runs INSIDE the container, at the end of the benchmark, so there is one
implementation rather than one per host OS.  The host wrapper only has to
start Docker.

Emits REPORT.md next to the results, plus report.csv for anyone who would
rather open it in a spreadsheet.
"""
import csv, glob, json, os, platform, sys, time


def main():
    res, tag, scale = sys.argv[1], sys.argv[2], sys.argv[3]
    d = os.path.join(res, tag)
    rows = []
    for p in sorted(glob.glob(f"{d}/query*.json")):
        j = json.load(open(p))
        rows.append(j)
    if not rows:
        print("  no query results, no report written")
        return
    rows.sort(key=lambda r: -(r.get("seconds") or 0))
    summ = {}
    sp = f"{d}/_summary.json"
    if os.path.exists(sp):
        summ = json.load(open(sp))
    total = sum(r.get("seconds") or 0 for r in rows)
    errs = [r for r in rows if r.get("status") != "OK"]

    L = [f"# TPC-DS on MariaDB — scale factor {scale}", ""]
    L.append(f"**{len(rows)} queries · {total:.1f}s total"
             + (f" · {len(errs)} errors**" if errs else " · no errors**"))
    L.append("")
    L.append("| | |")
    L.append("|---|---|")
    L.append(f"| scale factor | {scale} |")
    L.append(f"| data seed | {summ.get('rngseed', 10)} |")
    L.append(f"| query set | `queries/tuned/` — the 40 tier-4/5 queries |")
    if rows:
        L.append(f"| InnoDB page size | {rows[0].get('page_kb')} KiB |")
        # `indexes` counts every index including the 24 primary keys.
        L.append(f"| indexes (incl. primary keys) | {rows[0].get('indexes')} |")
        L.append(f"| statistics sample pages | {rows[0].get('sample_pages')} |")
    L.append(f"| generated | {time.strftime('%Y-%m-%d %H:%M:%S')} |")
    L.append(f"| container | {platform.platform()} |")
    L.append("")
    if errs:
        L.append("> **" + str(len(errs)) + " queries did not complete: "
                 + ", ".join(f"q{e['query']}" for e in errs)
                 + ".** The total below excludes nothing, so it is not "
                   "comparable to a clean run.\n")

    L.append("## Every query, slowest first\n")
    L.append("| # | query | seconds | share | rows | status |")
    L.append("|---|---|---:|---:|---:|---|")
    for i, r in enumerate(rows, 1):
        s = r.get("seconds")
        share = f"{s / total * 100:.1f}%" if total and s is not None else "—"
        L.append(f"| {i} | q{r['query']} | {s:.1f}s | {share} | "
                 f"{r.get('rows', '—')} | {r.get('status', '?')} |")
    L.append(f"| | **total** | **{total:.1f}s** | 100% | | |")
    L.append("")

    if len(rows) > 4:
        top = rows[:5]
        L.append(f"The five slowest account for "
                 f"**{sum(r['seconds'] for r in top) / total * 100:.0f}%** of the run: "
                 + ", ".join(f"q{r['query']} ({r['seconds']:.1f}s)" for r in top) + ".\n")

    L.append("## Reading these numbers\n")
    L.append("""Each query runs **once**, so a single figure carries whatever the buffer
pool happened to hold at that moment — a cold read can be three times the
warm one. The total averages that out and is the reliable part; an
individual row is not evidence on its own. To compare two configurations,
run each at least twice and treat differences smaller than the spread
between runs as unresolvable.

Answer checksums are recorded per query in `""" + tag + """/query*.json`
(`md5` and `md5_sorted`), so two runs can be checked for identical results
even when their timings differ.
""")

    out = os.path.join(res, "REPORT.md")
    open(out, "w").write("\n".join(L) + "\n")

    with open(os.path.join(res, "report.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["query", "seconds", "rows", "status", "md5_sorted"])
        for r in sorted(rows, key=lambda r: r["query"]):
            w.writerow([r["query"], f"{r.get('seconds', 0):.1f}", r.get("rows"),
                        r.get("status"), r.get("md5_sorted", "")])
        w.writerow(["TOTAL", f"{total:.1f}", "", "", ""])
    print(f"  wrote {out}")
    print(f"  wrote {os.path.join(res, 'report.csv')}")


if __name__ == "__main__":
    main()
