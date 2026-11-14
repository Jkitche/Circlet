<#
Copies the addon from this repo into the game: Interface\AddOns\Circlet, next to this
checkout (Interface\Circlet). Run it after every change, then /reload in game (or restart
the game if a file was added or removed: the game only reads the file list at startup).

It copies what the release zip would hold: everything except what .pkgmeta's "ignore" list
leaves out (tests, tools, docs...) and the repo's own files (.git, dist). It mirrors the
folder: changed files are copied and files the repo no longer has are removed from it.
@project-version@ stays as it is, so the options window shows "dev".

    .\localDeploy.ps1                        to ..\AddOns\Circlet
    .\localDeploy.ps1 -Target D:\Some\Circlet  somewhere else
    .\localDeploy.ps1 -WhatIf                show what it would do, change nothing
#>
param(
    [string]$Target,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $Target) { $Target = Join-Path (Split-Path $root -Parent) 'AddOns\Circlet' }

if (-not (Test-Path (Join-Path $root 'Circlet.toc'))) { throw "No Circlet.toc in ${root}: run this from the repo." }
$addons = Split-Path $Target -Parent
if (-not (Test-Path $addons)) { throw "No AddOns folder at $addons" }

# What .pkgmeta leaves out of a release, plus the repo's own files.
$skip = @('.git', 'dist', '__pycache__')
$inside = $false
foreach ($line in Get-Content (Join-Path $root '.pkgmeta')) {
    if ($line -match '^ignore:') { $inside = $true; continue }
    if ($inside -and $line -match '^\s+-\s+(.+?)\s*$') { $skip += $Matches[1]; continue }
    if ($inside -and $line.Trim() -and -not $line.StartsWith(' ')) { $inside = $false }
}

# Robocopy /MIR: copy what changed, remove what's gone. A name can be a folder or a file, so
# each goes to both /XD (folders) and /XF (files); full paths so only top-level ones match.
$xd = $skip | ForEach-Object { Join-Path $root $_ }
$rcArgs = @($root, $Target, '/MIR', '/NJH', '/NJS', '/NDL', '/NP', '/XD') + $xd + @('/XF') + $xd
if ($WhatIf) { $rcArgs += '/L' }
& robocopy @rcArgs
$code = $LASTEXITCODE
if ($code -ge 8) { throw "robocopy failed (exit code $code)" }

$what = if ($WhatIf) { 'Would deploy' } else { 'Deployed' }
Write-Host "$what $root -> $Target"
# robocopy's exit code: 1 = files copied, 2 = extra files (removed, with /MIR).
if ($code -band 3) { Write-Host 'Files changed: /reload in game (restart the game if files were added or removed).' }
elseif (-not $WhatIf) { Write-Host 'Already up to date.' }
exit 0
