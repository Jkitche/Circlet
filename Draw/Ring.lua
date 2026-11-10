-- Circlet: Drawing rings: segments, arcs, tracks, borders, styles, shapes and gradients.
local ADDON_NAME, ns = ...

local db = ns.db

-- Ring styles. smooth: a solid band. segmented: 24 notches with small gaps (like the
-- old XP bar's bubbles). thin: a slim band around the edge, so the text has more room.
local RING_STYLE_NAMES = { smooth = "Smooth", segmented = "Segmented", thin = "Thin" }
local RING_STYLE_ORDER = { "smooth", "segmented", "thin" }

-- Band width for a ring's style, plus the width used to size its text (the normal
-- one, so switching style doesn't resize the text).
local function RingThickness(key, size)
    local t = math.min(db[key .. "Thickness"], size / 2 - 2)
    if db[key .. "Style"] == "thin" then
        return math.max(2, math.floor(t * 0.4 + 0.5)), t
    end
    return t, t
end

-- Every ring is drawn with 72 straight segments per layer (fill, track, border...).
local XP_SEGMENTS = 72

-- The empty part of a ring.
local TRACK = { r = 0.07, g = 0.07, b = 0.09 }

-- One layer of a ring: XP_SEGMENTS line segments on parent, all one color.
-- count: how many segments (default XP_SEGMENTS); rings that draw a custom number of
-- notches (the crafting ring, one per item) need more.
local function NewRingLayer(drawLayer, subLevel, c, a, parent, count)
    local lines = {}
    for i = 1, count or XP_SEGMENTS do
        local line = parent:CreateLine(nil, drawLayer, nil, subLevel)
        if line.SetSnapToPixelGrid then
            line:SetSnapToPixelGrid(false)
            line:SetTexelSnappingBias(0)
        end
        line:SetColorTexture(c.r, c.g, c.b, a)
        lines[i] = line
    end
    return lines
end

-- frac 0 = the start of the ring (12 o'clock for a full ring), increasing clockwise.
-- geom.start / geom.sweep (fractions of a full circle) turn the ring into an arc.
-- geom.reverse: fill counter-clockwise instead, from the arc's other end.
local function RingPoint(geom, frac)
    local sweep = geom.sweep or 1
    local pos = geom.reverse and ((geom.start or 0) + sweep - frac * sweep) or ((geom.start or 0) + frac * sweep)
    local a = math.pi / 2 - 2 * math.pi * pos
    return geom.R * math.cos(a), geom.R * math.sin(a)
end

-- Draws the arc [from, to] (fractions of a full circle) using one layer's segments.
-- frame/geom: the ring frame the lines are anchored to and its { R, T, step, style,
-- notches }. notches (segmented style only): how many notches; default 24. Each notch
-- gets enough segments to look round, so the layer needs that many lines (extra lines
-- are hidden; a layer with too few draws as many notches as it can).
-- noOverlap: for translucent layers. Segments normally overlap a little at each joint
-- to hide notches, but on a see-through ring the overlaps show up as brighter stripes.
-- shade: optional { r, g, b, amt } (see Shade): colors each segment along a gradient,
-- amt darker at the ring's start and the full color at its end.
local NOTCH_LINES = 3 -- segmented style: each notch is 3 of the 72 segments (24 notches)

local function DrawArc(lines, from, to, frame, geom, noOverlap, shade)
    local N = XP_SEGMENTS
    local notches = geom.style == "segmented" and (geom.notches or N / NOTCH_LINES) or nil
    if notches and notches < 2 then notches = nil end -- one notch: just a smooth ring
    local notched = notches ~= nil
    local sweep = geom.sweep or 1
    local full = from <= 0 and to >= 1 and not notched and sweep >= 1
    local per = notched and math.max(1, math.ceil(N / notches)) or 1 -- segments per notch
    local total = notched and math.min(#lines, notches * per) or N
    -- Gap between notches, as a fraction of the circle (never more than a third of a notch).
    -- geom.gapPx overrides the width (the border uses a narrower gap than its band).
    local gap = 0
    if notched then
        gap = (geom.gapPx or math.max(1.5, geom.T * 0.3)) / (2 * math.pi * math.max(geom.R, 1) * sweep)
        gap = math.min(gap, 0.33 / notches)
    end
    for i = 1, total do
        local line = lines[i]
        local s0, e0, lo, hi = (i - 1) / N, i / N, from, to
        if notched then
            local n, k = math.floor((i - 1) / per), (i - 1) % per
            local ns, ne = n / notches, (n + 1) / notches
            s0, e0 = ns + (ne - ns) * k / per, ns + (ne - ns) * (k + 1) / per
            lo = math.max(from, ns + gap / 2)
            hi = math.min(to, ne - gap / 2)
        end
        -- Overlap at joints (fills the notch a bend would leave), sized to this segment.
        local miter = noOverlap and 0 or (geom.T / 2) * math.tan(math.pi * (e0 - s0) * sweep)
        local s = math.max(s0, lo)
        local e = math.min(e0, hi)
        if e - s > 1e-4 then
            local x1, y1 = RingPoint(geom, s)
            local x2, y2 = RingPoint(geom, e)
            local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
            if len > 0 then
                local ux, uy = (x2 - x1) / len * miter, (y2 - y1) / len * miter
                -- Extend into neighbouring segments, but not past the arc's (or notch's) ends.
                if full or s > lo + 1e-6 then x1, y1 = x1 - ux, y1 - uy end
                if full or e < hi - 1e-6 then x2, y2 = x2 + ux, y2 + uy end
            end
            line:SetStartPoint("CENTER", frame, x1, y1)
            line:SetEndPoint("CENTER", frame, x2, y2)
            line:SetThickness(geom.T)
            if shade then
                local f = 1 - shade.amt * (1 - (s + e) / 2)
                line:SetColorTexture(shade.r * f, shade.g * f, shade.b * f, 1)
            end
            line:Show()
        else
            line:Hide()
        end
    end
    for i = total + 1, #lines do lines[i]:Hide() end
end

-- A ring's gradient for color c, as DrawArc's shade; nil for a solid fill.
-- <key>Fill: "solid" or "gradient"; <key>Gradient (0-100): how much darker the start is.
local shades = {}
local function Shade(key, c)
    if not key or db[key .. "Fill"] ~= "gradient" then return nil end
    local amt = tonumber(db[key .. "Gradient"]) or 0
    if amt <= 0 or not c then return nil end
    local t = shades[key] or {}
    shades[key] = t
    t.r, t.g, t.b, t.amt = c.r, c.g, c.b, math.min(100, amt) / 100
    return t
end

-- Ring border: a black band a little wider than the ring, behind its track. With the
-- segmented style its gaps are narrower by the border on each side, so every notch
-- gets its own outline.
local BORDER_COLOR = { r = 0, g = 0, b = 0, a = 0.9 }

-- Each ring's own border width (<key>Border; 0 = none).
local function BorderWidth(key)
    return key and tonumber(db[key .. "Border"]) or 0
end

-- Ring shapes: a full ring, or an arc open at the bottom. start: where the arc begins,
-- clockwise from 12 o'clock; sweep: how much of the circle it covers (both fractions).
local RING_SHAPES = {
    ring = { start = 0, sweep = 1 },
    arc  = { start = 0.625, sweep = 0.75 }, -- 7:30 round the top to 4:30
    half = { start = 0.75, sweep = 0.5 },   -- 9 o'clock over the top to 3 o'clock
}
local RING_SHAPE_NAMES = { ring = "Ring", arc = "Arc (three quarters)", half = "Half arc" }
local RING_SHAPE_ORDER = { "ring", "arc", "half" }

-- Sets a ring's geometry to its shape (<key>Shape), rotation (<key>Rotation, degrees
-- clockwise from the shape's base position; the default is 180) and fill direction
-- (<key>Reverse: counter-clockwise).
local function ApplyShape(geom, key)
    local shape = RING_SHAPES[key and db[key .. "Shape"]] or RING_SHAPES.ring
    local rot = key and tonumber(db[key .. "Rotation"]) or 0
    geom.start, geom.sweep = shape.start + rot / 360, shape.sweep
    geom.reverse = key and db[key .. "Reverse"] and true or nil
end

-- Part of each ring's layout key: changes when its border or shape does.
local function BorderKey(key)
    return "b" .. BorderWidth(key) .. ":" .. tostring(key and db[key .. "Shape"])
        .. ":" .. tostring(key and db[key .. "Rotation"]) .. ":" .. tostring(key and db[key .. "Reverse"])
end

-- Draws a ring's track (the full background circle) and its border, if it has one.
-- Call wherever the track is drawn: bg is the track layer, geom the ring's geometry.
-- width: border width; defaults to the ring's own setting (frame.sqKey).
local function DrawTrack(frame, bg, geom, width)
    local border = frame.sqBorder
    local b = width or BorderWidth(frame.sqKey)
    if b > 0 then
        if not border then
            border = {}
            for i = 1, #bg do
                local line = frame:CreateLine(nil, "BACKGROUND", nil, -8)
                if line.SetSnapToPixelGrid then
                    line:SetSnapToPixelGrid(false)
                    line:SetTexelSnappingBias(0)
                end
                line:SetColorTexture(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, BORDER_COLOR.a)
                border[i] = line
            end
            frame.sqBorder = border
        end
        local outer = { R = geom.R, T = geom.T + 2 * b, step = geom.step, style = geom.style, notches = geom.notches,
                        start = geom.start, sweep = geom.sweep, reverse = geom.reverse }
        if geom.style ~= "segmented" and (geom.sweep or 1) < 1 then
            -- An arc's border runs a little past each end, so the ends are outlined too.
            local e = b / (2 * math.pi * math.max(geom.R, 1))
            outer.start, outer.sweep = (geom.start or 0) - e, geom.sweep + 2 * e
        end
        if geom.style == "segmented" then
            local notches = geom.notches or XP_SEGMENTS / NOTCH_LINES
            local circ = 2 * math.pi * math.max(geom.R, 1)
            local bandGap = math.min(math.max(1.5, geom.T * 0.3), 0.33 / math.max(notches, 1) * circ * (geom.sweep or 1))
            outer.gapPx = math.max(0, bandGap - 2 * b)
        end
        DrawArc(border, 0, 1, frame, outer)
    elseif border then
        for _, line in ipairs(border) do line:Hide() end
    end
    DrawArc(bg, 0, 1, frame, geom)
end

-- Shared with the files loaded after this one.
ns.XP_SEGMENTS = XP_SEGMENTS
ns.TRACK = TRACK
ns.RING_STYLE_NAMES = RING_STYLE_NAMES
ns.RING_STYLE_ORDER = RING_STYLE_ORDER
ns.RingThickness = RingThickness
ns.NewRingLayer = NewRingLayer
ns.DrawArc = DrawArc
ns.DrawTrack = DrawTrack
ns.Shade = Shade
ns.BorderWidthOf = BorderWidth
ns.BorderKey = BorderKey
ns.ApplyShape = ApplyShape
ns.RING_SHAPE_NAMES = RING_SHAPE_NAMES
ns.RING_SHAPE_ORDER = RING_SHAPE_ORDER
