<#  Step 2 - generate the SF=1 flat files (about 1.2 GB, 19.5 M rows).  #>
. "$PSScriptRoot\lib\Common.ps1"

if (-not (Test-Path "$Tools\dsdgen.exe")) { throw "dsdgen.exe missing - run 01-build-dsdgen.ps1 first" }
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

Write-Step "Generating scale factor $Scale into $DataDir"
Write-Warn2 "SF=1 is the qualification size; dsdgen will say so. That is expected."

Push-Location $Tools
try {
    # -FORCE overwrites without prompting. Note dsdgen needs the directory to
    # exist already and, on Windows, uses '\' as its path separator.
    & "$Tools\dsdgen.exe" -SCALE $Scale -DIR $DataDir -FORCE
    if ($LASTEXITCODE -ne 0) { throw "dsdgen failed (exit $LASTEXITCODE)" }
} finally { Pop-Location }

Write-Step "Verifying"
$expected = @{
    store_sales=2880404; catalog_sales=1441548; web_sales=719384; inventory=11745000
    store_returns=287514; catalog_returns=144067; web_returns=71763
    customer=100000; item=18000; date_dim=73049; time_dim=86400
}
$files = Get-ChildItem "$DataDir\*.dat"
Write-Ok "$($files.Count) .dat files, $([math]::Round(($files | Measure-Object Length -Sum).Sum/1GB,2)) GB"
if ($files.Count -ne 25) { Write-Err2 "expected 25 files, found $($files.Count)" }

# Row counts only hold at SF=1.
if ($Scale -eq 1) {
    foreach ($t in $expected.Keys) {
        $p = Join-Path $DataDir "$t.dat"
        if (-not (Test-Path $p)) { Write-Err2 "$t.dat missing"; continue }
        $n = 0; $r = [System.IO.File]::OpenText($p)
        try { while ($null -ne $r.ReadLine()) { $n++ } } finally { $r.Dispose() }
        if ($n -eq $expected[$t]) { Write-Ok "$t : $n rows" }
        else { Write-Err2 "$t : $n rows, expected $($expected[$t])" }
    }
}

$term = Get-DatLineTerminator (Join-Path $DataDir 'reason.dat')
Write-Ok "line terminator detected: '$term'  (Windows dsdgen writes CRLF; the loader adapts)"
