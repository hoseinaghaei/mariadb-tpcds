# What an index is for: read counters are the wrong instrument

## The question

The full index set is 166 secondary indexes, 23.3 GB at SF=4 — larger than
some of the tables they index. Most are never touched by the 40 tier-4/5
queries. The obvious move is to drop what is never used.

That move failed badly, and understanding why produced the most useful
result in this part of the project.

## Attempt 1: drop what is never read

With `userstat=1`, `INDEX_STATISTICS` counts rows read per index. Zero the
counters, run the 40 queries, read the counters back, and you have an exact
record of which indexes the queries touched.

| | never read | size |
|---|---:|---:|
| SF=4 | 137 of 190 | 17.1 GB |
| SF=1 | 136 of 190 | — |
| **neither scale** | **130 of 166 secondary** | **16.4 GB** |

Only 36 secondary indexes were read by any query at any scale. Dropping the
rest, leaving 37:

| SF=4, 40 queries | total |
|---|---:|
| full set | 735.2s |
| never-read indexes dropped | 1487.0s |

Twice as slow, on exactly the configuration whose own read counters said
those indexes did nothing.

> **Which database these numbers come from.** Everything in Attempts 1 and 2
> was measured on an SF=4 volume that had been through many index
> experiments. That database was later rebuilt, and the same full index set
> then ran the same queries in 454.4–470.9s rather than 735.2s — see *The
> measurement that moved more than any index* below. The comparisons in
> these two sections are internally consistent, because each pair was run
> back to back on the same database within the hour, but their absolute
> numbers are not comparable to anything measured after the rebuild.

## Why it failed

A read counter answers *"did executing the plan touch this index?"* It does
not answer *"did choosing the plan depend on this index existing?"*

The optimizer costs alternatives. To decide that a scan beats a nested loop
on `idx_x`, it has to consider `idx_x` — read its cardinality, estimate its
rows, compare. If `idx_x` is gone, that alternative is never costed, and the
comparison that produced the good plan never happens. The index did its work
at planning time and left no trace in any read counter.

Direct evidence: after dropping the 129, **7 of the 37 indexes that had been
read stopped being read**. Nothing about those 7 changed. The plans around
them did.

## Attempt 2: hide them instead of dropping them

Dropping changes two things at once: the optimizer can no longer see the
index (planning), and 16.4 GB leaves the disk (storage).

`ALTER TABLE t ALTER INDEX i IGNORED` changes only the first. The index stays
on disk, stays maintained, stays in the buffer pool, and becomes invisible to
the optimizer. Measured back-to-back on the same volume within one hour:

| SF=4, 190 indexes on disk | total | vs baseline |
|---|---:|---:|
| all visible | 735.2s | — |
| 129 hidden from the optimizer | 815.9s | +11.0% |
| 129 *dropped* (separate session) | 1487.0s | +102% |

**Hiding costs 11%. Dropping the same indexes cost 102%.** So the question
"is ignoring the same as dropping?" has a clear answer: no, and it does not
come close to the 1000s mark.

Per query, 18 of 40 got worse when the 129 were hidden and 4 got better.
The largest regressions: q68 +106%, q71 +92%, q77 +86%, q43 +81%, q46 +76%.
The largest improvement is the interesting one: **q22 fell from 76.6s to
35.0s, 2.2x faster with 129 indexes hidden.** At least one index is actively
pushing the optimizer into a worse plan.

## Attempt 3: ask the optimizer which indexes it considered

`EXPLAIN` already reports, for every table access, the `possible_keys` it
weighed and the `key` it chose. An index that appears nowhere in any plan for
the whole query set was never a candidate for anything, so removing it cannot
change which plan is chosen.

One pass over all 44 statements, no DDL, and perfectly deterministic — two
captures come back byte-identical. `scripts/index-consulted.py`.

At SF=4:

| verdict | indexes | size |
|---|---:|---:|
| **used** — read during execution | 36 | 6.89 GB |
| **considered** — never read, but weighed when costing | 60 | 11.05 GB |
| **unreferenced** — never read, never mentioned | 70 | 5.35 GB |

The middle row is the whole finding. **60 indexes and 11 GB are invisible to
read counters but shape plan choice.** Those are what Attempt 1 deleted.

Concretely, the three largest never-read indexes in the database —
`idx_inv_date_sk`, `idx_inv_item_sk`, `idx_inv_warehouse_sk` on `inventory`,
1,030 MB each — are weighed by q21, q22, q37, q39, q72 and q82. For q21 the
optimizer lists all four `inventory` secondary indexes in `possible_keys`
and then picks `PRIMARY`. Read counters record nothing; the costing used
every one of them.

Running the same classification at SF=1 gives **exactly the same split** —
36 used, 60 considered, 70 unreferenced — and the same 70 names, with no
index unreferenced at one scale and consulted at the other. So the droppable
set is not a scale-factor accident.

## The decision

| | indexes | SF=4 size |
|---|---:|---:|
| keep — read or weighed at some scale | 96 | 17.94 GB |
| **drop — neither, at both scales** | **70** | **5.35 GB** |

### Checked against the clock, not just the plans

EXPLAIN says removing these 70 cannot change a plan. Four alternating runs at
SF=4 — full, hidden, full, hidden — say the clock agrees:

| condition | runs | mean |
|---|---|---:|
| full set | 454.4s, 470.9s | 462.6s |
| 70 hidden | 424.4s, 472.3s | 448.4s |

The difference between the conditions (14.3s) is smaller than the spread
*within* the hidden condition (47.9s), and **no query is slower in both
hidden runs than in both full runs**. That is a null result, and a null
result is what the prediction called for.

Alternating matters. A single pair cannot tell the effect from the machine's
drift: an earlier full-then-hidden pair had the second run slower, and a
hidden-then-full pair had the second run faster. Here `full-2` is the slowest
of the four, which rules out a simple warm-up story.

So the 70 buy nothing and cost 5.35 GB. Dropping them is free in response
time and saves the storage, the maintenance on every load, and the time to
build them.

`sql/drop_unreferenced_indexes.sql` drops them;
`sql/ignore_unreferenced_indexes.sql` hides the same set reversibly;
`sql/unignore_all_indexes.sql` restores every index;
`analysis/index-decisions.md` lists each one with the reason it was kept.

The dropped set is almost entirely single-column foreign-key indexes on
columns no query in the set filters or joins on —
`idx_cs_ship_hdemo_sk`, `idx_ws_promo_sk`, `idx_sr_reason_sk` and their
relatives. The largest are `idx_ss_qty_q28` and
`idx_store_sales_quantity_2` at 469.7 MB each.

Note what is *not* in it. The three 1,030 MB `inventory` indexes are the
biggest never-read indexes in the database and the most tempting thing to
delete; they stay, because six queries weigh them.

## The measurement that moved more than any index

The SF=4 database was accidentally reloaded mid-investigation: two scratch
tables left in the `tpcds` schema broke a guard that required exactly 25
tables, and the entrypoint rebuilt from the `.dat` files. The data was
identical — `store_sales` is 11,516,885 rows either way.

The rebuilt database runs the same 40 queries in **454.4–470.9s** where the
database that had accumulated in the volume took **735.2s**. Same data, same
queries, same settings, same index set. The difference is physical layout and
freshly computed statistics.

That is a larger effect than any index decision in this report, and it is
consistent with the statistics sensitivity documented below: an index set
built up over many sessions carries statistics that have been re-sampled
dozens of times, and the plans chosen from them are measurably worse.

The practical consequence for reproducing this work: build the database in
one pass. A volume that has been through many index experiments is not the
same benchmark target, even when every table and index matches.

## A dead end worth writing down

The first attempt at attempt 3 was to hide one index at a time and diff the
plans. It does not work here, for a reason that is not in the manual.

`ALTER TABLE ... ALTER INDEX` is metadata-only, but **InnoDB still re-samples
the whole table's persistent statistics** — with
`innodb_stats_auto_recalc=OFF`, and there is no way to suppress it. Sampling
reads `innodb_stats_persistent_sample_pages` (160) random pages, so every
ALTER shifts cardinalities, which moves costs, which flips plans in queries
that never mention the hidden index.

Measured on `catalog_sales`: hiding one index appeared to move 37 of 44
plans. But capturing the plans twice *in the same hidden state*, where the
only thing between the two captures is another ALTER, moved 19 — so most of
the apparent effect was never the index. On `store_sales` that same
same-state noise is 31 of 44.

Writing the old values back into `mysql.innodb_index_stats` does not help:
InnoDB keeps the re-sampled numbers in memory, and neither `FLUSH TABLE`,
`FLUSH TABLES` nor `ALTER ... STATS_PERSISTENT=1` makes it re-read them.
Raising the sample to 4000 pages made `ANALYZE store_sales` 10x slower
(7.5s → 75.7s), made each `ALTER` on that table cost about 100s instead of
7s, and left the same-state noise at **31 of 44**. It is not a precision
problem — these plans sit on a knife edge and any re-sample re-rolls them.

Two consequences:

1. **Any index DDL re-rolls the plan dice.** Creating or dropping an index
   forces a re-sample of that table, and at this sample size the re-sample
   is enough to change plans on its own. Part of the 735s → 1487s regression
   may be exactly that, and nothing to do with the indexes' usefulness.
2. A hide-and-diff experiment needs replication to be worth anything.
   `scripts/plan-sensitivity.py` keeps that method, with a noise filter
   requiring a statement to be stable across every replicate in both states.

Where the noise was low the two methods agree exactly — for
`idx_inv_warehouse_sk` both name q21 and q72. Where it was high the
replicated method is simply blind: it called `idx_ss_q61` (640 MB) dead,
while `EXPLAIN` shows 7 queries weighing it. That is why `EXPLAIN` is the
instrument of record here and the hide-and-diff is kept only as
corroboration.

## Indexes cover for each other, so the unit of decision is a group

Testing one index at a time answers the wrong question. Of the 58 indexes
that are weighed but never read, hiding any *single* one moves a plan in only
8 cases. Hiding all 120 drop candidates **together** moves plans in 4 queries
and costs 17% — 513.7s against 600.7s, same answers.

Per table, the pattern is consistent: hide `store_sales`' whole candidate
group and 7 queries move; `web_sales`', and 10 move. Two indexes can each
look disposable because the optimizer still has the other to fall back on.

So the 13.37 GB of "never read or never decisive" is **not** recoverable.
What is recoverable is the set that no plan mentions at all, checked as a
group:

| set | indexes | size | plans moved |
|---|---:|---:|---|
| the 70 unreferenced, hidden together | 70 | 5.35 GB | **none** |
| plus `idx_inv_date_sk` | 71 | 6.35 GB | query22 only — 3.8x *faster* |

That is the recommendation: **drop 71 indexes, 6.35 GB**, and one query gets
faster.

## An index that makes a query slower

One result from the hiding experiment does not fit the "indexes help or do
nothing" picture. With the 129 never-read indexes hidden, **q22 ran 2.2x
faster — 76.6s to 35.0s.**

q22 weighs exactly five indexes. Two of them, `idx_inv_date_sk` and
`idx_inv_item_sk` (1,030 MB each), plus `idx_date_month_date_sk`, are never
read and were among the 129 hidden. Hiding them is what made q22 fast: the
optimizer considers them, costs them attractively, and chooses a worse plan
than it would if they did not exist.

So the three categories are not enough. An index can be:

1. read while executing — keep;
2. never read but weighed into a better plan — keep;
3. never read and never weighed — drop;
4. **weighed into a worse plan — drop, and the query gets faster.**

Category 4 is invisible to every method in this report except timing.

### But dropping it is not what fixes query22

Dropping `idx_inv_date_sk` made query22 fast, and that looked like the end of
the story. It was not. After `OPTIMIZE TABLE` re-sampled the statistics,
query22 chose `inventory:PRIMARY` again and returned to 38–46s **with
`idx_inv_date_sk` already dropped**.

The index was never the cause so much as the trigger. At
`innodb_stats_persistent_sample_pages=160` the costs of `PRIMARY` and
`idx_inv_item_date_sk` are close enough that the choice between them turns on
which pages the last `ANALYZE` happened to read. `idx_inv_date_sk` tipped it
one way; a fresh sample can tip it back.

So query22 carries `FORCE INDEX (idx_inv_item_date_sk)` in
`queries/tuned/query22.sql`:

| | runs | best | answer |
|---|---|---:|---|
| as-is | 46.3 / 40.8 / 39.0s | 39.0s | `dd6e2fc5` |
| forced | 11.3 / 10.5 / 10.4s | **10.4s** | `dd6e2fc5` |

3.75x, identical answer, and far steadier. That is consistent with the rest
of the tuned set, which already pins what this optimizer gets wrong —
`STRAIGHT_JOIN` in query43, `JOIN_PREFIX` in query72, `optimizer_switch` in
query14.

`idx_inv_date_sk` still goes, but on the honest grounds: it is 1,030 MB, no
query reads it at either scale, and its only measurable effect was to push
one query towards a worse plan. The 28 seconds are earned by the hint, not
by the drop.

## What this means for the submission

- **Drop the 71 in `sql/drop_unreferenced_indexes.sql`** — 6.35 GB. No plan
  at either scale factor mentions 70 of them; the 71st, `idx_inv_date_sk`,
  is weighed and makes query22 3.8x slower.
- **Keep the other 95**, including 58 that are never read. They are weighed
  when the optimizer costs alternatives, and removing them moves plans.
- "Never read" is not grounds for dropping an index, and this repository has
  the measurement to prove it: dropping on that test alone doubled SF=4.
- Test index removals **as a group**. Indexes substitute for each other, so
  one-at-a-time testing says every member is disposable and the set is not.
- Build the database in one pass. That was worth more than every index
  decision here combined — 735.2s against 454.4s on identical data.
