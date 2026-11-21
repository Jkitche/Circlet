-- Circlet: The controls the options window is made of, in a flat dark style.
local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
-- Plain frames and textures, no templates: an on/off switch, a slider with a number box
-- beside it, a dropdown, a color swatch, buttons, text boxes and a scrolling area with a
-- thin scrollbar. UI/Options.lua lays them out.

local W = {}

local ACCENT = { r = 0.95, g = 0.74, b = 0.28 } -- Circlet gold
W.ACCENT = ACCENT
W.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
W.TITLE_FONT = "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DOT = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
W.DOT = DOT

local function Clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end
W.Clamp = Clamp

function W.Text(parent, size, r, g, b, layer, font, flags)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    if not pcall(fs.SetFont, fs, font or W.FONT, size, flags or "") or not fs:GetFont() then
        fs:SetFontObject(GameFontHighlight)
    end
    fs:SetTextColor(r or 1, g or 1, b or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

function W.Solid(parent, layer, r, g, b, a, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- A 1px outline just inside a frame.
function W.Border(frame, r, g, b, a, layer)
    return ns.SkinEdges(frame, layer or "BORDER", 1, 1, 0, r, g, b, a or 1)
end

function W.SetBorderColor(edges, r, g, b, a)
    for _, t in pairs(edges) do t:SetColorTexture(r, g, b, a or 1) end
end
local SetBorderColor = W.SetBorderColor

-- A chevron drawn with two lines, pointing down (or right with `right`).
function W.Chevron(parent, size, r, g, b, right)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local h = size / 2
    local a = f:CreateLine(nil, "OVERLAY")
    local c = f:CreateLine(nil, "OVERLAY")
    for _, l in ipairs({ a, c }) do
        l:SetThickness(1.5)
        l:SetColorTexture(r, g, b, 1)
    end
    if right then
        a:SetStartPoint("CENTER", f, -h / 2, h); a:SetEndPoint("CENTER", f, h / 2, 0)
        c:SetStartPoint("CENTER", f, h / 2, 0); c:SetEndPoint("CENTER", f, -h / 2, -h)
    else
        a:SetStartPoint("CENTER", f, -h, h / 2); a:SetEndPoint("CENTER", f, 0, -h / 2)
        c:SetStartPoint("CENTER", f, 0, -h / 2); c:SetEndPoint("CENTER", f, h, h / 2)
    end
    f.lines = { a, c }
    function f:SetColor(r2, g2, b2, a2) for _, l in ipairs(self.lines) do l:SetColorTexture(r2, g2, b2, a2 or 1) end end
    return f
end

---------------------------------------------------------------- tooltips
-- title and text may be functions (called with no arguments).
function W.ShowTip(owner, title, text)
    if not GameTooltip then return end
    if type(title) == "function" then title = title() end
    if type(text) == "function" then text = text() end
    if not title or title == "" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if text and text ~= "" then GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

function W.HideTip()
    if GameTooltip then GameTooltip:Hide() end
end

-- Hovering `frame` shows `cell`'s tooltip and hover look (controls cover their cell, so
-- they pass the hover on).
function W.PassHover(frame, cell)
    frame:HookScript("OnEnter", function() if cell.OnHover then cell:OnHover(true) end end)
    frame:HookScript("OnLeave", function() if cell.OnHover then cell:OnHover(false) end end)
end

---------------------------------------------------------------- button
function W.Button(parent, w, h, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = W.Solid(b, "BACKGROUND", 0.10, 0.075, 0.08, 1)
    b.bg:SetAllPoints()
    b.border = W.Border(b, 0.33, 0.26, 0.24, 1)
    b.label = W.Text(b, 12, 0.92, 0.92, 0.92)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetText(text or "")
    b.borderColor = { 0.33, 0.26, 0.24 }
    b:SetScript("OnEnter", function(self)
        if not self.disabled then
            SetBorderColor(self.border, ACCENT.r, ACCENT.g, ACCENT.b, 1)
            self.bg:SetColorTexture(0.15, 0.11, 0.09, 1)
        end
        if self.tipTitle then W.ShowTip(self, self.tipTitle, self.tipText) end
    end)
    b:SetScript("OnLeave", function(self)
        local c = self.borderColor
        SetBorderColor(self.border, c[1], c[2], c[3], 1)
        self.bg:SetColorTexture(0.10, 0.075, 0.08, 1)
        W.HideTip()
    end)
    b:SetScript("OnClick", function(self, ...)
        if self.disabled then return end
        if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856) end
        if self.onClick then self.onClick(self, ...) end
    end)
    b.onClick = onClick
    function b:SetText(t) self.label:SetText(t or "") end
    function b:SetEnabled(on)
        self.disabled = not on
        self:SetAlpha(on and 1 or 0.4)
    end
    -- An accent outline that stays (the window's Close button).
    function b:SetAccent()
        self.borderColor = { ACCENT.r * 0.8, ACCENT.g * 0.8, ACCENT.b * 0.8 }
        SetBorderColor(self.border, ACCENT.r * 0.8, ACCENT.g * 0.8, ACCENT.b * 0.8, 1)
        self.label:SetTextColor(1, 0.86, 0.5)
    end
    return b
end

---------------------------------------------------------------- on/off switch
function W.Switch(parent, onToggle)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(40, 20)
    -- A pill: round caps at both ends and a bar between them, with a round knob.
    local function Round(layer, size)
        local t = s:CreateTexture(nil, layer)
        t:SetTexture(DOT)
        t:SetSize(size, size)
        return t
    end
    s.capL = Round("BACKGROUND", 20)
    s.capL:SetPoint("LEFT")
    s.capR = Round("BACKGROUND", 20)
    s.capR:SetPoint("RIGHT")
    s.mid = W.Solid(s, "BACKGROUND", 1, 1, 1, 1)
    s.mid:SetPoint("TOPLEFT", s, "TOPLEFT", 10, 0)
    s.mid:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -10, 0)
    s.knob = Round("ARTWORK", 14)
    local function Track(r, g, b)
        s.capL:SetVertexColor(r, g, b, 1)
        s.capR:SetVertexColor(r, g, b, 1)
        s.mid:SetColorTexture(r, g, b, 1)
    end
    function s:SetOn(on)
        self.on = on and true or false
        self.knob:ClearAllPoints()
        if self.on then
            Track(ACCENT.r, ACCENT.g, ACCENT.b)
            self.knob:SetVertexColor(0.16, 0.10, 0.06, 1)
            self.knob:SetPoint("RIGHT", self, "RIGHT", -3, 0)
        else
            Track(0.25, 0.2, 0.21)
            self.knob:SetVertexColor(0.62, 0.56, 0.54, 1)
            self.knob:SetPoint("LEFT", self, "LEFT", 3, 0)
        end
    end
    s:SetScript("OnClick", function(self)
        if PlaySound then
            pcall(PlaySound, SOUNDKIT and (self.on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
                or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856)
        end
        onToggle(self, not self.on)
    end)
    s:SetOn(false)
    return s
end

---------------------------------------------------------------- slider
-- onChange(value) while dragging; onRelease(value) when the mouse lets go.
function W.Slider(parent, width, onChange, onRelease)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(width, 20)
    s:EnableMouse(true)
    s.width = width
    s.track = W.Solid(s, "BACKGROUND", 0.28, 0.22, 0.21, 1)
    s.track:SetHeight(4)
    s.track:SetPoint("LEFT"); s.track:SetPoint("RIGHT")
    s.fill = W.Solid(s, "ARTWORK", ACCENT.r, ACCENT.g, ACCENT.b, 1)
    s.fill:SetHeight(4)
    s.fill:SetPoint("LEFT", s.track, "LEFT")
    s.thumb = W.Solid(s, "OVERLAY", ACCENT.r, ACCENT.g, ACCENT.b, 1)
    s.thumb:SetSize(12, 16)
    s.thumbHi = W.Solid(s, "OVERLAY", 1, 1, 1, 0.25, 1)
    s.thumbHi:SetPoint("TOPLEFT", s.thumb, "TOPLEFT", 1, -1)
    s.thumbHi:SetPoint("BOTTOMRIGHT", s.thumb, "TOPRIGHT", -1, -6)
    s.min, s.max, s.step, s.value = 0, 1, nil, 0

    function s:SetRange(min, max, step, dragStep)
        self.min, self.max, self.step, self.dragStep = min, max, step, dragStep
    end
    function s:SetValue(v)
        self.value = v
        local span = self.max - self.min
        local frac = span > 0 and Clamp((v - self.min) / span, 0, 1) or 0
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("CENTER", self, "LEFT", frac * self.width, 0)
        self.fill:SetWidth(math.max(0.5, frac * self.width))
    end
    local function FromCursor(self)
        local x = GetCursorPosition() / self:GetEffectiveScale()
        local frac = Clamp((x - (self:GetLeft() or 0)) / self.width, 0, 1)
        local v = self.min + frac * (self.max - self.min)
        local st = self.dragStep or self.step
        if st and st > 0 then v = self.min + math.floor((v - self.min) / st + 0.5) * st end
        v = tonumber(string.format("%.4f", Clamp(v, self.min, self.max)))
        if v ~= self.value then
            self:SetValue(v)
            onChange(v)
        end
    end
    s:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or self.disabled then return end
        self.dragging = true
        FromCursor(self)
        self:SetScript("OnUpdate", FromCursor)
    end)
    s:SetScript("OnMouseUp", function(self)
        if not self.dragging then return end
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        if onRelease then onRelease(self.value) end
    end)
    s:SetScript("OnEnter", function(self) self.thumb:SetColorTexture(1, 0.88, 0.55, 1) end)
    s:SetScript("OnLeave", function(self) self.thumb:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 1) end)
    return s
end

---------------------------------------------------------------- text boxes
-- onCommit(text) on Enter; Escape or clicking away puts back what `revert` returns.
function W.EditBox(parent, width, justify, onCommit)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width, 24)
    e:SetAutoFocus(false)
    pcall(e.SetFont, e, W.FONT, 12, "")
    e:SetJustifyH(justify or "LEFT")
    e:SetTextColor(0.88, 0.88, 0.88)
    e:SetTextInsets(8, 8, 0, 0)
    e.bg = W.Solid(e, "BACKGROUND", 0.045, 0.035, 0.04, 1)
    e.bg:SetAllPoints()
    e.border = W.Border(e, 0.28, 0.22, 0.21, 1)
    e:SetScript("OnEnterPressed", function(self)
        self.committing = true
        onCommit(self:GetText())
        self.committing = false
        self:ClearFocus()
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        SetBorderColor(self.border, ACCENT.r, ACCENT.g, ACCENT.b, 1)
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        SetBorderColor(self.border, 0.28, 0.22, 0.21, 1)
        if self.revert then self:SetText(self.revert() or "") end
    end)
    return e
end

---------------------------------------------------------------- dropdown
-- items: a list of { value, text }; onPick(value).
local list, catcher

local function CloseList()
    if list then list:Hide() end
    if catcher then catcher:Hide() end
end
W.CloseList = CloseList

local LIST_ROWS, LIST_ROW_H = 12, 22

local function LayoutList()
    local owner = list.owner
    local items = owner.items or {}
    local shown = math.min(#items, LIST_ROWS)
    list.offset = Clamp(list.offset, 0, math.max(0, #items - LIST_ROWS))
    for i = 1, LIST_ROWS do
        local row = list.rows[i]
        local item = items[i + list.offset]
        if i <= shown and item then
            row.value = item[1]
            row.text:SetText(item[2])
            local current = item[1] == owner.value
            row.text:SetTextColor(current and 1 or 0.88, current and 0.84 or 0.86, current and 0.45 or 0.84)
            row.mark:SetShown(current)
            row:Show()
        else
            row:Hide()
        end
    end
    list:SetHeight(shown * LIST_ROW_H + 8)
    list.more:SetShown(#items > LIST_ROWS)
end

local function BuildList()
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", CloseList)
    catcher:Hide()
    list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetFrameLevel(20)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    list.bg = W.Solid(list, "BACKGROUND", 0.085, 0.065, 0.07, 0.98)
    list.bg:SetAllPoints()
    list.border = W.Border(list, 0.4, 0.32, 0.26, 1)
    list.rows = {}
    for i = 1, LIST_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(LIST_ROW_H)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4 - (i - 1) * LIST_ROW_H)
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -4, -4 - (i - 1) * LIST_ROW_H)
        row.hi = W.Solid(row, "BACKGROUND", ACCENT.r, ACCENT.g, ACCENT.b, 0.22)
        row.hi:SetAllPoints()
        row.hi:Hide()
        row.mark = W.Solid(row, "ARTWORK", ACCENT.r, ACCENT.g, ACCENT.b, 1)
        row.mark:SetSize(3, LIST_ROW_H - 8)
        row.mark:SetPoint("LEFT", 2, 0)
        row.text = W.Text(row, 12, 0.88, 0.88, 0.88)
        row.text:SetPoint("LEFT", 12, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) self.hi:Show() end)
        row:SetScript("OnLeave", function(self) self.hi:Hide() end)
        row:SetScript("OnClick", function(self)
            local owner = list.owner
            CloseList()
            if owner and owner.onPick then owner.onPick(self.value) end
        end)
        list.rows[i] = row
    end
    list.more = W.Text(list, 10, 0.5, 0.5, 0.55)
    list.more:SetPoint("BOTTOMRIGHT", -8, 3)
    list.more:SetText("scroll for more")
    list:SetScript("OnMouseWheel", function(self, delta)
        self.offset = self.offset - delta * 3
        LayoutList()
    end)
    list:SetScript("OnHide", function() if catcher then catcher:Hide() end end)
end

local function OpenList(owner)
    if not list then BuildList() end
    if list:IsShown() and list.owner == owner then CloseList() return end
    list.owner = owner
    list.offset = 0
    for i, item in ipairs(owner.items or {}) do
        if item[1] == owner.value then list.offset = i - math.floor(LIST_ROWS / 2) break end
    end
    -- Same size on screen as the dropdown, whatever the window's scale.
    list:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    list:SetWidth(owner:GetWidth())
    LayoutList()
    catcher:Show()
    list:Show()
end

function W.Dropdown(parent, width, onPick)
    local b = W.Button(parent, width, 26, "", function(self) OpenList(self) end)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 10, 0)
    b.label:SetPoint("RIGHT", -26, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    b.label:SetTextColor(0.75, 0.76, 0.8)
    b.arrow = W.Chevron(b, 8, 0.75, 0.66, 0.55)
    b.arrow:SetPoint("RIGHT", -12, 0)
    b.onPick = onPick
    -- items: list of { value, text }; value: the current one.
    function b:SetItems(items, value)
        self.items, self.value = items, value
        local text
        for _, item in ipairs(items) do if item[1] == value then text = item[2] end end
        self.label:SetText(text or "")
    end
    b:HookScript("OnHide", function(self) if list and list.owner == self then CloseList() end end)
    return b
end

---------------------------------------------------------------- color swatch
function W.Swatch(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(28, 28)
    b.edge = W.Solid(b, "BACKGROUND", 0.4, 0.4, 0.44, 1)
    b.edge:SetAllPoints()
    b.gap = W.Solid(b, "BORDER", 0, 0, 0, 1)
    b.gap:SetPoint("TOPLEFT", 1, -1); b.gap:SetPoint("BOTTOMRIGHT", -1, 1)
    b.color = W.Solid(b, "ARTWORK", 1, 1, 1, 1)
    b.color:SetPoint("TOPLEFT", 3, -3); b.color:SetPoint("BOTTOMRIGHT", -3, 3)
    function b:SetColor(r, g, bl) self.color:SetColorTexture(r or 1, g or 1, bl or 1, 1) end
    b:SetScript("OnEnter", function(self) self.edge:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 1) end)
    b:SetScript("OnLeave", function(self) self.edge:SetColorTexture(0.4, 0.4, 0.44, 1) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- The game's color picker, on any client: onChange(r, g, b) as the color moves, and with
-- the old color again if it's cancelled.
function W.PickColor(r, g, b, onChange)
    local picker = ColorPickerFrame
    if not picker then return end
    local function Current()
        local nr, ng, nb = picker:GetColorRGB()
        onChange(nr, ng, nb)
    end
    local function Cancel() onChange(r, g, b) end
    if picker.SetupColorPickerAndShow then
        picker:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = Current, func = Current, cancelFunc = Cancel,
            previousValues = { r = r, g = g, b = b },
        })
    else
        picker:Hide()
        picker.hasOpacity = false
        picker.previousValues = { r, g, b }
        picker.func, picker.cancelFunc = Current, Cancel
        picker:SetColorRGB(r, g, b)
        if ShowUIPanel then ShowUIPanel(picker) else picker:Show() end
    end
end

---------------------------------------------------------------- scrolling area
-- A scroll frame with its content in .child, scrolled by the mouse wheel or by dragging the
-- thin bar on the right. Call :Update() after changing the content's height.
function W.ScrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    sf.child = child
    sf:EnableMouseWheel(true)
    local bar = CreateFrame("Frame", nil, sf)
    bar:SetWidth(6)
    bar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -2, -4)
    bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -2, 4)
    bar.track = W.Solid(bar, "BACKGROUND", 1, 1, 1, 0.04)
    bar.track:SetAllPoints()
    local thumb = CreateFrame("Frame", nil, bar)
    thumb:SetWidth(6)
    thumb:EnableMouse(true)
    thumb.tex = W.Solid(thumb, "ARTWORK", 0.5, 0.42, 0.36, 0.7)
    thumb.tex:SetAllPoints()
    sf.bar, sf.thumb = bar, thumb

    local function MaxScroll() return math.max(0, (tonumber(child:GetHeight()) or 0) - (tonumber(sf:GetHeight()) or 0)) end
    function sf:Update()
        local max = MaxScroll()
        local y = Clamp(tonumber(self:GetVerticalScroll()) or 0, 0, max)
        self:SetVerticalScroll(y)
        if max <= 0 then bar:Hide() return end
        bar:Show()
        local trackH = bar:GetHeight() or 1
        local view = self:GetHeight() or 1
        local thumbH = math.max(24, trackH * view / (view + max))
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -(trackH - thumbH) * (y / max))
    end
    function sf:ScrollTo(y)
        self:SetVerticalScroll(Clamp(y, 0, MaxScroll()))
        self:Update()
    end
    sf:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo((tonumber(self:GetVerticalScroll()) or 0) - delta * 60) end)
    sf:SetScript("OnSizeChanged", function(self) self:Update() end)
    thumb:SetScript("OnMouseDown", function(self)
        self.startY = select(2, GetCursorPosition()) / self:GetEffectiveScale()
        self.startScroll = tonumber(sf:GetVerticalScroll()) or 0
        self:SetScript("OnUpdate", function(me)
            local y = select(2, GetCursorPosition()) / me:GetEffectiveScale()
            local trackH, thumbH = bar:GetHeight() or 1, me:GetHeight() or 1
            local per = MaxScroll() / math.max(1, trackH - thumbH)
            sf:ScrollTo(me.startScroll + (me.startY - y) * per)
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    thumb:SetScript("OnEnter", function(self) self.tex:SetColorTexture(0.7, 0.6, 0.5, 0.9) end)
    thumb:SetScript("OnLeave", function(self) self.tex:SetColorTexture(0.5, 0.42, 0.36, 0.7) end)
    return sf
end

---------------------------------------------------------------- window pieces
-- The windows' colors: the body, section titles and text.
W.BG = { 0.072, 0.055, 0.065, 1 } -- solid: cards and cells on it then read the same
W.HEADING = { 0.68, 0.58, 0.48 } -- section titles: warm sand
W.BODY_TEXT = { 0.74, 0.76, 0.8 }
W.MUTED = { 0.68, 0.7, 0.75 }

-- A square button with an X drawn in it.
function W.CloseButton(parent, onClick)
    local b = W.Button(parent, 30, 30, "", onClick)
    for _, sign in ipairs({ 1, -1 }) do
        local l = b:CreateLine(nil, "OVERLAY")
        l:SetThickness(1.5)
        l:SetColorTexture(0.8, 0.8, 0.82, 1)
        l:SetStartPoint("CENTER", b, -6, 6 * sign)
        l:SetEndPoint("CENTER", b, 6, -6 * sign)
    end
    b.tipTitle = "Close"
    return b
end

-- Dresses a window skinned with ns.SkinPanel in the options window's colors: the warm dark
-- body, a faint gold glow in the header instead of the brown band, and a darker footer.
function W.ThemePanel(frame, skin, header, footer)
    -- Through SkinGradient (both ends the same), which replaces the panel's old gradient; a
    -- plain SetColorTexture would leave that gradient multiplied in (near black, see-through).
    local bg = W.BG
    ns.SkinGradient(skin.bg, "VERTICAL", bg[1], bg[2], bg[3], bg[4], bg[1], bg[2], bg[3], bg[4])
    ns.SkinGradient(skin.header, "VERTICAL", ACCENT.r, ACCENT.g, ACCENT.b, 0, ACCENT.r, ACCENT.g, ACCENT.b, 0.07)
    skin.header:SetHeight(header + 60)
    SetBorderColor(skin.border, ns.SKIN_GOLD.r, ns.SKIN_GOLD.g, ns.SKIN_GOLD.b, 0.55)
    if footer then
        skin.footBg = W.Solid(frame, "BACKGROUND", 0, 0, 0, 0.25, -5)
        skin.footBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
        skin.footBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        skin.footBg:SetHeight(footer - 1)
    end
end

-- Shared with the files loaded after this one.
ns.W = W
