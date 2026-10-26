# Benchmark results across scale factors

Generated 2026-10-26 14:53. 2 runs, 40 queries.

## Totals

| environment | scale | queries | errors | total |
|---|---:|---:|---:|---:|
| macos | 1 | 40 | 0 | 82.9s |
| macos | 4 | 40 | 0 | 400.9s |

## Scaling

Per-query response time at each scale factor.

### macos

| query | SF=1 | SF=4 | SF4/SF1 |
|---|---|---|---|
| q2 | 3.5s | 6.8s | 1.9x |
| q4 | 7.3s | 37.1s | 5.1x |
| q5 | 0.7s | 11.7s | 16.7x |
| q7 | 1.4s | 6.4s | 4.6x |
| q8 | 0.4s | 1.5s | — |
| q10 | 0.1s | 0.4s | — |
| q11 | 5.6s | 29.8s | 5.3x |
| q14 | 3.5s | 23.2s | 6.6x |
| q21 | 0.2s | 0.7s | — |
| q22 | 3.2s | 25.0s | 7.8x |
| q23 | 10.2s | 51.5s | 5.0x |
| q27 | 1.5s | 7.9s | 5.3x |
| q31 | 0.4s | 1.6s | — |
| q33 | 0.2s | 0.3s | — |
| q35 | 3.9s | 3.9s | 1.0x |
| q37 | 0.3s | 1.7s | — |
| q38 | 1.8s | 5.6s | 3.1x |
| q39 | 0.5s | 1.3s | 2.6x |
| q43 | 0.7s | 2.6s | 3.7x |
| q46 | 1.7s | 6.8s | 4.0x |
| q47 | 2.0s | 9.8s | 4.9x |
| q51 | 5.2s | 23.7s | 4.6x |
| q54 | 0.1s | 0.2s | — |
| q57 | 1.5s | 13.5s | 9.0x |
| q58 | 0.1s | 0.3s | — |
| q59 | 1.2s | 4.8s | 4.0x |
| q65 | 1.0s | 3.3s | 3.3x |
| q66 | 1.9s | 9.1s | 4.8x |
| q67 | 6.5s | 30.0s | 4.6x |
| q68 | 0.6s | 4.9s | 8.2x |
| q70 | 0.6s | 3.7s | 6.2x |
| q71 | 0.7s | 6.1s | 8.7x |
| q72 | 1.2s | 8.6s | 7.2x |
| q74 | 5.8s | 23.1s | 4.0x |
| q77 | 1.8s | 8.2s | 4.6x |
| q78 | 3.3s | 16.0s | 4.8x |
| q82 | 0.1s | 0.1s | — |
| q87 | 1.3s | 5.5s | 4.2x |
| q88 | 0.1s | 0.4s | — |
| q97 | 0.8s | 3.8s | 4.7x |

## Flagged

### warn

| kind | query | detail |
|---|---|---|
| SUPER-LINEAR | q5 | macos: 0.7s at SF=1 -> 11.7s at SF=4 = 16.7x for 4x the data |
| SUPER-LINEAR | q14 | macos: 3.5s at SF=1 -> 23.2s at SF=4 = 6.6x for 4x the data |
| SUPER-LINEAR | q22 | macos: 3.2s at SF=1 -> 25.0s at SF=4 = 7.8x for 4x the data |
| SUPER-LINEAR | q57 | macos: 1.5s at SF=1 -> 13.5s at SF=4 = 9.0x for 4x the data |
| SUPER-LINEAR | q68 | macos: 0.6s at SF=1 -> 4.9s at SF=4 = 8.2x for 4x the data |
| SUPER-LINEAR | q70 | macos: 0.6s at SF=1 -> 3.7s at SF=4 = 6.2x for 4x the data |
| SUPER-LINEAR | q71 | macos: 0.7s at SF=1 -> 6.1s at SF=4 = 8.7x for 4x the data |
| SUPER-LINEAR | q72 | macos: 1.2s at SF=1 -> 8.6s at SF=4 = 7.2x for 4x the data |

### info

| kind | query | detail |
|---|---|---|
| SUB-LINEAR | q2 | macos: 3.5s at SF=1 -> 6.8s at SF=4 = 1.9x for 4x the data |
| SUB-LINEAR | q35 | macos: 3.9s at SF=1 -> 3.9s at SF=4 = 1.0x for 4x the data |
| EMPTY | q8 | macos SF=1: returned no rows |
| DOMINATES | q23 | macos SF=1: 10.2s, 12% of the run |
| EMPTY | q54 | macos SF=1: returned no rows |
| EMPTY | q58 | macos SF=1: returned no rows |
| EMPTY | q8 | macos SF=4: returned no rows |
| DOMINATES | q23 | macos SF=4: 51.5s, 13% of the run |
| EMPTY | q54 | macos SF=4: returned no rows |

