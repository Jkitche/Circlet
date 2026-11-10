-- Circlet: Saved settings: the defaults, ring groups and the `db` table every file uses.
local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------
-- The general settings are here; each ring adds its own when it registers (see
-- Core/Registry.lua), so a ring's defaults sit in its own file. CircletDB gets every
-- default it lacks when the addon loads (FillDefaults).

local DEFAULTS = {
    optionsAutoEdit = true, -- options window: a ring's page puts that ring in edit mode while it's open
    summaryOnLogout = true, -- show the session summary when you start logging out
    sessions = {}, -- per character: what's been gained this session (for /circ summary)
    loginFx     = true, -- the welcome animation when you log in
    lastSeen    = {},   -- per character: when you last logged out (for the welcome)
    discoverFx  = true, -- the "Discovered" animation when you explore a new area
    autoArrange = true, -- rings that pop at the same time slide apart instead of overlapping
    snapGrid    = true, -- edit mode: rings snap to a grid while you drag them
    gridSize    = 20,   -- grid spacing, in UI units (measured out from the screen's centre)
}

-- Settings every ring has, added for each registered ring once they're all loaded.
local RING_COMMON = {
    Shape    = "ring",     -- full ring, three-quarter arc or half arc (Draw/Ring.lua)
    Rotation = 180,        -- degrees clockwise to turn the ring (or arc)
    Combat   = true,       -- false: the ring fades out while you're in combat
    Fill     = "gradient", -- "solid" color or a "gradient" along the ring
    Gradient = 50,         -- gradient: % darker at the ring's start than its end
}

local function FinalizeDefaults()
    for _, def in ipairs(ns.RINGS) do
        for field, value in pairs(RING_COMMON) do
            if DEFAULTS[def.key .. field] == nil then DEFAULTS[def.key .. field] = value end
        end
        -- Rings with an icon can show it as the ring's background instead (off by default).
        if def.iconBg and DEFAULTS[def.key .. "IconBg"] == nil then
            DEFAULTS[def.key .. "IconBg"] = false
            DEFAULTS[def.key .. "IconBgAlpha"] = 40
        end
        -- Rings with a game bar of their own can hide it (Features/DefaultUI.lua); off by default.
        if def.gameBar and DEFAULTS[def.key .. "HideDefault"] == nil then
            DEFAULTS[def.key .. "HideDefault"] = false
        end
    end
end

-- Fills in every setting missing from CircletDB with its default, and any color
-- missing from a saved color table (one added in an update, say).
local function FillDefaults()
    for k, v in pairs(DEFAULTS) do
        if CircletDB[k] == nil then CircletDB[k] = ns.Copy(v) end
    end
    for _, group in ipairs(ns.COLOR_GROUPS) do
        if type(CircletDB[group]) ~= "table" then CircletDB[group] = {} end
        for name, color in pairs(DEFAULTS[group]) do
            if type(CircletDB[group][name]) ~= "table" then
                CircletDB[group][name] = CopyTable(color)
            end
        end
    end
end

-- Saved settings from removed features; cleared on load. From the nameplate highlighting:
local OBSOLETE = { "ringBorder", "ringBorderSize", "cleanupNotice", "enabled", "border", "thickness", "radius", "icon", "iconSize", "progress", "xpY",
    -- ...and from the floating progress text, replaced by the quest ring.
    "popEnabled", "popSize", "popHeight", "color",
    -- ...and the old level-up checkbox, now a style choice.
    "xpLevelFx",
    -- ...and spell schools learned from the combat log, which addons can't use here.
    "castSchools" }

-- Saved settings. CircletDB only exists once the addon has loaded, so every file
-- reads and writes it through this table, which forwards to whatever CircletDB is.
--
-- Quest rings (pinned quests) stack down the screen; ring N's settings are read as
-- pinN<Setting> and map onto the shared pin<Setting>, with FromTop offset per ring.
-- That way every ring helper (layout, dragging, edit mode) works on them unchanged.
-- Ring groups: several rings that share one set of settings. Ring N's settings are
-- read as <group>N<Setting> and map onto the shared <group><Setting>, offset per ring:
-- quest rings (pin) stack downward, totem rings (totem) sit side by side.
local GROUPS = {
    pin   = { axis = "FromTop", gap = 12 },
    totem = { axis = "X", gap = 8 },
}
local function GroupKey(k)
    local group, i, field = k:match("^(%l+)(%d+)(%u%a*)$")
    local g = group and GROUPS[group]
    if not g then return nil end
    return group, tonumber(i), field, g
end

local function GroupOffset(group, i, g)
    return (i - 1) * ((CircletDB[group .. "Size"] or 0) + g.gap)
end

local db = setmetatable({}, {
    __index = function(_, k)
        local group, i, field, g = GroupKey(k)
        if group then
            local v = CircletDB[group .. field]
            if field == g.axis and v then v = v + GroupOffset(group, i, g) end
            return v
        end
        return CircletDB[k]
    end,
    __newindex = function(_, k, v)
        local group, i, field, g = GroupKey(k)
        if group then
            if field == g.axis and v then v = v - GroupOffset(group, i, g) end
            CircletDB[group .. field] = v
            return
        end
        CircletDB[k] = v
    end,
})


-- Shared with the files loaded after this one.
ns.DEFAULTS = DEFAULTS
ns.OBSOLETE = OBSOLETE
ns.FinalizeDefaults = FinalizeDefaults
ns.FillDefaults = FillDefaults
ns.db = db
