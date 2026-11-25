-- Circlet: effects on the health & power rings (Rings/Vitals.lua draws them each frame).
local ADDON_NAME, ns = ...

local db, SafeCall, Clean, CleanNumber, IsSecret = ns.db, ns.SafeCall, ns.Clean, ns.CleanNumber, ns.IsSecret

---------------------------------------------------------------------------
-- Health ring effects
---------------------------------------------------------------------------
-- Each one has its own setting, <key>Fx<Name>, on the rings it suits (all on by default):
--
--   Combo      (target)   five pips over the ring for your combo points, popping as they
--                         light, the lot pulsing gold at five (rogues and druids)
--   Mark       (all)      the unit's raid marker (skull, cross, star...) at its top left
--   Aggro      (target)   a red glare round the ring while the target is targeting you
--   Execute    (target)   the ring throbs red-orange below 20% health
--   LowHealth  (yours)    a red heartbeat (lub-dub) below 30% health
--   Death      (all)      dead: the ring cracks and darkens, a skull over it; your ghost: a
--                         pale glow with wisps drifting up
--   Flare      (yours)    a gold ring bursting outward as combat starts
--   Heal       (yours, target) green sparkles racing up both sides when a heal lands
--   Jolt       (yours, target) the ring jolts on a critical or crushing hit
--   Avoid      (yours, target) a shield on a block, a whoosh round the ring on a dodge,
--                         crossed blades on a parry
--   EnergyTick (yours)    a spark running round the energy band, once per energy tick
--   Rage       (yours)    embers flying off the rage band as rage comes in
--   FullMana   (yours)    a soft shine on the mana band while it's full
--   Elite      (target, target of target) a glint circling elite rings (silver for rares)
--
-- What the game hides from addons in combat shapes some of them. Health and power can be
-- hidden: thresholds (20%, 30%, full) are checked by running the hidden percentage through
-- a step curve, whose hidden 0 or 1 goes straight into a texture's SetAlpha (the way the
-- rings fill; see Rings/Vitals.lua), with the pulse on its parent frame. The size of a rage
-- gain can't be read, so embers come with each gain, not by its size. Energy ticks every
-- two seconds; with energy hidden, a tick is any energy change that isn't one of your casts.

local TEX = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\"
local GLOW = TEX .. "GlowRing"       -- a soft band peaking at 0.70 of its half-width
local GLOW_AT = 0.70
local STAR = "Interface\\Cooldown\\star4"
local SOFT = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local SWORDS = "Interface\\CharacterFrame\\UI-StateIcon"
local MARKS = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

local ON = {
    Combo = { targetHp = true }, Mark = { playerHp = true, targetHp = true, totHp = true },
    Aggro = { targetHp = true }, Execute = { targetHp = true }, LowHealth = { playerHp = true },
    Death = { playerHp = true, targetHp = true, totHp = true }, Flare = { playerHp = true },
    Heal = { playerHp = true, targetHp = true }, Jolt = { playerHp = true, targetHp = true },
    Avoid = { playerHp = true, targetHp = true }, EnergyTick = { playerHp = true }, Rage = { playerHp = true },
    FullMana = { playerHp = true }, Elite = { targetHp = true, totHp = true },
}
ns.VITALS_FX = ON

local function On(key, name) return ON[name][key] and db[key .. "Fx" .. name] end

-- Event times, by ring key.
local hits = {}   -- key -> { heal = t, jolt = t, block = t, dodge = t, parry = t, flare = t }
local function Mark(key, what) hits[key] = hits[key] or {}; hits[key][what] = GetTime() end
local function Since(key, what) local h = hits[key] return h and h[what] and GetTime() - h[what] or math.huge end
ns.VitalsFxMark = Mark -- tests and previews

---------------------------------------------------------------------------
-- Pieces: textures on a frame over the ring, made when first needed
---------------------------------------------------------------------------
local function Pieces(v, frame)
    if v.fx then return v.fx end
    local fx = { t = {}, frames = {} }
    fx.root = CreateFrame("Frame", nil, frame)
    fx.root:SetAllPoints(frame)
    fx.root:SetFrameLevel(frame:GetFrameLevel() + 6)
    v.fx = fx
    return fx
end

-- A frame of its own (for effects whose alpha is gated by a hidden value: the gate on the
-- texture, the pulse on this frame).
local function Sub(fx, name)
    local f = fx.frames[name]
    if not f then
        f = CreateFrame("Frame", nil, fx.root)
        f:SetAllPoints(fx.root)
        fx.frames[name] = f
    end
    return f
end

local function Tex(fx, name, file, layer, sub, add, parent)
    local t = fx.t[name]
    if not t then
        t = (parent or fx.root):CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
        t:SetTexture(file)
        if add then t:SetBlendMode("ADD") end
        fx.t[name] = t
    end
    t.used = true
    return t
end

local function At(t, frame, x, y, w, h)
    t:ClearAllPoints()
    t:SetPoint("CENTER", frame, "CENTER", x, y)
    t:SetSize(w, h or w)
    t:Show()
end

-- x, y at <deg> degrees (0 = right, counter-clockwise) and radius r.
local function Polar(deg, r) local a = math.rad(deg) return r * math.cos(a), r * math.sin(a) end

-- A glow ring texture sized to sit on a ring of radius r.
local function GlowOn(t, frame, r, x, y) At(t, frame, x or 0, y or 0, 2 * r / GLOW_AT) end

---------------------------------------------------------------------------
-- Hidden thresholds
---------------------------------------------------------------------------
local curves = {}
-- A step curve: <below> under t (a fraction), <above> from t on.
local function Curve(t, below, above)
    local k = t .. ":" .. below .. ":" .. above
    if curves[k] then return curves[k] end
    local scale = ns.VitalsCurves and ns.VitalsCurves.Scale() or 1
    local cv = C_CurveUtil.CreateCurve()
    if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then pcall(cv.SetType, cv, Enum.LuaCurveType.Step) end
    cv:AddPoint(0, below)
    cv:AddPoint(t * scale, above)
    curves[k] = cv
    return cv
end

-- Whether the unit's health is under t: true / false when readable, or the hidden 0/1 (a
-- secret, for SetAlpha), or nil if this client can't tell.
local function HealthUnder(st, t)
    if st.dead then return false end
    if st.hpFrac then return st.hpFrac < t end
    if not (st.unit and type(UnitHealthPercent) == "function" and ns.VitalsCurves and ns.VitalsCurves.Work()) then return nil end
    local ok, v = pcall(UnitHealthPercent, st.unit, false, Curve(t, 1, 0))
    if ok then return v end
end

-- Puts a gate (true/false or a hidden 0/1) on a texture's alpha; false if it's plainly off.
-- A hidden value can't be compared or tested, so it's checked for first and passed on.
local function Gate(t, g)
    if IsSecret(g) then
        if not pcall(t.SetAlpha, t, g) then t:Hide() return false end
        t:Show()
        return true
    end
    if g == true or (type(g) == "number" and g > 0) then
        t:SetAlpha(type(g) == "number" and g or 1)
        t:Show()
        return true
    end
    t:Hide()
    return false
end

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
    if not cp or cp <= 0 then fx.cpLast = 0 return end -- like the game: only once you have some
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
        if not lit then pip:SetVertexColor(0.22, 0.12, 0.10, 1)
        elseif full then pip:SetVertexColor(1, 0.80, 0.25, 1)
        else pip:SetVertexColor(1, 0.30, 0.12, 1) end
        pip:SetAlpha(lit and pulse or 1)
        local glow = Tex(fx, "cpG" .. i, SOFT, "ARTWORK", 3, true)
        if lit then
            At(glow, frame, x, y, pd * (1.8 + pop))
            if full then glow:SetVertexColor(1, 0.75, 0.2) else glow:SetVertexColor(1, 0.35, 0.1) end
            glow:SetAlpha(0.6 * pulse)
        else
            glow:Hide()
        end
    end
end

-- The raid marker. This client hides it from addons (a secret, even out of combat), so it
-- can't be read to pick the icon. Instead all eight icons sit in the same spot, each with a
-- step curve that's 1 only at its own index: the hidden index runs through each curve and the
-- hidden 0 or 1 goes straight into that icon's alpha, so only the right one shows, without
-- Circlet ever knowing which (as the rings fill with hidden health). Readable: just the one.
local markCurves = {}
local function MarkCurve(i)
    if markCurves[i] then return markCurves[i] end
    local cv = C_CurveUtil.CreateCurve()
    if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then pcall(cv.SetType, cv, Enum.LuaCurveType.Step) end
    cv:AddPoint(0, 0)
    cv:AddPoint(i - 0.5, 1)
    cv:AddPoint(i + 0.5, 0)
    markCurves[i] = cv
    return cv
end

local function DrawMark(key, fx, st, frame, geom, d)
    local raw
    if st.unit then raw = SafeCall(GetRaidTargetIndex, st.unit) else raw = 8 end -- previews: a skull
    local x, y = Polar(135, geom.R)
    if IsSecret(raw) then
        if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return end
        for i = 1, 8 do
            local t = Tex(fx, "mark" .. i, MARKS:format(i), "OVERLAY", 2)
            local ok, a = pcall(function() return MarkCurve(i):Evaluate(raw) end)
            if ok and pcall(t.SetAlpha, t, a) then
                At(t, frame, x, y, d * 1.25)
            else
                t:Hide()
            end
        end
        return
    end
    local idx = CleanNumber(raw)
    if not idx or idx < 1 or idx > 8 then return end
    local t = Tex(fx, "mark", MARKS:format(idx), "OVERLAY", 2)
    if fx.markIdx ~= idx then fx.markIdx = idx; t:SetTexture(MARKS:format(idx)) end
    t:SetAlpha(1)
    At(t, frame, x, y, d * 1.25)
end

local function DrawAggro(key, fx, st, frame, geom, d, now)
    local on
    if st.unit then
        on = Clean(SafeCall(UnitCanAttack, "player", st.unit)) and Clean(SafeCall(UnitIsUnit, st.unit .. "target", "player"))
    else
        on = true -- previews
    end
    if not on then return end
    local pulse = 0.55 + 0.45 * math.abs(math.sin(now * 3))
    local glow = Tex(fx, "aggroGlow", GLOW, "BACKGROUND", 1, true)
    GlowOn(glow, frame, geom.R + geom.T * 0.3)
    glow:SetVertexColor(1, 0.12, 0.08)
    glow:SetAlpha(0.6 * pulse)
end

-- A glow gated by a hidden or readable threshold, pulsing on its own frame.
local function DrawThreshold(fx, name, frame, r, gate, color, alpha)
    local f = Sub(fx, name)
    local t = Tex(fx, name, GLOW, "BACKGROUND", 2, true, f)
    if not Gate(t, gate) then f:Hide() return end
    GlowOn(t, frame, r)
    t:SetVertexColor(color[1], color[2], color[3])
    f:SetAlpha(alpha)
    f:Show()
end

local function DrawExecute(key, fx, st, frame, geom, d, now)
    local gate = HealthUnder(st, 0.20) -- may be hidden: not tested here, only passed on
    local pulse = 0.5 + 0.5 * math.abs(math.sin(now * 5))
    DrawThreshold(fx, "execute", frame, geom.R, gate, { 1, 0.35, 0.08 }, 0.35 + 0.65 * pulse)
end

local function DrawLowHealth(key, fx, st, frame, geom, d, now)
    local gate = HealthUnder(st, 0.30)
    -- Lub-dub: two beats a second, the second softer.
    local ph = now % 1
    local beat = math.max(math.exp(-((ph - 0.0) / 0.07) ^ 2), 0.6 * math.exp(-((ph - 0.22) / 0.07) ^ 2),
        math.exp(-((ph - 1.0) / 0.07) ^ 2))
    DrawThreshold(fx, "low", frame, geom.R, gate, { 1, 0.08, 0.05 }, 0.25 + 0.75 * beat)
end

local function DrawDeath(key, fx, st, frame, geom, d, now)
    if not st.dead then fx.deadAt = nil return end
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
    local skull = Tex(fx, "skull", SKULL, "OVERLAY", 3)
    local x, y = Polar(90, geom.R + geom.T)
    At(skull, frame, x, y, d * 1.2 * (1 + 0.4 * (1 - a)))
    skull:SetAlpha(a)
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
        if not fx.bladesCoord then fx.bladesCoord = true; blades:SetTexCoord(0.5, 1, 0, 0.5) end
        local u = sp / 0.6
        local x, y = Polar(0, geom.R + geom.T)
        At(blades, frame, x, y, d * (1.2 + 0.6 * math.max(0, 1 - u / 0.15)))
        blades:SetAlpha(u < 0.6 and 1 or (1 - u) / 0.4)
    else
        blades:Hide()
    end
end

-- Energy ticks: every two seconds from the last one seen.
local tickAt, lastCastAt = nil, 0
local function DrawEnergyTick(key, fx, st, frame, g2, now)
    if not (st.power and st.power.token == "ENERGY") then return end
    local at = tickAt or (not st.unit and now - (now % 2)) -- previews: a made-up beat
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
    if type(p.real) == "number" and not IsSecret(p.real) then gate = p.real >= 0.995
    elseif not st.unit then gate = true
    elseif type(UnitPowerPercent) == "function" and ns.VitalsCurves.Work() then
        local ok, v = pcall(UnitPowerPercent, st.unit, 0, false, Curve(0.995, 0, 1))
        if ok then gate = v end
    end
    DrawThreshold(fx, "fullMana", frame, g2.R, gate, { 0.55, 0.75, 1 }, 0.35 + 0.25 * math.sin(now * 1.5))
end

local GLINT = { elite = { 1, 0.82, 0.35 }, worldboss = { 1, 0.82, 0.35 }, rareelite = { 0.85, 0.9, 1 }, rare = { 0.85, 0.9, 1 } }
local function DrawElite(key, fx, st, frame, geom, now)
    local class = st.unit and Clean(SafeCall(UnitClassification, st.unit)) or (not st.unit and "elite")
    local c = GLINT[class or ""]
    if not c then return end
    for i = 1, 2 do
        local deg = 90 - (now * 40 + (i - 1) * 180) % 360
        local x, y = Polar(deg, geom.R)
        local glow = Tex(fx, "glint" .. i, SOFT, "OVERLAY", 5, true)
        At(glow, frame, x, y, geom.T * 2.6)
        glow:SetVertexColor(c[1], c[2], c[3])
        glow:SetAlpha(0.7)
        local star = Tex(fx, "glintS" .. i, STAR, "OVERLAY", 6, true)
        At(star, frame, x, y, geom.T * 2)
        star:SetVertexColor(c[1], c[2], c[3])
        if star.SetRotation then star:SetRotation(now * 2) end
    end
end

---------------------------------------------------------------------------
-- Each frame
---------------------------------------------------------------------------
function ns.DrawVitalsFx(key, v, st, frame, geom, d, now)
    local fx = Pieces(v, frame)
    for _, t in pairs(fx.t) do t.used = false end
    for _, f in pairs(fx.frames) do f.used = false end
    fx.root:Show()
    if On(key, "Death") then DrawDeath(key, fx, st, frame, geom, d, now) end
    if not st.dead then
        if On(key, "Combo") then DrawCombo(key, fx, st, frame, geom, d, now) end
        if On(key, "Aggro") then DrawAggro(key, fx, st, frame, geom, d, now) end
        if On(key, "Execute") then DrawExecute(key, fx, st, frame, geom, d, now) end
        if On(key, "LowHealth") then DrawLowHealth(key, fx, st, frame, geom, d, now) end
        if On(key, "Heal") then DrawHeal(key, fx, st, frame, geom, d, now) end
        if On(key, "Avoid") then DrawAvoid(key, fx, st, frame, geom, d, now) end
        if On(key, "Elite") then DrawElite(key, fx, st, frame, geom, now) end
        if v.g2 and v.g2.R and st.power then
            if On(key, "EnergyTick") then DrawEnergyTick(key, fx, st, frame, v.g2, now) end
            if On(key, "Rage") then DrawRage(key, fx, st, frame, v.g2, now) end
            if On(key, "FullMana") then DrawFullMana(key, fx, st, frame, v.g2, now) end
        end
    end
    if On(key, "Mark") then DrawMark(key, fx, st, frame, geom, d) end
    if On(key, "Flare") then DrawFlare(key, fx, st, frame, geom, d, now) end
    DrawJolt(key, fx, st, frame, geom, now) -- always called: it puts the ring back after a jolt
    -- Anything not drawn this frame goes.
    for name, t in pairs(fx.t) do
        if not t.used then t:Hide() end
    end
    for _, f in pairs(fx.frames) do
        local any = false
        for _, t in pairs(fx.t) do if t.used and t:GetParent() == f then any = true break end end
        if not any then f:Hide() end
    end
end

function ns.HideVitalsFx(v, frame)
    local fx = v.fx
    if not fx then return end
    fx.root:Hide()
    Restore(fx, frame)
end

-- Jolt only when the setting is on (DrawJolt runs regardless, to undo one).
local function JoltOn(key) return ON.Jolt[key] and db[key .. "FxJolt"] end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local UNIT_KEY = { player = "playerHp", target = "targetHp" }

ns.Listen({ "UNIT_COMBAT" }, function(_, unit, action, flag)
    local key = UNIT_KEY[unit]
    if not key then return end
    action, flag = Clean(action), Clean(flag)
    if action == "HEAL" then Mark(key, "heal")
    elseif action == "WOUND" and (flag == "CRITICAL" or flag == "CRUSHING") then
        if JoltOn(key) then Mark(key, "jolt") end
    elseif action == "BLOCK" then Mark(key, "block")
    elseif action == "DODGE" then Mark(key, "dodge")
    elseif action == "PARRY" then Mark(key, "parry") end
end)

ns.Listen({ "PLAYER_REGEN_DISABLED" }, function() Mark("playerHp", "flare") end)

ns.Listen({ "UNIT_SPELLCAST_SUCCEEDED:player" }, function() lastCastAt = GetTime() end)
ns.Listen({ "UNIT_POWER_FREQUENT:player" }, function(_, _, token)
    token = Clean(token)
    local now = GetTime()
    local yours = now - lastCastAt < 0.2 -- spent (or gained) by a cast of yours
    if token == "ENERGY" and not yours then tickAt = now end
    if token == "RAGE" and not yours and On("playerHp", "Rage") then ns.VitalsFxRage() end
end)

ns.VitalsFxState = function() return hits, tickAt end -- tests
