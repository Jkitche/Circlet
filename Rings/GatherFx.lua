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

local TAU = 2 * math.pi
local STAR_TEX = "Interface\\Cooldown\\star4"

-- A repeatable "random" number in [0, 1) for n: the same n always gives the same number.
local function Hash(n)
    local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)
end

local STRANDS = 96 -- lines for fur (two per tuft)

local fx -- lines and textures on the gathering ring's frame, made on first use

local function Build(frame)
    fx = { strands = {}, cutGeom = {} }
    -- The knife's cut: a thin bright arc over the fill (ARTWORK 0) and its flash (1).
    fx.cut = ns.NewRingLayer("ARTWORK", 2, { r = 1, g = 1, b = 1 }, 1, frame)
    for _, l in ipairs(fx.cut) do
        if l.SetBlendMode then l:SetBlendMode("ADD") end
        l:Hide()
    end
    fx.glint = frame:CreateTexture(nil, "ARTWORK", nil, 4) -- the blade's edge catching the light
    fx.glint:SetTexture(STAR_TEX)
    fx.glint:SetBlendMode("ADD")
    fx.glint:Hide()
    for i = 1, STRANDS do
        local l = frame:CreateLine(nil, "ARTWORK", nil, 3)
        l:Hide()
        fx.strands[i] = l
    end
end

local function HideAll()
    if not fx then return end
    for _, l in ipairs(fx.cut) do l:Hide() end
    fx.glint:Hide()
    for _, l in ipairs(fx.strands) do l:Hide() end
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
local function Tuft(frame, geom, s, now, born, f, seed, burst, lit, nextStrand)
    local age = now - born
    local life = (burst and 0.9 or 0.7) + 0.4 * Hash(seed + 0.1)
    if age < 0 or age > life then return nextStrand end
    local x, y, ox, oy, tx, ty = Frame3(geom, f)
    -- Flicked out a little and along the knife's way, then falling: they stay within about
    -- the ring's width of it.
    local out = ((burst and 30 or 16) + 22 * Hash(seed + 0.2)) * s
    local along = (Hash(seed + 0.3) - 0.3) * (burst and 30 or 40) * s
    local up = (burst and 8 or 18) * s
    local fall = -110 * s
    local px = x + (ox * out + tx * along) * age
    local py = y + (oy * out + ty * along + up) * age + 0.5 * fall * age * age
    local spin = Hash(seed + 0.4) * TAU + (Hash(seed + 0.5) - 0.5) * 9 * age
    local len = (6 + 5 * Hash(seed + 0.6)) * s
    local c = FUR[1 + math.floor(Hash(seed + 0.7) * #FUR) % #FUR]
    local a = math.min(1, age * 12) * (1 - (age / life) ^ 2) * lit
    for k = 0, 1 do
        local l = fx.strands[nextStrand]
        if not l then return nextStrand end
        local ang = spin + k * 0.55
        local ll = len * (k == 0 and 1 or 0.75)
        l:SetStartPoint("CENTER", frame, px, py)
        l:SetEndPoint("CENTER", frame, px + math.cos(ang) * ll, py + math.sin(ang) * ll)
        l:SetThickness(math.max(1, 1.6 * s))
        l:SetColorTexture(c[1], c[2], c[3], a)
        l:Show()
        nextStrand = nextStrand + 1
    end
    return nextStrand
end

-- The cut: a bright arc [from, to] of the ring, thinner than the band.
local function Cut(frame, geom, from, to, a)
    from, to = math.max(0, from), math.min(1, to)
    if to <= from then
        for _, l in ipairs(fx.cut) do l:Hide() end
        return
    end
    local g = fx.cutGeom
    g.R, g.T, g.start, g.sweep, g.step, g.reverse = geom.R, math.max(1.5, geom.T * 0.35), geom.start, geom.sweep, geom.step, geom.reverse
    for _, l in ipairs(fx.cut) do l:SetColorTexture(0.85, 0.92, 1, a) end
    ns.DrawArc(fx.cut, from, to, frame, g, true)
end

local function Glint(frame, geom, f, size, a, now)
    local x, y = ns.RingPoint(geom, f)
    fx.glint:ClearAllPoints()
    fx.glint:SetPoint("CENTER", frame, "CENTER", x, y)
    fx.glint:SetSize(size, size)
    fx.glint:SetRotation(now * 4)
    fx.glint:SetVertexColor(0.9, 0.95, 1)
    fx.glint:SetAlpha(a)
    fx.glint:Show()
end

local function Skinning(st, frame, geom, now)
    local s = math.max(0.4, geom.R / 50) -- sizes and speeds follow the ring's size
    local start = st.fxStart or now
    local stopAt = st.fxEndAt or math.huge
    local strand = 1
    local showCut, showGlint = false, false

    -- The strokes so far: the latest one's knife, and the tufts of the last few.
    local k = math.floor((math.min(now, stopAt) - start) / STROKE)
    for i = k, math.max(0, k - KEEP), -1 do
        local ks = start + i * STROKE
        local bite = ks + STROKE * 0.45 -- when the knife reaches the edge
        if bite <= stopAt then
            local f = Edge(st, bite)
            for m = 1, PER_STROKE do
                strand = Tuft(frame, geom, s, now, bite + m * 0.03, f, i * 7.13 + m * 1.91, false, 1, strand)
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
                Glint(frame, geom, math.max(0, head), geom.T * 2.2, a, now)
                showCut, showGlint = true, true
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
            if d < RUN then Glint(frame, geom, head, geom.T * 2.8, a, now) end
            showCut, showGlint = true, d < RUN
        end
        local N = 14
        for j = 1, N do
            local f = (j - 0.5) / N
            strand = Tuft(frame, geom, s, now, st.fxEndAt + f * RUN, f, 500 + j * 3.7, true, 1, strand)
        end
    end

    if not showCut then for _, l in ipairs(fx.cut) do l:Hide() end end
    if not showGlint then fx.glint:Hide() end
    for i = strand, STRANDS do fx.strands[i]:Hide() end
end

local DRAW = { skinning = Skinning }

-- Called every frame by the gathering ring (cfg.decorate).
local function DrawGatherFx(st, frame, geom)
    local draw = st and st.gatherFx and DRAW[st.gatherFx]
    if not draw or not geom or geom.R <= 0 then return HideAll() end
    if not fx then Build(frame) end
    draw(st, frame, geom, GetTime())
end

-- Shared with the files loaded after this one.
ns.DrawGatherFx = DrawGatherFx
ns.GATHER_FX = DRAW
