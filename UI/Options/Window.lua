-- Circlet: The options window's page: tabs, sections of cells, the footer's buttons, and moving between pages.
local _, ns = ...

local db = ns.db
local UI = ns.OptionsUI
local W = UI.W
local A = UI.A
local SIDE_W = UI.SIDE_W
local FOOT_H = UI.FOOT_H
local PAD = UI.PAD
local BODY_W = UI.BODY_W
local COL_W = UI.COL_W
local ROW_H = UI.ROW_H
local tabOf = UI.tabOf
local Eval = UI.Eval
local Num = UI.Num
local PageAt = UI.PageAt
local PageModel = UI.PageModel
local Tabs = UI.Tabs
local Signature = UI.Signature
local Commit = UI.Commit
local Acquire = UI.Acquire
local ReleaseAll = UI.ReleaseAll
local EachCell = UI.EachCell
local CELL_KIND = UI.CELL_KIND
local Head = UI.Head
local ReleaseHeads = UI.ReleaseHeads
local RefreshSidebar = UI.RefreshSidebar

---------------------------------------------------------------- the page
local tabButtons, footButtons = {}, {}

local function TabButton(i)
    local b = tabButtons[i]
    if not b then
        b = CreateFrame("Button", nil, UI.win)
        b:SetHeight(34)
        b.text = W.Text(b, 14, 1, 1, 1, "OVERLAY", W.TITLE_FONT)
        b.text:SetPoint("CENTER", b, "CENTER", 0, 2)
        b.line = W.Solid(b, "ARTWORK", A.r, A.g, A.b, 1)
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT"); b.line:SetPoint("BOTTOMRIGHT")
        b:SetScript("OnClick", function(self)
            tabOf[UI.current] = self.tab
            UI.lastSig = nil
            UI.win.body:ScrollTo(0)
            UI.Refresh()
        end)
        b:SetScript("OnEnter", function(self) if not self.selected then self.text:SetTextColor(0.9, 0.9, 0.92) end end)
        b:SetScript("OnLeave", function(self) if not self.selected then self.text:SetTextColor(0.6, 0.62, 0.66) end end)
        tabButtons[i] = b
    end
    b:Show()
    return b
end

local function FootButton(i)
    local b = footButtons[i]
    if not b then
        b = W.Button(UI.win, 140, 32, "", function(self) Commit(self.opt, self.info) end)
        b.tipTitle = function() return b.opt and tostring(Eval(b.opt.name, b.info) or "") end
        b.tipText = function() return b.opt and Eval(b.opt.desc, b.info) end
        footButtons[i] = b
    end
    b:Show()
    return b
end

local function UpdateHeader(m)
    UI.win.title:SetText(m.title or "")
    UI.win.intro:SetText(m.intro or "")
end

local function UpdateFooter(m)
    local x = SIDE_W + PAD
    for i, e in ipairs(m.buttons) do
        local b = FootButton(i)
        b.opt, b.info = e.opt, e.info
        b:SetText(tostring(Eval(e.opt.name, e.info) or ""))
        b:SetWidth(math.max(120, Num(b.label:GetStringWidth(), 80) + 40))
        b:SetEnabled(not m.disabled and not Eval(e.opt.disabled, e.info))
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", UI.win, "BOTTOMLEFT", x, 13)
        x = x + Num(b:GetWidth(), 120) + 12
    end
    for i = #m.buttons + 1, #footButtons do footButtons[i]:Hide() end
end

local function Render(m, tabs, tab)
    UpdateHeader(m)
    -- Where the tabs go depends on how long the description is.
    local titleH = Num(UI.win.title:GetStringHeight(), 30)
    local introH = (m.intro and m.intro ~= "") and Num(UI.win.intro:GetStringHeight(), 16) or 0
    local tabsTop = 24 + titleH + 10 + introH + 16
    local x = SIDE_W + PAD
    for i, name in ipairs(tabs) do
        local b = TabButton(i)
        b.tab = name
        b.selected = name == tab
        b.text:SetText(#tabs == 1 and (m.name or name) or name)
        b.text:SetTextColor(b.selected and 1 or 0.6, b.selected and 1 or 0.62, b.selected and 1 or 0.66)
        b.line:SetShown(b.selected)
        b:SetWidth(Num(b.text:GetStringWidth(), 80) + 28)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", UI.win, "TOPLEFT", x, -tabsTop)
        x = x + Num(b:GetWidth(), 100) + 6
    end
    for i = #tabs + 1, #tabButtons do tabButtons[i]:Hide() end
    UI.win.tabRule:ClearAllPoints()
    UI.win.tabRule:SetPoint("TOPLEFT", UI.win, "TOPLEFT", SIDE_W + PAD, -(tabsTop + 34))
    UI.win.tabRule:SetPoint("TOPRIGHT", UI.win, "TOPRIGHT", -PAD, -(tabsTop + 34))
    local body = UI.win.body
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", UI.win, "TOPLEFT", SIDE_W + PAD, -(tabsTop + 35))
    body:SetPoint("BOTTOMRIGHT", UI.win, "BOTTOMRIGHT", -PAD + 12, FOOT_H + 1)

    -- The sections, each a title over its cells in two columns.
    ReleaseAll()
    ReleaseHeads()
    local child = body.child
    child:SetWidth(BODY_W)
    local y = -18
    for _, s in ipairs(m.sections) do
        if s.tab == tab then
            if s.title and s.title ~= "" then
                local h = Head(child)
                h:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
                h:SetText(tostring(s.title):upper())
                y = y - 22
            end
            local col, row = 0, 0
            local function NextRow()
                if col > 0 then y = y - ROW_H; row = row + 1; col = 0 end
            end
            for _, e in ipairs(s.items) do
                local kind = CELL_KIND[e.opt.type]
                if not kind then
                    -- an option type the window doesn't draw
                elseif kind == "text" or kind == "subhead" then
                    NextRow()
                    local text = tostring(Eval(e.opt.name, e.info) or "")
                    if text:find("%S") then
                        local c = Acquire(kind, child)
                        c.opt, c.info, c.group, c.pageOff = e.opt, e.info, s.group, m.disabled
                        c:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
                        c:SetWidth(BODY_W)
                        c:SetHeight(kind == "subhead" and 30 or ROW_H)
                        c:Update()
                        y = y - Num(c:GetHeight(), ROW_H)
                        row = row + 1
                    end
                else
                    local c = Acquire(kind, child)
                    c.opt, c.info, c.group, c.pageOff = e.opt, e.info, s.group, m.disabled
                    c:SetPoint("TOPLEFT", child, "TOPLEFT", col * COL_W, y)
                    c:SetSize(COL_W, ROW_H)
                    c.bg:SetColorTexture(1, 1, 1, row % 2 == 0 and 0.035 or 0.018)
                    c.divider:SetShown(col == 0)
                    c:Update()
                    col = col + 1
                    if col == 2 then NextRow() end
                end
            end
            NextRow()
            y = y - 24
        end
    end
    child:SetHeight(-y)
    body:Update()
    UpdateFooter(m)
end

UI.Refresh = function()
    if not UI.win or not UI.win:IsShown() then return end
    local m = PageModel(UI.current)
    local tabs, tab = Tabs(m)
    local sig = Signature(m, tab)
    if sig ~= UI.lastSig then
        UI.lastSig = sig
        local scroll = tonumber(UI.win.body:GetVerticalScroll())
        Render(m, tabs, tab)
        UI.win.body:ScrollTo(scroll or 0)
    else
        UpdateHeader(m)
        EachCell(function(c) if c.opt then c:Update() end end)
        UpdateFooter(m)
    end
    RefreshSidebar()
end

-- Edit mode follows the page: opening a ring's page puts that ring in edit mode, and
-- leaving the page (or closing the window) ends it. Only rings it started itself.
local autoKey
local function FollowPage(path)
    local key = path and path:match("%.([^.]+)$")
    local def = key and ns.FindRing(key)
    if def and def.key ~= key then def = nil end
    if autoKey and autoKey ~= (def and key) then
        ns.SetRingEditing(autoKey, false, true)
        autoKey = nil
    end
    if def and db.optionsAutoEdit and not def.edit.get() and not ns.HiddenForClass(def) then
        ns.SetRingEditing(key, true, true)
        autoKey = key
    end
end

UI.SelectPage = function(path)
    if not PageAt(path) then path = "general" end
    UI.current = path
    UI.lastSig = nil
    W.CloseList()
    if UI.win.body then UI.win.body:SetVerticalScroll(0) end
    UI.Refresh()
    FollowPage(path)
end

-- For the files loaded after this one.
UI.FollowPage = FollowPage
