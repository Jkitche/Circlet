-- Circlet: XP ring: fills when you gain experience, colored by rest state.
local ADDON_NAME, ns = ...

local EDIT_STRATA, IsSecret = ns.EDIT_STRATA, ns.IsSecret
local RingHolder, RingThickness, XP_SEGMENTS, db = ns.RingHolder, ns.RingThickness, ns.XP_SEGMENTS, ns.db
local ns = ns.ns

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

local xpEditing = false

-- Around the minimap the ring can sit behind it (one frame strata lower), so the map,
-- its border and buttons draw over the ring rather than under it.
local STRATA_BELOW = { LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH",
                       FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", TOOLTIP = "FULLSCREEN_DIALOG" }
-- Over it (the default), the ring sits one strata above the map, but never above MEDIUM,
-- where the game's windows are; anywhere else it's at the rings' usual strata, under them.
local STRATA_ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5 }
local STRATA_ABOVE = { BACKGROUND = "LOW", LOW = "MEDIUM" }
local function RingStrata(mm)
    if xpEditing then return EDIT_STRATA end
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
    xpRing.gainText:SetFont(STANDARD_TEXT_FONT, math.max(10, math.floor(inner * 0.18)), "OUTLINE")
    xpRing.deltaText:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(inner * 0.10)), "OUTLINE")
    xpRing.levelText:SetFont(STANDARD_TEXT_FONT, math.max(9, math.floor(inner * 0.12)), "OUTLINE")
    xpRing.pctText:SetFont(STANDARD_TEXT_FONT, math.max(9, math.floor(inner * 0.13)), "OUTLINE")
    xpRing.stateText:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(inner * 0.11)), "OUTLINE")

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
local xpInCombat = false
local xpSampleAt, xpSampleRested = 0, true

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

-- Level-up effect -------------------------------------------------------------
-- Plays when the fill crosses into a new level. Two styles:
--   gold:    the ring flashes gold, two gold shockwaves expand out of it and a
--            burst of sparks flies off its edge.
--   rainbow: a rainbow comet swirls twice around the ring, then the whole ring
--            flashes in rainbow, followed by rainbow shockwaves and sparks.

local FX_GOLD   = { r = 1.00, g = 0.82, b = 0.20 }
local FX_GLOW   = { r = 1.00, g = 0.95, b = 0.60 }
local FX_WAVES  = 2
local FX_SPARKS = 18
-- All timings below are in "effect time"; FX_SLOWDOWN stretches them in real time
-- (2 = the whole effect plays at half speed, twice as long).
local FX_SLOWDOWN = 2
local FX_LENGTH = { gold = 1.4, rainbow = 2.3 } -- effect time until everything has faded
-- Rainbow timeline: the swirl runs first, then the burst (glow, waves, sparks).
local SWIRL_TIME, SWIRL_TURNS, SWIRL_TAIL = 1.1, 2, 0.55
local RAINBOW_BURST_AT = 0.95

-- Bright, fully saturated color for a hue in [0, 1).
local function HueColor(h)
    h = h % 1
    local r = math.min(1, math.max(0, math.abs(h * 6 - 3) - 1))
    local g = math.min(1, math.max(0, 2 - math.abs(h * 6 - 2)))
    local b = math.min(1, math.max(0, 2 - math.abs(h * 6 - 4)))
    return r, g, b
end

local fx = CreateFrame("Frame", nil, RingHolder("xp"))
fx:SetFrameStrata(ns.RING_STRATA) -- under the game's windows
fx:SetSize(1, 1)
fx:SetPoint("CENTER", xpRing, "CENTER")
fx:Hide()

fx.waves = {}
for i = 1, FX_WAVES do
    local w = CreateFrame("Frame", nil, fx)
    w:SetAllPoints(fx)
    w.geom = { R = 0, T = 0, step = 2 * math.pi / XP_SEGMENTS }
    w.lines = NewRingLayer("OVERLAY", 0, FX_GOLD, 1, w)
    fx.waves[i] = w
end

fx.glow = CreateFrame("Frame", nil, fx)
fx.glow:SetAllPoints(fx)
fx.glow.geom = { R = 0, T = 0, step = 2 * math.pi / XP_SEGMENTS }
fx.glow.lines = NewRingLayer("OVERLAY", 0, FX_GLOW, 1, fx.glow)

-- Rainbow comet that swirls around the ring.
fx.swirl = CreateFrame("Frame", nil, fx)
fx.swirl:SetAllPoints(fx)
fx.swirl.geom = { R = 0, T = 0, step = 2 * math.pi / XP_SEGMENTS }
fx.swirl.lines = NewRingLayer("OVERLAY", 1, { r = 1, g = 1, b = 1 }, 1, fx.swirl)

-- Colors every segment of a ring layer by hue, rotating with time.
local function RainbowLayer(lines, t, alpha)
    for i, line in ipairs(lines) do
        local r, g, b = HueColor(i / XP_SEGMENTS + t * 0.8)
        line:SetColorTexture(r, g, b, alpha or 1)
    end
end

local function SolidLayer(lines, c)
    for _, line in ipairs(lines) do line:SetColorTexture(c.r, c.g, c.b, 1) end
end

fx.sparks = {}
for i = 1, FX_SPARKS do
    local t = fx:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Cooldown\\star4")
    t:SetBlendMode("ADD")
    t:SetVertexColor(FX_GOLD.r, FX_GOLD.g, FX_GOLD.b)
    t:Hide()
    fx.sparks[i] = { tex = t }
end

local function PlayLevelUpEffect(styleOverride)
    local style = styleOverride or db.xpLevelFxStyle
    if style ~= "gold" and style ~= "rainbow" then return end -- "none": effect off
    if ring.R <= 0 then return end
    fx.style = style
    fx:SetFrameLevel(xpRing:GetFrameLevel() + 5)

    -- The glow is a full ring drawn once, slightly fatter than the real one.
    fx.glow.geom.R, fx.glow.geom.T = ring.R, ring.T + 4
    DrawArc(fx.glow.lines, 0, 1, fx.glow, fx.glow.geom, true)
    -- The swirl rides exactly on the ring.
    fx.swirl.geom.R, fx.swirl.geom.T = ring.R, ring.T + 2
    DrawArc(fx.swirl.lines, 0, 1, fx.swirl, fx.swirl.geom, true)

    if style == "gold" then
        SolidLayer(fx.glow.lines, FX_GLOW)
        for _, w in ipairs(fx.waves) do SolidLayer(w.lines, FX_GOLD) end
    end

    -- Each burst is a little different.
    for i, s in ipairs(fx.sparks) do
        s.angle = (i / FX_SPARKS) * 2 * math.pi + (math.random() - 0.5) * 0.3
        s.dist  = 25 + math.random() * 45
        s.life  = 0.7 + math.random() * 0.4
        s.delay = math.random() * 0.15
        s.size  = 10 + math.random() * 10
        if style == "rainbow" then
            s.tex:SetVertexColor(HueColor(i / FX_SPARKS))
        else
            s.tex:SetVertexColor(FX_GOLD.r, FX_GOLD.g, FX_GOLD.b)
        end
    end
    fx.swirl:SetShown(style == "rainbow")
    fx.t = 0
    fx:Show()

    -- Keep the ring and its "LEVEL UP!" label on screen until the effect has finished.
    local finishAt = GetTime() + FX_LENGTH[style] * FX_SLOWDOWN
    anim.flashUntil = math.max(anim.flashUntil, finishAt)
    anim.holdUntil = math.max(anim.holdUntil, finishAt + 0.5)
end

fx:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed / FX_SLOWDOWN
    local t = self.t
    local rainbow = self.style == "rainbow"

    -- Rainbow swirl: a comet with a fading tail runs around the ring, easing out.
    if rainbow then
        local st = t / SWIRL_TIME
        if st <= 1 then
            local head = (1 - (1 - st) ^ 2) * SWIRL_TURNS -- turns travelled
            local N = XP_SEGMENTS
            for i, line in ipairs(self.swirl.lines) do
                local center = (i - 0.5) / N
                local behind = (head - center) % 1 -- how far this segment trails the head
                if head - center < 0 or behind > SWIRL_TAIL then
                    line:Hide()
                else
                    local r, g, b = HueColor(center * 2 + t * 1.5)
                    line:SetColorTexture(r, g, b, 1 - behind / SWIRL_TAIL)
                    line:Show()
                end
            end
            self.swirl:SetAlpha(st > 0.85 and (1 - st) / 0.15 or 1)
            self.swirl:Show()
        else
            self.swirl:Hide()
        end
    end

    local bt = t - (rainbow and RAINBOW_BURST_AT or 0) -- time since the burst

    -- Shockwaves: grow from the ring outward, thinning and fading as they go.
    for i, w in ipairs(self.waves) do
        local wt = (bt - (i - 1) * 0.18) / 0.8
        if wt >= 0 and wt <= 1 then
            local e = 1 - (1 - wt) ^ 2
            w.geom.R = ring.R + ring.R * 0.7 * e
            w.geom.T = math.max(1.5, ring.T * 0.9 * (1 - wt))
            DrawArc(w.lines, 0, 1, w, w.geom, true)
            if rainbow then RainbowLayer(w.lines, t) end
            w:SetAlpha(1 - wt)
            w:Show()
        else
            w:Hide()
        end
    end

    -- Glow: the whole ring flashes, up and back down over 0.6 s.
    local gt = bt / 0.6
    if gt >= 0 and gt < 1 then
        if rainbow then RainbowLayer(self.glow.lines, t) end
        self.glow:SetAlpha(math.sin(math.pi * gt) * 0.85)
        self.glow:Show()
    else
        self.glow:Hide()
    end

    -- Sparks: fly out from the ring's edge, shrink and fade.
    for _, s in ipairs(self.sparks) do
        local st = (bt - s.delay) / s.life
        if st >= 0 and st <= 1 then
            local d = ring.R + s.dist * (1 - (1 - st) ^ 2)
            s.tex:ClearAllPoints()
            s.tex:SetPoint("CENTER", self, "CENTER", math.cos(s.angle) * d, math.sin(s.angle) * d)
            local size = s.size * (1 - 0.5 * st)
            s.tex:SetSize(size, size)
            s.tex:SetAlpha(1 - st)
            s.tex:Show()
        else
            s.tex:Hide()
        end
    end

    if t > (FX_LENGTH[self.style] or 1.5) then self:Hide() end
end)

local ShowXPIdle -- defined below; the OnUpdate script needs it
local XPSample   -- edit mode's sample gain, also defined below

-- Resting "zZZ": the same animated icon as above your player portrait, on the ring's
-- top-right edge while you're resting. Built from the player frame's own animation
-- when it can be found (modern flipbook, or the classic state icon); otherwise three
-- drawn z's that drift up and fade.
local restIcon = CreateFrame("Frame", nil, xpRing)
restIcon:SetSize(1, 1)
restIcon:Hide()

local function FindFlipbook(region)
    if not region then return nil end
    local textures, groups = {}, {}
    if region.GetAtlas then table.insert(textures, region) end
    if region.GetRegions then
        for _, r in ipairs({ region:GetRegions() }) do
            if r.GetAtlas then table.insert(textures, r) end
        end
    end
    for _, tex in ipairs(textures) do
        local atlas = tex:GetAtlas()
        if atlas and tex.GetAnimationGroups then
            for _, g in ipairs({ tex:GetAnimationGroups() }) do table.insert(groups, { tex = tex, g = g }) end
        end
    end
    if region.GetAnimationGroups then
        for _, g in ipairs({ region:GetAnimationGroups() }) do table.insert(groups, { tex = textures[1], g = g }) end
    end
    for _, entry in ipairs(groups) do
        for _, a in ipairs({ entry.g:GetAnimations() }) do
            if a.GetFlipBookRows and entry.tex and entry.tex:GetAtlas() then
                return entry.tex:GetAtlas(), a:GetFlipBookRows(), a:GetFlipBookColumns(), a:GetFlipBookFrames(),
                    a:GetDuration()
            end
        end
    end
end

local function BuildRestIcon()
    if restIcon.built then return end
    restIcon.built = true
    -- Modern player frame: a flipbook animation.
    local content = PlayerFrame and PlayerFrame.PlayerFrameContent
    local contextual = content and content.PlayerFrameContentContextual
    local atlas, rows, cols, frames, duration = FindFlipbook(contextual and contextual.PlayerRestLoop)
    if not atlas then atlas, rows, cols, frames, duration = FindFlipbook(_G.PlayerRestLoop) end
    if atlas and rows and cols and frames and rows * cols > 0 then
        local tex = restIcon:CreateTexture(nil, "OVERLAY")
        tex:SetAtlas(atlas, false)
        tex:SetPoint("CENTER")
        local group = tex:CreateAnimationGroup()
        local anim = group:CreateAnimation("FlipBook")
        anim:SetFlipBookRows(rows)
        anim:SetFlipBookColumns(cols)
        anim:SetFlipBookFrames(frames)
        anim:SetDuration((duration and duration > 0) and duration or 1.5)
        group:SetLooping("REPEAT")
        restIcon.tex, restIcon.anim, restIcon.kind = tex, group, "flipbook"
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
        restIcon.aspect = (info and info.width and info.height and info.height > 0)
            and (info.width / cols) / (info.height / rows) or 1
        return
    end
    -- Classic player frame: a static "zzz" from the state icon sheet; it bobs gently.
    local classic = _G.PlayerRestIcon
    if classic and classic.GetTexture and classic:GetTexture() then
        local tex = restIcon:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(classic:GetTexture())
        tex:SetTexCoord(classic:GetTexCoord())
        tex:SetPoint("CENTER")
        restIcon.tex, restIcon.kind, restIcon.aspect = tex, "classic", 1
        return
    end
    -- Fallback: three z's.
    restIcon.zs = {}
    for i = 1, 3 do
        local z = restIcon:CreateFontString(nil, "OVERLAY")
        z:SetText(i == 1 and "z" or "Z")
        z:SetTextColor(0.75, 0.85, 1)
        restIcon.zs[i] = z
    end
    restIcon.kind, restIcon.aspect = "drawn", 1
end

-- Each frame while the ring is up: place it on the ring and animate the fallbacks.
local function UpdateRestIcon(show, radius, size)
    if not (show and db.xpRestIcon) then
        if restIcon:IsShown() then
            restIcon:Hide()
            if restIcon.anim then restIcon.anim:Stop() end
        end
        return
    end
    BuildRestIcon()
    local s = math.max(18, size * 0.24)
    restIcon:SetFrameLevel(xpRing:GetFrameLevel() + 4)
    restIcon:ClearAllPoints()
    -- On the ring's top-right edge, like the portrait's corner.
    restIcon:SetPoint("CENTER", xpRing, "CENTER", radius * 0.72, radius * 0.72 + s * 0.15)
    restIcon:SetSize(s, s)
    local t = GetTime()
    if restIcon.kind == "flipbook" then
        restIcon.tex:SetSize(s * restIcon.aspect, s)
    elseif restIcon.kind == "classic" then
        restIcon.tex:SetSize(s, s)
        restIcon.tex:SetPoint("CENTER", 0, math.sin(t * 2.2) * s * 0.06)
        restIcon.tex:SetAlpha(0.8 + 0.2 * math.sin(t * 2.2))
    else
        for i, z in ipairs(restIcon.zs) do
            local p = (t * 0.45 + (i - 1) / 3) % 1 -- each z rises and fades on its own cycle
            z:SetFont(STANDARD_TEXT_FONT, math.floor(s * (0.35 + 0.35 * p)), "OUTLINE")
            z:ClearAllPoints()
            z:SetPoint("CENTER", restIcon, "CENTER", (p - 0.5) * s * 0.5, (p - 0.4) * s * 0.9)
            z:SetAlpha(math.sin(p * math.pi))
        end
    end
    if not restIcon:IsShown() then
        restIcon:Show()
        if restIcon.anim then restIcon.anim:Play() end
    end
end

-- Resting (inn or city): the XP ring stays up showing your rested XP building.
local function RestingShow()
    if not (db.xpRestedRing and IsResting and IsResting()) or InCombatLockdown() then return false end
    return xpState.max ~= nil and xpState.max > 0
end

-- Rested XP grows 5% of a level per 8 hours of resting, up to 150% of a level.
local RESTED_CAP, RESTED_PER_HOUR = 1.5, 0.05 / 8

local function RestedFullIn(rested, max)
    local missing = RESTED_CAP * max - rested
    if missing <= max * 0.005 then return nil end
    local hours = missing / (max * RESTED_PER_HOUR)
    local h, m = math.floor(hours), math.floor((hours % 1) * 60)
    if h >= 48 then return string.format("full in ~%d days", math.floor(hours / 24 + 0.5)) end
    if h >= 1 then return string.format("full in ~%dh %02dm", h, m) end
    return string.format("full in ~%dm", math.max(1, m))
end

local function DrawRing(value)
    LayoutXPRing() -- cheap unless a setting changed; keeps the toggle live while the ring is up
    local level = math.floor(value + 1e-9)
    local frac = value - level
    local rested, max = RestedNow()
    local isRested = rested > 0

    -- How much of this level's fill is blue (rested) vs purple (normal).
    local blueTo = 0
    if isRested then
        blueTo = frac -- still rested: the whole fill is blue, like Blizzard's bar
    elseif anim.restRunout then
        local ru = anim.restRunout
        if ru >= value then
            blueTo = frac
        elseif math.floor(ru + 1e-9) == level then
            blueTo = ru - level -- ran out partway through this level
        end -- ran out in an earlier level: all purple
    end
    -- Solid fill: reset the segments' color (a gradient colors each one).
    local shadeR, shadeN = ns.Shade("xp", STATE_COLORS.rested), ns.Shade("xp", STATE_COLORS.normal)
    if not shadeR then
        local c = STATE_COLORS.rested
        for _, l in ipairs(xpRing.fillRested) do l:SetColorTexture(c.r, c.g, c.b, 1) end
        c = STATE_COLORS.normal
        for _, l in ipairs(xpRing.fillNormal) do l:SetColorTexture(c.r, c.g, c.b, 1) end
    end
    DrawArc(xpRing.fillRested, 0, blueTo, nil, nil, nil, shadeR)
    DrawArc(xpRing.fillNormal, blueTo, frac, nil, nil, nil, shadeN)

    -- Rested band: from the fill to where rested runs out (fixed at the final XP
    -- position, so the fill grows into it). Only on the level you'll end on.
    local finalLevel = math.floor(anim.to + 1e-9)
    if isRested and max > 0 and level == finalLevel then
        local bandEnd = math.min(1, (anim.to - finalLevel) + rested / max)
        DrawArc(xpRing.restBand, frac, bandEnd)
    else
        DrawArc(xpRing.restBand, 0, 0)
    end

    local stateColor = isRested and STATE_COLORS.rested or STATE_COLORS.normal

    if GetTime() < anim.flashUntil then
        xpRing.levelText:SetText("LEVEL UP!")
        xpRing.levelText:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
    else
        xpRing.levelText:SetText("Level " .. level)
        xpRing.levelText:SetTextColor(0.85, 0.85, 0.85)
    end

    local idle = anim.session == 0 -- permanent ring with no recent gain
    local resting = idle and not anim.preview and RestingShow()
    local rg = anim.restGain
    if rg then
        -- Leaving a rest area: the rested XP gained there, counting up as the band grows.
        local rc = STATE_COLORS.rested
        xpRing.gainText:SetText("+" .. BreakUpLargeNumbers(math.floor(rg.shown - rg.from + 0.5)) .. " rested")
        xpRing.gainText:SetTextColor(rc.r, rc.g, rc.b)
        xpRing.deltaText:SetText(string.format("+%.0f%% of a level", (rg.shown - rg.from) / rg.max * 100))
        xpRing.deltaText:SetTextColor(0.8, 0.8, 0.8)
    elseif resting then
        -- At an inn: show rested XP building up instead of a gain.
        local rc = STATE_COLORS.rested
        xpRing.gainText:SetText("Resting")
        xpRing.gainText:SetTextColor(rc.r, rc.g, rc.b)
        xpRing.deltaText:SetText(max > 0 and (RestedFullIn(rested, max) or "Fully rested") or "")
        xpRing.deltaText:SetTextColor(0.8, 0.8, 0.8)
    else
        xpRing.gainText:SetText(idle and "" or ("+" .. BreakUpLargeNumbers(math.floor(anim.gainShown + 0.5)) .. " XP"))
        xpRing.gainText:SetTextColor(1, 1, 1)

        -- Share of a level gained since the ring appeared; exact across level-ups because
        -- it's measured in level units.
        local delta = (value - anim.sessionFrom) * 100
        xpRing.deltaText:SetText((db.xpShowDelta and not idle) and string.format("+%.1f%%", math.max(0, delta)) or "")
        xpRing.deltaText:SetTextColor(stateColor.r, stateColor.g, stateColor.b)
    end

    xpRing.pctText:SetText(string.format("%.1f%%", frac * 100))
    xpRing.pctText:SetTextColor(stateColor.r, stateColor.g, stateColor.b)

    if isRested then
        -- Rested pool as a share of a level (it caps at 150%).
        xpRing.stateText:SetText(string.format("Rested %d%%", math.floor(rested / max * 100 + 0.5)))
    else
        xpRing.stateText:SetText("Normal")
    end
    xpRing.stateText:SetTextColor(stateColor.r, stateColor.g, stateColor.b)
end

xpRing:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()

    if anim.t < anim.dur then
        anim.t = math.min(anim.dur, anim.t + elapsed)
        local p = anim.t / anim.dur
        p = 1 - (1 - p) ^ 3 -- ease out
        local v = anim.from + (anim.to - anim.from) * p
        if math.floor(v + 1e-9) > math.floor(anim.shown + 1e-9) then
            anim.flashUntil = now + 1.5 -- crossed into a new level
            PlayLevelUpEffect()
        end
        anim.shown = v
        anim.gainShown = anim.gainFrom + (anim.session - anim.gainFrom) * p -- count up with the fill
    end
    local rg = anim.restGain
    if rg and rg.t < rg.dur then
        rg.t = math.min(rg.dur, rg.t + elapsed)
        local p = 1 - (1 - rg.t / rg.dur) ^ 3 -- ease out
        rg.shown = rg.from + (rg.to - rg.from) * p
    end
    DrawRing(anim.shown)
    UpdateRestIcon((IsResting and IsResting()) or (xpEditing and xpSampleRested == false), ring.R + ring.T / 2,
        XPSize())

    if xpEditing then
        local a = self:GetAlpha()
        if a < 1 then self:SetAlpha(math.min(1, a + elapsed / 0.2)) end
        anim.idleSince = nil
        for _, t in ipairs(XP_TEXTS) do t:SetAlpha(1) end
        if now >= xpSampleAt then XPSample() end
        return
    end

    -- Around a minimap that's hidden (some UIs hide it), the ring hides too.
    local mmf = MinimapFrame()
    if mmf and not mmf:IsVisible() then
        self:SetAlpha(0)
        return
    end

    -- Always-on ring with "hide text": out in the world, once it's sat idle for the delay,
    -- the text fades out and the ring works as a plain XP bar. Any gain, or the mouse over
    -- the ring, brings the text back. While resting it stays (it shows your rested XP).
    local textTarget = 1
    if now >= anim.holdUntil and AlwaysOn() and db.xpHideText and db.xpEnabled and not RestingShow() then
        anim.idleSince = anim.idleSince or now
        if now - anim.idleSince >= (db.xpHideTextDelay or 3) and not (MouseIsOver and MouseIsOver(self)) then
            textTarget = 0
        end
    else
        anim.idleSince = nil
    end
    local ta = XP_TEXTS[1]:GetAlpha() or 1
    if ta ~= textTarget then
        ta = textTarget > ta and math.min(1, ta + elapsed / 0.25) or math.max(0, ta - elapsed / 0.6)
        for _, t in ipairs(XP_TEXTS) do t:SetAlpha(ta) end
    end

    local a = self:GetAlpha()
    if now < anim.holdUntil then
        if a < 1 then self:SetAlpha(math.min(1, a + elapsed / 0.2)) end
    elseif (AlwaysOn() or RestingShow()) and db.xpEnabled then
        -- Permanent ring (or resting at an inn): stay up, and once the gain has had its time, go back to idle.
        if a < 1 then self:SetAlpha(math.min(1, a + elapsed / 0.2)) end
        if anim.preview or anim.session ~= 0 or anim.restGain then
            ShowXPIdle(true)
        end
    else
        a = a - elapsed / 0.6
        if a <= 0 then
            self:SetAlpha(0)
            self:Hide()
            anim.session = 0
            anim.preview = false
            anim.restGain = nil
            return
        end
        self:SetAlpha(a)
    end
end)

-- restBefore / maxBefore: rested pool and level size just before this gain, used to
-- find where rested ran out. They only matter at the start of a ring session.
local function PlayXPRing(fromValue, toValue, gain, restBefore, maxBefore, force)
    if not db.xpEnabled and not force then return end
    if not force then anim.preview = false end
    if anim.restGain then
        anim.restGain = nil
        anim.session = 0 -- a real gain replaces the rested-gain display
    end
    LayoutXPRing()

    local gainFrom = 0
    if xpRing:IsShown() and anim.session > 0 then
        fromValue = anim.shown     -- keep going from wherever the fill currently is
        gainFrom = anim.gainShown  -- ...and keep counting from the number on screen
    else
        anim.session = 0
        anim.sessionFrom = fromValue
        if restBefore and restBefore > 0 and maxBefore and maxBefore > 0 then
            anim.restRunout = fromValue + restBefore / maxBefore
        else
            anim.restRunout = nil
        end
    end

    anim.session = anim.session + gain
    anim.gainFrom, anim.gainShown = gainFrom, gainFrom
    anim.from, anim.to, anim.shown, anim.t = fromValue, toValue, fromValue, 0

    -- Bigger fills (a whole fight's worth, or a level-up) animate longer so the
    -- count-up is readable; small ones stay snappy.
    anim.dur = math.min(2.5, math.max(0.8, 0.6 + (toValue - fromValue) * 2.5))

    anim.holdUntil = GetTime() + anim.dur + db.xpHold
    xpRing:Show()
    DrawRing(fromValue)
end

local function QueueOrPlayXP(fromValue, toValue, gain, restBefore, maxBefore)
    if (xpInCombat and db.xpAfterCombat) or xpEditing then
        if combatQueue.from == nil then
            combatQueue.from, combatQueue.rest, combatQueue.max = fromValue, restBefore, maxBefore
        end
        combatQueue.to = toValue
        combatQueue.gain = combatQueue.gain + gain
    else
        PlayXPRing(fromValue, toValue, gain, restBefore, maxBefore)
    end
end

local function OnXPCombatStart()
    xpInCombat = true
    if db.xpAfterCombat and xpRing:IsShown() then
        -- Fade out whatever was showing (a permanent ring just goes back to idle);
        -- the fight's total comes later.
        anim.holdUntil = 0
    end
end

-- Shows the ring at your current XP with no gain on it: the resting state of the
-- permanent ring. force: reset even if a gain or preview is on screen.
ShowXPIdle = function(force)
    if not ((AlwaysOn() or RestingShow()) and db.xpEnabled) then return end
    if not (xpState.level and xpState.max and xpState.max > 0) then return end -- max level / no data
    if not force and xpRing:IsShown() and (anim.session > 0 or anim.preview or anim.restGain) then return end

    local v = xpState.level + XPFraction(xpState.cur, xpState.max)
    LayoutXPRing()
    anim.preview = false
    anim.restGain = nil
    anim.session, anim.gainShown, anim.gainFrom = 0, 0, 0
    anim.from, anim.to, anim.shown, anim.t = v, v, v, anim.dur
    anim.sessionFrom, anim.restRunout, anim.holdUntil = v, nil, 0
    xpRing:Show()
    DrawRing(v)
end

-- Shows the rested XP gained while resting: the ring at your current XP with the
-- rested band growing from fromRest to toRest (XP, against a level of max).
local REST_GAIN_TIME = 1.8
local function PlayRestedGain(fromRest, toRest, max, preview)
    if not (db.xpEnabled or preview) then return end
    if not (xpState.level and xpState.max and xpState.max > 0) then return end
    local v = xpState.level + XPFraction(xpState.cur, xpState.max)
    LayoutXPRing()
    anim.preview = preview and true or false
    anim.session, anim.gainShown, anim.gainFrom = 0, 0, 0
    anim.from, anim.to, anim.shown, anim.t = v, v, v, anim.dur
    anim.sessionFrom, anim.restRunout = v, nil
    anim.restGain = { from = fromRest, to = toRest, max = max, shown = fromRest, t = 0, dur = REST_GAIN_TIME }
    anim.holdUntil = GetTime() + REST_GAIN_TIME + (db.xpHold or 3) + 1
    xpRing:SetAlpha(math.max(xpRing:GetAlpha(), 0.01))
    xpRing:Show()
    DrawRing(v)
end

-- Edit mode's sample: alternates a rested gain (blue fill, rested band) and a
-- normal one (purple), so both color states can be judged while settings change.
XPSample = function()
    local level = xpState.level or UnitLevel("player")
    anim.preview, anim.previewMax = true, 1000
    anim.previewRested = xpSampleRested and 250 or 0
    anim.session = 0 -- a fresh gain without hiding the ring
    PlayXPRing(level + 0.40, level + 0.62, 1240, xpSampleRested and 600 or nil, 1000, true)
    xpSampleAt = GetTime() + 3.5
    xpSampleRested = not xpSampleRested
end

local function SetXPEditing(on)
    xpEditing = on and true or false
    xpRing.isEditing = xpEditing
    xpRing:EnableMouse(xpEditing)
    xpRing.editHint:SetShown(xpEditing)
    xpRing:SetFrameStrata(RingStrata(MinimapFrame()))
    if xpEditing then
        xpSampleRested = true
        LayoutXPRing()
        XPSample()
        return
    end
    anim.preview = false
    anim.holdUntil = 0
    anim.session = 0 -- don't add the sample's numbers onto real XP
    if combatQueue.gain > 0 and not xpInCombat then
        -- XP that came in while editing.
        PlayXPRing(combatQueue.from, combatQueue.to, combatQueue.gain, combatQueue.rest, combatQueue.max)
        combatQueue.from, combatQueue.to, combatQueue.gain = nil, nil, 0
        combatQueue.rest, combatQueue.max = nil, nil
    else
        ShowXPIdle(true) -- a permanent ring goes back to your real XP
    end
end

-- The "Always show" checkbox: show the ring now, or let an idle one fade away.
-- Entering or leaving an inn or city (PLAYER_UPDATE_RESTING), or the option changing.
-- Rested XP when this character entered the current rest area, kept in saved
-- variables so rested XP built up while logged out at an inn counts too.
local function RestKey()
    local name, realm = UnitName("player"), GetRealmName and GetRealmName() or ""
    if IsSecret(name) then return nil end
    return (name or "?") .. "-" .. (realm or "")
end

local function OnRestingChanged()
    local key = RestKey()
    local resting = IsResting and IsResting()
    if key and db.restBase then
        if resting then
            if not db.restBase[key] then db.restBase[key] = LiveRestedXP() end
        elseif db.restBase[key] then
            -- Left the rest area: show what was gained there.
            local base = db.restBase[key]
            db.restBase[key] = nil
            local now, max = LiveRestedXP(), xpState.max or 0
            if db.xpRestedGain and max > 0 and now - base >= max * 0.01 and not xpEditing then
                PlayRestedGain(base, now, max)
                return
            end
        end
    end
    if RestingShow() then
        ShowXPIdle()
    elseif not AlwaysOn() and xpRing:IsShown() and anim.session == 0 and not anim.restGain then
        anim.holdUntil = 0 -- fade out
    end
end

local function PreviewRestedGain()
    local max = xpState.max or 1000
    PlayRestedGain(max * 0.15, max * 0.6, max, true)
end
ns.PreviewRestedGain = PreviewRestedGain
ns.OnRestingChanged = OnRestingChanged

local function OnXPAlwaysChanged()
    if AlwaysOn() then
        ShowXPIdle()
    elseif xpRing:IsShown() and anim.session == 0 then
        anim.holdUntil = 0 -- normal fade-out rules take over
    end
end

local function OnXPCombatEnd()
    -- XP for the final kill can land a moment after combat ends, so keep queueing
    -- briefly and then show the whole fight's total at once.
    C_Timer.After(0.4, function()
        if InCombatLockdown() then return end -- already in the next fight; keep queueing
        xpInCombat = false
        if combatQueue.gain > 0 then
            PlayXPRing(combatQueue.from, combatQueue.to, combatQueue.gain, combatQueue.rest, combatQueue.max)
        else
            ShowXPIdle() -- back to the resting / permanent ring
        end
        combatQueue.from, combatQueue.to, combatQueue.gain = nil, nil, 0
        combatQueue.rest, combatQueue.max = nil, nil
    end)
end

-- Rested XP grows while you sit in an inn; keep the "before" value fresh between gains.
-- Skipped during combat so a kill's rested use isn't counted before its XP arrives.
local function OnRestedChanged()
    if not xpInCombat then
        xpState.rest = LiveRestedXP()
    end
end

local function OnXPUpdate()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local level = UnitLevel("player")
    if IsSecret(cur) or IsSecret(max) or IsSecret(level) then return end

    -- Never go backwards: UnitLevel can lag behind a level-up for a moment.
    level = math.max(level, xpState.pendingLevel or 0, xpState.level or 0)
    xpState.pendingLevel = nil

    if xpState.level == nil then -- first reading is just the baseline
        xpState.level, xpState.cur, xpState.max = level, cur, max
        xpState.rest = LiveRestedXP()
        return
    end

    -- XP went down on the same level: a level-up the API hasn't reported yet.
    if level == xpState.level and cur < xpState.cur then
        level = xpState.level + 1
    end

    local gain
    if level > xpState.level then
        gain = (xpState.max - xpState.cur) + cur
    else
        gain = cur - xpState.cur
    end

    local fromValue = xpState.level + XPFraction(xpState.cur, xpState.max)
    local toValue = level + XPFraction(cur, max)
    local restBefore, maxBefore = xpState.rest, xpState.max
    xpState.level, xpState.cur, xpState.max = level, cur, max
    xpState.rest = LiveRestedXP()

    if gain > 0 then
        QueueOrPlayXP(fromValue, toValue, gain, restBefore, maxBefore)
        if ns.SessionAdd then
            ns.SessionAdd("xp", nil, gain)
            ns.SessionAdd("levels", nil, math.floor(toValue + 1e-9) - math.floor(fromValue + 1e-9))
        end
    end
end

-- Just the level-up moment, with whichever effect style is selected ("Off" shows
-- the level-up with no effect, exactly as it would happen in game).
local function PreviewLevelUp()
    local level = xpState.level or UnitLevel("player")
    xpRing:Hide()
    anim.session = 0
    anim.preview, anim.previewMax, anim.previewRested = true, 1000, 0
    PlayXPRing(level + 0.80, level + 1.15, 3500, nil, nil, true)
end

-- Walks through every state: rested with a band ahead, rested running out partway
-- (blue then purple), then a level-up while normal.
local function PreviewXPRing()
    local level = xpState.level or UnitLevel("player")
    xpRing:Hide()
    anim.session = 0
    anim.preview, anim.previewMax = true, 1000

    anim.previewRested = 150 -- 15% of a level left after this gain
    PlayXPRing(level + 0.40, level + 0.55, 980, 300, 1000, true) -- rested runs out at .70

    C_Timer.After(1.6, function()
        anim.previewRested = 0
        PlayXPRing(level + 0.55, level + 0.85, 1960, nil, nil, true) -- crosses .70: blue, then purple
    end)
    C_Timer.After(3.4, function()
        PlayXPRing(level + 0.85, level + 1.12, 2650, nil, nil, true) -- level-up, all purple
    end)
end

-- Events: XP, levels, rest state and combat.
ns.Listen({ "PLAYER_XP_UPDATE:player", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING",
            "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }, function(event, arg1)
    if event == "PLAYER_XP_UPDATE" then
        OnXPUpdate()
    elseif event == "PLAYER_LEVEL_UP" then
        -- UnitLevel can lag a moment behind this event; remember the new level.
        xpState.pendingLevel = tonumber(arg1)
    elseif event == "UPDATE_EXHAUSTION" or event == "PLAYER_UPDATE_RESTING" then
        OnRestedChanged()
        if event == "PLAYER_UPDATE_RESTING" then OnRestingChanged() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnXPCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnXPCombatEnd()
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnXPUpdate() -- baseline (or catch up after a loading screen)
        ShowXPIdle()  -- permanent XP ring, if turned on
        if IsResting and IsResting() then OnRestingChanged() end -- rested baseline if logging in at an inn
    end
end)

ns.RegisterCommand({ "levelup" }, PreviewLevelUp, "preview the level-up effect")
ns.RegisterCommand({ "rested" }, PreviewRestedGain, "preview the rested XP gained ring")

-- Shared with the files loaded after this one.
ns.OnRestedChanged = OnRestedChanged
ns.OnXPAlwaysChanged = OnXPAlwaysChanged
ns.OnXPCombatEnd = OnXPCombatEnd
ns.OnXPCombatStart = OnXPCombatStart
ns.OnXPUpdate = OnXPUpdate
ns.PreviewLevelUp = PreviewLevelUp
ns.PreviewXPRing = PreviewXPRing
ns.SetXPEditing = SetXPEditing
ns.ShowXPIdle = ShowXPIdle
ns.IsXPEditing = function() return xpEditing end -- live value, not a copy
ns.xpState = xpState

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "xp", name = "XP", order = 3,
    edit = { set = SetXPEditing, get = function() return xpEditing end },
    preview = PreviewXPRing, slash = { "xp" }, help = "preview the XP ring",
    toggle = { "XP ring", "Fills when you gain experience.", OnXPAlwaysChanged },
    gameBar = "the game's XP bar",
    onReset = function() OnXPAlwaysChanged() end,
    defaults = {
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
    },
    page = { folder = "progress", order = 2, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(2, "XP", "XP Ring",
                "A donut that pops up and fills when you gain experience, colored by rest state.",
                MergeTop(TopRow("xp", "XP ring", PreviewXPRing, "Show example XP gains: rested, rested running out, "
                    .. "and a level-up. Also /circ xp."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "xpEnabled", "Show XP ring", "Pop up and fill when you gain experience.",
                            OnXPAlwaysChanged),
                        always = Toggle(2, "xpAlways", "Always show",
                            "Keep the XP ring on screen permanently. Gains still animate and count up.", OnXPAlwaysChanged),
                        minimap = Toggle(2.05, "xpMinimap", "Show as minimap border",
                            "Wrap the XP ring around your minimap, as an XP bar that's always there. Its text sits below "
                            .. "the map (and hides when idle, below). Size and position settings don't apply then; "
                            .. "thickness, style and colors do.", OnXPAlwaysChanged),
                        minimapGap = {
                            type = "range", order = 2.07, name = "Distance from the map", min = -10, max = 30, step = 1,
                            desc = "Gap between the edge of the minimap and the ring. Negative values overlap the map's edge.",
                            get = function() return db.xpMinimapGap or 2 end,
                            set = function(_, v) db.xpMinimapGap = v end,
                            disabled = function() return not db.xpMinimap end,
                        },
                        minimapBehind = {
                            type = "toggle", order = 2.08, name = "Behind the minimap",
                            desc = "Draw the ring behind the minimap, so the map, its border and its buttons sit on top of "
                                .. "it. Off: the ring draws over them.",
                            get = function() return db.xpMinimapBehind end,
                            set = function(_, v) db.xpMinimapBehind = v end,
                            disabled = function() return not db.xpMinimap end,
                        },
                        hideText = {
                            type = "toggle", order = 2.1, name = "Hide text when idle",
                            desc = "With Always show on: out in the world, the ring's text fades out once nothing has changed "
                                .. "for a few seconds, so the ring works as a plain XP bar. The text comes back when you gain "
                                .. "XP or put the mouse over the ring, and stays while you're resting (it shows your rested XP).",
                            get = function() return db.xpHideText end,
                            set = function(_, v) db.xpHideText = v end,
                            disabled = function() return not (db.xpAlways or db.xpMinimap) end,
                        },
                        hideDelay = {
                            type = "range", order = 2.2, name = "Hide text after (seconds)", min = 1, max = 30, step = 1,
                            desc = "How long the always-on ring shows its text after a change before fading it out.",
                            get = function() return db.xpHideTextDelay or 3 end,
                            set = function(_, v) db.xpHideTextDelay = v end,
                            disabled = function() return not ((db.xpAlways or db.xpMinimap) and db.xpHideText) end,
                        },
                        resting = Toggle(2.5, "xpRestedRing", "Show while resting",
                            "At an inn or in a city, keep the ring up showing your rested XP building (the blue band) "
                            .. "and roughly how long until you're fully rested.", function() ns.OnRestingChanged() end),
                        restIcon = Toggle(2.55, "xpRestIcon", "Resting zZZ",
                            "While you're resting, the animated zZZ from your player portrait sits on the ring's "
                            .. "top-right edge."),
                        restedGain = Toggle(2.6, "xpRestedGain", "Show rested XP gained",
                            "When you leave an inn or city, the ring pops up with the rested band growing by the rested "
                            .. "XP you gained there (including while logged out), e.g. +1,240 rested."),
                        afterCombat = Toggle(3, "xpAfterCombat", "Wait until combat ends",
                            "Add up all XP earned during a fight and show the total once combat ends."),
                        delta = Toggle(4, "xpShowDelta", "Show gain as %",
                            "Add a line under the gain showing it as a share of the level, e.g. +4.2%."),
                    }),
                    levelUp = Box(3, "Level-up effect", {
                        style = Select(1, "xpLevelFxStyle", "Effect",
                            { gold = "Gold", rainbow = "Rainbow", none = "Off" }, { "gold", "rainbow", "none" },
                            "Gold: a gold flash, shockwaves and sparks. Rainbow: a rainbow swirl around the ring, "
                            .. "then a rainbow flash, shockwaves and sparks. Off: no effect."),
                        preview = Execute(2, "Preview level-up", PreviewLevelUp,
                            "Show a level-up with the selected effect. Also /circ levelup."),
                        restedPreview = Execute(3, "Preview rested gain", function() ns.PreviewRestedGain() end,
                            "Show what leaving an inn looks like after gaining rested XP. Also /circ rested."),
                    }),
                    size = SizeBox(4, "xp", "XP ring", "Offset from the center of the screen."),
                }))
            return tab
        end },
})
