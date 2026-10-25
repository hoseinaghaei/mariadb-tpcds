#!/usr/bin/env python3
"""One-off: lift the per-query prose out of report/25-query-by-query.md into
report/25-notes.json, and apply the entries that have gone stale.

Report 25 was written at commit 3996a15, before Nafiz's ten queries were
wired in (942fa2f), before q68/q46 were optimized (808ae93), and before the
remaining eleven were rewritten.  Twenty of its forty sections now say "Not
optimized. No optimized version exists." about a query that has one.

Rather than patch it again -- and have it drift again the next time the suite
is re-run -- the prose moves into a data file and `gen-25.py` renders the
report from that plus the measured timings.  Ranks, times and totals then
come from the run rather than from whoever last edited the markdown.

Run once.  After that, edit 25-notes.json (or this file's OVERRIDES and
re-run) rather than the generated markdown.
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
OLD = f"{HERE}/25-query-by-query.md"
OUT = f"{HERE}/25-notes.json"

# ---------------------------------------------------------------------------
# Replacements.  Each is (author, body).  author is what goes in the table's
# "optimized by" column; "" means the TPC-DS original is still what runs.
# ---------------------------------------------------------------------------
OVERRIDES = {
    # --- the eleven that had nothing, rewritten and measured in this pass ---
    23: ("Claude", """**Optimized by Claude** — `queries/optimized/q23-sf4/query23_v3_densekeys.sql`

Was the most expensive query in the suite by a factor of three. `ANALYZE FORMAT=JSON` showed its `frequent_ss_items` CTE being split-materialised **55,882 times** in one branch and 28,222 in the other — 99.1s of the 208.1s the query spent under instrumentation.

`split_materialized=off` was the wrong lever and had already measured +54.0s *slower*: materialising that CTE once meant grouping four years of `store_sales` on a 30-character varchar. The fix was to make the CTE cheap instead — drop the `item` join (its `substr(i_item_desc,1,30)` is functionally dependent on the unique `i_item_sk`, so it splits no group), swap `d_date` for `d_date_sk`, and order the GROUP BY to match `idx_ss_date_item_store_cover`.

Verified at SF=4: original 160.7s → 44.7s, **3.60x**, output byte-for-byte identical. The three CTEs were checked individually as well, since q23 returns a NULL and no rows at this scale and the final answer alone proves nothing. See `report/26-the-last-eleven.md`."""),

    70: ("Claude", """**Optimized by Claude** — `queries/optimized/q70-sf4/query70_v1_nosubquery.sql`

Its `s_state in (...)` subquery looks like a top-5 filter and removes nothing: it groups by `s_state` and then partitions by `s_state`, so every partition holds one row, `rank()` is 1 everywhere and `ranking <= 5` admits all of them. Establishing that cost a second full pass over a 12-month window of `store_sales`. Deleting it preserves the answer exactly — this is a quirk of the published TPC-DS text, not a transcription error.

Also aggregates on `ss_store_sk` and joins `store` afterwards, so 2.3M rows are grouped on an integer rather than two varchars.

Verified at SF=4: original 11.6s → 3.6s, **3.22x**, output byte-for-byte identical."""),

    82: ("Claude", """**Optimized by Claude** — `queries/optimized/q82-sf4/query82_v1_exists.sql`

Groups by three item columns with no aggregate in the select list, which makes it a DISTINCT: the join multiplicity against `inventory` and `store_sales` is built at full cost and thrown away. Both joins are existence tests, so `EXISTS` is exact rather than approximate, and with the date filter reduced to a key range both subqueries become index-only (`idx_inv_item_date_sk`, `idx_ss_item_sk`).

Verified at SF=4: original 0.8s → 0.1s, **8.00x** — the largest ratio in the suite — on consistent passes, output byte-for-byte identical."""),

    35: ("Claude", """**Optimized by Claude** — `queries/optimized/q35-sf4/query35_v1_keydate.sql`

Aysha's file for this query contained only `CREATE INDEX` statements, so there was no query to substitute; her indexes are in `sql/14_contributed_indexes.sql`.

The rewrite replaces the `date_dim` join inside each of the three `EXISTS` subqueries with a range on the fact table's own foreign key. That leaves each subquery naming exactly two columns, both carried in order by an existing index (`idx_ss_cust_date`, `idx_cs_cust_date`, `idx_ws_cust_date`), so all three existence checks become index-only probes.

Verified at SF=4: original 1.7s → 1.3s, **1.31x** (2.4x on a cold pass), output byte-for-byte identical."""),

    38: ("", """**Not optimized.** Aysha's file contains only `CREATE INDEX` statements, so there is no query to substitute; its indexes are in `sql/14_contributed_indexes.sql`.

A rewrite was written and measured — intersecting on `d_date_sk` instead of `d_date`, which is exact because the two are a bijection on `date_dim` — and it was **0.80x, slower**. The per-row `date_dim` probes it removes are not where q38 spends its time; the cost is building and intersecting three large `DISTINCT` sets keyed on two name columns. Kept with its measurements in `queries/optimized/q38-sf4/`."""),

    87: ("", """**Not optimized.** The same rewrite as q38 — `EXCEPT` in place of `INTERSECT` — was written and measured at **0.80x, slower**, on all three passes.

That the two queries share a shape and regressed by the same factor is what makes the result trustworthy rather than noise. Kept in `queries/optimized/q87-sf4/`."""),

    77: ("", """**Not optimized.** A rewrite replacing all six `date_dim` joins with key ranges was measured at **0.73x on best-of-3**, with means of 6.8s against 7.0s — a wash inside very large variance (the original spanned 3.3–11.9s over three passes).

The real cost is elsewhere: the plan reaches `store_sales` through `idx_ss_date_cust`, which carries neither `ss_store_sk` nor the two profit columns, so every qualifying row costs a base-table fetch. A covering index would fix it, but no DDL was possible under the read-only analysis policy, and adding indexes to this schema has backfired before. Kept in `queries/optimized/q77-sf4/`."""),

    66: ("", """**Not optimized.** Two rewrites were measured. Aggregating on `ws_warehouse_sk`/`cs_warehouse_sk` and joining `warehouse` afterwards is **1.01x** — a dead heat, because the inner aggregation produces about one group per warehouse and narrowing a GROUP BY key pays in proportion to the number of groups, not rows.

Adding a redundant date range on top of that made it **0.91x, slower**. That predicate is genuinely redundant — every row it admits the join already admitted — so it reads like a free hint, and it is not. Kept in `queries/optimized/q66-sf4/`."""),

    71: ("", """**Not optimized.** Replacing the three `date_dim` joins with key ranges measured **0.77x, slower**. The cost is the full scan of `item` to apply `i_manager_id = 1` — there is no index on that column — and the three-way union feeding a filesort; neither is touched.

Separately, this query's **output order is not deterministic**: `order by ext_price desc, i_brand_id` is not a total order, and 3,948 result rows collapse to 3,934 distinct sort keys, leaving 24 rows free to permute. A byte-for-byte diff of q71 can therefore report a difference between two correct runs, which is why the suite hashes both `md5` and `md5_sorted`. Kept in `queries/optimized/q71-sf4/`."""),

    65: ("", """**Not optimized.** q65 spells the same derived table out twice, so naming it once as a CTE looked like a free halving. It measured **0.97x** — no change — because MariaDB already recognises the two spellings as one derived table and materialises it once. Kept in `queries/optimized/q65-sf4/`."""),

    58: ("", """**Not optimized.** A rewrite resolving the week of 1998-03-14 to a key range at authoring time — replacing a join, an `IN` subquery and a scalar subquery over `date_dim`, three times over — measured **1.00x**. At 0.6s warm there was nothing to recover. Kept as a verified-equivalent alternative in `queries/optimized/q58-sf4/`."""),

    # --- Claude's first pass over the unoptimized set (commit 808ae93) ---
    68: ("Claude", """**Optimized by Claude** — `queries/optimized/q68-sf4/query68_v1_datefirst.sql`

`STRAIGHT_JOIN` from `date_dim` so the selective date filter drives the join instead of the plan scanning `store_sales` and probing the dimension per row.

Verified at SF=4: 12, 11, 11s → 2, 3, 2s, **4.9x**, output identical."""),

    46: ("Claude", """**Optimized by Claude** — `queries/optimized/q46-sf4/query46_v1_datefirst.sql`

The same defect and the same fix as q68. Less headroom because q46's date predicate is less selective — the gain comes from the predicate, not from `STRAIGHT_JOIN` itself.

Verified at SF=4: 13, 12, 12s → 7, 6, 6s, **1.9x**, output identical."""),

    # --- Nafiz, merged at 942fa2f ---
    7:  ("Nafiz", "**Optimized by Nafiz** — `queries/optimized/Nafiz/tier4/q7/query7_BEST.sql`"),
    8:  ("Nafiz", "**Optimized by Nafiz** — `queries/optimized/Nafiz/tier4/q8/query8_BEST.sql`"),
    10: ("Nafiz", "**Optimized by Nafiz** — `queries/optimized/Nafiz/tier4/q10/query10_BEST.sql`"),
    33: ("Nafiz", "**Optimized by Nafiz** — `queries/optimized/Nafiz/tier4/q33/query33_BEST.sql`"),
    37: ("Nafiz", "**Optimized by Nafiz** — `queries/optimized/Nafiz/tier4/q37/query37_BEST.sql`"),
    11: ("Nafiz", "**Optimized by Nafiz** — `queries/optimized/Nafiz/tier5/q11/query11_BEST.sql`"),
    57: ("Nafiz", "**Optimized by Nafiz** — `queries/optimized/Nafiz/tier5/q57/query57_BEST.sql`"),
    74: ("Nafiz", "**Optimized by Nafiz** — `queries/optimized/Nafiz/tier5/q74/query74_BEST.sql`"),
}

# Nafiz's eight arrived with a UTF-8 BOM that broke three of them; they were
# wired in and verified at 942fa2f but never timed individually against the
# original, so no speedup is quoted for them here.
NAFIZ_CAVEAT = ("\n\nWired in and verified identical at commit 942fa2f. No "
                "individual before/after timing was taken, so no speedup is "
                "quoted; its contribution shows in the suite total.")


def main():
    text = open(OLD).read()
    notes = {}
    # "### 14. q77 — 13.0s at SF=4, 0.5s at SF=1\n\n<body>"
    chunks = re.split(r'\n### \d+\. q(\d+) — [^\n]*\n', text)
    for i in range(1, len(chunks), 2):
        q = int(chunks[i])
        body = chunks[i + 1].split('\n## ')[0].strip()
        notes[q] = {"author": "", "body": body}
        m = re.search(r'\*\*Optimized by (\w+)\*\*', body)
        if m:
            notes[q]["author"] = m.group(1)

    print(f"  lifted {len(notes)} sections from {os.path.basename(OLD)}")

    for q, (author, body) in OVERRIDES.items():
        if q in (7, 8, 10, 11, 33, 37, 57, 74):
            body += NAFIZ_CAVEAT
        was = notes.get(q, {}).get("author", "")
        notes[q] = {"author": author, "body": body}
        print(f"    q{q:<3} {was or '(none)':>8} -> {author or '(none)'}")

    json.dump({str(q): notes[q] for q in sorted(notes)},
              open(OUT, 'w'), indent=1)
    print(f"  wrote {OUT}: {len(notes)} queries, "
          f"{sum(1 for n in notes.values() if n['author'])} attributed")


if __name__ == '__main__':
    main()
