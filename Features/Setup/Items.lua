-- Circlet: The setup wizard (first run) and the "New in <version>" page (after an update).
local ADDON_NAME, ns = ...

local db, Print, SafeCall, DEFAULTS = ns.db, ns.Print, ns.SafeCall, ns.DEFAULTS

-- Shared by Features/Setup/*.lua, which load in this order: Items, Pages, Window, Open.
ns.SetupUI = ns.SetupUI or {}
local SU = ns.SetupUI

---------------------------------------------------------------------------
-- Setup wizard and New in page
---------------------------------------------------------------------------
-- The first time Circlet runs on an account, a short wizard opens a few seconds after the
-- welcome animation:
--   1. Pick your rings, by group, each with a Show button that puts it on screen with
--      sample content (in edit mode, so it can be dragged there and then).
--   2. Hide the game's own bars that the rings you kept replace.
--   3. Look: one style and one size for every ring at once (or keep each ring's own).
--   4. Placement: keep the layout, reset it, or arrange the rings yourself after Finish.
-- Players who had Circlet before get, after an update, a "New in <version>" page instead:
-- just the rings and features added since (registered with since = "x.y.z", plus
-- NEW_FEATURES below), each with an on/off box and Show. Either one is shown once
-- (db.setupDone, db.seenNew: learned data, shared by every profile); /circ setup and
-- /circ new, or the buttons on the General tab, bring them back.
--
-- Each page is built as a list of items (headers, check rows, choices, notes); the window
-- is drawn from that list, and the tests read and click it through ns.Setup.

-- The rings, by group, in the order they're listed. A ring that isn't here goes to "Other".
local GROUPS = {
    { name = "Progress", keys = { "xp", "quest", "pin", "rep", "skill", "weapon" } },
    { name = "Health", keys = { "playerHp", "targetHp", "totHp", "petHp" } },
    { name = "Combat", keys = { "cast", "targetCast", "swing", "shot", "regen", "ammo" } },
    { name = "Class", keys = { "totem", "imbue", "soulstone", "pet" } },
    { name = "Group", keys = { "loot", "ready" } },
    { name = "Travel and survival", keys = { "flight", "hearth", "timed", "corpse", "breath" } },
    { name = "Professions", keys = { "craft", "gather", "fish" } },
    { name = "Comfort", keys = { "food", "camp", "clock", "timer" } },
}

-- Everything else in a release that isn't a ring of its own: with a setting, an on/off box
-- (and show: a ring to show it on); without one, just the news (fixes, changes, commands).
local NEW_FEATURES = {
    { id = "corpseReviveFx", since = "1.2.0", name = "Corpse ring: revive animation",
      desc = "Your soul drifts back into the ring when you revive in your own body.",
      setting = "corpseReviveFx", show = "corpse" },
    -- 1.4.0
    { id = "craftFx", since = "1.4.0", name = "Crafting animations",
      desc = "Each crafting profession gets its own animation on the crafting ring: bubbling potions, a hammer "
          .. "and sparks, lightning, runes, a stitching needle, flames and steam and more.",
      setting = "craftFx", show = "craft" },
    { id = "xpGainFx", since = "1.4.0", name = "XP ring: gain animation",
      desc = "A glowing comet rides the end of the fill as XP comes in, with a flare where it lands.",
      setting = "xpGainFx", show = "xp" },
    { id = "regenFx", since = "1.4.0", name = "Mana regen ring: animation",
      desc = "A spark charges while the five-second rule holds your regen back; mana spirals in when it starts again.",
      setting = "regenFx", show = "regen" },
    { id = "flightFx", since = "1.4.0", name = "Flight ring: animation",
      desc = "The arrow flies along the fill with a contrail through clouds and wind, then touches down in a puff of dust.",
      setting = "flightFx", show = "flight" },
    { id = "lootFx", since = "1.4.0", name = "Loot roll ring: dice",
      desc = "Two dice rattle while you decide, then tumble and land on their numbers when you roll.",
      setting = "lootFx", show = "loot" },
    { id = "timedFx", since = "1.4.0", name = "Timed quest ring: hourglass",
      desc = "Sand trickles from the end of the fill and piles up as time runs out.",
      setting = "timedFx", show = "timed" },
    { id = "skillFx", since = "1.4.0", name = "Profession skill ring: animation",
      desc = "A spark rides the fill shedding glitter, then bursts; a new tier or the cap sends a gold shimmer round.",
      setting = "skillFx", show = "skill" },
    { id = "weaponFx", since = "1.4.0", name = "Weapon skill ring: animation",
      desc = "A steel swoosh, a clang and a spray of sparks; capping a skill sends a blade glint round the ring.",
      setting = "weaponFx", show = "weapon" },
    { id = "swingHideDefault", since = "1.4.0", name = "Hide the game's swing timer bars",
      desc = "Let the swing timer ring replace WoW Forever's own melee swing timer bars.",
      setting = "swingHideDefault", show = "swing" },
    { id = "shotHideDefault", since = "1.4.0", name = "Hide the game's ranged swing timer bar",
      desc = "Let the shot timer ring replace WoW Forever's own ranged swing timer bar.",
      setting = "shotHideDefault", show = "shot" },
    { id = "flightTimesFixed", since = "1.4.0", name = "Flight times fixed",
      desc = "The flight ring counted down about 11% too fast; it now lands within a second of the real time.",
      show = "flight" },
    { id = "showxpCommand", since = "1.4.0", name = "/circ showxp",
      desc = "Brings the XP ring up for a few seconds at your current XP and prints your XP to chat." },
    { id = "optionsFolders", since = "1.4.0", name = "Tidier options window",
      desc = "Rings sorted into six folders, ring checkboxes grouped by folder, and checkboxes two to a row "
          .. "with their explanations in tooltips." },
    { id = "editAllSaved", since = "1.4.0", name = "Edit all rings: one message",
      desc = "Finishing Edit all rings says \"All ring positions saved.\" once, not a line for every ring." },
}

local STYLES = { { "keep", "Keep each ring's own" }, { "smooth", "Smooth" }, { "segmented", "Segmented" }, { "thin", "Thin" } }
local SIZES = { { "keep", "Keep each ring's own" }, { "smaller", "Smaller" }, { "default", "Default" }, { "larger", "Larger" } }
local SIZE_FACTOR = { smaller = 0.85, default = 1, larger = 1.2 }
local PLACES = { { "keep", "Keep where they are" }, { "reset", "Reset to the default layout" },
                 { "arrange", "Arrange them myself after Finish" } }
local STEPS = 4

---------------------------------------------------------------- helpers
-- "1.2.0" -> comparable; anything not a version (a dev build's @project-version@) is nil.
local function VersionParts(v)
    if type(v) ~= "string" then return nil end
    local a, b, c = v:match("^v?(%d+)%.?(%d*)%.?(%d*)")
    if not a then return nil end
    return { tonumber(a), tonumber(b) or 0, tonumber(c) or 0 }
end
local function Newer(a, b) -- is version string a newer than b?
    local x, y = VersionParts(a), VersionParts(b)
    if not x then return false elseif not y then return true end
    for i = 1, 3 do if x[i] ~= y[i] then return x[i] > y[i] end end
    return false
end
local function AddonVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = get and SafeCall(get, ADDON_NAME, "Version")
    return VersionParts(v) and (v:gsub("^v", "")) or nil
end

local function Def(key) local d = ns.FindRing(key) return d and d.key == key and d or nil end
local function Shown(def) return def.toggle and not ns.HiddenForClass(def) end

-- Everything that's new: rings with `since` and NEW_FEATURES, newest release first.
-- unseenOnly: only what this player hasn't been shown yet.
local function NewItems(unseenOnly)
    local list = {}
    for _, def in ipairs(ns.RINGS) do
        if def.since and Shown(def) then
            table.insert(list, { id = def.key, since = def.since, name = def.toggle[1], desc = def.toggle[2],
                                 setting = def.key .. "Enabled", onSet = def.toggle[3], show = def.key, rank = 1 })
        end
    end
    for i, f in ipairs(NEW_FEATURES) do
        local def = Def(f.show)
        if not def or Shown(def) then
            f.rank, f.order = f.setting and 2 or 3, i -- settings before plain news, as listed
            table.insert(list, f)
        end
    end
    if unseenOnly then
        local seen = db.seenNew or {}
        for i = #list, 1, -1 do if seen[list[i].id] then table.remove(list, i) end end
    end
    -- Newest release first; in each, new rings (by name), then new settings, then the news.
    table.sort(list, function(a, b)
        if a.since ~= b.since then return Newer(a.since, b.since) end
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.rank == 1 then return a.name < b.name end
        return a.order < b.order
    end)
    return list
end

local function MarkAllSeen()
    db.seenNew = db.seenNew or {}
    for _, item in ipairs(NewItems(false)) do db.seenNew[item.id] = true end
end

-- The version the New in page names: this build's, or (a dev build) the newest item's.
local function NewVersion(items)
    local v = AddonVersion()
    if v then return v end
    return items[1] and items[1].since or "this version"
end

---------------------------------------------------------------- state
SU.step = 1
SU.choice = {}     -- the Look and Placement choices: style, size, place
local showing = {}    -- rings the wizard put in edit mode to show them
SU.newItems = {}   -- what the New in page lists

local function StopShowing()
    for key in pairs(showing) do
        if ns.SetRingEditing then ns.SetRingEditing(key, false, true) end
        showing[key] = nil
    end
end

local function ToggleShow(key)
    local def = Def(key)
    if not (def and def.edit) then return end
    local on = not def.edit.get()
    ns.SetRingEditing(key, on, true)
    showing[key] = on or nil
end

local function SetEnabled(key, value, onSet)
    db[key] = value
    if onSet then onSet(value) end
end

-- Look: one style / size for every ring, or each ring's own (as it was when the wizard opened).
local function ApplyLook()
    for _, def in ipairs(ns.RINGS) do
        local k = def.key
        if DEFAULTS[k .. "Style"] ~= nil then
            db[k .. "Style"] = SU.choice.style == "keep" and SU.orig[k].style or SU.choice.style
        end
        if DEFAULTS[k .. "Size"] ~= nil then
            local f = SIZE_FACTOR[SU.choice.size]
            db[k .. "Size"] = f and math.floor(DEFAULTS[k .. "Size"] * f + 0.5) or SU.orig[k].size
        end
    end
end

-- For the files loaded after this one.
SU.GROUPS = GROUPS
SU.STYLES = STYLES
SU.SIZES = SIZES
SU.PLACES = PLACES
SU.STEPS = STEPS
SU.Def = Def
SU.Shown = Shown
SU.NewVersion = NewVersion
SU.showing = showing
SU.StopShowing = StopShowing
SU.ToggleShow = ToggleShow
SU.SetEnabled = SetEnabled
SU.ApplyLook = ApplyLook
SU.NewItems = NewItems
SU.MarkAllSeen = MarkAllSeen
