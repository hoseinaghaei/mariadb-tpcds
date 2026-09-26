# Step 17 — A retracted finding, and what it cost to check

> **NOT COMPARABLE TO TPC BENCHMARK RESULTS.**

An earlier version of this document claimed that hiding the 80 never-read
indexes caused query 78 to regress from 73s to over 900s, and explained the
mechanism in terms of `possible_keys` influencing join order.

**That claim is retracted. It does not reproduce.**

## The experiment

All 80 indexes with zero `ROWS_READ` were made `IGNORED` — hidden from the
optimizer, left built on disk — and all 99 queries re-run serially on the same
data with the same 8 GB buffer pool. Hiding all 80 takes **17.7 seconds**.

### Aggregate result

| Run | 96 queries completing in all three |
|---|---:|
| base (no indexes) | 1204.7s |
| indexed (117) | 1189.4s |
| **ignored80 (37 visible)** | **1179.6s** |

**−0.8% versus the indexed run.** 10 queries faster by >10%, 9 slower, 77
unchanged — noise in both directions. Row counts identical across all three.

## The outlier, and why it was not what it looked like

In that run, query 78 recorded **911.6s** and ended with
`ERROR 1969: execution time limit 300.0 sec exceeded`, against 73.4s in the
indexed run. That looked like a dramatic index-induced regression, and was
written up as one.

Re-testing:

| Configuration | query 78 |
|---|---:|
| all 117 visible | 45.4s |
| the 6 indexes in its `possible_keys` hidden | 43.8s |
| **all 80 hidden** | **43.7s** |
| all restored | 44.2s |

**Hiding the indexes makes no measurable difference to query 78.** The
regression does not reproduce under any of the three configurations.

### What the 911.6s actually was

`max_statement_time` limits *execution* time. The statement was killed at 300s
of execution, but the wall clock read 911.6s — meaning roughly **600 seconds
were spent not executing**: waiting on I/O, or descheduled. That is the
signature of an environmental stall on the machine, not a query plan.

It is consistent with the monitoring gap observed during that run, where
progress reporting went quiet for 32 minutes around the same point.

## What was wrong with the reasoning

The `possible_keys` explanation was constructed *after* seeing the outlier and
was never tested before publishing. It was plausible — hidden indexes really do
disappear from `possible_keys`, and that really can change cost estimates — but
plausible is not measured. Hiding exactly those six indexes changes query 78 by
1.6 seconds.

**One unrepeated measurement was treated as a finding.** The correct response
to a single 12x outlier is to run it again, which takes 45 seconds here.

## What stands

- **Hiding all 80 never-read indexes has no measurable effect on this query
  set.** That is the actual result, and it supports rather than contradicts
  the step 15 observation.
- The storage cost is real: **2.49 GB of the 3.74 GB secondary-index footprint**
  sits in indexes no query reads, along with the write amplification on every
  insert.
- `ALTER INDEX ... IGNORED` remains the right tool for this kind of test —
  17.7s for all 80, fully reversible, nothing rebuilt.

## What to be careful about anyway

A capped query is excluded from aggregate totals, so a genuine catastrophic
regression *could* hide inside a flat headline. That part of the earlier
warning was sound even though the specific instance was not. Any index
experiment should check queries individually and re-run anything anomalous
before believing it.

`sql/06_drop_unused_indexes.sql` carries a note to test with `IGNORED` first —
not because of query 78, but because dropping an index on an 11.7M-row table is
expensive to undo and `ROWS_READ` is a narrow measure.

## Reproducing

`queries/test-q78-index-effect.sql` walks through it step by step. The short
version:

```sh
cd queries
python3 run_query.py 78 before
mariadb tpcds < ../sql/09_ignore_unused_indexes.sql     # hide 80, ~17s
python3 run_query.py 78 hidden
mariadb tpcds < ../sql/10_unignore_unused_indexes.sql   # restore
python3 run_query.py 78 after
```

## Current state

All 117 indexes restored and visible; nothing ignored.
