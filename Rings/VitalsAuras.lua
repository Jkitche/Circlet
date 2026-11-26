-- Circlet: buffs and debuffs in an arc round the health rings (yours and your target's).
local ADDON_NAME, ns = ...

local db, SafeCall = ns.db, ns.SafeCall

-- <key>Auras on, the arc centred on one side of the ring (<key>AuraDir: up, down, left, right,
-- the same choice as the floating numbers), just outside the band and clear of the badges:
-- debuffs on the inner row, buffs on a row outside it. <key>AuraShow picks both / buffs /
-- debuffs, <key>AuraMine only the ones you cast, <key>AuraMax how many of each kind,
-- <key>AuraSize the icons' size (%), <key>AuraTime the game's countdown numbers on them,
-- <key>AuraGap the px between icons in a row, <key>AuraRowGap the px between the two rows.
--
-- In combat the game hands addons each aura as one hidden value: not even its icon can be
-- read off it. So the real icons are the game's own aura containers (CustomAuraContainer-
-- Template): Circlet gives each button its icon texture, border, sweep and stack text, and the
-- game fills them in from code that can see the aura. Nothing hidden passes through Circlet.
--
-- A container only lays its buttons out in a straight row, and in combat addons can't move
-- them. So each spot on the arc is its own container showing the first k auras in a row,
-- inside a small window of ours that clips all but the k-th: spot k shows aura k, and the
-- windows (ours, free to move) sit on the arc. How many auras there are (for centring the arc,
-- and whether there's a debuff row at all) comes from plain lists of their ids or slots.
--
-- Containers are set up and dressed out of combat (their buttons are the game's while auras
-- are hidden); a change asked for in combat waits for it to end. Previews and edit mode with
-- nothing to show use a few stand-in icons of our own.

local DIR_ANGLE = { up = 90, down = 270, left = 180, right = 0 }
local EASE_RATE = 9 -- how fast a spot slides to a new place (higher is quicker; ~0.3s to settle)
local MAX_SWEEP = math.rad(170) -- an arc never wraps further than this round the ring
local LIVE_UNIT = { playerHp = "player", targetHp = "target" }
local KINDS = { "debuffs", "buffs" }
local FILTER = { debuffs = "HARMFUL", buffs = "HELPFUL" }
local INNER_GAP = 4 -- px between the buttons inside a container's row (all but one clipped)
local STYLE_PRESERVE = 3 -- Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset

-- Previews and edit mode: a few stand-ins.
local SAMPLE = {
    debuffs = { "Interface\\Icons\\Ability_Warrior_Sunder", "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
                "Interface\\Icons\\Ability_Rogue_Garrote" },
    buffs = { "Interface\\Icons\\Spell_Holy_WordFortitude", "Interface\\Icons\\Spell_Nature_Regeneration",
              "Interface\\Icons\\Spell_Holy_MagicalSentry", "Interface\\Icons\\Spell_Nature_Thorns" },
}
local SAMPLE_EDGE = { debuffs = { 0.80, 0.10, 0.10 }, buffs = { 0, 0, 0 } }

local function InCombat() return InCombatLockdown and InCombatLockdown() end

local function NoMouse(f)
    if f.EnableMouse then pcall(f.EnableMouse, f, false) end
    if f.SetMouseClickEnabled then pcall(f.SetMouseClickEnabled, f, false) end
    if f.SetMouseMotionEnabled then pcall(f.SetMouseMotionEnabled, f, false) end
end

local function Try(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return false end
    return pcall(fn, obj, ...)
end

local function Settings(key)
    local pct = (tonumber(db[key .. "AuraSize"]) or 100) / 100
    return {
        show = db[key .. "AuraShow"] or "both",
        mine = db[key .. "AuraMine"] and "|PLAYER" or "",
        max = math.max(1, math.floor(tonumber(db[key .. "AuraMax"]) or 8)),
        pct = pct,
        gap = math.max(0, tonumber(db[key .. "AuraGap"]) or 2),
        rowGap = math.max(0, tonumber(db[key .. "AuraRowGap"]) or 2),
        time = db[key .. "AuraTime"] and true or false,
        text = (tonumber(db[key .. "AuraTextSize"]) or 100) / 100,
    }
end

local function Holder(v, frame)
    if v.auras then return v.auras end
    local h = CreateFrame("Frame", nil, frame)
    h:SetAllPoints(frame)
    h:SetFrameLevel(frame:GetFrameLevel() + 7)
    v.auras = { holder = h, icons = {}, spots = { debuffs = {}, buffs = {} } }
    ns.vitalsAuraHolders = ns.vitalsAuraHolders or {}
    table.insert(ns.vitalsAuraHolders, v.auras)
    return v.auras
end

---------------------------------------------------------------- stand-ins (previews)
local function SampleIcon(A, i)
    local b = A.icons[i]
    if b then return b end
    local h = A.holder
    b = CreateFrame("Frame", nil, h)
    b:SetFrameLevel(h:GetFrameLevel() + 1)
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetAllPoints(b)
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

-- The stand-ins, as rows of icons in order: debuffs then buffs.
local function FillSamples(key, A, set)
    local n = 0
    A.sampleRows = {}
    for _, kind in ipairs(KINDS) do
        if set.show == "both" or set.show == kind then
            local row = {}
            for i = 1, math.min(set.max, #SAMPLE[kind]) do
                n = n + 1
                local b = SampleIcon(A, n)
                b.icon:SetTexture(SAMPLE[kind][i])
                local c = SAMPLE_EDGE[kind]
                b.edge:SetColorTexture(c[1], c[2], c[3], 1)
                if b.cd then
                    b.cd:SetCooldown(GetTime() - i * 4, 30 + i * 10); b.cd:Show()
                    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(not set.time) end
                end
                b.count:SetText(i == 2 and "3" or "")
                row[#row + 1] = b
            end
            if #row > 0 then A.sampleRows[#A.sampleRows + 1] = row end
        end
    end
    for i = n + 1, #A.icons do A.icons[i]:Hide() end
end

local function HideSamples(A)
    for _, b in ipairs(A.icons) do b:Hide() end
    A.sampleRows = nil
end

---------------------------------------------------------------- the game's containers
-- Puts our icon, border, sweep and stack text on one of a container's buttons. Out of
-- combat only (in it the button is the game's).
local function Dress(spot, b, s, set)
    local parts = spot.parts[b]
    if not parts then
        NoMouse(b)
        Try(b, "SetHideTooltipInCombat", true)
        parts = {}
        parts.edge = b:CreateTexture(nil, "BACKGROUND")
        parts.edge:SetAllPoints(b)
        parts.icon = b:CreateTexture(nil, "ARTWORK")
        parts.icon:SetPoint("TOPLEFT", 1, -1)
        parts.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
        if ok and cd then
            cd:SetAllPoints(parts.icon)
            NoMouse(cd)
            Try(cd, "SetDrawEdge", false)
            Try(cd, "SetDrawBling", false)
            Try(cd, "SetReverse", true)
            parts.cd = cd
        end
        parts.top = CreateFrame("Frame", nil, b)
        parts.top:SetAllPoints(b)
        parts.top:SetFrameLevel(b:GetFrameLevel() + 3)
        parts.count = parts.top:CreateFontString(nil, "OVERLAY")
        parts.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
        if spot.kind == "debuffs" then
            -- The border, tinted by the game in the debuff's type color.
            parts.edge:SetColorTexture(1, 1, 1, 1)
            if not Try(b, "AddDispelTypeTexture", parts.edge,
                    { style = STYLE_PRESERVE, showWhenHarmful = true, showWithoutDispelType = true }) then
                parts.edge:SetColorTexture(0.8, 0.1, 0.1, 1)
            end
        else
            parts.edge:SetColorTexture(0, 0, 0, 1)
        end
        Try(b, "SetIcon", parts.icon)
        if parts.cd then Try(b, "SetDurationCooldown", parts.cd) end
        Try(b, "SetApplicationCount", parts.count)
        spot.parts[b] = parts
    end
    Try(b, "SetSize", s, s)
    Try(parts.icon, "SetTexCoord", 0.08, 0.92, 0.08, 0.92)
    if parts.cd then Try(parts.cd, "SetHideCountdownNumbers", not set.time) end
    local px = math.max(6, math.floor(s * 0.5 * set.text + 0.5))
    if parts.px ~= px then
        parts.px = px
        Try(parts.count, "SetFont", STANDARD_TEXT_FONT, px, "OUTLINE")
    end
end

-- One spot on the arc: a clipping window of ours holding a container whose k-th button
-- is the only one inside the window.
local function Spot(A, kind, k, unit)
    local spot = A.spots[kind][k]
    if spot then return spot end
    local win = CreateFrame("Frame", nil, A.holder)
    win:SetFrameLevel(A.holder:GetFrameLevel() + 1)
    if win.SetClipsChildren then win:SetClipsChildren(true) end
    NoMouse(win)
    spot = { win = win, kind = kind, k = k, parts = {}, buttons = {}, A = A }
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, win, "CustomAuraContainerTemplate")
    if ok and c and type(c.AddAuraGroup) == "function" then
        NoMouse(c)
        Try(c, "SetUnit", unit)
        spot.c = c
        spot.unit = unit
    else
        spot.broken = true -- this client has no containers for addons
    end
    A.spots[kind][k] = spot
    return spot
end

-- (Re)sets a spot's group from the settings. Out of combat only.
local function SetUpSpot(spot, set, s)
    local c = spot.c
    if not c then return end
    local filter = FILTER[spot.kind] .. set.mine
    local layout = { elementWidth = s, elementHeight = s, elementSpacing = INNER_GAP }
    if not spot.group then
        local opts = {
            maxFrameCount = spot.k,
            layout = layout,
            initializeFrame = function(b)
                spot.buttons[#spot.buttons + 1] = b
                -- One the game makes in combat is dressed when it ends.
                if not InCombat() then pcall(Dress, spot, b, spot.s or s, spot.set or set) else spot.A.sig = nil end
            end,
        }
        spot.s, spot.set = s, set
        spot.group = Try(c, "AddAuraGroup", "a", filter, opts)
        if not spot.group then spot.broken = true return end
    else
        Try(c, "SetAuraGroupFilterString", "a", filter)
        Try(c, "SetAuraGroupLayout", "a", layout)
    end
    spot.s, spot.set = s, set
    for _, b in ipairs(spot.buttons) do pcall(Dress, spot, b, s, set) end
    -- Its row starts this far left of the window, so only button k is inside it.
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", spot.win, "TOPLEFT", -(spot.k - 1) * (s + INNER_GAP), 0)
    spot.win:SetSize(s, s)
end

-- How many auras of a kind the unit has, without reading any of them: the game's list of
-- their ids, else its list of slots (both plain, even in combat), else (out of combat) by
-- walking them. If none of those answer (your target's in combat, on some clients), all the
-- spots stay open: each shows an aura only if there is one, so nothing's missed, though the
-- arc can't be centred on how many there really are. Your own auras can be counted, so your
-- buffs only move out a row when you have debuffs.
local function SlotCount(ok, _token, ...)
    if not ok then return nil end
    return select("#", ...)
end

local function Count(unit, filter, max)
    local ids = C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs
    if ids then
        local t = SafeCall(ids, unit, filter, max)
        if type(t) == "table" then return #t end
    end
    local slots = C_UnitAuras and C_UnitAuras.GetAuraSlots
    if slots then
        local n = SlotCount(pcall(slots, unit, filter, max))
        if n then return n end
    end
    if not InCombat() then
        local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
        if get then
            local n = 0
            for i = 1, max do
                local a = SafeCall(get, unit, i, filter)
                if not ns.IsSecret(a) and a == nil then break end
                n = n + 1
            end
            return n
        end
    end
end

local function CountOf(unit, filter, max)
    return math.min(max, Count(unit, filter, max) or max)
end

local function HideSpots(A)
    for _, kind in ipairs(KINDS) do
        for _, spot in pairs(A.spots[kind]) do spot.win:Hide() end
    end
end

---------------------------------------------------------------- drawing
-- Rows of things to place: each { size, items = { show(i, x, y), ... } }.
local function IconSize(geom, set) return math.max(10, math.floor(geom.R * 0.34 * set.pct + 0.5)) end

local function Arc(key, A, frame, geom, d, set, rows, s)
    s = s or IconSize(geom, set)
    local center = math.rad(DIR_ANGLE[db[key .. "AuraDir"]] or 270)
    -- Clear of the band and the badges sitting on it.
    local r = geom.R + math.max(geom.T / 2, (d or 0) / 2) + 3 + s / 2
    for _, row in ipairs(rows) do
        local step = (s + set.gap) / r
        local fit = math.max(1, math.floor(MAX_SWEEP / step) + 1)
        local shown = math.min(row.n, fit)
        for i = 1, row.slots do
            if i > shown then
                row.hide(i)
            else
                local a = center + (i - 1 - (shown - 1) / 2) * step
                row.place(i, a, r, s)
            end
        end
        r = r + s + set.rowGap
    end
    return s
end

-- Puts a spot at angle a, radius r round the ring's centre. When its place changes (a row
-- opening inside it as combat starts, the arc re-centring as auras come and go) it slides
-- there round the ring, easing in, rather than jumping. One just appearing starts in place.
local function PlaceAt(f, frame, a, r, s, dt)
    if not f:IsShown() or not f.ea then
        f.ea, f.er = a, r
    else
        local k = 1 - math.exp(-(dt or 0) * EASE_RATE)
        f.ea = f.ea + (a - f.ea) * k
        f.er = f.er + (r - f.er) * k
        if math.abs(a - f.ea) < 0.0005 and math.abs(r - f.er) < 0.05 then f.ea, f.er = a, r end
    end
    local x, y = f.er * math.cos(f.ea), f.er * math.sin(f.ea)
    local key = string.format("%.1f:%.1f:%d", x, y, s)
    if f.atKey ~= key then
        f.atKey = key
        f:ClearAllPoints()
        f:SetPoint("CENTER", frame, "CENTER", x, y)
        f:SetSize(s, s)
    end
    f:Show()
end

local function Step(A)
    local now = GetTime()
    local dt = A.drawnAt and math.min(0.25, now - A.drawnAt) or 0
    A.drawnAt = now
    return dt
end

local function DrawSamples(key, A, frame, geom, d, set)
    if not A.sampleRows or A.sampleKey ~= key then FillSamples(key, A, set); A.sampleKey = key end
    local rows = {}
    for _, list in ipairs(A.sampleRows) do
        rows[#rows + 1] = { n = #list, slots = #list,
            hide = function(i) list[i]:Hide() end,
            place = function(i, a, r, s)
                local b = list[i]
                PlaceAt(b, frame, a, r, s, A.dt)
                local px = math.max(6, math.floor(s * 0.5 * set.text + 0.5))
                if b.px ~= px then b.px = px; b.count:SetFont(STANDARD_TEXT_FONT, px, "OUTLINE") end
            end }
    end
    Arc(key, A, frame, geom, d, set, rows)
end

local function DrawLive(key, A, frame, geom, d, set, unit)
    local s = IconSize(geom, set)
    local sig = table.concat({ unit, set.show, set.mine, set.max, s, tostring(set.time),
        string.format("%.2f", set.text) }, "|")
    if A.sig ~= sig and not InCombat() then
        for _, kind in ipairs(KINDS) do
            if set.show == "both" or set.show == kind then
                for k = 1, set.max do SetUpSpot(Spot(A, kind, k, unit), set, s) end
            end
        end
        A.sig, A.s = sig, s
    end
    -- In combat the game's buttons keep the size they were set to; so do the windows.
    s = A.s or s
    local rows = {}
    for _, kind in ipairs(KINDS) do
        local list = A.spots[kind]
        if (set.show == "both" or set.show == kind) and list[1] and not list[1].broken then
            local n = CountOf(unit, FILTER[kind] .. set.mine, set.max)
            local slots = 0
            for k in pairs(list) do if k > slots then slots = k end end
            if n > 0 then
                rows[#rows + 1] = { n = n, slots = slots,
                    hide = function(i) if list[i] then list[i].win:Hide() end end,
                    place = function(i, a, r, sz)
                        local spot = list[i]
                        if spot and not spot.broken and i <= set.max then PlaceAt(spot.win, frame, a, r, sz, A.dt)
                        elseif spot then spot.win:Hide() end
                    end }
            else
                for _, spot in pairs(list) do spot.win:Hide() end
            end
        else
            for _, spot in pairs(list) do spot.win:Hide() end
        end
    end
    Arc(key, A, frame, geom, d, set, rows, s)
end

function ns.DrawVitalsAuras(key, v, st, frame, geom, d)
    if key ~= "playerHp" and key ~= "targetHp" then return end
    local A = v.auras
    if not db[key .. "Auras"] then
        if A then HideSamples(A); HideSpots(A); A.holder:Hide() end
        return
    end
    A = Holder(v, frame)
    A.dt = Step(A)
    local set = Settings(key)
    local unit = st.unit and LIVE_UNIT[key]
    if unit and not ns.vitalsAurasNoContainers then
        HideSamples(A)
        DrawLive(key, A, frame, geom, d, set, unit)
    else
        HideSpots(A)
        DrawSamples(key, A, frame, geom, d, set)
    end
    A.holder:Show()
end

function ns.HideVitalsAuras(v)
    if v.auras then HideSamples(v.auras); HideSpots(v.auras); v.auras.holder:Hide() end
end

-- Settings that change what's in the arc: the stand-ins refill, the containers re-set.
function ns.VitalsAurasDirty(key)
    for _, f in pairs(ns.vitalsAuraHolders or {}) do f.sampleRows = nil; f.sig = nil end
end
-- (A change asked for in combat is applied on the first frame after it ends: DrawLive.)
