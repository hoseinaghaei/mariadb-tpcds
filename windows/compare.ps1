<#  Compare two tagged runs (default base vs indexed).  Read-only.  #>
. "$PSScriptRoot\lib\Common.ps1"

$py = ((Get-Command python -ErrorAction SilentlyContinue) ??
       (Get-Command python3 -ErrorAction SilentlyContinue)).Source
if (-not $py) { throw "Python 3 not found" }

Push-Location $QDir
try { & $py (Join-Path $QDir 'compare.py') }
finally { Pop-Location }
