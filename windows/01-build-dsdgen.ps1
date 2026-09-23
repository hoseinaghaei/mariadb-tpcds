<#
  Step 1 - build dsdgen, dsqgen, distcomp and tpcds.idx with MSBuild.

  The toolkit ships a Visual Studio 2005 solution (format 9.00, toolset 8.00).
  Modern MSBuild cannot consume it directly, so it is upgraded to the installed
  toolset first. Unlike macOS, NO source porting is needed: config.h already
  has a WIN32 block.
#>
. "$PSScriptRoot\lib\Common.ps1"

Write-Step "Locating MSBuild"
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath  = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
$msbuild = Get-ChildItem "$vsPath\MSBuild\*\Bin\MSBuild.exe" | Select-Object -First 1 -ExpandProperty FullName
$devenv  = Join-Path $vsPath 'Common7\IDE\devenv.exe'
Write-Ok $msbuild

Push-Location $Tools
try {
    Write-Step "Upgrading the Visual Studio 2005 solution"
    # devenv /upgrade rewrites .vcproj -> .vcxproj for the installed toolset.
    if (Test-Path $devenv) {
        if (-not (Test-Path 'dbgen2.vcxproj')) {
            & $devenv 'dbgen2.sln' /upgrade
            Write-Ok "solution upgraded"
        } else { Write-Ok "already upgraded" }
    } else {
        Write-Warn2 "devenv.exe not found (Build Tools only installs MSBuild)."
        Write-Warn2 "Open dbgen2.sln once in Visual Studio to upgrade it, or install the IDE."
        throw "cannot upgrade the solution without devenv.exe"
    }

    Write-Step "Building (Release, x64)"
    & $msbuild 'dbgen2.sln' /p:Configuration=Release /p:Platform=x64 /m /v:minimal
    if ($LASTEXITCODE -ne 0) { throw "MSBuild failed (exit $LASTEXITCODE)" }

    # Collect the executables next to the sources, matching the Unix layout.
    Get-ChildItem -Recurse -Include dsdgen.exe,dsqgen.exe,distcomp.exe,mkheader.exe,checksum.exe |
        ForEach-Object { Copy-Item $_.FullName $Tools -Force }

    Write-Step "Building tpcds.idx"
    # distcomp compiles the .dst distribution sources into the binary index
    # that both dsdgen and dsqgen need at runtime.
    & "$Tools\distcomp.exe" -i tpcds.dst -o tpcds.idx
    if (-not (Test-Path "$Tools\tpcds.idx")) { throw "distcomp did not produce tpcds.idx" }

    Write-Step "Result"
    Get-ChildItem dsdgen.exe,dsqgen.exe,distcomp.exe,tpcds.idx -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Ok "$($_.Name)  $([math]::Round($_.Length/1KB))KB" }
} finally { Pop-Location }
