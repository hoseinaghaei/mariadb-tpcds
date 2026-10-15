# Verified local evidence, 14 October 2026

Dataset: toolkit 4.0.0, generator SF=1, data seed 10. Database:
`tpcds_riccio_sf1`. Machine: Ryzen 5 3500U, Linux, 6.7 GiB RAM. MariaDB
10.11.14; 2 GiB buffer pool and 16 MiB temporary-table limits.

`measurements.csv` and `summary.json` contain 81 checked ordinary repetitions.
`manifest.json` records 154 successful saved runs including warm-ups,
diagnostics and synthetic validation. All 27 timing groups have three trials.
Full XML outputs, canonical results, archived input SQL, execution plans,
database settings, index definitions and job manifests are in `raw_trials.zip`.
Run labels keep probes and diagnostics separate from measurements. The diagnostic
runner's initial comment-semicolon parsing error was repaired before resuming;
it did not execute a failed database trial.

There are two physical designs. `pk` is the original primary-key-only design.
`reference` adds 117 visible secondary indexes. `reference_q39_final` is a
separate series under that same indexed physical design, with fresh baselines
for the final Q39 corrections. Do not merge those series accidentally.

| Query | Chosen indexed variant | Original median (s) | Candidate median (s) | Speedup |
| --- | --- | ---: | ---: | ---: |
| 4 | v2 | 54.866 | 15.209 | 3.61× |
| 5 | v1 | 112.735 | 10.144 | 11.11× |
| 31 | v2 | 46.947 | 15.957 | 2.94× |
| 39 | v6, final series | 81.236 | 0.817 | 99.44× |
| 51 | v1 | 60.528 | 48.549 | 1.25× |

Q39's indexed gain includes avoiding the bad warehouse/item index path. Its
primary-key original median is 3.280 seconds, so the 99× figure must not be
presented as a gain over that primary-key baseline. The initial independent v4
rewrite has a primary-key median of 0.818 seconds; v6 was selected after the
indexed diagnosis and has not received a separate full-scale primary-key timing
series. Re-run the chosen candidate on every new configuration.

`final_validation.json` records zero orphans across 107 declared relationships,
unchanged counts in all 25 tables, unchanged primary keys, unique customer IDs
and 117 visible secondary indexes. Environment records are in `environment/`.
Index build time was 301.620 seconds; added index storage was 4,010,737,664 bytes.

These are preliminary one-scale Linux measurements. The final Mac, four scales,
full 99-query workload, required refresh/concurrency tests and integrated course
PDF/ZIP are still group work. Read [the workflow](../../README.md),
[the draft report](../../../report/riccardo-query-experiments.md), and the per-query
notes for assumptions, unsuccessful variants and reproducible commands.
