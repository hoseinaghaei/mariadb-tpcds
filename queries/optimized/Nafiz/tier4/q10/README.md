# Query 10 optimization

- v0: original correlated EXISTS query.
- v1: removes redundant date_dim joins while retaining exact April-July 2001 date-key ranges.
- v2: keeps the date_dim joins but adds the exact ranges to each sales EXISTS check.

All saved versions return identical output; BEST is chosen by measured runtime.
