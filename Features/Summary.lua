-- Circlet: Session summary: everything gained this session, as a panel of rings.
local ADDON_NAME, ns = ...

local db, Print, IsSecret, NewRingLayer, DrawArc = ns.db, ns.Print, ns.IsSecret, ns.NewRingLayer, ns.DrawArc
local XP_SEGMENTS, TRACK, FormatTime = ns.XP_SEGMENTS, ns.TRACK, ns.FormatTime

---------------------------------------------------------------------------
-- Session tracking
---------------------------------------------------------------------------
-- The rings report what they see through ns.SessionAdd; quests handed in, deaths
-- and money are counted here. A session starts when you log in (a /reload carries
-- on the same one) and is kept per character in CircletDB.sessions.

local session

local function CharKey()
    local name, realm = UnitName("player"), GetRealmName and GetRealmName() or ""
    if IsSecret(name) then name = "?" end
    return (name or "?") .. "-" .. (realm or "")
end

local function Money()
    local m = GetMoney and GetMoney()
    return (type(m) == "number" and not IsSecret(m)) and m or 0
end

local function NewSession()
    return { start = time(), money = Money(), xp = 0, levels = 0, quests = 0, objectives = 0,
             skills = {}, rep = {}, flights = 0, flightTime = 0, pet = 0, deaths = 0, crafts = 0, gathers = 0 }
end

-- kind: "xp", "levels", "objectives", "flights", "flightTime", "pet" (amounts), or
-- "skills" / "rep" (per name).
local function SessionAdd(kind, name, amount)
    if not session or not amount or amount == 0 then return end
    if name then
        session[kind] = session[kind] or {}
        session[kind][name] = (session[kind][name] or 0) + amount
    else
        session[kind] = (session[kind] or 0) + amount
    end
end
ns.SessionAdd = SessionAdd

local function StartOrResume(isInitialLogin)
    db.sessions = db.sessions or {}
    local key = CharKey()
    if isInitialLogin or not db.sessions[key] then
        db.sessions[key] = NewSession()
    end
    session = db.sessions[key]
end

---------------------------------------------------------------------------
-- Summary window
---------------------------------------------------------------------------
local TILE_W, TILE_H, RING = 132, 150, 92
local COLUMNS = 4

local panel = CreateFrame("Frame", "CircletSummaryFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
panel:SetFrameStrata("DIALOG")
panel:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetClampedToScreen(true)
panel:Hide()
if panel.SetBackdrop then
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0.04, 0.04, 0.06, 0.94)
    panel:SetBackdropBorderColor(0.6, 0.6, 0.65, 1)
else
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.94)
end
table.insert(UISpecialFrames, "CircletSummaryFrame") -- Esc closes it

panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panel.title:SetPoint("TOP", panel, "TOP", 0, -14)
panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.subtitle:SetPoint("TOP", panel.title, "BOTTOM", 0, -4)
panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
panel.close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
panel.reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
panel.reset:SetSize(120, 22)
panel.reset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 10)
panel.reset:SetText("Start new session")
panel.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
panel.footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 16)
panel.footer:SetText("/circ summary  ·  also shown when you log out")

local tiles = {}

local function Tile(i)
    local t = tiles[i]
    if t then return t end
    t = CreateFrame("Frame", nil, panel)
    t:SetSize(TILE_W, TILE_H)
    t.geom = { R = 0, T = 9, step = 2 * math.pi / XP_SEGMENTS }
    t.geom.R = RING / 2 - t.geom.T / 2
    t.ringFrame = CreateFrame("Frame", nil, t)
    t.ringFrame:SetSize(RING, RING)
    t.ringFrame:SetPoint("TOP", t, "TOP", 0, -4)
    t.bg = NewRingLayer("BACKGROUND", 0, TRACK, 1, t.ringFrame)
    t.fill = NewRingLayer("ARTWORK", 0, { r = 1, g = 1, b = 1 }, 1, t.ringFrame)
    t.value = t.ringFrame:CreateFontString(nil, "OVERLAY")
    t.value:SetFont(STANDARD_TEXT_FONT, 17, "OUTLINE")
    t.value:SetPoint("CENTER", t.ringFrame, "CENTER", 0, 0)
    t.label = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.label:SetPoint("TOP", t.ringFrame, "BOTTOM", 0, -6)
    t.sub = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.sub:SetPoint("TOP", t.label, "BOTTOM", 0, -2)
    t.sub:SetWidth(TILE_W - 6)
    t.sub:SetWordWrap(false)
    tiles[i] = t
    return t
end

local function Short(n)
    n = math.floor(n + 0.5)
    if math.abs(n) >= 100000 then return string.format("%.0fk", n / 1000) end
    if math.abs(n) >= 10000 then return string.format("%.1fk", n / 1000) end
    return BreakUpLargeNumbers(n)
end

local function Coins(c)
    local sign = c < 0 and "-" or "+"
    c = math.abs(c)
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. "|cffffd100g|r") end
    if s > 0 or g > 0 then table.insert(parts, s .. "|cffc7c7cfs|r") end
    if g == 0 then table.insert(parts, cp .. "|cffeda55fc|r") end
    return sign .. table.concat(parts, " ")
end

local function Total(t)
    local sum, top, topName = 0, nil, nil
    for name, v in pairs(t or {}) do
        sum = sum + v
        if not top or math.abs(v) > math.abs(top) then top, topName = v, name end
    end
    return sum, topName, top
end

local function Duration(seconds)
    seconds = math.max(0, seconds)
    local h, m = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end

-- The tiles to show: { value, label, sub, color, frac }.
local function BuildTiles()
    local s = session or NewSession()
    local list = {}
    local purple = { r = 0.58, g = 0.42, b = 0.95 }

    local cur, max = UnitXP("player"), UnitXPMax("player")
    local levelFrac = (not IsSecret(cur) and not IsSecret(max) and max and max > 0) and cur / max or 1
    local xpSub
    if s.levels > 0 then
        xpSub = "+" .. s.levels .. (s.levels == 1 and " level" or " levels")
    elseif max and max > 0 and not IsSecret(max) then
        xpSub = string.format("%.0f%% of a level", s.xp / max * 100)
    end
    table.insert(list, { value = "+" .. Short(s.xp), label = "Experience", sub = xpSub, color = purple, frac = levelFrac })

    table.insert(list, { value = tostring(s.quests), label = "Quests done",
                         sub = s.objectives > 0 and (s.objectives .. " objectives") or nil,
                         color = db.questColors.complete, frac = 1 })

    local money = Money() - (s.money or 0)
    table.insert(list, { value = Coins(money), label = "Money", sub = nil,
                         color = money >= 0 and { r = 1, g = 0.82, b = 0 } or { r = 0.9, g = 0.25, b = 0.2 },
                         frac = 1, small = true })

    local skillSum, topSkill, topSkillN = Total(s.skills)
    if skillSum > 0 then
        table.insert(list, { value = "+" .. skillSum, label = "Skill-ups",
                             sub = topSkill and (topSkill .. " +" .. topSkillN) or nil,
                             color = db.skillColors.profession, frac = 1 })
    end
    local repSum, topRep, topRepN = Total(s.rep)
    if topRep then
        table.insert(list, { value = (repSum >= 0 and "+" or "") .. Short(repSum), label = "Reputation",
                             sub = topRep .. (topRepN >= 0 and " +" or " ") .. Short(topRepN),
                             color = { r = 0.2, g = 0.75, b = 0.35 }, frac = 1 })
    end
    if s.flights > 0 then
        table.insert(list, { value = tostring(s.flights), label = s.flights == 1 and "Flight" or "Flights",
                             sub = FormatTime(s.flightTime) .. " in the air",
                             color = db.flightColors and db.flightColors.fill or purple, frac = 1 })
    end
    if (s.crafts or 0) > 0 then
        table.insert(list, { value = tostring(s.crafts), label = "Crafted", color = db.craftColors.fill, frac = 1 })
    end
    if (s.gathers or 0) > 0 then
        table.insert(list, { value = tostring(s.gathers), label = "Gathered", color = db.gatherColors.fill, frac = 1 })
    end
    if s.pet > 0 then
        table.insert(list, { value = "+" .. Short(s.pet), label = "Pet XP", color = db.petColors.xp, frac = 1 })
    end
    if s.deaths > 0 then
        table.insert(list, { value = tostring(s.deaths), label = s.deaths == 1 and "Death" or "Deaths",
                             color = { r = 0.55, g = 0.55, b = 0.6 }, frac = 1 })
    end
    return list, s
end

local function ShowSummary()
    local list, s = BuildTiles()
    local rows = math.ceil(#list / COLUMNS)
    local cols = math.min(COLUMNS, #list)
    panel:SetSize(math.max(380, cols * TILE_W + 32), 64 + rows * TILE_H + 44)
    panel.title:SetText("This session")
    panel.subtitle:SetText(Duration(time() - (s.start or time())) .. " played")
    for i, info in ipairs(list) do
        local t = Tile(i)
        local row, col = math.floor((i - 1) / COLUMNS), (i - 1) % COLUMNS
        local rowCount = (row == rows - 1) and (#list - row * COLUMNS) or COLUMNS
        local x = (col - (rowCount - 1) / 2) * TILE_W
        t:ClearAllPoints()
        t:SetPoint("TOP", panel, "TOP", x, -58 - row * TILE_H)
        ns.DrawTrack(t.ringFrame, t.bg, t.geom, 2)
        for _, l in ipairs(t.fill) do l:SetColorTexture(info.color.r, info.color.g, info.color.b, 1) end
        DrawArc(t.fill, 0, info.frac or 1, t.ringFrame, t.geom)
        t.value:SetFont(STANDARD_TEXT_FONT, info.small and 12 or 17, "OUTLINE")
        t.value:SetText(info.value)
        t.label:SetText(info.label)
        t.sub:SetText(info.sub or "")
        t:Show()
    end
    for i = #list + 1, #tiles do tiles[i]:Hide() end
    panel:Show()
end

local function ToggleSummary()
    if panel:IsShown() then panel:Hide() else ShowSummary() end
end

panel.reset:SetScript("OnClick", function()
    db.sessions[CharKey()] = NewSession()
    session = db.sessions[CharKey()]
    ShowSummary()
    Print("Started a new session.")
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen({ "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "QUEST_TURNED_IN", "PLAYER_CAMPING", "PLAYER_QUITING" }, function(event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        if not session then StartOrResume(arg1) end
    elseif not session then
        return
    elseif event == "QUEST_TURNED_IN" then
        session.quests = session.quests + 1
    elseif event == "PLAYER_DEAD" then
        session.deaths = session.deaths + 1
    elseif event == "PLAYER_CAMPING" or event == "PLAYER_QUITING" then
        if db.summaryOnLogout then ShowSummary() end
    end
end)

ns.RegisterCommand({ "summary", "session" }, ToggleSummary, "this session's summary")

-- Shared with the files loaded after this one.
ns.ToggleSummary = ToggleSummary
ns.ShowSummary = ShowSummary
