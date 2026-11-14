-- Circlet: Corpse ring: how far your body is while you're a ghost, and which way.
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing, FormatTime = ns.db, ns.IsSecret, ns.CreateLiveRing, ns.FormatTime
local SafeCall = ns.SafeCall

---------------------------------------------------------------------------
-- Corpse ring
---------------------------------------------------------------------------
-- After you release, the ring shows the distance to your corpse in yards and fills
-- as you close in. A dot on the ring points toward the corpse (straight up = ahead).
-- It says when you can resurrect: the wait if there is one, then "In range" once
-- you're close enough.

local RES_RANGE = 39 -- yards; the game's corpse-resurrect range is about 40
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local startDist -- distance when this corpse run began, for the fill

---------------------------------------------------------------------------
-- Revive animation
---------------------------------------------------------------------------
-- When you step back into your own body (at your corpse, or by accepting a resurrect
-- while a ghost), the ring plays your soul coming home. A pale, flickering orb drifts
-- down from above the ring, swaying, with a smoky tail behind it, while wisps of ghost
-- light rise from around the ring and stream into it. Just before it lands the ring
-- draws in around it, then the soul sinks into the middle and is gone. The ring warms
-- from the ghost color to the "in range" color, a heartbeat (lub-dub) thumps out, each
-- beat flashing the ring and rolling a wave outward, and the last of the ghost rises out
-- of the ring as mist and fades away. Everything is worked out from the time since you
-- revived, so edit mode's sample plays the same animation.
-- Reviving at a spirit healer (far from your corpse) doesn't play it.

local REVIVE_TIME  = 3.2  -- seconds the animation runs
local REVIVE_WISPS = 8
local WISP_TRAIL   = 3    -- puffs per wisp: its head and a smoky tail
local SOUL_TAIL    = 6    -- puffs trailing the soul as it drifts down
local MIST_PUFFS   = 6    -- the last of the ghost, rising away after the heartbeat
local GATHER_END   = 1.1  -- the soul settles into the body by now
local BEATS        = { 1.3, 1.57 } -- lub, dub
local GLOW_TEX     = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR_TEX     = "Interface\\Cooldown\\star4"
local WHITE        = { r = 1, g = 1, b = 1 }

local revivedAt     -- GetTime() when you came back to life (while the animation plays)
local reviveAsked   -- GetTime() you clicked Resurrect at your corpse or accepted a resurrect
local wasInRange    -- you were within resurrect range of your corpse as a ghost
local wasGhost      -- the ring saw you as a ghost (so a revive is a return from a corpse run)

local function EaseOut(t) return 1 - (1 - t) ^ 2 end
local function EaseIn(t) return t * t end
local function Clamp01(t) return math.max(0, math.min(1, t)) end
local function EaseInOut(t) return t < 0.5 and 2 * t * t or 1 - (2 - 2 * t) ^ 2 / 2 end

-- A ghostly waver in brightness (about 0.6..1), different for each seed.
local function Flicker(age, seed)
    return 0.8 + 0.12 * math.sin(age * 11 + seed) + 0.08 * math.sin(age * 6.7 + seed * 2.1)
end

-- Where the soul is, u (0..1) of the way down: from high above the ring into its
-- middle, swaying side to side less and less as it settles.
local function SoulPos(u, geom, ri)
    return math.sin(u * math.pi * 2.2) * ri * 0.35 * (1 - u), geom.R * 1.8 * (1 - EaseInOut(u))
end

local function Lighten(c, w)
    return c.r + (1 - c.r) * w, c.g + (1 - c.g) * w, c.b + (1 - c.b) * w
end

local function Mix(a, b, t)
    return { r = a.r + (b.r - a.r) * t, g = a.g + (b.g - a.g) * t, b = a.b + (b.b - a.b) * t }
end

-- How hard the heart is beating at `age`: a quick bump at each beat, 0 between.
local function Pulse(age)
    local p = 0
    for i, at in ipairs(BEATS) do
        local d = (age - at) / 0.22
        if d >= 0 and d < 1 then
            p = math.max(p, math.sin(math.pi * d) * (i == 1 and 1 or 0.8))
        end
    end
    return p
end

local fx -- the effect's textures and lines, made on the corpse ring's frame on first use

local function SoftGlow(frame, layer, sub)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    if t:SetTexture(GLOW_TEX) == false then t:SetTexture(STAR_TEX) end
    t:SetBlendMode("ADD")
    t:Hide()
    return t
end

local function BuildFx(frame)
    fx = { all = {}, wisps = {}, tail = {}, mist = {}, glowGeom = {}, pullGeom = {}, waves = {} }
    local function Glow(layer, sub)
        local t = SoftGlow(frame, layer, sub)
        fx.all[#fx.all + 1] = t
        return t
    end
    fx.heart    = Glow("BACKGROUND", -7) -- in the ring's hollow, behind the track
    fx.core     = Glow("BORDER", 1)
    fx.soulHalo = Glow("ARTWORK", 1)
    fx.soul     = Glow("ARTWORK", 2)
    fx.soulCore = Glow("ARTWORK", 3)
    fx.glow     = ns.NewRingLayer("OVERLAY", 2, WHITE, 1, frame)
    fx.pull     = ns.NewRingLayer("OVERLAY", 1, WHITE, 1, frame) -- the ring drawing in
    for i = 1, #BEATS do
        fx.waves[i] = { lines = ns.NewRingLayer("OVERLAY", 3, WHITE, 1, frame), geom = {} }
    end
    for i = 1, SOUL_TAIL do fx.tail[i] = Glow("ARTWORK", 0) end
    for i = 1, REVIVE_WISPS do
        local puffs = {}
        for k = 1, WISP_TRAIL do puffs[k] = Glow("ARTWORK", k == 1 and 1 or 0) end
        -- Fixed per wisp: where round the ring it rises from, how late it sets off, how
        -- far out it starts, how big it is and how much it snakes, so no two match.
        fx.wisps[i] = { puffs = puffs,
                        angle  = (i / REVIVE_WISPS) * 2 * math.pi + ((i * 0.37) % 1) * 0.4,
                        delay  = ((i * 0.618) % 1) * 0.3,
                        reach  = 1.05 + ((i * 0.29) % 1) * 0.3,
                        size   = 0.75 + ((i * 0.53) % 1) * 0.5,
                        wobble = 0.25 + ((i * 0.71) % 1) * 0.3,
                        seed   = i * 1.7 }
    end
    for i = 1, MIST_PUFFS do
        fx.mist[i] = { tex = Glow("ARTWORK", 0), side = ((i * 0.437) % 1) * 2 - 1,
                       delay = ((i * 0.29) % 1) * 0.4, size = 0.8 + ((i * 0.53) % 1) * 0.6, seed = i * 2.3 }
    end
end

local function HideLines(lines) for _, l in ipairs(lines) do l:Hide() end end

local function HideFx()
    if not fx then return end
    for _, t in ipairs(fx.all) do t:Hide() end
    HideLines(fx.glow); HideLines(fx.pull)
    for _, w in ipairs(fx.waves) do HideLines(w.lines) end
end

-- A soft puff of light at (x, y) from the ring's middle, or hidden when it's too faint.
local function Puff(t, frame, x, y, s, r, g, b, a)
    if a <= 0.01 or s <= 0.5 then return t:Hide() end
    t:ClearAllPoints()
    t:SetPoint("CENTER", frame, "CENTER", x, y)
    t:SetSize(s, s)
    t:SetVertexColor(r, g, b)
    t:SetAlpha(math.min(1, a))
    t:Show()
end

-- A full ring of radius R and band T in color r, g, b at alpha a.
local function DrawBand(lines, g, geom, frame, R, T, r, gr, b, a)
    g.R, g.T, g.start, g.sweep, g.step, g.reverse = R, T, geom.start, geom.sweep, geom.step, geom.reverse
    for _, l in ipairs(lines) do l:SetColorTexture(r, gr, b, a) end
    ns.DrawArc(lines, 0, 1, frame, g, true)
end

local function DrawReviveFx(st, frame, geom)
    if not (st and st.reviveAt) or not geom or geom.R <= 0 then return HideFx() end
    if not fx then BuildFx(frame) end
    local age = GetTime() - st.reviveAt
    if age < 0 or age >= REVIVE_TIME then return HideFx() end
    local c = db.corpseColors
    local ghost, life = c.fill, c.ready
    local ri = math.max(4, geom.R - geom.T / 2) -- the hollow's radius
    local fade = 1 - Clamp01((age - (REVIVE_TIME - 0.7)) / 0.7) -- everything dims at the end
    local pr, pg, pb = Lighten(ghost, 0.55) -- the soul's own pale light
    local u = Clamp01(age / GATHER_END)     -- how far down the soul has come
    local land = Clamp01((age - GATHER_END) / 0.2) -- it sinks into the body and is gone

    -- The soul: a flickering orb drifting down into the ring, a smoky tail behind it.
    if land < 1 then
        local sx, sy = SoulPos(u, geom, ri)
        local s = ri * (1 - 0.35 * u) * (1 - land)
        local a = math.min(1, age / 0.3) * Flicker(age, 0) * (1 - land)
        Puff(fx.soulHalo, frame, sx, sy, s * 2.2, ghost.r, ghost.g, ghost.b, a * 0.45)
        Puff(fx.soul, frame, sx, sy, s, pr, pg, pb, a * 0.85)
        Puff(fx.soulCore, frame, sx, sy, s * 0.35, 1, 1, 1, a * 0.8)
        -- The tail: where it was a moment ago, smaller and fainter the further back.
        for k, t in ipairs(fx.tail) do
            local uk = u - k * 0.055
            if uk > 0 then
                local tx, ty = SoulPos(uk, geom, ri)
                local f = 1 - k / (SOUL_TAIL + 1)
                Puff(t, frame, tx, ty, s * (0.4 + 0.6 * f), ghost.r, ghost.g, ghost.b,
                    a * 0.5 * f * Flicker(age, k))
            else
                t:Hide()
            end
        end
    else
        fx.soulHalo:Hide(); fx.soul:Hide(); fx.soulCore:Hide()
        for _, t in ipairs(fx.tail) do t:Hide() end
    end

    -- Wisps: rise from round the ring and snake up into the soul, each trailing smoke.
    -- Each puff of a wisp is where its head was a moment before, so the tail follows
    -- the same path.
    for _, w in ipairs(fx.wisps) do
        local span = GATHER_END - w.delay
        for k, p in ipairs(w.puffs) do
            local t = (age - w.delay - (k - 1) * 0.07) / span
            if t >= 0 and t < 1 then
                local e = EaseIn(t)
                local sx, sy = SoulPos(Clamp01((w.delay + t * span) / GATHER_END), geom, ri)
                local a0 = w.angle + 0.9 * e
                local ox, oy = math.sin(a0) * geom.R * w.reach, math.cos(a0) * geom.R * w.reach
                local wob = math.sin(t * math.pi * 3 + w.seed) * w.wobble * ri * (1 - e)
                local x = ox + (sx - ox) * e + math.cos(a0) * wob
                local y = oy + (sy - oy) * e - math.sin(a0) * wob
                local f = 1 - (k - 1) / WISP_TRAIL
                local s = ri * 0.42 * w.size * (1 - 0.5 * e) * (0.55 + 0.45 * f)
                local a = math.min(1, t / 0.2) * (1 - 0.6 * e) * f * Flicker(age, w.seed + k)
                if k == 1 then
                    Puff(p, frame, x, y, s, pr, pg, pb, a * 0.8)
                else
                    Puff(p, frame, x, y, s, ghost.r, ghost.g, ghost.b, a * 0.5)
                end
            else
                p:Hide()
            end
        end
    end

    -- Just before the soul lands, the ring draws in around it, brightening.
    local pt = (age - (GATHER_END - 0.4)) / 0.4
    if pt >= 0 and pt < 1 then
        DrawBand(fx.pull, fx.pullGeom, geom, frame, geom.R * (1.35 - 0.35 * EaseIn(pt)),
            math.max(1.5, geom.T * (0.3 + 0.7 * pt)), pr, pg, pb, 0.75 * pt)
    else
        HideLines(fx.pull)
    end

    -- The heart: a glow in the middle that gathers as the soul comes down, then beats.
    local gather = EaseIn(u)
    local pulse = Pulse(age)
    local lifeT = Clamp01((age - GATHER_END * 0.85) / 0.5)
    local hc = Mix(ghost, life, lifeT)
    local hs = ri * 2 * (0.2 + 0.8 * gather) * (1 + 0.35 * pulse)
    fx.heart:ClearAllPoints()
    fx.heart:SetPoint("CENTER", frame, "CENTER", 0, 0)
    fx.heart:SetSize(hs, hs)
    fx.heart:SetVertexColor(Lighten(hc, 0.25))
    fx.heart:SetAlpha((0.35 + 0.35 * gather + 0.3 * pulse) * fade)
    fx.heart:Show()

    -- A white core flares as the soul sinks in, and on each beat.
    local arrive = Clamp01(1 - math.abs(age - GATHER_END) / 0.2)
    local flare = math.max(arrive, pulse * 0.8)
    if flare > 0 then
        local cs = ri * (0.6 + 0.5 * flare)
        fx.core:ClearAllPoints()
        fx.core:SetPoint("CENTER", frame, "CENTER", 0, 0)
        fx.core:SetSize(cs, cs)
        fx.core:SetVertexColor(1, 1, 1)
        fx.core:SetAlpha(flare * 0.9)
        fx.core:Show()
    else
        fx.core:Hide()
    end

    -- The ring shimmers faintly in ghost light while the soul comes down, then flashes
    -- as it lands and with each beat.
    local shimmer = 0.3 * Flicker(age, 5) * (1 - lifeT) * math.min(1, age / 0.3)
    local ringFlash = math.max(shimmer, arrive * 0.7, pulse)
    if ringFlash > 0.01 then
        local r, g, b = Lighten(hc, 0.45)
        DrawBand(fx.glow, fx.glowGeom, geom, frame, geom.R, geom.T + 4, r, g, b, ringFlash * 0.85 * fade)
    else
        HideLines(fx.glow)
    end

    -- The last of the ghost rises out of the ring as mist and fades away.
    for _, m in ipairs(fx.mist) do
        local t = (age - BEATS[1] - m.delay) / 1.3
        if t >= 0 and t < 1 then
            local e = EaseOut(t)
            local x = (m.side * 0.5 + math.sin(t * math.pi * 2 + m.seed) * 0.15) * ri
            local y = ri * (-0.3 + 2.2 * e)
            Puff(m.tex, frame, x, y, ri * 0.5 * m.size * (1 + t), ghost.r, ghost.g, ghost.b,
                0.35 * math.sin(math.pi * t) * Flicker(age, m.seed))
        else
            m.tex:Hide()
        end
    end

    -- Each beat sends a wave rolling outward, thinning as it goes.
    for i, at in ipairs(BEATS) do
        local w = fx.waves[i]
        local wt = (age - at) / 0.95
        if wt >= 0 and wt < 1 then
            local r, g, b = Lighten(life, 0.2)
            DrawBand(w.lines, w.geom, geom, frame, geom.R * (1 + 0.7 * EaseOut(wt)),
                math.max(1.5, geom.T * (i == 1 and 0.9 or 0.7) * (1 - wt)), r, g, b, (1 - wt) * (i == 1 and 1 or 0.8))
        else
            for _, l in ipairs(w.lines) do l:Hide() end
        end
    end
end

-- The ring's state while the revive animation plays, `at` = when you revived.
local function ReviveState(at)
    local c = db.corpseColors
    local age = math.max(0, GetTime() - at)
    local color = Mix(c.fill, c.ready, Clamp01((age - GATHER_END * 0.85) / 0.5))
    return { title = "Your corpse", value = "", label = age < GATHER_END and "Returning..." or "Alive again!",
             labelColor = color, color = color, frac = 1, reviveAt = at, hold = 0.3 }
end

-- Clicking Resurrect at your corpse, or accepting someone's resurrect as a ghost, brings
-- you back in your own body: remember it so the animation plays once you're alive.
local function AskedToRevive()
    if UnitIsGhost("player") then reviveAsked = GetTime() end
end
if RetrieveCorpse then hooksecurefunc("RetrieveCorpse", AskedToRevive) end
if AcceptResurrect then hooksecurefunc("AcceptResurrect", AskedToRevive) end

local function XY(v)
    if type(v) == "table" and v.GetXY then return v:GetXY() end
    if type(v) == "table" then return v.x, v.y end
end

-- Distance in yards to the corpse and its bearing (radians, 0 = north, counter-
-- clockwise like GetPlayerFacing), or nil when the corpse isn't on this map.
local function CorpseVector()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = SafeCall(C_Map.GetBestMapForUnit, "player")
    if not mapID or IsSecret(mapID) then return nil end
    local px, py = XY(SafeCall(C_Map.GetPlayerMapPosition, mapID, "player"))
    local cx, cy
    if C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
        cx, cy = XY(SafeCall(C_DeathInfo.GetCorpseMapPosition, mapID))
    elseif GetCorpseMapPosition then
        cx, cy = SafeCall(GetCorpseMapPosition)
    end
    local w, h = SafeCall(C_Map.GetMapWorldSize, mapID)
    for _, v in ipairs({ px or false, py or false, cx or false, cy or false, w or false, h or false }) do
        if not v or IsSecret(v) then return nil end
    end
    if (cx == 0 and cy == 0) or w <= 0 then return nil end
    local east, north = (cx - px) * w, (py - cy) * h -- map y grows southward
    return math.sqrt(east * east + north * north), atan2(-east, north)
end

local function State(dist, bearing, facing, delay)
    local c = db.corpseColors
    local st = { title = "Your corpse", color = c.fill, markerColor = c.marker }
    if not dist then
        st.value, st.frac, st.label = "?", 0, "Not on this map"
        return st
    end
    startDist = math.max(startDist or 0, dist, 1)
    st.frac = math.max(0, math.min(1, 1 - dist / startDist))
    st.value = math.floor(dist + 0.5) .. " yd"
    if delay and delay > 0 then
        st.label = "Resurrect in " .. FormatTime(delay)
    elseif dist <= RES_RANGE then
        st.label, st.labelColor, st.color = "In range: resurrect!", c.ready, c.ready
        st.frac = 1
    else
        st.label = "to your corpse"
    end
    if bearing and facing then
        st.marker = -(bearing - facing) -- clockwise from straight ahead
    end
    return st
end

local corpseRing = CreateLiveRing({
    key = "corpse",
    read = function(now)
        now = now or GetTime()
        if not UnitIsGhost("player") then
            -- Just came back to life from a corpse run: in your own body (not at a
            -- spirit healer) if you asked to, or were standing by your corpse.
            if wasGhost and not revivedAt and db.corpseReviveFx and not UnitIsDead("player")
                and ((reviveAsked and now - reviveAsked < 10) or wasInRange) then
                revivedAt = now
            end
            startDist, wasGhost, wasInRange, reviveAsked = nil, nil, nil, nil
            if revivedAt and now - revivedAt < REVIVE_TIME then return ReviveState(revivedAt) end
            revivedAt = nil
            return nil
        end
        revivedAt, wasGhost = nil, true
        local dist, bearing = CorpseVector()
        if dist then wasInRange = dist <= RES_RANGE + 5 end
        local facing = GetPlayerFacing and SafeCall(GetPlayerFacing)
        if IsSecret(facing) then facing = nil end
        local delay = GetCorpseRecoveryDelay and SafeCall(GetCorpseRecoveryDelay)
        if IsSecret(delay) then delay = nil end
        return State(dist, bearing, facing, delay)
    end,
    sample = function(t)
        -- Walking back: 420 yards down to in range, the corpse drifting to the right,
        -- then (with the revive animation on) back into your body.
        local cycle = t % 16
        if cycle >= 12 and db.corpseReviveFx then return ReviveState(GetTime() - (cycle - 12)) end
        cycle = math.min(cycle, 12)
        local dist = math.max(20, 420 - cycle * 40)
        startDist = 420
        return State(dist, -0.6 - cycle * 0.05, 0, cycle < 2 and (2 - cycle) * 8 or 0)
    end,
    decorate = DrawReviveFx,
})

local function PreviewCorpseRing() corpseRing.Preview(16) end

-- Shared with the files loaded after this one.
ns.corpseRing = corpseRing
ns.PreviewCorpseRing = PreviewCorpseRing

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "corpse", name = "Corpse", order = 10,
    ring = corpseRing,
    preview = PreviewCorpseRing, slash = { "corpse", "ghost" }, help = "preview the corpse ring",
    toggle = { "Corpse ring", "Distance and direction to your corpse while you're a ghost." },
    defaults = {
        -- Corpse ring: distance (and direction) to your body while you're a ghost.
        corpseEnabled   = true,
        corpseReviveFx  = true, -- the revive animation when you're back in your body
        corpseSize      = 130,
        corpseThickness = 12,
        corpseOpacity   = 100,
        corpseX         = -170, -- left of the crafting ring
        corpseFromTop   = 250,
        corpseHold      = 0,
        corpseStyle     = "smooth",
        corpseBorder    = 2, -- black border width (0 = none)
        corpseColors = {
            fill   = { r = 0.60, g = 0.75, b = 0.95 },
            ready  = { r = 0.30, g = 0.90, b = 0.40 },
            marker = { r = 1.00, g = 0.95, b = 0.60 },
        },
    },
    page = { folder = "status", order = 3, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(10, "Corpse", "Corpse Ring",
                "While you're a ghost: how far your corpse is (filling as you get closer), an arrow on the ring pointing "
                .. "toward it (straight up = ahead), and when you can resurrect.",
                MergeTop(TopRow("corpse", "corpse ring", ns.PreviewCorpseRing,
                    "Show a sample corpse run. Also /circ corpse."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "corpseEnabled", "Show corpse ring", "Show the ring while you're a ghost."),
                        reviveFx = Toggle(2, "corpseReviveFx", "Revive animation",
                            "When you come back to life in your own body, your soul drifts down into the ring "
                            .. "with wisps of ghost light streaming into it, a heartbeat thumps out, and the last "
                            .. "of the ghost rises away as mist. Not at a spirit healer."),
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "corpseColors", "fill", "Distance", "Ring color on the way back."),
                        ready = Color(2, "corpseColors", "ready", "In range", "Ring color once you can resurrect."),
                        marker = Color(3, "corpseColors", "marker", "Direction arrow", "Tint of the arrow pointing at your corpse."),
                    }),
                    size = SizeBox(4, "corpse", "corpse ring", "Offset from the center of the screen."),
                }))
            tab.args.size.args.hold = nil
            return tab
        end },
})
