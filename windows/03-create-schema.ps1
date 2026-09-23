<#  Step 3 - create the tpcds database, 25 tables and 24 primary keys.
    WARNING: re-running DROPS AND RECREATES every table.  #>
. "$PSScriptRoot\lib\Common.ps1"

$schema = Join-Path $SqlDir '01_schema.sql'
if (-not (Test-Path $schema)) { throw "missing $schema" }

Write-Step "Creating schema from 01_schema.sql"
Write-Warn2 "this DROPS AND RECREATES all 25 tables - any loaded data is lost"
Invoke-MariaFile -Path $schema
Write-Ok "applied"

Write-Step "Verifying"
$q = @"
SELECT CONCAT(COUNT(*),' tables') FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DbName';
SELECT CONCAT(COUNT(*),' columns') FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$DbName';
SELECT CONCAT(COUNT(DISTINCT TABLE_NAME),' primary keys') FROM information_schema.STATISTICS
 WHERE TABLE_SCHEMA='$DbName' AND INDEX_NAME='PRIMARY';
"@
Invoke-Maria -Sql $q -Batch
Write-Ok "expected: 25 tables, 429 columns, 24 primary keys"
