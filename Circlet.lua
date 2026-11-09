-- Circlet
-- Quest and leveling quality-of-life for WoW Forever: progress rings that pop up
-- and fill when you gain quest progress, XP, skill points, reputation or pet XP,
-- plus an ammo / soul shard ring.
--
-- This file: saved-settings defaults and the shared ring drawing, positioning and
-- auto-arrange code. Everything else is in Modules\ (loaded in .toc order), and the
-- files share their functions through `ns`, the table the game passes every file.

local ADDON_NAME, ns = ...

local DEFAULTS = {
    questEnabled     = true,
    questAfterCombat = true,
    questShowDelta   = false,
    questCompleteFx  = true, -- "!" animation when an objective completes
    questSize        = 120,
    questThickness   = 12,
    questOpacity     = 100, -- percent
    questX           = -170,
    questFromTop     = 50,
    questHold        = 3,
    questStyle       = "smooth",
    questBorder      = 2, -- black border width (0 = none)
    questTurnIn      = true, -- "Ready to turn in" once every objective of a quest is done
    repEnabled     = true,
    repAfterCombat = true,
    repShowDelta   = false,
    repIcons       = true, -- the faction's icon as a badge on the ring
    repUseStanding = true,
    repSize        = 120,
    repThickness   = 12,
    repOpacity     = 100, -- percent
    repX           = -340,
    repFromTop     = 50,
    repHold        = 3,
    repStyle       = "smooth",
    repBorder      = 2, -- black border width (0 = none)
    repColors      = { custom = { r = 0.30, g = 0.80, b = 0.30 } },
    repKnown       = {}, -- faction IDs seen, so collapsed headers don't hide them later
    questColors = {
        progress = { r = 1.00, g = 0.82, b = 0.00 }, -- quest gold
        complete = { r = 0.25, g = 1.00, b = 0.25 },
    },
    xpEnabled     = true,
    xpSize        = 140,
    xpThickness   = 14,
    xpOpacity     = 100, -- percent
    xpX           = 0,
    xpFromTop     = 40,
    xpHold        = 3,
    xpStyle       = "smooth",
    xpBorder      = 2, -- black border width (0 = none)
    xpRestedRing  = true, -- at an inn or city, keep the ring up showing rested XP building
    xpRestedGain  = true, -- leaving a rest area, show how much rested XP you gained there
    xpRestIcon    = true, -- the animated "zZZ" on the ring while you're resting
    restBase      = {},   -- per character: rested XP when you entered the current rest area
    xpAfterCombat = true,
    xpShowDelta   = true,  -- "+23.6%" under the XP gain
    xpLevelFxStyle = "gold", -- level-up effect: "gold", "rainbow" or "none"
    xpAlways      = false, -- keep the XP ring on screen permanently
    xpMinimap     = false, -- draw the XP ring around the minimap (always on; text below the map)
    xpMinimapGap  = 2,     -- gap between the minimap's edge and the ring
    xpMinimapBehind = true, -- draw the ring behind the minimap (its border and buttons go on top)
    xpHideText    = true,  -- always-on ring out in the world: fade its text out after xpHideTextDelay idle seconds
    xpHideTextDelay = 3,
    skillEnabled     = true,
    skillAfterCombat = true,
    skillShowDelta   = false,
    skillIconAlpha   = 80, -- % opacity of the drawn skill-type icon behind the ring's text
    skillIconStyle   = "game", -- "game": the game's own icons as a badge; "drawn": line-drawn glyphs
    skillProfessions = true,
    skillSecondary   = true,
    skillSize        = 120,
    skillThickness   = 12,
    skillOpacity     = 100, -- percent
    skillX           = 170,
    skillFromTop     = 50,
    skillHold        = 3,
    skillStyle       = "smooth",
    skillBorder      = 2, -- black border width (0 = none)
    skillColors = {
        profession = { r = 0.32, g = 0.82, b = 0.36 },
        secondary  = { r = 0.26, g = 0.78, b = 0.86 },
        capped     = { r = 1.00, g = 0.82, b = 0.00 },
    },
    -- Weapon skill ring: weapon skills and Defense (the skill ring above is professions
    -- and secondary skills). Left of the reputation ring.
    weaponEnabled     = true,
    weaponAfterCombat = true,  -- weapon skills mostly go up mid-fight
    weaponShowDelta   = false,
    weaponIconAlpha   = 80,
    weaponIconStyle   = "game",
    weaponSize        = 120,
    weaponThickness   = 12,
    weaponOpacity     = 100,
    weaponX           = -510,
    weaponFromTop     = 50,
    weaponHold        = 3,
    weaponStyle       = "smooth",
    weaponBorder      = 2,
    weaponColors = {
        fill   = { r = 0.92, g = 0.40, b = 0.26 },
        capped = { r = 1.00, g = 0.82, b = 0.00 },
    },
    -- Ammo ring: arrows, bullets and thrown weapons, plus a warlock's soul shards.
    ammoEnabled     = true,
    ammoAfterCombat = false, -- running low mid-fight is exactly when it matters
    ammoShowDelta   = false,
    ammoWarn        = 200, -- show the ring at or below this much ammo
    ammoShards      = true,
    ammoShardWarn   = 5,   -- ...and at or below this many soul shards
    ammoSize        = 110,
    ammoThickness   = 11,
    ammoOpacity     = 100,
    ammoX           = 510,
    ammoFromTop     = 55,
    ammoHold        = 3,
    ammoStyle       = "segmented",
    ammoBorder      = 2, -- black border width (0 = none)
    ammoIcon        = true, -- the ammo's (or soul shard's) icon as a badge on the ring
    ammoColors = {
        normal  = { r = 0.86, g = 0.74, b = 0.46 },
        low     = { r = 1.00, g = 0.55, b = 0.10 },
        out     = { r = 0.95, g = 0.15, b = 0.15 },
        restock = { r = 0.30, g = 0.85, b = 0.30 },
    },
    -- Pet ring: your pet's experience.
    petEnabled     = true,
    petAfterCombat = true,
    petShowDelta   = false,
    petSize        = 110,
    petThickness   = 11,
    petOpacity     = 100,
    petX           = 340,
    petFromTop     = 55,
    petHold        = 3,
    petStyle       = "smooth",
    petBorder      = 2, -- black border width (0 = none)
    petPortrait    = true, -- your pet's portrait as a badge on the ring
    petColors = {
        xp    = { r = 0.40, g = 0.70, b = 1.00 },
        level = { r = 1.00, g = 0.82, b = 0.00 },
    },
    -- Flight ring: a countdown to landing on flight paths.
    flightEnabled     = true,
    flightLearnNotice = true, -- chat line when a new route has been timed
    flightSize        = 120,
    flightThickness   = 12,
    flightOpacity     = 100,
    flightX           = 170,  -- right of the crafting ring
    flightFromTop     = 255,
    flightHold        = 3,    -- seconds it stays after landing
    flightStyle       = "smooth",
    flightBorder      = 2, -- black border width (0 = none)
    flightColors = {
        fill     = { r = 0.45, g = 0.75, b = 1.00 },
        learning = { r = 0.75, g = 0.75, b = 0.80 },
    },
    flightTimes = {},
    -- Timed quest ring: escort and other timed quests. Sits on the right, by the quest list.
    timedEnabled   = true,
    timedWarn      = 60, -- seconds left when it turns the warning color
    timedSize      = 110,
    timedThickness = 11,
    timedOpacity   = 100,
    timedX         = 340,  -- right of the flight ring
    timedFromTop   = 260,
    timedHold      = 3,
    timedStyle     = "smooth",
    timedBorder    = 2, -- black border width (0 = none)
    timedColors = {
        fill = { r = 0.95, g = 0.80, b = 0.25 },
        warn = { r = 0.95, g = 0.25, b = 0.15 },
    },
    -- Corpse ring: distance (and direction) to your body while you're a ghost.
    corpseEnabled   = true,
    corpseSize      = 130,
    corpseThickness = 12,
    corpseOpacity   = 100,
    corpseX         = -170, -- left of the crafting ring
    corpseFromTop   = 250,
    corpseHold      = 0,
    corpseStyle     = "smooth",
    corpseBorder    = 2, -- black border width (0 = none)
    corpseColors = {
        fill   = { r = 0.60, g = 0.75, b = 0.95 },
        ready  = { r = 0.30, g = 0.90, b = 0.40 },
        marker = { r = 1.00, g = 0.95, b = 0.60 },
    },
    -- Crafting ring: progress through a batch of crafts.
    craftEnabled   = true,
    craftSingle    = true,  -- also for one-off crafts (not just batches)
    craftIcon      = true,  -- the item's icon as a badge on the ring
    craftSize      = 110,
    craftThickness = 11,
    craftOpacity   = 100,
    craftX         = 0,
    craftFromTop   = 260,
    craftHold      = 3,
    craftStyle     = "segmented",
    craftBorder    = 2, -- black border width (0 = none)
    craftColors = {
        fill = { r = 0.95, g = 0.65, b = 0.25 },
        done = { r = 0.35, g = 0.90, b = 0.40 },
    },
    -- Breath ring: breath, fatigue and Feign Death timers. Shares the corpse ring's
    -- spot (a ghost has no breath to hold).
    breathEnabled   = true,
    breathBubbles   = true, -- bubbles rising off the ring while you hold your breath
    breathSize      = 110,
    breathThickness = 11,
    breathOpacity   = 100,
    breathX         = -170,
    breathFromTop   = 260,
    breathHold      = 2,
    breathStyle     = "smooth",
    breathBorder    = 2,
    breathColors = {
        fill     = { r = 0.35, g = 0.75, b = 1.00 },
        low      = { r = 1.00, g = 0.60, b = 0.15 },
        critical = { r = 1.00, g = 0.20, b = 0.20 },
        fatigue  = { r = 0.85, g = 0.70, b = 0.30 },
        feign    = { r = 0.70, g = 0.70, b = 0.75 },
    },
    -- Cast ring: your casts and channels, timed even in combat. Shares the crafting
    -- ring's spot (crafts and gathers are left to their own rings).
    castEnabled   = true,
    castIcon      = true,
    castSize      = 100,
    castThickness = 10,
    castOpacity   = 100,
    castX         = 0,
    castFromTop   = 265,
    castHold      = 1,
    castStyle     = "smooth",
    castBorder    = 2,
    castColors = {
        cast        = { r = 1.00, g = 0.75, b = 0.20 },
        channel     = { r = 0.40, g = 0.80, b = 1.00 },
        done        = { r = 0.40, g = 0.90, b = 0.40 },
        interrupted = { r = 1.00, g = 0.30, b = 0.30 },
    },
    -- Gathering ring: mining, herbalism, skinning and fishing casts, then what you got.
    -- Shares the crafting ring's spot (you never do both at once).
    gatherEnabled   = true,
    gatherIcon      = true,  -- profession / item icon in the middle
    gatherLoot      = true,  -- show what you gathered when it finishes
    gatherSize      = 110,
    gatherThickness = 11,
    gatherOpacity   = 100,
    gatherX         = 0,
    gatherFromTop   = 260,
    gatherHold      = 3,
    gatherStyle     = "smooth",
    gatherBorder    = 2,
    gatherColors = {
        fill    = { r = 0.45, g = 0.85, b = 0.35 },
        fishing = { r = 0.30, g = 0.65, b = 1.00 },
        done    = { r = 1.00, g = 0.82, b = 0.25 },
    },
    -- Quest rings: quests you pin from the quest log's right-click menu, each tracked on
    -- its own ring, stacked down the right side by the quest list.
    pinEnabled   = true,
    pinSize      = 100,
    pinThickness = 10,
    pinOpacity   = 100,
    pinX         = 600,   -- set from your screen width the first time (see Events)
    pinFromTop   = 200,
    pinHold      = 3,
    pinStyle     = "segmented", -- with this, one notch per objective
    pinBorder    = 2,
    pinMenu      = true,  -- right-click a quest ring for its menu (remove it)
    pinMovable   = true,  -- quest rings can be dragged in edit mode
    pinned       = {},    -- per character: the pinned quest IDs, in order
    -- Totem rings (shamans): one small ring per active totem, in a row.
    totemEnabled   = true,
    totemWarn      = true, -- pulse in the last 10 seconds
    totemSize      = 56,
    totemThickness = 6,
    totemOpacity   = 100,
    totemX         = -96,  -- the first (earth) ring; the rest go to its right
    totemFromTop   = 400,
    totemHold      = 0,
    totemStyle     = "smooth",
    totemBorder    = 2,
    totemSpells = {}, -- learned: totem spell ID -> { slot, duration, icon }
    totemColors = {
        earth = { r = 0.65, g = 0.50, b = 0.30 },
        fire  = { r = 1.00, g = 0.40, b = 0.15 },
        water = { r = 0.25, g = 0.60, b = 1.00 },
        air   = { r = 0.80, g = 0.90, b = 1.00 },
    },
    optionsAutoEdit = true, -- options window: a ring's page puts that ring in edit mode while it's open
    summaryOnLogout = true, -- show the session summary when you start logging out
    sessions = {}, -- per character: what's been gained this session (for /sq summary) -- "From -> To" = seconds, learned as you fly (all characters)
    loginFx     = true, -- the welcome animation when you log in
    lastSeen    = {},   -- per character: when you last logged out (for the welcome)
    discoverFx  = true, -- the "Discovered" animation when you explore a new area
    autoArrange = true, -- rings that pop at the same time slide apart instead of overlapping
    snapGrid    = true, -- edit mode: rings snap to a grid while you drag them
    gridSize    = 20,   -- grid spacing, in UI units (measured out from the screen's centre)
}
-- Every ring can be a full ring or an arc (see RING_SHAPES).
do
    local rings = {}
    for k, v in pairs(DEFAULTS) do
        local ring = type(k) == "string" and k:match("^(%l+)Style$")
        if ring and (v == "smooth" or v == "segmented" or v == "thin") then rings[#rings + 1] = ring end
    end
    -- Rings with a game bar of their own can hide it (see DefaultUI.lua); off by default.
    for _, ring in ipairs({ "xp", "rep", "craft", "gather", "cast", "breath", "timed", "totem" }) do
        DEFAULTS[ring .. "HideDefault"] = false
    end
    for _, ring in ipairs(rings) do
        DEFAULTS[ring .. "Shape"] = "ring"
        DEFAULTS[ring .. "Rotation"] = 180 -- degrees clockwise to turn the ring (or arc)
        DEFAULTS[ring .. "Combat"] = true  -- false: the ring fades out while you're in combat
        DEFAULTS[ring .. "Fill"] = "gradient" -- "solid" color or a "gradient" along the ring
        DEFAULTS[ring .. "Gradient"] = 50  -- gradient: % darker at the ring's start than its end
    end
end

-- Saved settings from removed features; cleared on load. From the nameplate highlighting:
local OBSOLETE = { "ringBorder", "ringBorderSize", "cleanupNotice", "enabled", "border", "thickness", "radius", "icon", "iconSize", "progress", "xpY",
    -- ...and from the floating progress text, replaced by the quest ring.
    "popEnabled", "popSize", "popHeight", "color",
    -- ...and the old level-up checkbox, now a style choice.
    "xpLevelFx" }

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

local PREFIX = "|cffffd100Circlet|r: "

local function Print(...)
    print(PREFIX .. string.join(" ", tostringall(...)))
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Auto-arrange: every ring frame, so rings that are up at the same time can keep
-- out of each other's way. The ring that appeared first keeps its spot; a ring that
-- pops up on top of it slides sideways just far enough to clear it, and slides back
-- home once the first one fades.
local RING_FRAMES = {}
local ARRANGE_GAP = 8

local function HomeCenter(key)
    local size = db[key .. "Size"]
    return db[key .. "X"], -(db[key .. "FromTop"] + size / 2), size / 2
end

-- Called from each ring's layout (every frame while it's up). Returns the sideways
-- offset to add to the ring's saved position.
local function ArrangeX(key, frame)
    local now = GetTime()
    -- Layout runs every frame while a ring is up; a gap means it was hidden in between.
    local fresh = now - (frame.arrangeSeen or 0) > 0.5
    if fresh then frame.shownAt = now end
    local dt = fresh and 1 or (now - frame.arrangeSeen)
    frame.arrangeSeen = now

    local target = 0
    if db.autoArrange and not frame.isEditing then
        local hx, hy, r = HomeCenter(key)
        for _ = 1, 4 do -- a few passes, in case clearing one ring lands on another
            local moved = false
            for otherKey, other in pairs(RING_FRAMES) do
                local older = other.shownAt and (other.shownAt < frame.shownAt
                    or (other.shownAt == frame.shownAt and otherKey < key))
                if other ~= frame and older and other:IsShown() and now - (other.arrangeSeen or 0) < 0.5 then
                    local ox, oy, orad = HomeCenter(otherKey)
                    ox = ox + (other.arrangeX or 0)
                    local need, dy = r + orad + ARRANGE_GAP, math.abs(hy - oy)
                    if dy < need then
                        local minDx = math.sqrt(need * need - dy * dy)
                        if math.abs(hx + target - ox) < minDx - 0.5 then
                            local dir = (hx >= ox) and 1 or -1 -- away from it, on our home side
                            target = ox + dir * minDx - hx
                            moved = true
                        end
                    end
                end
            end
            if not moved then break end
        end
    end

    local cur = frame.arrangeX or 0
    frame.arrangeX = fresh and target or cur + (target - cur) * math.min(1, dt * 10)
    return frame.arrangeX
end

-- Ring styles. smooth: a solid band. segmented: 24 notches with small gaps (like the
-- old XP bar's bubbles). thin: a slim band around the edge, so the text has more room.
local RING_STYLE_NAMES = { smooth = "Smooth", segmented = "Segmented", thin = "Thin" }
local RING_STYLE_ORDER = { "smooth", "segmented", "thin" }

-- Band width for a ring's style, plus the width used to size its text (the normal
-- one, so switching style doesn't resize the text).
local function RingThickness(key, size)
    local t = math.min(db[key .. "Thickness"], size / 2 - 2)
    if db[key .. "Style"] == "thin" then
        return math.max(2, math.floor(t * 0.4 + 0.5)), t
    end
    return t, t
end


-- In edit mode a ring can be dragged by itself; right-click puts it back.
-- Snap grid (edit mode). Grid points are measured out from the centre of the screen,
-- and it's the ring's centre that snaps. Holding Shift places a ring freely.
local function CursorPosition()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

local function SnapToGrid(cx, cy)
    if not db.snapGrid or IsShiftKeyDown() then return cx, cy end
    local g = math.max(2, db.gridSize or 20)
    local mx, my = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    return mx + math.floor((cx - mx) / g + 0.5) * g, my + math.floor((cy - my) / g + 0.5) * g
end

-- Where the ring being dragged should sit now (UIParent coordinates of its centre).
local function DragCenter(frame)
    local x, y = CursorPosition()
    return SnapToGrid(x + frame.grabX, y + frame.grabY)
end

local dragging -- the ring being dragged, if any
local dragDriver = CreateFrame("Frame")
dragDriver:Hide()
dragDriver:SetScript("OnUpdate", function()
    if not dragging then dragDriver:Hide() return end
    local cx, cy = DragCenter(dragging)
    dragging:ClearAllPoints()
    dragging:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
end)

local function MakeRingDraggable(frame, key)
    RING_FRAMES[key] = frame
    frame.sqKey = key -- for its per-ring border setting
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false) -- only while editing; otherwise clicks go straight through
    frame:RegisterForDrag("LeftButton")
    -- Dragged by hand rather than with StartMoving, so the ring can snap to the grid as
    -- it moves. Grab offset: where on the ring you picked it up.
    -- frame.isLocked (optional function): when it returns true the ring can't be moved.
    frame:SetScript("OnDragStart", function(self)
        if self.isLocked and self.isLocked() then return end
        local x, y = CursorPosition()
        local cx, cy = self:GetCenter()
        if not cx then return end
        self.grabX, self.grabY = cx - x, cy - y
        self.dragging = true
        dragging = self
        dragDriver:Show()
    end)
    frame:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = false
        dragging = nil
        dragDriver:Hide()
        local cx, cy = DragCenter(self)
        -- Back into this addon's own coordinates: offset from centre, gap from the top.
        ns.SetPosition(key, cx - UIParent:GetWidth() / 2, UIParent:GetHeight() - cy - db[key .. "Size"] / 2)
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if self.isLocked and self.isLocked() then return end
        if button == "RightButton" then ns.ResetPosition(key) end -- both set in EditMode.lua
    end)

    frame.editHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.editHint:SetText("Drag to move  ·  Shift: no snap  ·  Right-click to reset")
    frame.editHint:Hide()
end

local EDIT_STRATA = "TOOLTIP" -- above the options window (and its color picker) while editing


local XP_SEGMENTS = 72

local TRACK     = { r = 0.07, g = 0.07, b = 0.09 }

-- Each ring and its extras (icons, effects, the "!") live in one holder frame per
-- ring; the holder's alpha is that ring's Opacity setting. Frame alpha multiplies
-- down to children, so it combines with the rings' own fades.
local ringHolders = {}
local function RingHolder(key)
    local holder = ringHolders[key]
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder:SetAllPoints(UIParent)
        ringHolders[key] = holder
    end
    return holder
end

-- Each ring's holder fades to its opacity setting, or out entirely while you're in
-- combat if the ring's "Show in combat" is off (it's hidden once faded, so it can't be
-- clicked, and comes back when combat ends).
local inCombat = false
local holderFader = CreateFrame("Frame")
holderFader:Hide()

local function TargetAlpha(key)
    if inCombat and db[key .. "Combat"] == false then return 0 end
    return math.max(0, math.min(100, db[key .. "Opacity"] or 100)) / 100
end

local function ApplyOpacity(key)
    local holder = RingHolder(key)
    holder.targetAlpha = TargetAlpha(key)
    if holder.targetAlpha > 0 then holder:Show() end
    holderFader:Show()
end

holderFader:SetScript("OnUpdate", function(self, elapsed)
    local busy = false
    for _, holder in pairs(ringHolders) do
        local target = holder.targetAlpha
        if target then
            local a = holder:GetAlpha()
            local step = elapsed / 0.3
            if math.abs(a - target) <= step then
                holder:SetAlpha(target)
                if target == 0 then holder:Hide() end
                holder.targetAlpha = nil
            else
                holder:SetAlpha(a + (target > a and step or -step))
                busy = true
            end
        end
    end
    if not busy then self:Hide() end
end)

holderFader:RegisterEvent("PLAYER_REGEN_DISABLED")
holderFader:RegisterEvent("PLAYER_REGEN_ENABLED")
holderFader:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    if not CircletDB then return end
    for key in pairs(ringHolders) do ApplyOpacity(key) end
end)

-- One layer of a ring: XP_SEGMENTS line segments on parent, all one color.
-- count: how many segments (default XP_SEGMENTS); rings that draw a custom number of
-- notches (the crafting ring, one per item) need more.
local function NewRingLayer(drawLayer, subLevel, c, a, parent, count)
    local lines = {}
    for i = 1, count or XP_SEGMENTS do
        local line = parent:CreateLine(nil, drawLayer, nil, subLevel)
        if line.SetSnapToPixelGrid then
            line:SetSnapToPixelGrid(false)
            line:SetTexelSnappingBias(0)
        end
        line:SetColorTexture(c.r, c.g, c.b, a)
        lines[i] = line
    end
    return lines
end

-- frac 0 = the start of the ring (12 o'clock for a full ring), increasing clockwise.
-- geom.start / geom.sweep (fractions of a full circle) turn the ring into an arc.
local function RingPoint(geom, frac)
    local a = math.pi / 2 - 2 * math.pi * ((geom.start or 0) + frac * (geom.sweep or 1))
    return geom.R * math.cos(a), geom.R * math.sin(a)
end

-- Draws the arc [from, to] (fractions of a full circle) using one layer's segments.
-- frame/geom: the ring frame the lines are anchored to and its { R, T, step, style,
-- notches }. notches (segmented style only): how many notches; default 24. Each notch
-- gets enough segments to look round, so the layer needs that many lines (extra lines
-- are hidden; a layer with too few draws as many notches as it can).
-- noOverlap: for translucent layers. Segments normally overlap a little at each joint
-- to hide notches, but on a see-through ring the overlaps show up as brighter stripes.
-- shade: optional { r, g, b, amt } (see Shade): colors each segment along a gradient,
-- amt darker at the ring's start and the full color at its end.
local NOTCH_LINES = 3 -- segmented style: each notch is 3 of the 72 segments (24 notches)

local function DrawArc(lines, from, to, frame, geom, noOverlap, shade)
    local N = XP_SEGMENTS
    local notches = geom.style == "segmented" and (geom.notches or N / NOTCH_LINES) or nil
    if notches and notches < 2 then notches = nil end -- one notch: just a smooth ring
    local notched = notches ~= nil
    local sweep = geom.sweep or 1
    local full = from <= 0 and to >= 1 and not notched and sweep >= 1
    local per = notched and math.max(1, math.ceil(N / notches)) or 1 -- segments per notch
    local total = notched and math.min(#lines, notches * per) or N
    -- Gap between notches, as a fraction of the circle (never more than a third of a notch).
    -- geom.gapPx overrides the width (the border uses a narrower gap than its band).
    local gap = 0
    if notched then
        gap = (geom.gapPx or math.max(1.5, geom.T * 0.3)) / (2 * math.pi * math.max(geom.R, 1) * sweep)
        gap = math.min(gap, 0.33 / notches)
    end
    for i = 1, total do
        local line = lines[i]
        local s0, e0, lo, hi = (i - 1) / N, i / N, from, to
        if notched then
            local n, k = math.floor((i - 1) / per), (i - 1) % per
            local ns, ne = n / notches, (n + 1) / notches
            s0, e0 = ns + (ne - ns) * k / per, ns + (ne - ns) * (k + 1) / per
            lo = math.max(from, ns + gap / 2)
            hi = math.min(to, ne - gap / 2)
        end
        -- Overlap at joints (fills the notch a bend would leave), sized to this segment.
        local miter = noOverlap and 0 or (geom.T / 2) * math.tan(math.pi * (e0 - s0) * sweep)
        local s = math.max(s0, lo)
        local e = math.min(e0, hi)
        if e - s > 1e-4 then
            local x1, y1 = RingPoint(geom, s)
            local x2, y2 = RingPoint(geom, e)
            local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
            if len > 0 then
                local ux, uy = (x2 - x1) / len * miter, (y2 - y1) / len * miter
                -- Extend into neighbouring segments, but not past the arc's (or notch's) ends.
                if full or s > lo + 1e-6 then x1, y1 = x1 - ux, y1 - uy end
                if full or e < hi - 1e-6 then x2, y2 = x2 + ux, y2 + uy end
            end
            line:SetStartPoint("CENTER", frame, x1, y1)
            line:SetEndPoint("CENTER", frame, x2, y2)
            line:SetThickness(geom.T)
            if shade then
                local f = 1 - shade.amt * (1 - (s + e) / 2)
                line:SetColorTexture(shade.r * f, shade.g * f, shade.b * f, 1)
            end
            line:Show()
        else
            line:Hide()
        end
    end
    for i = total + 1, #lines do lines[i]:Hide() end
end

-- A ring's gradient for color c, as DrawArc's shade; nil for a solid fill.
-- <key>Fill: "solid" or "gradient"; <key>Gradient (0-100): how much darker the start is.
local shades = {}
local function Shade(key, c)
    if not key or db[key .. "Fill"] ~= "gradient" then return nil end
    local amt = tonumber(db[key .. "Gradient"]) or 0
    if amt <= 0 or not c then return nil end
    local t = shades[key] or {}
    shades[key] = t
    t.r, t.g, t.b, t.amt = c.r, c.g, c.b, math.min(100, amt) / 100
    return t
end

-- Ring border: a black band a little wider than the ring, behind its track. With the
-- segmented style its gaps are narrower by the border on each side, so every notch
-- gets its own outline.
local BORDER_COLOR = { r = 0, g = 0, b = 0, a = 0.9 }

-- Each ring's own border width (<key>Border; 0 = none).
local function BorderWidth(key)
    return key and tonumber(db[key .. "Border"]) or 0
end

-- Ring shapes: a full ring, or an arc open at the bottom. start: where the arc begins,
-- clockwise from 12 o'clock; sweep: how much of the circle it covers (both fractions).
local RING_SHAPES = {
    ring = { start = 0, sweep = 1 },
    arc  = { start = 0.625, sweep = 0.75 }, -- 7:30 round the top to 4:30
    half = { start = 0.75, sweep = 0.5 },   -- 9 o'clock over the top to 3 o'clock
}
local RING_SHAPE_NAMES = { ring = "Ring", arc = "Arc (three quarters)", half = "Half arc" }
local RING_SHAPE_ORDER = { "ring", "arc", "half" }

-- Sets a ring's geometry to its shape (<key>Shape) and rotation (<key>Rotation, degrees
-- clockwise from the shape's base position; the default is 180).
local function ApplyShape(geom, key)
    local shape = RING_SHAPES[key and db[key .. "Shape"]] or RING_SHAPES.ring
    local rot = key and tonumber(db[key .. "Rotation"]) or 0
    geom.start, geom.sweep = shape.start + rot / 360, shape.sweep
end

-- Part of each ring's layout key: changes when its border or shape does.
local function BorderKey(key)
    return "b" .. BorderWidth(key) .. ":" .. tostring(key and db[key .. "Shape"])
        .. ":" .. tostring(key and db[key .. "Rotation"])
end

-- Draws a ring's track (the full background circle) and its border, if it has one.
-- Call wherever the track is drawn: bg is the track layer, geom the ring's geometry.
-- width: border width; defaults to the ring's own setting (frame.sqKey).
local function DrawTrack(frame, bg, geom, width)
    local border = frame.sqBorder
    local b = width or BorderWidth(frame.sqKey)
    if b > 0 then
        if not border then
            border = {}
            for i = 1, #bg do
                local line = frame:CreateLine(nil, "BACKGROUND", nil, -8)
                if line.SetSnapToPixelGrid then
                    line:SetSnapToPixelGrid(false)
                    line:SetTexelSnappingBias(0)
                end
                line:SetColorTexture(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, BORDER_COLOR.a)
                border[i] = line
            end
            frame.sqBorder = border
        end
        local outer = { R = geom.R, T = geom.T + 2 * b, step = geom.step, style = geom.style, notches = geom.notches,
                        start = geom.start, sweep = geom.sweep }
        if geom.style ~= "segmented" and (geom.sweep or 1) < 1 then
            -- An arc's border runs a little past each end, so the ends are outlined too.
            local e = b / (2 * math.pi * math.max(geom.R, 1))
            outer.start, outer.sweep = (geom.start or 0) - e, geom.sweep + 2 * e
        end
        if geom.style == "segmented" then
            local notches = geom.notches or XP_SEGMENTS / NOTCH_LINES
            local circ = 2 * math.pi * math.max(geom.R, 1)
            local bandGap = math.min(math.max(1.5, geom.T * 0.3), 0.33 / math.max(notches, 1) * circ * (geom.sweep or 1))
            outer.gapPx = math.max(0, bandGap - 2 * b)
        end
        DrawArc(border, 0, 1, frame, outer)
    elseif border then
        for _, line in ipairs(border) do line:Hide() end
    end
    DrawArc(bg, 0, 1, frame, geom)
end

-- Shared with the files loaded after this one.
ns.DrawTrack = DrawTrack
ns.BorderKey = BorderKey
ns.Shade = Shade
ns.BorderWidthOf = BorderWidth
ns.ApplyShape = ApplyShape
ns.RING_SHAPE_NAMES = RING_SHAPE_NAMES
ns.RING_SHAPE_ORDER = RING_SHAPE_ORDER
ns.ADDON_NAME = ADDON_NAME
ns.ApplyOpacity = ApplyOpacity
ns.ApplyAllOpacity = function() for key in pairs(ringHolders) do ApplyOpacity(key) end end
ns.ArrangeX = ArrangeX
ns.DEFAULTS = DEFAULTS
ns.DrawArc = DrawArc
ns.EDIT_STRATA = EDIT_STRATA
ns.IsSecret = IsSecret
ns.MakeRingDraggable = MakeRingDraggable
ns.NewRingLayer = NewRingLayer
ns.OBSOLETE = OBSOLETE
ns.Print = Print
ns.RING_STYLE_NAMES = RING_STYLE_NAMES
ns.RING_STYLE_ORDER = RING_STYLE_ORDER
ns.RingHolder = RingHolder
ns.RingThickness = RingThickness
ns.TRACK = TRACK
ns.XP_SEGMENTS = XP_SEGMENTS
ns.db = db
ns.ns = ns
