-- Circlet: Health ring effects on the ring itself: combo points, raid marker, aggro, low health, death, heals, jolts, dodges, energy, rage, mana.
local _, ns = ...

local SafeCall, Clean, CleanNumber, IsSecret = ns.SafeCall, ns.Clean, ns.CleanNumber, ns.IsSecret
local FX = ns.HealthFx
local TEX = FX.TEX
local GLOW = FX.GLOW
local STAR = FX.STAR
local SOFT = FX.SOFT
local DISC = FX.DISC
local SKULL = FX.SKULL
local SWORDS = FX.SWORDS
local BadgeAngle = FX.BadgeAngle
local Since = FX.Since
local Tex = FX.Tex
local At = FX.At
local Polar = FX.Polar
local GlowOn = FX.GlowOn
local Curve = FX.Curve
local HealthUnder = FX.HealthUnder
local Gate = FX.Gate

---------------------------------------------------------------------------
-- The effects
---------------------------------------------------------------------------
local function ComboPoints()
    local _, class = SafeCall(UnitClass, "player")
    if class ~= "ROGUE" and class ~= "DRUID" then return nil end
    local cp = CleanNumber(SafeCall(GetComboPoints, "player", "target"))
    if cp == nil and UnitPower and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
        cp = CleanNumber(SafeCall(UnitPower, "player", Enum.PowerType.ComboPoints))
    end
    return cp
end

local function DrawCombo(key, fx, st, frame, geom, d, now)
    local cp = st.unit and ComboPoints() or (not st.unit and 3) -- previews: three
    if not cp or cp <= 0 then
        fx.cpLast = 0
        return
    end -- like the game: only once you have some
    fx.cpLast = fx.cpLast or 0
    if cp > fx.cpLast then fx.cpPop = now end
    fx.cpLast = cp
    local pd = math.max(6, math.floor(geom.T * 1.15 + 0.5))
    local r = geom.R + geom.T / 2 + pd * 0.75
    local full = cp >= 5
    local pulse = full and (0.75 + 0.25 * math.sin(now * 8)) or 1
    for i = 1, 5 do
        local x, y = Polar(90 + (3 - i) * 12, r)
        local edge = Tex(fx, "cpE" .. i, DISC, "ARTWORK", 1)
        At(edge, frame, x, y, pd)
        edge:SetVertexColor(0, 0, 0, 0.85)
        local pip = Tex(fx, "cpP" .. i, DISC, "ARTWORK", 2)
        local lit = i <= cp
        local pop = (lit and i == cp and fx.cpPop) and math.max(0, 1 - (now - fx.cpPop) / 0.25) or 0
        At(pip, frame, x, y, (pd - 3) * (1 + 0.5 * pop))
        if not lit then
            pip:SetVertexColor(0.22, 0.12, 0.10, 1)
        elseif full then
            pip:SetVertexColor(1, 0.80, 0.25, 1)
        else
            pip:SetVertexColor(1, 0.30, 0.12, 1)
        end
        pip:SetAlpha(lit and pulse or 1)
        local glow = Tex(fx, "cpG" .. i, SOFT, "ARTWORK", 3, true)
        if lit then
            At(glow, frame, x, y, pd * (1.8 + pop))
            if full then
                glow:SetVertexColor(1, 0.75, 0.2)
            else
                glow:SetVertexColor(1, 0.35, 0.1)
            end
            glow:SetAlpha(0.6 * pulse)
        else
            glow:Hide()
        end
    end
end

-- The raid marker. This client hides it from addons (a secret, even out of combat), and a
-- curve won't take a hidden value from addon code, so it can't be gated that way. But
-- SetSpriteSheetCell takes a hidden cell: the marker sheet is 4x4 with the eight icons as
-- cells 1-8, so the hidden index picks its own icon without Circlet ever knowing which (it's
-- how Blizzard's target frame draws it now). No marker comes back as nil.
local MARK_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

local function DrawMark(key, fx, st, frame, geom, d)
    local raw
    if st.unit then
        raw = SafeCall(GetRaidTargetIndex, st.unit)
    else
        raw = 8
    end -- previews: a skull
    if not IsSecret(raw) then -- (never compare a hidden one, not even to nil)
        local idx = raw ~= nil and CleanNumber(raw)
        if not idx or idx < 1 or idx > 8 then return end
    end
    local t = Tex(fx, "mark", MARK_SHEET, "OVERLAY", 2)
    if not (t.SetSpriteSheetCell and pcall(t.SetSpriteSheetCell, t, raw, 4, 4)) then
        t:Hide()
        return
    end
    local x, y = Polar(BadgeAngle(key, "Mark"), geom.R)
    t:SetAlpha(1)
    At(t, frame, x, y, d * 1.25)
end

local function DrawAggro(key, fx, st, frame, geom, d, now)
    local on
    if st.unit then
        on = Clean(SafeCall(UnitCanAttack, "player", st.unit))
            and Clean(SafeCall(UnitIsUnit, st.unit .. "target", "player"))
    else
        on = true -- previews
    end
    if not on then return end
    local pulse = 0.55 + 0.45 * math.abs(math.sin(now * 3))
    local glow = Tex(fx, "aggroHalo", GLOW, "BACKGROUND", -8, true, frame)
    GlowOn(glow, frame, geom.R + geom.T * 0.3)
    glow:SetVertexColor(1, 0.12, 0.08)
    glow:SetAlpha(0.5 * pulse)
end

-- A glow gated by a hidden or readable threshold, pulsing. These halos sit under the ring
-- (on a frame of their own a level below the ring's), so they glow round the band without
-- washing it out. The gate goes in the texture's alpha (it may be hidden) and nothing else
-- touches that; the pulse goes in the frame's alpha. (Putting the pulse in the texture's
-- vertex color instead showed the glow whatever the gate said.)
local function DrawThreshold(fx, name, frame, r, gate, color, alpha)
    local f = fx.frames[name]
    if not f then
        f = CreateFrame("Frame", nil, frame)
        f:SetAllPoints(frame)
        fx.frames[name] = f
    end
    local level = math.max(0, frame:GetFrameLevel() - 1)
    if f:GetFrameLevel() ~= level then f:SetFrameLevel(level) end
    local t = Tex(fx, name .. "Halo", GLOW, "BACKGROUND", 0, true, f)
    if not Gate(t, gate) then
        f:Hide()
        return
    end
    GlowOn(t, frame, r)
    t:SetVertexColor(color[1], color[2], color[3])
    f:SetAlpha(alpha)
    f:Show()
end

local function DrawExecute(key, fx, st, frame, geom, d, now)
    local gate = HealthUnder(st, 0.20) -- may be hidden: not tested here, only passed on
    local pulse = 0.5 + 0.5 * math.abs(math.sin(now * 5))
    DrawThreshold(fx, "execute", frame, geom.R + geom.T * 0.3, gate, { 1, 0.35, 0.08 }, 0.3 + 0.5 * pulse)
end

local function DrawLowHealth(key, fx, st, frame, geom, d, now)
    local gate = HealthUnder(st, 0.30)
    -- Lub-dub: two beats a second, the second softer.
    local ph = now % 1
    local beat = math.max(
        math.exp(-((ph - 0.0) / 0.07) ^ 2),
        0.6 * math.exp(-((ph - 0.22) / 0.07) ^ 2),
        math.exp(-((ph - 1.0) / 0.07) ^ 2)
    )
    DrawThreshold(fx, "low", frame, geom.R + geom.T * 0.3, gate, { 1, 0.08, 0.05 }, 0.25 + 0.6 * beat)
end

local function DrawDeath(key, fx, st, frame, geom, d, now)
    if not st.dead then
        fx.deadAt = nil
        return
    end
    fx.deadAt = fx.deadAt or now
    local a = math.min(1, (now - fx.deadAt) / 0.5)
    if st.dead == "Ghost" then
        local glow = Tex(fx, "ghost", GLOW, "BACKGROUND", 3, true)
        GlowOn(glow, frame, geom.R)
        glow:SetVertexColor(0.6, 0.85, 1)
        glow:SetAlpha(a * (0.45 + 0.2 * math.sin(now * 1.6)))
        for i = 1, 6 do
            local w = Tex(fx, "wisp" .. i, SOFT, "OVERLAY", 1, true)
            local u = (now * 0.35 + i / 6) % 1
            local x, y = Polar(60 + i * 10 + math.sin(now + i) * 8, geom.R)
            At(w, frame, x + math.sin(now * 2 + i) * geom.T * 0.5, y + u * geom.R * 0.8, geom.T * 1.4 * (1 - u * 0.5))
            w:SetVertexColor(0.75, 0.9, 1)
            w:SetAlpha(a * math.min(1, u * 5) * (1 - u) * 0.8)
        end
        return
    end
    local veil = Tex(fx, "veil", GLOW, "OVERLAY", 0)
    GlowOn(veil, frame, geom.R)
    veil:SetVertexColor(0, 0, 0)
    veil:SetAlpha(0.55 * a)
    local cracks = Tex(fx, "cracks", TEX .. "Cracks", "OVERLAY", 1)
    GlowOn(cracks, frame, geom.R)
    cracks:SetVertexColor(0.08, 0.06, 0.06)
    cracks:SetAlpha(a)
    -- A big faded skull filling the middle: over the portrait, under the "Dead" text (on the
    -- ring frame's background layer, a level above the portrait), settling in as it fades up.
    local skull = Tex(fx, "skull", SKULL, "BACKGROUND", 3, false, frame)
    local size = math.max(d, (geom.R - geom.T) * 1.55)
    At(skull, frame, 0, 0, size * (1 + 0.25 * (1 - a)))
    skull:SetVertexColor(0.9, 0.88, 0.85)
    skull:SetAlpha(0.38 * a)
end

local function DrawFlare(key, fx, st, frame, geom, d, now)
    local s = Since(key, "flare")
    if s > 0.8 then return end
    local u = s / 0.8
    local t = Tex(fx, "flare", GLOW, "OVERLAY", 4, true)
    GlowOn(t, frame, geom.R * (1 + 0.6 * (1 - (1 - u) ^ 2)))
    t:SetVertexColor(1, 0.78, 0.25)
    t:SetAlpha(1 - u)
end

local function DrawHeal(key, fx, st, frame, geom, d, now)
    local s = Since(key, "heal")
    if s > 0.8 then return end
    local u = s / 0.8
    for i = 1, 8 do
        local side = i % 2 == 0 and 1 or -1
        local lag = math.floor((i - 1) / 2) * 0.06
        local p = math.max(0, math.min(1, (u - lag) / 0.75))
        local t = Tex(fx, "heal" .. i, STAR, "OVERLAY", 5, true)
        if p > 0 and p < 1 then
            local x, y = Polar(270 + side * p * 180, geom.R)
            At(t, frame, x, y, geom.T * (2.2 - p))
            t:SetVertexColor(0.4, 1, 0.45)
            t:SetAlpha(math.sin(p * math.pi))
            if t.SetRotation then t:SetRotation(now * 4 + i) end
        else
            t:Hide()
        end
    end
end

-- Jolt: the ring nudged about for a quarter second. Its one anchor's offset is read, shaken
-- round, and put back exactly (never zeroed: that offset is where the ring lives). If the
-- ring is laid out again mid-jolt, its new spot becomes the one to shake round and restore.
local function Restore(fx, frame)
    local j = fx.jolt
    fx.jolt = nil
    if not j then return end
    local p, rel, rp, x, y = frame:GetPoint(1)
    if p and x == j.sx and y == j.sy then -- still where we put it: back to its own spot
        frame:SetPoint(p, rel, rp, j.bx, j.by)
    end
end

local function DrawJolt(key, fx, st, frame, geom, now)
    local s = Since(key, "jolt")
    if s >= 0.25 or frame:GetNumPoints() ~= 1 then return Restore(fx, frame) end
    local p, rel, rp, x, y = frame:GetPoint(1)
    if not (p and type(x) == "number" and type(y) == "number") then return Restore(fx, frame) end
    local j = fx.jolt
    if not j or x ~= j.sx or y ~= j.sy then -- starting, or moved by its layout: shake round here
        j = { bx = x, by = y }
        fx.jolt = j
    end
    local amp = geom.T * 0.45 * (1 - s / 0.25)
    j.sx, j.sy = j.bx + math.sin(s * 90) * amp, j.by + math.cos(s * 70) * amp * 0.6
    frame:SetPoint(p, rel, rp, j.sx, j.sy)
end

local function DrawAvoid(key, fx, st, frame, geom, d, now)
    -- Block: a shield popping up at the left of the ring.
    local sb = Since(key, "block")
    local t = Tex(fx, "shield", TEX .. "Shield", "OVERLAY", 4)
    if sb < 0.7 then
        local u = sb / 0.7
        local x, y = Polar(180, geom.R + geom.T)
        At(t, frame, x, y, d * (1.1 + 0.5 * math.max(0, 1 - u / 0.2)))
        t:SetVertexColor(0.85, 0.88, 0.95)
        t:SetAlpha(u < 0.7 and 1 or (1 - u) / 0.3)
    else
        t:Hide()
    end
    -- Dodge: streaks whooshing a quarter of the way round the outside.
    local sd = Since(key, "dodge")
    for i = 1, 3 do
        local w = Tex(fx, "whoosh" .. i, SOFT, "OVERLAY", 4, true)
        if sd < 0.45 then
            local u = sd / 0.45
            local deg = 200 - u * 110 - i * 9
            local x, y = Polar(deg, geom.R + geom.T * (0.8 + i * 0.25))
            At(w, frame, x, y, geom.T * 3.2, geom.T * 1.1)
            if w.SetRotation then w:SetRotation(math.rad(deg - 90)) end
            w:SetVertexColor(0.9, 0.97, 1)
            w:SetAlpha((1 - u) * (1 - i * 0.2))
        else
            w:Hide()
        end
    end
    -- Parry: crossed blades flashing at the right.
    local sp = Since(key, "parry")
    local blades = Tex(fx, "blades", SWORDS, "OVERLAY", 4)
    if sp < 0.6 then
        if not fx.bladesCoord then
            fx.bladesCoord = true
            blades:SetTexCoord(0.5, 1, 0, 0.5)
        end
        local u = sp / 0.6
        local x, y = Polar(0, geom.R + geom.T)
        At(blades, frame, x, y, d * (1.2 + 0.6 * math.max(0, 1 - u / 0.15)))
        blades:SetAlpha(u < 0.6 and 1 or (1 - u) / 0.4)
    else
        blades:Hide()
    end
end

-- Energy ticks: every two seconds from the last one seen.
FX.tickAt, FX.lastCastAt = nil, 0
local function DrawEnergyTick(key, fx, st, frame, g2, now)
    if not (st.power and st.power.token == "ENERGY") then return end
    local at = FX.tickAt or (not st.unit and now - (now % 2)) -- previews: a made-up beat
    if not at then return end
    local u = ((now - at) % 2) / 2
    local x, y = ns.RingPoint(g2, u)
    local spark = Tex(fx, "tick", STAR, "OVERLAY", 5, true)
    At(spark, frame, x, y, g2.T * 3)
    spark:SetVertexColor(1, 0.95, 0.5)
    if spark.SetRotation then spark:SetRotation(now * 3) end
    local halo = Tex(fx, "tickHalo", SOFT, "OVERLAY", 4, true)
    At(halo, frame, x, y, g2.T * 4)
    halo:SetVertexColor(1, 0.85, 0.3)
    halo:SetAlpha(0.6)
    -- The tick itself: the band flashes.
    local flash = Tex(fx, "tickFlash", GLOW, "OVERLAY", 3, true)
    if u < 0.12 then
        GlowOn(flash, frame, g2.R)
        flash:SetVertexColor(1, 0.9, 0.4)
        flash:SetAlpha((1 - u / 0.12) * 0.7)
    else
        flash:Hide()
    end
end

-- Rage embers: a burst off the rage band with each rage gain.
local embers = {}
local function DrawRage(key, fx, st, frame, g2, now)
    if not (st.power and st.power.token == "RAGE") then return end
    if not st.unit and now - (fx.sampleEmber or 0) > 0.7 then -- previews: a gain now and then
        fx.sampleEmber = now
        ns.VitalsFxRage()
    end
    for i, e in ipairs(embers) do
        local t = Tex(fx, "ember" .. i, STAR, "OVERLAY", 5, true)
        local u = (now - e.at) / 0.9
        if u >= 0 and u < 1 then
            local x, y = Polar(e.deg, g2.R + u * g2.T * 6)
            At(t, frame, x + e.drift * u * g2.T * 2, y + u * u * g2.T * 4, g2.T * 1.8 * (1 - 0.5 * u))
            t:SetVertexColor(1, 0.55 - 0.35 * u, 0.1)
            t:SetAlpha(1 - u)
        else
            t:Hide()
        end
    end
end
local nextEmber = 0
function ns.VitalsFxRage()
    local now = GetTime()
    for _ = 1, 4 do
        nextEmber = nextEmber % 16 + 1
        embers[nextEmber] = { at = now + math.random() * 0.1, deg = math.random() * 360, drift = math.random() - 0.5 }
    end
end

local function DrawFullMana(key, fx, st, frame, g2, now)
    local p = st.power
    if not (p and p.token == "MANA") then return end
    local gate
    if type(p.real) == "number" and not IsSecret(p.real) then
        gate = p.real >= 0.995
    elseif not st.unit then
        gate = true
    elseif type(UnitPowerPercent) == "function" and ns.VitalsCurves.Work() then
        local ok, v = pcall(UnitPowerPercent, st.unit, 0, false, Curve(0.995, 0, 1))
        if ok then gate = v end
    end
    DrawThreshold(fx, "fullMana", frame, g2.R, gate, { 0.55, 0.75, 1 }, 0.35 + 0.25 * math.sin(now * 1.5))
end

-- For the files loaded after this one.
FX.DrawCombo = DrawCombo
FX.DrawMark = DrawMark
FX.DrawAggro = DrawAggro
FX.DrawExecute = DrawExecute
FX.DrawLowHealth = DrawLowHealth
FX.DrawDeath = DrawDeath
FX.DrawFlare = DrawFlare
FX.DrawHeal = DrawHeal
FX.Restore = Restore
FX.DrawJolt = DrawJolt
FX.DrawAvoid = DrawAvoid
FX.DrawEnergyTick = DrawEnergyTick
FX.DrawRage = DrawRage
FX.DrawFullMana = DrawFullMana
