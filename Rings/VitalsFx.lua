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
--   Death      (all)      dead: the ring cracks and darkens, a faded skull in its middle; your ghost: a
--                         pale glow with wisps drifting up
--   Flare      (yours)    a gold ring bursting outward as combat starts
--   Heal       (yours, target) green sparkles racing up both sides when a heal lands
--   Jolt       (yours, target) the ring jolts on a critical or crushing hit
--   Avoid      (yours, target) a shield on a block, a whoosh round the ring on a dodge,
--                         crossed blades on a parry
--   EnergyTick (yours)    a spark running round the energy band, once per energy tick
--   Rage       (yours)    embers flying off the rage band as rage comes in
--   FullMana   (yours)    a soft shine on the mana band while it's full
--   Skin       (target)   a pelt badge at the top right when the target can be skinned (or
--                         gathered: herbs, ore, parts), from the corpse's tooltip; kinds of
--                         creature seen skinnable before get a faint one while alive
--   Range      (target)   the ring dims while the target's out of range of your main attacks
--   Tapped     (target)   a mob someone else tagged (no XP or loot for you) goes grey, whatever the
--                         color mode, its portrait too
--   Loot       (target)   gold glints round a corpse that still has loot for you, a coin at the right
--   Stance     (you)      your stance, form, aura or stealth as a badge at the bottom right
--   Quest      (target)   a yellow ! at the bottom left when the target is part of one of
--                         your active quests, with the objective's progress (3/10) under it
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

local ON = {
    Combo = { targetHp = true }, Mark = { playerHp = true, targetHp = true, totHp = true, petHp = true },
    Aggro = { targetHp = true }, Execute = { targetHp = true }, LowHealth = { playerHp = true },
    Death = { playerHp = true, targetHp = true, totHp = true, petHp = true }, Flare = { playerHp = true },
    Heal = { playerHp = true, targetHp = true, petHp = true }, Jolt = { playerHp = true, targetHp = true, petHp = true },
    Avoid = { playerHp = true, targetHp = true, petHp = true }, EnergyTick = { playerHp = true }, Rage = { playerHp = true },
    FullMana = { playerHp = true }, Skin = { targetHp = true },
    Quest = { targetHp = true }, Range = { targetHp = true }, Tapped = { targetHp = true },
    Loot = { targetHp = true }, Stance = { playerHp = true },
}
ns.VITALS_FX = ON

local function On(key, name) return ON[name][key] and db[key .. "Fx" .. name] end

-- Badge positions: where each badge sits on its ring, one of eight spots round it, chosen per
-- ring in its options (<key>Pos<Badge>; the defaults are where they've always been). Two badges
-- never share a spot: picking a taken one swaps them (ns.SetBadgeSpot). The top is also where
-- combo points go, and the aura arc sits on whichever side it's set to.
local BADGE_SPOTS = { top = 90, topright = 45, right = 0, bottomright = 315,
                      bottom = 270, bottomleft = 225, left = 180, topleft = 135 }
local BADGE_SPOT_ORDER = { "topleft", "top", "topright", "right", "bottomright", "bottom", "bottomleft", "left" }
local BADGE_SPOT_NAMES = { topleft = "Top left", top = "Top", topright = "Top right", right = "Right",
                           bottomright = "Bottom right", bottom = "Bottom", bottomleft = "Bottom left", left = "Left" }
-- Each badge: its label, what it is, and its default spot on each ring that has it.
local BADGES = {
    Level = { "Level badge", "The level disc (with the elite dragon on it for elites).",
              playerHp = "bottomleft", targetHp = "bottomright", totHp = "bottomright", petHp = "bottomleft" },
    Combat = { "In-combat indicator", "The crossed swords while you're in combat.", playerHp = "topright" },
    Mark = { "Raid marker", "The raid target icon (skull, cross...).",
             playerHp = "topleft", targetHp = "topleft", totHp = "topleft", petHp = "topleft" },
    Stance = { "Stance or form", "Your stance, form, aura or stealth.", playerHp = "bottomright" },
    Skin = { "Skinnable", "The skinning (or herb, ore, parts) badge.", targetHp = "topright" },
    Quest = { "Quest target", "The quest ! and its progress.", targetHp = "bottomleft" },
    Loot = { "Lootable", "The coin on a corpse with loot for you.", targetHp = "right" },
}
local BADGE_ORDER = { "Level", "Combat", "Mark", "Stance", "Skin", "Quest", "Loot" }

-- The spot a badge is at on a ring, and its angle (degrees, 0 = right, counter-clockwise).
local function BadgeSpot(key, badge)
    local b = BADGES[badge]
    local spot = db[key .. "Pos" .. badge]
    if not BADGE_SPOTS[spot] then spot = b and b[key] or "topleft" end
    return spot
end
local function BadgeAngle(key, badge) return BADGE_SPOTS[BadgeSpot(key, badge)] end

-- Moves a badge; whichever was at that spot takes its old one.
local function SetBadgeSpot(key, badge, spot)
    if not BADGE_SPOTS[spot] then return end
    local old = BadgeSpot(key, badge)
    for other, b in pairs(BADGES) do
        if other ~= badge and b[key] and BadgeSpot(key, other) == spot then
            db[key .. "Pos" .. other] = old
        end
    end
    db[key .. "Pos" .. badge] = spot
end

ns.VitalsBadges = { spots = BADGE_SPOTS, spotOrder = BADGE_SPOT_ORDER, spotNames = BADGE_SPOT_NAMES,
                    badges = BADGES, order = BADGE_ORDER, Spot = BadgeSpot, Angle = BadgeAngle, Set = SetBadgeSpot }

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

-- The raid marker. This client hides it from addons (a secret, even out of combat), and a
-- curve won't take a hidden value from addon code, so it can't be gated that way. But
-- SetSpriteSheetCell takes a hidden cell: the marker sheet is 4x4 with the eight icons as
-- cells 1-8, so the hidden index picks its own icon without Circlet ever knowing which (it's
-- how Blizzard's target frame draws it now). No marker comes back as nil.
local MARK_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

local function DrawMark(key, fx, st, frame, geom, d)
    local raw
    if st.unit then raw = SafeCall(GetRaidTargetIndex, st.unit) else raw = 8 end -- previews: a skull
    if not IsSecret(raw) then -- (never compare a hidden one, not even to nil)
        local idx = raw ~= nil and CleanNumber(raw)
        if not idx or idx < 1 or idx > 8 then return end
    end
    local t = Tex(fx, "mark", MARK_SHEET, "OVERLAY", 2)
    if not (t.SetSpriteSheetCell and pcall(t.SetSpriteSheetCell, t, raw, 4, 4)) then t:Hide() return end
    local x, y = Polar(BadgeAngle(key, "Mark"), geom.R)
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
    if not Gate(t, gate) then f:Hide() return end
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
    local beat = math.max(math.exp(-((ph - 0.0) / 0.07) ^ 2), 0.6 * math.exp(-((ph - 0.22) / 0.07) ^ 2),
        math.exp(-((ph - 1.0) / 0.07) ^ 2))
    DrawThreshold(fx, "low", frame, geom.R + geom.T * 0.3, gate, { 1, 0.08, 0.05 }, 0.25 + 0.6 * beat)
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

-- Skinnable. The game doesn't tell addons whether a creature can be skinned; the only word is
-- the "Skinnable" line on a looted corpse's tooltip (or "Requires Herbalism / Mining /
-- Engineering"), colored by how hard it is for you. So a dead target's tooltip is read (twice
-- a second while it's dead), and each kind of creature (by its NPC id) seen skinnable is
-- remembered (skinKnown), so the next live one, or a corpse not looted yet, gets a faint badge.
-- Each kind shows the cursor the game gives you over such a corpse (the knife, the herb, the
-- pick), cropped to leave out the pointer arrow in its top-left corner; the icon is the
-- fallback if this client has no such cursor file.
local CURSOR_CROP = 0.3 -- the arrow's share of the cursor image, from its top-left corner
local SKIN_KINDS = {
    { kind = "leather", text = UNIT_SKINNABLE_LEATHER or "Skinnable", icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
      cursor = "Interface\\Cursor\\Skin" },
    { kind = "herb", text = UNIT_SKINNABLE_HERB or "Requires Herbalism", icon = "Interface\\Icons\\INV_Misc_Flower_02",
      cursor = "Interface\\Cursor\\GatherHerbs" },
    { kind = "rock", text = UNIT_SKINNABLE_ROCK or "Requires Mining", icon = "Interface\\Icons\\Trade_Mining",
      cursor = "Interface\\Cursor\\Mine" },
    { kind = "bolts", text = UNIT_SKINNABLE_BOLTS or "Requires Engineering", icon = "Interface\\Icons\\Trade_Engineering" },
}
local SKIN_BY = {}
for _, k in ipairs(SKIN_KINDS) do SKIN_BY[k.kind] = k end

-- Whether you can gather it yourself: you need the profession (Skinning 393, Herbalism 182,
-- Mining 186, Engineering 202; looked up by ID, else by name in your skills list, as Forever
-- may number them its own way), and the corpse's tooltip line turns red when it's beyond your
-- skill. If the client won't say what skills you have, it counts as yes.
local SKILL_OF = { leather = { 393, "Skinning" }, herb = { 182, "Herbalism" }, rock = { 186, "Mining" },
                   bolts = { 202, "Engineering" } }
local skillCache, skillAt = {}, -math.huge
local function HasSkill(kind, now)
    if now - skillAt > 2 then skillCache, skillAt = {}, now end
    if skillCache[kind] ~= nil then return skillCache[kind] end
    local s, has = SKILL_OF[kind], nil
    local api = C_SkillInfo
    if s and api then
        if api.GetSkillLineInfoByID then
            local ok, info = pcall(api.GetSkillLineInfoByID, s[1])
            if ok and type(info) == "table" then
                local rank = Clean(info.rank)
                if type(rank) == "number" and rank > 0 then has = true end
            end
        end
        if not has and api.GetNumSkillLines and api.GetSkillLineInfo then
            has = false
            for i = 1, (CleanNumber(SafeCall(api.GetNumSkillLines)) or 0) do
                local info = SafeCall(api.GetSkillLineInfo, i)
                if type(info) == "table" and Clean(info.name) == s[2] and not info.isHeader then
                    local rank = Clean(info.rank)
                    has = type(rank) ~= "number" or rank > 0
                    break
                end
            end
        end
    end
    if has == nil then has = true end
    skillCache[kind] = has
    return has
end

local function TooHard(color)
    return color and color[1] > 0.9 and color[2] < 0.35 and color[3] < 0.35
end

local function NpcId(unit)
    local guid = Clean(SafeCall(UnitGUID, unit))
    if type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)") or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)")), guid
end

-- The corpse's tooltip line: kind and its color, or nil.
local function SkinFromTooltip(unit)
    local get = C_TooltipInfo and C_TooltipInfo.GetUnit
    local data = get and SafeCall(get, unit)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        local text = Clean(line.leftText)
        if type(text) == "string" then
            for _, k in ipairs(SKIN_KINDS) do
                if text == k.text then
                    local c = line.leftColor
                    local r, g, b = c and Clean(c.r), c and Clean(c.g), c and Clean(c.b)
                    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then r, g, b = 1, 0.82, 0 end
                    return k.kind, { r, g, b }
                end
            end
        end
    end
end

-- A corpse that said so and no longer does has been skinned: no badge on it after that.
local skinSeen = {} -- unit -> { guid, dead, at, kind, color, done }
local function SkinState(unit, dead, now)
    local id, guid = NpcId(unit)
    local s = skinSeen[unit]
    if not s or s.guid ~= guid or s.dead ~= dead then
        s = { guid = guid, dead = dead, at = -math.huge }
        skinSeen[unit] = s
    end
    if dead and now - s.at >= 0.5 then
        s.at = now
        local was = s.kind
        s.kind, s.color = SkinFromTooltip(unit)
        if was and not s.kind then s.done = true end
        if s.kind and id then
            db.skinKnown = db.skinKnown or {}
            db.skinKnown[id] = s.kind
        end
    end
    if s.kind then return s.kind, s.color, true end
    if s.done then return nil end
    local known = id and db.skinKnown and db.skinKnown[id]
    if known then return known, nil, false end
end

local function DrawSkin(key, fx, st, frame, geom, d, now)
    local kind, color, sure
    if st.unit then
        kind, color, sure = SkinState(st.unit, st.dead and true or false, now)
    else
        kind, color, sure = "leather", { 1, 0.82, 0 }, true -- previews
    end
    local k = kind and SKIN_BY[kind]
    if not k then return end
    local x, y = Polar(BadgeAngle(key, "Skin"), geom.R)
    -- The cursor, if the client has it (SetTexture says so).
    local cur = k.cursor and Tex(fx, "skinCursor", nil, "OVERLAY", 3)
    if cur then
        if cur.skinFile ~= k.cursor then
            cur.skinFile = k.cursor
            cur.skinOk = cur:SetTexture(k.cursor) ~= false
            cur:SetTexCoord(CURSOR_CROP, 1, CURSOR_CROP, 1) -- leave out the arrow
        end
        if not cur.skinOk then cur.used = false cur = nil end
    end
    local icon = not cur and Tex(fx, "skin", k.icon, "OVERLAY", 3)
    if cur then
        icon = cur
    elseif icon.skinFile ~= k.icon then
        icon.skinFile = k.icon
        icon:SetTexture(k.icon)
        -- Crop the icon's border, then mask it round: the game won't set tex coords on a
        -- texture once it has a mask (the mask stays on through later SetTexture calls).
        if not icon.masked then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon.masked = true
            pcall(icon.SetMask, icon, DISC)
        end
    end
    At(icon, frame, x, y, d * (cur and 1.35 or 1.1))
    -- Not one you can gather yourself: grey, no glow.
    local can = not st.unit or (HasSkill(kind, now) and not TooHard(color))
    if not can then
        icon:SetAlpha(sure and 0.85 or 0.45)
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.6, 0.6, 0.6)
    elseif sure then
        icon:SetVertexColor(1, 1, 1)
        icon:SetAlpha(1)
        icon:SetDesaturated(false)
        local glow = Tex(fx, "skinGlow", SOFT, "OVERLAY", 2, true)
        At(glow, frame, x, y, d * 2.2)
        glow:SetVertexColor(color[1], color[2], color[3])
        glow:SetAlpha(0.55 + 0.3 * math.sin(now * 3))
    else
        icon:SetVertexColor(1, 1, 1)
        icon:SetAlpha(0.5)
        icon:SetDesaturated(true)
    end
end
ns.VitalsFxSkinKinds = SKIN_KINDS -- tests

-- Quest target. The game's C_QuestLog.UnitIsRelatedToActiveQuest (what its nameplates use)
-- says whether the unit is part of one of your active quests; the unit's tooltip has the
-- quest's own lines (title, then objectives like "Young Wolf slain: 3/10"), which give the
-- progress, and do as the answer where that function isn't there. Read once a second, and
-- again when your quest log changes.
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local LINE_OBJ = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective) or 8
local LINE_TITLE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle) or 17

-- From the tooltip: whether it has quest lines, and the first unfinished objective's x/y.
local function QuestFromTooltip(unit)
    local get = C_TooltipInfo and C_TooltipInfo.GetUnit
    local data = get and SafeCall(get, unit)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    local any, progress, done
    for _, line in ipairs(data.lines) do
        local kind = Clean(line.type)
        if kind == LINE_OBJ or kind == LINE_TITLE then
            any = true
            local text = Clean(line.leftText)
            if kind == LINE_OBJ and type(text) == "string" then
                local have, need = text:match("(%d+)%s*/%s*(%d+)")
                have, need = tonumber(have), tonumber(need)
                if have and need then
                    if have < need then progress = progress or (have .. "/" .. need)
                    else done = done or (have .. "/" .. need) end
                end
            end
        end
    end
    return any, progress or done
end

local questSeen = {} -- unit -> { guid, at, on, progress }
local function QuestState(unit, now)
    local guid = Clean(SafeCall(UnitGUID, unit))
    local q = questSeen[unit]
    if not q or q.guid ~= guid then q = { guid = guid, at = -math.huge }; questSeen[unit] = q end
    if now - q.at >= 1 then
        q.at = now
        local tipOn, progress = QuestFromTooltip(unit)
        local api = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
        local apiOn = api and Clean(SafeCall(api, unit))
        q.on = (apiOn == true) or tipOn
        q.progress = progress
    end
    return q.on, q.progress
end
ns.Listen({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_WATCH_UPDATE" }, function()
    for _, q in pairs(questSeen) do q.at = -math.huge end
end)

local function DrawQuest(key, fx, st, frame, geom, d, now)
    local on, progress
    if st.unit then on, progress = QuestState(st.unit, now) else on, progress = true, "3/10" end -- previews
    if not on then return end
    local x, y = Polar(BadgeAngle(key, "Quest"), geom.R)
    local icon = Tex(fx, "quest", QUEST_ICON, "OVERLAY", 3)
    At(icon, frame, x, y + d * 0.1, d * 1.1)
    icon:SetAlpha(1)
    local glow = Tex(fx, "questGlow", SOFT, "OVERLAY", 2, true)
    At(glow, frame, x, y + d * 0.1, d * 2)
    glow:SetVertexColor(1, 0.85, 0.2)
    glow:SetAlpha(0.35 + 0.2 * math.sin(now * 2.5))
    if progress then
        local fs = fx.questText
        if not fs then
            fs = fx.root:CreateFontString(nil, "OVERLAY")
            fs:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
            fx.questText = fs
        end
        local px = math.max(8, math.floor(d * 0.55 + 0.5))
        if fs.px ~= px then fs.px = px; fs:SetFont(STANDARD_TEXT_FONT, px, "OUTLINE") end
        fs:SetText(progress)
        fs:SetTextColor(1, 0.85, 0.2)
        fs:ClearAllPoints()
        fs:SetPoint("TOP", icon, "BOTTOM", 0, 1)
        fs:Show()
        fx.questTextUsed = true
    end
end
ns.VitalsFxQuest = QuestFromTooltip -- tests

-- A round icon: cropped first, then masked (the game won't crop a masked texture).
local function RoundIcon(fx, name, file, layer, sub)
    local t = Tex(fx, name, file, layer or "OVERLAY", sub or 3)
    if t.iconFile ~= file then
        t.iconFile = file
        t:SetTexture(file)
        if not t.masked then
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            t.masked = true
            pcall(t.SetMask, t, DISC)
        end
    end
    return t
end

-- Range: whether your class's main attacks reach the target (C_Spell.IsSpellInRange, which the
-- game doesn't hide), checked five times a second. In range if any of them reach (a hunter's
-- Auto Shot or Raptor Strike, so the dead zone between doesn't count as out); out if none do;
-- left alone if none can be checked (a friendly target, a class with none known yet). The dim
-- is the ring's own fade (ns.SetRingDim), so it eases and goes with its opacity setting.
local RANGE_SPELLS = {
    MAGE = { 133, 116, 5143 },            -- Fireball, Frostbolt, Arcane Missiles
    WARLOCK = { 686, 172 },               -- Shadow Bolt, Corruption
    PRIEST = { 585, 589, 8092 },          -- Smite, Shadow Word: Pain, Mind Blast
    DRUID = { 5176, 8921 },               -- Wrath, Moonfire
    SHAMAN = { 403, 8042 },               -- Lightning Bolt, Earth Shock
    HUNTER = { 75, 3044, 2973 },          -- Auto Shot, Arcane Shot, Raptor Strike
    ROGUE = { 1752, 2098 },               -- Sinister Strike, Eviscerate
    WARRIOR = { 78, 772 },                -- Heroic Strike, Rend
    PALADIN = { 20271, 35395 },           -- Judgement, Crusader Strike
    DEATHKNIGHT = { 45477, 49998 },       -- Icy Touch, Death Strike
}
local function Knows(id)
    local f = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsPlayerSpell or IsSpellKnown
    return f and Clean(SafeCall(f, id)) and true or false
end
local function InRange(id, unit)
    if C_Spell and C_Spell.IsSpellInRange then
        local v = Clean(SafeCall(C_Spell.IsSpellInRange, id, unit))
        if v == nil or IsSecret(v) then return nil end
        return v == true or v == 1
    end
    if IsSpellInRange and GetSpellInfo then
        local name = Clean(SafeCall(GetSpellInfo, id))
        local v = name and Clean(SafeCall(IsSpellInRange, name, unit))
        if v == nil or IsSecret(v) then return nil end
        return v == 1 or v == true
    end
end
local rangeAt, rangeOut = -math.huge, nil
local function DrawRange(key, fx, st, frame, geom, d, now)
    local out = false
    if st.unit and not st.dead and Clean(SafeCall(UnitCanAttack, "player", st.unit)) then
        if now - rangeAt >= 0.2 then
            rangeAt = now
            local _, class = UnitClass("player")
            local any, reach = false, false
            for _, id in ipairs(RANGE_SPELLS[Clean(class) or ""] or {}) do
                if Knows(id) then
                    local v = InRange(id, st.unit)
                    if v ~= nil then any = true; if v then reach = true break end end
                end
            end
            rangeOut = any and not reach
        end
        out = rangeOut and true or false
    end
    if ns.SetRingDim then ns.SetRingDim(key, out and 0.4 or 1) end
end
ns.VitalsRangeSpells = RANGE_SPELLS -- tests
ns.Listen({ "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED" }, function() rangeAt = -math.huge end)

-- Loot: gold glints running round a corpse that still has loot for you (CanLootUnit), and a
-- coin at the right. Checked twice a second.
local lootAt, lootHas, lootGuid = -math.huge, false, nil
local function DrawLoot(key, fx, st, frame, geom, d, now)
    local has
    if not st.unit then
        has = false -- previews: nothing (they're alive)
    elseif st.dead then
        local guid = Clean(SafeCall(UnitGUID, st.unit))
        if guid ~= lootGuid or now - lootAt >= 0.5 then
            lootGuid, lootAt = guid, now
            local h = guid and CanLootUnit and Clean(SafeCall(CanLootUnit, guid))
            lootHas = h == true
        end
        has = lootHas
    end
    if not has then return end
    local coin = RoundIcon(fx, "loot", "Interface\\Icons\\INV_Misc_Coin_01")
    local x, y = Polar(BadgeAngle(key, "Loot"), geom.R)
    At(coin, frame, x, y, d * 1.05)
    coin:SetAlpha(1)
    local halo = Tex(fx, "lootGlow", SOFT, "OVERLAY", 2, true)
    At(halo, frame, x, y, d * 2)
    halo:SetVertexColor(1, 0.8, 0.25)
    halo:SetAlpha(0.4 + 0.25 * math.sin(now * 3))
    for i = 1, 3 do
        local g = Tex(fx, "lootGlint" .. i, SOFT, "OVERLAY", 4, true)
        local deg = (now * 70 + i * 120) % 360
        local gx, gy = Polar(deg, geom.R)
        local tw = 0.5 + 0.5 * math.sin(now * 6 + i * 2)
        At(g, frame, gx, gy, geom.T * (1.2 + tw))
        g:SetVertexColor(1, 0.85, 0.35)
        g:SetAlpha(0.35 + 0.5 * tw)
    end
end

-- Stance: your stance, form, aura or stealth (the game's stance bar: GetShapeshiftForm) as a
-- round badge at the bottom right of your ring. Previews show Battle Stance.
local function DrawStance(key, fx, st, frame, geom, d, now)
    local icon
    if st.unit then
        local idx = CleanNumber(SafeCall(GetShapeshiftForm))
        if idx and idx > 0 and GetShapeshiftFormInfo then
            icon = Clean(SafeCall(GetShapeshiftFormInfo, idx))
        end
    else
        icon = "Interface\\Icons\\Ability_Warrior_OffensiveStance"
    end
    if not icon or IsSecret(icon) then return end
    local x, y = Polar(BadgeAngle(key, "Stance"), geom.R)
    local back = Tex(fx, "stanceBack", DISC, "OVERLAY", 2)
    At(back, frame, x, y, d * 1.25)
    back:SetVertexColor(0, 0, 0)
    back:SetAlpha(0.85)
    local t = RoundIcon(fx, "stance", icon)
    At(t, frame, x, y, d * 1.05)
    t:SetAlpha(1)
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
        if v.g2 and v.g2.R and st.power then
            if On(key, "EnergyTick") then DrawEnergyTick(key, fx, st, frame, v.g2, now) end
            if On(key, "Rage") then DrawRage(key, fx, st, frame, v.g2, now) end
            if On(key, "FullMana") then DrawFullMana(key, fx, st, frame, v.g2, now) end
        end
    end
    if On(key, "Mark") then DrawMark(key, fx, st, frame, geom, d) end
    if On(key, "Range") then DrawRange(key, fx, st, frame, geom, d, now)
    elseif ns.SetRingDim then ns.SetRingDim(key, 1) end
    if On(key, "Loot") then DrawLoot(key, fx, st, frame, geom, d, now) end
    if On(key, "Stance") then DrawStance(key, fx, st, frame, geom, d, now) end
    if On(key, "Skin") then DrawSkin(key, fx, st, frame, geom, d, now) end
    fx.questTextUsed = false
    if On(key, "Quest") then DrawQuest(key, fx, st, frame, geom, d, now) end
    if fx.questText and not fx.questTextUsed then fx.questText:Hide() end
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
    -- The halos live under the ring (on the ring frame or frames of their own), not on fx.root.
    for _, t in pairs(fx.t) do if t:GetParent() ~= fx.root then t:Hide() end end
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
