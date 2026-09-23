# Step 12 — Qualification parameters and the answer sets

This step documents a correctness trap that invalidates naive answer-set
comparison, and how the queries were made comparable.

## The trap

`dsqgen -QUALIFY Y` does **not** produce the qualification queries the answer
sets were computed from. Reading the source settles it — `QgenMain.c:293`:

```c
if (is_set("QUALIFY"))
    nQID = nQuery;                            /* ascending order */
else
    nQID = getPermutationEntry(pPermutation, nQuery);
```

`QUALIFY` controls only the **order** queries are emitted in. Substitution
parameters still come from the RNG, seeded by `-RNGSEED` (default `19620718`).
The help text — *"generate qualification queries in ascending order"* — is
accurate; it is easy to read more into it than it says.

Clause 4.3.1 confirms parameters are meant to be unpredictable for a real run:

> The value for the RNGSEED option, <SEED>, is selected as the timestamp of the
> end of the database load time … RNGSEED guarantees that the query
> substitution parameter values are not known prior to running the power and
> throughput tests.

The answer sets instead correspond to the **fixed values in Appendix B**.

### Observed

Query 3, spec Appendix B (B.3): `MONTH.01=11`, `MANUFACT=128`,
`AGGC=ss_ext_sales_price`.

| Generation method | produced |
|---|---|
| `-TEMPLATE query3.tpl -QUALIFY Y` | `MANUFACT=436`, `MONTH=12` |
| full 99-template stream, `-QUALIFY Y` | `MANUFACT=816`, `MONTH=11` |
| **Appendix B** | **`MANUFACT=128`, `MONTH=11`** |

Neither matches. Comparing those results against `3.ans` is meaningless — it is
a different question against the same data.

A second, separate mistake of ours showed up here too: generating each query
with `-TEMPLATE` individually resets the RNG stream, so per-query generation
does not even agree with full-stream generation.

## The fix

Appendix B lists the qualification parameters for all 99 queries in a regular
format:

```
B.3   query3.tpl
      Qualification Substitution Parameters:
      • MONTH.01=11
      • MANUFACT =128
      • AGGC = ss_ext_sales_price
```

These were parsed out of the specification PDF (**98 of 99 queries**; query 14
lists none) and used to rewrite each template's `define` lines, replacing the
random generator with the fixed value:

```
 define MONTH = random(11,12,uniform);      ->   define MONTH = 11;
 define MANUFACT= random(1,1000,uniform);   ->   define MANUFACT= 128;
 define AGGC= text({"ss_ext_sales_price",1},{...}); -> define AGGC= text({"ss_ext_sales_price",1});
```

Numeric values are substituted bare; string values as a single-choice
`text({"...",1})`. Regenerating query 3 from the patched template now yields
`i_manufact_id = 128` and `d_moy = 11` — exactly Appendix B.

## Where this does not work — 14 queries

Some parameters are **list-valued**, e.g. query 10:

```
define COUNTY = ulist(dist(fips_county,2,1),10);
```

used as `[COUNTY.1] … [COUNTY.5]`, with Appendix B giving five discrete county
names. dsqgen has no construct for pinning a `ulist` to a fixed sequence, so
simple substitution breaks the template (it generates nothing).

Affected: **8, 10, 12, 13, 18, 20, 28, 37, 41, 48, 64, 74, 82, 85.**

These fall back to RNG parameters. They still execute, but **their results
cannot be compared against the published answer sets**, and they are recorded
as such in `queries/qualification/NOT_ANSWER_VALIDATED.txt`. Pinning them would
require either patching dsqgen or post-substituting the literals into the
generated SQL — worth doing, not done here.

## Two query sets

| Set | Parameters | Purpose |
|---|---|---|
| `queries/mariadb/` | dsqgen RNG (seed 19620718) | timing / optimization work |
| `queries/qualification/` | Appendix B for 85, RNG for 14 | correctness vs. answer sets |

Both carry the same dialect adaptations from [step 10](10-adapt-queries.md);
the hand fixes were re-applied to the qualification set from saved patches.
