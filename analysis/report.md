# Benchmark results across scale factors

Generated 2026-10-26 16:48. 4 runs, 40 queries.

## Totals

| environment | scale | queries | errors | total |
|---|---:|---:|---:|---:|
| docker | 1 | 40 | 0 | 114.8s |
| docker | 4 | 40 | 0 | 491.4s |
| macos | 1 | 40 | 0 | 69.2s |
| macos | 4 | 40 | 0 | 565.7s |

## Scaling

Per-query response time at each scale factor.

### docker

| query | SF=1 | SF=4 | SF4/SF1 |
|---|---|---|---|
| q2 | 4.3s | 7.6s | 1.8x |
| q4 | 10.2s | 54.6s | 5.4x |
| q5 | 1.3s | 18.7s | 14.4x |
| q7 | 1.7s | 9.5s | 5.6x |
| q8 | 0.5s | 2.3s | 4.6x |
| q10 | 0.1s | 0.6s | — |
| q11 | 7.0s | 31.4s | 4.5x |
| q14 | 4.2s | 23.8s | 5.7x |
| q21 | 0.3s | 1.3s | — |
| q22 | 22.9s | 24.5s | 1.1x |
| q23 | 10.7s | 49.4s | 4.6x |
| q27 | 1.8s | 7.0s | 3.9x |
| q31 | 0.4s | 1.4s | — |
| q33 | 0.3s | 0.3s | — |
| q35 | 2.1s | 2.8s | 1.3x |
| q37 | 0.1s | 0.6s | — |
| q38 | 1.3s | 4.9s | 3.8x |
| q39 | 0.4s | 2.3s | — |
| q43 | 0.7s | 2.8s | 4.0x |
| q46 | 2.6s | 8.1s | 3.1x |
| q47 | 2.9s | 14.0s | 4.8x |
| q51 | 5.6s | 36.8s | 6.6x |
| q54 | 0.1s | 0.2s | — |
| q57 | 1.9s | 14.6s | 7.7x |
| q58 | 0.1s | 0.4s | — |
| q59 | 1.3s | 5.7s | 4.4x |
| q65 | 0.3s | 1.9s | — |
| q66 | 1.3s | 12.9s | 9.9x |
| q67 | 12.1s | 51.6s | 4.3x |
| q68 | 1.0s | 7.1s | 7.1x |
| q70 | 0.8s | 6.0s | 7.5x |
| q71 | 0.6s | 6.6s | 11.0x |
| q72 | 2.2s | 12.0s | 5.5x |
| q74 | 6.2s | 30.5s | 4.9x |
| q77 | 1.0s | 8.0s | 8.0x |
| q78 | 3.1s | 21.4s | 6.9x |
| q82 | 0.1s | 0.1s | — |
| q87 | 0.4s | 2.6s | — |
| q88 | 0.1s | 0.7s | — |
| q97 | 0.8s | 4.4s | 5.5x |

### macos

| query | SF=1 | SF=4 | SF4/SF1 |
|---|---|---|---|
| q2 | 2.6s | 5.5s | 2.1x |
| q4 | 6.5s | 38.1s | 5.9x |
| q5 | 0.7s | 10.2s | 14.6x |
| q7 | 1.3s | 6.1s | 4.7x |
| q8 | 0.3s | 1.6s | — |
| q10 | 0.1s | 1.0s | — |
| q11 | 5.1s | 31.1s | 6.1x |
| q14 | 3.3s | 41.4s | 12.5x |
| q21 | 0.2s | 2.1s | — |
| q22 | 3.4s | 31.9s | 9.4x |
| q23 | 10.8s | 100.5s | 9.3x |
| q27 | 1.5s | 23.5s | 15.7x |
| q31 | 0.3s | 2.1s | — |
| q33 | 0.1s | 0.7s | — |
| q35 | 1.3s | 6.9s | 5.3x |
| q37 | 0.2s | 1.8s | — |
| q38 | 1.2s | 10.2s | 8.5x |
| q39 | 0.4s | 2.6s | — |
| q43 | 0.7s | 3.3s | 4.7x |
| q46 | 1.3s | 12.9s | 9.9x |
| q47 | 1.7s | 16.2s | 9.5x |
| q51 | 4.3s | 40.9s | 9.5x |
| q54 | 0.1s | 0.2s | — |
| q57 | 1.4s | 18.7s | 13.4x |
| q58 | 0.1s | 0.6s | — |
| q59 | 1.1s | 6.0s | 5.5x |
| q65 | 0.3s | 1.9s | — |
| q66 | 1.2s | 10.9s | 9.1x |
| q67 | 6.2s | 46.4s | 7.5x |
| q68 | 0.6s | 5.7s | 9.5x |
| q70 | 0.6s | 4.6s | 7.7x |
| q71 | 0.5s | 8.6s | 17.2x |
| q72 | 0.9s | 11.7s | 13.0x |
| q74 | 4.5s | 27.6s | 6.1x |
| q77 | 0.7s | 10.1s | 14.4x |
| q78 | 2.5s | 14.4s | 5.8x |
| q82 | 0.0s | 0.1s | — |
| q87 | 0.3s | 3.3s | — |
| q88 | 0.1s | 0.4s | — |
| q97 | 0.8s | 3.9s | 4.9x |

## macOS against the container at SF=1

| query | docker | macos | ratio |
|---|---|---|---|
| q2 | 4.3s | 2.6s | 1.7x |
| q4 | 10.2s | 6.5s | 1.6x |
| q5 | 1.3s | 0.7s | 1.9x |
| q7 | 1.7s | 1.3s | 1.3x |
| q8 | 0.5s | 0.3s | 1.7x |
| q10 | 0.1s | 0.1s | 1.0x |
| q11 | 7.0s | 5.1s | 1.4x |
| q14 | 4.2s | 3.3s | 1.3x |
| q21 | 0.3s | 0.2s | 1.5x |
| q22 | 22.9s | 3.4s | 6.7x |
| q23 | 10.7s | 10.8s | 1.0x |
| q27 | 1.8s | 1.5s | 1.2x |
| q31 | 0.4s | 0.3s | 1.3x |
| q33 | 0.3s | 0.1s | 3.0x |
| q35 | 2.1s | 1.3s | 1.6x |
| q37 | 0.1s | 0.2s | 2.0x |
| q38 | 1.3s | 1.2s | 1.1x |
| q39 | 0.4s | 0.4s | 1.0x |
| q43 | 0.7s | 0.7s | 1.0x |
| q46 | 2.6s | 1.3s | 2.0x |
| q47 | 2.9s | 1.7s | 1.7x |
| q51 | 5.6s | 4.3s | 1.3x |
| q54 | 0.1s | 0.1s | 1.0x |
| q57 | 1.9s | 1.4s | 1.4x |
| q58 | 0.1s | 0.1s | 1.0x |
| q59 | 1.3s | 1.1s | 1.2x |
| q65 | 0.3s | 0.3s | 1.0x |
| q66 | 1.3s | 1.2s | 1.1x |
| q67 | 12.1s | 6.2s | 2.0x |
| q68 | 1.0s | 0.6s | 1.7x |
| q70 | 0.8s | 0.6s | 1.3x |
| q71 | 0.6s | 0.5s | 1.2x |
| q72 | 2.2s | 0.9s | 2.4x |
| q74 | 6.2s | 4.5s | 1.4x |
| q77 | 1.0s | 0.7s | 1.4x |
| q78 | 3.1s | 2.5s | 1.2x |
| q82 | 0.1s | 0.0s | — |
| q87 | 0.4s | 0.3s | 1.3x |
| q88 | 0.1s | 0.1s | 1.0x |
| q97 | 0.8s | 0.8s | 1.0x |

## macOS against the container at SF=4

| query | docker | macos | ratio |
|---|---|---|---|
| q2 | 7.6s | 5.5s | 1.4x |
| q4 | 54.6s | 38.1s | 1.4x |
| q5 | 18.7s | 10.2s | 1.8x |
| q7 | 9.5s | 6.1s | 1.6x |
| q8 | 2.3s | 1.6s | 1.4x |
| q10 | 0.6s | 1.0s | 1.7x |
| q11 | 31.4s | 31.1s | 1.0x |
| q14 | 23.8s | 41.4s | 1.7x |
| q21 | 1.3s | 2.1s | 1.6x |
| q22 | 24.5s | 31.9s | 1.3x |
| q23 | 49.4s | 100.5s | 2.0x |
| q27 | 7.0s | 23.5s | 3.4x |
| q31 | 1.4s | 2.1s | 1.5x |
| q33 | 0.3s | 0.7s | 2.3x |
| q35 | 2.8s | 6.9s | 2.5x |
| q37 | 0.6s | 1.8s | 3.0x |
| q38 | 4.9s | 10.2s | 2.1x |
| q39 | 2.3s | 2.6s | 1.1x |
| q43 | 2.8s | 3.3s | 1.2x |
| q46 | 8.1s | 12.9s | 1.6x |
| q47 | 14.0s | 16.2s | 1.2x |
| q51 | 36.8s | 40.9s | 1.1x |
| q54 | 0.2s | 0.2s | 1.0x |
| q57 | 14.6s | 18.7s | 1.3x |
| q58 | 0.4s | 0.6s | 1.5x |
| q59 | 5.7s | 6.0s | 1.1x |
| q65 | 1.9s | 1.9s | 1.0x |
| q66 | 12.9s | 10.9s | 1.2x |
| q67 | 51.6s | 46.4s | 1.1x |
| q68 | 7.1s | 5.7s | 1.2x |
| q70 | 6.0s | 4.6s | 1.3x |
| q71 | 6.6s | 8.6s | 1.3x |
| q72 | 12.0s | 11.7s | 1.0x |
| q74 | 30.5s | 27.6s | 1.1x |
| q77 | 8.0s | 10.1s | 1.3x |
| q78 | 21.4s | 14.4s | 1.5x |
| q82 | 0.1s | 0.1s | 1.0x |
| q87 | 2.6s | 3.3s | 1.3x |
| q88 | 0.7s | 0.4s | 1.7x |
| q97 | 4.4s | 3.9s | 1.1x |

## Flagged

### critical

| kind | query | detail |
|---|---|---|
| DIFFERENT DATASET | q— | SF=4: docker and macos disagree on the row count for 9 queries (q10, q31, q37, q39, q43, q58, ...). These are different databases -- almost certainly a different dsdgen -RNGSEED -- so their answers are not comparable and no per-query check was made. Timings remain broadly indicative. |

### warn

| kind | query | detail |
|---|---|---|
| SUPER-LINEAR | q5 | docker: 1.3s at SF=1 -> 18.7s at SF=4 = 14.4x for 4x the data |
| SUPER-LINEAR | q51 | docker: 5.6s at SF=1 -> 36.8s at SF=4 = 6.6x for 4x the data |
| SUPER-LINEAR | q57 | docker: 1.9s at SF=1 -> 14.6s at SF=4 = 7.7x for 4x the data |
| SUPER-LINEAR | q66 | docker: 1.3s at SF=1 -> 12.9s at SF=4 = 9.9x for 4x the data |
| SUPER-LINEAR | q68 | docker: 1.0s at SF=1 -> 7.1s at SF=4 = 7.1x for 4x the data |
| SUPER-LINEAR | q70 | docker: 0.8s at SF=1 -> 6.0s at SF=4 = 7.5x for 4x the data |
| SUPER-LINEAR | q71 | docker: 0.6s at SF=1 -> 6.6s at SF=4 = 11.0x for 4x the data |
| SUPER-LINEAR | q77 | docker: 1.0s at SF=1 -> 8.0s at SF=4 = 8.0x for 4x the data |
| SUPER-LINEAR | q78 | docker: 3.1s at SF=1 -> 21.4s at SF=4 = 6.9x for 4x the data |
| SUPER-LINEAR | q5 | macos: 0.7s at SF=1 -> 10.2s at SF=4 = 14.6x for 4x the data |
| SUPER-LINEAR | q11 | macos: 5.1s at SF=1 -> 31.1s at SF=4 = 6.1x for 4x the data |
| SUPER-LINEAR | q14 | macos: 3.3s at SF=1 -> 41.4s at SF=4 = 12.5x for 4x the data |
| SUPER-LINEAR | q22 | macos: 3.4s at SF=1 -> 31.9s at SF=4 = 9.4x for 4x the data |
| SUPER-LINEAR | q23 | macos: 10.8s at SF=1 -> 100.5s at SF=4 = 9.3x for 4x the data |
| SUPER-LINEAR | q27 | macos: 1.5s at SF=1 -> 23.5s at SF=4 = 15.7x for 4x the data |
| SUPER-LINEAR | q38 | macos: 1.2s at SF=1 -> 10.2s at SF=4 = 8.5x for 4x the data |
| SUPER-LINEAR | q46 | macos: 1.3s at SF=1 -> 12.9s at SF=4 = 9.9x for 4x the data |
| SUPER-LINEAR | q47 | macos: 1.7s at SF=1 -> 16.2s at SF=4 = 9.5x for 4x the data |
| SUPER-LINEAR | q51 | macos: 4.3s at SF=1 -> 40.9s at SF=4 = 9.5x for 4x the data |
| SUPER-LINEAR | q57 | macos: 1.4s at SF=1 -> 18.7s at SF=4 = 13.4x for 4x the data |
| SUPER-LINEAR | q66 | macos: 1.2s at SF=1 -> 10.9s at SF=4 = 9.1x for 4x the data |
| SUPER-LINEAR | q67 | macos: 6.2s at SF=1 -> 46.4s at SF=4 = 7.5x for 4x the data |
| SUPER-LINEAR | q68 | macos: 0.6s at SF=1 -> 5.7s at SF=4 = 9.5x for 4x the data |
| SUPER-LINEAR | q70 | macos: 0.6s at SF=1 -> 4.6s at SF=4 = 7.7x for 4x the data |
| SUPER-LINEAR | q71 | macos: 0.5s at SF=1 -> 8.6s at SF=4 = 17.2x for 4x the data |
| SUPER-LINEAR | q72 | macos: 0.9s at SF=1 -> 11.7s at SF=4 = 13.0x for 4x the data |
| SUPER-LINEAR | q74 | macos: 4.5s at SF=1 -> 27.6s at SF=4 = 6.1x for 4x the data |
| SUPER-LINEAR | q77 | macos: 0.7s at SF=1 -> 10.1s at SF=4 = 14.4x for 4x the data |

### info

| kind | query | detail |
|---|---|---|
| SUB-LINEAR | q2 | docker: 4.3s at SF=1 -> 7.6s at SF=4 = 1.8x for 4x the data |
| SUB-LINEAR | q22 | docker: 22.9s at SF=1 -> 24.5s at SF=4 = 1.1x for 4x the data |
| SUB-LINEAR | q35 | docker: 2.1s at SF=1 -> 2.8s at SF=4 = 1.3x for 4x the data |
| ENVIRONMENT GAP | q22 | SF=1: macos 3.4s vs docker 22.9s = 6.7x |
| ENVIRONMENT GAP | q27 | SF=4: docker 7.0s vs macos 23.5s = 3.4x |
| ENVIRONMENT GAP | q37 | SF=4: docker 0.6s vs macos 1.8s = 3.0x |
| EMPTY | q8 | docker SF=1: returned no rows |
| DOMINATES | q22 | docker SF=1: 22.9s, 20% of the run |
| EMPTY | q54 | docker SF=1: returned no rows |
| EMPTY | q58 | docker SF=1: returned no rows |
| DOMINATES | q67 | docker SF=1: 12.1s, 11% of the run |
| DOMINATES | q4 | docker SF=4: 54.6s, 11% of the run |
| EMPTY | q8 | docker SF=4: returned no rows |
| DOMINATES | q23 | docker SF=4: 49.4s, 10% of the run |
| EMPTY | q54 | docker SF=4: returned no rows |
| EMPTY | q58 | docker SF=4: returned no rows |
| DOMINATES | q67 | docker SF=4: 51.6s, 11% of the run |
| EMPTY | q8 | macos SF=1: returned no rows |
| DOMINATES | q23 | macos SF=1: 10.8s, 16% of the run |
| EMPTY | q54 | macos SF=1: returned no rows |
| EMPTY | q58 | macos SF=1: returned no rows |
| EMPTY | q8 | macos SF=4: returned no rows |
| DOMINATES | q23 | macos SF=4: 100.5s, 18% of the run |
| EMPTY | q54 | macos SF=4: returned no rows |

