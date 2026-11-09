-- Circlet: The /sq slash command (also /circlet and /circ).
local ADDON_NAME, ns = ...

local Print = ns.Print

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- Built from the ring registry (each ring's preview and its names) and the commands
-- features add with ns.RegisterCommand, so nothing here needs changing for a new ring.

-- Each ring's first slash name, for messages.
local function RingNames()
    local names = {}
    for _, def in ipairs(ns.RINGS) do table.insert(names, def.slash and def.slash[1] or def.key) end
    return table.concat(names, ", ")
end

-- /sq edit [ring] and /sq resetpos [ring]: one ring by any of its names, or all.
local function ForRing(arg, one, all)
    local def = ns.FindRing(arg)
    if def then
        one(def.key)
    elseif arg == "" or arg == "all" then
        all()
    else
        Print("Unknown ring '" .. arg .. "'. Use " .. RingNames() .. " or all.")
    end
end

local function Help()
    Print("commands:")
    local lines = { { "/sq", "open the options window" } }
    for _, def in ipairs(ns.RINGS) do
        if def.preview and def.slash then table.insert(lines, { "/sq " .. def.slash[1], def.help }) end
    end
    for _, c in ipairs(ns.COMMANDS) do
        if c.help then table.insert(lines, { "/sq " .. (c.usage or c.names[1]), c.help }) end
    end
    table.insert(lines, { "/sq edit [ring]", "edit mode for one ring or all" })
    table.insert(lines, { "/sq resetpos [ring]", "move one ring (or all) back to its default spot" })
    for _, l in ipairs(lines) do
        print(string.format("  %-15s - %s", l[1], l[2]))
    end
end

local function Run(msg)
    local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "config" or cmd == "options" then
        ns.OpenOptions()
    elseif cmd == "edit" or cmd == "move" or cmd == "unlock" or cmd == "lock" then
        ForRing(arg, ns.ToggleRingEditing, ns.ToggleAllEditing)
    elseif cmd == "resetpos" or cmd == "resetpositions" then
        ForRing(arg, ns.ResetPosition, ns.ResetPositions)
    else
        for _, def in ipairs(ns.RINGS) do
            for _, name in ipairs(def.slash or {}) do
                if name == cmd and def.preview then return def.preview() end
            end
        end
        for _, c in ipairs(ns.COMMANDS) do
            for _, name in ipairs(c.names) do
                if name == cmd then return c.fn(arg) end
            end
        end
        Help()
    end
end

SLASH_CIRCLET1 = "/sq" -- short; kept from the addon's working name
SLASH_CIRCLET2 = "/circlet"
SLASH_CIRCLET3 = "/circ"
SlashCmdList.CIRCLET = Run
