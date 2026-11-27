-- Circlet: Health rings: how a band moves to a new value (eased, with a trail or glow), and reading a unit's state.
local ADDON_NAME, ns = ...

local db, SafeCall, Clean, CleanNumber = ns.db, ns.SafeCall, ns.Clean, ns.CleanNumber
local H = ns.HealthRings
local POWER_TOKENS = H.POWER_TOKENS
local Readable = H.Readable
local Gate = H.Gate
local HiddenPercent100 = H.HiddenPercent100
local Short = H.Short
local HealthColor = H.HealthColor
local PowerColor = H.PowerColor
local InCombat = H.InCombat

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
    if not t then
        t = { snaps = {} }
        tracks[id] = t
    end
    return t
end

local function ResetTrack(id)
    local t = tracks[id]
    if t then
        t.shown, t.trailTop, t.glowAt, t.animAt = nil, nil, nil, nil
    end
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
        if p >= 1 then
            tr.shown, tr.animAt = target, nil
        end
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
        easedOK = EASE_OUT ~= nil
            and m ~= nil
            and type(m.SetRotation) == "function"
            and type(t.AddMaskTexture) == "function"
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
local function XY(turns, r)
    local a = 2 * math.pi * turns
    return r * math.sin(a), r * math.cos(a)
end

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
    local scale = H.percentScale
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
            if which == "to" then
                mx, my = -mx, -my
            end
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
        local zero = ea - pc.fa * L -- where 0% sits
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
    for i = #pieces + 1, #pool do
        pool[i].tex:Hide()
        pool[i].bar:Hide()
    end
    pool.n = #pieces
end

-- Draws a band's eased fill: lays it out when the geometry changes, colors it, and hands the
-- bars the hidden value (eased; at once when `immediate`) when the game says it changed.
local function DrawEased(pool, frame, g, c, value, changedAt, immediate)
    local lk = string.format(
        "%.2f:%.2f:%s:%s:%s:%s",
        g.R,
        g.T,
        tostring(g.start),
        tostring(g.sweep),
        tostring(g.reverse),
        tostring(H.percentScale)
    )
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
    if feed then
        pool.fedFor, pool.fedAt = changedAt, GetTime()
    end
end

local function HideEased(pool)
    for i = 1, #pool do
        pool[i].tex:Hide()
        pool[i].bar:Hide()
    end
    pool.layoutKey = nil
end

-- Bands to set at once next time (a new target: no easing over from the last one's value).
local easeNow = {}

-- When the game says a value changed (it doesn't say how).
local changes = {} -- "playerHp:hp" -> GetTime() the game last said that value changed
local UNIT_KEY = { player = "playerHp", target = "targetHp", pet = "petHp" }
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
        if
            db[key .. "Smooth"]
            and EasedOK()
            and db[key .. "Style"] ~= "segmented"
            and type(UnitHealthPercent) == "function"
        then
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
        local pwr = {
            color = PowerColor(key, token),
            token = token,
            track = pwTrack,
            changed = NO_EVENTS[unit] and math.floor(GetTime() * 5) or changes[key .. ":pw"],
        }
        local powerPct = function(curve) return UnitPowerPercent(unit, ptype, false, curve) end
        if pwTrack.token ~= token then
            ResetTrack(key .. ":pw")
            pwTrack.token = token
        end -- shapeshifted
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
            if
                db[key .. "Smooth"]
                and EasedOK()
                and db[key .. "Style"] ~= "segmented"
                and type(UnitPowerPercent) == "function"
            then
                pwr.frac, pwr.easedOn, pwr.eased = 0, true, SafeCall(UnitPowerPercent, unit, ptype)
            else
                pwr.frac = 1
                pwr.gate = type(UnitPowerPercent) == "function" and Gate(powerPct) or nil
                if not pwr.gate then pwr.frac = 0 end
            end
            pwr.hidden = {
                value = pw,
                pct = (token == "MANA" and type(UnitPowerPercent) == "function") and HiddenPercent100(powerPct) or nil,
            }
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

-- For the files loaded after this one.
H.GLOW_TIME = GLOW_TIME
H.FLASH_TIME = FLASH_TIME
H.bigHitAt = bigHitAt
H.NO_EVENTS = NO_EVENTS
H.Track = Track
H.ResetTrack = ResetTrack
H.Step = Step
H.DrawEased = DrawEased
H.HideEased = HideEased
H.easeNow = easeNow
H.UnitState = UnitState
H.Wanted = Wanted
H.tracks = tracks
H.HALF_PLANE = HALF_PLANE
H.changes = changes
H.UNIT_KEY = UNIT_KEY
