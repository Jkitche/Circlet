-- Circlet: Dragging rings in edit mode, with the snap grid.
local ADDON_NAME, ns = ...

local db, RING_FRAMES = ns.db, ns.RING_FRAMES

-- In edit mode a ring can be dragged by itself; right-click puts it back.
-- Snap grid (edit mode). Grid points are measured out from the centre of the screen,
-- and it's the ring's centre that snaps. Holding Shift places a ring freely.
local function CursorPosition()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

local function SnapToGrid(cx, cy)
    if not db.snapGrid or IsShiftKeyDown() then return cx, cy end
    local g = math.max(2, db.gridSize or 20)
    local mx, my = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    return mx + math.floor((cx - mx) / g + 0.5) * g, my + math.floor((cy - my) / g + 0.5) * g
end

-- Where the ring being dragged should sit now (UIParent coordinates of its centre).
local function DragCenter(frame)
    local x, y = CursorPosition()
    return SnapToGrid(x + frame.grabX, y + frame.grabY)
end

local dragging -- the ring being dragged, if any
local dragDriver = CreateFrame("Frame")
dragDriver:Hide()
dragDriver:SetScript("OnUpdate", function()
    if not dragging then dragDriver:Hide() return end
    local cx, cy = DragCenter(dragging)
    dragging:ClearAllPoints()
    dragging:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
end)

local function MakeRingDraggable(frame, key)
    RING_FRAMES[key] = frame
    frame.sqKey = key -- for its per-ring border setting
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false) -- only while editing; otherwise clicks go straight through
    frame:RegisterForDrag("LeftButton")
    -- Dragged by hand rather than with StartMoving, so the ring can snap to the grid as
    -- it moves. Grab offset: where on the ring you picked it up.
    -- frame.isLocked (optional function): when it returns true the ring can't be moved.
    frame:SetScript("OnDragStart", function(self)
        if self.isLocked and self.isLocked() then return end
        local x, y = CursorPosition()
        local cx, cy = self:GetCenter()
        if not cx then return end
        self.grabX, self.grabY = cx - x, cy - y
        self.dragging = true
        dragging = self
        dragDriver:Show()
    end)
    frame:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = false
        dragging = nil
        dragDriver:Hide()
        local cx, cy = DragCenter(self)
        -- Back into this addon's own coordinates: offset from centre, gap from the top.
        ns.SetPosition(key, cx - UIParent:GetWidth() / 2, UIParent:GetHeight() - cy - db[key .. "Size"] / 2)
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if self.isLocked and self.isLocked() then return end
        if button == "RightButton" then ns.ResetPosition(key) end -- both set in EditMode.lua
    end)

    frame.editHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.editHint:SetText("Drag to move  ·  Shift: no snap  ·  Right-click to reset")
    frame.editHint:Hide()
end

local EDIT_STRATA = "TOOLTIP" -- above the options window (and its color picker) while editing

-- Shared with the files loaded after this one.
ns.MakeRingDraggable = MakeRingDraggable
ns.EDIT_STRATA = EDIT_STRATA
