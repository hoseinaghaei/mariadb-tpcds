# Four scale factors, twice — adopted candidates + 118 indexes, 2026-11-05

Raw artifacts for the configuration that is now the **default** in
`./reproduce.sh`. Eight runs: the 40 tier-4/5 queries at SF=1, 2, 4 and 8,
each scale measured twice, every run verifying
`index set matches sql/ exactly (118 indexes)` before measuring.
40/40 queries and **zero errors in all eight**.

## What changed since `four_scale_twice_20261104`

Seven candidate rewrites adopted (q4, q5, q7, q11, q33, q57, q74) and 23
indexes added, giving 118 = the 95 previously kept plus the 23 those
rewrites need.

| | SF=1 | SF=2 | SF=4 | SF=8 |
|---|---:|---:|---:|---:|
| 95 indexes, previous queries | 139.8s | 291.2s | 741.2s | 2692.2s |
| **118 indexes, 7 rewrites** | **125.4s** | **241.9s** | **579.5s** | **1599.6s** |
| | −10.3% | −16.9% | −21.8% | **−40.6%** |

**The gain grows with scale.** At SF=1 the database largely fits the 8 GiB
buffer pool and access paths matter less; at SF=8 they decide the run.

## Both halves contribute

Measured per query at SF=4, comparing the *same* query at 95 and at 118
indexes, then the rewrite on top:

| | SF=4 |
|---|---:|
| the 23 added indexes alone | ≈ −103s |
| the 7 rewrites, on top | ≈ −91s |

Crediting the whole gain to either half would be wrong. The indexes help
queries nobody rewrote; q74's win is almost entirely its rewrite.

Cost: **+4.63 GB** of index and 477s to build at SF=4.

## Per-scale totals

| scale | pass a | pass b | best | spread |
|---|---:|---:|---:|---:|
| SF=1 | 136.1s | 125.4s | **125.4s** | +8.5% |
| SF=2 | 241.9s | 243.7s | **241.9s** | +0.7% |
| SF=4 | 579.5s | 591.0s | **579.5s** | +2.0% |
| SF=8 | 1609.8s | 1599.6s | **1599.6s** | +0.6% |

## Three candidates measured and rejected

| query | why |
|---|---|
| q46 | returns **0 rows** where the adopted query returns 101 — wrong, not fast |
| q8 | its 2.88x is on output that is identically **empty** at SF=4, so nothing proves equivalence |
| q10 | 1.04x, inside noise |

q77 had no rewrite to adopt: its 9.3x (4.3s → 0.5s) is entirely its five
covering indexes, which are in the 118.

## Method

Every candidate was diffed against the query it would replace **before**
being timed, with both sides seeing the new indexes — otherwise an index
gets credited to a rewrite. Report 19 is the reason: q72 once looked like
719x and was 1.1x once the original had the index too.

Two passes, intended to be separated by a full sweep of the other scales so
that adjacent runs could not agree with each other by sharing buffer-pool
state.

**That intent was met for SF=1, 2 and 4, and not for SF=8.** The actual
sequence was SF4, SF1, SF2, SF8 and then the same again; SF=8 failed both
times with `table 'store_sales' is full`, and was rerun only after the
Docker VM disk was raised from 180 to 220 GiB. Its two passes then ran
**back to back**, 20:46 and 21:29, with nothing between them.

| | pass a | pass b |
|---|---|---|
| SF=4 | 17:49 | 18:17 |
| SF=1 | 18:00 | 18:28 |
| SF=2 | 18:05 | 18:31 |
| SF=8 | 18:12 failed | 18:35 failed |
| SF=8 rerun | **20:46** | **21:29** |

This is visible in the spreads above: SF=8's two passes differ by 0.6%, the
tightest of the four, while the genuinely separated SF=1 differs by 8.5%.
**SF=8's error bar is therefore the least trustworthy of the four, and it
carries the largest reduction (−40.6%).** SF=8 also ran at a different VM
disk allocation from the other three scales.

An earlier version of this file claimed "two separated passes over all four
scales, not two adjacent runs per scale" without qualification. That was
wrong for SF=8, and the statement propagated into the submitted report.

## Not comparable across sessions

Absolute totals here should not be divided against figures from any other
session. The same configuration has measured 81.8s and 139.8s at SF=1 on
this host weeks apart. Everything in this bundle is one session.

Verify with `shasum -a 256 -c SHA256SUMS`.
