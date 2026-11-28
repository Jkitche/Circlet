-- Circlet: buffs and debuffs in an arc round the health rings (yours and your target's).
local ADDON_NAME, ns = ...

local db, SafeCall, Clean = ns.db, ns.SafeCall, ns.Clean

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
-- INCLUDE_NAME_PLATE_ONLY: without it the game leaves out every aura it flags as one for
-- nameplates only, which is most of an enemy's buffs (its own nameplates always ask for them).
local FILTER = { debuffs = "HARMFUL|INCLUDE_NAME_PLATE_ONLY", buffs = "HELPFUL|INCLUDE_NAME_PLATE_ONLY" }
local INNER_GAP = 4 -- px between the buttons inside a container's row (all but one clipped)
local STYLE_PRESERVE = 3 -- Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset

-- Previews and edit mode: a few stand-ins.
local SAMPLE = {
    debuffs = {
        "Interface\\Icons\\Ability_Warrior_Sunder",
        "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
        "Interface\\Icons\\Ability_Rogue_Garrote",
    },
    buffs = {
        "Interface\\Icons\\Spell_Holy_WordFortitude",
        "Interface\\Icons\\Spell_Nature_Regeneration",
        "Interface\\Icons\\Spell_Holy_MagicalSentry",
        "Interface\\Icons\\Spell_Nature_Thorns",
    },
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
        enemyBuffs = key == "targetHp" and db[key .. "AuraEnemyBuffs"] or "all",
    }
end

-- An enemy target's buffs (<key>AuraEnemyBuffs): all, only the ones that can be dispelled (the
-- game's DISPELLABLE filter), or none. Friendly units always show all of theirs.
local function KindFilter(kind, set, hostile)
    local f = FILTER[kind] .. set.mine
    if kind == "buffs" and hostile and set.enemyBuffs == "dispel" then f = f .. "|DISPELLABLE" end
    return f
end

local function KindShown(kind, set, hostile)
    if set.show ~= "both" and set.show ~= kind then return false end
    return not (kind == "buffs" and hostile and set.enemyBuffs == "none")
end

-- A buff's border in its dispel type's color (blue for magic: what Purge takes), black for one
-- with no type. The game picks the color from this map; Circlet never sees the type.
local BUFF_BORDERS
local function BuffBorders()
    if BUFF_BORDERS ~= nil then return BUFF_BORDERS end
    BUFF_BORDERS = false
    if type(CreateColor) ~= "function" then return false end
    local src = DebuffTypeColor
        or {
            Magic = { r = 0.2, g = 0.6, b = 1 },
            Curse = { r = 0.6, g = 0, b = 1 },
            Disease = { r = 0.6, g = 0.4, b = 0 },
            Poison = { r = 0, g = 0.6, b = 0 },
        }
    local map = { None = CreateColor(0, 0, 0, 1) }
    for _, name in ipairs({ "Magic", "Curse", "Disease", "Poison" }) do
        local c = src[name]
        if c then map[name] = CreateColor(c.r, c.g, c.b, 1) end
    end
    BUFF_BORDERS = map
    return map
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
                    b.cd:SetCooldown(GetTime() - i * 4, 30 + i * 10)
                    b.cd:Show()
                    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(not set.time) end
                end
                b.count:SetText(i == 2 and "3" or "")
                row[#row + 1] = b
            end
            if #row > 0 then A.sampleRows[#A.sampleRows + 1] = row end
        end
    end
    for i = n + 1, #A.icons do
        A.icons[i]:Hide()
    end
end

local function HideSamples(A)
    for _, b in ipairs(A.icons) do
        b:Hide()
    end
    A.sampleRows = nil
end

---------------------------------------------------------------- the game's containers
-- Puts our icon, border, sweep and stack text on one of a container's buttons. Out of
-- combat only (in it the button is the game's).
local function Dress(spot, b, s, set)
    local parts = spot.parts[b]
    if not parts then
        -- The game's own tooltip on mouse-over (clicks still pass through). Every button of
        -- the spot's container has it: the window clips the mouse as it clips the drawing,
        -- so only the one inside it answers. (Which one that is can't be told: the game
        -- hides its buttons' places, and it reuses them as auras come and go.)
        NoMouse(b)
        Try(b, "SetTooltipAnchorPoint", "ANCHOR_BOTTOMRIGHT")
        Try(b, "SetHideTooltipInCombat", false)
        local ok, err = pcall(b.SetMouseMotionEnabled, b, true)
        if not ok then spot.mouseErr = tostring(err) end
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
            if
                not Try(
                    b,
                    "AddDispelTypeTexture",
                    parts.edge,
                    { style = STYLE_PRESERVE, showWhenHarmful = true, showWithoutDispelType = true }
                )
            then
                parts.edge:SetColorTexture(0.8, 0.1, 0.1, 1)
            end
        else
            -- Black, or (tinted by the game) its dispel type's color: a buff you can Purge shows.
            parts.edge:SetColorTexture(1, 1, 1, 1)
            local map = BuffBorders()
            if
                not (
                    map
                    and Try(b, "AddDispelTypeTexture", parts.edge, {
                        style = STYLE_PRESERVE,
                        showWhenHarmful = true,
                        showWhenHelpful = true,
                        showWithoutDispelType = true,
                        customDispelColorMap = map,
                    })
                )
            then
                parts.edge:SetColorTexture(0, 0, 0, 1)
            end
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
local function SetUpSpot(spot, set, s, hostile)
    local c = spot.c
    if not c then return end
    local filter = KindFilter(spot.kind, set, hostile)
    spot.filter = filter
    local layout = { elementWidth = s, elementHeight = s, elementSpacing = INNER_GAP }
    if not spot.group then
        local opts = {
            maxFrameCount = spot.k,
            layout = layout,
            -- Every source, not just yours: the nameplates and DBM always give a group its
            -- candidate filters, and auras others cast (a mob's debuff on you, an enemy's own
            -- buffs) didn't show without them.
            candidateFilters = {},
            initializeFrame = function(b)
                spot.buttons[#spot.buttons + 1] = b
                -- One the game makes in combat is dressed when it ends.
                if not InCombat() then
                    pcall(Dress, spot, b, spot.s or s, spot.set or set)
                else
                    spot.A.sig = nil
                end
            end,
        }
        spot.s, spot.set = s, set
        spot.group = Try(c, "AddAuraGroup", "a", filter, opts)
        if not spot.group then
            spot.broken = true
            return
        end
    else
        Try(c, "SetAuraGroupFilterString", "a", filter)
        Try(c, "SetAuraGroupLayout", "a", layout)
    end
    Try(c, "SetAuraGroupCandidateFilters", "a", {})
    Try(c, "SetEnabled", true) -- (as the nameplates and DBM do once a container's set up)
    spot.s, spot.set = s, set
    for _, b in ipairs(spot.buttons) do
        pcall(Dress, spot, b, s, set)
    end
    -- Its row starts this far left of the window, so only button k is inside it.
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", spot.win, "TOPLEFT", -(spot.k - 1) * (s + INNER_GAP), 0)
    spot.win:SetSize(s, s)
end

-- How many auras of a kind the unit has, without reading any of them: the game's list of
-- their ids, else its list of slots (both plain, even in combat), else (out of combat) by
-- walking them. If none of those answer (in combat, on some clients), DrawLive keeps the
-- layout from the last count and leaves every spot open (each shows an aura only if there
-- is one), so nothing's missed.
local function SlotCount(ok, _token, ...)
    if not ok then return nil end
    return select("#", ...)
end

local function Count(unit, filter, max)
    local ids = C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs
    if ids then
        local t = SafeCall(ids, unit, filter, max)
        if type(t) == "table" then return #t, "ids" end
    end
    local slots = C_UnitAuras and C_UnitAuras.GetAuraSlots
    if slots then
        local n = SlotCount(pcall(slots, unit, filter, max))
        if n then return n, "slots" end
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
            return n, "walked"
        end
    end
    return nil, "unknown"
end

local countSrc = {} -- unit:filter -> how it was last counted (for /circ auradebug)
-- The count, or nil if it can't be had.
local function CountOf(unit, filter, max)
    local n, src = Count(unit, filter, max)
    countSrc[unit .. ":" .. filter] = src .. (n and (" " .. n) or "")
    return n and math.min(max, n) or nil
end

local function HideSpots(A)
    for _, kind in ipairs(KINDS) do
        for _, spot in pairs(A.spots[kind]) do
            spot.win:Hide()
        end
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
        -- Centred on n; a row that can't be counted keeps more spots open past the end (open).
        local centredOn = math.min(row.n, fit)
        local shown = math.min(row.open or row.n, fit)
        for i = 1, row.slots do
            if i > shown then
                row.hide(i)
            else
                local a = center + (i - 1 - (centredOn - 1) / 2) * step
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
        if math.abs(a - f.ea) < 0.0005 and math.abs(r - f.er) < 0.05 then
            f.ea, f.er = a, r
        end
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
    if not A.sampleRows or A.sampleKey ~= key then
        FillSamples(key, A, set)
        A.sampleKey = key
    end
    local rows = {}
    for _, list in ipairs(A.sampleRows) do
        rows[#rows + 1] = {
            n = #list,
            slots = #list,
            hide = function(i) list[i]:Hide() end,
            place = function(i, a, r, s)
                local b = list[i]
                PlaceAt(b, frame, a, r, s, A.dt)
                local px = math.max(6, math.floor(s * 0.5 * set.text + 0.5))
                if b.px ~= px then
                    b.px = px
                    b.count:SetFont(STANDARD_TEXT_FONT, px, "OUTLINE")
                end
            end,
        }
    end
    Arc(key, A, frame, geom, d, set, rows)
end

local function DrawLive(key, A, frame, geom, d, set, unit)
    local s = IconSize(geom, set)
    local sig =
        table.concat({ unit, set.show, set.mine, set.max, s, tostring(set.time), string.format("%.2f", set.text) }, "|")
    -- Whether it's an enemy (the last answer, if the game won't say right now).
    if unit ~= "player" then
        local h = Clean(SafeCall(UnitCanAttack, "player", unit))
        if h ~= nil then A.hostile = h and true or false end
    else
        A.hostile = false
    end
    local hostile = A.hostile
    -- A new target: each container off, onto the unit again, back on (as the nameplates and
    -- DBM do when a container's unit changes; allowed in combat).
    if A.rebind then
        A.rebind = nil
        for _, kind in ipairs(KINDS) do
            for _, spot in pairs(A.spots[kind]) do
                if spot.c then
                    Try(spot.c, "SetEnabled", false)
                    Try(spot.c, "SetUnit", unit)
                    if spot.group then Try(spot.c, "SetEnabled", true) end
                end
            end
        end
    end
    if A.sig ~= sig and not InCombat() then
        for _, kind in ipairs(KINDS) do
            if set.show == "both" or set.show == kind then
                for k = 1, set.max do
                    SetUpSpot(Spot(A, kind, k, unit), set, s, hostile)
                end
            end
        end
        A.sig, A.s = sig, s
    end
    -- A new target of the other reaction: its buffs' filter follows (the game allows this in
    -- combat; the nameplates do it).
    for _, kind in ipairs(KINDS) do
        local want = KindFilter(kind, set, hostile)
        for _, spot in pairs(A.spots[kind]) do
            if spot.group and spot.filter ~= want then
                spot.filter = want
                Try(spot.c, "SetAuraGroupFilterString", "a", want)
            end
        end
    end
    -- In combat the game's buttons keep the size they were set to; so do the windows.
    s = A.s or s
    -- Each kind's row. A kind that can't be counted (in combat the game may not say, even for
    -- your own auras) keeps the layout from when it last could: centred on that count, with
    -- every spot open past it in case more land. And if it was empty then, its row goes
    -- outside the others rather than inside, so nothing already showing gets pushed out
    -- for what may be no auras at all.
    A.known = A.known or {}
    local rows, late = {}, {}
    for _, kind in ipairs(KINDS) do
        local list = A.spots[kind]
        if KindShown(kind, set, hostile) and list[1] and not list[1].broken then
            local n = CountOf(unit, KindFilter(kind, set, hostile), set.max)
            local slots = 0
            for k in pairs(list) do
                if k > slots then slots = k end
            end
            local row = {
                slots = slots,
                hide = function(i)
                    if list[i] then list[i].win:Hide() end
                end,
                place = function(i, a, r, sz)
                    local spot = list[i]
                    if spot and not spot.broken and i <= set.max then
                        PlaceAt(spot.win, frame, a, r, sz, A.dt)
                    elseif spot then
                        spot.win:Hide()
                    end
                end,
            }
            if n then
                A.known[kind] = n
                if n > 0 then
                    row.n = n
                    rows[#rows + 1] = row
                elseif kind == "buffs" and hostile then
                    -- Counted none on an enemy's buffs: the game counts none of them where its
                    -- containers still show them, so the row's spots stay open, outside the
                    -- others. An empty container shows nothing.
                    row.n, row.open = 1, set.max
                    late[#late + 1] = row
                else
                    -- Really none: the row's closed, so it doesn't push the others outward.
                    for _, spot in pairs(list) do
                        spot.win:Hide()
                    end
                end
            else
                local was = A.known[kind] or 0
                row.n, row.open = math.max(1, was), set.max
                if was > 0 then
                    rows[#rows + 1] = row
                else
                    late[#late + 1] = row
                end
            end
        else
            for _, spot in pairs(list) do
                spot.win:Hide()
            end
        end
    end
    for _, row in ipairs(late) do
        rows[#rows + 1] = row
    end
    Arc(key, A, frame, geom, d, set, rows, s)
end

function ns.DrawVitalsAuras(key, v, st, frame, geom, d)
    if key ~= "playerHp" and key ~= "targetHp" then return end
    local A = v.auras
    if not db[key .. "Auras"] then
        if A then
            HideSamples(A)
            HideSpots(A)
            A.holder:Hide()
        end
        return
    end
    A = Holder(v, frame)
    A.key, A.unit = key, st.unit
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
    if v.auras then
        HideSamples(v.auras)
        HideSpots(v.auras)
        v.auras.holder:Hide()
    end
end

-- Settings that change what's in the arc: the stand-ins refill, the containers re-set.
function ns.VitalsAurasDirty(key)
    for _, f in pairs(ns.vitalsAuraHolders or {}) do
        f.sampleRows = nil
        f.sig = nil
    end
end
-- A new target starts with nothing remembered about its rows, and its containers are pointed
-- at it afresh (DrawLive): left alone they keep the last target's auras until the new one's
-- change.
ns.Listen({ "PLAYER_TARGET_CHANGED" }, function()
    for _, A in pairs(ns.vitalsAuraHolders or {}) do
        if A.key == "targetHp" then
            A.known = {}
            A.rebind = true
        end
    end
end)

-- (A change asked for in combat is applied on the first frame after it ends: DrawLive.)

-- Your target's nameplate unit (nameplate1...), if it has one showing: the nameplates read an
-- enemy's auras through that, and the game may treat it differently from "target".
local function TargetPlate()
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local plate = SafeCall(C_NamePlate.GetNamePlateForUnit, "target")
        local token = plate and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
        token = Clean(token)
        if type(token) == "string" then return token end
    end
    for i = 1, 40 do
        local token = "nameplate" .. i
        if Clean(SafeCall(UnitIsUnit, token, "target")) then return token end
    end
end

-- The names of a unit's auras through a filter (out of combat; hidden ones as "(hidden)").
local function AuraNames(unit, filt)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local names = {}
    if not get then return "no API" end
    for i = 1, 10 do
        local a = SafeCall(get, unit, i, filt)
        if ns.IsSecret(a) then
            names[#names + 1] = "(hidden)"
        elseif a == nil then
            break
        else
            local nm = a.name
            names[#names + 1] = ns.IsSecret(nm) and "(hidden)" or tostring(nm)
        end
    end
    return #names > 0 and table.concat(names, ", ") or "none"
end

-- /circ auradebug: what the buff and debuff arcs are doing, for each ring (for bug reports).
local function Safe(f, method, ...)
    local fn = f and f[method]
    if type(fn) ~= "function" then return "n/a" end
    local ok, v = pcall(fn, f, ...)
    if not ok then return "denied" end
    if ns.IsSecret(v) then return "hidden" end
    if type(v) == "table" or type(v) == "userdata" then return type(v) end
    return tostring(v)
end
ns.RegisterCommand({ "auradebug" }, function()
    ns.Print(
        "Aura arcs: in combat "
            .. tostring(InCombat() and true or false)
            .. ", containers "
            .. tostring(pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate"))
    )
    for _, A in ipairs(ns.vitalsAuraHolders or {}) do
        local set = A.key and Settings(A.key)
        ns.Print(
            string.format(
                "%s: unit %s, holder shown %s, set up %s, size %s, show %s, max %s",
                tostring(A.key),
                tostring(A.unit),
                Safe(A.holder, "IsVisible"),
                tostring(A.sig ~= nil),
                tostring(A.s),
                set and set.show or "?",
                set and set.max or "?"
            )
        )
        local unit = A.key and LIVE_UNIT[A.key]
        for _, kind in ipairs(KINDS) do
            local list, made, shown = A.spots[kind], 0, 0
            for _, spot in pairs(list) do
                made = made + 1
                if spot.win:IsShown() then shown = shown + 1 end
            end
            local filt = set and KindFilter(kind, set, A.hostile) or FILTER[kind]
            ns.Print(
                string.format(
                    "  %s: counted %s; spots made %d, shown %d",
                    kind,
                    tostring(unit and countSrc[unit .. ":" .. filt] or "-"),
                    made,
                    shown
                )
            )
            for k = 1, math.min(3, made) do
                local spot = list[k]
                if spot then
                    local c = spot.c
                    local b = c and Safe(c, "GetAuraGroupFrame", "a", k)
                    local btn = c and c.GetAuraGroupFrame and select(2, pcall(c.GetAuraGroupFrame, c, "a", k))
                    ns.Print(
                        string.format(
                            "    spot %d: window shown %s %sx%s, container %s unit %s, group %s broken %s, buttons %d (dressed %d), button %d shown %s alpha %s",
                            k,
                            tostring(spot.win:IsShown()),
                            Safe(spot.win, "GetWidth"),
                            Safe(spot.win, "GetHeight"),
                            c and "yes" or "no",
                            tostring(spot.unit),
                            tostring(spot.group),
                            tostring(spot.broken),
                            #spot.buttons,
                            (function()
                                local n = 0
                                for _ in pairs(spot.parts) do
                                    n = n + 1
                                end
                                return n
                            end)(),
                            k,
                            type(btn) == "table" and Safe(btn, "IsShown") or tostring(b),
                            type(btn) == "table" and Safe(btn, "GetAlpha") or "-"
                        )
                    )
                    -- Where it is, and what the game put on its buttons' icons.
                    local cx, cy = spot.win:GetCenter()
                    local icons = {}
                    for _, bb in ipairs(spot.buttons) do
                        local p = spot.parts[bb]
                        local tex = p and Safe(p.icon, "GetTexture") or "-"
                        local on = Safe(bb, "IsVisible")
                        if tex ~= "nil" or on == "true" then icons[#icons + 1] = on .. ":" .. tex end
                        if #icons >= 4 then break end
                    end
                    ns.Print(
                        string.format(
                            "      at %s,%s alpha %s, container shown %s %sx%s; icons set: %s",
                            cx and string.format("%.0f", cx) or "?",
                            cy and string.format("%.0f", cy) or "?",
                            Safe(spot.win, "GetEffectiveAlpha"),
                            c and Safe(c, "IsVisible") or "-",
                            c and Safe(c, "GetWidth") or "-",
                            c and Safe(c, "GetHeight") or "-",
                            #icons > 0 and table.concat(icons, ", ") or "none"
                        )
                    )
                    -- Which of its buttons has the mouse (for the tooltip), and why.
                    local mice = {}
                    for i, bb in ipairs(spot.buttons) do
                        mice[#mice + 1] = i .. ":" .. Safe(bb, "IsMouseMotionEnabled")
                    end
                    ns.Print(
                        string.format(
                            "      mouse-over on its buttons: %s%s",
                            #mice > 0 and table.concat(mice, " ") or "no buttons",
                            spot.mouseErr and ("; refused: " .. spot.mouseErr) or ""
                        )
                    )
                end
            end
            -- What the unit really has (readable only out of combat), and for the target, what
            -- its nameplate unit has (and without the nameplate filter word, to compare).
            if unit then
                ns.Print("    " .. unit .. " has: " .. AuraNames(unit, filt))
                if unit == "target" then
                    ns.Print(
                        "    target, plain "
                            .. FILTER[kind]:match("^%a+")
                            .. ": "
                            .. AuraNames(unit, FILTER[kind]:match("^%a+"))
                    )
                    local plate = TargetPlate()
                    ns.Print(
                        "    its nameplate " .. tostring(plate) .. " has: " .. (plate and AuraNames(plate, filt) or "-")
                    )
                end
            end
        end
    end
end, "what the buff and debuff arcs are doing (for bug reports)")

-- /circ auratest: plain aura containers in the middle of the screen, set up the way other
-- addons' (the nameplates', DBM's) are: the game's whole row, no clipping window, the icon made
-- in the game's own setup call. Your debuffs on the left, your target's buffs on the right.
-- If an aura shows here but not on the ring, Circlet's one-icon windows are what lose it.
local tests
local TESTS = {
    { unit = "player", filter = "HARMFUL|INCLUDE_NAME_PLATE_ONLY", label = "Your debuffs", x = 0 },
    { unit = "target", filter = "HELPFUL|INCLUDE_NAME_PLATE_ONLY", label = "Target's buffs", x = 0, y = 70 },
    -- The same, through the target's nameplate unit (followed as the target changes).
    {
        plate = true,
        filter = "HELPFUL|INCLUDE_NAME_PLATE_ONLY",
        label = "Target's buffs (its nameplate)",
        x = 0,
        y = 140,
    },
}
ns.RegisterCommand({ "auratest" }, function()
    if tests then
        local on = not tests[1]:IsShown()
        for _, c in ipairs(tests) do
            c:SetShown(on)
            pcall(c.SetEnabled, c, on)
        end
        ns.Print("Aura test " .. (on and "shown." or "hidden."))
        return
    end
    if InCombat() then
        ns.Print("Aura test: the game only lets addons make these out of combat. Try again after it.")
        return
    end
    tests = {}
    for _, t in ipairs(TESTS) do
        local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        if not (ok and c and c.AddAuraGroup) then
            ns.Print("Aura test: this client can't make aura containers.")
            tests = nil
            return
        end
        c:SetSize(300, 36)
        c:SetPoint("CENTER", UIParent, "CENTER", t.x, 120 - (t.y or 0))
        local label = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("BOTTOM", c, "TOP", 0, 4)
        label:SetText(t.label)
        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(c)
        bg:SetColorTexture(0, 0, 0, 0.6)
        local added, err = pcall(c.AddAuraGroup, c, "test", t.filter, {
            maxFrameCount = 8,
            candidateFilters = {},
            layout = { elementWidth = 32, elementHeight = 32, elementSpacing = 4 },
            initializeFrame = function(b)
                -- A bright green frame of our own (shows whether the button's there at all),
                -- then the icon set up as the nameplates do: sublevel -5, cropped, then handed over.
                local edge = b:CreateTexture(nil, "BACKGROUND")
                edge:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
                edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
                edge:SetColorTexture(0.2, 1, 0.2, 1)
                b.circletIcon = b:CreateTexture(nil, "ARTWORK", nil, -5)
                b.circletIcon:SetAllPoints(b)
                b.circletIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b:SetIcon(b.circletIcon)
                local cdOk, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
                if cdOk and cd then
                    cd:SetAllPoints(b)
                    pcall(b.SetDurationCooldown, b, cd)
                end
                local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
                count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
                pcall(b.SetApplicationCount, b, count)
            end,
        })
        pcall(c.SetEnabled, c, false) -- (the nameplates' order: off, set the unit, then on)
        if t.plate then
            -- Follows the target's nameplate unit, checked five times a second (from a frame of
            -- our own: the game won't let addons put scripts on its containers).
            local at, driver, cur = 0, CreateFrame("Frame"), false
            driver:SetScript("OnUpdate", function(_, elapsed)
                at = at + elapsed
                if at < 0.2 then return end
                at = 0
                local plate = TargetPlate()
                if plate ~= cur then
                    cur = plate
                    pcall(c.SetUnit, c, plate)
                    label:SetText(t.label .. ": " .. tostring(plate))
                end
            end)
        else
            pcall(c.SetUnit, c, t.unit)
        end
        pcall(c.SetEnabled, c, true)
        c:Show()
        tests[#tests + 1] = c
        ns.Print(
            string.format(
                "Aura test: %s (%s, %s): %s",
                t.label,
                t.unit or "nameplate",
                t.filter,
                added and "set up" or tostring(err)
            )
        )
    end
    ns.Print("Aura test: /circ auratest again hides or shows them.")
end, "plain aura containers in the middle of the screen, to compare with the rings' (for bug reports)")
