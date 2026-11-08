# Validation of `info_h419_mariadb_report.pdf` (8 November 2026)

Every quantitative claim in the submitted PDF checked against the measured
artifacts in this repository. 46 pages read in full.

**Summary: the numbers are sound. Every figure I could trace reproduces
exactly.** Four issues are worth fixing before submission, and one of them
originates in my own evidence bundle rather than in the report.

---

## 1. Verified correct — exhaustive

Checked value by value against `results/r3-sf*-{a,b}/tuned/query*.json`,
`report/25-row-counts.json`, `report/25-query-by-query.md` and reports 23/24.

| PDF element | Result |
|---|---|
| **Table 3.1** — 25 tables × 4 scales, plus totals | **exact**, all 100 cells and all four totals |
| **Table 3.2** — host and Docker environment | matches `submission_evidence.json` (one nuance, §3 below) |
| **Table 3.5 / 4.1** — configuration tuning | **exact**: 2403.4→1195.5 (2.01x), →971.4 (2.47x), 464.5→157.8 (2.94x) |
| **Table 3.6** — the 40 queries, 20 per tier | **exact** against `queries/build-tuned.py` |
| **Table 4.4** — campaign comparison | **exact**: 139.8/125.4, 291.2/241.9, 741.2/579.5, 2692.2/1599.6 and all four percentages |
| **Table 4.5** — six dedicated SF4 comparisons | all six trace to `report/25`; see note below |
| **Table 4.6** — pass totals, sums of minima, growth | **exact**: 136.1/125.4/124.0, 241.9/243.7/234.3, 579.5/591.0/551.9, 1609.8/1599.6/1517.0; growth 1.89x/2.36x/2.75x |
| **Table 4.7** — ten most expensive at SF8 | **exact**, all 20 values |
| **Table 4.8** — SF1→SF8 growth | **exact**, all rows including the 92.0x for Q71 |
| §4.3.2 — 103 s index / 91 s rewrite, 477 s, 4.63 GB | **exact** |
| §4.5.1 — 12.23x minima growth; Q14 339.0 s = 22.3% | **exact** |
| §4.6.1 — Q14+Q67+Q23 = 47.5% of SF8 minima | **exact** |
| §4.8.1 — Q5 SF8 7.3/16.3 s; Q88 SF4 0.6/3.9 s | **exact** |
| §3.5.3 — 95 → 118 indexes; seven rewrites Q4,Q5,Q7,Q11,Q33,Q57,Q74 | **exact** |
| Appendix A — five baseline-SQL cases Q38,Q58,Q66,Q71,Q77 | **exact** |
| §4.4.9 — Q97 overcounted by 2,569 catalogue pairs | **exact** |
| §4.7 — rejected Q46 (0 vs 101 rows), Q8 (empty), Q10 (1.04x) | **exact** |
| Q54 empty at every scale | **confirmed** (0 rows at SF1/2/4/8) |

**The PDF is more precise than my own prose in two places.** It recomputes
Table 4.5's ratios from the displayed timings and gets 36.93x for Q59 and
2.92x for Q11, where `report/25` rounds to 36.6x and 2.93x. The PDF is
right; report 25 should be corrected to match.

**The hedging is accurate throughout.** "Descriptive rather than an isolated
causal measurement" for the cross-campaign comparison, the separation of
sums-of-minima from complete-pass totals (equations 3.3–3.5), and the
refusal to pool timings from different studies are all correct and match
what the evidence supports.

---

## 2. The protocol claim is wrong for SF=8 — and the error is mine

§3.6.2 states the shared campaign used "two separated passes over the four
scale factors: SF1, SF2, SF4, and SF8, followed by a second pass over the
same sequence". §4.5.1 repeats "Two separated execution passes were
performed at each scale."

**That is not what happened at SF=8.** From the run logs:

| | pass a | pass b |
|---|---|---|
| SF=4 | 17:49 | 18:17 |
| SF=1 | 18:00 | 18:28 |
| SF=2 | 18:05 | 18:31 |
| SF=8 | 18:12 **failed** | 18:35 **failed** |
| **SF=8, rerun** | **20:46** | **21:29** |

SF=8 failed both passes with `table 'store_sales' is full`, and was rerun
after the Docker VM disk was raised from 180 to 220 GiB. **Its two passes
then ran back to back**, 43 minutes apart, with nothing between them —
not separated by a sweep of the other three scales.

This matters for a specific reason. The stated purpose of separating the
passes is that adjacent runs share buffer-pool state, agree with each
other, and produce a flattering error bar. SF=8 is exactly where that
protection was lost, and it shows: its two passes differ by **0.6%**
(1609.8 / 1599.6), the tightest agreement of all four scales, while SF=1 —
genuinely separated — differs by 8.5%. **SF=8 also carries the report's
largest headline claim, the 40.6% reduction.**

Two further undisclosed differences at SF=8: it ran at a different VM disk
allocation (220 GiB vs 180 GiB), and only after two failures.

**The source of the error is this repository, not the report's authors.**
`experiments/evidence/four_scale_twice_20261105_adopted/README.md` asserts
"Two separated passes over all four scales, not two adjacent runs per
scale." That sentence is mine and it is wrong for SF=8. The report
faithfully reproduced it.

**Fix:** correct the evidence README first, then amend §3.6.2 and §4.5.1 to
state the actual sequence (SF4, SF1, SF2, SF8) and to note that SF=8's two
passes were consecutive, at a larger VM disk, after two disk-exhaustion
failures.

---

## 3. A cited evidence file does not exist

§4.4.8 attributes Q74's local study to **`report/30-nafiz-sf4-revalidation.md`**
and quotes it in detail: seven repetitions after a discarded warm-up,
original median 14.896264 s, BEST 0.161919 s, ~92.00x, and ~627.03 MiB of
optional indexes.

That file **is not in the repository**, is not in any branch, and has never
been committed — checked with `find`, `git log --all --diff-filter=A`, and a
content search for the quoted figures. Appendix A directs the reader to the
GitHub repository, so a reader following the citation finds nothing.

**Fix:** commit the file, or re-attribute the claim to a source that exists.
The Q74 figures in the shared campaign (40.1 s → 0.6 s) are independently
verified and could stand alone if the local study cannot be published.

---

## 4. Two smaller corrections

**Memory.** Table 3.2 reports "Memory allocated: 12 GiB". That is the
Docker Desktop *setting*; `docker info` reports 11.67 GiB and every run's
own header recorded `memory 11G`. `submission_evidence.json` carries this
distinction and the report lost it. Suggested wording: *12 GiB allocated
(≈11.7 GiB usable)*.

**Host memory pressure is not disclosed.** The host swapped 10–14 GiB on a
16 GiB machine throughout the campaign. §4.8.1 gestures at "cache state,
background activity, resource contention" generically, but this is a
specific, documented and material condition — it is why the same
configuration measured 81.8 s and 139.8 s at SF1 in different sessions, and
it is recorded in `submission_evidence.json` under
`caveat_host_swap`. It belongs in Table 3.2 or §4.8.1.

---

## 5. Not errors, but worth knowing

- §3.6.2's pass order "SF1, SF2, SF4, and SF8" is also the wrong sequence
  for the adopted campaign (actual: SF4, SF1, SF2, SF8). The *earlier*
  campaign did use 1,2,4,8, so the sentence may have been carried over.
- The report never claims the index and rewrite contributions sum to the
  campaign difference, and explicitly warns against it (§4.3.2). That is
  the right call: 103 + 91 = 194 s, while the SF4 campaign difference is
  161.7 s — different sessions, not additive.
- Q23's "detail branch is empty" is consistent with the artifacts: q23
  returns one row, the rollup NULL.

---

## Verdict

The report's arithmetic is **clean**. I could not find a single incorrect
number in any table, and the uncertainty language is better calibrated than
most of what this project produced along the way.

The defects are in **provenance, not measurement**: one cited file is
missing, and one protocol claim overstates the rigour of the SF=8
measurement — which is the measurement carrying the largest headline. Both
are fixable without re-running anything, and one of them is my fault.
