<#
  Run every step in order, from a clean machine to a measured result.

  This is destructive: step 3 drops and recreates all 25 tables. It asks for
  confirmation first unless -Force is given.
#>
param([switch]$Force, [switch]$SkipIndexes)
. "$PSScriptRoot\lib\Common.ps1"

if (-not $Force) {
    Write-Warn2 "This will DROP AND RECREATE every table in the '$DbName' database."
    $a = Read-Host "Type 'yes' to continue"
    if ($a -ne 'yes') { Write-Host "aborted"; exit 1 }
}

$steps = @('00-check-prerequisites.ps1','01-build-dsdgen.ps1','02-generate-data.ps1',
           '03-create-schema.ps1','04-load-data.ps1')
if (-not $SkipIndexes) { $steps += '05-indexes.ps1' }

foreach ($s in $steps) {
    Write-Host "`n############ $s ############" -ForegroundColor Magenta
    & (Join-Path $PSScriptRoot $s)
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "$s failed" }
}

Write-Host "`n############ 06-run-queries.ps1 ############" -ForegroundColor Magenta
& (Join-Path $PSScriptRoot '06-run-queries.ps1') -Tag $(if ($SkipIndexes) {'base'} else {'indexed'})

Write-Step "All steps complete"
Write-Ok "results in queries\results\ ; compare runs with .\compare.ps1"
