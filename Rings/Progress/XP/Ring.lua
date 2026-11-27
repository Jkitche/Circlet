-- Circlet: XP ring: fills when you gain experience, colored by rest state.
local ADDON_NAME, ns = ...

local EDIT_STRATA, IsSecret = ns.EDIT_STRATA, ns.IsSecret
local RingHolder, RingThickness, XP_SEGMENTS, db = ns.RingHolder, ns.RingThickness, ns.XP_SEGMENTS, ns.db
local ns = ns.ns

-- Shared by the XP ring's files (Rings/Progress/XP/*.lua), which load in this order: Ring,
-- LevelUp, Gain, Rested, Draw, Play, Register.
ns.XPRing = ns.XPRing or {}
local XP = ns.XPRing

---------------------------------------------------------------------------
-- XP ring: a donut that pops up and fills when you gain experience
---------------------------------------------------------------------------
-- Drawn from line segments, so no image files are needed. Layers, back to front:
--   bg         dim full track
--   restBand   rested XP still ahead of you: ends where rested runs out
--              (the same spot as the marker on Blizzard's XP bar)
--   fillNormal / fillRested   your XP, colored by rest state like Blizzard's bar:
--              blue while rested, purple when normal. If rested runs out partway
--              through a gain, the fill is blue up to that point and purple after.
-- Values are tracked in "level units" (level + fraction), so a level-up just
-- animates past a whole number: the ring fills, flashes, and wraps.

-- Blizzard's XP bar hues, brightened a little to read on the dark track.
local STATE_COLORS = {
    rested = { r = 0.20, g = 0.52, b = 1.00 }, -- bar blue   (0.00, 0.39, 0.88)
    normal = { r = 0.74, g = 0.26, b = 0.86 }, -- bar purple (0.58, 0.00, 0.55)
}
-- Opaque on purpose: translucent segments overlap at their joints and show seams.
local REST_BAND = { r = 0.16, g = 0.28, b = 0.48 }   -- dim rested blue
local GOLD      = { r = 1.00, g = 0.82, b = 0.00 }


local xpRing = ns.NewRingFrame("xp")


xpRing.levelText = xpRing:CreateFontString(nil, "OVERLAY")
xpRing.gainText  = xpRing:CreateFontString(nil, "OVERLAY")
xpRing.deltaText = xpRing:CreateFontString(nil, "OVERLAY") -- share of a level gained
xpRing.pctText   = xpRing:CreateFontString(nil, "OVERLAY")
xpRing.stateText = xpRing:CreateFontString(nil, "OVERLAY")
local XP_TEXTS = { xpRing.levelText, xpRing.gainText, xpRing.deltaText, xpRing.pctText, xpRing.stateText }

-- The ring stays up permanently with "Always show", or as a minimap border.
local function AlwaysOn() return db.xpAlways or (db.xpMinimap and true) or false end
for _, fs in ipairs(XP_TEXTS) do
    fs:SetShadowOffset(1, -1)
end

local ring = xpRing.geom

-- The XP ring's own calls leave out its frame and geometry.
local NewRingLayer = function(drawLayer, subLevel, c, a, parent)
    return ns.NewRingLayer(drawLayer, subLevel, c, a, parent or xpRing)
end
local DrawArc = function(lines, from, to, frame, geom, noOverlap, shade)
    return ns.DrawArc(lines, from, to, frame or xpRing, geom or ring, noOverlap, shade)
end

xpRing.restBand   = NewRingLayer("BORDER", 0, REST_BAND, 1)
xpRing.fillNormal = NewRingLayer("ARTWORK", 0, STATE_COLORS.normal, 1)
xpRing.fillRested = NewRingLayer("ARTWORK", 1, STATE_COLORS.rested, 1)



-- "Show as minimap border": the ring wraps around the minimap instead of sitting in
-- its own spot. It's always up then, its text goes below the map, and it can't be dragged.
local function MinimapFrame()
    local mm = db.xpMinimap and _G.Minimap
    return (mm and mm.GetWidth) and mm or nil
end

-- The ring's diameter: its size setting, or around the minimap.
local function XPSize()
    local mm = MinimapFrame()
    if not mm then return db.xpSize end
    local parent = xpRing:GetParent() or UIParent
    local scale = (mm:GetEffectiveScale() or 1) / ((parent.GetEffectiveScale and parent:GetEffectiveScale()) or 1)
    local w = math.max(mm:GetWidth() or 0, mm:GetHeight() or 0) * scale
    local T = RingThickness("xp", db.xpSize)
    return math.floor(w + 2 * ((db.xpMinimapGap or 2) + T) + 0.5)
end


xpRing.isLocked = function() return MinimapFrame() ~= nil end

XP.xpEditing = false

-- Around the minimap the ring can sit behind it (one frame strata lower), so the map,
-- its border and buttons draw over the ring rather than under it.
local STRATA_BELOW = { LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH",
                       FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", TOOLTIP = "FULLSCREEN_DIALOG" }
-- Over it (the default), the ring sits one strata above the map, but never above MEDIUM,
-- where the game's windows are; anywhere else it's at the rings' usual strata, under them.
local STRATA_ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5 }
local STRATA_ABOVE = { BACKGROUND = "LOW", LOW = "MEDIUM" }
local function RingStrata(mm)
    if XP.xpEditing then return EDIT_STRATA end
    if not mm then return ns.RING_STRATA end
    local own = mm:GetFrameStrata()
    local cluster = _G.MinimapCluster
    local c = cluster and cluster.GetFrameStrata and cluster:GetFrameStrata()
    if db.xpMinimapBehind then
        -- The lower of the map and its cluster (the border and buttons live there).
        if c and (STRATA_ORDER[c] or 9) < (STRATA_ORDER[own] or 9) then own = c end
        return STRATA_BELOW[own] or "BACKGROUND"
    end
    -- The higher of the two, so the ring draws over both.
    if c and (STRATA_ORDER[c] or 0) > (STRATA_ORDER[own] or 0) then own = c end
    return STRATA_ABOVE[own] or "MEDIUM"
end

-- The XP ring's texts, top to bottom, for their size settings.
ns.RegisterTextRoles("xp", {
    { id = "Level", name = "Level", desc = "The top line: your level." },
    { id = "Gain", name = "XP gained", desc = "The big text in the middle: the XP you just gained." },
    { id = "Delta", name = "Gain as %", desc = "Under the gain, with Show gain as % on." },
    { id = "Pct", name = "Fill %", desc = "How far through the level you are." },
    { id = "State", name = "Rest state", desc = "The bottom line: rested, resting, or how long until fully rested." },
})

local function LayoutXPRing()
    local mm = MinimapFrame()
    local strata = RingStrata(mm)
    if xpRing:GetFrameStrata() ~= strata then xpRing:SetFrameStrata(strata) end
    local size = XPSize()
    ns.PlaceRing(xpRing, "xp", size)
    if mm then
        -- Around the minimap instead of its saved spot.
        xpRing:ClearAllPoints()
        xpRing:SetPoint("CENTER", mm, "CENTER", 0, 0)
    end

    local showDelta = db.xpShowDelta and true or false
    local inner = ns.UpdateGeometry(xpRing, "xp", size, tostring(showDelta) .. ":" .. tostring(mm ~= nil),
        mm and db.xpSize or nil)
    if not inner then return end
    if mm then inner = 100 end -- text below the minimap: a fixed size
    xpRing.gainText:SetFont(STANDARD_TEXT_FONT, ns.FontSize("xp", "Gain", inner * 0.18, 10), "OUTLINE")
    xpRing.deltaText:SetFont(STANDARD_TEXT_FONT, ns.FontSize("xp", "Delta", inner * 0.10, 8), "OUTLINE")
    xpRing.levelText:SetFont(STANDARD_TEXT_FONT, ns.FontSize("xp", "Level", inner * 0.12, 9), "OUTLINE")
    xpRing.pctText:SetFont(STANDARD_TEXT_FONT, ns.FontSize("xp", "Pct", inner * 0.13, 9), "OUTLINE")
    xpRing.stateText:SetFont(STANDARD_TEXT_FONT, ns.FontSize("xp", "State", inner * 0.11, 8), "OUTLINE")

    for _, fs in ipairs(XP_TEXTS) do
        fs:ClearAllPoints()
    end
    -- Stack: level / +gain XP / (+delta%) / fill % / rest state. Around the minimap the
    -- stack hangs below the ring instead of sitting inside it.
    if mm then
        xpRing.levelText:SetPoint("TOP", xpRing, "BOTTOM", 0, -2)
        xpRing.gainText:SetPoint("TOP", xpRing.levelText, "BOTTOM", 0, -1)
    else
        xpRing.gainText:SetPoint("CENTER", xpRing, "CENTER", 0, math.floor(inner * (showDelta and 0.11 or 0.06)))
        xpRing.levelText:SetPoint("BOTTOM", xpRing.gainText, "TOP", 0, 1)
    end
    xpRing.deltaText:SetPoint("TOP", xpRing.gainText, "BOTTOM", 0, 0)
    if showDelta then
        xpRing.pctText:SetPoint("TOP", xpRing.deltaText, "BOTTOM", 0, -2)
    else
        xpRing.pctText:SetPoint("TOP", xpRing.gainText, "BOTTOM", 0, -2)
    end
    xpRing.stateText:SetPoint("TOP", xpRing.pctText, "BOTTOM", 0, -1)
end

-- State ---------------------------------------------------------------------

local xpState = { level = nil, cur = nil, max = nil, rest = 0, pendingLevel = nil }
local anim = { from = 0, to = 0, shown = 0, t = 1, dur = 0.9, session = 0, holdUntil = 0, flashUntil = 0,
               gainFrom = 0, gainShown = 0,
               sessionFrom = 0,      -- level units where this ring session started (for the delta %)
               restRunout = nil,     -- level units where this session's rested XP ran out (nil: wasn't rested)
               preview = false, previewRested = 0, previewMax = 1000,
               restGain = nil }      -- leaving a rest area: { from, to, max, shown, t, dur } (rested XP)

-- XP earned during combat (or while editing the ring) is held here and shown afterwards.
local combatQueue = { from = nil, to = nil, gain = 0, rest = nil, max = nil }
XP.xpInCombat = false
XP.xpSampleAt, XP.xpSampleRested = 0, true

local function XPFraction(cur, max)
    if not max or max <= 0 then return 0 end
    return math.min(math.max(cur / max, 0), 1)
end

local function LiveRestedXP()
    local r = GetXPExhaustion and GetXPExhaustion() or 0
    if r == nil or IsSecret(r) then return 0 end
    return r
end

-- Remaining rested XP and the level size it's measured against.
local function RestedNow()
    local g = anim.restGain
    if g then return g.shown, g.max end -- the rested-gain animation
    if anim.preview then return anim.previewRested, anim.previewMax end
    return LiveRestedXP(), xpState.max or 0
end

-- For the files loaded after this one.
XP.xpRing = xpRing
XP.ring = ring
XP.NewRingLayer = NewRingLayer
XP.DrawArc = DrawArc
XP.anim = anim
XP.STATE_COLORS = STATE_COLORS
XP.xpState = xpState
XP.GOLD = GOLD
XP.XP_TEXTS = XP_TEXTS
XP.AlwaysOn = AlwaysOn
XP.MinimapFrame = MinimapFrame
XP.XPSize = XPSize
XP.LayoutXPRing = LayoutXPRing
XP.combatQueue = combatQueue
XP.RestedNow = RestedNow
XP.RingStrata = RingStrata
XP.XPFraction = XPFraction
XP.LiveRestedXP = LiveRestedXP
