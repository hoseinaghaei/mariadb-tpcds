# Does the SF=4 tuning help at SF=1?

Yes — **2.94x**, slightly more than it is worth at SF=4, and far more cleanly.

The tuning in `report/23-server-tuning-sf4.md` was measured entirely at scale
factor 4, where the database is ~4x larger than the buffer pool. Report 21
had already shown that page-size conclusions do not survive a scale change,
so there was no reason to assume these would either. This tests it directly.

## Setup

Three runs of the same 40 tuned tier-4/5 queries
(`queries/tuned/`, fed whole so their `SET SESSION` lines apply):

| run | scale | pages | configuration |
|---|---|---|---|
| **A** | 4 | 32K | the SF=4 tuning, sample 160 |
| **B** | 1 | 32K | stock — 16M temp tables, `join_cache_level=2`, sample 20 |
| **C** | 1 | 32K | **byte-identical to A** |

B and C run against the same SF=1 datadir with the same 188 indexes and
differ only by the tuning block, so C-vs-B isolates the configuration.

## Result

| run | total | |
|---|---:|---|
| A — SF=4, tuned | 942.1s | |
| B — SF=1, stock | 464.5s | |
| **C — SF=1, tuned** | **157.8s** | |

| comparison | |
|---|---|
| **C vs B** — the tuning at SF=1 | **2.94x faster** |
| A vs C — scale factor, configuration held constant | 5.97x slower at SF=4 |

Zero errors in all three. **B and C agree on all 40 answers, byte for byte.**

## It is broad, not one query

39 of 40 queries improve or stay level. Only q35 gets worse, by 0.9s.

| query | stock | tuned | |
|---|---:|---:|---:|
| q54 | 23.9s | **0.7s** | 34.1x |
| q5 | 79.6s | **5.2s** | 15.3x |
| q2 | 57.2s | **4.1s** | 14.0x |
| q51 | 35.3s | **5.1s** | 6.9x |
| q97 | 9.5s | **1.4s** | 6.8x |
| q47 | 35.3s | **7.6s** | 4.6x |
| q78 | 18.0s | **4.7s** | 3.8x |
| q11 | 24.2s | **6.8s** | 3.6x |
| q14 | 63.8s | 31.6s | 2.0x |

The winners are heavy-aggregation and window-function queries — q5, q2, q51,
q47, q54 — which is the same shape that dominated at SF=4. `tmp_table_size`
at **16 MB** is the obvious suspect in both cases.

## What this corrects

Report 23 frames the tuning as an SF=4 finding and closes by saying it should
be re-measured before being trusted elsewhere, because "report 21 showed
conclusions do not carry across scale factors". That caution was right to
state and wrong in its guess: **these conclusions do carry, and the gain at
SF=1 is larger and cleaner.**

The reason the two differ is worth keeping separate. Page size changed which
*plan* the optimizer chose, and plan choice flipped when the data stopped
fitting in memory. The tuning here mostly removes a hard limit — a 16 MB
temp table spills to disk whether the database is 9 GB or 32 GB. Spilling is
not a property of the data fitting in the buffer pool, which is why this
transfers and page size did not.

This matters practically: the live server on 3306 runs SF=1 at 16K pages, and
the measurement that was missing before is now here for 32K. 16K is still
untested.

## Caveats

- **macOS, where `O_DIRECT` does not work** (`pagesize/test-odirect.sh`). All
  three runs are equally affected and B and C ran back to back, so the
  comparison holds; absolute times would differ on Linux.
- **One run each.** 2.94x is far outside this host's ±8% noise and 39 of 40
  queries move the same way, so the direction is not in doubt. The individual
  per-query ratios are single measurements.
- **A is not directly comparable to report 23's figures.** It measured 942.1s
  where the same configuration measured 867.5s earlier; that drift is
  unexplained and is being investigated separately with interleaved passes.
- 32K pages throughout. The live server is 16K.

## Reproducing

```bash
pagesize/run-three.sh      # A, B, C in one pass
```
