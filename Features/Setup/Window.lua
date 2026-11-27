-- Circlet: Setup wizard and New in page: the window, and drawing a page in it.
local _, ns = ...

local SU = ns.SetupUI
local STEPS = SU.STEPS
local Current = SU.Current

---------------------------------------------------------------- window
local W, H = 700, 500
local frame = CreateFrame("Frame", "CircletSetupFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
frame:SetSize(W, H)
frame:SetFrameStrata("DIALOG")
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -40)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetClampedToScreen(true)
frame:Hide()
table.insert(UISpecialFrames, "CircletSetupFrame") -- Esc closes it

-- Circlet's window look (UI/PanelSkin.lua): header band with the turning logo,
-- gold border and accent line, a rule over the footer.
local HEADER, FOOTER = 58, 44
local GOLD = ns.SKIN_GOLD
local skin = ns.SkinPanel(frame, { header = HEADER, footer = FOOTER })
-- In the options window's colors and controls (UI/Widgets.lua).
local Wd = ns.W
Wd.ThemePanel(frame, skin, HEADER, FOOTER)

frame.title = Wd.Text(frame, 20, 1, 1, 1, "OVERLAY", Wd.TITLE_FONT)
frame.title:SetPoint("TOPLEFT", skin.logo, "TOPRIGHT", 12, -1)
frame.subtitle = Wd.Text(frame, 12, Wd.MUTED[1], Wd.MUTED[2], Wd.MUTED[3])
frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 1, -4)
frame.close = Wd.CloseButton(frame, function() frame:Hide() end)
frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -14)

-- The step ring, in the header's right corner: one notch per step, filled up to this one.
local STEP_R = 15
frame.steps = CreateFrame("Frame", nil, frame)
frame.steps:SetSize(STEP_R * 2, STEP_R * 2)
frame.steps:SetPoint("RIGHT", frame, "TOPRIGHT", -56, -HEADER / 2)
local stepGeom = { R = STEP_R - 2, T = 4, step = 2 * math.pi / ns.XP_SEGMENTS, style = "segmented", notches = STEPS, gapPx = 3 }
frame.steps.track = ns.NewRingLayer("BACKGROUND", 1, ns.TRACK, 1, frame.steps)
frame.steps.fill = ns.NewRingLayer("ARTWORK", 0, GOLD, 1, frame.steps)
frame.steps.text = frame.steps:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.steps.text:SetPoint("CENTER")
local function DrawSteps(n)
    ns.DrawArc(frame.steps.track, 0, 1, frame.steps, stepGeom, true)
    ns.DrawArc(frame.steps.fill, 0, n / STEPS, frame.steps, stepGeom)
    frame.steps.text:SetText(n .. "/" .. STEPS)
end

-- The page body scrolls (with the mouse wheel) when it's taller than the window: the New in
-- page can list a whole release. A slim bar on the right shows where you are.
local scroll = CreateFrame("ScrollFrame", nil, frame)
scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -(HEADER + 12))
scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, FOOTER + 6)
local body = CreateFrame("Frame", nil, scroll)
body:SetSize(W - 40, 10)
scroll:SetScrollChild(body)
local bar = scroll:CreateTexture(nil, "OVERLAY")
bar:SetColorTexture(0.5, 0.42, 0.36, 0.7)
bar:SetWidth(5)
bar:Hide()

local function Num(v) return type(v) == "number" and v or 0 end
local function MaxScroll() return math.max(0, Num(body:GetHeight()) - Num(scroll:GetHeight())) end
local function SetScroll(v)
    local max = MaxScroll()
    v = math.max(0, math.min(max, Num(v)))
    scroll:SetVerticalScroll(v)
    local view = Num(scroll:GetHeight())
    if max > 0 and view > 0 then
        local total = view + max
        local h = math.max(20, view * view / total)
        bar:SetHeight(h)
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 14, -(view - h) * v / max)
        bar:Show()
    else
        bar:Hide()
    end
end
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(_, delta) SetScroll(Num(scroll:GetVerticalScroll()) - delta * 40) end)
local scrolledFor -- the page the scroll position belongs to (a new page starts at the top)

local COL_X, COL_W, ROW_H = { 0, 340 }, 320, 23
local FULL_W = COL_X[2] + COL_W
local pool = { check = {}, header = {}, note = {}, card = {}, button = {}, footer = {} }
local used = {}

-- Pictures on the Look cards: mini rings { style, radius } drawn in that style / at that size.
local ART = {
    ["style:keep"] = { { "smooth", 11 }, { "segmented", 11 }, { "thin", 11 } },
    ["style:smooth"] = { { "smooth", 22 } }, ["style:segmented"] = { { "segmented", 22 } },
    ["style:thin"] = { { "thin", 22 } },
    ["size:keep"] = { { "smooth", 8 }, { "smooth", 11 }, { "smooth", 14 } },
    ["size:smaller"] = { { "smooth", 16 } }, ["size:default"] = { { "smooth", 20 } },
    ["size:larger"] = { { "smooth", 25 } },
}
local CARD_W, CARD_H, CARD_GAP = 155, 92, 10  -- picture cards (two to a column)
local TEXT_CARD_W, TEXT_CARD_H = 213, 48      -- placement cards (three across)

local function Tooltip(owner, title, text, hl)
    owner:SetScript("OnEnter", function(self)
        if hl then hl:Show() end
        if not (GameTooltip and text) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function()
        if hl then hl:Hide() end
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function SetEdges(e, r, g, b, a) for _, t in pairs(e) do t:SetColorTexture(r, g, b, a) end end

-- A mini ring on a card: style "smooth" / "segmented" / "thin", radius r, 70% filled in gold.
local function MiniRing(card, i)
    local m = card.minis[i]
    if m then return m end
    m = CreateFrame("Frame", nil, card)
    m.track = ns.NewRingLayer("BORDER", 0, ns.TRACK, 1, m)
    m.fill = ns.NewRingLayer("ARTWORK", 0, GOLD, 1, m)
    m.geom = { step = 2 * math.pi / ns.XP_SEGMENTS, notches = 12, gapPx = 2 }
    card.minis[i] = m
    return m
end

local function DrawMini(m, style, r, lit)
    m:SetSize(r * 2, r * 2)
    local g = m.geom
    g.T = style == "thin" and 2.5 or math.max(3, r * 0.3)
    g.R, g.style = r - g.T / 2, style
    for _, l in ipairs(m.fill) do l:SetColorTexture(lit and GOLD.r or 0.75, lit and GOLD.g or 0.75, lit and GOLD.b or 0.8, 1) end
    ns.DrawArc(m.track, 0, 1, m, g, true)
    ns.DrawArc(m.fill, 0, 0.7, m, g)
end

local makers = {
    -- Section title: small warm capitals over a faint line, like the options window's.
    header = function()
        local f = CreateFrame("Frame", nil, body)
        f:SetSize(COL_W, 20)
        f.text = Wd.Text(f, 11, Wd.HEADING[1], Wd.HEADING[2], Wd.HEADING[3])
        f.text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 5)
        f.line = f:CreateTexture(nil, "ARTWORK")
        f.line:SetPoint("BOTTOMLEFT"); f.line:SetPoint("BOTTOMRIGHT")
        f.line:SetHeight(1)
        ns.SkinGradient(f.line, "HORIZONTAL", 1, 1, 1, 0.12, 1, 1, 1, 0)
        f.SetLabel = function(self, t) self.text:SetText(tostring(t or ""):upper()) end
        return f
    end,
    -- A clickable card: a picture (mini rings) or just a label; gold border and tick when picked.
    card = function()
        local c = CreateFrame("Button", nil, body)
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints()
        c.glow = c:CreateTexture(nil, "BACKGROUND", nil, 1)
        c.glow:SetAllPoints()
        ns.SkinGradient(c.glow, "VERTICAL", GOLD.r, GOLD.g, GOLD.b, 0.02, GOLD.r, GOLD.g, GOLD.b, 0.16)
        c.edges = ns.SkinEdges(c, "BORDER", 0, 1, 0, 1, 1, 1, 0.10)
        c.label = Wd.Text(c, 12, 0.88, 0.88, 0.88)
        c.label:SetJustifyH("CENTER")
        c.tick = c:CreateTexture(nil, "OVERLAY")
        c.tick:SetTexture(Wd.DOT)
        c.tick:SetVertexColor(GOLD.r, GOLD.g, GOLD.b, 1)
        c.tick:SetSize(9, 9)
        c.tick:SetPoint("TOPRIGHT", c, "TOPRIGHT", -7, -7)
        c.minis = {}
        c:SetScript("OnEnter", function(self) if not self.picked then SetEdges(self.edges, 1, 1, 1, 0.3) end end)
        c:SetScript("OnLeave", function(self) if not self.picked then SetEdges(self.edges, 1, 1, 1, 0.10) end end)
        return c
    end,
    button = function()
        local b = Wd.Button(body, 150, 26, "")
        return b
    end,
    note = function()
        local f = Wd.Text(body, 12, Wd.BODY_TEXT[1], Wd.BODY_TEXT[2], Wd.BODY_TEXT[3])
        f:SetWordWrap(true)
        return f
    end,
    check = function()
        local w = CreateFrame("Frame", nil, body)
        -- Hover highlight; on the New in page also a panel, border and a NEW tag.
        w.hl = w:CreateTexture(nil, "BACKGROUND", nil, 2)
        w.hl:SetAllPoints()
        w.hl:SetColorTexture(1, 1, 1, 0.04)
        w.hl:Hide()
        w.panel = w:CreateTexture(nil, "BACKGROUND", nil, 1)
        w.panel:SetAllPoints()
        w.panel:SetColorTexture(1, 1, 1, 0.035)
        w.edges = ns.SkinEdges(w, "BORDER", 0, 1, 0, 1, 1, 1, 0.07)
        w.tag = Wd.Text(w, 10, GOLD.r, GOLD.g, GOLD.b)
        -- An on/off switch, as in the options window; clicking it clicks w.clickId.
        w.check = Wd.Switch(w, function() if w.onToggle then w.onToggle() end end)
        w.check.SetChecked = w.check.SetOn
        w.check.GetChecked = function(self) return self.on end
        w.text = Wd.Text(w, 13, 0.93, 0.93, 0.93)
        w.text:SetPoint("TOPLEFT", w.check, "TOPRIGHT", 10, -3)
        w.desc = Wd.Text(w, 11, 0.62, 0.6, 0.6)
        w.desc:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -3)
        w.show = Wd.Button(w, 58, 22, "")
        w.show:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)
        return w
    end,
    footer = function()
        local b = Wd.Button(frame, 110, 28, "")
        b.Disable = function(self) self:SetEnabled(false) end
        b.Enable = function(self) self:SetEnabled(true) end
        return b
    end,
}

local function Acquire(kind)
    used[kind] = (used[kind] or 0) + 1
    local w = pool[kind][used[kind]]
    if not w then w = makers[kind]() pool[kind][used[kind]] = w end
    w:Show()
    return w
end


-- Draws the current page.
SU.Render = function()
    if not frame:IsShown() then return end
    for kind, list in pairs(pool) do
        for _, w in ipairs(list) do w:Hide() end
        used[kind] = 0
    end
    local title, subtitle, items, buttons = Current()
    frame.title:SetText(title)
    frame.subtitle:SetText(subtitle)
    if SU.mode == "wizard" then frame.steps:Show(); DrawSteps(SU.step) else frame.steps:Hide() end
    local y = { 0, 0 }
    -- Cards flow left to right in rows; cardX / rowH track the row being filled per column.
    local cardX, rowH = { 0, 0 }, { 0, 0 }
    local function EndCardRow(c)
        if cardX[c] > 0 then y[c] = y[c] + rowH[c] + CARD_GAP; cardX[c], rowH[c] = 0, 0 end
    end
    for _, item in ipairs(items) do
        local c = item.col or 1
        local x, width = COL_X[c], (item.wide or item.kind == "note") and FULL_W or COL_W
        local isCard = item.kind == "choice"
        if not isCard then EndCardRow(c) end
        if item.kind == "header" then
            local f = Acquire("header")
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", body, "TOPLEFT", x, -(y[c] + 4))
            f:SetWidth(COL_W)
            f:SetLabel(item.text)
            y[c] = y[c] + 30
        elseif item.kind == "button" then
            local b = Acquire("button")
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", body, "TOPLEFT", x + 2, -(y[c] + 2))
            b:SetText(item.text)
            b.onClick = function() SU.Click(item.id) end
            y[c] = y[c] + 32
        elseif item.kind == "note" then
            local f = Acquire("note")
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y[c])
            f:SetWidth(width)
            f:SetText(item.text)
            -- A note spans both columns: both continue below it.
            local sh = f.GetStringHeight and f:GetStringHeight()
            local h = math.max(14, type(sh) == "number" and sh or 14) + 8
            y[1], y[2] = math.max(y[1], y[c] + h), math.max(y[2], y[c] + h)
        elseif item.kind == "check" then
            local w = Acquire("check")
            local panel = item.wide -- the New in page: each item on its own little panel
            local h = panel and 46 or ROW_H
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y[c])
            w:SetSize(width, h)
            w.panel:SetShown(panel)
            for _, e in pairs(w.edges) do e:SetShown(panel) end
            w.check:ClearAllPoints()
            w.check:SetPoint("TOPLEFT", w, "TOPLEFT", panel and 10 or 2, panel and -8 or -1)
            w.check:SetChecked(item.on)
            w.onToggle = function() SU.Click(item.id) end
            w.check:SetShown(not item.info)
            w.text:SetText(item.text)
            w.text:SetTextColor(item.on and 1 or 0.6, item.on and 1 or 0.6, item.on and 1 or 0.62)
            w.desc:SetText(panel and item.desc or "")
            w.desc:SetWidth(width - 140)
            if panel then -- tall enough for a description that wraps
                local dh = w.desc.GetStringHeight and w.desc:GetStringHeight()
                if type(dh) == "number" and dh > 0 then h = math.max(h, 30 + dh) w:SetHeight(h) end
            end
            w.tag:ClearAllPoints()
            w.tag:SetPoint("RIGHT", w.show, "LEFT", -10, 0)
            w.tag:SetText(panel and item.since and ("NEW  " .. item.since) or "")
            if not item.info then Tooltip(w.check, item.text, item.desc, w.hl) end
            w.show:ClearAllPoints()
            w.show:SetPoint("RIGHT", w, "RIGHT", panel and -8 or 0, panel and 0 or 0)
            if item.showId then
                w.show:SetText(item.showOn and "Hide" or "Show")
                w.show.onClick = function() SU.Click(item.showId) end
                Tooltip(w.show, item.text, item.showOn and "Take it off the screen again."
                    or "Put it on screen with sample content. You can drag it into place.", w.hl)
                w.show:Show()
            else
                w.show:Hide()
            end
            y[c] = y[c] + h + (panel and 6 or 0)
        elseif isCard then
            -- Picture cards (Look) two to a column; text cards (Placement) three across.
            local art = ART[item.id]
            local cw, ch = art and CARD_W or TEXT_CARD_W, art and CARD_H or TEXT_CARD_H
            local room = art and COL_W or FULL_W
            if cardX[c] > 0 and cardX[c] + cw > room then EndCardRow(c) end
            local card = Acquire("card")
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", body, "TOPLEFT", x + cardX[c], -y[c])
            card:SetSize(cw, ch)
            card.picked = item.selected
            card.bg:SetColorTexture(item.selected and 0.15 or 0.10, item.selected and 0.11 or 0.08,
                item.selected and 0.08 or 0.085, 0.95)
            card.glow:SetShown(item.selected)
            card.tick:SetShown(item.selected)
            SetEdges(card.edges, item.selected and GOLD.r or 1, item.selected and GOLD.g or 1,
                item.selected and GOLD.b or 1, item.selected and 0.95 or 0.10)
            card.label:ClearAllPoints()
            if art then card.label:SetPoint("BOTTOM", card, "BOTTOM", 0, 8) else card.label:SetPoint("CENTER") end
            card.label:SetWidth(cw - 12)
            card.label:SetText(item.text)
            card.label:SetTextColor(item.selected and 1 or 0.85, item.selected and 0.86 or 0.85, item.selected and 0.45 or 0.88)
            -- The mini rings, side by side above the label.
            local n = art and #art or 0
            local total = 0
            for i = 1, n do total = total + art[i][2] * 2 end
            total = total + math.max(0, n - 1) * 8
            local mx = -total / 2
            for i = 1, n do
                local m = MiniRing(card, i)
                local r = art[i][2]
                m:ClearAllPoints()
                m:SetPoint("CENTER", card, "TOP", mx + r, -36)
                DrawMini(m, art[i][1], r, item.selected)
                m:Show()
                mx = mx + r * 2 + 8
            end
            for i = n + 1, #card.minis do card.minis[i]:Hide() end
            card:SetScript("OnClick", function() SU.Click(item.id) end)
            cardX[c] = cardX[c] + cw + CARD_GAP
            rowH[c] = math.max(rowH[c], ch)
        end
    end
    EndCardRow(1); EndCardRow(2)
    body:SetHeight(math.max(10, y[1], y[2]))
    local page = SU.mode .. ":" .. tostring(SU.step)
    if scrolledFor ~= page then scrolledFor = page; SetScroll(0) else SetScroll(scroll:GetVerticalScroll()) end
    local right = -12
    for i = #buttons, 1, -1 do
        local spec = buttons[i]
        local b = Acquire("footer")
        b:ClearAllPoints()
        if spec.side == "left" then
            b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 8)
        else
            b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right - 2, 8)
            right = right - 120
        end
        b:SetText(spec.text)
        if spec.enabled == false then b:Disable() else b:Enable() end
        -- The way forward (Next / Finish / Done) in gold, like the options window's Close.
        if spec.id == "next" or spec.id == "done" then
            b:SetAccent()
        else
            b.borderColor = { 0.33, 0.26, 0.24 }
            Wd.SetBorderColor(b.border, 0.33, 0.26, 0.24, 1)
            b.label:SetTextColor(0.92, 0.92, 0.92)
        end
        b.onClick = function() SU.Click(spec.id) end
    end
end

-- For the files loaded after this one.
SU.frame = frame
