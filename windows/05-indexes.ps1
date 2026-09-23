<#  Step 5 - apply the 117 indexes (OPTIONAL).
    Read-only against sql\05_indexes.sql; nothing is written back.  #>
. "$PSScriptRoot\lib\Common.ps1"

$idx = Join-Path $SqlDir '05_indexes.sql'
if (-not (Test-Path $idx)) { throw "missing $idx" }

Write-Step "Applying 117 indexes"
Write-Warn2 "load the data FIRST - indexes slow a bulk load considerably"
Write-Warn2 "this roughly doubles the database size on disk"
$sw = [Diagnostics.Stopwatch]::StartNew()
Invoke-MariaFile -Path $idx
$sw.Stop()
Write-Ok "done in $([math]::Round($sw.Elapsed.TotalMinutes,1)) minutes"

Write-Step "Refreshing statistics"
# Without this the optimizer plans against stale cardinalities.
Invoke-Maria -Database $DbName -Batch -Sql @"
ANALYZE TABLE store_sales, catalog_sales, web_sales, inventory,
              store_returns, catalog_returns, web_returns
"@

Invoke-Maria -Batch -Sql @"
SELECT CONCAT(COUNT(*),' secondary indexes') FROM
 (SELECT DISTINCT TABLE_NAME,INDEX_NAME FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA='$DbName' AND INDEX_NAME<>'PRIMARY') x
"@
Write-Ok "expected: 117"
Write-Warn2 "19 of 99 queries were SLOWER with these indexes on the reference run - see report\13"
