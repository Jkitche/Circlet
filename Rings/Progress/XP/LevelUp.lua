-- Circlet: XP ring: the level-up effect (gold, or a rainbow swirl and burst).
local _, ns = ...

local RingHolder, XP_SEGMENTS, db = ns.RingHolder, ns.XP_SEGMENTS, ns.db
local XP = ns.XPRing
local xpRing = XP.xpRing
local ring = XP.ring
local NewRingLayer = XP.NewRingLayer
local DrawArc = XP.DrawArc
local anim = XP.anim

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

-- For the files loaded after this one.
XP.PlayLevelUpEffect = PlayLevelUpEffect
