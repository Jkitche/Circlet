-- Circlet: The ring registry: everything about each ring, declared in the ring's own file.
local ADDON_NAME, ns = ...

local DEFAULTS = ns.DEFAULTS

---------------------------------------------------------------------------
-- Rings
---------------------------------------------------------------------------
-- Each ring file calls ns.RegisterRing once, near its top, with everything the rest of
-- the addon needs to know about it. Edit mode, the slash commands and their help, the
-- options window and the defaults are all built from these, so adding a ring means
-- adding one file (and its line in Circlet.toc).
--
--   key       settings prefix ("quest" -> questSize, questX, ...)
--   name      what edit mode and messages call it ("Quest")
--   order     its place in edit mode, the General page's list and "Reset all positions"
--   defaults  its saved settings, keyed in full (questEnabled = true, ...); tables whose
--             key ends in "Colors" are its color groups. Every ring also gets the common
--             look settings (Core/Settings.lua: RING_COMMON).
--   edit      { set = function(on), get = function() } for edit mode, or
--   ring      a ring built by CreateProgressRing / CreateLiveRing (has SetEditing/IsEditing)
--   preview   function that shows a sample; slash = { "quest", "pop" } runs it as /sq quest
--             (the first name is the one shown in /sq help; all of them work with /sq edit
--             and /sq resetpos)
--   toggle    { "Quest ring", "Fills when ...", onSet } for the General page's list of rings
--   page      { folder = "progress" | "status" | "professions" | nil, order = n,
--               build = function(O) return O.RingTab(...) end } for its options page
--             (O is the option builders, UI/OptionsKit.lua)
--   class     { HUNTER = true, ... }: only these classes see its page and toggle
--   gameBar   "the game's XP bar": it can hide that (Features/DefaultUI.lua)
--   onLoaded  function run once the saved settings are loaded

local RINGS, BY_KEY = {}, {}
local COLOR_GROUPS = {}

local function RegisterRing(def)
    assert(def.key and not BY_KEY[def.key], "ring key missing or used twice")
    for k, v in pairs(def.defaults or {}) do
        DEFAULTS[k] = v
        if type(v) == "table" and k:match("Colors$") then table.insert(COLOR_GROUPS, k) end
    end
    if def.ring and not def.edit then
        def.edit = { set = def.ring.SetEditing, get = def.ring.IsEditing }
    end
    def.order = def.order or (#RINGS + 1)
    BY_KEY[def.key] = def
    table.insert(RINGS, def)
    table.sort(RINGS, function(a, b) return a.order < b.order end)
    return def
end

-- A ring's definition by key, or by any of its slash names ("taxi" -> flight).
local function FindRing(name)
    if not name then return nil end
    if BY_KEY[name] then return BY_KEY[name] end
    for _, def in ipairs(RINGS) do
        for _, alias in ipairs(def.slash or {}) do
            if alias == name then return def end
        end
    end
end

-- Hidden for the player's class? (Unknown classes see everything.)
local function HiddenForClass(def)
    if not (def and def.class) then return false end
    local _, class = UnitClass("player")
    return class ~= nil and not def.class[class]
end

---------------------------------------------------------------------------
-- Other slash commands
---------------------------------------------------------------------------
-- Features add their own /sq commands: names = { "summary", "session" }, fn(arg),
-- help = "this session's summary" (nil: not listed in /sq help).
local COMMANDS = {}

local function RegisterCommand(names, fn, help, usage)
    table.insert(COMMANDS, { names = names, fn = fn, help = help, usage = usage })
end

---------------------------------------------------------------------------
-- Startup hooks
---------------------------------------------------------------------------
-- Run once the saved settings are loaded and filled in (Core/Events.lua).
local LOADED = {}
local function OnLoaded(fn) table.insert(LOADED, fn) end

-- Shared with the files loaded after this one.
ns.RINGS = RINGS
ns.COLOR_GROUPS = COLOR_GROUPS
ns.COMMANDS = COMMANDS
ns.LOADED = LOADED
ns.RegisterRing = RegisterRing
ns.RegisterCommand = RegisterCommand
ns.OnLoaded = OnLoaded
ns.FindRing = FindRing
ns.HiddenForClass = HiddenForClass
