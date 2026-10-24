# Page size at SF=4: the SF=1 result does not generalise

Report 20 measured page size at scale factor 1, where the 9 GB database sits
in an 8 GB buffer pool and there is almost no I/O for page size to govern. It
closed with the caveat that the result "should not be extrapolated to a larger
dataset without re-measuring".

This is that re-measurement, at **SF=4**: a 32 GB database against the same
8 GB pool, so roughly **4x more data than memory**. Two instances, 16K (the
default) and 32K (the winner at SF=1), identical in every other respect.

## Correction to the SF=1 column

The 16K/SF=1 instance used here carried **182 indexes, not 188** — it was built
before `sql/11_optimizer_indexes.sql` was added to the build script, and only
the 32K copy was backfilled. Its SF=1 number is therefore not a like-for-like
comparison. Re-measured with both at 188 over tier 4+5, 32K is **1.95x** faster
at SF=1, not 1.54x. See `report/22-unused-indexes-by-configuration.md`.

The SF=4 figures below are unaffected: both SF=4 instances carried 188 indexes.

## Headline

| | SF=1 | SF=4 |
|---|---:|---:|
| 16K | 645.4s | **4004.6s** |
| 32K | 419.1s | **4050.3s** |
| winner | 32K by **1.54x** | 16K by **1.01x** |

**The page-size advantage disappears.** 1.1% apart at SF=4 is inside the
3.8–8.0% run-to-run variation measured in report 20, so the two are
indistinguishable. Whatever 32K was buying at SF=1, it does not survive
contact with a working set that exceeds memory.

Note also how differently the two scale. 4x the data costs:

| page | SF=1 → SF=4 |
|---|---:|
| 16K | **6.0x** |
| 32K | **9.7x** |

32K degrades substantially worse. Its SF=1 lead was not a durable property —
it was a head start that the larger dataset erases.

## The per-query winners invert

45 of the 80 measurable queries still differ by more than 20% between page
sizes at SF=4 — but the sign flips for the ones that mattered most.

| query | SF1 16K | SF1 32K | SF4 16K | SF4 32K |
|---|---:|---:|---:|---:|
| q89 | 7.1s | **0.7s** | **17.9s** | 56.8s |
| q63 | 7.5s | **0.5s** | **14.8s** | 41.5s |
| q53 | 7.4s | **0.6s** | **16.0s** | 44.5s |
| q66 | 1.1s | **1.0s** | **4.7s** | 15.3s |
| q62 | **0.5s** | **0.5s** | **2.1s** | 6.5s |

q53, q63 and q89 were 32K's three largest wins at SF=1 — 10x or better. At
SF=4 they are 32K's three largest losses, by about 3x. These are the queries
whose plans 32K's coarser statistics steered toward a `date_dim`-first
covering-index scan (report 20). That plan is excellent when the index is
resident in memory and poor when reading it means real I/O.

A handful go the other way (q40 4.91x, q81 3.44x, q45 3.07x in 32K's favour),
which is why the totals cancel out to a wash rather than a clear loss.

q72, the query report 20 singled out as the one genuine page-size effect,
narrows sharply:

| | 16K | 32K | ratio |
|---|---:|---:|---:|
| SF=1 | 55.4s | 2.6s | **21x** |
| SF=4 | 240.1s | 186.8s | **1.28x** |

So that effect was not a page-size property either. It was the same
statistics-driven plan difference, amplified at SF=1 by everything fitting in
memory.

## What this means

1. **Do not change page size for this workload.** At the scale where page size
   should matter — data larger than memory — the two are within noise of each
   other, and 32K scales worse. The SF=1 result was an artefact of measuring a
   fully-cached database.
2. **Report 20's conclusions hold only at SF=1.** Both its original
   recommendation and its revised one were reasoning from a cached workload.
   The honest summary across both reports: page size did not matter; what
   moved was the optimizer's plan, and which plan wins depends on whether the
   data is resident.
3. **Plans tuned on a cached database are not transferable.** The
   date-first covering-index plan is 10x better cached and 3x worse uncached,
   on the same queries. This applies directly to the hand optimizations in
   report 19 — all were tuned at SF=1, and q53/q63/q89 show exactly how such a
   plan can invert.
4. **Benchmark at a scale where the data does not fit.** This is the clearest
   lesson. Every page-size and statistics finding in report 20 was measured on
   a database that fit in RAM, and most of them reversed or vanished here.

## Method

- SF=4 generated with `dsdgen -SCALE 4` into `DSGen-software-code-4.0.0/data-sf4`
  (4.3 GB, 5m21s). dsdgen warns `Selected scale factor is NOT valid for result
  publication` — fine for an experiment, not a publishable TPC-DS number.
- Separate instances on ports 3500+KB, datadirs `pagesize/data-<P>k-sf4`, so
  nothing at SF=1 was touched.
- Same 8 GB pool, same 188 indexes (`05` + `11` + `14`), default statistics
  sampling, `ANALYZE TABLE` after build, each started cold.
- `max_statement_time` raised from 300s to 3600s. At SF=4 several queries
  legitimately exceed 300s, and a query killed by the cap records a censored
  time that would corrupt the comparison. Client timeout 5400s.
  **SF=4 totals are therefore not directly comparable to SF=1 totals** — only
  the 16K-vs-32K ratio within SF=4 is.
- Build cost: 16K load 321s / index 1362s; 32K load 326s / index 1495s.
  Datadirs 31 GB and 32 GB.
- 99/99 queries completed with no errors on either instance.

### One answer discrepancy, resolved

query71 returned a different md5 on 16K than on 32K — the first such
difference in 14 configurations. It is not a correctness problem: re-running
the query on both instances produced byte-identical output, and **2160 of its
3948 rows share an `(ext_price, i_brand_id)` key**, so
`ORDER BY ext_price desc, i_brand_id` leaves more than half the result
unordered and the server may return ties in any order. At SF=1 the query
returns 1005 rows and the ties happened not to reshuffle.

This is a defect in the query, not the engine: TPC-DS queries whose ORDER BY
is not a total order cannot be compared by checksum. Only q71 is affected
among the 99.
