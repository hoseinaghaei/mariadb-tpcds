# Benchmark results across scale factors

Generated 2026-10-26 22:07. 2 runs, 40 queries.

## Totals

| environment | scale | queries | errors | total |
|---|---:|---:|---:|---:|
| docker | 1 | 40 | 0 | 114.8s |
| docker | 4 | 40 | 0 | 491.4s |

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

## Flagged

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

### info

| kind | query | detail |
|---|---|---|
| SUB-LINEAR | q2 | docker: 4.3s at SF=1 -> 7.6s at SF=4 = 1.8x for 4x the data |
| SUB-LINEAR | q22 | docker: 22.9s at SF=1 -> 24.5s at SF=4 = 1.1x for 4x the data |
| SUB-LINEAR | q35 | docker: 2.1s at SF=1 -> 2.8s at SF=4 = 1.3x for 4x the data |
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

