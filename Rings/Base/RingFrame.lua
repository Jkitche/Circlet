-- Circlet: The parts every ring frame shares: creating it, placing it, sizing its geometry.
local ADDON_NAME, ns = ...

local db, RingHolder, MakeRingDraggable, ApplyOpacity = ns.db, ns.RingHolder, ns.MakeRingDraggable, ns.ApplyOpacity
local ArrangeX, RingThickness, NewRingLayer, TRACK, XP_SEGMENTS = ns.ArrangeX, ns.RingThickness, ns.NewRingLayer, ns.TRACK, ns.XP_SEGMENTS

---------------------------------------------------------------------------
-- Ring frames
---------------------------------------------------------------------------
-- Every ring (the XP and flight rings, and everything built by CreateProgressRing and
-- CreateLiveRing) is a frame in its holder (Layout/Holders.lua) with a track layer
-- (frame.bg) and a geometry table (frame.geom: R, T, style, shape...), placed by its
-- <key>X / <key>FromTop / <key>Size settings and draggable in edit mode.

-- A new, hidden ring frame for settings key `key`, with its track layer.
local function NewRingFrame(key, trackLines)
    local frame = CreateFrame("Frame", nil, RingHolder(key))
    frame:SetFrameStrata(ns.RING_STRATA) -- under the game's windows
    frame:SetSize(1, 1)
    frame:SetAlpha(0)
    frame:Hide()
    frame.geom = { R = 0, T = 0, step = 2 * math.pi / XP_SEGMENTS }
    frame.bg = NewRingLayer("BACKGROUND", 0, TRACK, 1, frame, trackLines)
    MakeRingDraggable(frame, key)
    return frame
end

-- Applies the ring's opacity and puts it at its saved spot (unless it's being dragged),
-- `size` across (default its Size setting). Runs every frame while the ring is up, so
-- position and opacity changes show straight away.
local function PlaceRing(frame, key, size)
    size = size or db[key .. "Size"]
    ApplyOpacity(key)
    frame:SetSize(size, size) -- also the hit area for dragging in edit mode
    if not frame.dragging then
        frame:ClearAllPoints()
        -- Anchored to the top edge so it stays put across UI scales and resolutions.
        frame:SetPoint("CENTER", UIParent, "TOP", db[key .. "X"] + ArrangeX(key, frame),
            -(db[key .. "FromTop"] + size / 2))
    end
    frame.editHint:ClearAllPoints()
    frame.editHint:SetPoint("TOP", frame, "CENTER", 0, -(size / 2 + 4))
end

---------------------------------------------------------------- text sizes
-- Every text on a ring can be sized: each ring's texts are registered as roles ({ id, name,
-- desc }; ns.RegisterTextRoles), and <key><id>Size is that text's size as a % of its usual
-- one (default 100; the usual size follows the ring's). A ring's options page gets a slider
-- per role (UI/Options/Kit.lua RingTab), and the sizes are part of its layout key, so a change
-- shows at once. Grouped rings (totem1, pin2...) share their group's roles and sizes.
local TEXT_ROLES = {}
local function GroupOf(key) return key:match("^(%l+)%d+$") or key end

local function RegisterTextRoles(key, roles) TEXT_ROLES[GroupOf(key)] = roles end

local function TextScale(key, id)
    local v = tonumber(db[key .. id .. "Size"])
    return (v and v > 0 and v or 100) / 100
end

-- A text's font size: base px (its usual size for this ring), at least min, both scaled
-- (at 100% exactly the sizes the rings always had).
local function FontSize(key, id, base, min)
    local s = TextScale(key, id)
    return math.max(5, math.floor((min or 0) * s), math.floor(base * s))
end

local function TextSizesKey(key)
    local roles = TEXT_ROLES[GroupOf(key)]
    if not roles then return "" end
    local t = {}
    for i, r in ipairs(roles) do t[i] = tostring(db[key .. r.id .. "Size"] or "") end
    return table.concat(t, ",")
end

-- Recomputes the ring's geometry and redraws its track and border, but only when a
-- setting that affects them changed (size, thickness, style, border, shape, or `extra`,
-- anything else the caller's layout depends on). Returns nil when nothing changed, else
-- the room inside the ring for text (its diameter less the band, at the normal style's
-- width, so switching style doesn't resize the text).
-- thicknessSize: size to work out the band width from (default `size`).
local function UpdateGeometry(frame, key, size, extra, thicknessSize)
    local layoutKey = size .. ":" .. db[key .. "Thickness"] .. ":" .. tostring(db[key .. "Style"])
        .. ":" .. ns.BorderKey(key) .. ":" .. tostring(extra) .. ":" .. TextSizesKey(key)
    if frame.layoutKey == layoutKey then return nil end
    frame.layoutKey = layoutKey
    local geom, textT = frame.geom, nil
    geom.T, textT = RingThickness(key, thicknessSize or size)
    geom.R = size / 2 - geom.T / 2
    geom.style = db[key .. "Style"]
    ns.ApplyShape(geom, key)
    ns.DrawTrack(frame, frame.bg, geom)
    return size - 2 * textT
end

-- A text line on a ring, with the usual drop shadow.
local function RingText(frame, layer)
    local fs = frame:CreateFontString(nil, layer or "OVERLAY")
    fs:SetShadowOffset(1, -1)
    return fs
end

-- Shared with the files loaded after this one.
ns.NewRingFrame = NewRingFrame
ns.PlaceRing = PlaceRing
ns.UpdateGeometry = UpdateGeometry
ns.RegisterTextRoles = RegisterTextRoles
ns.TextRoles = function(key) return TEXT_ROLES[GroupOf(key)] end
ns.TextScale = TextScale
ns.FontSize = FontSize
ns.RingText = RingText
