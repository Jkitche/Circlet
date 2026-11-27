-- Circlet: The options window's sidebar: the pages at the top, search, and every ring under its folder.
local _, ns = ...

local db = ns.db
local UI = ns.OptionsUI
local FOLDERS = UI.FOLDERS
local W = UI.W
local A = UI.A
local SIDE_W = UI.SIDE_W
local Eval = UI.Eval
local Sorted = UI.Sorted
local Info = UI.Info

---------------------------------------------------------------- the sidebar
local NAV = {
    { path = "general", text = "General", icon = "Interface\\Icons\\INV_Misc_Gear_01" },
    { path = "profiles", text = "Profiles", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { text = "Edit all rings", icon = "Interface\\Icons\\INV_Jewelry_Ring_03",
      tip = "Put every ring on screen at once to arrange them. Also /circ edit.",
      func = function() ns.ToggleAllEditing() end,
      active = function()
          for _, def in ipairs(ns.RINGS) do if def.edit.get() then return true end end
      end },
    { text = "What's new", icon = "Interface\\Icons\\INV_Scroll_03",
      tip = "The rings and features added in the latest version. Also /circ new.",
      func = function() UI.win:Hide(); ns.OpenWhatsNew() end },
    { text = "Setup wizard", icon = "Interface\\Icons\\Trade_Engineering",
      tip = "Pick your rings, hide the game bars they replace, and set their look, in four short steps. Also /circ setup.",
      func = function() UI.win:Hide(); ns.OpenSetup() end },
}

local function SideRow(parent, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(h)
    b.hi = W.Solid(b, "BACKGROUND", 1, 1, 1, 0.045)
    b.hi:SetAllPoints()
    b.hi:Hide()
    b.sel = W.Solid(b, "BACKGROUND", A.r, A.g, A.b, 0.16, 1)
    b.sel:SetAllPoints()
    b.bar = W.Solid(b, "ARTWORK", A.r, A.g, A.b, 1)
    b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(3)
    b.text = W.Text(b, 13, 0.85, 0.86, 0.88)
    b.text:SetWordWrap(false)
    function b:SetSelected(on)
        self.selected = on
        self.sel:SetShown(on)
        self.bar:SetShown(on)
    end
    b:SetScript("OnEnter", function(self)
        if not self.selected then self.hi:Show() end
        if self.tip then W.ShowTip(self, self.text:GetText(), self.tip) end
    end)
    b:SetScript("OnLeave", function(self) self.hi:Hide(); W.HideTip() end)
    b:SetSelected(false)
    return b
end

local sideRows, sideUsed = {}, 0
UI.search = ""

local function RingRow(parent)
    sideUsed = sideUsed + 1
    local b = sideRows[sideUsed]
    if not b then
        b = SideRow(parent, 26)
        b.dot = CreateFrame("Button", nil, b)
        b.dot:SetSize(22, 22)
        b.dot:SetPoint("RIGHT", b, "RIGHT", -10, 0)
        b.dot.ring = W.Solid(b.dot, "ARTWORK", 1, 1, 1, 1)
        b.dot.ring:SetTexture(W.DOT)
        b.dot.ring:SetSize(10, 10)
        b.dot.ring:SetPoint("CENTER")
        b.dot:SetScript("OnClick", function(self)
            local def = self.def
            local key = def.key .. "Enabled"
            db[key] = not db[key]
            if def.toggle[3] then def.toggle[3](db[key]) end
            UI.Refresh()
        end)
        b.dot:SetScript("OnEnter", function(self)
            local on = db[self.def.key .. "Enabled"]
            W.ShowTip(self, self.def.toggle[1], (on and "|cff33ff33On|r" or "|cff999999Off|r") .. ": click to turn "
                .. (on and "off." or "on.") .. "\n" .. self.def.toggle[2])
        end)
        b.dot:SetScript("OnLeave", W.HideTip)
        b.chev = W.Chevron(b, 7, 0.78, 0.62, 1, true)
        b.chevDown = W.Chevron(b, 7, 0.78, 0.62, 1, false)
        sideRows[sideUsed] = b
    end
    b:ClearAllPoints()
    b:Show()
    b.tip = nil
    b.chevDown:Hide()
    return b
end

-- The Classes folder's rings are listed under a header per class, each one collapsible.
local collapsedClass = {}

local function ClassName(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and names[class]) or (class:sub(1, 1) .. class:sub(2):lower())
end

local function ClassColor(class)
    local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if c then return c.r, c.g, c.b end
    return 0.86, 0.87, 0.89
end

-- The class a ring is filed under: yours when it's one of its classes, else the first by name.
local function RingClass(def)
    if not (def and def.class) then return "OTHER" end
    local _, mine = UnitClass("player")
    if mine and def.class[mine] then return mine end
    local best
    for class in pairs(def.class) do
        if not best or class < best then best = class end
    end
    return best or "OTHER"
end

local function RefreshSidebar()
    local list = UI.win.ringList
    for i = 1, #sideRows do sideRows[i]:Hide() end
    sideUsed = 0
    local child = list.child
    local y = -4
    local needle = UI.search:lower()
    local folders = {}
    for key, f in pairs(FOLDERS) do folders[#folders + 1] = { key = key, f = f } end
    table.sort(folders, function(a, b) return a.f.order < b.f.order end)
    for _, entry in ipairs(folders) do
        local folderPage = UI.root.args[entry.key]
        local rings = {}
        for _, e in ipairs(Sorted(folderPage.args)) do
            if e.opt.type == "group" and not e.opt.inline and not Eval(e.opt.hidden, Info(e.opt, entry.key, e.key)) then
                local name = tostring(Eval(e.opt.name, Info(e.opt, entry.key, e.key)) or e.key)
                if needle == "" or name:lower():find(needle, 1, true) or entry.f.name:lower():find(needle, 1, true) then
                    rings[#rings + 1] = { key = e.key, name = name }
                end
            end
        end
        if #rings > 0 then
            local head = RingRow(child)
            head:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y - 6)
            head:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            head:SetHeight(30)
            head.text:ClearAllPoints()
            head.text:SetPoint("LEFT", head, "LEFT", 18, 0)
            head.text:SetText(entry.f.name)
            head.text:SetTextColor(0.80, 0.66, 1) -- the logo's violet
            head.dot:Hide()
            head.chev:Hide()
            head.tip = entry.f.text
            head:SetSelected(UI.current == entry.key)
            head:SetScript("OnClick", function() UI.SelectPage(entry.key) end)
            y = y - 36
            -- In the Classes folder, the rings go under a header per class (yours first, then
            -- by name); clicking a header folds its rings away. A search shows them all.
            local shown = rings
            if entry.key == "class" then
                local byClass, order = {}, {}
                for _, r in ipairs(rings) do
                    local class = RingClass(ns.FindRing(r.key))
                    if not byClass[class] then byClass[class] = {}; order[#order + 1] = class end
                    table.insert(byClass[class], r)
                end
                local _, mine = UnitClass("player")
                table.sort(order, function(a, b)
                    if (a == mine) ~= (b == mine) then return a == mine end
                    return ClassName(a) < ClassName(b)
                end)
                shown = {}
                for _, class in ipairs(order) do
                    shown[#shown + 1] = { classHead = class, count = #byClass[class] }
                    if needle ~= "" or not collapsedClass[class] then
                        for _, r in ipairs(byClass[class]) do shown[#shown + 1] = r end
                    end
                end
            end
            for _, r in ipairs(shown) do
              if r.classHead then
                local class = r.classHead
                local open = needle ~= "" or not collapsedClass[class]
                local row = RingRow(child)
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
                row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
                row:SetHeight(26)
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row, "LEFT", 40, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -34, 0)
                row.text:SetText(class == "OTHER" and "Other" or ClassName(class))
                row.text:SetTextColor(ClassColor(class))
                row.dot:Hide()
                row.chev:ClearAllPoints(); row.chev:SetPoint("LEFT", row, "LEFT", 26, 0)
                row.chevDown:ClearAllPoints(); row.chevDown:SetPoint("LEFT", row, "LEFT", 26, 0)
                row.chev:SetShown(not open)
                row.chevDown:SetShown(open)
                row.tip = (open and "Click to hide " or "Click to show ") .. "this class's rings ("
                    .. r.count .. ")."
                row:SetSelected(false)
                row:SetScript("OnClick", function()
                    collapsedClass[class] = not collapsedClass[class] or nil
                    RefreshSidebar()
                end)
                y = y - 26
              else
                local path = entry.key .. "." .. r.key
                local row = RingRow(child)
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
                row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
                row:SetHeight(26)
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row, "LEFT", entry.key == "class" and 42 or 30, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -34, 0)
                row.text:SetText(r.name)
                local def = ns.FindRing(r.key)
                local selected = UI.current == path
                row:SetSelected(selected)
                row.chev:Hide()
                if def and def.key == r.key and ns.HiddenForClass(def) then
                    -- another class's ring: its page opens (greyed out), but no on/off dot
                    row.dot:Hide()
                    row.text:SetTextColor(selected and 0.8 or 0.42, selected and 0.8 or 0.43, selected and 0.8 or 0.46)
                elseif def and def.key == r.key and def.toggle then
                    local on = db[def.key .. "Enabled"]
                    row.dot.def = def
                    row.dot.ring:SetVertexColor(on and 0.35 or 0.32, on and 0.85 or 0.33, on and 0.45 or 0.36, 1)
                    row.dot:Show()
                    row.text:SetTextColor(selected and 1 or (on and 0.86 or 0.55), selected and 1 or (on and 0.87 or 0.56),
                        selected and 1 or (on and 0.89 or 0.6))
                else
                    row.dot:Hide()
                    row.text:SetTextColor(selected and 1 or 0.86, selected and 1 or 0.87, selected and 1 or 0.89)
                end
                row:SetScript("OnClick", function() UI.SelectPage(path) end)
                y = y - 26
              end
            end
        end
    end
    if sideUsed == 0 then
        local row = RingRow(child)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y - 6)
        row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", 18, 0)
        row.text:SetText("No rings match.")
        row.text:SetTextColor(0.5, 0.5, 0.55)
        row.dot:Hide(); row.chev:Hide()
        row:SetSelected(false)
        row:SetScript("OnClick", nil)
        y = y - 30
    end
    child:SetWidth(SIDE_W - 14)
    child:SetHeight(-y + 8)
    list:Update()

    for _, b in ipairs(UI.win.nav) do
        local item = b.item
        b:SetSelected(item.path ~= nil and UI.current == item.path)
        local active = item.active and item.active()
        b.text:SetText(active and "|cff33ff33Finish editing|r" or item.text)
    end
end

-- For the files loaded after this one.
UI.RefreshSidebar = RefreshSidebar
UI.NAV = NAV
UI.SideRow = SideRow
