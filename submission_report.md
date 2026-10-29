# TPC-DS on MariaDB — project submission report

**TPC-DS v4.0.0 · MariaDB 13.0.2 · scale factors 1, 2, 4, 8**

> **Not comparable to TPC Benchmark Results.** Unaudited, not produced at a
> publishable scale factor, and not meeting any official TPC Benchmark
> Standard. Published as an engineering exercise under clause 4.c(3) of the
> TPC End User License Agreement (`DSGen-software-code-4.0.0/EULA.txt`).

---

## Contents

1. [How MariaDB indexes and optimizes](#1-how-mariadb-indexes-and-optimizes)
2. [Where we started: the reference repository](#2-where-we-started-the-reference-repository)
3. [What that repository did on our machine](#3-what-that-repository-did-on-our-machine)
4. [What we changed](#4-what-we-changed)
5. [The optimization catalogue, by type](#5-the-optimization-catalogue-by-type)
6. [Total execution time across scale factors](#6-total-execution-time-across-scale-factors)
7. [Queries with the largest wins](#7-queries-with-the-largest-wins)
8. [Observations: what worked, what did not](#8-observations-what-worked-what-did-not)
9. [Reproducing](#9-reproducing)
10. [Limitations](#10-limitations)

---

## 1. How MariaDB indexes and optimizes

Everything this project found follows from four properties of the engine.
They are stated here because most of our results are consequences of them,
not of TPC-DS.

### 1.1 InnoDB is clustered, and the primary key is the table

InnoDB stores rows *inside* the primary-key B-tree. The primary key is not an
index over the table; it **is** the table, in primary-key order. Two
consequences shaped the whole project:

- **Every secondary index implicitly contains the primary key.** The leaf of a
  secondary index stores the indexed columns plus the PK, because that is how
  it finds the row. So an index on a **leading prefix of the primary key
  indexes nothing new**. We found seven such indexes inherited from the
  reference set — `inventory(inv_date_sk)` where the PK is
  `(inv_date_sk, inv_item_sk, inv_warehouse_sk)`, and six siblings — wasting
  **470 MB** at SF=1 and duplicating work on every insert
  ([report 18](report/18-query-optimization.md)).
- **Physical row order is primary-key order.** TPC-DS fact tables are keyed
  `(item_sk, ticket_number)` but the generated data arrives in *date* order,
  so loading writes rows to random points in the B-tree, splitting pages. We
  measured the result: leaf pages end up **~48% full**, which is why 4.2 GB of
  generated SF=4 text loads into 8.87 GB of database (§8.4).

### 1.2 The optimizer is cost-based, and its costs come from sampled statistics

MariaDB chooses a plan by estimating rows at each step and costing the
alternatives. Those estimates come from InnoDB's persistent statistics, which
are built by **sampling `innodb_stats_persistent_sample_pages` pages per
index** — 20 by default. A sample, not a count.

This single fact explains more of our results than any other:

- Raising the sample from 20 to 160 on a 16K-page instance recovered **21%**
  of the entire 99-query suite with no other change ([report 20](report/20-innodb-page-size.md)).
- It is also why `innodb_page_size` appeared to matter: a 32K page holds twice
  the entries of a 16K page, so the *same* 20-page sample covered twice as
  many rows and produced better estimates. The page size was buying
  statistics, not I/O.
- And because the sample is random, **re-analysing can change the plan**. We
  measured a case where hiding and immediately re-showing one index — a net
  no-op — changed 31 of 44 query plans (§8.2).

### 1.3 `EXPLAIN` exposes what the optimizer considered, not just what it chose

For each table access `EXPLAIN` reports `possible_keys` (the indexes it
weighed) and `key` (the one it picked). The distinction between *weighed* and
*read* turned out to be the key to the entire index analysis (§5.4), because
an index can shape a plan without a single row ever being read through it.

### 1.4 Hints and `IGNORED` are the available levers

- `/*+ JOIN_PREFIX(...) */`, `STRAIGHT_JOIN`, `FORCE INDEX`, `IGNORE INDEX` —
  per-statement steering. MariaDB 13.0.2 parses optimizer hints properly (a
  bogus hint name raises `Warning 1064`, so they are not silently ignored).
- `ALTER TABLE … ALTER INDEX … IGNORED` — hides an index from the optimizer
  while leaving it on disk. Reversible in ~0.15s. Indispensable for index
  experiments, and carrying a trap we document in §8.2.

---

## 2. Where we started: the reference repository

The starting point was
[`spetrunia/tpcds-run-tool`](https://github.com/spetrunia/tpcds-run-tool), by
a MariaDB optimizer developer, tracking MariaDB bug
[MDEV-17802](https://jira.mariadb.org/browse/MDEV-17802) — *"MySQL/MariaDB
cannot run all of the TPC-DS queries"*.

It gave us three things:

| | |
|---|---|
| `ddl/indexes.sql` | **117 indexes** — the optimization starting point |
| `adapt-queries-for-mariadb-v4.diff` | an independent check on our dialect fixes |
| `setup-mariadb-current.sh` | the server config — **one** performance line, `innodb_buffer_pool_size=8G` |

And it had two limits we had to deal with before measuring anything.

**It runs 83 of 99 queries.** Sixteen are excluded, three replaced by stubs
such as `select 'MARIADB-EXPECTED-ERROR: full outer join'`. We got all 99
running. Part of that gap was simply seven years of MariaDB development —
`INTERSECT`/`EXCEPT` arrived in 10.3, window functions in 10.2, both after the
repo was written. The rest (ROLLUP ordering, FULL OUTER JOIN, unaliased
derived tables) needed real workarounds
([report 11](report/11-reference-repo.md), [report 10](report/10-adapt-queries.md)).

**Its dataset cannot be checked against the TPC answer sets.** It generates
with `-rngseed 10`, which changes the *data*, not just its order — `store_sales`
has 2,879,152 rows at seed 10 against 2,880,404 at the default. The published
reference cardinalities are the default-seed ones. We kept seed 10 for
comparability with the reference and verify answers by cross-run checksum
instead ([report 13](report/13-benchmark-results.md)).

We also built the schema from the **specification**, not from the toolkit's
`tpcds.sql`, which disagrees with it — most consequentially declaring
`customer.c_last_review_date` as `char(10)` where the spec, the toolkit's own
RI script and the generated data all say `c_last_review_date_sk`, an integer
date key. Taking the shipped DDL at face value breaks query 30
([report 04](report/04-reconcile-discrepancies.md)).

---

## 3. What that repository did on our machine

### 3.1 The first answer was wrong, and finding out why set the method

Our first measurement said the 117 indexes delivered **2.06x**. It was an
artefact. Everything up to that point had run with
`innodb_buffer_pool_size = 128M` against a 3.2 GB database — **under 4%** —
the Homebrew default, never examined. The indexes were compensating for a
memory shortage, not adding value.

Rebuilt on the reference's own 8 GB pool, serially, on a quiet machine
([report 16](report/16-buffer-pool-and-root-cause.md)):

| set | base (no indexes) | indexed (117) | speedup |
|---|---:|---:|---:|
| all 99, including capped | 1877.0s | 1563.0s | 1.20x |
| **97 completing in both** | **1276.8s** | **1262.8s** | **1.01x** |

**With an adequate buffer pool, the inherited 117 indexes were worth 1%.**
25 queries got faster, **18 got slower**, 54 were unchanged. Time won 188.4s,
time lost 154.2s.

The 1.20x on all-99 is carried almost entirely by one query: **q95, from
not completing in 300s to 0.1s**, a `web_sales` self-join that is quadratic
without `idx_ws_order_number`.

### 3.2 Where the regressions came from

Three `inventory` indexes caused **74% of all time lost**. Confirmed by a
three-pass visible/ignored/visible test, not inferred:

| query | base | visible | **ignored** | visible again |
|---|---:|---:|---:|---:|
| q39 | 1.7s | 58.3s | **1.1s** | 58.9s |
| q21 | 0.4s | 14.3s | **0.2s** | 14.5s |
| q22 | 12.0s | 14.3s | **7.5s** | 12.9s |
| q31 | 14.8s | 18.1s | 17.6s | 17.8s |

q31 was *predicted not to improve* — its plan uses `store_sales.idx_ss_addr_sk`,
not an inventory index — and did not. That the experiment discriminates is
what makes the diagnosis credible rather than coincidental.

The mechanism, measured: `idx_inv_warehouse_sk` read **64.3 million rows from
an 11.7 million row table** — five whole passes, each as random single-row
lookups. The slow log makes it concrete: *1,744,439 pages accessed to return
100 rows, zero prefetched*. Zero prefetch is the signature of random index
access; a scan-based plan in the same log prefetched 2,598 of 3,818 pages
([report 15](report/15-index-statistics.md)).

### 3.3 Most of the inherited index set was dead

**81 of the 117 indexes were never read by any query** — the same count on two
completely different datasets. Whole groups were dead: 15 of `catalog_returns`'
17 indexes, 11 of `web_returns`' 14, 13 of `catalog_sales`' 18.

The obvious conclusion — drop them — turned out to be wrong, and §5.4 is the
story of why.

---

## 4. What we changed

Four independent levers, measured separately:

| # | lever | effect | section |
|---|---|---|---|
| 1 | **Server configuration** | ~2.5x at SF=4, 2.94x at SF=1 | §5.1 |
| 2 | **Query rewrites** | 35 of 40 tier-4/5 queries rewritten | §5.2–5.3 |
| 3 | **Indexes added** | the reference 117 → **166** defined | §5.5 |
| 4 | **Indexes removed** | 166 → **95**, −6.35 GB at SF=4, no cost | §5.4 |

Scope note: from the point where the full 99-query behaviour was established,
comparisons use the **40 tier-4 and tier-5 queries** — the expensive ones.
Tiers 1–3 are sub-second, and their timings are dominated by connection and
parse overhead rather than by anything we changed.

---

## 5. The optimization catalogue, by type

### 5.1 Server configuration — the single largest lever

Ten proposed settings, tested individually at SF=4 against a 2403.4s baseline
([report 23](report/23-server-tuning-sf4.md)):

| run | what it adds | total | vs baseline |
|---|---|---:|---:|
| baseline | — | 2403.4s | 1.00x |
| **item 1 only** | `tmp_table_size`/`max_heap_table_size` 16M → 1.5G | **1195.5s** | **2.01x** |
| **T1 (re-measured)** | + 6 more settings | **971.4s** | **2.47x** |
| T1 + `split_materialized=off` | globally | 867.5s | 2.77x |
| T1, best setting per query | — | 777.7s | 3.09x |

Two further variants were tested against T1 **as first published (829.8s)** and
both regressed, so they are not comparable to the corrected T1 above:
histograms **939.5s** and `innodb_buffer_pool_dump_pct=100` **1049.3s**.

**One setting is two thirds of it.** `tmp_table_size` and
`max_heap_table_size` were at MariaDB's 16 MB default. TPC-DS queries
materialise multi-million-row intermediates, so nearly every tier-4/5 query
was spilling temp tables to disk. Raising those two alone is worth **2.01x**.

Biggest movers under T1: q5 376.7s → 27.6s, q2 242.2s → 13.5s,
q51 218.8s → 29.4s, q54 111.2s → 4.3s.

**Two proposals were rejected on measurement.** Collecting engine-independent
histograms cost 649s and made the suite 13% slower; `dump_pct=100` was 26%
slower and caused two OOM kills. **And smaller pool + bigger temp space was
32% worse** — the buffer pool mattered more than the temp space.

The histogram regression was originally attributed to histograms themselves.
That was wrong: the cause was q59 drawing one of the two plans it flips
between (§8.3). Clearing `mysql.column_stats` to zero changed nothing.

**It transfers across scale.** Re-tested at SF=1, byte-identical config:
464.5s → **157.8s, 2.94x**, with 39 of 40 queries improving
([report 24](report/24-does-the-tuning-transfer.md)). This is worth separating
from the page-size result, which did *not* transfer (§8.1): a 16 MB temp table
spills whether the database is 9 GB or 32 GB, so removing a hard limit
generalises in a way that a plan preference does not.

### 5.2 Query rewrites — the techniques that worked

**(a) Replace a dimension join with a key range.** TPC-DS dimensions are
*dense*: `date_dim` holds 73,049 rows over `d_date_sk` 2,415,022–2,488,070
with no gaps. We verified density by checking `max(key) − min(key) + 1 = count`
for `date_dim`, `item` and `customer`. So any contiguous set of days is a
contiguous key range, and a `date_dim` join that exists only to apply a date
filter becomes a `BETWEEN` on the fact table's own foreign key:

```sql
-- before
join date_dim on ss_sold_date_sk = d_date_sk  where d_year = 1999 and d_moy = 7
-- after
where ss_sold_date_sk between 2451361 and 2451391
```

The substitution is always *correct*. It is almost never *sufficient* — see
§8.5, where the same technique failed on five queries out of eleven.

**(b) Conditional aggregation — collapse N passes into one.** q88 asks for
eight half-hour counts and the TPC-DS text delivers them as **eight
subqueries cross-joined**, each scanning `store_sales`. All eight are
identical but for the time window:

```sql
sum(case when t_hour = 8 and t_minute < 30 then 1 else 0 end) h8_30_to_9,
sum(case when t_hour = 8 and t_minute >= 30 then 1 else 0 end) h9_to_9_30, ...
```

**36.0s → 4.2s** from the rewrite alone, close to the 8x the structure predicts.

**(c) Delete work that does nothing.** q70 carries an `s_state in (select …
rank() over (partition by s_state …))` subquery. It groups by `s_state` and
then partitions by `s_state`, so the rank is always 1 and the filter removes
nothing. Deleting it: **11.6s → 3.6s**.

> **Partly superseded.** That rewrite also replaced the `date_dim` join with a
> key range and kept the TPC-DS `(s_state is null)+(s_county is null)`
> idiom for `lochierarchy`. Riccardo later showed that idiom is **wrong**
> whenever `s_state` or `s_county` is genuinely NULL in the data, because it
> cannot distinguish a rollup NULL from a data NULL. The adopted q70 now
> builds the hierarchy with explicit `UNION ALL` levels and restores the
> `date_dim` join. The aggregate-before-join structure survives; the
> `ROLLUP` shortcut does not. Same correction applied to q36 and q86.

**(d) Convert joins that only test existence into `EXISTS`.** q82's joins feed
a `GROUP BY` with no aggregate — which is a `DISTINCT` in disguise.
**0.8s → 0.1s, 8.00x.**

**(e) Push a filter into every CTE that will be filtered later.** q78's three
CTEs each aggregate all six years in the data while the outer query keeps only
2001. Pushing `d_year = 2001` into all three: **27.2s → 11.4s**.

**(f) Make the expensive thing cheap instead of choosing between bad plans.**
q23 — the full story is §7.2.

**(g) Steer the optimizer when it is wrong.** `JOIN_PREFIX` on q72,
`STRAIGHT_JOIN` on q43, `FORCE INDEX` on q22 (§7.3). We prefer a *prefix* to a
full join order: `JOIN_PREFIX` beat `JOIN_ORDER` in every comparison, because
over-constraining denies the optimizer the freedom to get the rest right.

### 5.3 Who rewrote what

35 of the 40 tier-4/5 queries run an optimized version:

| contributor | queries |
|---:|---|
| Claude | 12 — q2, q22, q23, q35, q46, q59, q68, q70, q72, q78, q82, q88 |
| Nafiz | 8 — q7, q8, q10, q11, q33, q37, q57, q74 |
| Aysha | 7 — q14, q21, q27, q43, q47, q54, q67 |
| riccio | 5 — q4, q5, q31, q39, q51 |
| classmate | 2 — q65, q87 |
| Aysha + adaptation | 1 — q97 |
| **still on the TPC-DS original** | **5 — q38, q58, q66, q71, q77** |

The five originals are not untouched — each was rewritten and measured, and
each rewrite was **slower** ([report 26](report/26-the-last-eleven.md)). They
are 19.7s of the 409.1s SF=4 total.

**A correctness rule throughout:** a rewrite is accepted only if its output is
byte-identical to the original. That rule caught a q97 rewrite that was
faster and wrong — a bare `count(*)` counted 2,569 NULL-customer rows,
giving 1,141,754 where the original gives 1,139,185.

### 5.4 Index removal — and why "never read" is the wrong test

This is the most transferable result in the project.

**The naive approach fails.** 130 of the 166 secondary indexes are never read
at either scale factor. Dropping them, leaving 37:

| SF=4, 40 queries | total |
|---|---:|
| full index set | 735.2s |
| never-read indexes dropped | **1487.0s** |

**Twice as slow**, on exactly the configuration whose own read counters said
those indexes did nothing. The mechanism is visible afterwards: **7 of the 37
indexes that had been read stopped being read**. Nothing about those 7
changed — the plans around them did.

**Why.** A read counter answers *"did executing the plan touch this index?"*
It does not answer *"did choosing the plan depend on this index existing?"*
The optimizer costs alternatives; to decide a scan beats a nested loop on
`idx_x`, it must consider `idx_x`. Remove it and that alternative is never
costed. The index did its work at planning time and left no trace.

**Hiding is not dropping.** Measured back to back on one database:

| SF=4, 190 indexes on disk | total | |
|---|---:|---:|
| all visible | 735.2s | — |
| 129 hidden from the optimizer | 815.9s | +11% |
| the same 129 *dropped* | 1487.0s | +102% |

**The right test is `EXPLAIN`.** `possible_keys` names what the optimizer
weighed. An index appearing in no plan anywhere was never a candidate, so
removing it cannot change which plan is chosen. One pass, no DDL, perfectly
deterministic — two captures of all 44 statements come back byte-identical.
(`scripts/index-consulted.py`.) At SF=4:

| verdict | indexes | size |
|---|---:|---:|
| **used** — read during execution | 36 | 6.89 GB |
| **considered** — never read, but weighed when costing | **60** | **11.05 GB** |
| **unreferenced** — never read, never mentioned | 70 | 5.35 GB |

That middle row is the finding: **11 GB of index that read counters call
useless and the optimizer depends on.** The clearest case is the three 1,030 MB
`inventory` indexes — the biggest never-read indexes in the database. For q21
the optimizer lists all four `inventory` secondary indexes in `possible_keys`
and then chooses `PRIMARY`. They are never read. They are not removable.

**Indexes also cover for each other.** Hiding any *single* candidate moves a
plan in only 8 of 58 cases; hiding all 120 candidates **together** moves 4
plans and costs 17%. Two indexes can each look disposable because the
optimizer still has the other. The unit of decision is a group, and a drop
list has to be validated as the list you intend to apply.

**The validated result:**

| set | indexes | size | plans moved when hidden together |
|---|---:|---:|---|
| unreferenced at both scales | 70 | 5.35 GB | **none** |
| + `idx_inv_date_sk` | **71** | **6.35 GB** | q22 only — and it gets *faster* |

Confirmed on the clock with four alternating runs (full, hidden, full,
hidden): 462.6s vs 448.4s mean, a difference smaller than the within-condition
spread, with **no query slower in both hidden runs**. A null result, which is
exactly what the plan analysis predicted.

Applied: **SF=4 31.72 GB → 25.36 GB (−20%), SF=1 9.63 GB → 7.86 GB (−18%),
no measurable cost.**

**A fourth category we did not anticipate.** `idx_inv_date_sk` is 1,030 MB,
read by nothing, *and actively harmful*: it makes the optimizer mis-cost a
choice between two other access paths, costing q22 28 seconds. So "unused"
splits four ways — read → keep; weighed into a better plan → keep; never
weighed → drop; **weighed into a worse plan → drop, and the query speeds up**.

### 5.5 Indexes added

| file | count | what |
|---|---:|---|
| `sql/05_indexes.sql` | 117 | the reference repository's set |
| `sql/11_optimizer_indexes.sql` | 14 | found during optimization |
| `sql/14_contributed_indexes.sql` | 43 | contributed by the team |
| **distinct total** | **166** | nine are defined twice |

The highest-value single index found was `date_dim(d_week_seq)`. q72 self-joins
`date_dim` on `d_week_seq` and **no index existed on that column**, so the join
was a full scan of 72,124 rows per driving row. Adding it took q72 from 13.1s
to 1.0s.

Note it declares **only** `d_week_seq`. InnoDB appends the PK, so
`(d_week_seq, d_date_sk)` is identical — same 161 pages, same `key_len=9`,
same `Using index`. That is §1.1 in practice.

---

## 6. Total execution time across scale factors

All four measured on **one identical recipe**: `dsdgen -RNGSEED 10`, 32K pages,
8 GB buffer pool, `innodb_stats_persistent_sample_pages=160`, the tuned server
block, **95 indexes**, the 40 tier-4/5 queries from `queries/tuned/`, no
`OPTIMIZE TABLE`, run serially in a Linux container.

| scale | rows* | data | secondary indexes | total DB | **40 queries** | vs previous |
|---|---:|---:|---:|---:|---:|---:|
| **SF=1** | 19.3 M | 2.91 GB | 4.95 GB | **7.86 GB** | **81.8s** | — |
| **SF=2** | 30.2 M | — | — | **13.4 GB** | **180.6s** | 2.21x |
| **SF=4** | 59.5 M | 9.02 GB | 16.35 GB | **25.36 GB** | **409.1s** | 2.27x |
| **SF=8** | 138.4 M | 18.8 GB | ~39 GB | **~58 GB** | **1583.2s** | **3.87x** |

40/40 queries, **0 errors at every scale**.

\* Row counts are `information_schema` estimates, which InnoDB samples rather
than counts — they move by ~1% between runs on identical data. Exact counts
are available per table; `store_sales` is 2,879,152 at SF=1 and 11,516,885 at
SF=4. The data/index split was measured directly only at SF=1 and SF=4; SF=2
and SF=8 give the total, and SF=8's data figure was taken at load time before
the indexes were built.

**Indexes outweigh the data roughly 2:1 at every scale** — 4.95 GB of index on
2.91 GB of data at SF=1, 16.35 on 9.02 at SF=4. That ratio is why §5.4 was
worth the effort, and why the answer it produced (−6.35 GB at SF=4, free)
matters more than it would on a normally-indexed schema.

### The suite scales linearly until the buffer pool loses

The data doubles at each step. Through SF=4 the suite tracks it at 2.21x and
2.27x — mildly superlinear and unremarkable. **From SF=4 to SF=8 it costs
3.87x.** That is a different regime, not more of the same.

It is concentrated, not general. **11 of 40 queries degrade worse than 4x**,
and they account for **694s of the 1583s total — 44% of the suite in 28% of
the queries**:

| query | SF=4 | SF=8 | |
|---|---:|---:|---:|
| q71 | 7.0s | 75.1s | 10.7x |
| q27 | 6.5s | 69.6s | 10.7x |
| q68 | 4.0s | 37.8s | 9.4x |
| q14 | 20.6s | 152.0s | 7.4x |
| q70 | 5.7s | 40.0s | 7.0x |
| q46 | 9.1s | 63.6s | 7.0x |
| q74 | 26.1s | 179.0s | 6.9x |

while the flattest barely move — q43 1.3x, q35 1.4x, q88 1.7x, q2 1.9x.

The ones that break are **mid-sized queries with large intermediate results**.
At SF=4 their working set still fits the 8 GB pool; at SF=8 it does not, and
they fall to disk at once. The queries already large enough to spill at SF=4 —
q4, q23, q67 — degrade at only 2.6–3.5x, because they were paying that cost
already.

**The useful number is not 1583.2s, it is the 2.27x → 3.87x break.** It
locates where this configuration stops being bound by work and starts being
bound by memory. Nothing about the queries or the index set predicts which
eleven queries pay for it. Raising `innodb_buffer_pool_size` is the obvious
next experiment.

### Per-query, all four scales (top 12 by SF=4)

| query | SF=1 | SF=2 | SF=4 | SF=8 | optimized by |
|---|---:|---:|---:|---:|---|
| q4 | 8.5s | 24.8s | 50.3s | 130.2s | riccio |
| q67 | 11.1s | 22.0s | 45.9s | 162.6s | Aysha |
| q23 | 9.6s | 21.0s | 44.8s | 115.0s | Claude |
| q51 | 5.0s | 13.6s | 29.4s | 82.1s | riccio |
| q11 | 5.6s | 12.6s | 28.3s | 91.6s | Nafiz |
| q74 | 5.2s | 11.1s | 26.1s | 179.0s | Nafiz |
| q14 | 3.7s | 8.1s | 20.6s | 152.0s | Aysha |
| q22 | 5.7s | 8.4s | 19.2s | 55.4s | Claude |
| q78 | 2.5s | 6.7s | 17.2s | 44.7s | Claude |
| q5 | 1.0s | 5.0s | 12.6s | 32.8s | riccio |
| q47 | 2.6s | 6.2s | 11.2s | 29.8s | Aysha |
| q57 | 1.9s | 3.7s | 10.6s | 33.6s | Nafiz |

The full 40-row table, with a note per query, is
[`report/25-query-by-query.md`](report/25-query-by-query.md).

---

## 7. Queries with the largest wins

Five queries where the win was large and the *route to it* was different each
time. Each was verified byte-identical to the original.

### 7.1 q72 — 719.3s → 1.0s, and the lesson is ablation

The worst query in the set; it failed to complete in every early run. Two
independent causes, separated by ablation:

| | |
|---:|---|
| original order, no hint | 719.3s |
| reordered FROM clause, no hint | 619.3s |
| original order, **with hint** | **13.0s** |
| + `date_dim(d_week_seq)` | **1.0s** |

**The FROM-clause reorder was worth 14%. The hint was worth 55x. The missing
index was worth another 13x.** The intuition going in was that rewriting the
join order mattered; it barely did. Without separating them, the wrong lesson
gets learned.

**But the honest figure is not 719x.** Once everyone's indexes are available
to the *original* too, q72's original runs in 90.6s, not a 300s timeout, and
the rewrite's remaining contribution is **1.1x**
([report 19](report/19-three-way-comparison.md)). It was never a 719x rewrite —
it was an index. We report both numbers because the first is what a naive
before/after measures and the second is what the rewrite is worth.

### 7.2 q23 — 160.7s → 44.7s, diagnosed by loop counts not by timing

The most expensive query in the suite, and two earlier attempts found nothing.
Timing cannot resolve it on this host — four identical runs of the original
spanned **160.7–213.0s** — so it was analysed with `ANALYZE FORMAT=JSON`,
whose loop counts are deterministic:

| node | ms | loops |
|---|---:|---:|
| `materialized` | **164,024** | **55,882** |

The CTE `frequent_ss_items` was being split-materialised **55,882 times**.
The obvious fix, `split_materialized=off`, had already measured **+54s
slower** — and that result was correct, because materialising once meant
grouping four years of `store_sales` by a 30-character varchar.

So instead of choosing between two bad plans, we made the CTE cheap: drop the
`item` join (its only contribution, `substr(i_item_desc,1,30)`, is
functionally dependent on the unique `i_item_sk`), use `d_date_sk` instead of
`d_date`, and reorder the `GROUP BY` to match an existing covering index.
**A 28.7s CTE became 3.0s.**

### 7.3 q22 — a plan that was a coin flip, now pinned

q22 is a plain `inventory ⋈ item` with a date range. Its cost depends entirely
on which `inventory` access path the optimizer picks:

| | best of 3 | inventory access |
|---|---:|---|
| as-is | 39.0s | `PRIMARY` |
| `FORCE INDEX (idx_inv_item_date_sk)` | **10.4s** | `idx_inv_item_date_sk` |

Identical answers. We first "fixed" this by dropping `idx_inv_date_sk`, which
was tipping the choice — and it worked, until an `OPTIMIZE TABLE` re-sampled
the statistics and the bad plan came back **with that index already dropped**.
The two paths cost almost the same at `sample_pages=160`, so the winner is
decided by which pages the last `ANALYZE` happened to read: **a 28-second
swing on a ~430s suite, settled by chance.** Pinning the path is the only
thing that makes it reproducible.

### 7.4 q88 — ~130x, and the opposite lesson to q72

| configuration | time |
|---|---:|
| original, no index | 29.8–36.0s |
| original + covering index | 1.4s |
| single-pass rewrite, no index | 4.2s |
| **both** | **0.2–0.3s** |

**8x from the rewrite, 25x from the index, ~130x together.** Where q72's
ablation showed one ingredient carried everything, q88's two ingredients
compose. And q22's ablation showed a third pattern — *no* ingredient is good
alone (the hint by itself made it **worse**, 23.0s → 29.6s) and only all three
together win. **How optimizations interact has to be measured per query, never
assumed.**

### 7.5 q66 — a 7–10x win that nearly vanished without anybody noticing

Two covering indexes, `idx_cs_q66` and `idx_ws_q66`, existed only on the
*running databases* — created by an experiment script and never written into
`sql/`. They survived on one volume and vanished when another was rebuilt from
the schema:

| query66 at SF=4 | |
|---|---:|
| with them | 1.0–1.1s |
| without them | 7.4–11.6s |

Anyone reproducing this work from the schema scripts would have been 7–10x
slower on q66 with nothing to explain it. They are now in
`sql/14_contributed_indexes.sql`, and the build asserts the database's index
set matches `sql/` **by name** after every run.

### Other notable wins

| query | from | to | what did it |
|---|---:|---:|---|
| q95 | >300s (capped) | 0.1s | one index on `ws_order_number` |
| q5 | 78.2s | 1.0s | riccio's rewrite (after fixing `PIPES_AS_CONCAT`) |
| q39 | 92.5s | 0.6s | hiding two `inventory` indexes + rewrite |
| q2 | 84s | 25.9s | push a date window into both union arms |
| q82 | 0.8s | 0.1s | existence-only joins → `EXISTS` |
| q70 | 11.6s | 3.6s | delete a rank subquery that filters nothing (see the NULL-rollup note in §5.2c) |

---

## 8. Observations: what worked, what did not

### 8.1 Page size: a large result that was entirely an artefact

At SF=1, `innodb_page_size=32K` beat 16K by **1.54x** across 99 queries, with
42 of 60 measurable queries fastest at 32K. A clear, reproducible result across
two passes.

At SF=4 it **vanished**: 4004.6s vs 4050.3s, 1.1% apart — inside the run-to-run
noise. Worse, the per-query winners *inverted*. q53, q63 and q89 were 32K's
three largest wins at SF=1 (10x or better) and became its three largest losses
at SF=4 (about 3x).

The reason: at SF=1 the 9 GB database sits in an 8 GB pool, so there is
essentially no I/O for page size to govern. What 32K was actually buying was
**better statistics** — a 32K page holds twice the entries, so the same 20-page
sample covered twice as many rows. The date-first covering-index plan that
better statistics produced is excellent when the index is resident and poor
when reading it means real I/O.

**Lesson: benchmark at a scale where the data does not fit.** Every page-size
finding measured on a cached database reversed or vanished when it did not.
This is also why SF=8 was worth the 85 minutes it took to build.

### 8.2 `ALTER INDEX … IGNORED` is not inert, and that invalidated an approach

The documented, advertised way to test whether an index is needed is to hide
it. It is metadata-only. But **InnoDB re-samples the whole table's persistent
statistics on that statement** — with `innodb_stats_auto_recalc=OFF`, and with
no way to suppress it. One `ALTER … IGNORED` on `catalog_sales` changed **85
rows** of `mysql.innodb_index_stats`.

Consequences:

- Hiding one `catalog_sales` index appeared to move **37 of 44 query plans**.
- Capturing plans twice *in the same hidden state* — a net no-op — moved **19**.
- Writing the old statistics back does not help: InnoDB keeps the re-sampled
  values in memory, and neither `FLUSH TABLE`, `FLUSH TABLES` nor
  `ALTER … STATS_PERSISTENT=1` makes it re-read them.
- Raising the sample to 4000 pages made `ANALYZE` 10x slower and left the noise
  at 31 of 44. **It is not a precision problem.**

**The general consequence is larger than the experiment: any index DDL
re-rolls plan choice.** Creating or dropping an index forces a re-sample, and
at this scale the re-sample alone changes plans. Every before/after index
experiment carries that confound — including our own 735.2s → 1487.0s.

The method that works is **per-statement index hints**, which touch no
metadata and re-sample nothing.

### 8.3 A suite total is only as stable as its least stable query

We published a server-tuning figure of **2.90x**. It was optimistic by 17%.
T1's total contained q59 at 15.3s; in twelve subsequent runs q59 measured
152–187s with byte-identical output. Re-measured, T1 is **2.47x**.

q59 flips between two plans — its CTE is referenced twice, and one reference is
re-materialised **7,665 times**, 164s of a 167s query. One query swinging 140s
on a ~900s total is 15%, wider than most of the effects being compared. **A
benchmark containing a plan-unstable query cannot resolve a 5–10% difference.**

### 8.4 The data is twice the size of the generated text, and the obvious fix is wrong

SF=4 generates 4.2 GB of `.dat` and loads to 8.87 GB. With exact row counts the
cause is unambiguous:

| table | rows | text B/row | InnoDB B/row | user data + 18B header | page fill |
|---|---:|---:|---:|---:|---:|
| store_sales | 11,516,885 | 137 | 244 | ~116 | **48%** |
| catalog_sales | 5,763,962 | 208 | 334 | ~154 | 46% |
| inventory | 36,019,566 | 20.5 | 73.6 | ~36 | 49% |

InnoDB adds ~18 bytes per row of hidden columns (6-byte transaction id, 7-byte
roll pointer, 5-byte header) — which on `inventory`, whose rows are four
integers, more than doubles the row. And leaf pages are only ~48% full,
because the load order does not match the clustered key (§1.1).

`OPTIMIZE TABLE` reclaims it exactly as predicted — data **8.87 → 6.36 GB**,
indexes unchanged, 12 minutes. **We rejected it anyway.** It rewrites the table
in primary-key order, and q22 goes from ~11s to 38.1s warm because the plan
flips. 2.5 GB bought with a plan regression on a database this
statistics-sensitive is a bad trade. The fix that would give compactness *and*
date locality is a **date-leading primary key** — a schema change we have not
tried.

### 8.5 Techniques that failed, and why the failures were informative

**The dense-key substitution (§5.2a) failed on 5 of 11 queries.** It paid when
it *unlocked something else* — on q35 it left each `EXISTS` naming exactly two
columns carried by an existing index, making them index-only probes. It cost
when it stood alone: on q38, q66, q71, q77 and q87 it removed a per-row
dimension probe that was never the bottleneck while handing the optimizer a
different access path, and on four of the five it chose worse. q38 and q87 have
the same shape and regressed by the same 0.80x, which rules out noise.

**A redundant predicate is not free.** q66 was split into two versions to find
which half hurt. Key aggregation alone measured 1.01x; key aggregation *plus a
redundant range predicate* measured 0.91x. The predicate admits only rows the
join already admits — it reads like a free hint, and it is not.

**An index that looked obvious was 10x wrong.** `date_dim(d_month_seq)` —
several queries filter on it, no index existed. Adding it took q59 from 1.2s to
**12.7s**. Three-pass confirmed. It is recorded as *rejected* in
`sql/11_optimizer_indexes.sql` so nobody adds it again on the same reasoning.

**Symmetry in a query does not imply symmetry in the payoff.** A seven-column
covering index on `store_sales` took q78 from 11.4s to 8.5s. The identical idea
on `catalog_sales`, its second-most expensive CTE, contributed **nothing** —
and combined with the first was marginally *worse*. Built, measured, dropped.

**Two of our rejections were beaten by someone else.** q65 and q87 — exactly
the two where our rewrite failed. On q65 our premise was simply false (we
assumed a duplicated derived table was computed twice; MariaDB already
materialises it once). On q87 the diagnosis was right and the remedy was aimed
at the wrong place.

**A faster query on a smaller database can be slower on a larger one.** Nafiz's
q23 is 38x at SF=1 and **2.1x slower at SF=4**. His pruning is not weak, it is
*perfect* — at SF=4 there are 9 best customers and 0 candidate items. MariaDB
does not exploit that: the driving scan is unchanged at 11.5M index entries,
and the semi-join adds a probe for every one of them. An empty set
short-circuits each probe and never avoids the scan.

### 8.6 Measurement discipline — what we had to learn

Each of these produced a confident, plausible, wrong answer first. Full
write-up in [`report/29-measuring-indexes.md`](report/29-measuring-indexes.md).

| # | trap | what it cost |
|---|---|---|
| 1 | Buffer pool at 4% of the database | a headline "2.06x" that was really 1.01x |
| 2 | One A/B pair cannot separate effect from drift | within-condition spread (47.9s) exceeded the effect (14.3s); both orderings were observed pointing opposite ways |
| 3 | A single-run number is mostly cold cache | "8 of 40 queries regressed" — q68 read 7.4s cold and **3.2s** warm |
| 4 | A rebuilt database is a different benchmark | same data, same queries, same settings: **735.2s vs 454.4s** |
| 5 | A stale index list silently measured the wrong config | a run labelled "full index set" had 48 indexes hidden, and reported a clean, plausible, false +18% |
| 6 | A guard requiring *exactly* 25 tables | two scratch tables made it 27, and it dropped and reloaded 32 GB |
| 7 | Prefixing `EXPLAIN` to "the query" | q14/23/39/67 are two statements each, so half of each ran for real — one part-B executed 58s inside a planning-only pass |
| 8 | `\|\|` is logical OR without `PIPES_AS_CONCAT` | q5 and q80 returned **7 rows instead of 100**, with no error, for an unknown number of runs |

Trap 8 deserves its own note: it meant **riccio's q5 was being measured on a
degenerate query** (both sides returned 7 rows, so the grouping work that
dominates the real q5 never happened), and **Aysha's q80 was being scored
against a broken original** — her translation was correct and the "before" was
wrong, so the reported 6.5x was an artefact. The honest figure is 3.0x.

### 8.7 Things that are still open

- **Raise `innodb_buffer_pool_size`** and re-measure SF=8. §6 locates the
  break; nothing tests the remedy.
- **A date-leading primary key** on the fact tables (§8.4) would give
  compactness and locality together.
- **Partitioning** is explicitly permitted by Clause 2.5.3.8 on date columns
  and date surrogate keys, which is exactly the access pattern TPC-DS
  exercises. Never tried.
- **q59's plan instability** (§8.3) is understood but not fixed; item 5 of the
  tuning list is worth revisiting only after it is.
- **16K pages with deep sampling** was never measured at SF=4.

---

## 9. Reproducing

Everything runs in a Linux container; the repository is mounted read-only.

```sh
./reproduce.sh smoke                      # low-memory install check
./reproduce.sh                            # SF=1, 40 queries
./reproduce.sh full                       # SF=4
./reproduce.sh full SCALE=8 PRUNE_INDEXES=1
```

| knob | effect |
|---|---|
| `SCALE` | scale factor; data generated with `-RNGSEED 10` |
| `PRUNE_INDEXES=1` | build the validated 95-index set instead of all 166 |
| `QUERYSET=tier45` | the unoptimized TPC-DS text, to isolate the rewrites |
| `TUNED=baseline` | stock server settings, to isolate the configuration |
| `IGNORE_UNUSED=1` | hide an index list instead of dropping it |

The build **asserts** its own state: the index set is compared against `sql/`
by name in both directions after every run, the standing configuration is
checked setting by setting (13/13), and a run that cannot produce results fails
loudly rather than reporting a clean total.

| artefact | what it is |
|---|---|
| `sql/drop_unreferenced_indexes.sql` | the validated 71 drops |
| `sql/ignore_unreferenced_indexes.sql` | the same set, reversibly hidden |
| `analysis/index-decisions.md` | every index, kept or dropped, with the reason |
| `scripts/index-consulted.py` | the `possible_keys` classifier |
| `scripts/index-harm-scan.py` | finds indexes that make queries slower |
| `scripts/plan-sensitivity.py` | the hide-and-diff method, with its noise filter |
| `report/25-query-by-query.md` | all 40 queries × 4 scale factors, with notes |
| `report/29-measuring-indexes.md` | the twelve measurement traps, in full |

---

## 10. Limitations

1. **Not a TPC result.** Unaudited; SF=1–8 are not publishable scale factors;
   `dsdgen` itself warns that SF=2 and SF=8 are not valid for result
   publication.
2. **One machine, and a loaded one.** A 16 GiB Apple Silicon host with 12 GiB
   given to the Docker VM. It was swapping 12–14 GB for much of the final
   session, which inflates absolute timings. **Paired and alternating
   comparisons survive that; absolute numbers quoted across sessions do not.**
3. **Single runs at each scale factor in §6.** The configuration is identical
   across all four and the growth pattern is consistent, but no scale factor
   was repeated. The 2.27x → 3.87x break is far outside this host's noise; the
   individual per-query ratios are single measurements.
4. **Not all figures come from the same environment.** §3 and parts of §5 were
   measured on the macOS host during earlier phases; §6 and §5.4 are from the
   container. They are not interchangeable — the same full index set measured
   735.2s on an accumulated volume and 454.4s on a freshly built one. Each
   comparison in this report is internally paired; totals from different
   phases should not be divided against each other.
5. **q71's output order is not deterministic.** Its `ORDER BY` is not a total
   order — 2,160 of 3,948 rows share a sort key at SF=4 — so it cannot be
   compared by checksum. It is verified on sorted checksum instead.
6. **The 5 unoptimized queries are not unexamined.** Each was rewritten and
   measured; each rewrite was slower and is kept with its measurement.
7. **q70's measurements predate its correctness fix.** The four-scale run in
   §6 used the adopted q70 as it stood before the NULL-rollup correction
   (§5.2c) was merged. Its figures — 1.6s / 2.9s / 5.7s / 40.0s — are for the
   earlier text. The corrected query restores a `date_dim` join and replaces
   `ROLLUP` with explicit `UNION ALL` levels, so it will not be faster; q70
   is 1.4% of the SF=4 total, so the suite totals move little, but **the q70
   row specifically should be re-measured** before being quoted. No other
   measured query changed: q22's `FORCE INDEX` was committed 26 hours before
   the run.
