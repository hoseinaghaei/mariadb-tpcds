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

On the macOS host, where only the SF=1 and SF=4 instances are built:

```bash
pagesize/run-scales-mac.sh 1 4       # writes pagesize/results/mac-sf<N>/
```

### The buffer pool is held constant on purpose

`run-scales.sh` defaults to `BUFFER_POOL=4G` for **every** scale factor and
does not grow it with the data. A scaling curve measured with a pool that
grows alongside the dataset conflates two variables and mostly measures the
pool. Holding it fixed is what makes the curve informative: at SF=1 the
working set fits, and somewhere above it stops fitting — which is the part
worth seeing. Override it if you want the other experiment, but say so when
reporting the numbers.

## 2. Analyse

```bash
python3 analysis/analyze.py          # or --open to open the report
```

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
| **ANSWER MISMATCH** | two environments at the **same** scale returned different answers — a defect, listed first, because nothing else matters if it fires |
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
it. The hash comparison runs **only** between environments at the same scale,
where the databases are identical and any difference is a real defect. This
is how a wrong answer in q97 was caught earlier in the project.

### Thresholds are deliberately loose

This host has shown **16–34% run-to-run variation on identical
configurations** — the same suite measured 408.7s and 475.4s back to back.
Tight thresholds would report that noise as findings. The constants live at
the top of `analyze.py` if you want to change them, and every flag prints the
numbers it fired on so you can judge for yourself.

Each figure comes from a single run. Treat the **ordering** as more reliable
than any individual number, and prefer the per-query A/B comparisons in
`queries/optimized/*/README.md` where a claim needs to be firm.
