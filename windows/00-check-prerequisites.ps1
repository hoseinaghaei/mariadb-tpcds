<#
  Step 0 - verify everything needed is present before starting.
  Nothing is installed or changed; this only reports.
#>
. "$PSScriptRoot\lib\Common.ps1"

Write-Step "Prerequisites"
$fail = 0

# --- MSBuild / Visual Studio ------------------------------------------------
$msbuild = $null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null
    if ($vsPath) {
        $msbuild = Get-ChildItem "$vsPath\MSBuild\*\Bin\MSBuild.exe" -ErrorAction SilentlyContinue |
                   Select-Object -First 1 -ExpandProperty FullName
    }
}
if (-not $msbuild) { $msbuild = (Get-Command msbuild.exe -ErrorAction SilentlyContinue).Source }
if ($msbuild) { Write-Ok "MSBuild: $msbuild" }
else {
    Write-Err2 "MSBuild not found."
    Write-Host "       Install 'Build Tools for Visual Studio' with the"
    Write-Host "       'Desktop development with C++' workload:"
    Write-Host "       https://visualstudio.microsoft.com/downloads/"
    $fail++
}

# --- MariaDB ----------------------------------------------------------------
try {
    $client = Get-MariaClient
    Write-Ok "MariaDB client: $client"
    $v = Invoke-Maria -Sql "SELECT VERSION()" -Batch 2>&1 | Select-Object -Last 1
    Write-Ok "server reachable, version $v"
} catch {
    Write-Err2 "MariaDB not reachable: $($_.Exception.Message)"
    Write-Host "       Install from https://mariadb.org/download/ and set:"
    Write-Host "         `$env:TPCDS_USER='root'; `$env:TPCDS_PASSWORD='yourpassword'"
    $fail++
}

# --- local_infile (needed to load the .dat files) ---------------------------
try {
    $li = (Invoke-Maria -Sql "SELECT @@local_infile" -Batch 2>&1 | Select-Object -Last 1)
    if ("$li".Trim() -eq '1') { Write-Ok "server local_infile = 1" }
    else {
        Write-Warn2 "server local_infile = $li - LOAD DATA LOCAL INFILE will be refused."
        Write-Host  "       Add  local_infile=1  under [mysqld] in my.ini and restart the service."
        $fail++
    }
} catch { Write-Warn2 "could not read @@local_infile" }

# --- Python (for the query runner and comparison) ---------------------------
$py = (Get-Command python -ErrorAction SilentlyContinue) ?? (Get-Command python3 -ErrorAction SilentlyContinue)
if ($py) { Write-Ok "Python: $($py.Source)" }
else { Write-Err2 "Python 3 not found - needed by 06-run-queries.ps1. https://python.org/downloads/"; $fail++ }

# --- disk space -------------------------------------------------------------
$drive = (Get-Item $Root).PSDrive
$freeGb = [math]::Round($drive.Free / 1GB, 1)
$needGb = [math]::Round(1.3 * $Scale + 2.5, 1)   # ~1.2 GB data + ~3.2 GB loaded at SF=1
if ($freeGb -ge $needGb) { Write-Ok "free space on $($drive.Name): $freeGb GB (need about $needGb GB)" }
else { Write-Err2 "only $freeGb GB free on $($drive.Name); need roughly $needGb GB"; $fail++ }

Write-Step "Summary"
if ($fail -eq 0) { Write-Ok "all prerequisites satisfied - run 01-build-dsdgen.ps1 next" }
else { Write-Err2 "$fail problem(s) above must be fixed first"; exit 1 }
