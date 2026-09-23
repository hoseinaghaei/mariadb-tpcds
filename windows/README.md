# Running TPC-DS on MariaDB — Windows

Self-contained Windows setup. **Nothing here modifies the committed macOS
artifacts**; see [Isolation](#isolation) below.

> **Untested.** These scripts were written on macOS and have not been executed
> on a Windows machine. The logic follows the verified Unix pipeline and the
> Windows-specific differences are handled deliberately, but expect to debug
> the first run. Every script reports what it is doing before doing it.

---

## What is different on Windows

Four real differences, each handled:

| | Unix | Windows | Handled by |
|---|---|---|---|
| **Line endings** | `.dat` files are LF | **CRLF** — `print.c` opens them with `fopen(path,"wt")`, text mode | loader detects the terminator and emits `LINES TERMINATED BY '\|\r\n'` |
| **Build** | `make` with a patched `MACOS` target | MSBuild on the shipped VS2005 solution; `config.h` already has a `WIN32` block, **no source porting needed** | `01-build-dsdgen.ps1` |
| **Auth** | unix_socket, no password | no socket auth — user/password always required | `$env:TPCDS_USER` / `$env:TPCDS_PASSWORD` |
| **Paths** | `/` | MariaDB still wants `/` in `LOAD DATA` paths | loader converts them |

The CRLF one is the trap. Loading Windows-generated `.dat` files with the
Unix `LINES TERMINATED BY '\|\n'` leaves a trailing `\r` on the last column of
every row — silently, with no error.

---

## Prerequisites

1. **Build Tools for Visual Studio** with the *Desktop development with C++*
   workload — <https://visualstudio.microsoft.com/downloads/>
   The toolkit ships a **Visual Studio 2005** solution that must be upgraded.
   `devenv.exe /upgrade` does it, which means the **full IDE**, not just Build
   Tools. With Build Tools only, open `dbgen2.sln` in Visual Studio once by
   hand.
2. **MariaDB** — <https://mariadb.org/download/>, with `bin\` on `PATH`.
3. **Python 3** — <https://python.org/downloads/>
4. **~5 GB free disk** at SF=1 (1.2 GB of flat files + ~3.2 GB loaded).

Enable `local_infile` on the server. In `my.ini` under `[mysqld]`:

```ini
local_infile=1
```

then restart the MariaDB service.

---

## Setup

```powershell
# allow local scripts for this session only
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# credentials (no socket auth on Windows)
$env:TPCDS_USER     = 'root'
$env:TPCDS_PASSWORD = 'yourpassword'

cd path\to\dw\windows
.\00-check-prerequisites.ps1
```

Optional overrides: `$env:TPCDS_SCALE` (default 1), `$env:TPCDS_DB` (default
`tpcds`), `$env:TPCDS_HOST`, `$env:TPCDS_PORT`.

---

## Steps

Run in order, or `.\run-all.ps1` for everything.

| Script | Does | Time |
|---|---|---|
| `00-check-prerequisites.ps1` | verifies tools, server, `local_infile`, disk. **Changes nothing.** | seconds |
| `01-build-dsdgen.ps1` | upgrades the VS2005 solution, builds the 5 exes + `tpcds.idx` | ~2 min |
| `02-generate-data.ps1` | `dsdgen -SCALE 1`, then verifies row counts and detects the line terminator | ~5 min |
| `03-create-schema.ps1` | **DROPS AND RECREATES** 25 tables from `sql\01_schema.sql` | seconds |
| `04-load-data.ps1` | generates a Windows loader, loads 19.5 M rows, verifies NULL handling | ~10 min |
| `05-indexes.ps1` | 117 indexes + `ANALYZE TABLE` (optional) | ~5 min |
| `06-run-queries.ps1` | runs the 99 queries and compares to the answer sets | 30–60 min |
| `compare.ps1` | base vs indexed | seconds |

```powershell
.\run-all.ps1                 # everything, with indexes
.\run-all.ps1 -SkipIndexes    # baseline only
.\run-all.ps1 -Force          # no confirmation prompt
```

To measure the index effect, run the queries twice:

```powershell
.\03-create-schema.ps1 ; .\04-load-data.ps1
.\06-run-queries.ps1 -Tag base      # no indexes
.\05-indexes.ps1
.\06-run-queries.ps1 -Tag indexed
.\compare.ps1
```

---

## Isolation

The whole point of this folder is that it cannot disturb the existing setup.

- **Every script refuses to run on a non-Windows host.** `Assert-Windows` in
  `lib\Common.ps1` runs at import and exits before anything else happens.
- **Generated files go to `windows\generated\`**, never into the shared `sql\`
  or `queries\` folders. `sql\04_load_data.sql` is read-only here; the Windows
  loader is written as `windows\generated\04_load_data.windows.sql`.
- **`sql\*.sql` and `queries\*` are only ever read.**
- Query results still land in `queries\results\<tag>\`, so a Windows run and a
  Unix run are directly comparable — use distinct `-Tag` values if you want to
  keep both.

The one genuinely destructive action is `03-create-schema.ps1`, which drops and
recreates all 25 tables. It says so before running, and `run-all.ps1` asks for
confirmation unless given `-Force`.

---

## Troubleshooting

**`devenv.exe not found`** — you installed Build Tools rather than the full
Visual Studio. Open `DSGen-software-code-4.0.0\tools\dbgen2.sln` in Visual
Studio once to upgrade it, then re-run `01-build-dsdgen.ps1`.

**`The used command is not allowed with this MariaDB version`** — `local_infile`
is off. Set it server-side in `my.ini` *and* keep the client's
`--local-infile=1` (the scripts pass it).

**Row counts right but the last column looks wrong** — the line terminator was
misdetected. Check what `02-generate-data.ps1` reported and confirm the
`LINES TERMINATED BY` in `windows\generated\04_load_data.windows.sql`.

**`Access denied`** — `$env:TPCDS_USER` / `$env:TPCDS_PASSWORD` are unset in
*this* shell. They do not persist across windows unless you set them with
`setx`.

**query95 runs for over 30 minutes** — expected without indexes. It is a
`web_sales` self-join on `ws_order_number`; with `idx_ws_order_number` it takes
about a second. Run `05-indexes.ps1` first, or skip it in the baseline.
