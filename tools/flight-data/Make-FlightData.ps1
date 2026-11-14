<#
Circlet tools: builds Data/FlightPaths.lua from your own WoW Forever install.

Reads three of the game's database tables straight from the local game files (CASC
storage, read-only) with CascReader.cs:
  TaxiNodes     the flight masters: ID and English name
  TaxiPath      each direct flight: from node, to node
  TaxiPathNode  the points each flight path flies through: position, order, continent,
                flags (1 = teleport) and stop delay (seconds)
and writes, per direct flight, the length of its path in yards (the 3D distance from
point to point, in order) and its stop delays. The flight ring turns those into times
(Rings/Flight.lua).

Run it again after a patch that changes flight paths:
  powershell -ExecutionPolicy Bypass -File tools\flight-data\Make-FlightData.ps1
Options: -WowDir (default: the standard install), -Product (default wowf = WoW Forever),
and the tables' file data IDs, should a patch move them.
#>
param(
    [string]$WowDir = "C:\Program Files (x86)\World of Warcraft",
    [string]$Product = "wowf",
    [int]$TaxiNodesFdid = 1068100,
    [int]$TaxiPathFdid = 1067802,
    [int]$TaxiPathNodeFdid = 1000437
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$addon = Split-Path -Parent (Split-Path -Parent $here)
Add-Type -Path (Join-Path $here "CascReader.cs")

# The build, for the file header.
$buildInfo = Get-Content (Join-Path $WowDir ".build.info")
$cols = $buildInfo[0].Split('|')
$verCol = [Array]::FindIndex($cols, [Predicate[string]]{ param($c) $c.StartsWith('Version') })
$prodCol = [Array]::FindIndex($cols, [Predicate[string]]{ param($c) $c.StartsWith('Product') })
$build = "unknown"
foreach ($line in ($buildInfo | Select-Object -Skip 1)) {
    $f = $line.Split('|')
    if ($f[$prodCol] -eq $Product) { $build = $f[$verCol]; break }
}

$casc = New-Object CircletTools.Casc $WowDir, $Product
function Table($fdid) { New-Object CircletTools.Db2 (,$casc.ReadFileDataID($fdid)) }
$nodes = Table $TaxiNodesFdid
$paths = Table $TaxiPathFdid
$points = Table $TaxiPathNodeFdid

# Sanity checks: the columns this script reads (see the field layouts printed by -Verbose).
if ($paths.FieldCount -ne 4) { throw "TaxiPath layout changed ($($paths.FieldCount) fields)" }
if ($points.FieldCount -ne 9) { throw "TaxiPathNode layout changed ($($points.FieldCount) fields)" }
Write-Verbose $nodes.Info; Write-Verbose $paths.Info; Write-Verbose $points.Info

# TaxiNodes: ID (field 4) and name (field 0).
$names = @{}
foreach ($r in $nodes.Records) { $names[[int]$r.Fields[4][0]] = $nodes.String($r, 0) }

# TaxiPathNode: Loc[3] (0), PathID (2), NodeIndex (3), ContinentID (4), Flags (5), Delay (6).
$byPath = @{}
foreach ($r in $points.Records) {
    $owner = [int]$r.Fields[2][0]
    if (-not $byPath.ContainsKey($owner)) { $byPath[$owner] = New-Object System.Collections.ArrayList }
    [void]$byPath[$owner].Add($r)
}
$F = [CircletTools.Db2]
$out = @{} # from -> to -> @(yards, delay)
$skipped = 0
foreach ($p in $paths.Records) {
    $pathId = [int]$p.Fields[0][0]; $from = [int]$p.Fields[1][0]; $to = [int]$p.Fields[2][0]
    $pts = $byPath[$pathId]
    if (-not $pts -or $pts.Count -lt 2 -or $from -le 0 -or $to -le 0 -or $from -eq $to) { $skipped++; continue }
    $pts = $pts | Sort-Object { [int]$_.Fields[3][0] }
    $yards = 0.0; $delay = 0; $cross = $false; $prev = $null
    foreach ($pt in $pts) {
        $delay += [int]$pt.Fields[6][0]
        if ($prev) {
            if ($prev.Fields[4][0] -ne $pt.Fields[4][0] -or ($prev.Fields[5][0] -band 1)) { $cross = $true }
            else {
                $dx = $F::F($pt.Fields[0][0]) - $F::F($prev.Fields[0][0])
                $dy = $F::F($pt.Fields[0][1]) - $F::F($prev.Fields[0][1])
                $dz = $F::F($pt.Fields[0][2]) - $F::F($prev.Fields[0][2])
                $yards += [Math]::Sqrt($dx * $dx + $dy * $dy + $dz * $dz)
            }
        }
        $prev = $pt
    }
    if ($cross -or $yards -le 0) { $skipped++; continue } # a teleport in the middle: not a plain flight
    if (-not $out.ContainsKey($from)) { $out[$from] = @{} }
    $y = [int][Math]::Round($yards)
    # Parallel paths between the same two nodes: keep the shorter.
    if (-not $out[$from].ContainsKey($to) -or $out[$from][$to][0] -gt $y) { $out[$from][$to] = @($y, $delay) }
}

# Write the Lua file.
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("-- Circlet: flight path lengths, generated from the WoW Forever game files. Do not edit by hand.")
[void]$sb.AppendLine("-- Made by tools/flight-data/Make-FlightData.ps1 from the client's TaxiNodes, TaxiPath and")
[void]$sb.AppendLine("-- TaxiPathNode tables (build $build). Rings/Flight.lua turns these into flight times")
[void]$sb.AppendLine("-- (length / taxi speed, plus stops).")
[void]$sb.AppendLine("--   ns.FLIGHT_PATHS[from node ID][to node ID] = yards, or { yards, stop delay in seconds }")
[void]$sb.AppendLine("--   ns.FLIGHT_NODES[node ID] = English name (the client's own names may be translated)")
[void]$sb.AppendLine("local ADDON_NAME, ns = ...")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("ns.FLIGHT_DATA_BUILD = `"$build`"")
[void]$sb.AppendLine("ns.FLIGHT_PATHS = {")
$count = 0
foreach ($from in ($out.Keys | Sort-Object)) {
    $parts = foreach ($to in ($out[$from].Keys | Sort-Object)) {
        $v = $out[$from][$to]; $count++
        if ($v[1] -gt 0) { "[$to]={$($v[0]),$($v[1])}" } else { "[$to]=$($v[0])" }
    }
    [void]$sb.AppendLine("    [$from] = { " + ($parts -join ", ") + " },")
}
[void]$sb.AppendLine("}")
[void]$sb.AppendLine("ns.FLIGHT_NODES = {")
foreach ($id in ($names.Keys | Sort-Object)) {
    $n = $names[$id] -replace '\\', '\\' -replace '"', '\"'
    [void]$sb.AppendLine("    [$id] = `"$n`",")
}
[void]$sb.AppendLine("}")

$dest = Join-Path $addon "Data\FlightPaths.lua"
New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
[IO.File]::WriteAllText($dest, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
"Build $build`: $($names.Count) flight masters, $count direct flights ($skipped paths skipped: teleports or no points)."
"Wrote $dest"
