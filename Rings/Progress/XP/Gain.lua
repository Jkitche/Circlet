-- Circlet: XP ring: the gain effect, a comet riding the end of the fill.
local _, ns = ...

local db = ns.db
local XP = ns.XPRing
local STATE_COLORS = XP.STATE_COLORS
local xpRing = XP.xpRing
local ring = XP.ring
local anim = XP.anim

-- Gain effect -------------------------------------------------------------------
-- With xpGainFx on, while a gain fills the ring a comet rides the end of the fill (a
-- glow with a turning star, in the fill's color), shedding sparkles that drift outward
-- and fade behind it. Where the fill lands, the glow flares once and fades.
local GAIN_SPARKLES = 20
local SPARKLE_EVERY, SPARKLE_LIFE = 0.035, 0.6
local LAND_TIME = 0.5

local gainFx = { sparkles = {}, next = 1, emitAt = 0, landAt = nil }
local function GainTex(layer, sub, glow)
    local t = xpRing:CreateTexture(nil, layer, nil, sub)
    if not glow or t:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64") == false then
        t:SetTexture("Interface\\Cooldown\\star4")
    end
    t:SetBlendMode("ADD")
    t:Hide()
    return t
end
gainFx.glow = GainTex("OVERLAY", 5, true)
gainFx.star = GainTex("OVERLAY", 6)
for i = 1, GAIN_SPARKLES do gainFx.sparkles[i] = { tex = GainTex("OVERLAY", 4) } end

local function Whiter(c, k) return c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k end

local function HideGainFx()
    gainFx.glow:Hide()
    gainFx.star:Hide()
    for _, s in ipairs(gainFx.sparkles) do s.tex:Hide(); s.born = nil end
    gainFx.landAt = nil
end

-- moving: the fill is animating a gain this frame. landed: it finished this frame.
local function DrawGainFx(now, moving, landed)
    if not db.xpGainFx or ring.R <= 0 then return HideGainFx() end
    local frac = anim.shown - math.floor(anim.shown + 1e-9)
    local c = xpRing.tipColor or STATE_COLORS.normal
    local x, y = ns.RingPoint(ring, frac)
    local T = math.max(3, ring.T)
    if landed then gainFx.landAt = now end

    -- The comet's head while it moves; a flare where it lands.
    local landAge = gainFx.landAt and now - gainFx.landAt
    if landAge and landAge >= LAND_TIME then gainFx.landAt, landAge = nil, nil end
    if moving or landAge then
        local k = moving and 1 or (1 - landAge / LAND_TIME)
        local swell = moving and 1 or (1 + 0.8 * math.sin(math.pi * math.min(1, landAge / LAND_TIME * 1.5)))
        local gs = T * 3.2 * swell
        gainFx.glow:ClearAllPoints()
        gainFx.glow:SetPoint("CENTER", xpRing, "CENTER", x, y)
        gainFx.glow:SetSize(gs, gs)
        gainFx.glow:SetVertexColor(c.r, c.g, c.b)
        gainFx.glow:SetAlpha(0.9 * k)
        gainFx.glow:Show()
        local ss = T * 1.9 * (moving and (0.9 + 0.1 * math.sin(now * 20)) or swell)
        gainFx.star:ClearAllPoints()
        gainFx.star:SetPoint("CENTER", xpRing, "CENTER", x, y)
        gainFx.star:SetSize(ss, ss)
        gainFx.star:SetVertexColor(Whiter(c, 0.7))
        gainFx.star:SetAlpha(k)
        if gainFx.star.SetRotation then gainFx.star:SetRotation(now * 3) end
        gainFx.star:Show()
    else
        gainFx.glow:Hide()
        gainFx.star:Hide()
    end

    -- Shed a sparkle every so often while moving, from just behind the head.
    if moving and now >= gainFx.emitAt then
        gainFx.emitAt = now + SPARKLE_EVERY
        local s = gainFx.sparkles[gainFx.next]
        gainFx.next = gainFx.next % GAIN_SPARKLES + 1
        local d = math.sqrt(x * x + y * y)
        local jitter = (math.random() - 0.5) * T * 0.6
        s.born, s.size = now, 0.6 + math.random() * 0.6
        s.ox, s.oy = (d > 0 and x / d or 0), (d > 0 and y / d or 1)
        s.x, s.y = x + s.ox * jitter, y + s.oy * jitter
        s.drift = T * (0.8 + math.random() * 1.4) * (math.random() < 0.5 and -1 or 1)
        s.r, s.g, s.b = Whiter(c, 0.4)
    end
    for _, s in ipairs(gainFx.sparkles) do
        local age = s.born and (now - s.born) / SPARKLE_LIFE
        if age and age < 1 then
            local e = 1 - (1 - age) ^ 2
            local size = T * 0.9 * s.size * (1 - 0.6 * age)
            s.tex:ClearAllPoints()
            s.tex:SetPoint("CENTER", xpRing, "CENTER", s.x + s.ox * s.drift * e, s.y + s.oy * s.drift * e)
            s.tex:SetSize(size, size)
            s.tex:SetVertexColor(s.r, s.g, s.b)
            s.tex:SetAlpha(1 - age)
            s.tex:Show()
        else
            s.born = nil
            s.tex:Hide()
        end
    end
end
ns.XPGainFxParts = function() return gainFx end -- for the tests

-- For the files loaded after this one.
XP.DrawGainFx = DrawGainFx
XP.gainFx = gainFx
