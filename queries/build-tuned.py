#!/usr/bin/env python3
"""Generate queries/tuned/ — the tier-4/5 queries as we actually run them.

Each file is self-contained and uses, in order of preference:

  1. the team's optimized version of that query, where one exists
  2. otherwise the adapted TPC-DS original from queries/mariadb/

plus the settings that query needs: sql_mode always, and
split_materialized=off on the six queries measured to gain from it.

Tier 4 and 5 are the 40 expensive queries of the 99 and the only ones this
project compares.  The list is read from the generated tier files, not
hardcoded, so it follows a re-ranking.

On split_materialized: it is worth 12x on q59, which is structural (one of
q59's two CTE references was re-materialised 7,665 times).  Whether applying
it per query beats applying it globally is NOT established -- two interleaved
passes put per-query at +4.8% and -8.9% against global, so the two are
indistinguishable in total on this host.  It is set per query because the
per-query evidence is strong, not because the totals favour it.

Re-generate with:  python3 queries/build-tuned.py
"""
import os, re, glob

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = f"{REPO}/queries/mariadb"
OPT = f"{REPO}/queries/optimized"
DST = f"{REPO}/queries/tuned"

NOSPLIT = "SET SESSION optimizer_switch = 'split_materialized=off';"
# Every file sets this so it is correct run on its own.  TPC-DS concatenates
# with ANSI '||' in q5, q66, q80 and q84; without PIPES_AS_CONCAT MariaDB
# reads '||' as logical OR and those queries silently return the wrong rows --
# q5 gives 7 instead of 100.
SQLMODE = ("SET SESSION sql_mode = "
           "CONCAT(@@sql_mode, ',IGNORE_SPACE,PIPES_AS_CONCAT');")
PIPES = (5, 66, 80, 84)

# The team's chosen optimized source per query.  A list means the query has
# several statements and each part has its own file (q14 is two halves).
OPTIMIZED = {
    2:  "q2/query2_BEST.sql",
    4:  "q4/query4_BEST.sql",
    5:  "q5/query5_BEST.sql",
    14: ["Aysha/q14/Query-14-A/q14_A_Optimized.sql",
         "Aysha/q14/Query-14-B/Q14-B-Optimized.sql"],
    21: "Aysha/q21/query21_optimized.sql",
    22: "q22/query22_BEST.sql",
    27: "Aysha/q27/q27_Optimized.sql",
    31: "q31/query31_BEST.sql",
    39: "q39/query39_BEST.sql",
    43: "Aysha/q43/q43_Optimized.sql",
    47: "Aysha/q47/q47_Optimized_3secs.sql",
    51: "q51/query51_BEST.sql",
    54: "Aysha/q54/q54_Optimized_V2.sql",
    59: "q59-sf4/query59_BEST.sql",      # the SF=4 rewrite, 38.9x
    67: "Aysha/q67/q67-v2-Optimized.sql",
    72: "q72/query72_BEST.sql",
    78: "q78/query78_BEST.sql",
    88: "q88/query88_BEST.sql",
    97: "Aysha/q97/query97_BEST_no_temp_tables.sql",   # temp tables not permitted
    # Nafiz, merged 2026-10-25.  He also has q31 and q51, but riccio's are
    # already verified here; worth comparing the two later.
    7:  "Nafiz/tier4/q7/query7_BEST.sql",
    8:  "Nafiz/tier4/q8/query8_BEST.sql",
    10: "Nafiz/tier4/q10/query10_BEST.sql",
    33: "Nafiz/tier4/q33/query33_BEST.sql",
    37: "Nafiz/tier4/q37/query37_BEST.sql",
    11: "Nafiz/tier5/q11/query11_BEST.sql",
    57: "Nafiz/tier5/q57/query57_BEST.sql",
    74: "Nafiz/tier5/q74/query74_BEST.sql",
    # Claude, from the structural scan of the unoptimized queries
    68: "q68-sf4/query68_v1_datefirst.sql",
    46: "q46-sf4/query46_v1_datefirst.sql",
    # Claude, second pass over the ten that were still on the original text.
    # Ten were rewritten; these four are the ones that measured faster with
    # byte-identical output.  The other six (38, 58, 65, 66, 77, 87) are kept
    # in queries/optimized/q*-sf4/ with their measurements and are NOT
    # substituted -- see each directory's README.
    23: "q23-sf4/query23_v3_densekeys.sql",   # 160.7s -> 44.7s, 3.60x
    70: "q70-sf4/query70_v1_nosubquery.sql",  #  11.6s ->  3.6s, 3.22x
    35: "q35-sf4/query35_v1_keydate.sql",     #   1.7s ->  1.3s, 1.31x
    82: "q82-sf4/query82_v1_exists.sql",      #   0.8s ->  0.1s, 8.00x
    # Five queries were optimized twice, independently (commits c56bfbc,
    # f871372).  Measured head to head here at SF=4, three interleaved
    # passes, every pair returning identical output
    # (queries/optimized/compare-classmates.sh):
    #
    #     q65   ours 2.6s   theirs 1.6s   theirs wins all three passes
    #     q87   ours 3.9s   theirs 1.1s   theirs wins all three passes
    #     q70   ours 2.6s   theirs 3.5s   ours wins warm; their pass 1 was cold
    #     q82   ours 0.1s   theirs 0.3s   ours
    #     q37   ours 0.3s   theirs 0.3s   tie, Nafiz's stays
    #
    # The two theirs win are exactly the two where the rewrite attempted here
    # failed -- q65 measured 0.97x and q87 0.80x against the original, and
    # both were rejected.  Their approaches succeed where those did not.
    65: "q65/query65_BEST.sql",               # theirs, 1.62x over ours
    87: "q87/query87_BEST.sql",               # theirs, 3.55x over ours
}

# q38's "optimized" file contains only CREATE INDEX -- no query to
# substitute.  Its indexes are already in sql/14_contributed_indexes.sql.
# q35 was in this set until it got a real rewrite above.
INDEX_ONLY = {38}

# Per-query split_materialized measurements, seconds at SF=4, relative to
# leaving it at the default.  Negative means turning it off helped.
#
# q23 used to sit here at +54.0.  That figure was measured against the
# original query text, whose frequent_ss_items CTE grouped four years of
# store_sales on a 30-character varchar -- materialising it once really was
# worse than recomputing it 55,882 times.  queries/optimized/q23-sf4/ now
# replaces that CTE with a single-table aggregate costing 3.0s, so the
# trade-off the number describes no longer exists.  Dropped rather than
# carried forward, so the generated file does not claim a measurement about
# a query text it is not running.
DELTA = {59: -138.1, 14: -17.0, 2: -9.5, 5: -8.9, 11: -5.6, 27: -3.7,
         68: -1.9, 72: -1.6, 46: -1.6, 22: -1.3,
         57: +3.2, 78: +13.9, 4: +14.6}
THRESHOLD = 3.0
APPLY = sorted(q for q, d in DELTA.items() if d <= -THRESHOLD)
WORSE = sorted(q for q, d in DELTA.items() if d > 0)
MARGINAL = sorted(q for q, d in DELTA.items() if -THRESHOLD < d < 0)


def correct(n, sql):
    """Fix defects in the optimized sources on the way out, leaving the
       files under queries/optimized/ untouched."""
    notes = []
    if n == 14 and "i_braknd_id" in sql:
        # transposed letters: part B has never executed
        sql = sql.replace("i_braknd_id", "i_brand_id")
        notes.append("typo i_braknd_id -> i_brand_id (part B would not run at all)")
    if n == 14 and "as brand_id," in sql:
        # Part B collapses the ty_/ly_ column pairs: TPC-DS emits channel,
        # brand, class and category TWICE (once per year, 12 columns), this
        # emits them once plus both years' figures (8 columns).  The join
        # forces ty_ == ly_ on those four -- verified against the original's
        # own output -- so expanding them back is faithful.
        sql = sql.replace(
            """select 'store' as channel,
       weekly_sales.i_brand_id    as brand_id,
       weekly_sales.i_class_id    as class_id,
       weekly_sales.i_category_id as category_id,
       weekly_sales.this_year_sales,
       weekly_sales.this_year_number_of_sales,
       weekly_sales.last_year_sales,
       weekly_sales.last_year_number_of_sales""",
            """select 'store' as ty_channel,
       weekly_sales.i_brand_id    as ty_brand,
       weekly_sales.i_class_id    as ty_class,
       weekly_sales.i_category_id as ty_category,
       weekly_sales.this_year_sales as ty_sales,
       weekly_sales.this_year_number_of_sales as ty_number_sales,
       'store' as ly_channel,
       weekly_sales.i_brand_id    as ly_brand,
       weekly_sales.i_class_id    as ly_class,
       weekly_sales.i_category_id as ly_category,
       weekly_sales.last_year_sales as ly_sales,
       weekly_sales.last_year_number_of_sales as ly_number_sales""")
        # the ORDER BY referenced the aliases just renamed
        sql = sql.replace("order by brand_id, class_id, category_id",
                          "order by ty_brand, ty_class, ty_category")
        notes.append("part B emitted 8 columns; TPC-DS requires 12 (the ty_/ly_ "
                     "key columns are repeated per year) - expanded, and its "
                     "ORDER BY updated to the new aliases")
    if n == 47 and re.search(r'SELECT\s+\*\s*\n\s*FROM\s+v1', sql, re.I):
        # its v1 declares sum_sales before avg_monthly_sales, so SELECT *
        # emits columns 7 and 8 transposed against the TPC-DS select list
        sql = re.sub(
            r'SELECT\s+\*\s*\n\s*FROM\s+v1',
            "SELECT i_category, i_brand, s_store_name, s_company_name,\n"
            "       d_year, d_moy, avg_monthly_sales, sum_sales, psum, nsum\n"
            "FROM v1", sql, flags=re.I)
        notes.append("named the select list: SELECT * had sum_sales and "
                     "avg_monthly_sales transposed")
    return sql, notes


def clean(sql):
    """Drop a leading EXPLAIN/ANALYZE and index DDL; keep SET and temp tables.

    Strips a UTF-8 BOM first.  Eight of Nafiz's files begin with one, and it
    defeats the comment test: the first line reads "\ufeff-- v3: ..." which
    does not start with '--', so the comment survived into the SQL.  Where the
    BOM sat directly before SELECT (q8) it made the statement itself invalid.
    All three failures were this.

    Comments are stripped BEFORE splitting on ';'.  A comment containing a
    semicolon -- q4 opens with "-- Requires unique customer.c_customer_id;
    validate that assumption separately." -- otherwise splits mid-comment and
    the tail survives as stray text ahead of the query.
    """
    sql = sql.lstrip('\ufeff')
    sql = "\n".join(l for l in sql.splitlines()
                    if not l.strip().lstrip('\ufeff').startswith('--'))
    out, dropped = [], []
    for st in sql.split(';'):
        body = st.strip()
        if not body:
            continue
        head = body.split(None, 1)[0].lower()
        # index DDL and ANALYZE TABLE are maintenance, not the query.  Left in,
        # ANALYZE TABLE prints its own Table/Op/Msg_type/Msg_text rows into the
        # result set, which looks like the query returning extra rows.
        if head in ('create', 'drop') and re.search(r'\bindex\b', body, re.I):
            dropped.append(re.sub(r'\s+', ' ', body)[:60])
            continue
        if re.match(r'analyze\s+(table|local|no_write_to_binlog)', body, re.I):
            dropped.append(re.sub(r'\s+', ' ', body)[:60])
            continue
        body = re.sub(r'^\s*(analyze\s+format\s*=\s*json|explain\s+analyze|explain)\s+',
                      '', body, flags=re.I).strip()
        if body:
            out.append(body)
    return ";\n".join(out) + ";\n", dropped


def tier45():
    ns = set()
    for pat in (f"{REPO}/queries/tiers/04_*.sql", f"{REPO}/queries/tiers/05_*.sql"):
        for f in glob.glob(pat):
            ns |= {int(m) for m in re.findall(r'query(\d+)', open(f).read())}
    if not ns:
        raise SystemExit("could not read queries/tiers/04_*.sql and 05_*.sql")
    return ns


def main():
    want = tier45()
    os.makedirs(DST, exist_ok=True)
    for old in glob.glob(f"{DST}/query*.sql"):
        os.remove(old)

    used_opt, used_orig, all_notes = [], [], []
    for n in sorted(want):
        src = OPTIMIZED.get(n)
        notes = []
        if src and n not in INDEX_ONLY:
            paths = src if isinstance(src, list) else [src]
            parts = []
            for rel in paths:
                fixed, nt = correct(n, open(f"{OPT}/{rel}").read())
                notes += nt
                body, dropped = clean(fixed)
                parts.append(body)
                if dropped:
                    notes.append("removed index DDL: " + "; ".join(dropped))
            sql = "\n".join(parts)
            origin = ", ".join(f"queries/optimized/{p}" for p in paths)
            used_opt.append(n)
        else:
            sql = open(f"{SRC}/query{n}.sql").read().rstrip()
            sql += ("" if sql.endswith(';') else ';') + "\n"
            why = ("its optimized file is index-only, no query to substitute"
                   if n in INDEX_ONLY else "no optimized version exists")
            origin = f"queries/mariadb/query{n}.sql  ({why})"
            used_orig.append(n)

        h = [f"-- query{n}", f"-- source: {origin}"]
        for note in notes:
            h.append(f"-- correction: {note}")
        if n in APPLY:
            h.append(f"-- split materialisation OFF: measured {DELTA[n]:+.1f}s at SF=4")
        elif n in WORSE:
            h.append(f"-- split materialisation left ON: disabling it measured "
                     f"{DELTA[n]:+.1f}s (slower)")
        elif n in MARGINAL:
            h.append(f"-- split materialisation at default: {DELTA[n]:+.1f}s is "
                     f"inside this host's noise")
        if n in PIPES:
            h.append("-- needs PIPES_AS_CONCAT: it concatenates with ANSI '||', and")
            h.append("-- without the mode MariaDB reads that as OR and returns wrong rows")

        body = "\n".join(h) + "\n\n" + SQLMODE + "\n"
        if n in APPLY:
            body += NOSPLIT + "\n"
        body += "\n" + sql
        open(f"{DST}/query{n}.sql", 'w').write(body)
        if notes:
            all_notes.append((n, notes))

    print(f"wrote {len(want)} files to queries/tuned/ (tier 4+5)")
    print(f"  team's optimized version : {len(used_opt):>2}  {used_opt}")
    print(f"  TPC-DS original          : {len(used_orig):>2}  {used_orig}")
    print(f"  split_materialized=off   : {len(APPLY):>2}  {APPLY}")
    if all_notes:
        print("  corrections applied:")
        for n, nt in all_notes:
            for x in nt:
                print(f"    q{n}: {x}")


if __name__ == "__main__":
    main()
