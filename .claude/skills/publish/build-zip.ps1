# Builds TinkersBelt-<version>.zip (one TinkersBelt folder inside, ready to drop into Interface\AddOns).
# Same file set as publish.ps1. Usage: build-zip.ps1 -Version 0.2.0 -OutDir <dir>
param([Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][string]$OutDir)

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$stage = Join-Path $OutDir "stage"
$addon = Join-Path $stage "TinkersBelt"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $addon | Out-Null
robocopy $root $addon /E /XD docs tests .git .claude .superpowers /XF publish.ps1 .gitignore .gitattributes CHANGELOG.md /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { exit 1 }
$zip = Join-Path $OutDir "TinkersBelt-$Version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
# Windows tar writes / in paths (Compress-Archive in PS 5.1 writes \, which breaks other unzippers)
& (Join-Path $env:SystemRoot "System32\tar.exe") -a -c -f $zip -C $stage TinkersBelt
if ($LASTEXITCODE -ne 0) { exit 1 }
Remove-Item -Recurse -Force $stage
Write-Host $zip
exit 0
