# TPC-DS Query 90: Optimization 

## What the query does

Compares web orders placed around midday (hours 12-13) with orders placed in the evening (hours 17-18), and returns the ratio `midday count / evening count`.

Only orders that match all of these are counted:

- Household has exactly 1 dependent (`hd_dep_count = 1`)
- Web page has 5000-5200 characters (`wp_char_count`)

Tables: `web_sales` (fact), `web_page`, `household_demographics`, `time_dim` (small lookups).

## Constraints

- No new tables.
- Allowed techniques: filter first, optimizer hints (`straight_join`), join reordering, and indexes.

## Original query: what the plan showed

The original query is two subqueries (`at` for midday, `pt` for evening) cross joined, then divided. Both subqueries do identical work.

| Observation (no index) | Value |
|---|---|
| Total time (analyze) | about 1.48 s |
| `web_sales` access | full scan, 719k rows, done twice |
| `household_demographics` lookups | 719k per subquery (largest single cost, ~420 ms each) |
| `time_dim` lookups | about 70k per subquery |
| `web_page` lookups | about 8k per subquery |

Cause: the joins start from the big table and filter late. Every `web_sales` row triggers a lookup before the selective filters can discard it.

## Selectivity of each filter (from the plan)

| Table | Rows kept |
|---|---|
| `web_page` | about 2% |
| `household_demographics` | about 10% |
| `time_dim` (hours 12,13,17,18) | about 23% |

Best order is most selective first: `web_page`, then `household_demographics`, then `time_dim`. Starting from `time_dim` would be the worst choice.

## Optimizations applied

### 1. Single pass with conditional aggregation (V1)

Merge the two subqueries into one. Filter `t_hour in (12,13,17,18)` and split the counts with `sum(t_hour between ...)`. The `web_sales` scan happens once instead of twice. Join order forced with `straight_join`: `web_sales -> web_page -> household_demographics -> time_dim`.

### 2. Covering index

```sql
create index idx_ws_page_hdemo_time
  on web_sales (ws_web_page_sk, ws_ship_hdemo_sk, ws_sold_time_sk);
```

- Lets the database find rows by page and household directly, with no `web_sales` scan.
- Covering: all three columns the query needs are in the index (`using_index: true`).
- One index serves the whole query. Size is small: three 4-byte columns plus the primary key.

### 3. Drive from the small tables (V2)

Start from `web_page` (60 rows, 1 matches) and `household_demographics` (720 matching households). This builds a tiny set of (page, household) pairs, and each pair probes the index once. The missing join condition between these two tables is intentional.

```sql
select straight_join
       cast(sum(t_hour between 12 and 13) as decimal(15,4))
     / cast(sum(t_hour between 17 and 18) as decimal(15,4)) as am_pm_ratio
from web_page
join household_demographics on hd_dep_count = 1
join web_sales              on ws_web_page_sk = wp_web_page_sk
                           and ws_ship_hdemo_sk = hd_demo_sk
join time_dim               on t_time_sk = ws_sold_time_sk
                           and t_hour in (12,13,17,18)
where wp_char_count between 5000 and 5200;
```

## Results

Scale factor 1.

| Version | Time |
|---|---|
| Original, cold run | 3.199 s |
| Original, warm (avg of 6) | 1.50 s |
| V1 (single pass), no index | 0.55 s |
| V1 with index | 0.175 s |
| Original with index | 0.015 s |
| V2 with index | 0.006 s |

V2 with index is about 250x faster than the warm original.

## Why each result looks the way it does

- V1 without index: the scan and the 719k `web_page` lookups are what remain.
- V1 with index: the scan becomes an index-only scan (1,355 pages instead of 13,766), but it still reads all 719k entries, because `web_sales` is the first table.
- Original with index: the optimizer picked `web_page` first on its own, so it never scans `web_sales` (about 720 index probes per subquery).
- V2: forces that good order and also removes the second subquery.

Lesson: merging two scans only wins when there is no index to narrow them. Once an index can serve each branch, the order of the joins matters more than the number of passes.

## How to verify

Run each version with `analyze format=json` and check:

- `web_sales` shows `access_type: ref`, `key_length: 10`, `using_index: true`
- `web_sales` `r_loops` is around 720 (one probe per page/household pair)
- No `access_type: ALL` or `index` on `web_sales`

## Scale testing (10 GB)

Not measured yet. Expectations:

- `household_demographics` has a fixed size, and `web_page` grows only slightly, so the number of index probes stays small.
- Only the rows returned grow with scale, so V2 should stay in the tens of milliseconds, while scan-based plans grow roughly 10x.
- The index will grow with `web_sales`. If storage matters more than speed, drop `ws_sold_time_sk` from the index to make it smaller. The few thousand matching rows are then read from the table.
- After the test, record the index size and the V2 time here.