# Measuring indexes is harder than it looks

Ten things that went wrong while deciding which indexes to drop. Each one
produced a confident, plausible, wrong answer first. They are written up
because the wrong answers are reproducible and the traps are not specific to
this project.

---

## 1. `ALTER INDEX ... IGNORED` re-samples the whole table's statistics

`ALTER TABLE t ALTER INDEX i IGNORED` is documented as a metadata-only
change, and it is: the index stays on disk, stays maintained, and merely
becomes invisible to the optimizer. It is advertised as the safe, reversible
way to test whether an index is needed.

It is not inert. InnoDB **re-samples the persistent statistics for the entire
table** on that statement, reading
`innodb_stats_persistent_sample_pages` random pages. Measured directly on
`catalog_sales`: one `ALTER ... IGNORED` changed **85 rows** of
`mysql.innodb_index_stats`, and the matching `NOT IGNORED` changed 84 more.

This happens with `innodb_stats_auto_recalc = OFF`. We found no way to
suppress it.

Consequences:

- Hiding one `catalog_sales` index appeared to move **37 of 44** query plans.
- Hiding it and immediately re-showing it — a net no-op — moved **19**.
- So the great majority of an apparent "this index matters" signal was the
  re-sampling, not the index.

**Writing the old statistics back does not fix it.** Restoring the saved rows
into `mysql.innodb_index_stats` leaves InnoDB using the re-sampled values it
holds in memory. Neither `FLUSH TABLE t`, `FLUSH TABLES`, nor
`ALTER TABLE t STATS_PERSISTENT=1` makes it re-read them.

**A bigger sample does not fix it either.** Raising
`innodb_stats_persistent_sample_pages` from 160 to 4000 made
`ANALYZE TABLE store_sales` 10x slower (7.5s → 75.7s), made each `ALTER` on
that table cost about 100s instead of 7s, and left the same-state noise at
**31 of 44**, unchanged. It is not a precision problem.

### The general consequence

**Any index DDL re-rolls plan choice.** Creating or dropping an index forces
a re-sample of that table, and at this scale the re-sample alone is enough to
change plans elsewhere. Every before/after index experiment in the
literature of this project — including our own 735.2s → 1487.0s result for
dropping 129 indexes — carries that confound.

### What to do instead

Use per-statement **index hints**. `FROM inventory IGNORE INDEX (idx_x)`
hides the index from one statement, touches no metadata, and re-samples
nothing. Every result in report 27 that depends on hiding an index uses
hints.

---

## 2. Read counters do not measure what you think

`INDEX_STATISTICS.ROWS_READ` with `userstat=1` answers *"did executing the
plan touch this index?"* It does not answer *"did choosing the plan depend on
this index existing?"*

At SF=4, 137 of 190 indexes were never read. Dropping the 130 that no scale
factor read took the suite from 735.2s to 1487.0s.

The mechanism is visible afterwards: **7 of the 37 indexes that had been read
stopped being read** once the others were gone. Nothing about those 7
changed; the plans around them did.

`EXPLAIN`'s `possible_keys` answers the real question directly, costs one
EXPLAIN pass, and is perfectly deterministic — two captures of all 44
statements come back byte-identical. See report 27.

---

## 3. An index can make a query slower

`idx_inv_date_sk` on `inventory` is 1,030 MB and is read by **no query at
either scale factor**. It is also not harmless.

| query22 | best of 2 | inventory access |
|---|---:|---|
| as-is | 38.4s | `PRIMARY` |
| `IGNORE INDEX (idx_inv_date_sk)` | **10.6s** | `idx_inv_item_date_sk` |

Identical answers. **3.6x.** The index is never used; its only effect is to
mis-cost a choice between two *other* access paths. Timing all six queries
that weigh it: 44.5s → 15.0s, with nothing made slower.

So "unused" splits four ways, not three:

1. read while executing — keep
2. never read, but weighed into a *better* plan — keep
3. never read, never weighed — drop, free the space
4. never read, weighed into a *worse* plan — **drop, and the query speeds up**

Category 4 is invisible to read counters, invisible to `possible_keys`, and
only shows up when you time it.

---

## 4. Indexes cover for each other, so one-at-a-time testing lies

Of the 58 indexes weighed but never read, hiding any *single* one moves a
plan in only 8 cases. That reads as "the other 50 are disposable".

Hiding all 120 drop candidates **together** moves plans in 4 queries and
costs 17% — 513.7s against 600.7s, identical answers. Per table the pattern
repeats: hide `store_sales`' whole candidate group and 7 queries move;
`web_sales`', and 10 move.

Two indexes can each look disposable because the optimizer still has the
other to fall back on. The unit of decision is a group, and a drop list has
to be validated as the list you intend to apply.

The set that survives that test is the one no plan mentions **at all** —
70 indexes, 5.35 GB, zero plans moved when hidden together — plus
`idx_inv_date_sk`, whose single plan move makes query22 faster.

## 5. A rebuilt database is a different benchmark

The SF=4 database was accidentally reloaded mid-investigation. The same 40
queries, the same data (`store_sales` is 11,516,885 rows either way), the
same settings and the same index set:

| | SF=4 total |
|---|---:|
| database accumulated over many index experiments | 735.2s |
| rebuilt in one pass | 454.4–470.9s |

**1.6x, from physical layout and freshly computed statistics alone.** That is
a larger effect than any index decision in this work.

Anyone reproducing these numbers should build the database in one pass. A
volume that has been through a series of index experiments is not the same
benchmark target, even when every table and every index matches.

---

## 6. A stale list silently measured the wrong configuration

`sql/unignore_all_indexes.sql` was a static file. After a rebuild, two of the
index names in it no longer existed. The client stops at the first error, and
the call site had `2>/dev/null || true`, so:

- the error was discarded,
- every statement after the missing index went unapplied,
- **48 indexes stayed hidden through a run labelled "full index set"**,
- and the A/B that run anchored was comparing 70 hidden against 48 hidden.

It reported a clean, plausible +18%. The real answer, measured properly, is
no difference at all.

Two fixes, both worth generalising: derive the un-ignore statements from
`information_schema` rather than from a file so the list cannot go stale,
and **assert the resulting state** — an ignore run must end with exactly as
many ignored indexes as its list has statements, and a full-set run must end
with none. Both now exit rather than measure.

---

## 7. A guard that required exactly 25 tables dropped the database

The loader skipped reloading when `information_schema.tables` held exactly 25
rows for the schema. Two scratch tables left behind by an experiment made it
27, which read as a broken database, and the entrypoint dropped and reloaded
32 GB without being asked.

Guards should check that what is needed is **present**, not that nothing else
is. It now verifies the 25 tables `sql/01_schema.sql` defines exist and
tolerates extras.

---

## 8. Prefixing `EXPLAIN` to "the query" executes half of it

Queries 14, 23, 39 and 67 are **two statements each** — TPC-DS asks for two
result sets. A planning-only pass that attaches `EXPLAIN` to the first
statement leaves the second to run for real. One part-B of query 14 was
observed executing for 58 seconds inside what was supposed to be a pass that
executes nothing.

---

## 9. A single-run benchmark number is mostly cold cache

After dropping the 71 indexes, 8 of 40 queries looked slower than their
previous best, and query68 looked 2.5x slower -- 2.9s before, 7.4s after.
That is exactly the "don't hurt any query" failure the drop list was meant
to avoid.

Re-timing each of them warm:

| query | benchmark (1 run) | run 1 | run 2 | previous range |
|---|---:|---:|---:|---|
| query68 | 7.4s | 12.7s | **3.2s** | 2.8–3.8s |
| query66 | 11.6s | 20.3s | **6.1s** | 7.3–8.4s |
| query57 | 14.6s | 10.2s | **7.4s** | 9.7–14.5s |
| query2 | 7.8s | 7.1s | **5.7s** | 6.5s |

Every one of them is at or below its previous range once the cache is warm.
The benchmark runs each query exactly once, so each number carries whatever
the buffer pool happened to hold at that moment, and a cold read can be 3x
the warm time.

That is tolerable for a 40-query total, where the effect averages out. It is
not tolerable for per-query claims, and "8 of 40 queries regressed" would
have been reported as a real finding on this evidence alone.

## 10. One A/B pair cannot tell an effect from drift

Within-condition spread on this host exceeded the effect being measured:

| condition | runs | mean | spread |
|---|---|---:|---:|
| full set | 454.4s, 470.9s | 462.6s | 16.5s |
| 70 indexes hidden | 424.4s, 472.3s | 448.4s | **47.9s** |

A single pair would have supported either conclusion depending on the order
it was run in — and both orders were observed, in opposite directions, on the
same configuration. Alternating `full, hidden, full, hidden` is what makes
the null result readable: `full-2` being the slowest of all four rules out
"later runs are warmer".

The host was also swapping 12–14 GB throughout, which inflates every absolute
number by roughly 1.45x. Paired, alternating comparisons survive that;
absolute figures quoted across sessions do not.
