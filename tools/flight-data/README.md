# Flight data generator

Builds `Data/FlightPaths.lua` (the flight ring's path lengths) from your own WoW Forever
install. It reads the client's `TaxiNodes`, `TaxiPath` and `TaxiPathNode` tables straight
from the local game files (CASC storage, read-only), works out each direct flight's path
length in yards and its stop delays, and writes them as Lua.

Run it again after a patch that changes flight paths (Windows PowerShell, no other tools
needed; the game can stay open):

```
powershell -ExecutionPolicy Bypass -File tools\flight-data\Make-FlightData.ps1
```

- `CascReader.cs`: reads files from local CASC storage and decodes DB2 tables (WDC3 to WDC5).
- `Make-FlightData.ps1`: finds the three tables, computes the lengths, writes the Lua file.
  Options: `-WowDir`, `-Product` (default `wowf`, WoW Forever), and the tables' file data IDs
  (`-TaxiNodesFdid 1068100 -TaxiPathFdid 1067802 -TaxiPathNodeFdid 1000437` in build
  1.60.1.70888), in case a patch moves them. The script stops if a table's layout changes.

This folder isn't needed in game; leave it out of release packages.
