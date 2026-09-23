# Shared configuration and helpers for the TPC-DS on MariaDB Windows scripts.
# Dot-source this from every step script:  . "$PSScriptRoot\lib\Common.ps1"

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# HARD GUARD. These scripts are for a Windows machine only. They must have
# zero effect on the macOS setup this repository was built on, so every script
# refuses to run anywhere else rather than trusting the operator.
# ---------------------------------------------------------------------------
function Assert-Windows {
    $isWin = $IsWindows -or ($env:OS -eq 'Windows_NT')
    if (-not $isWin) {
        Write-Host ""
        Write-Host "  REFUSING TO RUN: these scripts are Windows-only." -ForegroundColor Red
        Write-Host "  They create and drop database objects and would damage a"          -ForegroundColor Red
        Write-Host "  working setup on another platform. Run them on Windows."           -ForegroundColor Red
        Write-Host ""
        exit 1
    }
}
Assert-Windows

# Repository root = parent of the windows\ folder
$script:Root   = Split-Path -Parent $PSScriptRoot
if ($PSScriptRoot -like '*\lib') { $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$script:Kit    = Join-Path $Root 'DSGen-software-code-4.0.0'
$script:Tools  = Join-Path $Kit  'tools'
$script:DataDir= Join-Path $Kit  'data'
$script:SqlDir = Join-Path $Root 'sql'
$script:QDir   = Join-Path $Root 'queries'
# Anything these scripts GENERATE goes here, never into the shared sql\ or
# queries\ folders, so a Windows run cannot overwrite the committed artifacts.
$script:GenDir = Join-Path $PSScriptRoot 'generated'
if ($PSScriptRoot -like '*\lib') { $script:GenDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'generated' }

# Scale factor. 1 = the qualification size defined by the specification.
$script:Scale  = if ($env:TPCDS_SCALE) { [int]$env:TPCDS_SCALE } else { 1 }
$script:DbName = if ($env:TPCDS_DB)    { $env:TPCDS_DB }        else { 'tpcds' }

function Write-Step   ($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-Ok     ($m) { Write-Host "  [ok] $m"    -ForegroundColor Green }
function Write-Warn2  ($m) { Write-Host "  [!]  $m"    -ForegroundColor Yellow }
function Write-Err2   ($m) { Write-Host "  [X]  $m"    -ForegroundColor Red }

# MariaDB ships mariadb.exe on 11+ and mysql.exe on older builds; accept either.
function Get-MariaClient {
    foreach ($n in 'mariadb','mysql') {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    foreach ($p in @(
        "$env:ProgramFiles\MariaDB*\bin\mariadb.exe",
        "$env:ProgramFiles\MariaDB*\bin\mysql.exe")) {
        $f = Get-ChildItem $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    throw "MariaDB client not found. Install MariaDB and ensure its bin\ is on PATH."
}

# Credentials. Socket auth does not exist on Windows, so a user/password is
# always required. Set these once in your shell:
#   $env:TPCDS_USER = 'root'; $env:TPCDS_PASSWORD = 'yourpassword'
function Get-MariaArgs {
    param([switch]$LocalInfile)
    $a = @()
    if ($env:TPCDS_USER)     { $a += "--user=$env:TPCDS_USER" }
    if ($env:TPCDS_PASSWORD) { $a += "--password=$env:TPCDS_PASSWORD" }
    if ($env:TPCDS_HOST)     { $a += "--host=$env:TPCDS_HOST" }     else { $a += "--host=127.0.0.1" }
    if ($env:TPCDS_PORT)     { $a += "--port=$env:TPCDS_PORT" }
    if ($LocalInfile)        { $a += "--local-infile=1" }
    return $a
}

function Invoke-Maria {
    param([string]$Sql, [string]$Database, [switch]$LocalInfile, [switch]$Batch)
    $exe  = Get-MariaClient
    $args = Get-MariaArgs -LocalInfile:$LocalInfile
    if ($Batch)    { $args += '-B' }
    if ($Database) { $args += $Database }
    $args += @('-e', $Sql)
    & $exe @args
    if ($LASTEXITCODE -ne 0) { throw "MariaDB command failed (exit $LASTEXITCODE)" }
}

function Invoke-MariaFile {
    param([string]$Path, [string]$Database, [switch]$LocalInfile)
    $exe  = Get-MariaClient
    $args = Get-MariaArgs -LocalInfile:$LocalInfile
    if ($Database) { $args += $Database }
    Get-Content -Raw -LiteralPath $Path | & $exe @args
    if ($LASTEXITCODE -ne 0) { throw "MariaDB failed running $Path (exit $LASTEXITCODE)" }
}

# MariaDB wants forward slashes in LOAD DATA paths on Windows.
function ConvertTo-SqlPath ([string]$p) { return ($p -replace '\\','/') }

# dsdgen opens .dat files with fopen(path,"wt") -- TEXT mode -- so on Windows
# it writes CRLF, while on Unix it writes LF. The loader's LINES TERMINATED BY
# must match or the final column of every row keeps a trailing \r.
function Get-DatLineTerminator ([string]$sampleFile) {
    if (-not (Test-Path $sampleFile)) { return '|\r\n' }   # Windows default
    $fs = [System.IO.File]::OpenRead($sampleFile)
    try {
        $buf = New-Object byte[] 8192
        $n = $fs.Read($buf, 0, $buf.Length)
        for ($i = 0; $i -lt $n; $i++) {
            if ($buf[$i] -eq 10) {                        # LF
                if ($i -gt 0 -and $buf[$i-1] -eq 13) { return '|\r\n' }
                return '|\n'
            }
        }
    } finally { $fs.Dispose() }
    return '|\r\n'
}
