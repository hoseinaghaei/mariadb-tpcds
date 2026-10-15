# Draft contribution: optimizing TPC-DS queries 4, 5, 31, 39 and 51

This chapter describes independent experiments for Part I of the course project.
It covers five checked-in query instances on one dataset and machine. It must be
combined with the group's four-scale benchmark, full-workload validation and
implementation sections before producing the submission PDF. Original repository
results are historical evidence from its author, not measurements by this group.

## Environment and data provenance

- TPC-DS toolkit: 4.0.0, generated on 14 October 2026 using
  `dsdgen -SCALE 1 -RNGSEED 10 -DIR ../data/sf1_seed10`.
- Database: the isolated `tpcds_riccio_sf1`, MariaDB
  `10.11.14-MariaDB-0ubuntu0.24.04.1`.
- Machine: AMD Ryzen 5 3500U, Ubuntu/Linux, 6.7 GiB RAM. The recorded machine
  had substantial swap use; this limits the precision of conclusions from three
  trials and makes final-machine replication necessary.
- InnoDB buffer pool: 2,147,483,648 bytes. Session temporary-table and heap-table
  limits: 16,777,216 bytes each. Global settings were not changed.
- 25 loaded tables; key fact counts: store_sales 2,879,152, catalog_sales
  1,441,837, web_sales 720,378 and inventory 11,745,000. All loaded table counts
  were checked before the experiments. Data occupy 2,859,876,352 table bytes.
- The five baseline SQL files exactly match their committed versions at
  repository commit `eeeaf679a5edf66b12265e1f8c6ba907508d14cc`.

Two physical designs are compared. The first has primary keys and no secondary
indexes. The second adds the repository's 117 indexes, with all visible to the
optimizer. Their build took 301.620 seconds and added 4,010,737,664 index bytes
(3.74 GiB). Storage and build time are implementation costs; the workload must
justify them. ANALYZE TABLE succeeded for all 25 tables after the build.

The generator scale of 1 is not the course's final normalized reference scale.
The group has not selected its largest feasible dataset, four scale mapping or
final Mac configuration. No extrapolated times are reported as measurements.

## Measurement and correctness method

We run one client at a time on unchanged data. Each ordinary trial uses a fresh
MariaDB client connection, enables IGNORE_SPACE and PIPES_AS_CONCAT, disables
the query cache and caps each statement at 600 seconds. PIPES_AS_CONCAT is
necessary for Q5's entity identifiers. The measured interval includes connection
and session setup, execution and complete result transfer. Database metadata is
collected separately before the timed interval.

Exploratory probes serve as discarded initial executions in the primary-key
phase. Three repetitions per selected candidate and baseline are retained, with
interleaved versions. The initial Q31 rounds use the same v0/v1/v2 order; Q4, Q5
and Q51 alternate the order in their second round. Q39 v4 was added after the
main primary-key series and measured three times separately. These order choices
remain in the raw manifests and are limitations of the preliminary comparisons.
In the indexed phase, each query receives a baseline and candidate warm-up
immediately before three alternating baseline/candidate rounds.

No cache reset is performed, and warm-up does not guarantee that the working set
fits the buffer pool. Timing ranges and raw trials are retained. The main statistic
is the median; the speedup is the original median divided by the candidate median
within the same physical configuration. EXPLAIN, ANALYZE, synthetic tests and
setup operations are excluded from those statistics. Three trials do not provide
a precise confidence interval or establish a universal speedup.

Results are read through MariaDB XML output and compared as ordered result sets.
The comparison preserves duplicate field names, NULLs, empty strings and the
complete numeric text returned by the client; it never rounds to two decimals.
Every retained candidate trial is compared to the original. Indexed original
warm-ups are also compared to the saved primary-key originals. For Q39 both
result sets are checked separately, rather than treating their 143 combined rows
as one output. Original row counts are Q4: 6, Q5: 100, Q31: 44, Q39: 141 and 2,
and Q51: 100. LIMIT 100 remains part of Q4/Q5/Q51's original semantics.

Small synthetic fixtures provide nonempty tests of conditions that may be rare
in generated data. They use temporary tables scoped to one client connection
and do not modify the permanent dataset. They cover missing periods, NULL
aggregates, zero denominators, duplicate business identifiers, orphan facts,
date boundaries, older sales linked to current returns, negative increments and
channel-only dates. These are equivalence tests, not official qualification
against Appendix B answer sets.

## Measured indexed results

The following values are medians of three ordinary runs per version with all
117 reference indexes visible. Q39 uses its separate final correction series
with fresh original runs and alternating candidates; the other queries use the
main indexed series. All retained repetitions matched the original exactly.

| Query | Candidate | Original median (s) | Candidate median (s) | Speedup |
| --- | --- | ---: | ---: | ---: |
| 4 | v2 | 54.866 | 15.209 | 3.61× |
| 5 | v1 | 112.735 | 10.144 | 11.11× |
| 31 | v2 | 46.947 | 15.957 | 2.94× |
| 39 | v6 | 81.236 | 0.817 | 99.44× |
| 51 | v1 | 60.528 | 48.549 | 1.25× |

The primary-key history and all ablations are in the per-query notes and
`experiments/evidence/riccio_sf1_20261014/measurements.csv`. Q4, Q5 and Q31 have
large repeatable improvements in these local trials. Q51's gain is modest.
Q39's large gain depends on avoiding the bad warehouse/item-driven indexed plan;
it is not a general promise that every query or scale becomes 99 times faster.

The final checks found zero orphan rows across all 107 declared relationships,
unchanged counts in all 25 permanent tables, all original primary keys retained,
and 117 visible secondary indexes. The dataset has 19,558,918 rows including
one dbgen_version row. Customer business IDs remain unique and non-NULL.

## Query-specific reasoning

### Q4: aggregate both years before joining customer details

The original creates two yearly aggregates per channel and carries customer
attributes through them. The candidate computes the original monetary expression
conditionally for each year, grouped by customer surrogate key, then joins the
three channel results and customer details. The plan contains three sales-table
nodes instead of six. Both year groups must exist, and the first-year positivity
tests and guarded division comparisons remain unchanged.

Grouping by surrogate key requires unique customer business IDs. The scale-1
dataset has 100,000 customer rows and 100,000 distinct c_customer_id values.
The same assumption must be validated at every scale and after refresh. See
[Q4's experiment notes](../queries/optimized/q4/README.md).

### Q5: restrict the UNION branches before materialization

The candidate joins date_dim inside every sales and returns branch and applies
the original inclusive 28 August–11 September 1998 interval there. The existing
outer predicates remain. UNION ALL, zero contributions, NULL handling, business-ID
grouping and rollup levels are retained. An important distinction is that web
returns use the return date; their lookup into web_sales must still find sales
from before the interval. See [Q5's notes](../queries/optimized/q5/README.md).

### Q31: compute quarter groups once per channel

The primary-key actual plans show three full store_sales scans and three full
web_sales scans in the original. The pivot candidate reads each channel once,
computes its three quarterly groups, selects those existing totals with MAX(CASE)
and performs one channel join. COUNT(DISTINCT quarter)=3 preserves the original
requirement that all three groups exist. Missing quarters are not filled with
zeros. The original denominator guards, ratio comparisons and ordering remain.
Simple predicate pushdown alone adds little because the optimizer already pushes
quarter/year conditions into the original derived results. See
[Q31's notes](../queries/optimized/q31/README.md).

### Q39: move dimension lookups after the inventory aggregation

The coefficient of variation is the sample standard deviation divided by the
mean. Both functions and both coefficient thresholds remain unchanged. Grouping
inventory by its warehouse key, item key and month before joining the item and
warehouse dimensions avoids repeated dimension lookups for raw observations.
Both inner joins are retained, so orphan groups still disappear.

The actual primary-key plan for the first original SELECT performs 405,000 item
lookups across the two months. The combined late-join aggregation tested in v3
performs 5,235 such lookups. Sharing a temporary table without moving those joins
(v2) is slower than the original; sharing alone is not the cause of the gain.
The v4 variant keeps two independent SELECT statements, but with the 117 indexes
its grouped results can be evaluated laterally from a warehouse/item key. The
plan then selects idx_inv_warehouse_sk or idx_inv_item_sk and reaches the date
filter late; its median is 44.234 seconds despite its 0.818-second primary-key
median. The final v6 adds STRAIGHT_JOIN to keep each grouped inventory result
before its dimension lookups. Its indexed plan uses date_dim followed by inventory
PRIMARY with inv_date_sk and no lateral materializations. The actual first SELECT
reads 225,000 April and 180,000 May inventory observations and performs 2,311
item lookups, with one materialization per month. Both fixes were measured in
fresh rounds: v5 forces inventory PRIMARY and has a median of 0.867 seconds;
v6 fixes join order and has a median of 0.817 seconds. The fresh original median
is 81.236 seconds. v6 is selected without naming an index. The slightly faster
shared-table v3 on the primary-key design remains an option for unchanged data. See [Q39's notes](../queries/optimized/q39/README.md).

### Q51: combine daily channel keys before the window computations

The original emulates a full outer join through two UNION branches, which repeat
the channel materializations. The candidate computes each daily channel aggregate
once and combines the unique item/date keys. Presence flags mask cumulative values
to NULL on dates without that channel's original row. It retains both the running
SUM and subsequent running MAX: negative sales make those different operations.
The final fields, predicate, order and LIMIT are unchanged. The primary-key gain
is smaller than the others and requires careful replication. See
[Q51's notes](../queries/optimized/q51/README.md).

## Remaining work before submission

Run these candidates on the agreed final machine and four full generated scales
with identical parameters and controlled configurations. Validate customer-ID
uniqueness and results at every scale. Measure all 99 queries and record errors,
timeouts, load time, warehouse/index storage and correctness evidence. Confirm
the lecturer's refresh, concurrency and metric requirements and implement that
workload accordingly; this five-query chapter does not establish completion.

Use [the experiment guide](../experiments/README.md) for reproduction, evidence
locations, group decisions and the final PDF/ZIP checklist. Generate the submitted
PDF from the group's integrated report, and test the submitted ZIP from a fresh
directory. Part I is due 1 November 2026; TPC-DI Part II is separate and due
24 December 2026.
