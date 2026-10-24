# Which indexes go unused, and why the answer keeps changing

Four configurations, all carrying the same **188 indexes with none ignored**,
all measured over the **tier 4 and tier 5 queries only** (40 of the 99 — the
expensive ones; tiers 1–3 are sub-second and their timings are dominated by
connection and parse overhead).

`userstat` on, `FLUSH INDEX_STATISTICS` immediately before each run so the
counters cover exactly those 40 queries. `INDEX_STATISTICS` lists only indexes
with a non-zero read count, so "unused" is the full index list left-joined
onto it — anything absent was never read.

| configuration | sampling | total | unused | used |
|---|---:|---:|---:|---:|
| 32K / SF=1 | 20 | 382.0s | 129 | 59 |
| 16K / SF=1 | 20 | 745.4s | 129 | 59 |
| 32K / SF=4 | 160 | 2403.4s | 126 | 62 |
| 16K / SF=4 | 160 | 2548.6s | 131 | 57 |

## The headline: 20 indexes flip

| | count |
|---|---:|
| unused in **all four** configurations | **119** |
| **used in some, unused in others** | **20** |
| used in all four | 49 |

Only 49 of 188 indexes are reliably earning their keep. 119 are dead weight
everywhere. The interesting 20 are the ones an audit would get wrong.

| index | 32K SF=1 | 16K SF=1 | 32K SF=4 | 16K SF=4 |
|---|---:|---:|---:|---:|
| `store_sales.idx_ss_date_store_price` | **UNUSED** | 27,973,753 | 356,964,581 | 349,070,546 |
| `store_sales.idx_ss_sold_date_sk` | 21,704,607 | **UNUSED** | 87,023,076 | **UNUSED** |
| `store_sales.idx_ss_date_cust` | **UNUSED** | **UNUSED** | 8,211,559 | 59,815,017 |
| `date_dim.idx_date_dim_d_date_year` | 8,662,308 | 2,357 | 53,678,034 | **UNUSED** |
| `store_sales.idx_ss_date_item_store_cover` | 29,058,695 | **UNUSED** | **UNUSED** | **UNUSED** |
| `catalog_sales.idx_cs_sold_date_sk` | **UNUSED** | 1,431,670 | 25,056,246 | **UNUSED** |
| `web_sales.idx_ws_sold_date_sk` | **UNUSED** | **UNUSED** | 21,449,062 | 8,598,360 |
| `web_sales.idx_ws_date_item_price` | **UNUSED** | 5,362,597 | **UNUSED** | 12,857,381 |
| `inventory.idx_inv_warehouse_sk` | **UNUSED** | 11,745,000 | **UNUSED** | **UNUSED** |
| `store_sales.idx_ss_sold_date_sk_store_sales_price` | 2,505,694 | **UNUSED** | **UNUSED** | **UNUSED** |

(ten more flip at lower volumes: `idx_ss_cdemo_sk`, `idx_ss_customer_sk`,
`idx_inv_item_date_sk`, `idx_date_year_sk`, `idx_ss_item_sk`, `idx_item_1`,
`idx_ss_cust_date`, `idx_cs_item_sk`, `idx_date_ym`, `idx_ws_bill_customer_sk`)

## The one that matters most

`store_sales.idx_ss_date_store_price` is **never touched at SF=1 on 32K** and
reads **357 million rows at SF=4**. It is the single most-read index in the
whole experiment.

An audit run the way report 15 ran it — one configuration, look for zero reads,
drop what you find — would have flagged this index as dead and recommended
dropping it. At SF=4 that would have been the most damaging change available.

This is the concrete mechanism behind report 17's warning that never-read
indexes are not safe to drop. It is not that the measurement is unreliable; it
is that "unused" is a property of a *configuration*, not of an index.

## What changes the answer

All four configurations run identical SQL against identical data with identical
indexes. The only differences are page size, scale factor, and statistics
sampling — and each one moves the set:

- **Scale factor.** `idx_ss_date_store_price` and `idx_ss_date_cust` are dead
  at SF=1 and heavily used at SF=4. `idx_ss_date_item_store_cover` is the
  reverse: 29M reads at SF=1, untouched at SF=4. When the data stops fitting in
  the buffer pool the optimizer wants different access paths, so it reaches for
  different indexes.
- **Page size.** At SF=4 with identical sampling, `idx_ss_sold_date_sk` reads
  87M rows on 32K and nothing on 16K; `idx_ws_date_item_price` is the reverse.
  Same data, same queries, same statistics depth — different plan.
- **Statistics sampling.** Changing it alone reshuffles plans (report 20), and
  therefore reshuffles which indexes get read.

## A result that arrived sideways

The 16K/SF=1 instance was initially built without
`sql/11_optimizer_indexes.sql` — 182 indexes rather than 188. Backfilling the
six missing indexes and re-running gave:

| 16K / SF=1, tier 4+5 | total |
|---|---:|
| 182 indexes | 532.8s |
| 188 indexes | **745.4s** |

**Adding six indexes made it 40% slower.** The same six were worth +9% on 32K.
Nothing was removed and no query was changed; the optimizer simply had more
options and chose worse ones. This is the clearest single demonstration in the
project that an index is not a free addition — it is an extra branch in the
optimizer's search, and more branches is not better.

It also means the SF=1 column of `report/21-page-size-at-scale.md` compared
mismatched index sets (16K at 182, 32K at 188). With both at 188 over tier 4+5,
**32K is 1.95x faster than 16K at SF=1** — a wider gap than the 1.54x reported
there, though report 21's central finding is untouched, since its SF=4
instances both carried 188.

## What to do with this

1. **Never drop an index on single-configuration evidence.** 20 of 188 flip,
   and the one with the largest flip is the most-read index in the benchmark.
   `sql/06_drop_unused_indexes.sql` should stay unexecuted, and its "TEST
   BEFORE YOU DROP" warning is now backed by a measured counterexample.
2. **Prefer `ALTER INDEX ... IGNORED` over `DROP`.** It is metadata-only,
   reversible in about 0.15s, and lets a wrong call be undone before it costs a
   rebuild. The 119 unused-everywhere indexes are the defensible candidates —
   and even those were measured on 40 queries, so a tier-1 query may depend on
   one.
3. **"Unused" here means unused by tier 4 and 5.** That is a narrower claim
   than report 15's full-99 audit, and a weaker basis for removal.

## Reproducing

```bash
pagesize/index-usage.sh <PAGE_KB> <SF>                   # default sampling
pagesize/index-usage-sampled.sh <PAGE_KB> <SF> <SAMPLE>  # with re-ANALYZE
```

Each writes `pagesize/results/idxuse-<P>k-sf<SF>[-stats<N>].tsv`:
table, index, rows read, used/UNUSED.
