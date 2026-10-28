# Running the benchmark at several scale factors, and reading the results

Two steps: produce runs, then analyse them.

## 1. Produce runs

```bash
./run-scales.sh                      # container, scale factors 1 2 3 4
./run-scales.sh 1 4                  # just two of them
./run-scales.sh 1 2 3 4 BUFFER_POOL=8G
```

Each scale factor is a full reproduction — generate, load, index, `ANALYZE`,
benchmark — inside the Linux container, writing to `results/sf<N>/`. Budget
roughly 20 min at SF=1 rising to ~3 h at SF=4, and about 115 GB of Docker
volumes for all four. Each scale keeps its own volume, so re-running one
later skips generation and loading.

Existing commands and `results/sf<N>/tuned/` paths remain supported. A repeat
run archives the earlier query artifacts and log under
`results/sf<N>/.history/<tag>/<timestamp>/`; the collector reads the latest
paths only. `QUERYSET=all-tuned` opts into all 99 queries; the historical
default still selects 40. Missing query measurements are displayed as `—`.

On the macOS host, where only the SF=1 and SF=4 instances are built:

```bash
pagesize/run-scales-mac.sh 1 4       # writes pagesize/results/mac-sf<N>/
```

### The buffer pool is held constant on purpose

`run-scales.sh` defaults to `BUFFER_POOL=8G` for **every** scale factor and
does not grow it with the data. A scaling curve measured with a pool that
grows alongside the dataset conflates two variables and mostly measures the
pool. Holding it fixed is what makes the curve informative: at SF=1 the
working set fits, and somewhere above it stops fitting — which is the part
worth seeing. Override it if you want the other experiment, but say so when
reporting the numbers.

For a low-memory installation check use `./reproduce.sh smoke`. That profile
uses separate `results/smoke/` output and is intentionally excluded from the
scaling reports. It runs four adapted queries and skips secondary-index builds;
its timings do not represent the reference experiment.

## 2. Analyse

```bash
python3 analysis/analyze.py          # the container runs — this is the one to share
python3 analysis/analyze.py --all    # plus macOS and the pruned experiment
python3 analysis/analyze.py --open   # and open the HTML report
```

**The default is the container runs only.** Five runs were being mixed into
one document — macOS at two scales, the container at two, and a container
run with 127 indexes dropped — and most of them do not belong side by side:
the macOS SF=4 dataset was generated without `-RNGSEED 10`, so it is a
different database, and the pruned run exists at SF=1 only. `--all` brings
them back for our own comparisons.

Writes three files:

| file | what it is |
|---|---|
| `analysis/results.csv` | one row per query per run — for your own analysis |
| `analysis/report.md` | tables and findings as text |
| `analysis/report.html` | the same plus charts, opens offline |

The charts are hand-written inline SVG: no matplotlib, no CDN, no
JavaScript. The report has to open on a machine where nothing has been
installed, which rules out a plotting library.

## What gets flagged, and why

| flag | meaning |
|---|---|
| **ANSWER MISMATCH** | same scale, recorded seed and result format, different saved hashes; requires SQL and ORDER BY/LIMIT review |
| **ANSWER CHECK SKIPPED** | missing or different seed/hash metadata prevents a justified answer comparison |
| **TIMING PROTOCOL CHANGE** | different measurement protocols; raw timings remain visible but cross-protocol ratios are suppressed |
| **ERROR** | the query did not complete |
| **SUPER-LINEAR** | time grew faster than the data; usually a working set that stopped fitting in the pool, or a plan that turned worse as statistics moved |
| **SUB-LINEAR** | time grew much slower than the data; sometimes a query whose cost does not scale, sometimes a sign it is not doing the work you expect — check the row count |
| **NON-MONOTONIC** | slower at a smaller scale than a larger one; on a quiet machine this should not happen, and usually means the measurement was disturbed |
| **ENVIRONMENT GAP** | same query, same scale, large factor between macOS and the container |
| **DOMINATES** | one query is a large share of a run — not a fault, but where effort pays |
| **EMPTY** | returned no rows, so it is not really exercising anything at this scale (q8, q54 and q23 do this at SF=4) |

### Answers across scale factors are *supposed* to differ

`dsdgen` builds a different database at every scale factor, so comparing
`md5_sorted` between SF=1 and SF=4 is meaningless and the tooling never does
it. The hash comparison also requires matching recorded data seeds and result
hash formats. Scale alone does not identify a dataset, and different row counts
do not prove that the datasets differ: multiple incorrect queries can also
produce different counts. Legacy records without sufficient metadata remain
readable but are marked `ANSWER CHECK SKIPPED` when compared with other runs.

The new `result-sets-json-v1` hashes cannot be compared with historical TSV
hashes. Likewise, `whole-file-xml-v1` timings are labelled separately from
legacy timings. Run a complete scaling campaign with the same harness and
workload before interpreting its curve. Matching row-sorted hashes alone do
not verify output ordering or nondeterministic LIMIT ties; use the saved-answer
comparison in [the Docker guide](../docker/README.md#complete-99-query-coverage-and-answer-comparison)
for the new results.

### Thresholds are deliberately loose

This host has shown **16–34% run-to-run variation on identical
configurations** — the same suite measured 408.7s and 475.4s back to back.
Tight thresholds would report that noise as findings. The constants live at
the top of `analyze.py` if you want to change them, and every flag prints the
numbers it fired on so you can judge for yourself.

Each figure comes from a single run. Treat the **ordering** as more reliable
than any individual number, and prefer the per-query A/B comparisons in
`queries/optimized/*/README.md` where a claim needs to be firm.
