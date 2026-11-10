-- Circlet: Spell school effects on the cast ring: embers for fire, snow for frost, and so on.
local ADDON_NAME, ns = ...

local db = ns.db

---------------------------------------------------------------------------
-- Which school a spell is
---------------------------------------------------------------------------
-- The game doesn't tell addons a spell's school (the combat log would, but this client
-- only lets Blizzard's own UI listen to it), so, in order:
--   1. a list of class spells (matched by name, so every rank counts);
--   2. the icon's file name, when the client gives a path (Spell_Fire_..., Spell_Frost_...).
-- A spell with no school found (or a physical one) gets no effect.

local KNOWN = {
    fire   = { 133, 2136, 2120, 11366, 2948, 348, 5676, 6353, 5740, 1949, 8050, 17877, 17962, 543, 1535, 8190 },
    frost  = { 116, 10, 120, 122, 8056, 168, 7302, 11426, 6143 },
    arcane = { 5143, 1449, 118, 2912, 8921, 1459, 130, 587, 5504, 12051, 1463, 2139, 475, 770, 3044 },
    shadow = { 686, 172, 689, 5782, 980, 8092, 589, 15407, 6789, 5138, 1120, 710, 5484, 755, 687, 706,
               1454, 6201, 702, 1714, 1490, 17862, 704, 18265, 5697, 605, 8122, 8129 },
    nature = { 403, 421, 331, 8004, 1064, 5176, 5185, 8936, 774, 339, 2637, 8042, 5570, 16914, 740, 324,
               370, 1978, 20484 },
    holy   = { 585, 2050, 2054, 2060, 2061, 596, 635, 19750, 879, 14914, 139, 17, 15237, 24275, 20473, 26573 },
}
local ICON_HINTS = { Fire = "fire", Frost = "frost", Arcane = "arcane", Shadow = "shadow", Nature = "nature", Holy = "holy" }

local knownByID, knownByName = {}, nil
for school, ids in pairs(KNOWN) do for _, id in ipairs(ids) do knownByID[id] = school end end

local function SpellSchool(spellID, name, icon)
    if spellID and knownByID[spellID] then return knownByID[spellID] end
    if name then
        if not knownByName then
            local names, any = {}, false
            for id, school in pairs(knownByID) do
                local n = ns.SpellName(id)
                if n then names[n], any = school, true end
            end
            if any then knownByName = names end -- try again later if no names could be read yet
            if names[name] then return names[name] end
        elseif knownByName[name] then
            return knownByName[name]
        end
    end
    if type(icon) == "string" then
        local hint = icon:match("[Ss]pell_(%a+)_")
        return hint and ICON_HINTS[hint] or nil
    end
end

---------------------------------------------------------------------------
-- The effects
---------------------------------------------------------------------------
-- Drawn in and around the ring, building up as the cast goes on and fading quickly when
-- it ends (spells don't burst): a glow fills the middle, an aura pulses round the ring's
-- band, and motes move in the school's way, spilling out past the ring. All worked out
-- from the time, so edit mode's sample plays them too. castSchoolFxStrength (%) scales
-- how bright it all is.
--   fire:   embers rise and flicker from yellow to red, up out of the ring.
--   frost:  snowflakes drift down through the ring, turning and twinkling.
--   arcane: motes orbit the middle both ways, inside and outside the ring, pulsing.
--   shadow: wisps spiral in from outside the ring toward a dark core.
--   nature: motes swirl outward from the middle, past the ring.
--   holy:   large rays turn behind motes rising up out of the ring.

local MOTES = 22
local END_FADE = { done = 0.4 } -- seconds to fade once the cast ends (others: 0.3)
local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR_TEX = "Interface\\Cooldown\\star4"
local TAU = 2 * math.pi

local HALO = {
    fire   = { r = 1.00, g = 0.45, b = 0.10 },
    frost  = { r = 0.45, g = 0.75, b = 1.00 },
    arcane = { r = 0.75, g = 0.40, b = 1.00 },
    shadow = { r = 0.55, g = 0.20, b = 0.85 },
    nature = { r = 0.35, g = 0.95, b = 0.35 },
    holy   = { r = 1.00, g = 0.85, b = 0.45 },
}
local SCHOOL_NAMES = { fire = "Fire", frost = "Frost", arcane = "Arcane", shadow = "Shadow", nature = "Nature", holy = "Holy" }

local function Mix(a, b, t) return a + (b - a) * t end

local fx -- textures and lines on the cast ring's frame, made on first use

local function Glow(frame, layer, sub, blend)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    if t:SetTexture(GLOW_TEX) == false then t:SetTexture(STAR_TEX) end
    t:SetBlendMode(blend or "ADD")
    t:SetPoint("CENTER", frame, "CENTER", 0, 0)
    t:Hide()
    return t
end

local function Build(frame)
    fx = { motes = {}, auraGeom = {} }
    fx.core = Glow(frame, "BACKGROUND", -6, "BLEND") -- shadow's dark heart
    fx.halo = Glow(frame, "BACKGROUND", -5)
    fx.rays = frame:CreateTexture(nil, "BACKGROUND", nil, -4) -- holy's turning rays
    fx.rays:SetTexture(STAR_TEX)
    fx.rays:SetBlendMode("ADD")
    fx.rays:SetPoint("CENTER", frame, "CENTER", 0, 0)
    fx.rays:Hide()
    -- Aura: a soft band of the school's color hugging the ring, pulsing.
    fx.aura = ns.NewRingLayer("BACKGROUND", -3, { r = 1, g = 1, b = 1 }, 1, frame)
    for _, l in ipairs(fx.aura) do
        if l.SetBlendMode then l:SetBlendMode("ADD") end
        l:Hide()
    end
    for i = 1, MOTES do
        local t = frame:CreateTexture(nil, "ARTWORK", nil, 3) -- over the ring's band, under its text
        t:SetTexture(STAR_TEX)
        t:SetBlendMode("ADD")
        t:Hide()
        -- Fixed per mote so they don't move in lockstep.
        fx.motes[i] = { tex = t, speed = 1 / (1.4 + (i * 0.37) % 0.9), phase = (i * 0.618) % 1,
                        side = ((i * 0.437) % 1) * 2 - 1, size = 0.7 + (i * 0.53) % 0.6,
                        orbit = 0.3 + (i * 0.371) % 1.15, dir = (i % 2 == 0) and 1 or -1 }
    end
end

local function HideAll()
    if not fx then return end
    fx.core:Hide(); fx.halo:Hide(); fx.rays:Hide()
    for _, l in ipairs(fx.aura) do l:Hide() end
    for _, m in ipairs(fx.motes) do m.tex:Hide() end
end

-- One mote for a school at time `now`, in a ring whose hollow has radius ri and outer
-- edge radius ro: x, y, size, alpha (before `lit`), r, g, b, rotation.
local MOTE = {
    fire = function(m, i, now, ri, ro)
        local u = (now * m.speed * 1.6 + m.phase) % 1
        local y = ri * -0.7 + (ro * 1.6 + ri * 0.7) * u -- up and out of the ring
        local spread = math.sqrt(math.max(0, 1 - (math.min(y, ri) / ri) ^ 2))
        local x = m.side * 0.6 * ri * spread + math.sin(now * 7 + i) * ri * 0.12 * u
        local r, g, b
        if u < 0.5 then r, g, b = 1, Mix(0.95, 0.55, u * 2), Mix(0.5, 0.1, u * 2)
        else r, g, b = 1, Mix(0.55, 0.2, (u - 0.5) * 2), Mix(0.1, 0.05, (u - 0.5) * 2) end
        return x, y, ri * 0.32 * m.size * (1 - 0.55 * u), math.min(1, u * 6) * (1 - u ^ 2), r, g, b, 0
    end,
    frost = function(m, i, now, ri, ro)
        local u = (now * m.speed * 0.5 + m.phase) % 1
        local y = ro * 1.3 - (ro * 1.3 + ri * 0.8) * u -- from above the ring down into it
        local x = m.side * ro * 0.85 + math.sin(u * TAU * 0.8 + i) * ri * 0.15
        local twinkle = 0.75 + 0.25 * math.sin(now * 6 + i * 1.7)
        return x, y, ri * 0.28 * m.size, math.sin(math.pi * u) * twinkle, 0.8, 0.94, 1, now * (0.6 + m.speed * 0.5) + i
    end,
    arcane = function(m, i, now, ri, ro)
        local a = m.phase * TAU + now * (0.7 + m.speed * 0.6) * m.dir
        local rad = ri * m.orbit -- some inside the ring, some round its outside
        local pulse = 0.7 + 0.3 * math.sin(now * 4 + i)
        local pink = i % 2 == 0
        return math.cos(a) * rad, math.sin(a) * rad, ri * 0.24 * m.size * pulse, 0.65 + 0.35 * math.sin(now * 3 + i),
            pink and 1 or 0.8, pink and 0.55 or 0.5, pink and 0.95 or 1, 0
    end,
    shadow = function(m, i, now, ri, ro)
        local u = (now * m.speed * 0.7 + m.phase) % 1
        local rad = ro * 1.5 * (1 - u) ^ 1.2 -- in from well outside the ring
        local a = m.phase * TAU + u * 2.6
        return math.cos(a) * rad, math.sin(a) * rad, ri * 0.3 * m.size * (1 - 0.5 * u),
            math.min(1, u * 4) * (1 - u ^ 3), 0.7, 0.35, 0.95, 0
    end,
    nature = function(m, i, now, ri, ro)
        local u = (now * m.speed * 0.6 + m.phase) % 1
        local rad = ri * 0.1 + ro * 1.4 * u -- out past the ring
        local a = m.phase * TAU + u * 3.2
        return math.cos(a) * rad, math.sin(a) * rad, ri * 0.27 * m.size * (0.5 + 0.5 * math.sin(math.pi * u)),
            math.sin(math.pi * u), Mix(0.6, 0.3, u), 1, Mix(0.45, 0.3, u), a
    end,
    holy = function(m, i, now, ri, ro)
        local u = (now * m.speed * 0.45 + m.phase) % 1
        local y = ri * -0.75 + (ro * 1.5 + ri * 0.75) * u -- up and out of the ring
        local spread = math.sqrt(math.max(0, 1 - (math.min(y, ri) / ri) ^ 2))
        local x = (m.side * 0.65 + math.sin(u * TAU + i) * 0.1) * ri * spread
        return x, y, ri * 0.25 * m.size, math.sin(math.pi * u), 1, 0.95, 0.7, 0
    end,
}

-- st.school: the school; st.schoolFrac: how far the cast is (nil if unknown);
-- st.schoolEnd / st.schoolAt: how and when it ended.
local function DrawSchoolFx(st, frame, geom)
    local school = st and st.school
    local mote = school and MOTE[school]
    if not mote or not geom or geom.R <= 0 then return HideAll() end
    if not fx then Build(frame) end
    local now = GetTime()
    local ri = math.max(4, geom.R - geom.T / 2) -- the hollow
    local ro = geom.R + geom.T / 2              -- the ring's outer edge
    local strength = (tonumber(db.castSchoolFxStrength) or 100) / 100

    local lit
    if st.schoolEnd then
        local age = math.max(0, now - (st.schoolAt or now))
        lit = math.max(0, 1 - age / (END_FADE[st.schoolEnd] or 0.3))
    else
        lit = 0.75 + 0.25 * (st.schoolFrac or 0.5)
    end
    if lit <= 0 then return HideAll() end
    local function A(a) return math.min(1, a * lit * strength) end

    local c = HALO[school]
    local breathe
    if school == "fire" then
        breathe = 0.85 + 0.075 * (math.sin(now * 11) + math.sin(now * 17.3)) -- flicker
    elseif school == "arcane" then
        breathe = 0.85 + 0.15 * math.sin(now * 2.2)
    else
        breathe = 0.9 + 0.1 * math.sin(now * 1.5)
    end
    -- Glow: fills the middle and spills a little past the ring.
    local hs = ro * 2.6 * breathe
    fx.halo:SetSize(hs, hs)
    fx.halo:SetVertexColor(c.r, c.g, c.b)
    fx.halo:SetAlpha(A(0.8))
    fx.halo:Show()

    -- Aura: hugs the ring's band, pulsing.
    local pulse = 0.65 + 0.35 * math.sin(now * (school == "fire" and 5 or 2.4))
    local g = fx.auraGeom
    g.R, g.T, g.start, g.sweep, g.step = geom.R, geom.T * 2.6, geom.start, geom.sweep, geom.step
    for _, l in ipairs(fx.aura) do l:SetColorTexture(c.r, c.g, c.b, A(0.4 * pulse)) end
    ns.DrawArc(fx.aura, 0, 1, frame, g, true)

    if school == "shadow" then
        local cs = ri * 1.5 * (0.95 + 0.05 * math.sin(now * 2))
        fx.core:SetSize(cs, cs)
        fx.core:SetVertexColor(0.08, 0.0, 0.12)
        fx.core:SetAlpha(A(0.8))
        fx.core:Show()
    else
        fx.core:Hide()
    end
    if school == "holy" then
        local rs = ro * 3.2
        fx.rays:SetSize(rs, rs)
        fx.rays:SetRotation(now * 0.35)
        fx.rays:SetVertexColor(1, 0.9, 0.6)
        fx.rays:SetAlpha(A(0.6))
        fx.rays:Show()
    else
        fx.rays:Hide()
    end

    for i, m in ipairs(fx.motes) do
        local x, y, size, a, r, gg, b, rot = mote(m, i, now, ri, ro)
        a = A(a)
        if a > 0.01 then
            m.tex:ClearAllPoints()
            m.tex:SetPoint("CENTER", frame, "CENTER", x, y)
            m.tex:SetSize(size, size)
            m.tex:SetVertexColor(r, gg, b)
            m.tex:SetRotation(rot or 0)
            m.tex:SetAlpha(a)
            m.tex:Show()
        else
            m.tex:Hide()
        end
    end
end

-- Shared with the files loaded after this one.
ns.SpellSchool = SpellSchool
ns.DrawSchoolFx = DrawSchoolFx
ns.SPELL_SCHOOL_NAMES = SCHOOL_NAMES
