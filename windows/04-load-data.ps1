<#
  Step 4 - load the .dat files.

  The committed loader sql\04_load_data.sql has Unix paths and 'LINES
  TERMINATED BY |\n' baked in. It is READ-ONLY here. This script generates a
  Windows version into windows\generated\ instead:
    * absolute paths with forward slashes (MariaDB wants those even on Windows)
    * the line terminator actually present in the generated files (CRLF here)

  Nullable columns are read into @variables and passed through NULLIF(@v,'')
  because LOAD DATA would otherwise write 0 into numeric columns and
  0000-00-00 into DATE columns for an empty field.
#>
. "$PSScriptRoot\lib\Common.ps1"

if (-not (Test-Path "$DataDir\store_sales.dat")) { throw "no .dat files - run 02-generate-data.ps1 first" }

$term = Get-DatLineTerminator (Join-Path $DataDir 'reason.dat')
Write-Step "Building the loader"
Write-Ok "line terminator: '$term'"

# Dimensions first, then facts, so the optional foreign keys can be applied after.
$order = @('date_dim','time_dim','customer_demographics','household_demographics',
 'income_band','item','reason','ship_mode','warehouse','customer_address','customer',
 'store','call_center','catalog_page','web_site','web_page','promotion',
 'store_sales','store_returns','catalog_sales','catalog_returns','web_sales',
 'web_returns','inventory','dbgen_version')

# Column nullability comes from the live schema, so it can never drift.
$rows = Invoke-Maria -Batch -Sql @"
SELECT TABLE_NAME, COLUMN_NAME, IS_NULLABLE FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA='$DbName' ORDER BY TABLE_NAME, ORDINAL_POSITION
"@
$cols = @{}
foreach ($line in $rows) {
    $p = "$line" -split "`t"
    if ($p.Count -lt 3 -or $p[0] -eq 'TABLE_NAME') { continue }
    if (-not $cols.ContainsKey($p[0])) { $cols[$p[0]] = @() }
    $cols[$p[0]] += ,@($p[1], ($p[2] -eq 'YES'))
}
if ($cols.Count -eq 0) { throw "no columns found in '$DbName' - run 03-create-schema.ps1 first" }

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("USE $DbName;")
[void]$sb.AppendLine("SET FOREIGN_KEY_CHECKS = 0;")
[void]$sb.AppendLine("SET UNIQUE_CHECKS = 0;")
foreach ($t in $order) {
    if (-not $cols.ContainsKey($t)) { Write-Warn2 "table $t not in schema, skipped"; continue }
    $names = @(); $sets = @()
    foreach ($c in $cols[$t]) {
        if ($c[1]) { $names += "@$($c[0])"; $sets += "  $($c[0]) = NULLIF(@$($c[0]), '')" }
        else       { $names += $c[0] }
    }
    $p = ConvertTo-SqlPath (Join-Path $DataDir "$t.dat")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("LOAD DATA LOCAL INFILE '$p'")
    [void]$sb.AppendLine("  INTO TABLE $t")
    [void]$sb.AppendLine("  CHARACTER SET utf8mb4")
    [void]$sb.AppendLine("  FIELDS TERMINATED BY '|' ESCAPED BY ''")
    [void]$sb.AppendLine("  LINES TERMINATED BY '$term'")
    [void]$sb.AppendLine("  (" + ($names -join ', ') + ")")
    if ($sets.Count) { [void]$sb.AppendLine("  SET`n" + ($sets -join ",`n")) }
    [void]$sb.AppendLine(";")
}
[void]$sb.AppendLine("SET UNIQUE_CHECKS = 1;")
[void]$sb.AppendLine("SET FOREIGN_KEY_CHECKS = 1;")

# written into windows\generated\, NOT into the shared sql\ folder
New-Item -ItemType Directory -Force -Path $GenDir | Out-Null
$out = Join-Path $GenDir '04_load_data.windows.sql'
$sb.ToString() | Set-Content -LiteralPath $out -Encoding UTF8
Write-Ok "wrote $out"

Write-Step "Loading (this takes several minutes)"
Invoke-MariaFile -Path $out -LocalInfile
Write-Ok "load finished"

Write-Step "Verifying row counts"
$check = ($order | ForEach-Object { "SELECT '$_', COUNT(*) FROM $_" }) -join " UNION ALL "
Invoke-Maria -Database $DbName -Batch -Sql $check
Write-Ok "store_sales must be 2880404 and inventory 11745000 at SF=1"

Write-Step "Verifying NULL handling"
Invoke-Maria -Database $DbName -Batch -Sql @"
SELECT CONCAT('ss_sold_date_sk NULL: ', SUM(ss_sold_date_sk IS NULL),
              '  bogus zeros: ',        SUM(ss_sold_date_sk = 0)) FROM store_sales
"@
Write-Ok "expect about 130093 NULLs and ZERO bogus zeros"
