-- Circlet: Health rings: floating damage and healing numbers, drawing a ring each frame, and the four rings.
local _, ns = ...

local db, CreateLiveRing, SafeCall, Clean = ns.db, ns.CreateLiveRing, ns.SafeCall, ns.Clean
local DrawArc = ns.DrawArc
local H = ns.HealthRings
local REACTION = H.REACTION
local PowerColor = H.PowerColor
local Track = H.Track
local ResetTrack = H.ResetTrack
local Step = H.Step
local DrawEased = H.DrawEased
local HideEased = H.HideEased
local easeNow = H.easeNow
local UnitState = H.UnitState
local Wanted = H.Wanted
local Parts = H.Parts
local HideBadge = H.HideBadge
local DrawLevel = H.DrawLevel
local DrawCombat = H.DrawCombat
local DrawPortrait = H.DrawPortrait
local PlaceTexts = H.PlaceTexts
local HideLayer = H.HideLayer
local Whiten = H.Whiten
local Effects = H.Effects
local BigHitFlash = H.BigHitFlash
local HEALTH_TRAIL = H.HEALTH_TRAIL
local Put = H.Put
local HealthText = H.HealthText
local PowerText = H.PowerText

---------------------------------------------------------------------------
-- Damage and healing numbers (<key>Float): what the unit takes, floating up off the ring
---------------------------------------------------------------------------
-- Each hit or heal the unit takes (UNIT_COMBAT) pops up at the top of the ring and floats up
-- and away, fading: damage (red on yours, white on others, crits bigger and gold with a pop),
-- heals green with a +, and misses as words (Dodge, Parry, Block...). In combat the amount is
-- hidden from addons, so it's handed to the font string as it is (the game draws it; it can't
-- be formatted or added up); readable amounts are shortened (12.3k).
local FLOAT_TIME, FLOAT_MAX = 1.5, 8
local FLOAT_DIRS = { up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
local MISS_WORDS = {
    MISS = "Miss",
    DODGE = "Dodge",
    PARRY = "Parry",
    BLOCK = "Block",
    ABSORB = "Absorb",
    RESIST = "Resist",
    IMMUNE = "Immune",
    DEFLECT = "Deflect",
    EVADE = "Evade",
    REFLECT = "Reflect",
}
local floats = {} -- ring key -> { { kind, amount, crit, word, at, drift } ... }, oldest first

local function AddFloat(key, action, flag, amount)
    if not db[key .. "Float"] then return end
    local f
    if action == "WOUND" then
        f = { kind = "dmg", amount = amount, crit = (flag == "CRITICAL" or flag == "CRUSHING") }
    elseif action == "HEAL" then
        f = { kind = "heal", amount = amount, crit = flag == "CRITICAL" }
    elseif MISS_WORDS[action] then
        f = { kind = "miss", word = MISS_WORDS[action] }
    else
        return
    end
    local list = floats[key] or {}
    floats[key] = list
    -- Side to side by turns, a little at random, so a burst of hits doesn't stack up.
    list.n = (list.n or 0) + 1
    f.at, f.drift = GetTime(), ((list.n % 3) - 1) * 0.55 + (math.random() - 0.5) * 0.3
    table.insert(list, f)
    while #list > FLOAT_MAX do
        table.remove(list, 1)
    end
end

local function ShortAmount(n)
    n = math.floor(math.abs(n) + 0.5)
    if n >= 1e6 then return string.format("%.1fm", n / 1e6) end
    if n >= 1e4 then return string.format("%.1fk", n / 1e3) end
    return tostring(n)
end

-- Puts an amount on a font string with a prefix ("+" for heals), hidden or not.
local function SetAmount(fs, prefix, amount)
    if amount == nil then
        fs:SetText(prefix)
        return
    end
    if ns.IsSecret(amount) then
        if not pcall(fs.SetFormattedText, fs, prefix .. "%s", amount) then
            if not pcall(fs.SetText, fs, amount) then fs:SetText(prefix ~= "" and prefix or "Hit") end
        end
        return
    end
    local n = tonumber(amount)
    fs:SetText(prefix .. (n and ShortAmount(n) or tostring(amount)))
end

local function DrawFloats(key, v, frame, geom, now)
    local list = floats[key]
    local pool = v.floats
    if not pool then
        pool = {}
        v.floats = pool
        v.ff = CreateFrame("Frame", nil, frame)
        v.ff:SetAllPoints(frame)
        v.ff:SetFrameLevel(frame:GetFrameLevel() + 7)
    end
    local used = 0
    if list and db[key .. "Float"] then
        local i = 1
        while i <= #list do
            if now - list[i].at >= FLOAT_TIME then
                table.remove(list, i)
            else
                i = i + 1
            end
        end
        local size = math.max(9, geom.R * 0.3) * (tonumber(db[key .. "FloatTextSize"]) or 100) / 100
        for _, f in ipairs(list) do
            used = used + 1
            local fs = pool[used]
            if not fs then
                fs = v.ff:CreateFontString(nil, "OVERLAY")
                fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
                fs:SetShadowOffset(1, -1)
                pool[used] = fs
            end
            local t = (now - f.at) / FLOAT_TIME
            -- A crit pops in big and settles; everything rises, drifts aside and fades.
            local scale = f.crit and (1.25 + 0.5 * math.max(0, 1 - t / 0.12)) or 1
            local px = math.floor(size * scale * (f.kind == "miss" and 0.8 or 1) + 0.5)
            if fs.px ~= px then
                fs.px = px
                fs:SetFont(STANDARD_TEXT_FONT, px, "OUTLINE")
            end
            local ease = 1 - (1 - t) ^ 2
            -- <key>FloatDir: which side they start on and float out from (up, down, left, right);
            -- the drift aside runs across that.
            local dx, dy =
                FLOAT_DIRS[db[key .. "FloatDir"]] and FLOAT_DIRS[db[key .. "FloatDir"]][1] or 0,
                FLOAT_DIRS[db[key .. "FloatDir"]] and FLOAT_DIRS[db[key .. "FloatDir"]][2] or 1
            local out = geom.R + geom.T + size * (dx ~= 0 and 1.2 or 0.2) + ease * geom.R * 0.9
            local side = f.drift * geom.R * 0.6 * ease
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", frame, "CENTER", dx * out + dy * side, dy * out + dx * side)
            if f.kind == "heal" then
                fs:SetTextColor(0.35, 1, 0.35)
                SetAmount(fs, "+", f.amount)
            elseif f.kind == "miss" then
                fs:SetTextColor(0.8, 0.8, 0.85)
                fs:SetText(f.word)
            else
                if f.crit then
                    fs:SetTextColor(1, 0.8, 0.2)
                elseif key == "playerHp" then
                    fs:SetTextColor(1, 0.3, 0.25)
                else
                    fs:SetTextColor(1, 1, 1)
                end
                SetAmount(fs, "", f.amount)
            end
            fs:SetAlpha(t < 0.6 and 1 or math.max(0, 1 - (t - 0.6) / 0.4))
            fs:Show()
        end
    end
    for i = used + 1, #pool do
        pool[i]:Hide()
    end
end

local function DrawVitals(key, st, frame, geom)
    local v = Parts(frame)
    if not st or not geom or geom.R <= 0 then
        HideLayer(v.border)
        HideLayer(v.track)
        HideLayer(v.fill)
        for _, b in ipairs({ "h", "p" }) do
            for _, l in pairs(v[b]) do
                HideLayer(l)
            end
        end
        HideEased(v.eh)
        HideEased(v.ep)
        v.hp:SetText("")
        v.hp2:SetText("")
        v.pw:SetText("")
        v.name:SetText("")
        v.portrait:Hide()
        HideBadge(v.lvl)
        HideBadge(v.cmb)
        if v.floats then
            for _, fs in ipairs(v.floats) do
                fs:Hide()
            end
        end
        if ns.HideVitalsFx then ns.HideVitalsFx(v, frame) end
        if ns.HideVitalsAuras then ns.HideVitalsAuras(v) end
        return
    end
    local b = ns.BorderWidthOf(key)
    local inner = geom.R - geom.T / 2 - b
    local now = GetTime()
    v.lastColor = st.color -- (tests)
    Effects(key, v.h, st.hpTrack, geom, frame, st.color, now, HEALTH_TRAIL)
    BigHitFlash(key, v.h, geom, frame, now)
    DrawFloats(key, v, frame, geom, now)
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
        local layoutKey = string.format(
            "%.2f:%.2f:%s:%s:%s:%s:%d",
            g2.R,
            T2,
            tostring(g2.style),
            tostring(g2.start),
            tostring(g2.sweep),
            tostring(g2.reverse),
            b
        )
        if v.layoutKey ~= layoutKey then
            v.layoutKey = layoutKey
            DrawArc(v.track, 0, 1, frame, g2)
            if b > 0 then
                local gb = {
                    R = g2.R,
                    T = T2 + 2 * b,
                    step = g2.step,
                    style = g2.style,
                    notches = g2.notches,
                    start = g2.start,
                    sweep = g2.sweep,
                    reverse = g2.reverse,
                }
                DrawArc(v.border, 0, 1, frame, gb)
            else
                HideLayer(v.border)
            end
        end
        local c = p.color
        for _, l in ipairs(v.fill) do
            l:SetColorTexture(c.r, c.g, c.b, 1)
        end
        DrawArc(v.fill, 0, p.frac or 0, frame, g2, nil, ns.Shade(key, c))
        if p.gate then
            for _, l in ipairs(v.fill) do
                if l.arcMid and l:IsShown() then pcall(l.SetAlpha, l, p.gate(l.arcMid)) end
            end
            v.gated = true
        elseif v.gated then
            for _, l in ipairs(v.fill) do
                l:SetAlpha(1)
            end
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
        HideLayer(v.border)
        HideLayer(v.track)
        HideLayer(v.fill)
        for _, l in pairs(v.p) do
            HideLayer(l)
        end
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
    if ns.DrawVitalsFx then ns.DrawVitalsFx(key, v, st, frame, geom, d, now) end
    if ns.DrawVitalsAuras then ns.DrawVitalsAuras(key, v, st, frame, geom, d) end
    if st.name ~= nil then
        v.name:SetTextColor(1, 0.82, 0.25)
        if st.level and not db[key .. "Level"] then
            Put(v.name, "%s |cffbbbbbb%d|r", st.name, st.level)
        else
            Put(v.name, nil, st.name)
        end
    else
        v.name:SetText("")
    end
end

---------------------------------------------------------------- the rings
local SAMPLE_NAMES = { playerHp = nil, targetHp = "Defias Bandit", petHp = "Wolf" }

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
    if t < 0.05 then
        ResetTrack(key .. ":sample:hp")
        ResetTrack(key .. ":sample:pw")
    end
    Step(key, hpTrack, hpTarget, now, true)
    Step(key, pwTrack, pwTarget, now, false)
    local hpf, pwf = hpTrack.shown, pwTrack.shown
    local mana = math.floor(t / 12.8) % 2 == 0
    local token = mana and "MANA" or "RAGE"
    local st = {
        color = db[key .. "ColorMode"] == "class"
                and (key == "targetHp" and REACTION.hostile or db[key .. "Colors"].health)
            or db[key .. "Colors"].health,
        frac = hpf,
        hpFrac = hpTarget,
        hold = 0.5,
        vitals = key,
        hpTrack = hpTrack,
        hpText = {
            pct = string.format("%d%%", math.floor(hpTarget * 100 + 0.5)),
            value = ShortAmount(math.floor(hpTarget * 2480)),
        },
    }
    if db[key .. "Power"] then
        local pc = PowerColor(key, token)
        st.power = {
            frac = pwf,
            real = pwTarget,
            color = pc,
            token = token,
            track = pwTrack,
            text = mana and string.format("%d%%", math.floor(pwTarget * 100 + 0.5))
                or tostring(math.floor(pwTarget * 100)),
        }
    end
    if db[key .. "Name"] then
        st.name = SAMPLE_NAMES[key] or Clean(SafeCall(UnitName, "player")) or "You"
        if key == "targetHp" then
            st.level = 18
        elseif key == "totHp" then
            st.level = 20
        elseif key == "petHp" then
            st.level = 19
        end
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
            { id = "FloatText", name = "Damage & healing", desc = "The numbers floating up off the ring." },
            key ~= "totHp" and key ~= "petHp" and {
                id = "AuraText",
                name = "Buff stacks",
                desc = "The stack counts on the buff and debuff icons.",
            } or nil,
        },
        decorate = function(st, frame, geom) DrawVitals(key, st, frame, geom) end,
    })
    return rings[key]
end

local playerRing = MakeRing("playerHp", "player")
local targetRing = MakeRing("targetHp", "target")
local totRing = MakeRing("totHp", "targettarget")
local petRing = MakeRing("petHp", "pet")

-- For the files loaded after this one.
H.playerRing = playerRing
H.targetRing = targetRing
H.totRing = totRing
H.petRing = petRing
H.floats = floats
H.AddFloat = AddFloat
