# Copies the addon into the WoW: Forever AddOns folder. Then /reload in game.
param([string]$AddOnsDir = "D:\Games\World of Warcraft\_forever_\Interface\AddOns")

if (-not (Test-Path $AddOnsDir)) {
	Write-Error "AddOns folder not found: $AddOnsDir"
	exit 1
}
$target = Join-Path $AddOnsDir "dpws_tools"
# /MIR deletes stale files, but only inside our own dpws_tools folder
robocopy $PSScriptRoot $target /MIR /XD docs .git .claude .superpowers /XF publish.ps1 .gitignore .gitattributes /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { exit 1 }
Write-Host "Published to $target"
exit 0
