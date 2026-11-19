-- Circlet: Crafting effects: an animation of its own for each crafting profession, on the
-- crafting ring.
local ADDON_NAME, ns = ...

local db, SafeCall, Clean = ns.db, ns.SafeCall, ns.Clean

---------------------------------------------------------------------------
-- Which profession
---------------------------------------------------------------------------
-- When a batch starts, the profession is the trade skill window that's open: its name
-- (English, or this client's own name for the profession, from the profession's spell).
-- These are the crafting professions WoW Forever has (its SkillLine table: no Jewelcrafting or
-- Inscription).
local PROFESSIONS = {
    -- kind           English names                        the profession's spell (for its local name)
    { kind = "alchemy",        names = { "Alchemy" },                 spell = 2259 },
    { kind = "blacksmithing",  names = { "Blacksmithing" },           spell = 2018 },
    { kind = "enchanting",     names = { "Enchanting" },              spell = 7411 },
    { kind = "engineering",    names = { "Engineering" },             spell = 4036 },
    { kind = "leatherworking", names = { "Leatherworking" },          spell = 2108 },
    { kind = "tailoring",      names = { "Tailoring" },               spell = 3908 },
    { kind = "cooking",        names = { "Cooking" },                 spell = 2550 },
    { kind = "firstaid",       names = { "First Aid" },               spell = 3273 },
    { kind = "smelting",       names = { "Mining", "Smelting" },      spell = 2656 },
    { kind = "poisons",        names = { "Poisons" },                 spell = 2842 },
}

local byName
local function KindOf(name)
    name = Clean(name)
    if type(name) ~= "string" then return nil end
    if not byName then
        byName = {}
        for _, p in ipairs(PROFESSIONS) do
            for _, n in ipairs(p.names) do byName[n] = p.kind end
            local own = ns.SpellName and ns.SpellName(p.spell)
            if own then byName[own] = byName[own] or p.kind end
        end
    end
    return byName[name]
end

-- The profession of the trade skill window that's open now (nil if it can't be told).
-- craft: the batch came from the older Craft window (Enchanting on old clients).
local function OpenProfession(craft)
    local name
    if craft then
        name = GetCraftDisplaySkillLine and SafeCall(GetCraftDisplaySkillLine)
        if not name and GetCraftName then name = SafeCall(GetCraftName) end
    else
        local info = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and SafeCall(C_TradeSkillUI.GetBaseProfessionInfo)
        if type(info) == "table" then name = Clean(info.professionName) end
        if not name and GetTradeSkillLine then name = SafeCall(GetTradeSkillLine) end
    end
    return KindOf(name)
end

---------------------------------------------------------------------------
-- The effects
---------------------------------------------------------------------------
-- Worked out from the time alone, so edit mode's sample plays them too. The crafting
-- ring's state carries (Rings/Craft.lua):
--   st.craftFx: the profession (only while craftFx is on); st.fxStart: when the batch
--   started; st.fxMadeAt: when the last item was made (a pop at the end of the fill);
--   st.fxEndAt: when the batch ended, if it has; st.fxDone: it finished (a closing burst
--   in the profession's colors) rather than being stopped (the effect just fades).
--
--   alchemy:        bubbles rise through a potion glow that shifts from green to violet.
--   blacksmithing:  a hammer strikes the end of the fill, throwing sparks off hot metal.
--   engineering:    lightning crackles between the end of the fill and the middle.
--   enchanting:     runes orbit the middle, and a beam of arcane light plays on the fill.
--   tailoring:      a needle stitches along the fill, leaving neat stitches behind it.
--   leatherworking: the fill turns to tooled, studded leather, laced by a needle in wide waves.
--   cooking:        flames lick the bottom of the ring and steam rises from it.
--   firstaid:       a heartbeat glow in the middle, and crosses rising through it.
--   smelting:       molten metal glows in the hollow and embers rise off it.
--   poisons:        green drops gather and fall from the bottom of the ring.

local TAU = 2 * math.pi
local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR_TEX = "Interface\\Cooldown\\star4"
local DOT_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HAMMER_TEX = "Interface\\Cursor\\Crosshair\\Repair"
local HAMMER_FALLBACK = "Interface\\Cursor\\Repair"

local POP_TIME, BURST_TIME, FADE_TIME = 0.5, 1.2, 0.8

-- Each profession's colors: the main one and a second one for variety.
local PALETTE = {
    alchemy        = { { r = 0.35, g = 1.00, b = 0.45 }, { r = 0.75, g = 0.40, b = 1.00 } },
    blacksmithing  = { { r = 1.00, g = 0.60, b = 0.15 }, { r = 1.00, g = 0.90, b = 0.55 } },
    engineering    = { { r = 0.55, g = 0.85, b = 1.00 }, { r = 1.00, g = 0.85, b = 0.30 } },
    enchanting     = { { r = 0.75, g = 0.45, b = 1.00 }, { r = 1.00, g = 0.55, b = 0.95 } },
    tailoring      = { { r = 1.00, g = 0.95, b = 0.80 }, { r = 0.55, g = 0.75, b = 1.00 } },
    leatherworking = { { r = 0.70, g = 0.45, b = 0.22 }, { r = 0.90, g = 0.72, b = 0.35 } },
    cooking        = { { r = 1.00, g = 0.55, b = 0.15 }, { r = 1.00, g = 0.90, b = 0.40 } },
    firstaid       = { { r = 0.45, g = 1.00, b = 0.55 }, { r = 1.00, g = 1.00, b = 1.00 } },
    smelting       = { { r = 1.00, g = 0.45, b = 0.10 }, { r = 1.00, g = 0.85, b = 0.35 } },
    poisons        = { { r = 0.45, g = 1.00, b = 0.20 }, { r = 0.75, g = 1.00, b = 0.40 } },
}

local function Hash(n)
    local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)
end
local function Mix(a, b, t) return a + (b - a) * t end
local function Clamp(x) return math.max(0, math.min(1, x)) end

-- Pools of textures and lines on the crafting ring's frame, made on first use. Each frame
-- takes what it needs from the front of each pool and hides the rest.
local POOL_SIZES = { glow = 20, star = 48, dot = 80, puff = 12, line = 640, spark = 128 }
local fx, used

local function Build(frame)
    fx = { frame = frame }
    local function Tex(tex, blend, sub)
        local t = frame:CreateTexture(nil, "ARTWORK", nil, sub)
        if t:SetTexture(tex) == false then t:SetTexture(STAR_TEX) end -- a client without the glow art
        t:SetBlendMode(blend)
        t:Hide()
        return t
    end
    local function Line(add, sub)
        local l = frame:CreateLine(nil, "ARTWORK", nil, sub)
        if add and l.SetBlendMode then l:SetBlendMode("ADD") end
        if l.SetSnapToPixelGrid then l:SetSnapToPixelGrid(false); l:SetTexelSnappingBias(0) end
        l:Hide()
        return l
    end
    fx.glow, fx.star, fx.dot, fx.puff, fx.line, fx.spark = {}, {}, {}, {}, {}, {}
    for i = 1, POOL_SIZES.glow do fx.glow[i] = Tex(GLOW_TEX, "ADD", 2) end
    for i = 1, POOL_SIZES.puff do fx.puff[i] = Tex(GLOW_TEX, "BLEND", 3) end -- soft smoke and steam
    for i = 1, POOL_SIZES.star do fx.star[i] = Tex(STAR_TEX, "ADD", 6) end
    for i = 1, POOL_SIZES.dot do fx.dot[i] = Tex(DOT_TEX, "BLEND", 3) end
    for i = 1, POOL_SIZES.line do fx.line[i] = Line(false, 4) end
    for i = 1, POOL_SIZES.spark do fx.spark[i] = Line(true, 5) end
    fx.tool = frame:CreateTexture(nil, "ARTWORK", nil, 7)
    if fx.tool:SetTexture(HAMMER_TEX) == false then fx.tool:SetTexture(HAMMER_FALLBACK) end
    fx.tool:Hide()
end

local function Take(kind)
    local i = used[kind] + 1
    local item = fx[kind][i]
    if item then used[kind] = i end
    return item
end

-- A soft glow (ADD), a star (ADD, turned by rot), or a round dot (normal blending).
local function Put(kind, x, y, size, r, g, b, a, rot)
    if a <= 0.01 or size <= 0.5 then return end
    local t = Take(kind)
    if not t then return end
    t:ClearAllPoints()
    t:SetPoint("CENTER", fx.frame, "CENTER", x, y)
    t:SetSize(size, size)
    t:SetVertexColor(r, g, b)
    t:SetAlpha(Clamp(a))
    if t.SetRotation then t:SetRotation(rot or 0) end
    t:Show()
end
local function Glow(...) Put("glow", ...) end
local function Star(...) Put("star", ...) end
local function Dot(...) Put("dot", ...) end
local function Puff(...) Put("puff", ...) end

-- A line: "line" (normal) or "spark" (ADD, glowing).
local function Seg(kind, x1, y1, x2, y2, w, r, g, b, a)
    if a <= 0.01 then return end
    local l = Take(kind)
    if not l then return end
    l:SetStartPoint("CENTER", fx.frame, x1, y1)
    l:SetEndPoint("CENTER", fx.frame, x2, y2)
    l:SetThickness(math.max(1, w))
    l:SetColorTexture(r, g, b, Clamp(a))
    l:Show()
end

local function HideRest()
    for kind in pairs(POOL_SIZES) do
        local pool = fx[kind]
        for i = used[kind] + 1, #pool do pool[i]:Hide() end
    end
    if not used.tool then fx.tool:Hide() end
end

local function HideAll()
    if not fx then return end
    used = { glow = 0, star = 0, dot = 0, puff = 0, line = 0, spark = 0 }
    HideRest()
end

-- Everything a profession needs to draw one frame.
--   x, y: the end of the fill (on the ring's middle line); ox, oy: outward from the middle there
--   R, T, ri: ring radius, band width, inside radius; k: how strongly to draw (fades when it ends)
local function Context(st, geom, now)
    local frac = Clamp(st.frac or 0)
    local x, y = ns.RingPoint(geom, frac)
    local d = math.sqrt(x * x + y * y)
    return { now = now, t = now - (st.fxStart or now), frac = frac, x = x, y = y,
             ox = d > 0 and x / d or 0, oy = d > 0 and y / d or 1,
             R = geom.R, T = math.max(3, geom.T), ri = math.max(4, geom.R - geom.T / 2), geom = geom,
             k = 1, ended = st.fxEndAt ~= nil }
end

---------------------------------------------------------------------------
-- The professions
---------------------------------------------------------------------------
local DRAW = {}

-- Alchemy: bubbles rising through a potion glow that slowly shifts color.
function DRAW.alchemy(c, p)
    local shift = 0.5 + 0.5 * math.sin(c.now * 0.7)
    local r, g, b = Mix(p[1].r, p[2].r, shift), Mix(p[1].g, p[2].g, shift), Mix(p[1].b, p[2].b, shift)
    Glow(0, -c.ri * 0.35, c.ri * 1.7 * (0.95 + 0.05 * math.sin(c.now * 4)), r, g, b, 0.45 * c.k)
    for i = 1, 14 do
        local speed = 0.35 + Hash(i) * 0.35
        local u = (c.now * speed + Hash(i + 50)) % 1
        local bx = (Hash(i + 100) * 2 - 1) * c.ri * 0.6 + math.sin(c.now * 3 + i) * c.ri * 0.06
        local by = -c.ri * 0.8 + u * c.ri * 1.6
        local s = c.ri * (0.07 + 0.08 * Hash(i + 150)) * (0.7 + 0.5 * u)
        local a = math.min(1, u * 5) * (1 - u ^ 4) * c.k
        Dot(bx, by, s, Mix(r, 1, 0.3), Mix(g, 1, 0.3), Mix(b, 1, 0.3), 0.55 * a)
        Dot(bx - s * 0.22, by + s * 0.22, s * 0.3, 1, 1, 1, 0.8 * a) -- a glint on the bubble
    end
end

-- Blacksmithing: a hammer strikes the end of the fill; each blow flashes and throws sparks.
local BEAT = 0.7
function DRAW.blacksmithing(c, p)
    local h = p[1]
    -- The metal glows where it's being worked, fading between blows.
    local n = math.floor(c.now / BEAT)
    local since = c.now - n * BEAT -- time since the last blow
    Glow(c.x, c.y, c.T * 3.2 * (1 + 0.3 * math.max(0, 1 - since / 0.3)), h.r, h.g, h.b, (0.4 + 0.5 * math.max(0, 1 - since / 0.4)) * c.k)
    -- The hammer: raised, then brought down on the beat.
    local swing = since < 0.12 and (since / 0.12) or (since < 0.2 and 1 or 1 - (since - 0.2) / (BEAT - 0.2))
    swing = 1 - Clamp(swing) -- 0 = down on the metal, 1 = raised
    local size = math.max(16, c.R * 0.45)
    local out = c.T * 0.6 + size * 0.35 + swing * size * 0.25
    local side = -0.9 + swing * 0.9 -- swings round from beside the metal
    local hx, hy = c.x + c.ox * out - c.oy * size * 0.15, c.y + c.oy * out + c.ox * size * 0.15
    fx.tool:ClearAllPoints()
    fx.tool:SetPoint("CENTER", fx.frame, "CENTER", hx, hy)
    fx.tool:SetSize(size, size)
    local facing = math.atan2 and math.atan2(c.oy, c.ox) or math.atan(c.oy, c.ox)
    if fx.tool.SetRotation then fx.tool:SetRotation(facing - math.pi * 0.75 + side) end
    fx.tool:SetAlpha(c.k)
    fx.tool:Show()
    used.tool = true
    -- The blow: a flash and sparks flying off, falling.
    if since < 0.12 then Star(c.x, c.y, c.T * 3.5 * (1 - since / 0.12 * 0.5), 1, 0.95, 0.75, c.k, since * 5) end
    for j = 1, 2 do -- this blow's sparks and the last one's
        local blow = n - (j - 1)
        local age = c.now - blow * BEAT
        if age >= 0 and age < 0.6 then
            for i = 1, 7 do
                local seed = blow * 13 + i
                local ang = (Hash(seed) - 0.5) * 2.4
                local sp = c.R * (0.8 + Hash(seed + 7) * 1.2)
                local vx = (c.ox * math.cos(ang) - c.oy * math.sin(ang)) * sp
                local vy = (c.oy * math.cos(ang) + c.ox * math.sin(ang)) * sp
                local px, py = c.x + vx * age, c.y + vy * age - c.R * 1.6 * age * age
                local tx, ty = px - vx * 0.04, py - (vy - c.R * 3.2 * age) * 0.04
                Seg("spark", tx, ty, px, py, math.max(1, c.T * 0.18), h.r, Mix(h.g, 1, 0.4), Mix(h.b, 0.8, 0.3), (1 - age / 0.6) * c.k)
            end
        end
    end
end

-- Engineering: lightning arcs between the end of the fill and points in the middle, crackling.
local function Bolt(x1, y1, x2, y2, seed, w, r, g, b, a)
    local steps = 6
    local px, py = x1, y1
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    local nx, ny = -dy / math.max(len, 1), dx / math.max(len, 1)
    for s = 1, steps do
        local f = s / steps
        local off = s < steps and (Hash(seed + s) - 0.5) * len * 0.35 or 0
        local qx, qy = x1 + dx * f + nx * off, y1 + dy * f + ny * off
        Seg("spark", px, py, qx, qy, w, r, g, b, a)
        px, py = qx, qy
    end
end
function DRAW.engineering(c, p)
    local e = p[1]
    local tick = math.floor(c.now / 0.09) -- the arcs re-strike this often
    Glow(c.x, c.y, c.T * 3, e.r, e.g, e.b, 0.6 * c.k)
    Glow(0, 0, c.ri * 0.8, e.r, e.g, e.b, (0.15 + 0.1 * Hash(tick)) * c.k)
    for i = 1, 3 do
        local seed = tick * 7 + i * 31
        if Hash(seed) < 0.8 then
            local a = Hash(seed + 3) * TAU
            local r = c.ri * (0.1 + 0.5 * Hash(seed + 5))
            local tx, ty = math.sin(a) * r, math.cos(a) * r
            Bolt(c.x, c.y, tx, ty, seed, math.max(1, c.T * 0.22), Mix(e.r, 1, 0.5), Mix(e.g, 1, 0.5), 1, 0.9 * c.k)
            Star(tx, ty, c.T * 1.4, e.r, e.g, e.b, 0.8 * c.k, a)
        end
    end
    -- A few loose sparks jumping off the end of the fill.
    for i = 1, 4 do
        local seed = tick * 3 + i
        Star(c.x + (Hash(seed) - 0.5) * c.T * 2.5, c.y + (Hash(seed + 9) - 0.5) * c.T * 2.5, c.T * 0.8,
            p[2].r, p[2].g, p[2].b, Hash(seed + 4) * c.k)
    end
end

-- Enchanting: runes orbit the middle in two rings, a beam plays on the fill.
function DRAW.enchanting(c, p)
    local a1, a2 = p[1], p[2]
    local pulse = 0.8 + 0.2 * math.sin(c.now * 3)
    Glow(0, 0, c.ri * 1.4 * pulse, a1.r, a1.g, a1.b, 0.4 * c.k)
    for ring = 1, 2 do
        local n = ring == 1 and 6 or 9
        local rad = c.ri * (ring == 1 and 0.35 or 0.7)
        local spin = c.now * (ring == 1 and 1.4 or -0.9)
        local col = ring == 1 and a2 or a1
        for i = 1, n do
            local a = spin + i / n * TAU
            local tw = 0.6 + 0.4 * math.sin(c.now * 5 + i * 1.7 + ring)
            Star(math.sin(a) * rad, math.cos(a) * rad, c.ri * (ring == 1 and 0.22 or 0.18) * tw,
                Mix(col.r, 1, 0.3), Mix(col.g, 1, 0.3), Mix(col.b, 1, 0.3), tw * c.k, -spin * 2)
        end
    end
    -- The beam from the heart to the work, shimmering.
    local w = c.T * (0.35 + 0.15 * math.sin(c.now * 17))
    Seg("spark", 0, 0, c.x, c.y, w * 2, a1.r, a1.g, a1.b, 0.35 * c.k)
    Seg("spark", 0, 0, c.x, c.y, w * 0.7, 1, 0.9, 1, 0.7 * c.k)
    Glow(c.x, c.y, c.T * 3.5 * pulse, a2.r, a2.g, a2.b, 0.8 * c.k)
end

-- Stitches along the filled part of the ring, every `gap` of a turn, up to the fill.
local function Stitches(c, gap, draw)
    local n = math.floor(c.frac / gap)
    for i = 1, n do
        local f = (i - 0.5) * gap
        local x, y = ns.RingPoint(c.geom, f)
        local d = math.sqrt(x * x + y * y)
        draw(i, x, y, d > 0 and x / d or 0, d > 0 and y / d or 1)
    end
end

-- Tailoring: a needle dips in and out at the end of the fill, laying stitches behind it.
function DRAW.tailoring(c, p)
    local th = p[1]
    local L = c.T * 0.4 -- each stitch stays inside the band
    Stitches(c, 1 / 48, function(i, x, y, ox, oy)
        local tx, ty = oy, -ox -- along the ring
        local tilt = 0.45
        local ax, ay = ox * math.cos(tilt) + tx * math.sin(tilt), oy * math.cos(tilt) + ty * math.sin(tilt)
        Seg("line", x - ax * L, y - ay * L, x + ax * L, y + ay * L, math.max(1, c.T * 0.16), th.r, th.g, th.b, 0.9 * c.k)
    end)
    -- The needle: a bright glint bobbing through the band.
    local bob = math.sin(c.now * 9)
    local nx, ny = c.x + c.ox * bob * c.T * 0.8, c.y + c.oy * bob * c.T * 0.8
    Star(nx, ny, c.T * 1.8, 1, 1, 1, c.k, c.now * 2)
    -- Thread trailing from the needle, swaying.
    local sway = math.sin(c.now * 2.3) * c.T
    Seg("line", nx, ny, nx + c.ox * c.T * 3 - c.oy * sway, ny + c.oy * c.T * 3 + c.ox * sway,
        math.max(1, c.T * 0.12), p[2].r, p[2].g, p[2].b, 0.8 * c.k)
end

-- Leatherworking: the filled part of the band turns to tooled, studded leather. It takes a
-- leather-brown tint, worn and cracked, a carved scroll groove (dark, with a light edge) winds along
-- it, and brass studs sit in it every so often, each popping in as the fill reaches it. At
-- the end of the fill a needle laces a thread along it in wide, sweeping waves.
local HIDE  = { r = 0.45, g = 0.27, b = 0.13 }
local GROOVE = { r = 0.18, g = 0.10, b = 0.04 }
local BRASS = { r = 0.90, g = 0.72, b = 0.35 }
local LACE  = { r = 0.92, g = 0.82, b = 0.62 } -- waxed thread
local CRACK = { r = 0.12, g = 0.06, b = 0.02 } -- cracks in the worn leather
local WORN  = { r = 0.78, g = 0.58, b = 0.38 } -- the lighter, raised edge along a crack
local WEAVE = 0.55 -- seconds the needle takes over one stitch
local function Along(geom, f)
    local x, y = ns.RingPoint(geom, f)
    local d = math.sqrt(x * x + y * y)
    local ox, oy = d > 0 and x / d or 0, d > 0 and y / d or 1
    return x, y, ox, oy
end
function DRAW.leatherworking(c, p)
    local k, T = c.k, c.T
    -- The hide: a brown tint over the fill, in short pieces so it follows the ring's shape.
    local STEP = 1 / 48
    local n = math.floor(c.frac / STEP + 0.999)
    local px, py = Along(c.geom, 0)
    for i = 1, n do
        local f = math.min(c.frac, i * STEP)
        local x, y, ox, oy = Along(c.geom, f)
        Seg("line", px, py, x, y, T * 0.95, HIDE.r, HIDE.g, HIDE.b, 0.6 * k)
        -- Cracks: most pieces have one, a jagged line running across the band from near one
        -- edge, sometimes forking, with a lighter worn edge beside it.
        if Hash(i * 3.1) < 0.65 then
            local seglen = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
            local tx, ty = 0, 0
            if seglen > 0 then tx, ty = (x - px) / seglen, (y - py) / seglen end
            local mx, my = (px + x) / 2, (py + y) / 2
            local side = Hash(i * 5.7) < 0.5 and -1 or 1         -- which edge it starts from
            local reach = 0.55 + 0.4 * Hash(i * 2.3)            -- how far across it gets
            local w = math.max(1, T * 0.08)
            local function Pt(a, along) -- a: -0.5..0.5 across the band; along: shift along the ring
                return mx + ox * a * T * 0.9 + tx * along, my + oy * a * T * 0.9 + ty * along
            end
            local a0 = side * 0.48
            local ax, ay = Pt(a0, (Hash(i * 7.9) - 0.5) * seglen * 0.6)
            local forkX, forkY
            for s = 1, 3 do
                local a1 = side * (0.48 - reach * s / 3)
                local bx, by = Pt(a1, (Hash(i * 11.3 + s) - 0.5) * seglen * 0.7)
                Seg("line", ax + tx * w, ay + ty * w, bx + tx * w, by + ty * w, w, WORN.r, WORN.g, WORN.b, 0.35 * k)
                Seg("line", ax, ay, bx, by, w, CRACK.r, CRACK.g, CRACK.b, 0.9 * k)
                if s == 1 then forkX, forkY = bx, by end
                ax, ay = bx, by
            end
            if Hash(i * 13.7) < 0.4 then -- a fork off the first bend
                local ex, ey = Pt(side * (0.48 - reach * 0.6), (Hash(i * 17.1) < 0.5 and -1 or 1) * seglen * 0.55)
                Seg("line", forkX, forkY, ex, ey, math.max(1, w * 0.8), CRACK.r, CRACK.g, CRACK.b, 0.75 * k)
            end
        end
        px, py = x, y
    end
    -- The tooled scroll: a groove winding back and forth across the band, lit along one edge.
    local WSTEP = 1 / 96
    local wn = math.floor(c.frac / WSTEP)
    local lx, ly, hx, hy
    for i = 0, wn do
        local f = i * WSTEP
        local x, y, ox, oy = Along(c.geom, f)
        local wave = math.sin(f * TAU * 24) * T * 0.28
        local gx, gy = x + ox * wave, y + oy * wave
        local ex, ey = gx + ox * T * 0.08, gy + oy * T * 0.08
        if lx then
            Seg("line", lx, ly, gx, gy, math.max(1, T * 0.14), GROOVE.r, GROOVE.g, GROOVE.b, 0.85 * k)
            Seg("spark", hx, hy, ex, ey, math.max(1, T * 0.07), 1, 0.85, 0.6, 0.3 * k)
        end
        lx, ly, hx, hy = gx, gy, ex, ey
    end
    -- Brass studs, every 1/24 of the ring; the newest grows in as the fill reaches it.
    local SSTEP = 1 / 24
    for i = 1, math.floor(c.frac / SSTEP + 0.5) do
        local f = (i - 0.5) * SSTEP
        if f <= c.frac then
            local grow = Clamp((c.frac - f) / (SSTEP * 0.3))
            local x, y = Along(c.geom, f)
            local s = T * 0.62 * (grow < 1 and (0.6 + 0.6 * math.sin(math.pi * 0.5 * grow * 1.8)) or 1)
            Dot(x, y, s * 1.15, 0.12, 0.07, 0.03, 0.8 * k) -- its shadow in the leather
            Dot(x, y, s, BRASS.r, BRASS.g, BRASS.b, k)
            Dot(x - s * 0.18, y + s * 0.18, s * 0.35, 1, 0.95, 0.8, 0.85 * k) -- the shine
            if grow < 1 then Star(x, y, T * 2.2 * (1 - grow), 1, 0.95, 0.75, (1 - grow) * k, grow * 2) end
        end
    end
    -- The lacing: one thread winding along the leather in long, loose sweeps, out past the
    -- band's outer edge and in past its inner edge, the way a hand-laced thread lies: no two
    -- sweeps quite the same width or length, each a little lopsided. Where it crosses in front
    -- of the leather it's solid; where it passes behind, faint. It's laid up to the end of the
    -- fill, and the needle works just ahead of it on the same path, pushing on and drawing
    -- back a little with a short loose length of thread between, so it follows the lacing
    -- round as the fill grows.
    local GAP = 1 / 10       -- about one sweep (out and back in) per this much of the ring
    local AMP = T * 0.7      -- about how far it swings either side of the band's middle (just past its edges)
    local PIECES = 14        -- straight pieces per sweep
    local function Smooth(sw) -- a smooth wander in 0..1 along the sweeps (fixed per ring)
        local i = math.floor(sw)
        local t = sw - i
        t = t * t * (3 - 2 * t)
        return Mix(Hash(i * 1.37 + 5), Hash((i + 1) * 1.37 + 5), t)
    end
    local function Wave(f)   -- the point on the lacing at f, and whether it's in front (0..1)
        local sw = f / GAP
        -- Sweeps a little longer or shorter than each other, and lopsided (quicker going out
        -- than coming back in).
        local ph = TAU * (sw + 0.18 * (Smooth(sw * 0.6 + 11) - 0.5))
        ph = ph + 0.45 * math.sin(ph)
        local amp = AMP * (0.85 + 0.3 * Smooth(sw + 3))
        local x, y, ox, oy = Along(c.geom, math.max(0, f))
        local off = amp * (math.sin(ph) + 0.2 * math.sin(2 * ph + 0.8)) + T * 0.1 * (Smooth(sw * 0.5 + 7) - 0.5)
        return x + ox * off, y + oy * off, Clamp(0.5 + math.cos(ph) * 2)
    end
    local function Thread(f0, f1, a)
        local steps = math.max(1, math.ceil((f1 - f0) / GAP * PIECES))
        local x0, y0 = Wave(f0)
        for i = 1, steps do
            local f = f0 + (f1 - f0) * i / steps
            local x1, y1, front = Wave(f - (f1 - f0) / steps / 2)
            local x2, y2 = Wave(f)
            Seg("line", x0, y0, x2, y2, math.max(1, T * 0.2), LACE.r, LACE.g, LACE.b, (0.25 + 0.7 * front) * a)
            x0, y0 = x2, y2
        end
    end
    Thread(0, c.frac, k)
    -- The needle: just ahead of the fill, pushing on and drawing back (a stitch every WEAVE
    -- seconds), never more than a sixth of a sweep ahead.
    local u = (c.now % WEAVE) / WEAVE
    local push = u < 0.6 and (1 - math.cos(math.pi * u / 0.6)) / 2 -- pushing through
        or (1 + math.cos(math.pi * (u - 0.6) / 0.4)) / 2           -- drawing back
    local fade = k
    local fn = c.frac + GAP * (0.04 + 0.13 * push)
    Thread(c.frac, fn, 0.85 * fade) -- the loose length between the laid lacing and the needle
    local nx1, ny1, front = Wave(fn)
    local nx2, ny2 = Wave(fn + GAP * 0.02)
    local dx, dy = nx2 - nx1, ny2 - ny1
    local dl = math.sqrt(dx * dx + dy * dy)
    if dl < 1e-4 then dx, dy = -c.oy, c.ox else dx, dy = dx / dl, dy / dl end
    local na = (0.3 + 0.7 * front) * fade
    local NL = T * 2.4
    local tipx, tipy = nx1 + dx * NL * 0.6, ny1 + dy * NL * 0.6
    local eyex, eyey = nx1 - dx * NL * 0.4, ny1 - dy * NL * 0.4
    Seg("line", eyex, eyey, tipx, tipy, math.max(1, T * 0.22), 0.80, 0.82, 0.86, na)
    Seg("spark", eyex, eyey, tipx, tipy, math.max(1, T * 0.08), 1, 1, 1, 0.6 * na) -- the shine on it
    if front > 0.5 then Star(tipx, tipy, T * 1.2, 1, 1, 1, (front - 0.5) * 1.6 * fade, c.now * 3) end
end

-- Cooking: flames under the ring, steam rising off it.
function DRAW.cooking(c, p)
    local f1, f2 = p[1], p[2]
    for i = 1, 7 do
        local u = (i - 4) / 3.5
        local flick = 0.75 + 0.25 * math.sin(c.now * (9 + i) + i * 2.1)
        local fx_, fy = u * c.R * 0.7, -c.R - c.T * 0.4
        Glow(fx_, fy + c.T * flick, c.T * 3.2 * flick * (1 - math.abs(u) * 0.4), f1.r, f1.g * flick, f1.b, 0.75 * c.k)
        Star(fx_, fy + c.T * 1.6 * flick, c.T * 1.4 * flick, f2.r, f2.g, f2.b, 0.6 * flick * c.k, 0)
    end
    for i = 1, 9 do
        local speed = 0.3 + Hash(i) * 0.2
        local u = (c.now * speed + Hash(i + 20)) % 1
        local sx = (Hash(i + 40) * 2 - 1) * c.ri * 0.5 + math.sin(c.now * 1.7 + i * 2) * c.ri * 0.15 * u
        local sy = -c.ri * 0.4 + u * (c.ri * 0.4 + c.R * 1.3)
        Puff(sx, sy, c.ri * (0.5 + 0.8 * u), 0.95, 0.95, 0.95, 0.35 * math.min(1, u * 4) * (1 - u) * c.k)
    end
end

-- First aid: a heartbeat glow, and crosses rising through the middle.
local function Cross(x, y, s, r, g, b, a)
    Seg("spark", x - s, y, x + s, y, s * 0.6, r, g, b, a)
    Seg("spark", x, y - s, x, y + s, s * 0.6, r, g, b, a)
end
function DRAW.firstaid(c, p)
    local h = p[1]
    local beat = c.now % 1.1
    local thump = math.max(math.exp(-((beat - 0.0) / 0.08) ^ 2), 0.7 * math.exp(-((beat - 0.25) / 0.08) ^ 2))
    Glow(0, 0, c.ri * (1.3 + 0.4 * thump), h.r, h.g, h.b, (0.25 + 0.45 * thump) * c.k)
    for i = 1, 6 do
        local u = (c.now * 0.4 + i / 6) % 1
        local x = (Hash(i) * 2 - 1) * c.ri * 0.55 + math.sin(c.now * 2 + i) * c.ri * 0.05
        local y = -c.ri * 0.7 + u * c.ri * 1.5
        Cross(x, y, c.ri * 0.09 * (0.8 + 0.4 * Hash(i + 3)), Mix(h.r, 1, 0.4), 1, Mix(h.b, 1, 0.4), math.min(1, u * 5) * (1 - u) * c.k)
    end
    Glow(c.x, c.y, c.T * 2.6, 1, 1, 1, (0.3 + 0.4 * thump) * c.k)
end

-- Smelting: molten metal glowing in the hollow, embers rising off it.
function DRAW.smelting(c, p)
    local m1, m2 = p[1], p[2]
    local heat = 0.85 + 0.15 * math.sin(c.now * 5.3) * math.sin(c.now * 3.1)
    Glow(0, -c.ri * 0.3, c.ri * 1.8 * heat, m1.r, m1.g, m1.b, 0.6 * c.k)
    Glow(0, -c.ri * 0.4, c.ri * 0.9 * heat, m2.r, m2.g, m2.b, 0.6 * c.k)
    for i = 1, 14 do
        local speed = 0.45 + Hash(i) * 0.4
        local u = (c.now * speed + Hash(i + 9)) % 1
        local x = (Hash(i + 30) * 2 - 1) * c.ri * 0.6 + math.sin(c.now * 4 + i) * c.ri * 0.06
        local y = -c.ri * 0.5 + u * (c.ri * 0.5 + c.R * 1.1)
        Star(x, y, c.T * 1.1 * (1 - 0.5 * u), m2.r, Mix(m2.g, m1.g, u), Mix(m2.b, m1.b, u), math.min(1, u * 6) * (1 - u) * c.k, u * 3)
    end
end

-- Poisons: green drops gathering on the bottom of the ring and falling.
function DRAW.poisons(c, p)
    local v = p[1]
    Glow(0, -c.ri * 0.2, c.ri * 1.3, v.r, v.g, v.b, 0.3 * c.k)
    for i = 1, 8 do
        local period = 1.1 + Hash(i) * 0.6
        local u = ((c.now + Hash(i + 4) * period) % period) / period
        local x = (Hash(i + 11) * 2 - 1) * c.R * 0.6
        local top = -math.sqrt(math.max(0, c.R * c.R - x * x)) -- the ring's underside here
        local y, s = top, c.T * 0.9
        if u < 0.5 then
            s = c.T * (0.4 + 1.0 * u) -- swelling on the ring
        else
            y = top - (u - 0.5) ^ 2 * 4 * c.R * 1.2 -- falling
        end
        Dot(x, y, s, v.r, v.g, v.b, 0.85 * (u < 0.9 and 1 or (1 - u) / 0.1) * c.k)
        Dot(x - s * 0.2, y + s * 0.2, s * 0.35, 1, 1, 1, 0.7 * c.k)
    end
end

-- Anything else: soft sparkles round the end of the fill.
function DRAW.generic(c)
    local col = db.craftColors and db.craftColors.fill or { r = 1, g = 0.8, b = 0.4 }
    Glow(c.x, c.y, c.T * 3, col.r, col.g, col.b, 0.6 * c.k)
    for i = 1, 6 do
        local u = (c.now * 0.8 + i / 6) % 1
        local a = i / 6 * TAU + c.now
        Star(c.x + math.sin(a) * c.T * 2 * u, c.y + math.cos(a) * c.T * 2 * u, c.T * (1 - u), 1, 0.95, 0.8, (1 - u) * c.k, a)
    end
end

-- Each item made: a little pop at the end of the fill, in the profession's colors.
local function MadePop(c, p, age)
    local t = age / POP_TIME
    Glow(c.x, c.y, c.T * (3 + 4 * t), p[1].r, p[1].g, p[1].b, 0.9 * (1 - t))
    for i = 1, 6 do
        local a = i / 6 * TAU + 0.4
        local d = c.T * (1 + 3.5 * (1 - (1 - t) ^ 2))
        local col = p[(i % 2) + 1]
        Star(c.x + math.sin(a) * d, c.y + math.cos(a) * d, c.T * 1.2 * (1 - 0.5 * t), Mix(col.r, 1, 0.3), Mix(col.g, 1, 0.3), Mix(col.b, 1, 0.3), 1 - t, a)
    end
end

-- The batch finished: a burst all round the ring in the profession's colors.
local function DoneBurst(c, p, age)
    local t = age / BURST_TIME
    Glow(0, 0, c.R * (1.6 + 1.2 * t), p[1].r, p[1].g, p[1].b, 0.4 * (1 - t))
    for i = 1, 18 do
        local f = i / 18
        local x, y = ns.RingPoint(c.geom, f)
        local d = math.sqrt(x * x + y * y)
        local ox, oy = d > 0 and x / d or 0, d > 0 and y / d or 1
        local out = c.R * 0.8 * (1 - (1 - t) ^ 2) * (0.7 + 0.6 * Hash(i))
        local col = p[(i % 2) + 1]
        Star(x + ox * out, y + oy * out, c.T * 1.8 * (1 - 0.6 * t), Mix(col.r, 1, 0.3), Mix(col.g, 1, 0.3), Mix(col.b, 1, 0.3), 1 - t, t * 4 + i)
    end
end

local function DrawCraftFx(st, frame, geom)
    local kind = st and st.craftFx
    if not kind or not geom or geom.R <= 0 then return HideAll() end
    if not fx then Build(frame) end
    used = { glow = 0, star = 0, dot = 0, puff = 0, line = 0, spark = 0 }
    local now = GetTime()
    local c = Context(st, geom, now)
    local p = PALETTE[kind] or { { r = 1, g = 0.8, b = 0.4 }, { r = 1, g = 1, b = 0.8 } }
    if st.fxEndAt then c.k = 1 - Clamp((now - st.fxEndAt) / FADE_TIME) end
    if c.k > 0 then (DRAW[kind] or DRAW.generic)(c, p) end
    if st.fxMadeAt and now - st.fxMadeAt < POP_TIME and now >= st.fxMadeAt then MadePop(c, p, now - st.fxMadeAt) end
    if st.fxDone and st.fxEndAt and now - st.fxEndAt < BURST_TIME and now >= st.fxEndAt then DoneBurst(c, p, now - st.fxEndAt) end
    HideRest()
    used.tool = nil
end

---------------------------------------------------------------------------
-- Shared with the files loaded after this one.
---------------------------------------------------------------------------
ns.CraftProfession = OpenProfession
ns.CraftKindOf = KindOf
ns.DrawCraftFx = DrawCraftFx
ns.CraftFxParts = function() return fx end -- for the tests
-- For the options' preview and edit mode's sample: each profession with a recipe to show.
ns.CRAFT_FX_SAMPLES = {
    { kind = "alchemy",        name = "Alchemy",        recipe = "Lesser Healing Potion", icon = "Interface\\Icons\\INV_Potion_51" },
    { kind = "blacksmithing",  name = "Blacksmithing",  recipe = "Copper Chain Belt",     icon = "Interface\\Icons\\INV_Belt_03" },
    { kind = "engineering",    name = "Engineering",    recipe = "Rough Boomstick",       icon = "Interface\\Icons\\INV_Weapon_Rifle_04" },
    { kind = "enchanting",     name = "Enchanting",     recipe = "Runed Copper Rod",      icon = "Interface\\Icons\\INV_Staff_Goldfeathered_01" },
    { kind = "tailoring",      name = "Tailoring",      recipe = "Bolt of Linen Cloth",   icon = "Interface\\Icons\\INV_Fabric_Linen_02" },
    { kind = "leatherworking", name = "Leatherworking", recipe = "Light Armor Kit",       icon = "Interface\\Icons\\INV_Misc_ArmorKit_17" },
    { kind = "cooking",        name = "Cooking",        recipe = "Roasted Boar Meat",     icon = "Interface\\Icons\\INV_Misc_Food_14" },
    { kind = "firstaid",       name = "First Aid",      recipe = "Heavy Linen Bandage",   icon = "Interface\\Icons\\INV_Misc_Bandage_18" },
    { kind = "smelting",       name = "Smelting",       recipe = "Smelt Copper",          icon = "Interface\\Icons\\INV_Ingot_02" },
    { kind = "poisons",        name = "Poisons",        recipe = "Instant Poison",        icon = "Interface\\Icons\\Ability_Poisons" },
}
