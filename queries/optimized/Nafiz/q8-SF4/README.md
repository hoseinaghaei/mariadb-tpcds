# Q8 optimization — Docker SF4, seed 10

BEST is `query8_v5_prefix_pushdown.sql`, copied exactly to `query8_BEST.sql`. Seven final measured rounds gave a median **0.015217s**, compared with **0.468198s** for original SQL on the shared reference profile: **30.77x** including index changes. With the same two added indexes, unchanged SQL measured **0.115572s**, so the SQL rewrite itself measured **7.59x** faster.

**The real SF4 result is empty.** The original and every retained candidate agree. This speedup describes how quickly this query instance establishes that no rows qualify; it is not a claim about a large nonempty result. A separate session-local nonempty fixture validated the aggregate semantics before selecting BEST.

## Final retained versions — decreasing runtime

| Version | Optimization criteria | Index profile | Median seconds | Min–max seconds | Reference speedup |
|---|---|---|---:|---:|---:|
| `v0_original` | Original | reference167 | 0.468198 | 0.374926–0.484375 | 1.00x |
| `v1_zip_store_first` | ZIP/store first | reference167 | 0.188611 | 0.138454–0.196945 | 2.48x |
| `v2_address_cover` | Address covering | reference167 + address pair | 0.115572 | 0.095305–0.124255 | 4.05x |
| `v3_filtered_address` | Filtered address groups | reference167 | 0.038597 | 0.033023–0.048342 | 12.13x |
| `v4_filtered_cover` | Filtered covering | reference167 + address pair | 0.027565 | 0.023008–0.028438 | 16.99x |
| `v5_prefix_pushdown` | Prefix range pushdown | reference167 + address pair | 0.015217 | 0.013192–0.016258 | 30.77x |

Every version has seven measured runs after a discarded warm-up. Retained timing ranges do not overlap. Version numbers follow measured runtime, not development chronology. These include alternative physical designs as well as cumulative SQL changes; the differences are explicit below.

## What Q8 computes and why it is empty

Q8 finds distinct five-character ZIPs that are in its fixed ZIP list and belong to full address-ZIP groups with more than ten preferred customers. It joins each qualifying ZIP to stores sharing its first two characters, then sums store-sales profit for quarter 2 of 2000, grouping by store name.

The original and simplified eligible-ZIP sets match exactly: **7 ZIPs**. None shares a prefix with a store in this SF4 seed-10 dataset: **0 store/ZIP pairs**. That is why the final result is empty. The original plan nevertheless reads about 310,086 qualifying sales rows before applying that match. This is wasted work that a join-order change can avoid. No query has been replaced by a hardcoded empty SELECT.

## Indexing was investigated first

The original already uses `idx_ss_date_store_profit` as a covering sales index; adding another sales index would duplicate that useful access. The main address-side work was a scan of 233,000 customers and roughly 110,042 address lookups. Three new experimental indexes were tested independently and in combinations:

| Index | Ordered columns | Size MiB | Build + ANALYZE seconds |
|---|---|---:|---:|
| `idx_nf_q8_pref_addr` | c_preferred_cust_flag,c_current_addr_sk | 7.031 | 0.382 |
| `idx_nf_q8_addr_pref` | c_current_addr_sk,c_preferred_cust_flag | 7.031 | 0.263 |
| `idx_nf_q8_zip_cover` | ca_zip | 5.031 | 0.168 |

The flag-first customer index alone gave only a small improvement and was not retained as a separate numbered version. The address-first customer covering index plus the ZIP index reduced unchanged Q8 to the v2 result. The ZIP secondary index includes the InnoDB primary key (`ca_address_sk`) implicitly, so it covers the address key and ZIP without adding the key a second time. Both indexes are small compared with sales-table covering indexes. `indexes-BEST.sql` contains the selected pair and is required for v2, v4 and v5. It adds two secondary indexes to the 167-index reference profile.

## How every retained version was optimized

### v0_original — untouched reference

Original SQL, original INTERSECT and original joins. SF4 execution-plan diagnostics show a date-first sales scan followed by the late ZIP/store match. The source `queries/mariadb/query8.sql` is not edited; the saved v0 is an exact file copy.

### v1_zip_store_first — apply the restrictive join first

Keeps the original ZIP INTERSECT query intact and uses STRAIGHT_JOIN with the derived ZIP set followed by store, date_dim and store_sales. If no store matches the ZIP set, sales need not be touched. This is a SQL-only alternative using the original 167 visible indexes. It retains every join and sum expression.

### v2_address_cover — index-only alternative

SQL is intentionally identical to v0. Only the two selected customer/address indexes change. This demonstrates index benefit separately from a SQL rewrite. It is not cumulative with v1's reordered SQL.

### v3_filtered_address — simplify INTERSECT and filter before counting

The INTERSECT's first branch merely proves the existence of a listed address ZIP. The preferred-customer/address join in the second branch already proves the same address exists. The rewrite therefore performs that join once, filters the fixed ZIP list before grouping, and retains `GROUP BY a.ca_zip HAVING COUNT(*)>10`. It then selects DISTINCT five-character ZIPs. Inner STRAIGHT_JOIN makes address filtering happen before customer lookups; outer STRAIGHT_JOIN keeps the ZIP/store test ahead of sales. This version uses only the reference indexes.

Two correctness details are essential: the count threshold applies to the original **full ZIP value**, not to the five-character projection; and DISTINCT applies after grouping, so multiple full ZIP groups with the same five-character ZIP contribute only one eligible ZIP.

### v4_filtered_cover — combine the filtered rewrite with covering indexes

Uses the simplified ZIP query and the selected address/customer index pair. The outer join still checks the ZIP/store relationship first. This version lets the optimizer order the inner filtered address/customer join under the new indexes instead of retaining v3's inner STRAIGHT_JOIN. It is a combined index + SQL variant, not merely a renamed file.

### v5_prefix_pushdown — BEST

Keeps the simplified, distinct ZIP calculation and covering indexes. Adds an equivalent OR-list of `a.ca_zip LIKE 'xxxxx%'` predicates alongside the original substring-IN predicate, allowing range access to the ZIP index. This is generated from the original fixed list of five-digit ZIP values; no ZIP literal is changed. It handles full ZIP strings such as `67454-0001` as well as five-character strings.

An EXISTS test for a store with the same two-character prefix is pushed into the address filter. It prunes only ZIPs that could never survive the original later store join. The original outer store join is still present. This EXISTS does **not** replace the ZIP join or remove its multiplicity: if two distinct eligible ZIPs share a store prefix, the store's profit is counted twice, just as in the original. On this dataset ANALYZE reads 766 candidate addresses, rejects the unmatched/under-threshold groups, and records zero loops for the sales table.

## Other executed tests and reasons not to retain them

- Date-key bounds for 2000 Q2 (`2451636` through `2451726`, 91 days) did not provide a reliable additional benefit here; the original already chooses a date-first access path. The selected SQL keeps date_dim and the original year/quarter predicates.
- Flag-first preferred-customer covering index alone: small gain; the address-index pair is substantially better. Adding all three indexes did not improve reliably over that pair.
- A prefix-count weighted aggregate preserved the nonempty fixture's sums, but did not improve reliably over the simpler DISTINCT-ZIP join. It was rejected rather than adding more aggregate complexity.
- Removing the outer join-order control was slower without the new indexes and tied under the covering profile. Keeping the measured ZIP/store-first plan is clearer.
- Address-first ordering without the new indexes was useful (v3); with the pair it tied the simpler inner join and was not kept as another version.
- ZIP LIKE-ranges alone improved time, but the combined range + store-prefix pruning was faster. The intermediate range-only query remains screening evidence rather than an extra final SQL version.
- Store-prefix EXISTS alone, without indexed ZIP ranges, was slower in refinement (roughly 0.54s). The combined method avoids that broad-scan overhead.

`screening-results.csv` records each exploratory median, including the different physical profiles. Compare retained versions using the final seven-round table, rather than mixing screening and confirmation timings. Rejected SQL texts are preserved only as investigation evidence in `evidence/candidates.json` and `evidence/refinements.json`, not as numbered optimized versions.

## Correctness validation

All real SF4 timed executions matched the original ordered output exactly: zero rows. Therefore every saved top-level `.out` is correctly zero bytes; this is not a failed or missing output. SQL errors stop the runner and are never recorded as successful empty results.

The original INTERSECT and simplified eligible-ZIP set were also compared directly and matched all seven ZIPs. Their nonempty outputs are saved under `evidence/`.

A temporary-table fixture produced `Alpha 22.50` and `Null profit NULL` for the original and all **13** tested original/rewrite forms. It tests two qualifying ZIPs with one store prefix (profit multiplication), repeated full ZIPs sharing a five-character ZIP (DISTINCT), two six-customer full ZIP groups (must not incorrectly pass >10 after prefix grouping), exactly ten preferred customers, nonpreferred customers, NULL profits and ZIPs, duplicate store names, excluded dates, absent date/store/address joins, and stores without sales. Temporary tables existed only in each fixture client session; no SF4 base data was modified. The fixture SQL, actual output and per-candidate checks are saved in `evidence/nonempty-fixture.sql`, `.out` and `fixture-validation.json`. These are strong checks for this rewrite, not a mathematical proof for every possible collation, schema or scale.

## Measurement protocol and limitations

MariaDB 13.0.2 Docker; SF4 seed 10; 8 GiB buffer pool; 32 KiB pages; query cache OFF; persistent-statistics sample pages 160; serial workload; all 13 standing settings checked. The initial index definitions and settings are in `evidence/metadata.json`. One discarded warm-up per final variant, seven measured rounds with forward/reversed order, and median/min/max client wall times. Connection, session preamble and output transfer are included. Index creation, ANALYZE, visibility changes and diagnostic EXPLAIN/ANALYZE executions are outside the timers. No cache clearing was used. Other experimental indexes were IGNORED per profile; all 167 reference indexes stayed visible. Physically present ignored indexes may still affect cache/storage conditions, which is why this is a controlled local experiment rather than a certification result.

BEST's 15.22ms client time is close to client overhead; do not treat sub-millisecond differences as meaningful new improvements. The empty qualifying-store case makes early pruning especially effective. Benchmark other scales and genuinely nonempty real instances before generalizing the speedup. Further methods may exist; the tested alternatives stopped giving a useful reliable gain beyond this combination.

## Saved files and shared configuration

Each numbered version has SQL and its checked `.out`; BEST is an exact alias of v5. `benchmark-results.csv` contains the final seven-run summaries and duration components/totals, including derived 100-nanosecond ticks (not CPU cycles). `benchmark-runs.csv` contains all successful exploratory, warm-up and final executions with labels, profiles and hashes. The HTML chart is longest to shortest, original first. Evidence includes diagnostic plans, index sizes, exact ZIP sets, fixture validation, SQL texts and unrounded timings.

After testing, only the three experiment-owned indexes were removed, restoring the shared **167 visible secondary indexes** and 8 GiB buffer pool. No original reference index was removed or hidden. The preserved index setup must be applied before expecting BEST's measured performance. Q8-only measurements do not establish benefit to other queries.

## Run BEST again

From the repository root in PowerShell, with the prepared SF4 container running:

```powershell
$container = 'tpcds-nafiz-sf4-ready-20261028t200145z'
docker cp ./queries/optimized/Nafiz/q8-SF4 "$($container):/tmp/q8-SF4"
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot tpcds < /tmp/q8-SF4/indexes-BEST.sql'
docker exec $container bash -c 'mariadb --socket=/data/mysql.sock -uroot --batch --skip-column-names tpcds < /tmp/q8-SF4/query8_BEST.sql'
```

An empty terminal output is expected for this real dataset. The setup changes the live physical profile to 169 secondary indexes; record that in subsequent benchmarks. To reproduce the reference baseline, use the clean reference profile or remove only these experiment-owned additions after saving results. `evidence/study-runner.py` records the development protocol and uses the mounted Docker `/project`, `/setup` and `/results` paths; it is not an automatic fresh-database setup tool.
