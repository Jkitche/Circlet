-- Circlet: buffs and debuffs in an arc round the health rings (yours and your target's).
local ADDON_NAME, ns = ...

local db, SafeCall, Clean, CleanNumber, IsSecret = ns.db, ns.SafeCall, ns.Clean, ns.CleanNumber, ns.IsSecret

-- <key>Auras on, the arc centred on one side of the ring (<key>AuraDir: up, down, left, right,
-- the same choice as the floating numbers), just outside the band and clear of the badges:
-- debuffs on the inner row, buffs on a row outside it. <key>AuraShow picks both / buffs /
-- debuffs, <key>AuraMine only the ones you cast, <key>AuraMax how many of each kind,
-- <key>AuraSize the icons' size (%), <key>AuraTime the game's countdown numbers on them,
-- <key>AuraGap the px between icons in a row, <key>AuraRowGap the px between the two rows.
--
-- In combat the game hides most of an aura from addons (its icon, time and stacks can be
-- secret). So nothing is read: the icon goes straight to the texture, the time to a cooldown
-- swipe through the game's own duration object, and the stacks to the game's display count.
-- Readable values (out of combat, older clients) are used the plain way.

local DIR_ANGLE = { up = 90, down = 270, left = 180, right = 0 }
local MAX_SWEEP = math.rad(170) -- an arc never wraps further than this round the ring

-- Previews and edit mode: a few stand-ins.
local SAMPLE = {
    debuffs = { "Interface\\Icons\\Ability_Warrior_Sunder", "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
                "Interface\\Icons\\Ability_Rogue_Garrote" },
    buffs = { "Interface\\Icons\\Spell_Holy_WordFortitude", "Interface\\Icons\\Spell_Nature_Regeneration",
              "Interface\\Icons\\Spell_Holy_MagicalSentry", "Interface\\Icons\\Spell_Nature_Thorns" },
}

local DEBUFF_RED = { 0.80, 0.10, 0.10 }
local BUFF_EDGE = { 0, 0, 0 }

local dirty = { playerHp = true, targetHp = true }
ns.Listen({ "UNIT_AURA" }, function(_, unit)
    if unit == "player" then dirty.playerHp = true elseif unit == "target" then dirty.targetHp = true end
end)
ns.Listen({ "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD" }, function()
    dirty.targetHp = true; dirty.playerHp = true
end)

---------------------------------------------------------------- reading
-- Up to `max` auras of a kind on the unit (filter HELPFUL / HARMFUL, maybe |PLAYER).
local function Read(unit, filter, max)
    local out = {}
    local api = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 40 do
        if #out >= max then break end
        local a
        if api then
            a = SafeCall(api, unit, i, filter)
            if type(a) ~= "table" then break end
        else
            local get = filter:find("HARMFUL") and UnitDebuff or UnitBuff
            if not get then break end
            local name, icon, count, dispel, duration, expires = SafeCall(get, unit, i, filter:find("PLAYER") and "PLAYER" or nil)
            if name == nil then break end
            a = { icon = icon, applications = count, dispelName = dispel, duration = duration, expirationTime = expires }
        end
        out[#out + 1] = a
    end
    return out
end

---------------------------------------------------------------- the icons
local function Holder(v, frame)
    if v.auras then return v.auras end
    local h = CreateFrame("Frame", nil, frame)
    h:SetAllPoints(frame)
    h:SetFrameLevel(frame:GetFrameLevel() + 7)
    v.auras = { holder = h, icons = {} }
    return v.auras
end

local function Icon(A, i)
    local b = A.icons[i]
    if b then return b end
    local h = A.holder
    b = CreateFrame("Frame", nil, h)
    b:SetFrameLevel(h:GetFrameLevel() + 1)
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetAllPoints(b)
    b.edge:SetColorTexture(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    if ok and cd then
        cd:SetAllPoints(b.icon)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetReverse then cd:SetReverse(true) end
        b.cd = cd
    end
    -- Above the cooldown's swipe.
    b.top = CreateFrame("Frame", nil, b)
    b.top:SetAllPoints(b)
    b.top:SetFrameLevel(b:GetFrameLevel() + 3)
    b.count = b.top:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
    b:Hide()
    A.icons[i] = b
    return b
end

-- The time left, as a swipe: the game's own duration object when it has one (works with hidden
-- times), else the readable start and length; none if it doesn't run out.
local function SetTime(b, unit, a)
    local cd = b.cd
    if not cd then return end
    local id = a.auraInstanceID
    local get = C_UnitAuras and C_UnitAuras.GetAuraDuration
    if unit and id ~= nil and get then
        local ok, dur = pcall(get, unit, id)
        if ok and dur and pcall(cd.SetCooldownFromDurationObject, cd, dur) then cd:Show() return end
    end
    local d, e = CleanNumber(a.duration), CleanNumber(a.expirationTime)
    if d and e and d > 0 then
        cd:SetCooldown(e - d, d)
        cd:Show()
    else
        if cd.Clear then cd:Clear() end
        cd:Hide()
    end
end

-- The stack count, through the game's own display count when it has one (hidden-safe).
local function SetCount(b, unit, a)
    local fs = b.count
    local get = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
    if unit and a.auraInstanceID ~= nil and get then
        local ok, txt = pcall(get, unit, a.auraInstanceID, 2, 99)
        if ok and pcall(fs.SetText, fs, txt) then return end
    end
    local n = CleanNumber(a.applications)
    fs:SetText((n and n > 1) and tostring(n) or "")
end

local function EdgeColor(a, debuff)
    if not debuff then return BUFF_EDGE end
    local kind = Clean(a.dispelName)
    local c = type(kind) == "string" and DebuffTypeColor and DebuffTypeColor[kind]
    if c then return { c.r, c.g, c.b } end
    return DEBUFF_RED
end

-- Fills the icons from the unit's auras (or the samples), in order: debuffs then buffs.
local function Fill(key, A, unit)
    local show = db[key .. "AuraShow"] or "both"
    local max = math.floor(tonumber(db[key .. "AuraMax"]) or 8)
    local mine = db[key .. "AuraMine"] and "|PLAYER" or ""
    local lists = {}
    if show ~= "buffs" then
        lists.debuffs = unit and Read(unit, "HARMFUL" .. mine, max) or {}
        if not unit then for i = 1, math.min(max, #SAMPLE.debuffs) do lists.debuffs[i] = { icon = SAMPLE.debuffs[i], sample = i } end end
    end
    if show ~= "debuffs" then
        lists.buffs = unit and Read(unit, "HELPFUL" .. mine, max) or {}
        if not unit then for i = 1, math.min(max, #SAMPLE.buffs) do lists.buffs[i] = { icon = SAMPLE.buffs[i], sample = i } end end
    end
    A.rows = {}
    local n = 0
    for _, kind in ipairs({ "debuffs", "buffs" }) do
        local list = lists[kind]
        if list and #list > 0 then
            local row = {}
            for _, a in ipairs(list) do
                n = n + 1
                local b = Icon(A, n)
                pcall(b.icon.SetTexture, b.icon, a.icon) -- may be hidden: passed on as it is
                local c = EdgeColor(a, kind == "debuffs")
                b.edge:SetColorTexture(c[1], c[2], c[3], 1)
                if a.sample then
                    if b.cd then b.cd:SetCooldown(GetTime() - a.sample * 4, 30 + a.sample * 10); b.cd:Show() end
                    b.count:SetText(a.sample == 2 and "3" or "")
                else
                    SetTime(b, unit, a)
                    SetCount(b, unit, a)
                end
                if b.cd and b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(not db[key .. "AuraTime"]) end
                row[#row + 1] = b
            end
            A.rows[#A.rows + 1] = row
        end
    end
    for i = n + 1, #A.icons do A.icons[i]:Hide() end
end

---------------------------------------------------------------- drawing
local function HideAll(A)
    for _, b in ipairs(A.icons) do b:Hide() end
    A.rows = nil
end

-- Lays each row out along an arc centred on the chosen side, spreading out from the middle.
local function Place(key, A, frame, geom, d)
    local pct = (tonumber(db[key .. "AuraSize"]) or 100) / 100
    local s = math.max(10, math.floor(geom.R * 0.34 * pct + 0.5))
    local center = math.rad(DIR_ANGLE[db[key .. "AuraDir"]] or 270)
    -- Clear of the band and the badges sitting on it.
    local r = geom.R + math.max(geom.T / 2, (d or 0) / 2) + 3 + s / 2
    local gap = math.max(0, tonumber(db[key .. "AuraGap"]) or 2)
    local rowGap = math.max(0, tonumber(db[key .. "AuraRowGap"]) or 2)
    local fontSize = math.max(6, math.floor(s * 0.5 * ((tonumber(db[key .. "AuraTextSize"]) or 100) / 100) + 0.5))
    for _, row in ipairs(A.rows or {}) do
        local step = (s + gap) / r
        local fit = math.max(1, math.floor(MAX_SWEEP / step) + 1)
        local n = #row
        for i, b in ipairs(row) do
            if i > fit then
                b:Hide()
            else
                local shown = math.min(n, fit)
                local a = center + (i - 1 - (shown - 1) / 2) * step
                local k = string.format("%.1f:%.3f:%d", r, a, s)
                if b.k ~= k then
                    b.k = k
                    b:ClearAllPoints()
                    b:SetPoint("CENTER", frame, "CENTER", r * math.cos(a), r * math.sin(a))
                    b:SetSize(s, s)
                end
                if b.fontSize ~= fontSize then
                    b.fontSize = fontSize
                    b.count:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
                end
                b:Show()
            end
        end
        r = r + s + rowGap
    end
end

function ns.DrawVitalsAuras(key, v, st, frame, geom, d)
    if key ~= "playerHp" and key ~= "targetHp" then return end
    local A = v.auras
    if not db[key .. "Auras"] then
        if A then HideAll(A) end
        return
    end
    A = Holder(v, frame)
    local unit = st.unit
    if dirty[key] or A.unit ~= unit or not A.rows or (A.fillAt and GetTime() - A.fillAt > 1) then
        dirty[key] = false
        A.unit = unit
        A.fillAt = GetTime()
        Fill(key, A, unit)
    end
    Place(key, A, frame, geom, d)
    A.holder:Show()
end

function ns.HideVitalsAuras(v)
    if v.auras then HideAll(v.auras) end
end

-- Settings that change what's in the arc refill it.
function ns.VitalsAurasDirty(key) dirty[key] = true end
