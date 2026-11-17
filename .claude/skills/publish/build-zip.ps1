# Builds dpws_tools-<version>.zip (one dpws_tools folder inside, ready to drop into Interface\AddOns).
# Same file set as publish.ps1. Usage: build-zip.ps1 -Version 0.2.0 -OutDir <dir>
param([Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][string]$OutDir)

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$stage = Join-Path $OutDir "stage"
$addon = Join-Path $stage "dpws_tools"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $addon | Out-Null
robocopy $root $addon /E /XD docs tests .git .claude .superpowers /XF publish.ps1 .gitignore .gitattributes CHANGELOG.md /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { exit 1 }
$zip = Join-Path $OutDir "dpws_tools-$Version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path $addon -DestinationPath $zip
Remove-Item -Recurse -Force $stage
Write-Host $zip
exit 0
