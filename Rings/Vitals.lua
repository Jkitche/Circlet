-- Circlet: Health & power rings for you and your target: health round the band, power in a
-- thinner band inside it.
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall, Clean, CleanNumber, IsSecret = ns.db, ns.CreateLiveRing, ns.SafeCall, ns.Clean, ns.CleanNumber, ns.IsSecret
local NewRingLayer, DrawArc, TRACK = ns.NewRingLayer, ns.DrawArc, ns.TRACK

---------------------------------------------------------------------------
-- Health & power rings (playerHp: you; targetHp: your target; totHp: its target, smaller)
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
-- (<key>Trail). Hidden values (WoW Forever always hides your own): the game eases them itself
-- in the eased bands below; trail and glow need to know how much changed, which the game won't
-- tell addons, so they only show for readable values.
-- Big hits (<key>BigHit): the health band flashes red, briefly. With readable values, when one
-- loss takes <key>BigHitSize % of it or more; with hidden ones the size of a hit can't be known
-- (UNIT_COMBAT's amount is hidden too), so critical and crushing hits count as big.
local TRAIL_HOLD, TRAIL_DRAIN = 0.45, 0.9 -- seconds the trail holds; band per second it drains
local GLOW_TIME = 1.0
local FLASH_TIME = 0.45
local bigHitAt = {} -- ring key -> GetTime() of the last critical / crushing hit its unit took

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
        if isHealth and (before - target) * 100 >= (tonumber(db[key .. "BigHitSize"]) or 15) then
            bigHitAt[key] = now
        end
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
-- Units the game sends no health / power / portrait events for.
local NO_EVENTS = { targettarget = true }

-- Everything the ring shows for `unit`: health fill (frac, or a gate for hidden values),
-- power, texts (plain strings, or functions that put hidden ones on a font string).
local function UnitState(key, unit)
    local st = { color = HealthColor(key, unit), hold = 0.5, unit = unit, vitals = key }
    local hp, hpMax = SafeCall(UnitHealth, unit), SafeCall(UnitHealthMax, unit)
    local healthPct = function(curve) return UnitHealthPercent(unit, false, curve) end
    local now = GetTime()
    local hpTrack = Track(key .. ":hp")
    st.hpTrack, st.hpChanged = hpTrack, NO_EVENTS[unit] and math.floor(GetTime() * 5) or changes[key .. ":hp"]
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
        local pwr = { color = PowerColor(key, token), token = token, track = pwTrack,
                      changed = NO_EVENTS[unit] and math.floor(GetTime() * 5) or changes[key .. ":pw"] }
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
        if level and level > 0 and key ~= "playerHp" then st.level = level end
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
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a soft-edged white disc
-- The elite marker's wing (the left one; the right is it flipped): Textures/EliteWing.tga,
-- made by tools/make_wing_texture.py. Light grey, tinted gold or silver.
local WING = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\EliteWing"

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
        v[b] = { trail = NewRingLayer("ARTWORK", -1, white, 1, frame), glow = NewRingLayer("ARTWORK", 2, white, 1, frame),
                 flash = NewRingLayer("ARTWORK", 3, white, 1, frame) }
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
    -- Badges on the band: the level (bottom left) and the in-combat swords (top right). On a
    -- child frame, so they sit over the bands and the texts.
    local bf = CreateFrame("Frame", nil, frame)
    bf:SetAllPoints(frame)
    bf:SetFrameLevel(frame:GetFrameLevel() + 5)
    local function Badge()
        local bd = { parent = bf }
        bd.edge = bf:CreateTexture(nil, "BACKGROUND")
        bd.edge:SetTexture(DISC)
        bd.edge:SetVertexColor(0, 0, 0, 0.9)
        bd.fill = bf:CreateTexture(nil, "ARTWORK")
        bd.fill:SetTexture(DISC)
        bd.edge:Hide(); bd.fill:Hide()
        return bd
    end
    v.lvl = Badge()
    v.lvl.fill:SetVertexColor(0.11, 0.08, 0.10, 1)
    -- Its outline: a gold rim between the dark edge and the fill.
    v.lvl.rim = bf:CreateTexture(nil, "BORDER")
    v.lvl.rim:SetTexture(DISC)
    v.lvl.rim:SetVertexColor(0.85, 0.66, 0.28, 1)
    v.lvl.rim:Hide()
    v.lvl.text = bf:CreateFontString(nil, "OVERLAY")
    v.lvl.text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE") -- a font before any SetText (sized when drawn)
    v.lvl.text:SetShadowOffset(1, -1)
    v.lvl.text:SetJustifyH("CENTER")
    v.lvl.text:SetPoint("CENTER", v.lvl.fill, "CENTER", 0.5, 0)
    -- Elite marker: the game's own target-frame dragon behind the badge (or, if this client
    -- lacks that art, our wings).
    v.lvl.dragon = bf:CreateTexture(nil, "BACKGROUND", nil, -3)
    v.lvl.dragon:Hide()
    v.lvl.wingL = bf:CreateTexture(nil, "BACKGROUND", nil, -2)
    v.lvl.wingL:SetTexture(WING)
    v.lvl.wingR = bf:CreateTexture(nil, "BACKGROUND", nil, -2)
    v.lvl.wingR:SetTexture(WING)
    v.lvl.wingR:SetTexCoord(1, 0, 0, 1) -- flipped
    v.lvl.wingL:Hide(); v.lvl.wingR:Hide()
    v.cmb = Badge()
    v.cmb.fill:SetVertexColor(0.32, 0.05, 0.04, 1)
    v.cmb.icon = bf:CreateTexture(nil, "OVERLAY")
    v.cmb.icon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    v.cmb.icon:SetTexCoord(0.5, 1, 0, 0.5) -- the crossed swords
    v.cmb.icon:SetPoint("CENTER", v.cmb.fill, "CENTER")
    v.cmb.icon:Hide()
    frame.vit = v
    return v
end

-- A badge's disc, centered on the band at <deg> degrees (0 = right, counter-clockwise).
local function PlaceBadge(bd, R, deg, d)
    local k = R .. ":" .. deg .. ":" .. d
    if bd.k ~= k then
        bd.k = k
        local a = math.rad(deg)
        local x, y = R * math.cos(a), R * math.sin(a)
        bd.x, bd.y, bd.d = x, y, d
        bd.edge:ClearAllPoints(); bd.edge:SetPoint("CENTER", bd.parent, "CENTER", x, y); bd.edge:SetSize(d, d)
        local inset = 3
        if bd.rim then
            -- Outline: about a tenth of the disc, at least 2 px, inside a 1 px dark edge.
            local w = math.max(2, math.floor(d * 0.1 + 0.5))
            bd.rim:ClearAllPoints(); bd.rim:SetPoint("CENTER", bd.parent, "CENTER", x, y); bd.rim:SetSize(d - 2, d - 2)
            inset = 2 + 2 * w
        end
        bd.fill:ClearAllPoints(); bd.fill:SetPoint("CENTER", bd.parent, "CENTER", x, y); bd.fill:SetSize(d - inset, d - inset)
    end
    bd.edge:Show(); bd.fill:Show()
    if bd.rim then bd.rim:Show() end
end
local function HideBadge(bd)
    bd.edge:Hide(); bd.fill:Hide()
    if bd.rim then bd.rim:Hide() end
    if bd.wingL then bd.wingL:Hide(); bd.wingR:Hide() end
    if bd.dragon then bd.dragon:Hide() end
    if bd.text then bd.text:SetText("") end
    if bd.icon then bd.icon:Hide() end
end

-- Where each ring's level badge sits (degrees, 0 = right, counter-clockwise): bottom left on
-- yours, bottom right on the target's (the side away from yours).
local LEVEL_ANGLE = { playerHp = 225, targetHp = 315, totHp = 315 }

-- The elite marker (<key>Elite) on the level badge: the game's own target-frame dragon
-- round it, the art TargetFrame uses for that classification: the gold dragon for elites
-- and world bosses, the silver one for rare elites, and the silver frame (no wings) for
-- rares. Previews show the gold one.
--
-- The art is TargetFrame's whole frame (256x128, drawn a pixel a texel); we cut out the
-- dragon round its portrait. From TargetFrame.xml: the 64 px portrait sits at TOPRIGHT
-- -24,-16 of the 232x100 frame, and the frame art at CENTER +18.5,-4, 230x99, texcoords
-- 0.1015625..1 x 0.0078125..0.78125. So the portrait's center is texel (182.5, 44.5). We
-- draw texels 142..256 x 0..100 (the dragon, not the bars to its left), scaled so the
-- portrait is the badge, its center on the badge's.
local ELITE = { elite = "gold", worldboss = "gold", rareelite = "silver", rare = "silver" }
local DRAGON_ART = {
    elite = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
    worldboss = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
    rareelite = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
    rare = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
}
local ART_W, ART_H = 256, 128
local PU, PV, PD = 182.5, 44.5, 64          -- the portrait's center and size, in texels
local U0, U1, V0, V1 = 142, 256, 0, 100     -- the piece we draw
local WING_COLORS = { gold = { 1, 0.80, 0.32 }, silver = { 0.85, 0.88, 0.95 } }
-- The badge's colors (rim, outline, inside): plain, or, with a dragon round it, taken from
-- the dragon's own art (its gold or steel, and the dark of its shading) so the two read as
-- one piece rather than a black-edged disc sat on the dragon.
local BADGE_LOOK = {
    plain  = { rim = { 0.85, 0.66, 0.28 }, edge = { 0, 0, 0, 0.9 },          fill = { 0.11, 0.08, 0.10 } },
    gold   = { rim = { 0.96, 0.72, 0.22 }, edge = { 0.24, 0.13, 0.03, 0.85 }, fill = { 0.17, 0.10, 0.04 } },
    silver = { rim = { 0.80, 0.83, 0.88 }, edge = { 0.13, 0.13, 0.16, 0.85 }, fill = { 0.11, 0.11, 0.14 } },
}

local function BadgeLook(bd, look)
    if bd.look == look then return end
    bd.look = look
    local c = BADGE_LOOK[look]
    bd.rim:SetVertexColor(c.rim[1], c.rim[2], c.rim[3], 1)
    bd.edge:SetVertexColor(c.edge[1], c.edge[2], c.edge[3], c.edge[4])
    bd.fill:SetVertexColor(c.fill[1], c.fill[2], c.fill[3], 1)
end

-- The game's dragon round the badge; false if this client hasn't the art.
local function DrawDragon(bd, class)
    local t = bd.dragon
    local file = DRAGON_ART[class]
    if bd.dragonFile ~= file then
        bd.dragonFile = file
        bd.dragonOK = t:SetTexture(file) ~= false
        t:SetTexCoord(U0 / ART_W, U1 / ART_W, V0 / ART_H, V1 / ART_H)
    end
    if not bd.dragonOK then t:Hide() return false end
    local k = bd.d / PD
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", bd.parent, "CENTER", bd.x - (PU - U0) * k, bd.y + (PV - V0) * k)
    t:SetSize((U1 - U0) * k, (V1 - V0) * k)
    t:Show()
    return true
end

local function DrawElite(key, bd, st)
    local class
    if db[key .. "Elite"] then
        if st.unit then
            class = Clean(SafeCall(UnitClassification, st.unit))
        elseif key ~= "playerHp" then
            class = "elite" -- the preview's sample
        end
    end
    local kind = ELITE[class or ""]
    BadgeLook(bd, kind or "plain")
    if not kind or not bd.x then bd.dragon:Hide(); bd.wingL:Hide(); bd.wingR:Hide() return end
    if DrawDragon(bd, class) then bd.wingL:Hide(); bd.wingR:Hide() return end
    -- No dragon art on this client: our wings (rares, like the game, get none).
    if class == "rare" then bd.wingL:Hide(); bd.wingR:Hide() return end
    local d, c = bd.d, WING_COLORS[kind]
    local w = d * 1.05
    -- Each wing's root (its inner bottom corner) tucked behind the disc's upper side.
    bd.wingL:ClearAllPoints()
    bd.wingL:SetPoint("BOTTOMRIGHT", bd.parent, "CENTER", bd.x - d * 0.18, bd.y - d * 0.02)
    bd.wingR:ClearAllPoints()
    bd.wingR:SetPoint("BOTTOMLEFT", bd.parent, "CENTER", bd.x + d * 0.18, bd.y - d * 0.02)
    for _, t in ipairs({ bd.wingL, bd.wingR }) do
        t:SetSize(w, w)
        t:SetVertexColor(c[1], c[2], c[3], 1)
        t:Show()
    end
end

-- The level badge (<key>Level): the unit's level on a disc at the bottom of the ring;
-- others' levels in the game's difficulty colors, "??" for ones too high to tell.
local function DrawLevel(key, v, st, geom, d)
    if not db[key .. "Level"] then HideBadge(v.lvl) return end
    local unit = st.unit or "player"
    local level = st.level or CleanNumber(SafeCall(UnitLevel, unit))
    if not st.unit and key ~= "playerHp" then level = st.level or 18 end
    if not level then HideBadge(v.lvl) return end
    d = math.floor(d * 1.4 + 0.5) -- bigger than the combat badge: it carries text
    PlaceBadge(v.lvl, geom.R, LEVEL_ANGLE[key] or 225, d)
    local fk = d .. ":" .. ((tonumber(db[key .. "LevelTextSize"]) or 100))
    if v.lvl.fk ~= fk then
        v.lvl.fk = fk
        local size = math.max(6, math.floor(d * 0.5 * (tonumber(db[key .. "LevelTextSize"]) or 100) / 100 + 0.5))
        v.lvl.text:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    end
    local r, g, b = 1, 0.82, 0.25
    -- Colored the way the game's target frame and nameplates color it: the creature difficulty
    -- colors (the quest ones call anything within a few levels yellow), by its effective level.
    -- Friendly units: plain yellow (difficulty only matters for what you can fight).
    local Difficulty = GetCreatureDifficultyColor or GetQuestDifficultyColor
    local friend = st.unit and Clean(SafeCall(UnitIsFriend, "player", st.unit))
    if friend then
        r, g, b = 1, 0.82, 0
    elseif key ~= "playerHp" and st.unit and Difficulty then
        local eff = UnitEffectiveLevel and CleanNumber(SafeCall(UnitEffectiveLevel, st.unit)) or level
        local ok, c = pcall(Difficulty, (eff and eff > 0) and eff or 999)
        if ok and type(c) == "table" and c.r then r, g, b = c.r, c.g, c.b end
    end
    v.lvl.text:SetTextColor(r, g, b)
    v.lvl.text:SetText(level > 0 and tostring(level) or "??")
    DrawElite(key, v.lvl, st)
end

-- The in-combat badge (<key>Combat, your ring): crossed swords at the top right while you're
-- in combat, gently pulsing. Edit mode and previews show it so it can be placed.
local function DrawCombat(key, v, st, geom, d, now)
    local on = db[key .. "CombatIcon"]
    if on and st.unit then on = Clean(SafeCall(UnitAffectingCombat, st.unit)) and true or false end
    if not on then HideBadge(v.cmb) return end
    PlaceBadge(v.cmb, geom.R, 45, d)
    v.cmb.icon:SetSize(d * 0.8, d * 0.8)
    v.cmb.icon:Show()
    local a = 0.8 + 0.2 * math.sin(now * 4)
    v.cmb.fill:SetAlpha(a)
    v.cmb.icon:SetAlpha(a)
end

-- Portraits to redraw (by ring key): when the target or a portrait changes.
local portraitDirty = {}

local function DrawPortrait(key, v, unit, room)
    if not db[key .. "Portrait"] or not SetPortraitTexture then v.portrait:Hide() return end
    local size = math.max(8, room - 2)
    v.portrait:SetSize(size, size)
    if v.mask then v.mask:SetSize(size, size) end
    if NO_EVENTS[unit] and GetTime() - (v.portraitAt or 0) > 1 then portraitDirty[key] = true end
    if portraitDirty[key] or v.portraitUnit ~= unit then
        v.portraitAt = GetTime()
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

-- A big hit: the whole health band flashes red, fading out fast (FLASH_TIME).
local function BigHitFlash(key, L, g, frame, now)
    local at = bigHitAt[key]
    if db[key .. "BigHit"] and at and now - at < FLASH_TIME then
        local k = 1 - (now - at) / FLASH_TIME
        for _, l in ipairs(L.flash) do l:SetColorTexture(1, 0.3, 0.25, 0.55 * k * k) end
        DrawArc(L.flash, 0, 1, frame, g, true)
    else
        HideLayer(L.flash)
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
        HideBadge(v.lvl); HideBadge(v.cmb)
        return
    end
    local b = ns.BorderWidthOf(key)
    local inner = geom.R - geom.T / 2 - b
    local now = GetTime()
    Effects(key, v.h, st.hpTrack, geom, frame, st.color, now, HEALTH_TRAIL)
    BigHitFlash(key, v.h, geom, frame, now)
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
    -- Badges: about two band-widths across, never tiny.
    local d = math.floor(math.max(14, geom.T * 1.7, geom.R * 0.36) + 0.5)
    DrawLevel(key, v, st, geom, d)
    DrawCombat(key, v, st, geom, d, now)
    if st.name ~= nil then
        v.name:SetTextColor(1, 0.82, 0.25)
        if st.level and not db[key .. "Level"] then Put(v.name, "%s |cffbbbbbb%d|r", st.name, st.level) else Put(v.name, nil, st.name) end
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
        if key == "targetHp" then st.level = 18 elseif key == "totHp" then st.level = 20 end
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
            { id = "LevelText", name = "Level", desc = "The level on its badge at the bottom left." },
        },
        decorate = function(st, frame, geom) DrawVitals(key, st, frame, geom) end,
    })
    return rings[key]
end

local playerRing = MakeRing("playerHp", "player")
local targetRing = MakeRing("targetHp", "target")
local totRing = MakeRing("totHp", "targettarget")

---------------------------------------------------------------- right-click menus
-- The game's own unit menu on right-click, the way unit frames do it: a secure unit button
-- (right-click = togglemenu) over each ring, so the game opens the menu itself and its
-- protected entries (Set Focus...) keep working, with nothing tainted. Secure buttons can't be
-- moved, shown or hidden by addon code in combat, so they aren't the rings' children (a ring can
-- fade and slide freely): out of combat each button follows its ring where it actually is (auto-
-- arrange included) and shows exactly while the ring does; in combat the game shows and hides it
-- itself (a state driver: while the unit exists), where it was when combat started. Left clicks
-- pass through to the world; in edit mode the buttons step aside so the rings can be dragged.
local MENU_RINGS = {
    { key = "playerHp", unit = "player", ring = playerRing, name = "CircletPlayerHpMenu" },
    { key = "targetHp", unit = "target", ring = targetRing, name = "CircletTargetHpMenu" },
    { key = "totHp", unit = "targettarget", ring = totRing, name = "CircletTotHpMenu" },
}
local menuDebug = {}

local function MenuButton(m)
    if m.button then return m.button end
    local ok, b = pcall(CreateFrame, "Button", m.name, UIParent, "SecureUnitButtonTemplate")
    if not ok or not b then menuDebug[m.key] = "couldn't make the button: " .. tostring(b) return nil end
    b:SetAttribute("unit", m.unit)
    b:SetAttribute("*type1", nil)
    b:SetAttribute("*type2", "togglemenu")
    b:SetAttribute("type2", "togglemenu")
    b:RegisterForClicks("AnyUp")
    if b.SetPassThroughButtons then pcall(b.SetPassThroughButtons, b, "LeftButton") end
    b:SetFrameStrata(ns.RING_STRATA)
    b:SetFrameLevel(50)
    b:EnableMouse(true)
    b:Hide()
    m.button = b
    return b
end

local function Wants(m)
    return db[m.key .. "Enabled"] and db[m.key .. "Menu"] and not m.ring.IsEditing()
end

-- Where the ring is: its real center if it has one, else its saved spot.
local function RingSpot(m)
    local f = m.ring.frame
    local size = f:GetWidth()
    if not size or size <= 0 then size = tonumber(db[m.key .. "Size"]) or 110 end
    local x, y = f:GetCenter()
    if x and y then
        local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        return "BOTTOMLEFT", x * k, y * k, size * k
    end
    return "TOP", tonumber(db[m.key .. "X"]) or 0, -((tonumber(db[m.key .. "FromTop"]) or 0) + size / 2), size
end

local function PlaceMenu(m, b)
    local rel, x, y, size = RingSpot(m)
    local k = string.format("%s:%.1f:%.1f:%.1f", rel, x, y, size)
    if m.spot == k then return end
    m.spot = k
    b:ClearAllPoints()
    b:SetPoint("CENTER", UIParent, rel, x, y)
    b:SetSize(size, size)
end

-- Out of combat: follow the ring, shown while it is.
local function SyncMenus()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, m in ipairs(MENU_RINGS) do
        local want = Wants(m)
        local b = (want or m.button) and MenuButton(m)
        if b then
            if m.driver then pcall(UnregisterStateDriver, b, "visibility"); m.driver = nil end
            local f = m.ring.frame
            local up = want and f:IsVisible() and f:GetAlpha() > 0.05
            if up then
                PlaceMenu(m, b)
                if not b:IsShown() then b:Show() end
            elseif b:IsShown() then
                b:Hide()
            end
        end
    end
end

-- Combat starting (still allowed to set things up): the game takes over showing them.
local function HandOver()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, m in ipairs(MENU_RINGS) do
        local b = m.button
        if b and Wants(m) then
            PlaceMenu(m, b)
            if RegisterStateDriver then
                pcall(RegisterStateDriver, b, "visibility", "[@" .. m.unit .. ",exists] show; hide")
                m.driver = true
            end
        end
    end
end
ns.Listen({ "PLAYER_REGEN_DISABLED" }, HandOver)
ns.Listen({ "PLAYER_REGEN_ENABLED" }, SyncMenus)

local menuWatch = CreateFrame("Frame")
menuWatch.t = 0
menuWatch:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.t < 0.1 or not CircletDB then return end
    self.t = 0
    SyncMenus()
end)

-- /circ menudebug: where the menu buttons are and what they'd do.
ns.RegisterCommand({ "menudebug" }, function()
    for _, m in ipairs(MENU_RINGS) do
        local b = m.button
        if not b then
            ns.Print(m.key .. ": no button (" .. (menuDebug[m.key] or (Wants(m) and "not made yet" or "off")) .. ")")
        else
            local x, y = b:GetCenter()
            local rx, ry = m.ring.frame:GetCenter()
            ns.Print(string.format("%s: shown %s, mouse %s, over %s, at %s,%s (ring at %s,%s), size %d, unit %s, type2 %s, protected %s",
                m.key, tostring(b:IsVisible()), tostring(b:IsMouseEnabled()), tostring(b:IsMouseOver()),
                x and math.floor(x) or "?", y and math.floor(y) or "?", rx and math.floor(rx) or "?", ry and math.floor(ry) or "?",
                b:GetWidth() or 0, tostring(b:GetAttribute("unit")), tostring(b:GetAttribute("*type2")),
                tostring(b:IsProtected())))
        end
    end
    local focus = GetMouseFoci and GetMouseFoci() or (GetMouseFocus and { GetMouseFocus() }) or {}
    local names = {}
    for _, f in ipairs(focus) do names[#names + 1] = tostring(f.GetName and f:GetName() or f) end
    ns.Print("Under the mouse: " .. (#names > 0 and table.concat(names, ", ") or "nothing"))
end)

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
-- Critical and crushing hits taken (UNIT_COMBAT: the kind of hit can be read, its size can't):
-- with hidden values, the big hits.
ns.Listen({ "UNIT_COMBAT" }, function(_, unit, action, flag)
    local key = UNIT_KEY[unit]
    if not key then return end
    action, flag = Clean(action), Clean(flag)
    if action == "WOUND" and (flag == "CRITICAL" or flag == "CRUSHING") then
        local tr = tracks[key .. ":hp"]
        if not tr or tr.hidden then bigHitAt[key] = GetTime() end -- readable: sized by the loss
    end
end)

local function FreshStart(key)
    ResetTrack(key .. ":hp"); ResetTrack(key .. ":pw")
    easeNow[key .. ":hp"], easeNow[key .. ":pw"] = true, true
    portraitDirty[key] = true
end
ns.Listen({ "PLAYER_TARGET_CHANGED" }, function()
    FreshStart("targetHp"); FreshStart("totHp")
end)
ns.Listen({ "UNIT_TARGET" }, function(_, unit)
    if unit == "target" then FreshStart("totHp") end
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
ns.PreviewTotHpRing = function() totRing.Preview(12) end

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
    for unit, key in pairs({ player = "playerHp", target = "targetHp", targettarget = "totHp" }) do
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
        [key .. "BigHit"]    = spec.bigHit and true or false,
        [key .. "Menu"]      = true,       -- right-click menu
        [key .. "BigHitSize"] = 15,
        [key .. "HealthTextSize"] = 100,   -- text sizes, % of the usual size for the ring
        [key .. "PowerTextSize"]  = 100,
        [key .. "NameTextSize"]   = 100,
        [key .. "LevelTextSize"]  = 100,
        [key .. "Level"]     = spec.level and true or false, -- level badge, bottom left
        [key .. "Elite"]     = (spec.level and key ~= "playerHp") and true or nil, -- wings on it for elites
        [key .. "CombatIcon"] = spec.combat and true or nil,  -- in-combat badge (your ring)
        [key .. "Portrait"]  = false,      -- the unit's portrait filling the middle
        [key .. "PortraitAlpha"] = 70,
        [key .. "Name"]      = spec.name,
        [key .. "ColorMode"] = spec.colorMode,
        [key .. "Size"]      = spec.size or 110,
        [key .. "Thickness"] = spec.thickness or 12,
        [key .. "Opacity"]   = 100,
        [key .. "X"]         = spec.x,
        [key .. "FromTop"]   = spec.fromTop or 470,
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
                            level = Toggle(7.3, key .. "Level", "Level badge",
                                "The level on a small disc at the bottom " .. (key == "playerHp" and "left" or "right") .. " of the ring"
                                .. (key == "playerHp" and "." or ", in the game's difficulty colors (\"??\" when "
                                .. "it's too high to tell). The name then leaves its level off.")),
                            elite = key ~= "playerHp" and spec.level and (function()
                                local t = Toggle(7.4, key .. "Elite", "Elite indicator",
                                    "The game's target-frame dragon round the level badge: gold for elites and world "
                                    .. "bosses, silver for rare elites, and the silver frame for rares.")
                                t.disabled = function() return not db[key .. "Level"] end
                                return t
                            end)() or nil,
                            combat = spec.combat and Toggle(7.6, key .. "CombatIcon", "In-combat indicator",
                                "Crossed swords on a small disc at the top right of the ring while you're in combat. "
                                .. "Edit mode and previews show it so you can see where it sits.") or nil,
                            menu = Toggle(8.5, key .. "Menu", "Right-click menu",
                                "Right-click the ring for the game's own menu for " .. spec.menuWho .. ", as on its "
                                .. "frame (Set Focus, raid marks, whisper, inspect...). Left clicks still go through to "
                                .. "the world. In combat it stays where the ring was when the fight started."),
                            portraitAlpha = Range(9, key .. "PortraitAlpha", "Portrait opacity", 10, 100, 5,
                                "How strongly the portrait shows. Lower keeps the numbers on it easier to read.",
                                { disabled = function() return not db[key .. "Portrait"] end }),
                        }),
                        anim = Box(2.5, "Animations", {
                            smooth = Toggle(1, key .. "Smooth", "Smooth changes",
                                "The bands ease to a new value instead of jumping, like the XP ring. When the game "
                                .. "hides the values (WoW Forever always hides your own), it does the easing itself; "
                                .. "the band is then one solid color, and the Segmented style can't ease."),
                            bigHit = Toggle(3, key .. "BigHit", "Flash on big hits",
                                "The health band flashes red for a moment on a big hit. When the game hides the "
                                .. "values (always for your own, in combat for others) it won't say how big a hit was, "
                                .. "so then critical and crushing hits count as big."),
                            bigHitSize = Range(4, key .. "BigHitSize", "Big hit (% of health)", 5, 50, 1,
                                "How much one hit has to take to count as big, when the values can be read.",
                                { disabled = function() return not db[key .. "BigHit"] end }),
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
    show = "combat", name = false, colorMode = "health", x = -230, bigHit = true, level = true, combat = true, menuWho = "yourself",
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
    show = "always", name = true, colorMode = "class", x = 230, bigHit = true, level = true, menuWho = "your target",
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

Register({
    key = "totHp", ring = totRing, title = "Target of target", order = 12.97, pageOrder = 1.7,
    show = "always", name = true, colorMode = "class", x = 330, fromTop = 490, size = 70, thickness = 8, menuWho = "it",
    preview = ns.PreviewTotHpRing, slash = { "tot", "targettarget" }, help = "preview the target of target ring",
    toggleName = "Target of target ring", toggleDesc = "A small ring for your target's target: who it's after.",
    gameBar = "the game's target of target frame",
    pageName = "Target of target", header = "Target of Target Ring", what = "target of target ring",
    intro = "A smaller ring beside the target ring for your target's target: who your target is after, so you "
        .. "can see at a glance when it turns on you or a healer. Its health round the ring and its power inside, "
        .. "with its name. The game sends no updates for this unit, so the ring checks it several times a second.",
    showDesc = "Whenever your target has a target; when you're in combat or it isn't at full health; or only in "
        .. "combat.",
    nameLabel = "Show name and level", nameDesc = "The name, and level, above the health.",
    portraitLabel = "Use its portrait as center frame",
    portraitDesc = "Its portrait fills the middle of the ring, behind the numbers. In edit mode and previews your "
        .. "own portrait stands in.",
})
