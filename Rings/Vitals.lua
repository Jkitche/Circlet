-- Circlet: Health & power rings for you and your target: health round the band, power in a
-- thinner band inside it.
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall, Clean, CleanNumber, IsSecret = ns.db, ns.CreateLiveRing, ns.SafeCall, ns.Clean, ns.CleanNumber, ns.IsSecret
local NewRingLayer, DrawArc, TRACK = ns.NewRingLayer, ns.DrawArc, ns.TRACK

---------------------------------------------------------------------------
-- Health & power rings (playerHp: you; targetHp: your target)
---------------------------------------------------------------------------
-- The outer band is health, the thinner band inside it power (mana, rage, energy, focus),
-- with the health (and power) as text in the middle and, optionally, the unit's name.
--
-- Hidden values: in combat the game can hide health and power from addons (secret values:
-- they can be passed on, never read, compared or added up). A ring's fill is drawn from
-- line segments, so it can't simply be given a hidden number to fill to. Instead every
-- segment gets a step curve of its own (0 below its place round the ring, 1 from there on),
-- and UnitHealthPercent / UnitPowerPercent run the hidden percentage through it: the hidden
-- 0 or 1 that comes back goes straight into the segment's SetAlpha, which accepts hidden
-- values from addon code. So the right segments show without Circlet ever knowing the
-- number (the same way the target cast ring shows hidden cast times; LiveRing fillGate).
-- The text goes the same way: the hidden number is handed to the font string, which
-- draws it. When the values can be read (often your own, or out of combat) they're used
-- as they are. What can't be done with hidden values: anything that compares them (a
-- "not full" check, colors by how low it is), so those treat hidden as "something to show".

local POWER_TOKENS = { [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY" }

---------------------------------------------------------------- hidden-value helpers
local function Readable(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) ~= "number" or IsSecret(v) then return false end
    end
    return true
end

-- The percent functions' scale: 1 if they run 0..1 (as they should), 100 if 0..100. Checked
-- against your own health whenever both can be read.
local percentScale = 1
local function CheckScale()
    if type(UnitHealthPercent) ~= "function" then return end
    local hp, max = SafeCall(UnitHealth, "player"), SafeCall(UnitHealthMax, "player")
    local p = SafeCall(UnitHealthPercent, "player")
    if Readable(hp, max, p) and max > 0 and hp > 0 then
        percentScale = (p > 1.001) and 100 or 1
    end
end

local stepCurves = {} -- by threshold (in 1/400ths): 0 below it, 1 from it on
local function StepCurve(t)
    local key = math.max(1, math.floor(t * 400 + 0.5))
    local cv = stepCurves[key]
    if cv then return cv end
    cv = C_CurveUtil.CreateCurve()
    if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then pcall(cv.SetType, cv, Enum.LuaCurveType.Step) end
    cv:AddPoint(0, 0)
    cv:AddPoint(key / 400 * percentScale, 1)
    stepCurves[key] = cv
    return cv
end

local function CurvesWork()
    return C_CurveUtil and type(C_CurveUtil.CreateCurve) == "function"
end

-- A fill gate (each segment's alpha from where it sits round the ring) for a hidden value,
-- or nil if this client can't do it. pct(curve) runs the hidden percentage through a curve.
local function Gate(pct)
    if not CurvesWork() then return nil end
    local okC, cv = pcall(StepCurve, 0.5)
    if not okC or not pcall(pct, cv) then return nil end
    return function(pos)
        local ok, v = pcall(pct, StepCurve(pos))
        if ok then return v end
        return 0
    end
end

-- The hidden percentage (0..100) for text, through the game's own scaling curve if it has one.
local function HiddenPercent100(pct)
    local scale = CurveConstants and CurveConstants.ScaleTo100
    if scale then
        local ok, v = pcall(pct, scale)
        if ok then return v end
    end
end

---------------------------------------------------------------- reading a unit
local function Short(n)
    if n >= 1e6 then return string.format("%.1fm", n / 1e6) end
    if n >= 1e4 then return string.format("%.1fk", n / 1e3) end
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- Health color: the ring's own, or the unit's class color (players) / reaction (NPCs).
local REACTION = {
    hostile = { r = 0.85, g = 0.2, b = 0.15 }, neutral = { r = 0.95, g = 0.8, b = 0.2 },
    friendly = { r = 0.25, g = 0.8, b = 0.3 }, tapped = { r = 0.5, g = 0.5, b = 0.5 },
}
local function HealthColor(key, unit)
    local c = db[key .. "Colors"]
    if db[key .. "ColorMode"] ~= "class" then return c.health end
    if Clean(SafeCall(UnitIsPlayer, unit)) then
        local _, class = SafeCall(UnitClass, unit)
        class = Clean(class)
        local cc = class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
            or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
        if cc then return { r = cc.r, g = cc.g, b = cc.b } end
        return c.health
    end
    if Clean(SafeCall(UnitIsTapDenied, unit)) then return REACTION.tapped end
    local reaction = CleanNumber(SafeCall(UnitReaction, unit, "player"))
    if reaction then
        if reaction <= 3 then return REACTION.hostile elseif reaction == 4 then return REACTION.neutral end
        return REACTION.friendly
    end
    return c.health
end

local function PowerColor(key, token)
    local c = db[key .. "Colors"]
    if token == "MANA" then return c.mana elseif token == "RAGE" then return c.rage
    elseif token == "ENERGY" then return c.energy elseif token == "FOCUS" then return c.focus end
    local pc = PowerBarColor and token and PowerBarColor[token]
    if pc and pc.r then return { r = pc.r, g = pc.g, b = pc.b } end
    return c.mana
end

local function InCombat()
    return Clean(SafeCall(UnitAffectingCombat, "player")) or (InCombatLockdown and InCombatLockdown()) or false
end

---------------------------------------------------------------- transitions
-- Readable values: the fill eases to a new value the way the XP ring's does (<key>Smooth:
-- fast at first, settling at the end, longer for a bigger change); a loss leaves a red trail
-- that holds a moment, then drains after the fill, and a gain glows softly as it fills in
-- (<key>Trail). Nothing flashes. Hidden values (WoW Forever always hides your own): the game
-- eases them itself in the eased bands below; trail and glow need to know how much changed,
-- which the game won't tell addons, so they only show for readable values.
local TRAIL_HOLD, TRAIL_DRAIN = 0.45, 0.9 -- seconds the trail holds; band per second it drains
local GLOW_TIME = 1.0

local tracks = {} -- "playerHp:hp", "targetHp:pw", ...
local function Track(id)
    local t = tracks[id]
    if not t then t = { snaps = {} }; tracks[id] = t end
    return t
end

local function ResetTrack(id)
    local t = tracks[id]
    if t then t.shown, t.trailTop, t.glowAt, t.animAt = nil, nil, nil, nil end
end

-- One frame of a readable value: target is the real value (0..1), tr.shown what's drawn.
local function Step(key, tr, target, now, isHealth)
    if tr.shown == nil or tr.hidden then
        tr.shown, tr.target, tr.lastNow, tr.hidden = target, target, now, nil
        tr.trailTop, tr.glowAt, tr.animAt = nil, nil, nil
        return
    end
    local dt = math.max(0, math.min(0.25, now - (tr.lastNow or now)))
    tr.lastNow = now
    local before = tr.target
    if math.abs(target - before) > 0.002 then
        -- Ease from where it's drawn now: 0.4 s for a small change, up to 1.1 s for a big one.
        tr.animFrom, tr.animTo, tr.animAt = tr.shown, target, now
        tr.animDur = math.min(1.1, math.max(0.4, 0.4 + math.abs(target - tr.shown) * 1.4))
    end
    if target < before - 0.002 then
        tr.trailTop = math.max(tr.trailTop or 0, tr.shown, before)
        tr.trailAt = now
    elseif target > before + 0.002 then
        tr.glowFrom, tr.glowTo, tr.glowAt = math.min(tr.shown, before), target, now
        if tr.trailTop and target >= tr.trailTop then tr.trailTop = nil end
    end
    tr.target = target
    if db[key .. "Smooth"] and tr.animAt then
        local p = math.min(1, (now - tr.animAt) / tr.animDur)
        tr.shown = tr.animFrom + (tr.animTo - tr.animFrom) * (1 - (1 - p) ^ 3) -- ease out, as the XP ring
        if p >= 1 then tr.shown, tr.animAt = target, nil end
    else
        tr.shown = target
    end
    if tr.trailTop then
        -- Holds, then drains after the fill; gone once the fill (maybe still easing down) is past it.
        if now - tr.trailAt > TRAIL_HOLD then
            tr.trailTop = tr.trailTop - dt * TRAIL_DRAIN
            if tr.trailTop <= tr.shown + 0.001 then tr.trailTop = nil end
        end
    end
end

---------------------------------------------------------------- eased bands (hidden values)
-- The game won't let a hidden value be read, compared, or run through a curve that addon code
-- stored, so the ring can't work out in-between values itself. But a status bar takes a
-- hidden value and can ease to it on its own (SetValue with ExponentialEaseOut, as the game's
-- own health bars), and a mask can be pinned to the moving end of its fill. So the band is built
-- from pieces (one per 1/24 of the circle), each the ring texture of the band's width
-- (Textures/Ring40-96, as the target cast ring's timer) masked to its own slice, and cut by a
-- half-plane mask pinned to the end of an invisible bar the game eases. Every bar runs the whole
-- 0..100% and gets the same hidden value, so as the game eases it the edge sweeps on round the
-- ring from piece to piece, cut towards the centre (within 7.5 degrees). One solid color.
local EASE = Enum and Enum.StatusBarInterpolation
local EASE_OUT, EASE_NOW = EASE and EASE.ExponentialEaseOut, EASE and EASE.Immediate
local RING_MASK = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Ring%d"
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Needs the game's easing and masks (checked on a mask of our own).
local easedOK
local function EasedOK()
    if easedOK == nil then
        local f = CreateFrame("Frame")
        local m = f.CreateMaskTexture and f:CreateMaskTexture()
        local t = f:CreateTexture()
        easedOK = EASE_OUT ~= nil and m ~= nil and type(m.SetRotation) == "function" and type(t.AddMaskTexture) == "function"
    end
    return easedOK
end

local function MaskFile(inner, outer)
    local pct = math.floor(inner / math.max(outer, 1) * 25 + 0.5) * 4
    return RING_MASK:format(math.max(40, math.min(96, pct)))
end

-- The fill's pieces for geometry g: { fa, fb, pa, pb } (fill fractions and where they sit, in
-- turns clockwise from the top), cut every PIECE_TURN of the circle.
local PIECE_TURN = 1 / 24 -- so a moving edge, turned to the piece's middle, is within 7.5 degrees of radial
local function Pieces(g)
    local start, sweep, rev = g.start or 0, g.sweep or 1, g.reverse
    local function Pos(f) return rev and (start + sweep - f * sweep) or (start + f * sweep) end
    local cuts = { 0, 1 }
    for k = -48, 72 do
        local b = k * PIECE_TURN
        local f = rev and (start + sweep - b) / sweep or (b - start) / sweep
        if f > 1e-6 and f < 1 - 1e-6 then cuts[#cuts + 1] = f end
    end
    table.sort(cuts)
    local pieces = {}
    for i = 1, #cuts - 1 do
        local fa, fb = cuts[i], cuts[i + 1]
        if fb - fa > 1e-4 then pieces[#pieces + 1] = { fa = fa, fb = fb, pa = Pos(fa), pb = Pos(fb) } end
    end
    return pieces
end

local HALF_PLANE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\HalfPlane"

-- The point at `turns` (clockwise from the top) and radius r, from the ring's centre.
local function XY(turns, r) local a = 2 * math.pi * turns return r * math.sin(a), r * math.cos(a) end

-- Which way the fill moves round the ring at `turns` (unit x, y; s = -1 when it runs backwards).
local function Motion(turns, s)
    local a = 2 * math.pi * turns
    return math.cos(a) * s, -math.sin(a) * s
end

-- Turns a half-plane mask (Textures/HalfPlane: solid left half) so its solid side faces the
-- screen direction (nx, ny) (y up). Checked in game (/circ masktest): SetRotation turns a mask
-- counter-clockwise about its middle, negative angles included; the image is clipped to its own
-- square as it turns (the corners go black), so a mask only reaches half its size from its
-- middle in every direction; and masks ignore SetTexCoord.
local function TurnHalfPlane(m, nx, ny)
    -- Unturned, the solid side faces (-1, 0); turned by r it faces (-cos r, -sin r).
    m:SetRotation((math.atan2 or math.atan)(-ny, -nx))
end

-- Overlap between neighbouring pieces, so their soft edges don't leave a seam (pixels).
local SEAM = 0.6

-- (Re)lays out a band's pieces for geometry g on ring frame `frame` (pool: the band's own).
-- Each piece is the ring texture (the band's shape), tinted, masked three ways (the most a
-- texture takes): a half-plane along the radial line where the piece starts and one where it
-- ends (so it covers only its own slice); and a half-plane pinned to the moving edge of a status
-- bar the game eases, facing along the piece's middle, so the fill's edge is a cut towards the
-- centre. The bar itself is
-- invisible: it only moves that mask. It runs along x or y (whichever the band runs nearer
-- here), across the line through the band at the piece's middle, scaled so the mask's edge
-- crosses the band's centreline at the right place at each end of the piece.
local function LayoutEased(pool, frame, g)
    local rin, rout = g.R - g.T / 2, g.R + g.T / 2
    local rc = g.R
    local ring = MaskFile(rin, rout)
    local scale = percentScale
    local s = g.reverse and -1 or 1
    local big = 4 * rout + 8 -- the slice masks: centred on the ring, reaching all of it however turned
    local pieces = Pieces(g)
    for i, pc in ipairs(pieces) do
        local e = pool[i]
        if not e then
            e = {}
            e.tex = frame:CreateTexture(nil, "ARTWORK", nil, 1)
            e.bar = CreateFrame("StatusBar", nil, frame)
            e.bar:SetStatusBarTexture(WHITE)
            e.bar:SetStatusBarColor(1, 1, 1, 0) -- never seen: it only carries the edge
            e.fill = e.bar:GetStatusBarTexture()
            e.masks = {}
            -- (A texture takes at most three masks: the ring's shape is the texture itself.)
            for _, name in ipairs({ "from", "to", "edge" }) do
                local m = frame:CreateMaskTexture()
                e.masks[name] = m
                if e.tex.AddMaskTexture then pcall(e.tex.AddMaskTexture, e.tex, m) end
            end
            pool[i] = e
        end
        -- The ring texture (white, the band's width), tinted: the band's shape.
        e.tex:SetTexture(ring)
        e.tex:ClearAllPoints()
        e.tex:SetPoint("CENTER", frame, "CENTER", 0, 0)
        e.tex:SetSize(2 * rout, 2 * rout)
        local M = e.masks
        -- The piece's own slice: forward of its start line, behind its end line.
        -- (Each line is moved SEAM pixels outwards, so neighbours overlap a little.)
        for _, which in ipairs({ "from", "to" }) do
            local m = M[which]
            local mx, my = Motion(which == "from" and pc.pa or pc.pb, s)
            if which == "to" then mx, my = -mx, -my end
            m:SetTexture(HALF_PLANE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:ClearAllPoints()
            m:SetPoint("CENTER", frame, "CENTER", -mx * SEAM, -my * SEAM)
            m:SetSize(big, big)
            TurnHalfPlane(m, mx, my)
        end
        -- The moving edge: a radial cut at the piece's middle, solid behind it.
        local mid = (pc.pa + pc.pb) / 2
        local mx, my = Motion(mid, s)
        local dx, dy = XY(mid, 1) -- the radial direction there
        local horizontal = math.abs(mx) >= math.abs(my)
        -- Where along the bar's line the edge must be for the cut to cross the band's centreline
        -- at fill fraction f (the bar runs along x at y = fixed, or along y at x = fixed).
        local fixed = horizontal and rc * dy or rc * dx
        local function At(turns)
            local cx, cy = XY(turns, rc)
            if horizontal then return cx + (fixed - cy) * dx / dy end
            return cy + (fixed - cx) * dy / dx
        end
        local ea, eb = At(pc.pa), At(pc.pb)
        local L = (eb - ea) / (pc.fb - pc.fa) -- 0..100% of the bar, signed
        local zero = ea - pc.fa * L           -- where 0% sits
        local back = L < 0
        local len = math.max(1, math.abs(L))
        local lo = back and (zero - len) or zero -- the bar's low end (left or bottom)
        e.bar:SetOrientation(horizontal and "HORIZONTAL" or "VERTICAL")
        e.bar:SetReverseFill(back)
        e.bar:SetMinMaxValues(0, scale)
        e.bar:ClearAllPoints()
        if horizontal then
            e.bar:SetPoint("BOTTOMLEFT", frame, "CENTER", lo, fixed - 1)
            e.bar:SetSize(len, 2)
        else
            e.bar:SetPoint("BOTTOMLEFT", frame, "CENTER", fixed - 1, lo)
            e.bar:SetSize(2, len)
        end
        local lead = horizontal and (back and "LEFT" or "RIGHT") or (back and "BOTTOM" or "TOP")
        M.edge:SetTexture(HALF_PLANE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        M.edge:ClearAllPoints()
        M.edge:SetPoint("CENTER", e.fill, lead, 0, 0)
        -- Big enough to reach the whole piece from anywhere along the bar (it only reaches half
        -- its size from its middle, see TurnHalfPlane).
        local reach = 2 * (len + 2 * rout + 4)
        M.edge:SetSize(reach, reach)
        TurnHalfPlane(M.edge, -mx, -my)
        e.tex:Show()
        e.bar:Show()
    end
    for i = #pieces + 1, #pool do pool[i].tex:Hide(); pool[i].bar:Hide() end
    pool.n = #pieces
end

-- Draws a band's eased fill: lays it out when the geometry changes, colors it, and hands the
-- bars the hidden value (eased; at once when `immediate`) when the game says it changed.
local function DrawEased(pool, frame, g, c, value, changedAt, immediate)
    local lk = string.format("%.2f:%.2f:%s:%s:%s:%s", g.R, g.T, tostring(g.start), tostring(g.sweep),
        tostring(g.reverse), tostring(percentScale))
    if pool.layoutKey ~= lk then
        pool.layoutKey = lk
        LayoutEased(pool, frame, g)
        immediate = true
    end
    local feed = immediate or pool.fedFor ~= changedAt or GetTime() - (pool.fedAt or 0) > 1
    for i = 1, pool.n or 0 do
        local e = pool[i]
        e.tex:SetVertexColor(c.r, c.g, c.b, 1)
        if feed then pcall(e.bar.SetValue, e.bar, value, immediate and EASE_NOW or EASE_OUT) end
        e.tex:Show()
        e.bar:Show()
    end
    if feed then pool.fedFor, pool.fedAt = changedAt, GetTime() end
end

local function HideEased(pool)
    for i = 1, #pool do pool[i].tex:Hide(); pool[i].bar:Hide() end
    pool.layoutKey = nil
end

-- Bands to set at once next time (a new target: no easing over from the last one's value).
local easeNow = {}

-- When the game says a value changed (it doesn't say how).
local changes = {} -- "playerHp:hp" -> GetTime() the game last said that value changed
local UNIT_KEY = { player = "playerHp", target = "targetHp" }

-- Everything the ring shows for `unit`: health fill (frac, or a gate for hidden values),
-- power, texts (plain strings, or functions that put hidden ones on a font string).
local function UnitState(key, unit)
    local st = { color = HealthColor(key, unit), hold = 0.5, unit = unit, vitals = key }
    local hp, hpMax = SafeCall(UnitHealth, unit), SafeCall(UnitHealthMax, unit)
    local healthPct = function(curve) return UnitHealthPercent(unit, false, curve) end
    local now = GetTime()
    local hpTrack = Track(key .. ":hp")
    st.hpTrack, st.hpChanged = hpTrack, changes[key .. ":hp"]
    local dead = Clean(SafeCall(UnitIsDeadOrGhost, unit))
    if dead then st.dead = Clean(SafeCall(UnitIsGhost, unit)) and "Ghost" or "Dead" end
    if Readable(hp, hpMax) and hpMax > 0 then
        local frac = dead and 0 or math.max(0, math.min(1, hp / hpMax))
        st.hpFrac = frac
        st.hpText = { pct = string.format("%d%%", math.floor(frac * 100 + 0.5)), value = Short(hp) }
        Step(key, hpTrack, frac, now, true)
        st.frac = hpTrack.shown
    elseif dead then
        st.frac = 0
    else
        hpTrack.hidden = true
        st.hpHidden = { value = hp, pct = type(UnitHealthPercent) == "function" and HiddenPercent100(healthPct) or nil }
        if db[key .. "Smooth"] and EasedOK() and db[key .. "Style"] ~= "segmented" and type(UnitHealthPercent) == "function" then
            -- The game eases it (eased bands, above); the ring's own fill stays empty.
            st.frac, st.easedOn, st.eased = 0, true, SafeCall(UnitHealthPercent, unit)
        else
            st.frac = 1
            st.fillGate = type(UnitHealthPercent) == "function" and Gate(healthPct) or nil
            if not st.fillGate then st.frac = 0 end -- this client can't show it: an empty band
        end
    end

    -- Power.
    if db[key .. "Power"] then
        local ptype, token = SafeCall(UnitPowerType, unit)
        ptype, token = CleanNumber(ptype), Clean(token)
        token = token or POWER_TOKENS[ptype or 0]
        local pw, pwMax = SafeCall(UnitPower, unit, ptype), SafeCall(UnitPowerMax, unit, ptype)
        local pwTrack = Track(key .. ":pw")
        local pwr = { color = PowerColor(key, token), token = token, track = pwTrack, changed = changes[key .. ":pw"] }
        local powerPct = function(curve) return UnitPowerPercent(unit, ptype, false, curve) end
        if pwTrack.token ~= token then ResetTrack(key .. ":pw"); pwTrack.token = token end -- shapeshifted
        if Readable(pw, pwMax) then
            if pwMax > 0 then
                local frac = math.max(0, math.min(1, pw / pwMax))
                pwr.real = frac
                pwr.text = (token == "MANA") and string.format("%d%%", math.floor(frac * 100 + 0.5)) or tostring(pw)
                Step(key, pwTrack, frac, now, false)
                pwr.frac = pwTrack.shown
                st.power = pwr
            end -- no power (some NPCs): no inner band
        else
            pwTrack.hidden = true
            if db[key .. "Smooth"] and EasedOK() and db[key .. "Style"] ~= "segmented" and type(UnitPowerPercent) == "function" then
                pwr.frac, pwr.easedOn, pwr.eased = 0, true, SafeCall(UnitPowerPercent, unit, ptype)
            else
                pwr.frac = 1
                pwr.gate = type(UnitPowerPercent) == "function" and Gate(powerPct) or nil
                if not pwr.gate then pwr.frac = 0 end
            end
            pwr.hidden = { value = pw, pct = (token == "MANA" and type(UnitPowerPercent) == "function")
                and HiddenPercent100(powerPct) or nil }
            st.power = pwr
        end
    end

    -- Name (target ring, or if asked for).
    if db[key .. "Name"] then
        local name = SafeCall(UnitName, unit)
        st.name = name -- may be hidden: handed to the font string as it is
        local level = CleanNumber(SafeCall(UnitLevel, unit))
        if level and level > 0 and key == "targetHp" then st.level = level end
    end
    return st
end

-- Is there anything to show? show: "always", "combat" (in combat, or anything not full)
-- or "combatOnly". Hidden values count as not full.
local function Wanted(key, st)
    local show = db[key .. "Show"]
    if show == "always" then return true end
    if InCombat() then return true end
    if show == "combatOnly" then return false end
    if st.dead then return true end
    if not st.hpFrac or st.hpFrac < 0.999 then return true end
    local p = st.power
    if p then
        local f = p.real or p.frac
        if not f or p.gate then return true end
        -- Rage (and the like) builds up from empty: worth showing while there's some.
        if p.token == "RAGE" or p.token == "RUNIC_POWER" then
            if f > 0.001 then return true end
        elseif f < 0.999 then
            return true
        end
    end
    return false
end

---------------------------------------------------------------- drawing: the inner band and text
local function Parts(frame)
    if frame.vit then return frame.vit end
    local v = {}
    v.border = NewRingLayer("BACKGROUND", -8, { r = 0, g = 0, b = 0 }, 0.9, frame)
    v.track = NewRingLayer("BACKGROUND", 0, TRACK, 1, frame)
    v.fill = NewRingLayer("ARTWORK", 0, { r = 1, g = 1, b = 1 }, 1, frame)
    -- Transition layers, for the health band (h) and the power band (p): the trail beside the
    -- fill and the soft glow over it.
    v.eh, v.ep = {}, {} -- eased bands' bars (health, power)
    local white = { r = 1, g = 1, b = 1 }
    for _, b in ipairs({ "h", "p" }) do
        v[b] = { trail = NewRingLayer("ARTWORK", -1, white, 1, frame), glow = NewRingLayer("ARTWORK", 2, white, 1, frame) }
    end
    local function Text(layer)
        local fs = frame:CreateFontString(nil, layer or "OVERLAY")
        fs:SetShadowOffset(1, -1)
        fs:SetJustifyH("CENTER")
        return fs
    end
    v.hp, v.hp2, v.pw, v.name = Text(), Text(), Text(), Text()
    v.g2 = {}
    -- The unit's portrait, clipped to a circle, filling the middle behind the text.
    v.portrait = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    v.portrait:SetPoint("CENTER")
    if frame.CreateMaskTexture then
        v.mask = frame:CreateMaskTexture()
        v.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        v.mask:SetPoint("CENTER")
        v.portrait:AddMaskTexture(v.mask)
    end
    v.portrait:Hide()
    frame.vit = v
    return v
end

-- Portraits to redraw (by ring key): when the target or a portrait changes.
local portraitDirty = {}

local function DrawPortrait(key, v, unit, room)
    if not db[key .. "Portrait"] or not SetPortraitTexture then v.portrait:Hide() return end
    local size = math.max(8, room - 2)
    v.portrait:SetSize(size, size)
    if v.mask then v.mask:SetSize(size, size) end
    if portraitDirty[key] or v.portraitUnit ~= unit then
        portraitDirty[key] = nil
        v.portraitUnit = unit
        pcall(SetPortraitTexture, v.portrait, unit)
    end
    v.portrait:SetAlpha((tonumber(db[key .. "PortraitAlpha"]) or 70) / 100)
    v.portrait:Show()
end

-- Lays out the texts: the name on top, the health in the middle (with <key>SplitText and
-- "Value and percent", the number on one line and the percentage on a second, smaller one
-- under it), the power under those.
local function PlaceTexts(v, frame, room, split)
    v.hp:ClearAllPoints()
    v.hp2:ClearAllPoints()
    v.pw:ClearAllPoints()
    v.name:ClearAllPoints()
    if split then
        v.hp:SetPoint("CENTER", frame, "CENTER", 0, room * 0.09)
        v.hp2:SetPoint("TOP", v.hp, "BOTTOM", 0, -1)
        v.pw:SetPoint("TOP", v.hp2, "BOTTOM", 0, -1)
    else
        v.hp:SetPoint("CENTER", frame, "CENTER", 0, room * 0.02)
        v.pw:SetPoint("TOP", v.hp, "BOTTOM", 0, -1)
    end
    v.name:SetPoint("BOTTOM", v.hp, "TOP", 0, 1)
end

local function HideLayer(lines) for _, l in ipairs(lines) do l:Hide() end end

local function Whiten(c, k) return c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k end

-- One band's transitions (readable values only). L: its layers; tr: its track; c: its color;
-- trailColor: { r, g, b }.
local function Effects(key, L, tr, g, frame, c, now, trailColor)
    local readable = tr and not tr.hidden and tr.shown ~= nil
    -- The trail behind a loss: holds, then drains after the fill.
    if readable and db[key .. "Trail"] and tr.trailTop and tr.trailTop > tr.shown then
        for _, l in ipairs(L.trail) do l:SetColorTexture(trailColor.r, trailColor.g, trailColor.b, 0.85) end
        DrawArc(L.trail, tr.shown, tr.trailTop, frame, g)
    else
        HideLayer(L.trail)
    end
    -- A gain: the new part glows a little lighter as it fills in, fading out gently.
    if readable and db[key .. "Trail"] and tr.glowAt and now - tr.glowAt < GLOW_TIME then
        local k = 1 - (now - tr.glowAt) / GLOW_TIME
        local to = math.min(tr.glowTo, tr.shown)
        if to > tr.glowFrom + 0.002 then
            local r, gg, b = Whiten(c, 0.4)
            for _, l in ipairs(L.glow) do l:SetColorTexture(r, gg, b, 0.4 * k * k) end
            DrawArc(L.glow, tr.glowFrom, to, frame, g, true)
        else
            HideLayer(L.glow)
        end
    else
        HideLayer(L.glow)
    end
end

local HEALTH_TRAIL = { r = 1, g = 0.32, b = 0.25 }

-- Puts text on a font string; hidden values go through SetText / SetFormattedText (which
-- accept them), and if even that's refused, nothing shows.
local function Put(fs, fmt, ...)
    if fmt then
        if not pcall(fs.SetFormattedText, fs, fmt, ...) then fs:SetText("") end
    else
        if not pcall(fs.SetText, fs, (...)) then fs:SetText("") end
    end
end

-- Health text on fs; split: the number on fs and the percentage on fs2 ("Value and
-- percent" only).
local function HealthText(key, st, fs, fs2, split)
    local mode = db[key .. "Text"]
    fs2:SetText("")
    if mode == "none" then fs:SetText("") return end
    if st.dead then fs:SetText(st.dead) return end
    if st.hpText then
        local t = st.hpText
        if mode == "value" then fs:SetText(t.value)
        elseif mode == "both" and split then fs:SetText(t.value); fs2:SetText(t.pct)
        elseif mode == "both" then fs:SetText(t.value .. "  |cffcccccc" .. t.pct .. "|r")
        else fs:SetText(t.pct) end
        return
    end
    local h = st.hpHidden or {}
    if mode == "value" or (mode == "both" and h.pct == nil) then
        if h.value ~= nil then Put(fs, nil, h.value) else fs:SetText("") end
    elseif mode == "both" and split then
        if h.value ~= nil then Put(fs, nil, h.value) else fs:SetText("") end
        Put(fs2, "%d%%", h.pct)
    elseif mode == "both" then
        Put(fs, "%s  |cffcccccc%d%%|r", h.value, h.pct)
    elseif h.pct ~= nil then
        Put(fs, "%d%%", h.pct)
    else
        fs:SetText("")
    end
end

local function PowerText(key, p, fs)
    if not (p and db[key .. "PowerText"]) then fs:SetText("") return end
    local c = p.color
    fs:SetTextColor(c.r + (1 - c.r) * 0.35, c.g + (1 - c.g) * 0.35, c.b + (1 - c.b) * 0.35)
    if p.text then fs:SetText(p.text) return end
    local h = p.hidden or {}
    if h.pct ~= nil then Put(fs, "%d%%", h.pct)
    elseif h.value ~= nil then Put(fs, nil, h.value)
    else fs:SetText("") end
end

local function DrawVitals(key, st, frame, geom)
    local v = Parts(frame)
    if not st or not geom or geom.R <= 0 then
        HideLayer(v.border); HideLayer(v.track); HideLayer(v.fill)
        for _, b in ipairs({ "h", "p" }) do for _, l in pairs(v[b]) do HideLayer(l) end end
        HideEased(v.eh); HideEased(v.ep)
        v.hp:SetText(""); v.hp2:SetText(""); v.pw:SetText(""); v.name:SetText("")
        v.portrait:Hide()
        return
    end
    local b = ns.BorderWidthOf(key)
    local inner = geom.R - geom.T / 2 - b
    local now = GetTime()
    Effects(key, v.h, st.hpTrack, geom, frame, st.color, now, HEALTH_TRAIL)
    if st.easedOn then
        DrawEased(v.eh, frame, geom, st.color, st.eased, st.hpChanged, easeNow[key .. ":hp"])
        easeNow[key .. ":hp"] = nil
    else
        HideEased(v.eh)
    end
    local p = st.power
    if p then
        -- The power band: inside the health band, a fraction of its width, with a gap that
        -- leaves room for both borders.
        local T2 = math.max(2, geom.T * (tonumber(db[key .. "PowerSize"]) or 55) / 100)
        local g2 = v.g2
        g2.T = T2
        g2.R = geom.R - geom.T / 2 - (2 * b + 1) - T2 / 2
        g2.step, g2.style, g2.notches = geom.step, geom.style, geom.notches
        g2.start, g2.sweep, g2.reverse = geom.start, geom.sweep, geom.reverse
        local layoutKey = string.format("%.2f:%.2f:%s:%s:%s:%s:%d", g2.R, T2, tostring(g2.style), tostring(g2.start),
            tostring(g2.sweep), tostring(g2.reverse), b)
        if v.layoutKey ~= layoutKey then
            v.layoutKey = layoutKey
            DrawArc(v.track, 0, 1, frame, g2)
            if b > 0 then
                local gb = { R = g2.R, T = T2 + 2 * b, step = g2.step, style = g2.style, notches = g2.notches,
                             start = g2.start, sweep = g2.sweep, reverse = g2.reverse }
                DrawArc(v.border, 0, 1, frame, gb)
            else
                HideLayer(v.border)
            end
        end
        local c = p.color
        for _, l in ipairs(v.fill) do l:SetColorTexture(c.r, c.g, c.b, 1) end
        DrawArc(v.fill, 0, p.frac or 0, frame, g2, nil, ns.Shade(key, c))
        if p.gate then
            for _, l in ipairs(v.fill) do
                if l.arcMid and l:IsShown() then pcall(l.SetAlpha, l, p.gate(l.arcMid)) end
            end
            v.gated = true
        elseif v.gated then
            for _, l in ipairs(v.fill) do l:SetAlpha(1) end
            v.gated = nil
        end
        local tr, tg, tb = Whiten(c, 0.55)
        Effects(key, v.p, p.track, g2, frame, c, now, { r = tr, g = tg, b = tb })
        if p.easedOn then
            DrawEased(v.ep, frame, g2, c, p.eased, p.changed, easeNow[key .. ":pw"])
            easeNow[key .. ":pw"] = nil
        else
            HideEased(v.ep)
        end
        inner = g2.R - T2 / 2 - b
    else
        v.layoutKey = nil
        HideLayer(v.border); HideLayer(v.track); HideLayer(v.fill)
        for _, l in pairs(v.p) do HideLayer(l) end
        HideEased(v.ep)
    end

    -- Text: health in the middle, power under it, the name above.
    local room = math.max(10, inner * 2)
    local split = db[key .. "SplitText"] and db[key .. "Text"] == "both" and not st.dead
    -- Text sizes, each a % of its usual size (which follows the ring's): <key>HealthTextSize
    -- (the health and its percentage line), <key>PowerTextSize, <key>NameTextSize.
    local function Pct(name) return (tonumber(db[key .. name]) or 100) / 100 end
    local hs, ps, ns_ = Pct("HealthTextSize"), Pct("PowerTextSize"), Pct("NameTextSize")
    local textKey = room .. ":" .. tostring(split) .. ":" .. hs .. ":" .. ps .. ":" .. ns_
    if v.textKey ~= textKey then
        v.textKey = textKey
        local function Size(f, scale, min) return math.max(min, math.floor(room * f * scale + 0.5)) end
        -- Split: the number a little smaller, so the two lines and the power still fit.
        v.hp:SetFont(STANDARD_TEXT_FONT, Size(split and 0.21 or 0.24, hs, 6), "OUTLINE")
        v.hp2:SetFont(STANDARD_TEXT_FONT, Size(0.15, hs, 5), "OUTLINE")
        v.pw:SetFont(STANDARD_TEXT_FONT, Size(0.15, ps, 5), "OUTLINE")
        v.name:SetFont(STANDARD_TEXT_FONT, Size(0.13, ns_, 5), "OUTLINE")
        v.name:SetWidth(room * 0.95)
        v.name:SetWordWrap(false)
        PlaceTexts(v, frame, room, split)
    end
    -- Edit mode and previews have no unit of their own: your portrait stands in.
    DrawPortrait(key, v, st.unit or "player", room)
    v.hp:SetTextColor(1, 1, 1)
    v.hp2:SetTextColor(0.8, 0.8, 0.8)
    HealthText(key, st, v.hp, v.hp2, split)
    PowerText(key, p, v.pw)
    if st.name ~= nil then
        v.name:SetTextColor(1, 0.82, 0.25)
        if st.level then Put(v.name, "%s |cffbbbbbb%d|r", st.name, st.level) else Put(v.name, nil, st.name) end
    else
        v.name:SetText("")
    end
end

---------------------------------------------------------------- the rings
local SAMPLE_NAMES = { playerHp = nil, targetHp = "Defias Bandit" }

-- Edit mode / previews: health and mana drifting up and down, a target that's a warrior now
-- and then (rage).
-- Hits, heals and spending in steps, so the transitions show.
local SAMPLE_HP = { 0.95, 0.78, 0.81, 0.52, 0.86, 0.3, 0.64, 0.98 }
local SAMPLE_PW = { 0.9, 0.72, 0.74, 0.45, 0.6, 0.88, 0.5, 0.95 }
local function Sample(key, t)
    local i = math.floor(t / 1.6)
    local hpTarget = SAMPLE_HP[i % #SAMPLE_HP + 1]
    local pwTarget = SAMPLE_PW[i % #SAMPLE_PW + 1]
    local now = GetTime()
    local hpTrack, pwTrack = Track(key .. ":sample:hp"), Track(key .. ":sample:pw")
    if t < 0.05 then ResetTrack(key .. ":sample:hp"); ResetTrack(key .. ":sample:pw") end
    Step(key, hpTrack, hpTarget, now, true)
    Step(key, pwTrack, pwTarget, now, false)
    local hpf, pwf = hpTrack.shown, pwTrack.shown
    local mana = math.floor(t / 12.8) % 2 == 0
    local token = mana and "MANA" or "RAGE"
    local st = { color = db[key .. "ColorMode"] == "class" and (key == "targetHp" and REACTION.hostile or db[key .. "Colors"].health)
                     or db[key .. "Colors"].health,
                 frac = hpf, hpFrac = hpTarget, hold = 0.5, vitals = key, hpTrack = hpTrack,
                 hpText = { pct = string.format("%d%%", math.floor(hpTarget * 100 + 0.5)),
                            value = Short(math.floor(hpTarget * 2480)) } }
    if db[key .. "Power"] then
        local pc = PowerColor(key, token)
        st.power = { frac = pwf, real = pwTarget, color = pc, token = token, track = pwTrack,
                     text = mana and string.format("%d%%", math.floor(pwTarget * 100 + 0.5)) or tostring(math.floor(pwTarget * 100)) }
    end
    if db[key .. "Name"] then
        st.name = SAMPLE_NAMES[key] or Clean(SafeCall(UnitName, "player")) or "You"
        if key == "targetHp" then st.level = 18 end
    end
    return st
end

local rings = {}
local function MakeRing(key, unit)
    rings[key] = CreateLiveRing({
        key = key,
        watchEvery = 0.2,
        read = function()
            if not Clean(SafeCall(UnitExists, unit)) then return nil end
            local st = UnitState(key, unit)
            if not Wanted(key, st) then return nil end
            return st
        end,
        sample = function(t) return Sample(key, t) end,
        -- Its own texts (sized in the Text sizes box like every ring's).
        textRoles = {
            { id = "NameText", name = "Name", desc = "The name (and level) above the health." },
            { id = "HealthText", name = "Health", desc = "The health in the middle, and its percentage line." },
            { id = "PowerText", name = "Power", desc = "The mana, rage or energy under the health." },
        },
        decorate = function(st, frame, geom) DrawVitals(key, st, frame, geom) end,
    })
    return rings[key]
end

local playerRing = MakeRing("playerHp", "player")
local targetRing = MakeRing("targetHp", "target")

ns.Listen({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UNIT_MAXHEALTH:player" }, CheckScale)

-- Portraits: a new target, or a portrait that changed (gear, shapeshift, a model loading in).
-- Hidden changes: the game says a value changed (not how): the eased bars take the new value.
ns.Listen({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }, function(_, unit)
    local key = UNIT_KEY[unit]
    if key then changes[key .. ":hp"] = GetTime() end
end)
ns.Listen({ "UNIT_POWER_UPDATE" }, function(_, unit)
    local key = UNIT_KEY[unit]
    if key then changes[key .. ":pw"] = GetTime() end
end)
-- A new target: its bands start from its own values, not slide over from the last one's.
ns.Listen({ "PLAYER_TARGET_CHANGED" }, function()
    ResetTrack("targetHp:hp"); ResetTrack("targetHp:pw")
    easeNow["targetHp:hp"], easeNow["targetHp:pw"] = true, true
end)

ns.Listen({ "PLAYER_TARGET_CHANGED", "UNIT_PORTRAIT_UPDATE", "PLAYER_ENTERING_WORLD" }, function(event, unit)
    if event == "UNIT_PORTRAIT_UPDATE" then
        if unit == "player" then portraitDirty.playerHp = true elseif unit == "target" then portraitDirty.targetHp = true end
    else
        portraitDirty.targetHp = true
        if event == "PLAYER_ENTERING_WORLD" then portraitDirty.playerHp = true end
    end
end)

ns.PreviewPlayerHpRing = function() playerRing.Preview(12) end

-- /circ masktest: how this client applies masks (which way SetRotation turns them, what the
-- corner texture coordinates do), as white squares masked by Textures/HalfPlane, each labelled
-- with what it should show if the eased bands' assumptions hold. Click to close.
local maskTest
ns.RegisterCommand({ "masktest" }, function()
    if maskTest then maskTest:SetShown(not maskTest:IsShown()) return end
    local W = 110
    local f = CreateFrame("Button", "CircletMaskTest", UIParent)
    f:SetSize(W * 4 + 40, W * 2 + 90)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.12, 0.95)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Circlet mask test (click to close). Expected result under each square.")
    f:SetScript("OnClick", function(self) self:Hide() end)
    local cases = {
        { "plain mask", "left half white", nil },
        { "SetRotation(+90)", "bottom half (if counter-clockwise)", function(m) m:SetRotation(math.pi / 2) end },
        { "SetRotation(-90)", "top half (if counter-clockwise)", function(m) m:SetRotation(-math.pi / 2) end },
        { "SetRotation(+45)", "lower-left half", function(m) m:SetRotation(math.pi / 4) end },
        { "texcoords mirrored", "right half white", function(m) m:SetTexCoord(1, 0, 1, 1, 0, 0, 0, 1) end },
        { "texcoords: u up", "bottom half white", function(m) m:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0) end },
        { "texcoords: half size", "left 3/4 white", function(m) m:SetTexCoord(0.25, 0, 0.25, 1, 0.75, 0, 0.75, 1) end },
        { "no mask", "all white", false },
    }
    for i, c in ipairs(cases) do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local x, y = 20 + col * W, -30 - row * (W + 30)
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetSize(W - 20, W - 20)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        t:SetColorTexture(1, 1, 1, 1)
        local edge = f:CreateTexture(nil, "BORDER")
        edge:SetPoint("TOPLEFT", t, "TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 1, -1)
        edge:SetColorTexture(0.5, 0.2, 0.2, 1)
        if c[3] ~= false then
            local m = f:CreateMaskTexture()
            m:SetTexture(HALF_PLANE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(t)
            if c[3] then
                local ok, err = pcall(c[3], m)
                if not ok then c[2] = "ERROR: " .. tostring(err) end
            end
            t:AddMaskTexture(m)
        end
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOP", t, "BOTTOM", 0, -3)
        label:SetWidth(W - 4)
        label:SetText(i .. ". " .. c[1] .. "\n|cffaaaaaa" .. c[2] .. "|r")
    end
    maskTest = f
end, "show how this client applies masks (for bug reports)")

-- /circ hpdebug: what the health rings can see right now (readable or hidden values, which
-- functions this client has, the animation's state), printed and kept in CircletDB.vitalsDebug.
local function Describe(v)
    if v == nil then return "nil" end
    if IsSecret(v) then return "HIDDEN" end
    return tostring(v)
end
ns.RegisterCommand({ "hpdebug" }, function()
    local out = { at = date and date("%Y-%m-%d %H:%M:%S") or "?", combat = InCombat() and true or false,
                  hasHealthPercent = type(UnitHealthPercent) == "function", hasCurves = CurvesWork() and true or false,
                  hasScaleTo100 = (CurveConstants and CurveConstants.ScaleTo100) and true or false,
                  issecretvalue = issecretvalue ~= nil, percentScale = percentScale }
    for unit, key in pairs({ player = "playerHp", target = "targetHp" }) do
        if Clean(SafeCall(UnitExists, unit)) then
            local tr = tracks[key .. ":hp"] or {}
            local u = {
                health = Describe(SafeCall(UnitHealth, unit)), max = Describe(SafeCall(UnitHealthMax, unit)),
                power = Describe(SafeCall(UnitPower, unit)), powerMax = Describe(SafeCall(UnitPowerMax, unit)),
                healthPercent = type(UnitHealthPercent) == "function" and Describe(SafeCall(UnitHealthPercent, unit)) or "-",
                smooth = tostring(db[key .. "Smooth"]), shown = tostring(tr.shown), target = tostring(tr.target),
                hiddenPath = tostring(tr.hidden), easing = tostring(tr.animAt ~= nil),
            }
            out[unit] = u
            ns.Print(string.format("%s: health %s / %s, power %s / %s, percent %s | smooth=%s shown=%s hidden path=%s",
                unit, u.health, u.max, u.power, u.powerMax, u.healthPercent, u.smooth, u.shown, u.hiddenPath))
        end
    end
    ns.Print(string.format("in combat %s, UnitHealthPercent %s, curves %s, ScaleTo100 %s, issecretvalue %s",
        tostring(out.combat), tostring(out.hasHealthPercent), tostring(out.hasCurves), tostring(out.hasScaleTo100),
        tostring(out.issecretvalue)))
    -- Can a status bar ease to a hidden value on its own (the game doing the in-betweens)?
    local interp = Enum and Enum.StatusBarInterpolation
    local bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetSize(10, 10)
    bar:Hide()
    local okRange = pcall(bar.SetMinMaxValues, bar, 0, 1)
    local hp = SafeCall(UnitHealthPercent, "player")
    local okPlain = pcall(bar.SetValue, bar, hp)
    local okEase, easeErr = false, "no Enum.StatusBarInterpolation"
    if interp then
        local mode = interp.ExponentialEaseOut or interp.Linear
        okEase, easeErr = pcall(bar.SetValue, bar, hp, mode)
    end
    out.statusBar = { interpolation = interp and table.concat((function()
                          local t = {} for k, v in pairs(interp) do t[#t + 1] = k .. "=" .. tostring(v) end return t end)(), ",") or "none",
                      setRange = okRange, setHiddenValue = okPlain, easeHiddenValue = okEase,
                      easeError = not okEase and tostring(easeErr) or nil,
                      hasGetInterpolated = type(bar.GetInterpolatedValue) == "function",
                      hasMask = type(bar.GetStatusBarTexture) == "function" and bar:GetStatusBarTexture() ~= nil }
    ns.Print(string.format("status bar: hidden value %s, eased hidden value %s (modes: %s)%s",
        tostring(okPlain), tostring(okEase), out.statusBar.interpolation,
        okEase and "" or (" - " .. tostring(easeErr))))
    db.vitalsDebug = out
end, "what the health rings can see (for bug reports)")
ns.PreviewTargetHpRing = function() targetRing.Preview(12) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
local SHOW_NAMES = { always = "Always", combat = "In combat, or when not full", combatOnly = "Only in combat" }
local SHOW_ORDER = { "always", "combat", "combatOnly" }
local TEXT_NAMES = { percent = "Percent", value = "Value", both = "Value and percent", none = "None" }
local TEXT_ORDER = { "percent", "value", "both", "none" }
local COLOR_MODES = { health = "Health color", class = "Class / reaction color" }
local COLOR_ORDER = { "health", "class" }

local function Colors()
    return {
        health = { r = 0.25, g = 0.85, b = 0.30 },
        mana   = { r = 0.25, g = 0.50, b = 1.00 },
        rage   = { r = 0.90, g = 0.20, b = 0.20 },
        energy = { r = 1.00, g = 0.85, b = 0.20 },
        focus  = { r = 1.00, g = 0.55, b = 0.25 },
    }
end

local function Register(spec)
    local key = spec.key
    local defaults = {
        [key .. "Enabled"]   = true,
        [key .. "Show"]      = spec.show,
        [key .. "Power"]     = true,
        [key .. "PowerSize"] = 55,   -- the power band's width, % of the health band's
        [key .. "Text"]      = "percent",
        [key .. "PowerText"] = true,
        [key .. "SplitText"] = false,      -- "Value and percent": the number and % on two lines
        [key .. "Smooth"]    = true,       -- transitions (see above)
        [key .. "Trail"]     = true,
        [key .. "HealthTextSize"] = 100,   -- text sizes, % of the usual size for the ring
        [key .. "PowerTextSize"]  = 100,
        [key .. "NameTextSize"]   = 100,
        [key .. "Portrait"]  = false,      -- the unit's portrait filling the middle
        [key .. "PortraitAlpha"] = 70,
        [key .. "Name"]      = spec.name,
        [key .. "ColorMode"] = spec.colorMode,
        [key .. "Size"]      = 110,
        [key .. "Thickness"] = 12,
        [key .. "Opacity"]   = 100,
        [key .. "X"]         = spec.x,
        [key .. "FromTop"]   = 470,
        [key .. "Hold"]      = 1,
        [key .. "Style"]     = "smooth",
        [key .. "Border"]    = 2,
        [key .. "Colors"]    = Colors(),
    }
    ns.RegisterRing({
        key = key, name = spec.title, order = spec.order, since = "1.5.0",
        ring = spec.ring, alwaysInCombat = true,
        preview = spec.preview, slash = spec.slash, help = spec.help,
        toggle = { spec.toggleName, spec.toggleDesc },
        gameBar = spec.gameBar,
        defaults = defaults,
        page = { folder = "combat", order = spec.pageOrder, build = function(O)
                local Toggle, Range, Select, Color, Box = O.Toggle, O.Range, O.Select, O.Color, O.Box
                local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
                local tab = RingTab(spec.pageOrder, spec.pageName, spec.header, spec.intro,
                    MergeTop(TopRow(key, spec.what, spec.preview, "Show sample health and power. Also /circ " .. spec.slash[1] .. "."), {
                        general = Box(2, "General", {
                            enabled = Toggle(1, key .. "Enabled", "Show " .. spec.what, spec.toggleDesc),
                            show = Select(2, key .. "Show", "Show", SHOW_NAMES, SHOW_ORDER, spec.showDesc),
                            power = Toggle(3, key .. "Power", "Power band",
                                "A thinner band inside the health band for mana, rage, energy or focus."),
                            powerSize = Range(4, key .. "PowerSize", "Power band width (%)", 25, 100, 5,
                                "How wide the power band is, compared with the health band.",
                                { disabled = function() return not db[key .. "Power"] end }),
                            text = Select(5, key .. "Text", "Health text", TEXT_NAMES, TEXT_ORDER,
                                "What the middle of the ring says: the health as a percentage, the number, both, or "
                                .. "nothing."),
                            powerText = Toggle(6, key .. "PowerText", "Power text",
                                "Mana as a percentage (rage, energy and focus as the number) under the health.",
                                nil),
                            split = Toggle(5.5, key .. "SplitText", "Number and % on two lines",
                                "With Health text on Value and percent: the number on one line and the percentage "
                                .. "on a second, smaller line under it, instead of side by side."),
                            name = Toggle(7, key .. "Name", spec.nameLabel, spec.nameDesc),
                            portrait = Toggle(8, key .. "Portrait", spec.portraitLabel, spec.portraitDesc),
                            portraitAlpha = Range(9, key .. "PortraitAlpha", "Portrait opacity", 10, 100, 5,
                                "How strongly the portrait shows. Lower keeps the numbers on it easier to read.",
                                { disabled = function() return not db[key .. "Portrait"] end }),
                        }),
                        anim = Box(2.5, "Animations", {
                            smooth = Toggle(1, key .. "Smooth", "Smooth changes",
                                "The bands ease to a new value instead of jumping, like the XP ring. When the game "
                                .. "hides the values (WoW Forever always hides your own), it does the easing itself; "
                                .. "the band is then one solid color, and the Segmented style can't ease."),
                            trail = Toggle(2, key .. "Trail", "Damage trail and heal glow",
                                "Health you lose stays behind as a red trail for a moment, then drains away after the "
                                .. "band; health you gain glows softly as it fills in. Power does the same. Only when "
                                .. "the values can be read (the game must say how much changed)."),
                        }),
                        colors = Box(3, "Colors", {
                            mode = Select(0.5, key .. "ColorMode", "Health band color", COLOR_MODES, COLOR_ORDER,
                                "Health color: the color below. Class / reaction: players in their class color, "
                                .. "creatures red, yellow or green by how they feel about you."),
                            health = Color(1, key .. "Colors", "health", "Health", "Health band color.",
                                { disabled = function() return db[key .. "ColorMode"] == "class" end }),
                            mana = Color(2, key .. "Colors", "mana", "Mana", "Power band color for mana."),
                            rage = Color(3, key .. "Colors", "rage", "Rage", "Power band color for rage."),
                            energy = Color(4, key .. "Colors", "energy", "Energy", "Power band color for energy."),
                            focus = Color(5, key .. "Colors", "focus", "Focus", "Power band color for focus (hunter pets)."),
                        }),
                        size = SizeBox(4, key, spec.what, "Offset from the center of the screen."),
                    }))
                local g = tab.args.general.args
                g.powerText.disabled = function() return not db[key .. "Power"] end
                g.split.disabled = function() return db[key .. "Text"] ~= "both" end

                return tab
            end },
    })
end

Register({
    key = "playerHp", ring = playerRing, title = "Health", order = 12.9, pageOrder = 1.5,
    show = "combat", name = false, colorMode = "health", x = -230,
    preview = ns.PreviewPlayerHpRing, slash = { "health", "hp" }, help = "preview your health and power ring",
    toggleName = "Health ring", toggleDesc = "Your health, with your mana, rage or energy inside it.",
    gameBar = "the game's player frame",
    pageName = "Health & power", header = "Health & Power Ring", what = "health ring",
    intro = "Your health round the ring, and your mana, rage or energy in a thinner band inside it, with both "
        .. "in the middle. In combat the game can hide these from addons; the ring still fills and shows the "
        .. "numbers then, but can't compare them, so it counts hidden values as not full.",
    showDesc = "Always; in combat, or when your health or power isn't full (rage: when you have some); or only in "
        .. "combat.",
    nameLabel = "Show your name", nameDesc = "Your name above the health.",
    portraitLabel = "Use player portrait as center frame",
    portraitDesc = "Your character's portrait fills the middle of the ring, behind the numbers.",
})

Register({
    key = "targetHp", ring = targetRing, title = "Target health", order = 12.95, pageOrder = 1.6,
    show = "always", name = true, colorMode = "class", x = 230,
    preview = ns.PreviewTargetHpRing, slash = { "targethealth", "thp" }, help = "preview the target health ring",
    toggleName = "Target health ring", toggleDesc = "Your target's health and power, with its name.",
    gameBar = "the game's target frame",
    pageName = "Target health", header = "Target Health Ring", what = "target health ring",
    intro = "Your target's health round the ring and its mana, rage or energy in a thinner band inside it, with "
        .. "its name and level. Players show in their class color and creatures by how they feel about you (with "
        .. "Class / reaction color). In combat the game can hide these from addons; the ring still fills and shows "
        .. "the numbers then.",
    showDesc = "Whenever you have a target; when you're in combat or it isn't at full health; or only in combat.",
    nameLabel = "Show name and level", nameDesc = "The target's name, and its level, above the health.",
    portraitLabel = "Use target portrait as center frame",
    portraitDesc = "Your target's portrait fills the middle of the ring, behind the numbers, and changes with your "
        .. "target. In edit mode and previews your own portrait stands in.",
})
