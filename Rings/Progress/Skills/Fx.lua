-- Circlet: Skill rings: the animations on the profession and weapon skill rings.
local _, ns = ...

local db = ns.db
local SK = ns.SkillRings

---------------------------------------------------------------------------
-- The animations
---------------------------------------------------------------------------
-- With skillFx / weaponFx on (worked out from the time, so edit mode's samples play them):
--   skill:  a spark rides the end of the fill as it rises, shedding glitter in the
--           profession's colors (the crafting animations' palettes; gathering ones of their
--           own); when it lands it bursts and motes float up. A new tier or the cap also sends
--           a gold shimmer round the whole ring.
--   weapon: a steel swoosh slices across the end of the fill as it rises; when it lands, a
--           clang (a white flash) and a spray of steel sparks. Capped, a blade glint sweeps
--           round the ring.
local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR_TEX = "Interface\\Cooldown\\star4"
local TAU = 2 * math.pi
local LAND_TIME, SHIMMER_TIME = 0.9, 1.2
local GOLD = { r = 1, g = 0.85, b = 0.35 }
local STEEL = { r = 0.85, g = 0.9, b = 1 }
local GATHER_PALETTE = {
    Herbalism = { { r = 0.40, g = 0.95, b = 0.35 }, { r = 1.00, g = 0.85, b = 0.40 } },
    Skinning = { { r = 0.85, g = 0.62, b = 0.40 }, { r = 1.00, g = 0.90, b = 0.70 } },
    Fishing = { { r = 0.35, g = 0.70, b = 1.00 }, { r = 0.80, g = 0.95, b = 1.00 } },
}

local function Hash(n)
    local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)
end
local function Whiter(c, k) return c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k end

local function SkillPalette(e, fill)
    local p = GATHER_PALETTE[e.name]
    if not p and ns.CraftKindOf and ns.CraftPalette then p = ns.CraftPalette(ns.CraftKindOf(e.name)) end
    return p or { fill, GOLD }
end

-- Pools of glows, stars and lines on a ring's frame; each frame takes from the front.
local pools = {}
local function Pools(frame)
    local p = pools[frame]
    if p then return p end
    p = { glow = {}, star = {}, line = {}, used = {} }
    local function Tex(tex, sub)
        local t = frame:CreateTexture(nil, "OVERLAY", nil, sub)
        if t:SetTexture(tex) == false then t:SetTexture(STAR_TEX) end
        t:SetBlendMode("ADD")
        t:Hide()
        return t
    end
    for i = 1, 6 do
        p.glow[i] = Tex(GLOW_TEX, 4)
    end
    for i = 1, 40 do
        p.star[i] = Tex(STAR_TEX, 6)
    end
    for i = 1, 48 do
        local l = frame:CreateLine(nil, "OVERLAY", nil, 5)
        if l.SetBlendMode then l:SetBlendMode("ADD") end
        l:Hide()
        p.line[i] = l
    end
    pools[frame] = p
    return p
end
local function Take(p, kind)
    local i = (p.used[kind] or 0) + 1
    local item = p[kind][i]
    if item then p.used[kind] = i end
    return item
end
local function Put(p, frame, kind, x, y, size, r, g, b, a, rot)
    if a <= 0.01 or size <= 0.5 then return end
    local t = Take(p, kind)
    if not t then return end
    t:ClearAllPoints()
    t:SetPoint("CENTER", frame, "CENTER", x, y)
    t:SetSize(size, size)
    t:SetVertexColor(r, g, b)
    t:SetAlpha(math.min(1, a))
    if t.SetRotation then t:SetRotation(rot or 0) end
    t:Show()
end
local function PutW(p, frame, kind, x, y, size, c, k, a, rot) -- c whitened by k
    local r, g, b = Whiter(c, k)
    Put(p, frame, kind, x, y, size, r, g, b, a, rot)
end
local function Seg(p, frame, x1, y1, x2, y2, w, r, g, b, a)
    if a <= 0.01 then return end
    local l = Take(p, "line")
    if not l then return end
    l:SetStartPoint("CENTER", frame, x1, y1)
    l:SetEndPoint("CENTER", frame, x2, y2)
    l:SetThickness(math.max(1, w))
    l:SetColorTexture(r, g, b, math.min(1, a))
    l:Show()
end
local function Finish(p)
    for _, kind in ipairs({ "glow", "star", "line" }) do
        for i = (p.used[kind] or 0) + 1, #p[kind] do
            p[kind][i]:Hide()
        end
        p.used[kind] = 0
    end
end

-- The end of the fill and the way out from the middle there.
local function Tip(geom, frac)
    local x, y = ns.RingPoint(geom, frac)
    local d = math.sqrt(x * x + y * y)
    return x, y, d > 0 and x / d or 0, d > 0 and y / d or 1
end

-- A gold shimmer running once round the whole ring (new tier, or capped).
local function Shimmer(p, frame, geom, age, c)
    local t = age / SHIMMER_TIME
    if t >= 1 then return end
    local head = t * 1.15
    for i = 0, 10 do
        local f = head - i * 0.02
        if f >= 0 and f <= 1 then
            local x, y = ns.RingPoint(geom, f)
            PutW(p, frame, "star", x, y, geom.T * (2.2 - i * 0.15), c, 0.5, (1 - i / 11) * (1 - t * 0.5), f * 6)
        end
    end
end

local function DrawSkillFx(e, frame, geom, shown, moving, fill)
    local p = Pools(frame)
    if not db.skillFx or geom.R <= 0 then return Finish(p) end
    local now, T = GetTime(), math.max(3, geom.T)
    local pal = SkillPalette(e, fill)
    local c1, c2 = pal[1], pal[2]
    local x, y, ox, oy = Tip(geom, shown % 1 == 0 and shown > 0 and 0.9999 or shown % 1)
    local landAge = e.landedAt and now - e.landedAt
    if moving then
        -- The spark at the end of the fill, and glitter falling off behind it.
        Put(p, frame, "glow", x, y, T * 3.2 * (0.9 + 0.1 * math.sin(now * 14)), c1.r, c1.g, c1.b, 0.85)
        PutW(p, frame, "star", x, y, T * 2, c2, 0.6, 1, now * 4)
        for i = 1, 10 do
            local u = (now * 2.2 + i / 10) % 1
            local a = Hash(math.floor(now * 2.2 + i / 10) * 7 + i) * TAU
            local d = T * (0.4 + 2.6 * u)
            local col = (i % 2 == 0) and c1 or c2
            PutW(
                p,
                frame,
                "star",
                x + math.cos(a) * d,
                y + math.sin(a) * d - T * 1.5 * u * u,
                T * 0.9 * (1 - u),
                col,
                0.3,
                1 - u,
                a
            )
        end
    elseif landAge and landAge < LAND_TIME then
        -- Landed: a burst from the end of the fill, and motes floating up.
        local t = landAge / LAND_TIME
        Put(p, frame, "glow", x, y, T * (3 + 5 * t), c1.r, c1.g, c1.b, 0.9 * (1 - t))
        for i = 1, 10 do
            local a = i / 10 * TAU + 0.3
            local d = T * (0.5 + 4 * (1 - (1 - t) ^ 2))
            local col = (i % 2 == 0) and c1 or c2
            PutW(
                p,
                frame,
                "star",
                x + math.cos(a) * d,
                y + math.sin(a) * d,
                T * 1.4 * (1 - 0.6 * t),
                col,
                0.3,
                1 - t,
                a + t * 3
            )
        end
        for i = 1, 5 do
            local u = math.min(1, t * 1.2)
            Put(
                p,
                frame,
                "glow",
                x + (Hash(i) - 0.5) * T * 3,
                y + T * (1 + 5 * u) * (0.6 + Hash(i + 3) * 0.6),
                T * 1.1,
                c2.r,
                c2.g,
                c2.b,
                (1 - u) * 0.9
            )
        end
    end
    local big = e.change == "tier" or (e.to >= e.max)
    if big and landAge and landAge < SHIMMER_TIME then Shimmer(p, frame, geom, landAge, GOLD) end
    Finish(p)
end

-- A swoosh: a thick-to-thin crescent of steel, sweeping across the ring at the end of the fill.
local SWING = 0.55 -- seconds per swing while the fill rises
local function DrawWeaponFx(e, frame, geom, shown, moving, fill)
    local p = Pools(frame)
    if not db.weaponFx or geom.R <= 0 then return Finish(p) end
    local now, T, R = GetTime(), math.max(3, geom.T), geom.R
    local x, y, ox, oy = Tip(geom, shown % 1 == 0 and shown > 0 and 0.9999 or shown % 1)
    local tx, ty = oy, -ox -- along the ring
    local landAge = e.landedAt and now - e.landedAt
    if moving then
        local u = (now % SWING) / SWING
        local sweep = u < 0.45 and u / 0.45 or 1 -- the cut, then the trail fading
        local fade = u < 0.45 and 1 or 1 - (u - 0.45) / 0.55
        local L = T * 4 -- the reach of the cut
        -- The blade path: an arc through the end of the fill, from out-and-behind to in-and-ahead.
        local function Path(s)
            local a = (s - 0.5) * 2.2
            local px = x + ox * math.cos(a) * L * 0.5 + tx * math.sin(a) * L * 0.6
            local py = y + oy * math.cos(a) * L * 0.5 + ty * math.sin(a) * L * 0.6
            return px - ox * L * 0.25, py - oy * L * 0.25
        end
        local steps = 10
        local px, py = Path(math.max(0, sweep - 0.5))
        for i = 1, steps do
            local s = math.max(0, sweep - 0.5) + (sweep - math.max(0, sweep - 0.5)) * i / steps
            local qx, qy = Path(s)
            local k = i / steps -- thicker and brighter toward the blade's edge
            Seg(p, frame, px, py, qx, qy, T * (0.15 + 0.6 * k), STEEL.r, STEEL.g, STEEL.b, 0.85 * k * fade)
            px, py = qx, qy
        end
        if u < 0.45 then Put(p, frame, "star", px, py, T * 1.6, 1, 1, 1, 1, now * 5) end -- the blade's tip
        Put(p, frame, "glow", x, y, T * 2.6, fill.r, fill.g, fill.b, 0.5)
    elseif landAge and landAge < LAND_TIME then
        -- The clang: a white flash and steel sparks spraying out.
        local t = landAge / LAND_TIME
        Put(p, frame, "glow", x, y, T * (2.5 + 4 * t), 1, 1, 1, 0.9 * (1 - t) ^ 2)
        if t < 0.25 then Put(p, frame, "star", x, y, T * 4 * (1 - t * 2), 1, 1, 1, 1 - t * 4, 0.785) end
        for i = 1, 9 do
            local a = (Hash(i + (e.landedAt or 0)) - 0.5) * 2.6
            local dx, dy = ox * math.cos(a) - tx * math.sin(a), oy * math.cos(a) - ty * math.sin(a)
            local sp = R * (1 + Hash(i + 5) * 1.4)
            local age = landAge
            local sx, sy = x + dx * sp * age, y + dy * sp * age - R * 1.2 * age * age
            local vx, vy = dx * sp, dy * sp - R * 2.4 * age
            local len = 0.035
            Seg(p, frame, sx - vx * len, sy - vy * len, sx, sy, math.max(1, T * 0.18), 1, 0.95, 0.8, 1 - t)
        end
    end
    if e.to >= e.max and landAge and landAge < SHIMMER_TIME then Shimmer(p, frame, geom, landAge, STEEL) end
    Finish(p)
end

ns.SkillFxPools = function() return pools end -- for the tests: frame -> its effect pieces

-- For the files loaded after this one.
SK.DrawSkillFx = DrawSkillFx
SK.DrawWeaponFx = DrawWeaponFx
