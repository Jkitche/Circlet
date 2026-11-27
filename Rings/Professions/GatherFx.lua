-- Circlet: Gathering effects: an animation of its own for each gathering profession, on the
-- gathering ring.
local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- The effects
---------------------------------------------------------------------------
-- Worked out from the time alone (nothing kept between frames), so edit mode's sample plays
-- them too. The tools work at one spot, the ring's top right, whatever the progress; only the
-- closing flourishes go round the whole ring. The gathering ring's state carries:
--   st.gatherFx: the profession (only set while gatherFx is on and it has an effect);
--   st.fxStart: when the gather started (the tools' rhythm); st.fxEndAt: when it ended, if it
--     has; st.fxDone: it finished (rather than being interrupted), which plays the closing
--     flourish.
--
--   skinning: a knife slashes along the ring in quick strokes, each flicking off a few
--             tufts of fur that tumble down and fade. When it's done one last cut runs round
--             the whole ring and fur sprays off all of it.
--   mining:   a pickaxe swings at the ring: it winds up, strikes with a flash and a crack
--             of light, and throws sparks and chips of rock that fall away. When the vein
--             breaks a last heavy strike flashes the whole ring and rock and sparks burst off
--             all round.
--   herb:     pruning shears snip at the ring, each snip sending leaves and petals
--             fluttering down. The last snip sends a gust of them off the whole ring.
-- The tools are the game's own cursor art (the crosshair cursors, which have no pointer arrow
-- painted on), turned about where they're held.

local TAU = 2 * math.pi
local STAR_TEX = "Interface\\Cooldown\\star4"

-- The tools: the game's cursor art (32x32). Points are fractions of the image, measured from
-- its top left: where it's held and the end that does the work.
local TOOLS = {
    knife = {
        tex = "Interface\\Cursor\\Crosshair\\Attack",
        fallback = "Interface\\Cursor\\Attack",
        grip = { 0.78, 0.78 },
        tip = { 0.03, 0.03 },
    },
    pick = {
        tex = "Interface\\Cursor\\Crosshair\\Mine",
        fallback = "Interface\\Cursor\\Mine",
        grip = { 0.77, 0.875 },
        tip = { 0.92, 0.06 },
    },
    -- Gold pruning shears (a crosshair cursor known only by its file ID): jaws at the top left.
    shears = {
        tex = 4675625,
        fallback = "Interface\\Cursor\\GatherHerbs",
        grip = { 0.75, 0.75 },
        tip = { 0.19, 0.19 },
    },
}

-- A point of the image, from its middle, in screen units (y up) for an image `size` across.
local function FromMiddle(pt, size) return (pt[1] - 0.5) * size, (0.5 - pt[2]) * size end
local function Turn(x, y, a)
    local c, s = math.cos(a), math.sin(a)
    return x * c - y * s, x * s + y * c
end
local function Angle(x, y) return math.atan2 and math.atan2(y, x) or math.atan(y, x) end

-- A repeatable "random" number in [0, 1) for n: the same n always gives the same number.
local function Hash(n)
    local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)
end

local BITS = 96 -- lines for solid bits (fur: two per tuft; rock chips: one each)
local SPARKS = 64 -- glowing lines (sparks)

local fx -- lines and textures on the gathering ring's frame, made on first use
local used -- this frame: how many bits and sparks are drawn, and whether the cut and glint are

local function Build(frame)
    fx = { bits = {}, sparks = {}, cutGeom = {} }
    -- The cut / crack: a thin bright arc over the fill (ARTWORK 0) and its flash (1).
    fx.cut = ns.NewRingLayer("ARTWORK", 2, { r = 1, g = 1, b = 1 }, 1, frame)
    for _, l in ipairs(fx.cut) do
        if l.SetBlendMode then l:SetBlendMode("ADD") end
        l:Hide()
    end
    -- The tool (knife or pickaxe), over the fur and rock (3), under the sparks (5).
    fx.tool = frame:CreateTexture(nil, "ARTWORK", nil, 4)
    fx.tool:Hide()
    fx.glint = frame:CreateTexture(nil, "ARTWORK", nil, 6) -- a pick's strike
    fx.glint:SetTexture(STAR_TEX)
    fx.glint:SetBlendMode("ADD")
    fx.glint:Hide()
    for i = 1, BITS do
        local l = frame:CreateLine(nil, "ARTWORK", nil, 3)
        l:Hide()
        fx.bits[i] = l
    end
    for i = 1, SPARKS do
        local l = frame:CreateLine(nil, "ARTWORK", nil, 5)
        if l.SetBlendMode then l:SetBlendMode("ADD") end
        l:Hide()
        fx.sparks[i] = l
    end
end

local function HideAll()
    if not fx then return end
    for _, l in ipairs(fx.cut) do
        l:Hide()
    end
    fx.glint:Hide()
    fx.tool:Hide()
    for _, l in ipairs(fx.bits) do
        l:Hide()
    end
    for _, l in ipairs(fx.sparks) do
        l:Hide()
    end
end

-- Where the tools work: the ring's top right. Places round the ring here are fractions of
-- a full turn, clockwise from 12 o'clock, whatever the ring's shape and rotation.
local SPOT = 0.125

-- The point at fraction f round the ring's middle line, the way out from the middle there,
-- and the way along it (clockwise).
local function Frame3(geom, f)
    local ang = math.pi / 2 - TAU * f
    local ox, oy = math.cos(ang), math.sin(ang)
    return geom.R * ox, geom.R * oy, ox, oy, oy, -ox
end

-- One line of a pool, from (x1, y1) to (x2, y2).
local function Put(pool, count, frame, x1, y1, x2, y2, w, r, g, b, a)
    local i = used[count] + 1
    local l = pool[i]
    if not l then return end
    used[count] = i
    l:SetStartPoint("CENTER", frame, x1, y1)
    l:SetEndPoint("CENTER", frame, x2, y2)
    l:SetThickness(w)
    l:SetColorTexture(r, g, b, a)
    l:Show()
end

-- A thrown bit's place at `age`: thrown from ring fraction f with speeds out (from the
-- middle), along (the ring) and up, falling under `fall`. Also its velocity.
local function Thrown(geom, f, age, out, along, up, fall)
    local x, y, ox, oy, tx, ty = Frame3(geom, f)
    local vx, vy = ox * out + tx * along, oy * out + ty * along + up
    return x + vx * age, y + vy * age + 0.5 * fall * age * age, vx, vy + fall * age
end

-- The cut: a bright arc [from, to], thinner than the band. Fractions of a full turn from
-- 12 o'clock, or with onRing, of the ring itself (its shape and rotation: the flourishes).
local function Cut(frame, geom, from, to, a, r, g, b, onRing)
    from, to = math.max(0, from), math.min(1, to)
    if to <= from then return end
    local cg = fx.cutGeom
    cg.R, cg.T, cg.step = geom.R, math.max(1.5, geom.T * 0.35), geom.step
    if onRing then
        cg.start, cg.sweep, cg.reverse = geom.start, geom.sweep, geom.reverse
    else
        cg.start, cg.sweep, cg.reverse = 0, 1, nil
    end
    for _, l in ipairs(fx.cut) do
        l:SetColorTexture(r or 0.85, g or 0.92, b or 1, a)
    end
    ns.DrawArc(fx.cut, from, to, frame, cg, true)
    used.cut = true
end

local function Glint(frame, geom, f, size, a, rot, r, g, b)
    local x, y = Frame3(geom, f)
    fx.glint:ClearAllPoints()
    fx.glint:SetPoint("CENTER", frame, "CENTER", x, y)
    fx.glint:SetSize(size, size)
    fx.glint:SetRotation(rot)
    fx.glint:SetVertexColor(r or 0.9, g or 0.95, b or 1)
    fx.glint:SetAlpha(a)
    fx.glint:Show()
    used.glint = true
end

-- A point of a tool's image, mirrored left to right if `mirror`.
local function ToolPoint(which, at, mirror)
    local pt = TOOLS[which][at]
    if mirror then return { 1 - pt[1], pt[2] } end
    return pt
end

-- Draws a tool `size` across, turned by `turn` (radians, counterclockwise from how the image
-- stands, after mirroring) with its point `at` (its grip or tip) at (x, y).
local function Tool(frame, which, size, turn, at, x, y, a, mirror)
    local t = TOOLS[which]
    if fx.toolIs ~= which then
        if fx.tool:SetTexture(t.tex) == false then fx.tool:SetTexture(t.fallback) end
        fx.toolIs = which
    end
    local mx, my = FromMiddle(ToolPoint(which, at, mirror), size)
    local px, py = Turn(mx, my, turn)
    fx.tool:ClearAllPoints()
    fx.tool:SetPoint("CENTER", frame, "CENTER", x - px, y - py)
    fx.tool:SetSize(size, size)
    if mirror then
        fx.tool:SetTexCoord(1, 0, 0, 1)
    else
        fx.tool:SetTexCoord(0, 1, 0, 1)
    end
    fx.tool:SetRotation(turn)
    fx.tool:SetAlpha(a)
    fx.tool:Show()
    used.tool = true
end

-- Which way from the spot the tools are held: on along the ring (clockwise, so down and to
-- the right at the top right) and a little out from it, so the handles hang down and away
-- outside the ring and the working end reaches in to it.
local function HoldWay(ox, oy, tx, ty)
    local hx, hy = tx + ox * 0.25, ty + oy * 0.25
    local l = math.sqrt(hx * hx + hy * hy)
    return hx / l, hy / l
end

-- The turn that points a tool's image from its grip toward its tip along (dx, dy).
local function PointAlong(which, dx, dy, mirror)
    local gx, gy = FromMiddle(ToolPoint(which, "grip", mirror), 1)
    local kx, ky = FromMiddle(ToolPoint(which, "tip", mirror), 1)
    return Angle(dx, dy) - Angle(kx - gx, ky - gy)
end

-- How the tool fades once the gather ends: gone `fade` seconds after `from`.
local function ToolAlpha(now, from, fade)
    if not from or now <= from then return 1 end
    return math.max(0, 1 - (now - from) / fade)
end

local function Smooth(x)
    x = math.max(0, math.min(1, x))
    return x * x * (3 - 2 * x)
end

---------------------------------------------------------------- skinning
local STROKE = 0.42 -- seconds per knife stroke
local REACH = 0.10 -- how far back along the ring a stroke starts
local PER_STROKE = 3 -- tufts flicked off each stroke
local KEEP = 8 -- strokes whose tufts can still be falling
local FUR = {
    { 0.55, 0.38, 0.22 }, -- tan
    { 0.40, 0.27, 0.16 }, -- brown
    { 0.72, 0.58, 0.40 }, -- light
    { 0.86, 0.81, 0.71 }, -- pale
}

-- One tuft of fur (two strands) at time `now`, flicked off at `born` from ring fraction f.
-- `seed` picks its way; `burst` throws it harder (the closing spray).
local function Tuft(frame, geom, s, now, born, f, seed, burst)
    local age = now - born
    local life = (burst and 0.9 or 0.7) + 0.4 * Hash(seed + 0.1)
    if age < 0 or age > life then return end
    -- Flicked out a little and along the knife's way, then falling: they stay within about
    -- the ring's width of it.
    local out = ((burst and 30 or 16) + 22 * Hash(seed + 0.2)) * s
    local along = (Hash(seed + 0.3) - 0.3) * (burst and 30 or 40) * s
    local px, py = Thrown(geom, f, age, out, along, (burst and 8 or 18) * s, -110 * s)
    local spin = Hash(seed + 0.4) * TAU + (Hash(seed + 0.5) - 0.5) * 9 * age
    local len = (6 + 5 * Hash(seed + 0.6)) * s
    local c = FUR[1 + math.floor(Hash(seed + 0.7) * #FUR) % #FUR]
    local a = math.min(1, age * 12) * (1 - (age / life) ^ 2)
    for k = 0, 1 do
        local ang = spin + k * 0.55
        local ll = len * (k == 0 and 1 or 0.75)
        Put(
            fx.bits,
            "bits",
            frame,
            px,
            py,
            px + math.cos(ang) * ll,
            py + math.sin(ang) * ll,
            math.max(1, 1.6 * s),
            c[1],
            c[2],
            c[3],
            a
        )
    end
end

-- The knife: its tip slices along the band up to the spot, then it lifts out and back for the
-- next stroke. When it's done it makes one long last slice, then goes.
local KNIFE_RUN = 0.35
local function Knife(st, frame, geom, now, s, start, stopAt)
    local f, lift, a
    if st.fxDone and st.fxEndAt and now >= st.fxEndAt then
        f, lift = SPOT - 2 * REACH * (1 - math.min(1, (now - st.fxEndAt) / KNIFE_RUN)) ^ 2, 0
        a = ToolAlpha(now, st.fxEndAt + KNIFE_RUN, 0.25)
    else
        local t = math.min(now, stopAt)
        local i = math.floor((t - start) / STROKE)
        local p = (t - (start + i * STROKE)) / STROKE
        if p < 0.45 then
            f, lift = SPOT - REACH * (1 - p / 0.45) ^ 2, 0
        else
            local q = Smooth((p - 0.45) / 0.55)
            f, lift = SPOT - REACH * q, math.sin(math.pi * q)
        end
        a = ToolAlpha(now, st.fxEndAt, 0.25)
    end
    if a <= 0 then return end
    local x, y, ox, oy, tx, ty = Frame3(geom, math.max(0, f))
    -- Held from below and to the right, the blade reaches up into the band, its tip drawn
    -- along it toward the hand (the slice); lifted, it tips back out of the ring.
    local hx, hy = HoldWay(ox, oy, tx, ty)
    local dx, dy = -hx + ox * 0.7 * lift, -hy + oy * 0.7 * lift
    local h = lift * geom.T * 2.2
    Tool(frame, "knife", 34 * s, PointAlong("knife", dx, dy), "tip", x + ox * h, y + oy * h, a)
end

local function Skinning(st, frame, geom, now, s)
    local start = st.fxStart or now
    local stopAt = st.fxEndAt or math.huge

    -- The strokes so far: the latest one's knife, and the tufts of the last few.
    local k = math.floor((math.min(now, stopAt) - start) / STROKE)
    for i = k, math.max(0, k - KEEP), -1 do
        local ks = start + i * STROKE
        local bite = ks + STROKE * 0.45 -- when the knife reaches the edge
        if bite <= stopAt then
            local f = SPOT
            for m = 1, PER_STROKE do
                Tuft(frame, geom, s, now, bite + m * 0.03, f, i * 7.13 + m * 1.91, false)
            end
        end
        if i == k and now < stopAt then
            -- The knife slices along the band up to the spot, leaving a bright cut behind it.
            local p = (now - ks) / STROKE
            if p < 0.55 then
                local e = SPOT
                local ease = 1 - (1 - math.min(1, p / 0.45)) ^ 2
                local head = e - REACH * (1 - ease)
                Cut(frame, geom, head - 0.06, head, 0.85 * math.sin(math.pi * p / 0.55))
            end
        end
    end
    Knife(st, frame, geom, now, s, start, stopAt)

    -- Done: one last cut runs round the whole ring, spraying fur as it passes.
    if st.fxDone and st.fxEndAt then
        local d = now - st.fxEndAt
        local RUN = 0.35
        if d >= 0 and d < RUN + 0.15 then
            local head = d / RUN
            local a = d < RUN and 1 or (1 - (d - RUN) / 0.15)
            Cut(frame, geom, head - 0.25, head, 0.9 * a, nil, nil, nil, true)
        end
        local N = 14
        for j = 1, N do
            local f = (j - 0.5) / N
            Tuft(frame, geom, s, now, st.fxEndAt + f * RUN, f, 500 + j * 3.7, true)
        end
    end
end

---------------------------------------------------------------- mining
local SWING = 0.55 -- seconds per swing of the pick
local WIND = 0.6 -- of a swing spent winding up; the strike lands then
local SPARKS_PER = 5 -- sparks thrown each strike
local CHIPS_PER = 3 -- chips of rock knocked off each strike
local KEEP_SWINGS = 3 -- swings whose sparks and chips can still be flying
local ROCK = {
    { 0.50, 0.48, 0.45 }, -- grey
    { 0.36, 0.34, 0.32 }, -- dark
    { 0.60, 0.53, 0.43 }, -- sandy
    { 0.28, 0.25, 0.23 }, -- near black
}

-- A spark: a short glowing streak along its way, hot white cooling to orange.
local function Spark(frame, geom, s, now, born, f, seed, burst)
    local age = now - born
    local life = (burst and 0.45 or 0.3) + 0.25 * Hash(seed + 0.1)
    if age < 0 or age > life then return end
    local out = ((burst and 70 or 50) + 70 * Hash(seed + 0.2)) * s
    local along = (Hash(seed + 0.3) - 0.5) * 110 * s
    local px, py, vx, vy = Thrown(geom, f, age, out, along, 30 * s, -260 * s)
    local u = age / life
    local tail = 0.035 -- seconds of travel the streak covers
    Put(
        fx.sparks,
        "sparks",
        frame,
        px,
        py,
        px - vx * tail,
        py - vy * tail,
        math.max(1, 1.4 * s),
        1,
        0.95 - 0.45 * u,
        0.7 - 0.6 * u,
        (1 - u) ^ 1.5
    )
end

-- A chip of rock: a small tumbling block, knocked out and falling.
local function Chip(frame, geom, s, now, born, f, seed, burst)
    local age = now - born
    local life = 0.55 + 0.35 * Hash(seed + 0.1)
    if age < 0 or age > life then return end
    local out = ((burst and 28 or 18) + 22 * Hash(seed + 0.2)) * s
    local along = (Hash(seed + 0.3) - 0.5) * 50 * s
    local px, py = Thrown(geom, f, age, out, along, 30 * s, -200 * s)
    local size = (2.5 + 2 * Hash(seed + 0.4)) * s
    local spin = Hash(seed + 0.5) * TAU + (Hash(seed + 0.6) - 0.5) * 14 * age
    local hx, hy = math.cos(spin) * size * 0.45, math.sin(spin) * size * 0.45
    local c = ROCK[1 + math.floor(Hash(seed + 0.7) * #ROCK) % #ROCK]
    local a = math.min(1, age * 15) * (1 - (age / life) ^ 3)
    Put(fx.bits, "bits", frame, px - hx, py - hy, px + hx, py + hy, math.max(1.5, size * 0.8), c[1], c[2], c[3], a)
end

-- The pickaxe: held outside the ring, it raises, swings down so its point lands on the fill's
-- edge as the strike lands, bounces back a little, and settles ready for the next. When the
-- vein breaks it lands one last time on the ring's end, then goes.
local PICK_RAISE = 1.1 -- radians it's raised at the top of the swing
local function PickAngle(p)
    if p < 0.45 then return PICK_RAISE * (0.3 + 0.7 * (1 - (1 - p / 0.45) ^ 2)) end -- raising
    if p < WIND then return PICK_RAISE * (1 - ((p - 0.45) / (WIND - 0.45)) ^ 2) end -- the swing
    if p < 0.75 then return PICK_RAISE * 0.15 * math.sin(math.pi * (p - WIND) / (0.75 - WIND)) end -- the bounce
    return PICK_RAISE * 0.3 * Smooth((p - 0.75) / 0.25) -- getting ready again
end

local function Pickaxe(st, frame, geom, now, s, start, stopAt)
    local f, raise, a
    if st.fxDone and st.fxEndAt and now >= st.fxEndAt then
        local d = now - st.fxEndAt
        f, raise = SPOT, PICK_RAISE * 0.25 * math.sin(math.pi * math.min(1, d / 0.3))
        a = ToolAlpha(now, st.fxEndAt + 0.3, 0.3)
    else
        local t = math.min(now, stopAt)
        local i = math.floor((t - start) / SWING)
        f, raise = SPOT, PickAngle((t - (start + i * SWING)) / SWING)
        a = ToolAlpha(now, st.fxEndAt, 0.25)
    end
    if a <= 0 then return end
    local size = 40 * s
    local x, y, ox, oy, tx, ty = Frame3(geom, f)
    -- Held by the end of its handle, below and to the right of the spot: it turns about that
    -- hand, and its point lands on the spot as the strike lands. The image's point leads when
    -- it turns clockwise; mirrored, counterclockwise. Take whichever way raising it lifts the
    -- point away from the ring rather than through it.
    local hx, hy = HoldWay(ox, oy, tx, ty)
    local best, bestTurn, bestMirror, Gx, Gy
    for _, mirror in ipairs({ false, true }) do
        local gx, gy = FromMiddle(ToolPoint("pick", "grip", mirror), size)
        local kx, ky = FromMiddle(ToolPoint("pick", "tip", mirror), size)
        local vx, vy = kx - gx, ky - gy -- hand to point
        local len = math.sqrt(vx * vx + vy * vy)
        local hgx, hgy = x + hx * len, y + hy * len
        local hit = Angle(x - hgx, y - hgy) - Angle(vx, vy)
        local up = mirror and -1 or 1 -- which way raising turns it
        local rx, ry = Turn(vx, vy, hit + up * PICK_RAISE)
        local away = (hgx + rx) ^ 2 + (hgy + ry) ^ 2 -- the raised point's distance from the middle
        if not best or away > best then
            best, bestTurn, bestMirror, Gx, Gy = away, hit + up * raise, mirror, hgx, hgy
        end
    end
    Tool(frame, "pick", size, bestTurn, "grip", Gx, Gy, a, bestMirror)
end

local function Mining(st, frame, geom, now, s)
    local start = st.fxStart or now
    local stopAt = st.fxEndAt or math.huge

    local k = math.floor((math.min(now, stopAt) - start) / SWING)
    for i = k, math.max(0, k - KEEP_SWINGS), -1 do
        local ks = start + i * SWING
        local hit = ks + SWING * WIND -- when the pick lands
        if hit <= stopAt then
            local f = SPOT
            for m = 1, SPARKS_PER do
                Spark(frame, geom, s, now, hit, f, i * 5.31 + m * 2.17, false)
            end
            for m = 1, CHIPS_PER do
                Chip(frame, geom, s, now, hit + m * 0.02, f, i * 3.77 + m * 1.43, false)
            end
        end
        if i == k and now < stopAt then
            local e = SPOT
            local p = (now - ks) / SWING
            if p >= WIND and p < WIND + 0.25 then
                -- The strike: a flash that shrinks, and a short crack of light along the edge.
                local d = (p - WIND) / 0.25
                Glint(frame, geom, e, geom.T * (3.4 - 1.6 * d), 1 - d, 0.3 + d * 0.5, 1, 0.92, 0.65)
                Cut(frame, geom, e - 0.035, e + 0.005, 0.9 * (1 - d), 1, 0.85, 0.55)
            end
        end
    end

    Pickaxe(st, frame, geom, now, s, start, stopAt)

    -- Done: the vein breaks. A heavy strike flashes the whole ring, and rock and sparks burst
    -- off all round.
    if st.fxDone and st.fxEndAt then
        local d = now - st.fxEndAt
        if d >= 0 and d < 0.35 then
            local u = d / 0.35
            Cut(frame, geom, 0, 1, 0.75 * (1 - u) ^ 2, 1, 0.85, 0.55, true)
            Glint(frame, geom, SPOT, geom.T * (4.5 - 2 * u), 1 - u, 0.3 + u, 1, 0.92, 0.65)
        end
        local N = 12
        for j = 1, N do
            local f = (j - 0.5) / N
            Chip(frame, geom, s, now, st.fxEndAt + 0.02 * (j % 3), f, 700 + j * 2.9, true)
            Spark(frame, geom, s, now, st.fxEndAt, f + 0.03, 800 + j * 4.1, true)
            Spark(frame, geom, s, now, st.fxEndAt + 0.05, f - 0.03, 900 + j * 3.3, true)
        end
    end
end

---------------------------------------------------------------- herbalism
local SNIP = 0.45 -- seconds per snip
local SNIP_AT = 0.42 -- of a snip: when the jaws close
local LEAVES_PER = 3 -- leaves cut loose each snip
local PETALS_PER = 2 -- and petals
local KEEP_SNIPS = 4 -- snips whose leaves can still be falling
local LEAF = {
    { 0.35, 0.65, 0.25 }, -- green
    { 0.24, 0.50, 0.20 }, -- dark green
    { 0.52, 0.76, 0.30 }, -- light green
}
local PETAL = {
    { 0.96, 0.95, 0.88 }, -- white
    { 1.00, 0.84, 0.30 }, -- yellow
    { 0.95, 0.60, 0.75 }, -- pink
    { 0.76, 0.62, 0.95 }, -- lavender
}

-- A leaf or petal: cut loose, it floats out and flutters down, swaying and turning.
local function Leaf(frame, geom, s, now, born, f, seed, petal, gust)
    local age = now - born
    local life = (gust and 1.4 or 1.0) + 0.5 * Hash(seed + 0.1)
    if age < 0 or age > life then return end
    local out = ((gust and 26 or 14) + 16 * Hash(seed + 0.2)) * s
    local along = (Hash(seed + 0.3) - 0.5) * 30 * s
    local px, py = Thrown(geom, f, age, out, along, (gust and 38 or 24) * s, -60 * s)
    local sway = math.sin(age * 5 + seed * 3) * 5 * s * math.min(1, age * 2)
    px = px + sway
    local spin = Hash(seed + 0.4) * TAU + math.sin(age * 4 + seed) * 0.9
    local c, len, w
    if petal then
        c = PETAL[1 + math.floor(Hash(seed + 0.7) * #PETAL) % #PETAL]
        len, w = (3 + 1.5 * Hash(seed + 0.6)) * s, math.max(1.5, 3 * s)
    else
        c = LEAF[1 + math.floor(Hash(seed + 0.7) * #LEAF) % #LEAF]
        len, w = (6 + 3 * Hash(seed + 0.6)) * s, math.max(1.5, 2.6 * s)
    end
    local hx, hy = math.cos(spin) * len * 0.5, math.sin(spin) * len * 0.5
    local a = math.min(1, age * 10) * (1 - (age / life) ^ 2)
    Put(fx.bits, "bits", frame, px - hx, py - hy, px + hx, py + hy, w, c[1], c[2], c[3], a)
end

-- The shears: they move in until the jaws meet the spot, snip (a quick squeeze and
-- twist), and pull back out for the next. The last snip lands on the ring's end.
local SHEARS_GAP = 1.6 -- how far out (in ring widths) they pull back between snips
local function Shears(st, frame, geom, now, s, start, stopAt)
    local f, gap, squeeze, a
    local function Snip(p)
        if p < SNIP_AT - 0.07 then return 1 - (p / (SNIP_AT - 0.07)) ^ 2, 0 end -- moving in
        if p < SNIP_AT + 0.08 then return 0, math.sin(math.pi * (p - SNIP_AT + 0.07) / 0.15) end -- the snip
        return Smooth((p - SNIP_AT - 0.08) / (1 - SNIP_AT - 0.08)), 0 -- pulling back
    end
    if st.fxDone and st.fxEndAt and now >= st.fxEndAt then
        local d = now - st.fxEndAt
        f, gap, squeeze = SPOT, 0, d < 0.15 and math.sin(math.pi * d / 0.15) or 0
        a = ToolAlpha(now, st.fxEndAt + 0.2, 0.3)
    else
        local t = math.min(now, stopAt)
        local i = math.floor((t - start) / SNIP)
        f = SPOT
        gap, squeeze = Snip((t - (start + i * SNIP)) / SNIP)
        a = ToolAlpha(now, st.fxEndAt, 0.25)
    end
    if a <= 0 then return end
    local x, y, ox, oy, tx, ty = Frame3(geom, f)
    -- Held from below and to the right, the jaws reach in to the spot; they pull back along
    -- the same way between snips, and a snip squeezes and twists them.
    local hx, hy = HoldWay(ox, oy, tx, ty)
    local turn = PointAlong("shears", -hx, -hy) + 0.18 * squeeze
    local h = geom.T * (0.5 + SHEARS_GAP * gap) -- the jaws close just over the band's outside
    Tool(
        frame,
        "shears",
        34 * s * (1 - 0.1 * squeeze),
        turn,
        "tip",
        x + (ox * 0.5 + hx * 0.5) * h,
        y + (oy * 0.5 + hy * 0.5) * h,
        a
    )
end

local function Herbalism(st, frame, geom, now, s)
    local start = st.fxStart or now
    local stopAt = st.fxEndAt or math.huge
    local k = math.floor((math.min(now, stopAt) - start) / SNIP)
    for i = k, math.max(0, k - KEEP_SNIPS), -1 do
        local at = start + (i + SNIP_AT) * SNIP -- when the jaws close
        if at <= stopAt then
            local f = SPOT
            for m = 1, LEAVES_PER do
                Leaf(frame, geom, s, now, at + m * 0.02, f, i * 6.17 + m * 1.37, false)
            end
            for m = 1, PETALS_PER do
                Leaf(frame, geom, s, now, at + m * 0.03, f, i * 4.91 + m * 2.53, true)
            end
            -- A small bright snip where the jaws meet.
            local d = now - at
            if d >= 0 and d < 0.18 then
                Glint(frame, geom, f, geom.T * (2.4 - 4 * d), 0.8 * (1 - d / 0.18), d * 6, 0.85, 1, 0.7)
            end
        end
    end
    Shears(st, frame, geom, now, s, start, stopAt)

    -- Done: a last snip, and a gust of leaves and petals off the whole ring.
    if st.fxDone and st.fxEndAt then
        local d = now - st.fxEndAt
        if d >= 0 and d < 0.3 then
            Cut(frame, geom, 0, 1, 0.45 * (1 - d / 0.3) ^ 2, 0.6, 1, 0.5, true)
            Glint(frame, geom, SPOT, geom.T * (3 - 3 * d), 1 - d / 0.3, d * 5, 0.85, 1, 0.7)
        end
        local N = 18
        for j = 1, N do
            local f = (j - 0.5) / N
            Leaf(frame, geom, s, now, st.fxEndAt + 0.04 * (j % 4), f, 1100 + j * 2.3, j % 3 == 0, true)
        end
    end
end

local DRAW = { skinning = Skinning, mining = Mining, herb = Herbalism }

-- Called every frame by the gathering ring (cfg.decorate).
local function DrawGatherFx(st, frame, geom)
    local draw = st and st.gatherFx and DRAW[st.gatherFx]
    if not draw or not geom or geom.R <= 0 then return HideAll() end
    if not fx then Build(frame) end
    used = { bits = 0, sparks = 0 }
    draw(st, frame, geom, GetTime(), math.max(0.4, geom.R / 50)) -- sizes and speeds follow the ring's size
    if not used.cut then
        for _, l in ipairs(fx.cut) do
            l:Hide()
        end
    end
    if not used.glint then fx.glint:Hide() end
    if not used.tool then fx.tool:Hide() end
    for i = used.bits + 1, BITS do
        fx.bits[i]:Hide()
    end
    for i = used.sparks + 1, SPARKS do
        fx.sparks[i]:Hide()
    end
end

-- Shared with the files loaded after this one.
ns.DrawGatherFx = DrawGatherFx
ns.GATHER_FX = DRAW
