-- Circlet: Gathering effects: an animation of its own for each gathering profession, on the
-- gathering ring.
local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- The effects
---------------------------------------------------------------------------
-- Worked out from the time alone (nothing kept between frames), so edit mode's sample plays
-- them too. The gathering ring's state carries:
--   st.gatherFx: the profession (only set while gatherFx is on and it has an effect);
--   st.fxStart / st.fxSpan: when the gather started and how long it takes (where the fill's
--     edge is at any moment); st.fxEndAt: when it ended, if it has; st.fxDone: it finished
--     (rather than being interrupted), which plays the closing flourish.
--
--   skinning: a knife works along the fill's edge in quick strokes, each flicking off a few
--             tufts of fur that tumble down and fade. When it's done one last cut runs round
--             the whole ring and fur sprays off all of it.
--   mining:   a pick swings at the fill's edge: it winds up, strikes with a flash and a crack
--             of light, and throws sparks and chips of rock that fall away. When the vein
--             breaks a last heavy strike flashes the whole ring and rock and sparks burst off
--             all round.

local TAU = 2 * math.pi
local STAR_TEX = "Interface\\Cooldown\\star4"

-- A repeatable "random" number in [0, 1) for n: the same n always gives the same number.
local function Hash(n)
    local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)
end

local BITS = 96   -- lines for solid bits (fur: two per tuft; rock chips: one each)
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
    fx.glint = frame:CreateTexture(nil, "ARTWORK", nil, 4) -- a blade's edge, a pick's strike
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
    for _, l in ipairs(fx.cut) do l:Hide() end
    fx.glint:Hide()
    for _, l in ipairs(fx.bits) do l:Hide() end
    for _, l in ipairs(fx.sparks) do l:Hide() end
end

-- Where the fill's edge is (a fraction of the ring) at time t.
local function Edge(st, t)
    if not (st.fxStart and st.fxSpan and st.fxSpan > 0) then return 0 end
    return math.max(0, math.min(1, (t - st.fxStart) / st.fxSpan))
end

-- The point on the ring at fraction f, the way out from the middle there, and the way
-- along the ring (the way the fill grows).
local function Frame3(geom, f)
    local x, y = ns.RingPoint(geom, f)
    local x2, y2 = ns.RingPoint(geom, f + 0.002)
    local tx, ty = x2 - x, y2 - y
    local tl = math.sqrt(tx * tx + ty * ty)
    if tl > 0 then tx, ty = tx / tl, ty / tl end
    local r = math.sqrt(x * x + y * y)
    local ox, oy = 0, 1
    if r > 0 then ox, oy = x / r, y / r end
    return x, y, ox, oy, tx, ty
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

-- The cut: a bright arc [from, to] of the ring, thinner than the band.
local function Cut(frame, geom, from, to, a, r, g, b)
    from, to = math.max(0, from), math.min(1, to)
    if to <= from then return end
    local cg = fx.cutGeom
    cg.R, cg.T, cg.start, cg.sweep, cg.step, cg.reverse = geom.R, math.max(1.5, geom.T * 0.35), geom.start, geom.sweep, geom.step, geom.reverse
    for _, l in ipairs(fx.cut) do l:SetColorTexture(r or 0.85, g or 0.92, b or 1, a) end
    ns.DrawArc(fx.cut, from, to, frame, cg, true)
    used.cut = true
end

local function Glint(frame, geom, f, size, a, rot, r, g, b)
    local x, y = ns.RingPoint(geom, f)
    fx.glint:ClearAllPoints()
    fx.glint:SetPoint("CENTER", frame, "CENTER", x, y)
    fx.glint:SetSize(size, size)
    fx.glint:SetRotation(rot)
    fx.glint:SetVertexColor(r or 0.9, g or 0.95, b or 1)
    fx.glint:SetAlpha(a)
    fx.glint:Show()
    used.glint = true
end

---------------------------------------------------------------- skinning
local STROKE = 0.42      -- seconds per knife stroke
local REACH = 0.10       -- how far back along the ring a stroke starts
local PER_STROKE = 3     -- tufts flicked off each stroke
local KEEP = 8           -- strokes whose tufts can still be falling
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
        Put(fx.bits, "bits", frame, px, py, px + math.cos(ang) * ll, py + math.sin(ang) * ll,
            math.max(1, 1.6 * s), c[1], c[2], c[3], a)
    end
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
            local f = Edge(st, bite)
            for m = 1, PER_STROKE do
                Tuft(frame, geom, s, now, bite + m * 0.03, f, i * 7.13 + m * 1.91, false)
            end
        end
        if i == k and now < stopAt then
            -- The knife: slides up to the edge, then lifts away.
            local p = (now - ks) / STROKE
            if p < 0.55 then
                local e = Edge(st, now)
                local ease = 1 - (1 - math.min(1, p / 0.45)) ^ 2
                local head = e - REACH * (1 - ease)
                local a = math.sin(math.pi * p / 0.55)
                Cut(frame, geom, head - 0.06, head, 0.85 * a)
                Glint(frame, geom, math.max(0, head), geom.T * 2.2, a, now * 4)
            end
        end
    end

    -- Done: one last cut round the whole ring, spraying fur as it passes.
    if st.fxDone and st.fxEndAt then
        local d = now - st.fxEndAt
        local RUN = 0.35
        if d >= 0 and d < RUN + 0.15 then
            local head = d / RUN
            local a = d < RUN and 1 or (1 - (d - RUN) / 0.15)
            Cut(frame, geom, head - 0.25, head, 0.9 * a)
            if d < RUN then Glint(frame, geom, head, geom.T * 2.8, a, now * 4) end
        end
        local N = 14
        for j = 1, N do
            local f = (j - 0.5) / N
            Tuft(frame, geom, s, now, st.fxEndAt + f * RUN, f, 500 + j * 3.7, true)
        end
    end
end

---------------------------------------------------------------- mining
local SWING = 0.55       -- seconds per swing of the pick
local WIND = 0.6         -- of a swing spent winding up; the strike lands then
local SPARKS_PER = 5     -- sparks thrown each strike
local CHIPS_PER = 3      -- chips of rock knocked off each strike
local KEEP_SWINGS = 3    -- swings whose sparks and chips can still be flying
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
    Put(fx.sparks, "sparks", frame, px, py, px - vx * tail, py - vy * tail, math.max(1, 1.4 * s),
        1, 0.95 - 0.45 * u, 0.7 - 0.6 * u, (1 - u) ^ 1.5)
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

local function Mining(st, frame, geom, now, s)
    local start = st.fxStart or now
    local stopAt = st.fxEndAt or math.huge

    local k = math.floor((math.min(now, stopAt) - start) / SWING)
    for i = k, math.max(0, k - KEEP_SWINGS), -1 do
        local ks = start + i * SWING
        local hit = ks + SWING * WIND -- when the pick lands
        if hit <= stopAt then
            local f = Edge(st, hit)
            for m = 1, SPARKS_PER do Spark(frame, geom, s, now, hit, f, i * 5.31 + m * 2.17, false) end
            for m = 1, CHIPS_PER do Chip(frame, geom, s, now, hit + m * 0.02, f, i * 3.77 + m * 1.43, false) end
        end
        if i == k and now < stopAt then
            local e = Edge(st, now)
            local p = (now - ks) / SWING
            if p < WIND then
                -- Winding up: a faint glint gathering at the edge.
                local w = p / WIND
                Glint(frame, geom, e, geom.T * (1 + 0.6 * w), 0.35 * w * w, 0.3, 1, 0.9, 0.7)
            elseif p < WIND + 0.25 then
                -- The strike: a flash that shrinks, and a short crack of light along the edge.
                local d = (p - WIND) / 0.25
                Glint(frame, geom, e, geom.T * (3.4 - 1.6 * d), 1 - d, 0.3 + d * 0.5, 1, 0.92, 0.65)
                Cut(frame, geom, e - 0.035, e + 0.005, 0.9 * (1 - d), 1, 0.85, 0.55)
            end
        end
    end

    -- Done: the vein breaks. A heavy strike flashes the whole ring, and rock and sparks burst
    -- off all round.
    if st.fxDone and st.fxEndAt then
        local d = now - st.fxEndAt
        if d >= 0 and d < 0.35 then
            local u = d / 0.35
            Cut(frame, geom, 0, 1, 0.75 * (1 - u) ^ 2, 1, 0.85, 0.55)
            Glint(frame, geom, 1, geom.T * (4.5 - 2 * u), 1 - u, 0.3 + u, 1, 0.92, 0.65)
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

local DRAW = { skinning = Skinning, mining = Mining }

-- Called every frame by the gathering ring (cfg.decorate).
local function DrawGatherFx(st, frame, geom)
    local draw = st and st.gatherFx and DRAW[st.gatherFx]
    if not draw or not geom or geom.R <= 0 then return HideAll() end
    if not fx then Build(frame) end
    used = { bits = 0, sparks = 0 }
    draw(st, frame, geom, GetTime(), math.max(0.4, geom.R / 50)) -- sizes and speeds follow the ring's size
    if not used.cut then for _, l in ipairs(fx.cut) do l:Hide() end end
    if not used.glint then fx.glint:Hide() end
    for i = used.bits + 1, BITS do fx.bits[i]:Hide() end
    for i = used.sparks + 1, SPARKS do fx.sparks[i]:Hide() end
end

-- Shared with the files loaded after this one.
ns.DrawGatherFx = DrawGatherFx
ns.GATHER_FX = DRAW
