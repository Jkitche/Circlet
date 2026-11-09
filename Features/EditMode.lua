-- Circlet: Edit mode: live preview and dragging for each ring.
local ADDON_NAME, ns = ...

local DEFAULTS, EDIT_STRATA, Print, db, RINGS = ns.DEFAULTS, ns.EDIT_STRATA, ns.Print, ns.db, ns.RINGS

-- Edit mode calls ns.RefreshOptions so the options window's sliders and buttons follow
-- drags and toggles; Options.lua replaces this once the window is built.
ns.RefreshOptions = function() end

---------------------------------------------------------------------------
-- Edit mode: the real rings, one at a time (/sq edit [ring])
---------------------------------------------------------------------------
-- Each ring's page has its own Edit mode button. The ring stays on screen showing
-- sample content (above the options window), so color, size and other changes show
-- live, and the ring itself can be dragged. Position = <key>X (offset from screen
-- centre) and <key>FromTop (gap from the top of the screen to the ring's top).

-- The rings, in order, come from the registry (Core/Registry.lua): each has a name and
-- an edit = { set, get }.
local function Editor(key) local def = ns.FindRing(key) return def and def.key == key and def.edit end
local function Name(key) return (ns.FindRing(key) or {}).name or key end

local function SetPosition(key, x, fromTop)
    db[key .. "X"] = math.floor(x + 0.5)
    db[key .. "FromTop"] = math.max(0, math.floor(fromTop + 0.5))
    ns.RefreshOptions() -- keeps the position sliders in sync
end

-- Puts one ring back at its default spot (quiet: skips the chat message). The rings
-- re-read their position every frame, so this shows immediately.
local function ResetPosition(key, quiet)
    key = key:match("^(%l+)%d+$") or key -- quest / totem rings share one position per group
    local x = DEFAULTS[key .. "X"]
    if key == "pin" then x = math.max(0, math.floor(UIParent:GetWidth() / 2 - 330)) end -- by the quest list
    SetPosition(key, x, DEFAULTS[key .. "FromTop"])
    if not quiet then Print(Name(key) .. " ring position reset.") end
end

-- Puts every ring back at its default spot in the row across the top of the screen.
local function ResetPositions()
    for _, def in ipairs(RINGS) do
        ResetPosition(def.key, true)
    end
    Print("All ring positions reset.")
end

-- A small bar naming the rings being edited, with Done; Esc also finishes.
local editBar = CreateFrame("Frame", "CircletEditModeFrame", UIParent)
editBar:SetSize(360, 62)
editBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180)
editBar:SetFrameStrata(EDIT_STRATA)
editBar:Hide()
editBar.bg = editBar:CreateTexture(nil, "BACKGROUND")
editBar.bg:SetAllPoints()
editBar.bg:SetColorTexture(0, 0, 0, 0.75)
editBar.text = editBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
editBar.text:SetPoint("TOP", editBar, "TOP", 0, -9)
editBar.button = CreateFrame("Button", nil, editBar, "UIPanelButtonTemplate")
editBar.button:SetSize(100, 22)
editBar.button:SetPoint("BOTTOM", editBar, "BOTTOM", 0, 9)
editBar.button:SetText(DONE or "Done")

local SetRingEditing -- forward declaration (the bar's buttons call it)

local function EditingKeys()
    local keys = {}
    for _, def in ipairs(RINGS) do
        if def.edit.get() then table.insert(keys, def.key) end
    end
    return keys
end

-- The snap grid, drawn across the screen while any ring is being edited (and snapping
-- is on). Lines run out from the screen's centre, which gets brighter lines.
local grid = CreateFrame("Frame", nil, UIParent)
grid:SetAllPoints(UIParent)
grid:SetFrameStrata("LOW")
grid:Hide()
grid.lines = {}

local function GridLine(i)
    local line = grid.lines[i]
    if not line then
        line = grid:CreateTexture(nil, "BACKGROUND")
        grid.lines[i] = line
    end
    return line
end

local function DrawGrid()
    local g = math.max(4, db.gridSize or 20)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local key = g .. ":" .. math.floor(w) .. ":" .. math.floor(h)
    if grid.key == key then return end
    grid.key = key
    local n = 0
    local function Add(vertical, offset)
        n = n + 1
        local line = GridLine(n)
        local center = math.abs(offset) < 0.5
        line:SetColorTexture(center and 1 or 1, center and 0.82 or 1, center and 0 or 1, center and 0.35 or 0.08)
        line:ClearAllPoints()
        if vertical then
            line:SetPoint("TOP", grid, "TOP", offset, 0)
            line:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
            line:SetWidth(1)
        else
            line:SetPoint("LEFT", grid, "LEFT", 0, offset)
            line:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
            line:SetHeight(1)
        end
        line:Show()
    end
    for i = 0, math.floor(w / 2 / g) do
        Add(true, i * g)
        if i > 0 then Add(true, -i * g) end
    end
    for i = 0, math.floor(h / 2 / g) do
        Add(false, i * g)
        if i > 0 then Add(false, -i * g) end
    end
    for i = n + 1, #grid.lines do grid.lines[i]:Hide() end
end

-- Follows the grid size and snap settings while editing.
grid:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.2 then return end
    self.t = 0
    if not db.snapGrid then self:Hide() return end
    DrawGrid()
end)

local function UpdateGrid(editing)
    if editing and db.snapGrid then
        DrawGrid()
        grid:Show()
    else
        grid:Hide()
    end
end

local function UpdateEditBar()
    local keys = EditingKeys()
    UpdateGrid(#keys > 0)
    if #keys == 0 then
        editBar.closing = true
        editBar:Hide()
        editBar.closing = false
        return
    end
    local names = {}
    for _, key in ipairs(keys) do table.insert(names, Name(key)) end
    editBar.text:SetText("Circlet: editing " .. table.concat(names, ", ")
        .. (#keys == 1 and " ring" or " rings"))
    editBar:Show()
end

-- The options window's Snap to grid checkbox.
ns.RefreshEditGrid = function() UpdateGrid(#EditingKeys() > 0) end

-- quiet: skip the chat line (the options window turns edit mode on and off as you
-- move between ring pages).
SetRingEditing = function(key, on, quiet)
    local editor = Editor(key)
    if not editor or editor.get() == on then return end
    editor.set(on)
    if not on and not quiet then Print(Name(key) .. " ring position saved.") end
    UpdateEditBar()
    ns.RefreshOptions() -- the Edit mode button's label
end

local function ToggleRingEditing(key)
    local editor = Editor(key)
    if editor then SetRingEditing(key, not editor.get()) end
end

local function StopAllEditing()
    for _, def in ipairs(RINGS) do SetRingEditing(def.key, false) end
end

-- /sq edit with no ring: start all of them, or finish if any are being edited.
local function ToggleAllEditing()
    if #EditingKeys() > 0 then
        StopAllEditing()
    else
        for _, def in ipairs(RINGS) do SetRingEditing(def.key, true) end
    end
end

editBar.button:SetScript("OnClick", StopAllEditing)
editBar:SetScript("OnHide", function(self)
    if not self.closing then StopAllEditing() end -- Esc
end)
table.insert(UISpecialFrames, "CircletEditModeFrame")

-- Shared with the files loaded after this one.
ns.ResetPosition = ResetPosition
ns.ResetPositions = ResetPositions
ns.SetPosition = SetPosition
ns.ToggleAllEditing = ToggleAllEditing
ns.ToggleRingEditing = ToggleRingEditing
ns.SetRingEditing = function(...) return SetRingEditing(...) end
