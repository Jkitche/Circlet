-- Circlet
-- Progress rings for WoW Forever: rings that pop up and fill when you gain XP, quest
-- progress, skill points or reputation, plus rings for casts, flights, breath, totems
-- and more.
--
-- Files load in Circlet.toc order and share everything through `ns`, the table the game
-- passes every file. Each file pulls what it needs from ns at the top and adds what it
-- offers at the bottom ("Shared with the files loaded after this one").
--   Core/     this file (helpers), settings, the ring registry, slash commands, startup
--   Draw/     drawing rings and glyphs
--   Layout/   ring holders (opacity, combat), auto-arrange, dragging
--   Rings/    the two ring builders (Base/) and one file per ring
--   Features/ edit mode, profiles, migrations, effects, the session summary
--   UI/       the options window

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Helpers used everywhere
---------------------------------------------------------------------------

local PREFIX = "|cffffd100Circlet|r: "

local function Print(...)
    print(PREFIX .. string.join(" ", tostringall(...)))
end

-- In combat the client hides some values from addons ("secret values"). They can be
-- passed to display functions but not compared or used in arithmetic.
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- A value, or nil if it's hidden.
local function Clean(v)
    if v == nil or IsSecret(v) then return nil end
    return v
end

-- A number, or nil if it's hidden or not a number.
local function CleanNumber(v)
    return (type(v) == "number" and not IsSecret(v)) and v or nil
end

-- Calls fn if it exists and returns its results; nil if it doesn't exist or errors
-- (APIs that this client lacks, or that refuse in some situation).
local function Pass(ok, ...)
    if ok then return ... end
end
local function SafeCall(fn, ...)
    if not fn then return nil end
    return Pass(pcall(fn, ...))
end

local function Copy(v)
    return type(v) == "table" and CopyTable(v) or v
end

-- 0:42, 12:05 or 1:02:05.
local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- A spell's name and icon by ID, nil if unknown or hidden.
local function SpellName(id)
    local name = C_Spell and C_Spell.GetSpellName and SafeCall(C_Spell.GetSpellName, id)
    if not name and GetSpellInfo then name = SafeCall(GetSpellInfo, id) end
    return type(name) == "string" and not IsSecret(name) and name or nil
end

local function SpellIcon(id)
    local icon = C_Spell and C_Spell.GetSpellTexture and SafeCall(C_Spell.GetSpellTexture, id)
    if not icon and GetSpellInfo then icon = select(3, SafeCall(GetSpellInfo, id)) end
    return Clean(icon)
end

-- Calls handler(event, ...) for each event in the list; "UNIT_PET:player" registers a
-- unit event for that unit. Events this client doesn't have are skipped.
local function Listen(list, handler)
    local frame = CreateFrame("Frame")
    for _, e in ipairs(list) do
        local name, unit = e:match("^([^:]+):?(.*)$")
        if unit ~= "" then
            pcall(frame.RegisterUnitEvent, frame, name, unit)
        else
            pcall(frame.RegisterEvent, frame, name)
        end
    end
    frame:SetScript("OnEvent", function(_, event, ...) handler(event, ...) end)
    return frame
end

-- Shared with the files loaded after this one.
ns.ns = ns
ns.ADDON_NAME = ADDON_NAME
ns.Print = Print
ns.IsSecret = IsSecret
ns.Clean = Clean
ns.CleanNumber = CleanNumber
ns.SafeCall = SafeCall
ns.Copy = Copy
ns.FormatTime = FormatTime
ns.SpellName = SpellName
ns.SpellIcon = SpellIcon
ns.Listen = Listen
