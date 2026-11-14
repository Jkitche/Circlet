-- Circlet: "Discovered" animation when you explore a new area.
local ADDON_NAME, ns = ...

local db, IsSecret, NewRingLayer, DrawArc, XP_SEGMENTS = ns.db, ns.IsSecret, ns.NewRingLayer, ns.DrawArc, ns.XP_SEGMENTS

---------------------------------------------------------------------------
-- Discovery animation
---------------------------------------------------------------------------
-- When you discover a new area the game says so in chat ("Discovered Thelsamar: 120
-- experience gained", or "Discovered: Thelsamar"). This plays a compass-ring flourish
-- under the zone text: a gold ring sweeps closed down both sides at once, from 12 o'clock
-- to 6, with compass ticks and a ring of sparks bursting as the two halves meet; the area
-- name scales in, a pair of glints bounces up and down both sides of the ring, then it all widens
-- and fades. Everything mirrors left to right. Turned on and off on the General tab
-- (db.discoverFx).

local SIZE = 200
local GOLD = { r = 1.0, g = 0.82, b = 0.25 }
local TIMES = { sweep = 0.7, nameIn = 0.35, nameDur = 0.5, hold = 3.0, out = 1.0 }
local TOTAL = TIMES.hold + TIMES.out

local fx = CreateFrame("Frame", nil, UIParent)
fx:SetFrameStrata("HIGH")
fx:SetSize(SIZE, SIZE)
fx:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
fx:Hide()

local geom = { R = SIZE / 2 - 6, T = 5, step = 2 * math.pi / XP_SEGMENTS }
local glintGeom = { R = geom.R, T = 9, step = geom.step }
fx.track = NewRingLayer("BACKGROUND", 0, { r = 0, g = 0, b = 0 }, 0.45, fx)
-- Each mirrored part has a right-hand layer and a left-hand one.
fx.ring = NewRingLayer("ARTWORK", 0, GOLD, 1, fx)
fx.ring2 = NewRingLayer("ARTWORK", 0, GOLD, 1, fx)
fx.glint = NewRingLayer("ARTWORK", 1, { r = 1, g = 1, b = 0.9 }, 1, fx)
fx.glint2 = NewRingLayer("ARTWORK", 1, { r = 1, g = 1, b = 0.9 }, 1, fx)

-- Compass ticks at north / east / south / west, just outside the ring.
fx.ticks = {}
for i = 1, 4 do
    local line = fx:CreateLine(nil, "ARTWORK", nil, 2)
    line:SetThickness(3)
    line:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 1)
    fx.ticks[i] = line
end

-- Sparks that burst outward as the ring closes.
local SPARKS = 12
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
fx.sparks = {}
for i = 1, SPARKS do
    local s = fx:CreateTexture(nil, "OVERLAY")
    s:SetTexture(CIRCLE)
    s:SetVertexColor(1, 0.9, 0.55)
    s:SetBlendMode("ADD")
    fx.sparks[i] = s
end

local function Text(size, r, g, b)
    local fs = fx:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    fs:SetTextColor(r, g, b)
    fs:SetShadowOffset(1, -1)
    return fs
end
fx.label = Text(13, GOLD.r, GOLD.g, GOLD.b)
fx.label:SetPoint("BOTTOM", fx, "CENTER", 0, 22) -- the same gap as the XP line below
fx.label:SetText("DISCOVERED")
fx.name = Text(24, 1, 1, 1)
fx.name:SetPoint("CENTER", fx, "CENTER", 0, 0)
fx.name:SetWidth(SIZE - 30)
fx.name:SetWordWrap(true)
fx.xp = Text(14, 0.72, 0.6, 1)
fx.xp:SetPoint("TOP", fx, "CENTER", 0, -22)

local current, startedAt, queue = nil, 0, {}

local function Ease(t) return 1 - (1 - math.max(0, math.min(1, t))) ^ 3 end

local function SetRingColor(layer, c, a)
    for _, l in ipairs(layer) do l:SetColorTexture(c.r, c.g, c.b, a) end
end

local function DrawFrame(t)
    -- Sweep: the ring closes down both sides at once, from 12 o'clock to 6. `sweep` is
    -- how much of the ring is drawn (each side gets half).
    local sweep = Ease(t / TIMES.sweep)
    -- Out: everything widens and fades.
    local out = t > TIMES.hold and Ease((t - TIMES.hold) / TIMES.out) or 0
    local scale = 1 + 0.35 * out
    local alpha = 1 - out
    geom.R = (SIZE / 2 - 6) * scale
    glintGeom.R = geom.R

    SetRingColor(fx.track, { r = 0, g = 0, b = 0 }, 0.45 * alpha)
    DrawArc(fx.track, 0, 1, fx, geom, true)
    SetRingColor(fx.ring, GOLD, alpha)
    SetRingColor(fx.ring2, GOLD, alpha)
    local half = sweep / 2
    DrawArc(fx.ring, 0, half, fx, geom)       -- right side, top down
    DrawArc(fx.ring2, 1 - half, 1, fx, geom)  -- left side, top down

    -- Glints: a pair of bright arcs bouncing up and down both sides of the ring together
    -- once it's closed: down to the bottom, where they meet, back up to the top, where they
    -- meet again, easing to a stop at each end before turning.
    if t > TIMES.sweep and alpha > 0 then
        local BOUNCE = 2.4 -- seconds for one trip down and back up
        local u = (t - TIMES.sweep) / BOUNCE
        local p = 0.25 * (1 - math.cos(2 * math.pi * u)) -- the glint's middle: 0 (top) .. 0.5 (bottom) .. 0
        local len = 0.06
        local a = alpha * (0.5 + 0.5 * math.sin(math.min(1, (t - TIMES.sweep) / 0.4) * math.pi / 2))
        local glintColor = { r = 1, g = 1, b = 0.9 }
        SetRingColor(fx.glint, glintColor, a)
        SetRingColor(fx.glint2, glintColor, a)
        -- Each stays on its own side: at the top and bottom the two halves join into one.
        DrawArc(fx.glint, math.max(0, p - len / 2), math.min(0.5, p + len / 2), fx, glintGeom, true)
        DrawArc(fx.glint2, math.max(0.5, 1 - p - len / 2), math.min(1, 1 - p + len / 2), fx, glintGeom, true)
    else
        for _, l in ipairs(fx.glint) do l:Hide() end
        for _, l in ipairs(fx.glint2) do l:Hide() end
    end

    -- Ticks grow out as the sweep passes them: north first, east and west together,
    -- south last as the two halves meet.
    for i, line in ipairs(fx.ticks) do
        local at = (i - 1) / 4
        local reach = math.min(at, 1 - at) * 2 -- how much of the sweep reaches this tick
        local grow = Ease((sweep - reach * 0.85) / 0.15) * alpha -- (0.85: south still grows in full)
        local ang = at * 2 * math.pi
        local r1, r2 = geom.R + 6, geom.R + 6 + 12 * grow
        local sx, sy = math.sin(ang), math.cos(ang)
        line:SetStartPoint("CENTER", fx, sx * r1, sy * r1)
        line:SetEndPoint("CENTER", fx, sx * r2, sy * r2)
        line:SetAlpha(grow > 0.01 and alpha or 0)
    end

    -- Sparks: burst outward all round the ring just as it closes, evenly spaced with one
    -- straight up and one straight down, so the burst mirrors left to right.
    local sp = (t - TIMES.sweep * 0.8) / 0.9
    for i, s in ipairs(fx.sparks) do
        if sp > 0 and sp < 1 then
            local ang = ((i - 1) / SPARKS) * 2 * math.pi
            local dist = geom.R + 8 + 60 * Ease(sp)
            s:ClearAllPoints()
            s:SetPoint("CENTER", fx, "CENTER", math.sin(ang) * dist, math.cos(ang) * dist)
            local size = 7 * (1 - sp) + 2
            s:SetSize(size, size)
            s:SetAlpha(1 - sp)
            s:Show()
        else
            s:Hide()
        end
    end

    -- Text: label first, then the name scales down into place.
    fx.label:SetAlpha(Ease(t / 0.4) * alpha)
    local n = Ease((t - TIMES.nameIn) / TIMES.nameDur)
    fx.name:SetAlpha(n * alpha)
    fx.name:SetScale(math.max(0.01, 1 + 0.4 * (1 - n)))
    fx.xp:SetAlpha(Ease((t - TIMES.nameIn - 0.3) / 0.4) * alpha)
end

local function Start(entry)
    current, startedAt = entry, GetTime()
    fx.name:SetText(entry.area)
    fx.xp:SetText(entry.xp and ("+" .. BreakUpLargeNumbers(entry.xp) .. " XP") or "")
    fx:Show()
    DrawFrame(0)
end

fx:SetScript("OnUpdate", function()
    local t = GetTime() - startedAt
    if t >= TOTAL then
        current = nil
        local nextEntry = table.remove(queue, 1)
        if nextEntry then Start(nextEntry) else fx:Hide() end
        return
    end
    DrawFrame(t)
end)

local function PlayDiscovery(area, xp, force)
    if not (force or db.discoverFx) or not area or area == "" then return end
    -- The XP line and the plain "Discovered" line can both arrive: merge them.
    if current and current.area == area then
        if xp and not current.xp then
            current.xp = xp
            fx.xp:SetText("+" .. BreakUpLargeNumbers(xp) .. " XP")
        end
        return
    end
    for _, q in ipairs(queue) do
        if q.area == area then
            q.xp = q.xp or xp
            return
        end
    end
    local entry = { area = area, xp = xp }
    if current then table.insert(queue, entry) else Start(entry) end
end

---------------------------------------------------------------------------
-- Spotting discoveries in the game's messages
---------------------------------------------------------------------------
-- Turns a format string like "Discovered %s: %d experience gained." into a pattern.
local function ToPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    fmt = fmt:gsub("%%%d%$", "%%") -- "%1$s" -> "%s"
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end

local PATTERNS = {}
for _, entry in ipairs({
    { ERR_ZONE_EXPLORED_XP, true }, { ERR_ZONE_EXPLORED, false },
    { "Discovered %s: %d experience gained", true }, { "Discovered %s: %d experience gained.", true },
    { "Discovered: %s", false }, { "Discovered %s", false },
}) do
    local p = ToPattern(entry[1])
    if p then table.insert(PATTERNS, { p, entry[2] }) end
end

local function Parse(msg)
    if type(msg) ~= "string" or IsSecret(msg) then return nil end
    for _, entry in ipairs(PATTERNS) do
        local area, xp = msg:match(entry[1])
        if area then
            area = area:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            return area, entry[2] and tonumber(xp) or nil
        end
    end
end

ns.Listen({ "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_SYSTEM", "UI_INFO_MESSAGE" }, function(event, a1, a2)
    if not CircletDB then return end
    local area, xp = Parse(event == "UI_INFO_MESSAGE" and a2 or a1)
    if area then PlayDiscovery(area, xp) end
end)

local function PreviewDiscovery()
    PlayDiscovery("Thelsamar", 120, true)
end

ns.RegisterCommand({ "discover", "discovered", "explore" }, PreviewDiscovery, "preview the discovered area animation")

-- Shared with the files loaded after this one.
ns.PreviewDiscovery = PreviewDiscovery
