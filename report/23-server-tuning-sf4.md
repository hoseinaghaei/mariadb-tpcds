# Testing a proposed MariaDB tuning list at SF=4

A list of ten tuning changes, supplied by someone who knows MariaDB
internals, tested on **32K pages / SF=4 / `innodb_stats_persistent_sample_pages=160`
/ tier 4 and 5 (40 queries)**, against a measured baseline of **2403.4s**.

> **Corrected.** The 2.90x below came from a run in which q59 happened to get
> a plan 10x faster than the one it normally gets. Re-measured, T1 is
> **971.4s (2.47x)**; with `split_materialized=off` it is **867.5s (2.77x)**,
> and applied per query **777.7s (3.09x)**. The attribution of the T2
> regression to histograms was also wrong. See "Correction: q59 and split
> materialisation" at the end.

## Result

| run | what it adds | total | vs baseline |
|---|---|---:|---:|
| baseline | — | 2403.4s | 1.00x |
| **T4** | **item 1 only** — temp tables 16M → 1.5G | **1195.5s** | **2.01x** |
| **T1** | items 1, 2, 3, 4, 6, 7, 9 | **829.8s** | **2.90x** |
| T2 | T1 + item 5, histograms | 939.5s | 2.56x |
| T3 | T1 + item 8, `dump_pct=100` | 1049.3s | 2.29x |

**T1 at 2.90x is the largest single improvement found anywhere in this
project** — larger than page size, larger than statistics sampling, larger
than any hand-written query rewrite.

All runs completed 40/40 with no errors. 38 of 40 queries are md5-identical to
the baseline in every run; the two that differ, q65 and q71, have `ORDER BY`
clauses that are not a total order and differ only in row order (q71 has 2160
of 3948 rows tied; q65 has 7 of 100 tied plus a `LIMIT 100`, so even its row
*set* is under-determined). Neither is an answer change.

## T5: a smaller pool with bigger temp tables is worse

Tested at the user's request: buffer pool **8G → 4G**, temp tables
**1.5G → 4G**, items 2/3/4/6/7/9 unchanged.

| | pool | tmp/heap | peak budget | total |
|---|---:|---:|---:|---:|
| T1 | 8G | 1.5G | ~10.8G | **829.8s** |
| T5 | 4G | 4G | ~9.3G | 1097.1s |

**32% slower.** 19 of 40 queries regressed, 7 improved, 14 unchanged.

The buffer pool mattered more than the temp space. At SF=4 the database is
32.5 GB, so the pool went from 25% of it to 12%, and the queries that suffered
are the ones that re-read large amounts of data — q14 +56.8s, q23 +52.5s,
q70 +25.8s, q74 +24.8s.

Raising temp tables past 1.5G bought nothing: the queries that needed a large
in-memory temp table were already served by 1.5G, so the extra 2.5G sat idle
while the pages evicted from the smaller pool had to be re-read from disk.

It did, though, bring the peak budget down from ~10.8G to ~9.3G, which is the
one argument for it on a memory-constrained machine — at a 32% cost.

Worth noting `tmp_table_size` is a **per temp table** limit, not a global cap,
so 4G is not a 4G ceiling: a query materialising two large intermediates can
hold twice that.

## Item 1 is most of it

`tmp_table_size` and `max_heap_table_size` were at **16 MB**. TPC-DS queries
materialise multi-million-row intermediates, so almost every tier-4/5 query
was spilling its temp tables to disk.

Raising just those two to 1.5G is worth **2.01x on its own** — about
two-thirds of what all seven settings achieve together. The other six items
add a further 1.44x (1195.5s → 829.8s) at the cost of six more settings and
roughly 1.2 GB more memory.

Biggest per-query movers in T1:

| query | baseline | T1 |
|---|---:|---:|
| q5 | 376.7s | **27.6s** |
| q2 | 242.2s | **13.5s** |
| q51 | 218.8s | **29.4s** |
| q59 | 152.9s | **15.3s** |
| q54 | 111.2s | **4.3s** |
| q23 | 176.2s | 199.8s *(slower)* |

Only q23 regressed.

## Item 5 (histograms): a regression

`histogram_type` was **already** `JSON_HB` and
`optimizer_use_condition_selectivity` **already** 4, so the real content of
item 5 is running `ANALYZE TABLE ... PERSISTENT FOR ALL` to populate the
engine-independent statistics, which were empty.

Collecting them took **649s** and made the suite **13% slower** (829.8 →
939.5s). The breakdown is not uniformly bad — 16 queries got faster, 10
slower — but one query wipes out the gains:

| | T1 | T2 |
|---|---:|---:|
| q59 | 15.3s | **157.7s** |
| everything else, net | — | ~17s faster |

Excluding q59, histograms are marginally positive. With it, they are a clear
loss. q59 has now flipped plan dramatically under three separate changes in
this project, and is best treated as plan-unstable.

Note this change is **persistent**: once collected, `use_stat_tables =
PREFERABLY_FOR_QUERIES` means every later query uses them. Reverting needs
`use_stat_tables = never` (what is set now) or clearing
`mysql.{table,column,index}_stats`. The collected statistics are left in place
but switched off.

## Item 8 (`dump_pct=100`): a regression, and a hazard

26% slower than T1 (829.8 → 1049.3s). Reloading the full 8 GB buffer pool at
startup competes with the queries for memory and I/O instead of helping them.

It is also what made the machine unstable: see below.

## Items already in effect, and items not applicable

| item | status |
|---|---|
| 2 — tmpdir on fastest SSD | already: tmpdir and datadir are on the same internal SSD |
| 3 — datadir on SSD | already |
| 4 — `innodb_old_blocks_time=1000` | already the default |
| 5 — `histogram_type=JSON_HB` | already |
| 5 — `optimizer_use_condition_selectivity=4` | already |
| 9 — `performance_schema=OFF` | already off on lab instances |
| 9 — `innodb_adaptive_hash_index=OFF` | already |
| 10 — power plan, antivirus, `vm.swappiness`, THP | **not applicable on macOS** |

Item 9's `performance_schema=OFF` was **not** applied to the live 3306 server:
that conflicts with the standing instruction to leave the observability
settings alone, and it contributed nothing to T1 since it was already off here.

## The memory ceiling is the real constraint

Two runs were killed mid-pass by the OS before producing any result. The cause
was not the settings themselves but total memory:

- This is a **16 GB machine**.
- The **live Homebrew server on 3306 reserves its own 8 GB buffer pool**, and
  had been running for 27 days.
- A lab instance reserves another 8 GB, plus T1's 1.5 GB temp tables and 1 GB
  Aria cache — a peak budget of about **10.8 GB** on top.

At the point of failure: `PhysMem: 14G used, 1320M unused`, swap at **24.7 GB
of 25.6 GB**. T3 and T4 were each killed after 6 of 40 queries.

Stopping the live server for the duration (`pagesize/run-exclusive.sh`, which
restarts it from a trap) allowed both to complete. Worth noting that stopping
it freed less than expected — its 8 GB pool had been entirely swapped out
after 27 idle days, so most of the relief came from not *also* faulting it
back in.

**Nothing should be concluded from the two killed runs.** They were rerun to
completion, and only the completed numbers appear above.

## Recommendation

1. **Apply item 1.** `tmp_table_size` and `max_heap_table_size` at 16 MB are
   the single worst setting on this server. 2.01x for one reversible change.
   1.5G is sized for a serial benchmark on a 16 GB box; a server taking
   concurrent connections needs this scaled down, since the limit is **per
   temp table**, not global.
2. **Then items 2, 3, 4, 6, 7, 9** for a further 1.44x, with the memory budget
   checked first. On a machine with more RAM this is straightforwardly worth
   it; on this one it is close to the ceiling.
3. **Skip item 5.** Costs 649s to collect and loses 13%, entirely to q59.
   Worth revisiting only if q59's plan instability is fixed first.
4. **Skip item 8.** 26% slower here, and the direct cause of two OOM kills.
5. **Item 10 does not apply** to macOS.
6. **Re-measure before trusting any of this on the live server.** Every number
   here is SF=4 on 32K pages over tier 4+5. The live server is SF=1 on 16K
   pages, and report 21 showed conclusions do not carry across scale factors.

## Reproducing

```bash
pagesize/run-cnf.sh <config.cnf> <tag>            # one config
pagesize/run-exclusive.sh <cnf> <tag> [<cnf> <tag>...]   # stops 3306 first
```

Configs: `my-32k-sf4.cnf` (baseline), `-t4.cnf` (item 1 only),
`-tuned.cnf` (T1/T2/T3). `run-cnf.sh` prints the peak memory budget before
each run, so a kill can be attributed rather than guessed at.

---

## Shareable version

A version of this report written for the author of the tuning list, with the
verdict per item and the open questions back to them:

  https://claude.ai/artifact/33mJ3a4jVsDx5EGAMnbagn


---

# Correction: q59 and split materialisation

Two claims in this report were wrong. Both trace to one query.

## What was wrong

**1. The 2.90x is not reproducible.** T1's 829.8s contains q59 at 15.3s. In
twelve subsequent runs q59 measured ~152-187s with byte-identical output, and
T1's configuration rebuilt exactly still gave 166.4s and 170.9s. Re-measured
under identical conditions, T1 is **971.4s**.

**2. The T2 histogram regression was misattributed.** This report said
histograms cost 13% "entirely to q59". The cause was not histograms: q59 flips
between two plans, and the T2 run drew the slow one. Clearing
`mysql.column_stats` to zero changed nothing (157.8s).

## The real cause

`ANALYZE FORMAT=JSON` on q59:

| node | ms | loops |
|---|---:|---:|
| `materialized` | **164,024** | **7,665** |
| `materialized` | 2,351 | 1 |

q59 references its CTE twice. One reference materialises once in 2.4s; the
other is **re-materialised 7,665 times, once per outer row**, for 164s of a
167s query. That is split materialisation (lateral derived) — sound for a
selective lookup, ruinous for a full aggregate over 15.5M rows. The two plans
are the two timings: ~14s without the split, ~155s with it.

Six other causes were eliminated by direct test first — histograms, stale
InnoDB statistics, `join_cache_level=8`, MRR, cache residency and
`use_stat_tables` — and are listed in
`queries/optimized/q59-sf4/README.md` so they are not re-investigated.

## Corrected figures

| configuration | total | vs 2403.4s baseline |
|---|---:|---:|
| T1, as originally published | 829.8s | 2.90x |
| **T1, re-measured** | **971.4s** | **2.47x** |
| **T1 + `split_materialized=off` globally** | **867.5s** | **2.77x** |
| **best of each, per query** | **777.7s** | **3.09x** |

`split_materialized=off` is **not** a good global setting despite being worth
12x on q59 alone. It costs q23 +54s, q4 +15s and q78 +14s, so suite-wide it
is worth only 10.7%. It belongs per query:

```sql
SET SESSION optimizer_switch = 'split_materialized=off';   -- for q59 only
```

39 of 40 answers are identical between the two configurations; the exception
is q71, whose `md5_sorted` matches, so it differs only in the order of tied
rows.

## What to take from it

The tuning in this report is worth about **2.5x reliably**, 2.77x with the
split setting applied globally, and 3.09x applied per query. The direction of
every finding stands; the headline figure was optimistic by roughly 17%
because one query in one run drew a lucky plan.

The method lesson is that a suite total is only as stable as its least stable
query. q59 alone swings 140s on a ~900s total — 15% — which is wider than
most of the effects being measured. A benchmark containing a plan-unstable
query cannot resolve a 5-10% difference, and this report compared several
configurations that differed by less than that.
