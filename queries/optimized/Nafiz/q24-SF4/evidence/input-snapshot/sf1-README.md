# Query 24 optimization

## Result

`query24_v0_original.sql` remains the `BEST` version for this SF=1 database.
It completed in **0.064 seconds** and its output is saved in
`query24_v0_original.out`.

## Why the original is already fast

The query is highly selective before it reaches the larger fact tables:

- `s_market_id = 10` matches one store.
- `i_color = 'sky'` matches 402 items.

These filters allow MariaDB to avoid a broad scan, so there is no meaningful
performance problem to solve at this scale factor.

## Tested rewrite: single CTE materialization

The original `ssales` CTE is referenced once for the `sky` result and once to
calculate the average threshold. A window-function rewrite was tested to
calculate `AVG(netpaid) OVER ()` while materializing the grouped data once.

It returned the exact same empty result set, but took about **0.816 seconds**,
which is much slower than the original. It was therefore not saved as a SQL
version and is not the best choice.

## Verification

`benchmark-results.csv` and `optimization-report.html` contain the measured
original result. No additional version is saved unless it both preserves the
answer and improves time.

## Additional index test

The following temporary index was also tested:

```sql
CREATE INDEX idx_item_color_opt_q24 ON item (i_color, i_item_sk);
```

It allows a direct lookup of the 402 `sky` items, but repeated measurements
showed no meaningful improvement (roughly 105–108ms, within normal timing
variation). It was removed immediately, so no unhelpful database index or
index-dependent SQL version remains.
