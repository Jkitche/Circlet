-- Circlet: The options window's cells: one setting each, a label and its control, pooled by kind.
local _, ns = ...

local UI = ns.OptionsUI
local W = UI.W
local BODY_W = UI.BODY_W
local COL_W = UI.COL_W
local ROW_H = UI.ROW_H
local Eval = UI.Eval
local Num = UI.Num
local Commit = UI.Commit
local Fmt = UI.Fmt

---------------------------------------------------------------- cells
-- One setting: a label on the left and its control on the right, half the width of the
-- page (or all of it, for text). Pooled by kind and reused as pages change.
local pools, used = {}, {}
local BUILD = {}

local function CellUpdateCommon(c)
    local opt, info = c.opt, c.info
    c.isDisabled = (c.pageOff or Eval(opt.disabled, info) or (c.group and Eval(c.group.disabled, info))) and true
        or false
    c:SetAlpha(c.isDisabled and 0.38 or 1)
    if c.label then c.label:SetText(tostring(Eval(opt.name, info) or "")) end
end

local function NewCell(kind, parent)
    local c = CreateFrame("Button", nil, parent)
    c.kind = kind
    c.bg = W.Solid(c, "BACKGROUND", 1, 1, 1, 0.03)
    c.bg:SetAllPoints()
    c.hover = W.Solid(c, "BACKGROUND", 1, 1, 1, 0.035, 1)
    c.hover:SetAllPoints()
    c.hover:Hide()
    c.divider = W.Solid(c, "BORDER", 1, 1, 1, 0.07)
    c.divider:SetWidth(1)
    c.divider:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, -8)
    c.divider:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 8)
    c.label = W.Text(c, 13, 0.93, 0.93, 0.93)
    c.label:SetPoint("LEFT", c, "LEFT", 18, 0)
    c.label:SetWordWrap(true)
    c.tipTitle = function() return c.opt and tostring(Eval(c.opt.name, c.info) or "") end
    c.tipText = function() return c.opt and Eval(c.opt.desc, c.info) end
    function c:OnHover(on)
        self.hover:SetShown(on and not self.isText and not self.isDisabled)
        if on and not self.isText then
            W.ShowTip(self, self.tipTitle, self.tipText)
        else
            W.HideTip()
        end
    end
    c:SetScript("OnEnter", function(self) self:OnHover(true) end)
    c:SetScript("OnLeave", function(self) self:OnHover(false) end)
    BUILD[kind](c)
    return c
end

local function Acquire(kind, parent)
    pools[kind] = pools[kind] or {}
    used[kind] = (used[kind] or 0) + 1
    local c = pools[kind][used[kind]]
    if not c then
        c = NewCell(kind, parent)
        pools[kind][used[kind]] = c
    end
    c:ClearAllPoints()
    c:Show()
    return c
end

local function ReleaseAll()
    for kind, list in pairs(pools) do
        for _, c in ipairs(list) do
            c:Hide()
            c.opt = nil
        end
        used[kind] = 0
    end
end

local function EachCell(fn)
    for kind, list in pairs(pools) do
        for i = 1, used[kind] or 0 do
            fn(list[i])
        end
    end
end

BUILD.toggle = function(c)
    c.switch = W.Switch(c, function(_, v)
        if not c.isDisabled then Commit(c.opt, c.info, v) end
    end)
    c.switch:SetPoint("RIGHT", c, "RIGHT", -18, 0)
    W.PassHover(c.switch, c)
    c.label:SetPoint("RIGHT", c.switch, "LEFT", -14, 0)
    c:SetScript("OnClick", function(self)
        if not self.isDisabled then self.switch:Click() end
    end)
    c.Update = function(self)
        CellUpdateCommon(self)
        self.switch:SetOn(self.opt.get(self.info))
        self.switch:EnableMouse(not self.isDisabled)
    end
end

-- A number typed in the box: clamped to the option's range and rounded to its step.
local function ParseNumber(opt, text)
    local v = tonumber((tostring(text or ""):gsub("%%", "")))
    if not v then return nil end
    if opt.isPercent then v = v / 100 end
    local min, max = opt.min or -math.huge, opt.max or math.huge
    if opt.step and opt.step > 0 and opt.min then
        v = opt.min + math.floor((v - opt.min) / opt.step + 0.5) * opt.step
    end
    return math.max(min, math.min(max, v))
end

BUILD.range = function(c)
    c.box = W.EditBox(c, 54, "CENTER", function(text)
        local v = ParseNumber(c.opt, text)
        if v and not c.isDisabled then Commit(c.opt, c.info, v) end
    end)
    c.box:SetPoint("RIGHT", c, "RIGHT", -18, 0)
    c.box.revert = function() return c.opt and Fmt(c.opt.get(c.info), c.opt) or "" end
    W.PassHover(c.box, c)
    c.slider = W.Slider(c, 120, function(v)
        c.box:SetText(Fmt(v, c.opt))
        c.opt.set(c.info, v)
    end, function() UI.Refresh() end)
    c.slider:SetPoint("RIGHT", c.box, "LEFT", -16, 0)
    W.PassHover(c.slider, c)
    c.label:SetPoint("RIGHT", c.slider, "LEFT", -14, 0)
    c.Update = function(self)
        CellUpdateCommon(self)
        local opt = self.opt
        local min, max = opt.softMin or opt.min or 0, opt.softMax or opt.max or 100
        self.slider:SetRange(min, max, opt.step, opt.bigStep)
        local v = Num(opt.get(self.info), min)
        if not self.slider.dragging then self.slider:SetValue(v) end
        if not self.box:HasFocus() then self.box:SetText(Fmt(v, opt)) end
        self.slider.disabled = self.isDisabled
        self.box:EnableMouse(not self.isDisabled)
    end
end

BUILD.select = function(c)
    c.drop = W.Dropdown(c, 184, function(v)
        if not c.isDisabled then Commit(c.opt, c.info, v) end
    end)
    c.drop:SetPoint("RIGHT", c, "RIGHT", -18, 0)
    W.PassHover(c.drop, c)
    c.label:SetPoint("RIGHT", c.drop, "LEFT", -14, 0)
    c.Update = function(self)
        CellUpdateCommon(self)
        local opt, info = self.opt, self.info
        local values = Eval(opt.values, info) or {}
        local sorting = Eval(opt.sorting, info)
        local items = {}
        if type(sorting) == "table" then
            for _, k in ipairs(sorting) do
                if values[k] ~= nil then items[#items + 1] = { k, tostring(values[k]) } end
            end
        else
            for k, text in pairs(values) do
                items[#items + 1] = { k, tostring(text) }
            end
            table.sort(items, function(a, b) return a[2] < b[2] end)
        end
        local value = opt.get(info)
        self.drop:SetItems(items, value)
        if value == nil or values[value] == nil then self.drop.label:SetText("|cff777a80Choose...|r") end
        self.drop.disabled = self.isDisabled
    end
end

BUILD.color = function(c)
    c.swatch = W.Swatch(c, function()
        if c.isDisabled then return end
        local opt, info = c.opt, c.info
        local r, g, b = opt.get(info)
        W.PickColor(r or 1, g or 1, b or 1, function(nr, ng, nb)
            opt.set(info, nr, ng, nb, 1)
            c.swatch:SetColor(nr, ng, nb)
        end)
    end)
    c.swatch:SetPoint("RIGHT", c, "RIGHT", -18, 0)
    W.PassHover(c.swatch, c)
    c.label:SetPoint("RIGHT", c.swatch, "LEFT", -14, 0)
    c:SetScript("OnClick", function(self) self.swatch:Click() end)
    c.Update = function(self)
        CellUpdateCommon(self)
        self.swatch:SetColor(self.opt.get(self.info))
    end
end

BUILD.input = function(c)
    c.edit = W.EditBox(c, 184, "LEFT", function(text)
        if not c.isDisabled then Commit(c.opt, c.info, text) end
    end)
    c.edit:SetPoint("RIGHT", c, "RIGHT", -18, 0)
    c.edit.revert = function() return c.opt and tostring(c.opt.get(c.info) or "") or "" end
    W.PassHover(c.edit, c)
    c.label:SetPoint("RIGHT", c.edit, "LEFT", -14, 0)
    c.Update = function(self)
        CellUpdateCommon(self)
        if not self.edit:HasFocus() then self.edit:SetText(tostring(self.opt.get(self.info) or "")) end
        self.edit:EnableMouse(not self.isDisabled)
    end
end

BUILD.execute = function(c)
    c.label:Hide()
    c.button = W.Button(c, COL_W - 36, 28, "", function() Commit(c.opt, c.info) end)
    c.button:SetPoint("CENTER")
    c.button.tipTitle, c.button.tipText = c.tipTitle, c.tipText
    c:SetScript("OnClick", function(self)
        if not self.isDisabled then self.button:Click() end
    end)
    c.Update = function(self)
        CellUpdateCommon(self)
        self:SetAlpha(1)
        self.button:SetText(tostring(Eval(self.opt.name, self.info) or ""))
        self.button:SetEnabled(not self.isDisabled)
    end
end

-- Text across the whole page (descriptions), and small headings inside a section.
BUILD.text = function(c)
    c.isText = true
    c.divider:Hide()
    c.label:ClearAllPoints()
    c.label:SetPoint("TOPLEFT", c, "TOPLEFT", 18, -12)
    c.label:SetWidth(BODY_W - 36)
    c.label:SetTextColor(0.74, 0.76, 0.8)
    c.Update = function(self)
        CellUpdateCommon(self)
        self:SetAlpha(1)
        local h = Num(self.label:GetStringHeight(), 14)
        self:SetHeight(math.max(ROW_H - 8, h + 24))
    end
end

BUILD.subhead = function(c)
    c.isText = true
    c.divider:Hide()
    c.bg:Hide()
    c.label:ClearAllPoints()
    c.label:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 4, 6)
    c.label:SetTextColor(0.68, 0.58, 0.48)
    c.Update = function(self)
        CellUpdateCommon(self)
        self:SetAlpha(1)
        self.label:SetText(tostring(Eval(self.opt.name, self.info) or ""):upper())
    end
end

local CELL_KIND = {
    toggle = "toggle",
    range = "range",
    select = "select",
    color = "color",
    input = "input",
    execute = "execute",
    description = "text",
    header = "subhead",
}

---------------------------------------------------------------- section titles
local heads, headsUsed = {}, 0
local function Head(parent)
    headsUsed = headsUsed + 1
    local h = heads[headsUsed]
    if not h then
        h = W.Text(parent, 11, 0.68, 0.58, 0.48)
        heads[headsUsed] = h
    end
    h:ClearAllPoints()
    h:Show()
    return h
end

local function ReleaseHeads()
    for i = 1, headsUsed do
        heads[i]:Hide()
    end
    headsUsed = 0
end

-- For the files loaded after this one.
UI.Acquire = Acquire
UI.ReleaseAll = ReleaseAll
UI.EachCell = EachCell
UI.CELL_KIND = CELL_KIND
UI.Head = Head
UI.ReleaseHeads = ReleaseHeads
