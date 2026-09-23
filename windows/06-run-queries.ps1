<#
  Step 6 - run the 99 adapted queries, time them, compare to the answer sets.

  Wraps the same queries\run_query.py the Unix side uses, so results are
  directly comparable. Nothing in queries\ is modified; results land in
  queries\results\<tag>\.

    .\06-run-queries.ps1                  # all 99, tag 'indexed'
    .\06-run-queries.ps1 -Tag base        # before applying indexes
    .\06-run-queries.ps1 -From 1 -To 20   # a subset
#>
param(
    [string]$Tag  = 'indexed',
    [int]$From    = 1,
    [int]$To      = 99,
    [int]$TimeoutMinutes = 60
)
. "$PSScriptRoot\lib\Common.ps1"

$py = ((Get-Command python -ErrorAction SilentlyContinue) ??
       (Get-Command python3 -ErrorAction SilentlyContinue)).Source
if (-not $py) { throw "Python 3 not found" }

$runner = Join-Path $QDir 'run_query.py'
if (-not (Test-Path $runner)) { throw "missing $runner" }

# run_query.py shells out to a bare `mariadb` with no credentials, which works
# with socket auth on Unix but never on Windows. Pass them through instead.
$env:TPCDS_USER     = $env:TPCDS_USER
$env:TPCDS_PASSWORD = $env:TPCDS_PASSWORD

Write-Step "Running queries $From..$To  (tag: $Tag)"
Write-Warn2 "some queries take many minutes; query95 needs its index or it runs for over half an hour"

$results = @()
Push-Location $QDir
try {
    foreach ($q in $From..$To) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $line = & $py $runner $q $Tag 2>&1 | Select-Object -Last 1
        $sw.Stop()
        Write-Host ("  {0,-60} {1,7:N1}s" -f "$line", $sw.Elapsed.TotalSeconds)
        $results += [pscustomobject]@{ Query = $q; Seconds = $sw.Elapsed.TotalSeconds; Line = "$line" }
    }
} finally { Pop-Location }

Write-Step "Summary"
Write-Ok "$($results.Count) queries, total $([math]::Round(($results | Measure-Object Seconds -Sum).Sum,1))s"
Write-Host "  slowest:"
$results | Sort-Object Seconds -Descending | Select-Object -First 5 |
    ForEach-Object { Write-Host ("    query{0,-4} {1,8:N1}s" -f $_.Query, $_.Seconds) }
Write-Ok "compare two tagged runs with:  .\compare.ps1"
