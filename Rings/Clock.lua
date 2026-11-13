-- Circlet: Clock ring: the time, always on screen.
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall = ns.db, ns.CreateLiveRing, ns.SafeCall

---------------------------------------------------------------------------
-- Clock ring
---------------------------------------------------------------------------
-- A clock face: the ring fills as the hour goes by (a minute hand sweeping round), a dot
-- rides the ring at the hour (the hour hand), and ticks mark the hours outside it, longer
-- at 12, 3, 6 and 9. The middle shows the time, with the day above and the date below.
-- Unlike the other rings it stays on screen (it's off until you turn it on). Your computer's
-- time or the realm's (clockRealm), in 12 or 24 hours (clock24).
--
-- The hour dot and ticks are placed along the ring's own geometry, so they follow its shape
-- and rotation like the fill does. Its rotation defaults to 0, putting 12 at the top (the
-- other rings default to 180, filling from the bottom).

local TICKS = 12

-- The time to show: hour (0-23), minute, second (fractional seconds aren't needed).
local function Now()
    local t = date("*t")
    if db.clockRealm and GetGameTime then
        local h, m = SafeCall(GetGameTime)
        if type(h) == "number" and type(m) == "number" then
            if m ~= t.min then t.sec = 0 end -- realm and computer minutes differ: no seconds to borrow
            t.hour, t.min = h, m
        end
    end
    return t
end

local function State(t)
    local c = db.clockColors
    local h, m, s = t.hour, t.min, t.sec or 0
    local value, ampm
    if db.clock24 then
        value = string.format("%d:%02d", h, m)
    else
        local h12 = h % 12
        if h12 == 0 then h12 = 12 end
        value, ampm = string.format("%d:%02d", h12, m), (h < 12) and "AM" or "PM"
    end
    local when = date("%b %d"):gsub(" 0", " ")
    return {
        clock = true,
        title = date("%A"),
        value = value,
        label = (ampm and (ampm .. " · ") or "") .. when .. (db.clockRealm and " · Realm" or ""),
        frac = (m + s / 60) / 60,
        hourFrac = ((h % 12) + (m + s / 60) / 60) / 12,
        color = c.fill, labelColor = { r = 0.8, g = 0.8, b = 0.8 },
        hold = 1,
    }
end

local clockRing = CreateLiveRing({
    key = "clock",
    watchEvery = 1,
    read = function() return State(Now()) end,
    sample = function() return State(Now()) end,
    decorate = function(st, frame, geom) ns.DrawClockFace(st, frame, geom) end,
})

---------------------------------------------------------------------------
-- The face: hour ticks and the hour dot
---------------------------------------------------------------------------
local CIRCLE_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"

local face -- made on first use

local function Build(frame)
    face = { ticks = {} }
    for i = 1, TICKS do
        local l = frame:CreateLine(nil, "OVERLAY", nil, 1)
        if l.SetSnapToPixelGrid then l:SetSnapToPixelGrid(false); l:SetTexelSnappingBias(0) end
        l:Hide()
        face.ticks[i] = l
    end
    face.glow = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    if face.glow:SetTexture(GLOW_TEX) == false then face.glow:SetTexture(CIRCLE_TEX) end
    face.glow:SetBlendMode("ADD")
    face.rim = frame:CreateTexture(nil, "OVERLAY", nil, 3) -- a dark edge around the dot
    face.rim:SetTexture(CIRCLE_TEX)
    face.rim:SetVertexColor(0, 0, 0)
    face.dot = frame:CreateTexture(nil, "OVERLAY", nil, 4)
    face.dot:SetTexture(CIRCLE_TEX)
    for _, t in ipairs({ face.glow, face.rim, face.dot }) do t:Hide() end
end

local function HideFace()
    if not face then return end
    for _, l in ipairs(face.ticks) do l:Hide() end
    face.glow:Hide(); face.rim:Hide(); face.dot:Hide()
end

local function DrawClockFace(st, frame, geom)
    if not (st and st.clock) or not geom or geom.R <= 0 then return HideFace() end
    if not face then Build(frame) end
    local R, T = geom.R, geom.T
    local ro = R + T / 2 + (db.clockBorder or 0)

    -- Hour ticks, just outside the ring: longer and brighter at 12, 3, 6 and 9.
    local tc = db.clockColors.ticks
    for i, l in ipairs(face.ticks) do
        if db.clockTicks then
            local x, y = ns.RingPoint(geom, (i - 1) / TICKS)
            local ox, oy = x / R, y / R
            local major = (i - 1) % 3 == 0
            local len = math.max(2, T * (major and 0.8 or 0.45))
            local d0 = ro + math.max(1.5, T * 0.2)
            l:SetThickness(math.max(1, T * (major and 0.22 or 0.14)))
            l:SetStartPoint("CENTER", frame, ox * d0, oy * d0)
            l:SetEndPoint("CENTER", frame, ox * (d0 + len), oy * (d0 + len))
            l:SetColorTexture(tc.r, tc.g, tc.b, major and 0.95 or 0.6)
            l:Show()
        else
            l:Hide()
        end
    end

    -- The hour dot, riding the ring.
    local hc = db.clockColors.hour
    local x, y = ns.RingPoint(geom, st.hourFrac or 0)
    local size = math.max(6, T * 1.5)
    face.rim:ClearAllPoints(); face.rim:SetPoint("CENTER", frame, "CENTER", x, y)
    face.rim:SetSize(size + 3, size + 3)
    face.dot:ClearAllPoints(); face.dot:SetPoint("CENTER", frame, "CENTER", x, y)
    face.dot:SetSize(size, size)
    face.dot:SetVertexColor(hc.r, hc.g, hc.b)
    face.glow:ClearAllPoints(); face.glow:SetPoint("CENTER", frame, "CENTER", x, y)
    face.glow:SetSize(size * 2.6, size * 2.6)
    face.glow:SetVertexColor(hc.r, hc.g, hc.b)
    face.glow:SetAlpha(0.6)
    face.rim:Show(); face.dot:Show(); face.glow:Show()
end
ns.DrawClockFace = DrawClockFace

-- Shared with the files loaded after this one.
ns.clockRing = clockRing
ns.PreviewClockRing = function() clockRing.Preview(8) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "clock", name = "Clock", order = 11.7,
    ring = clockRing,
    preview = ns.PreviewClockRing, slash = { "clock" }, help = "preview the clock ring",
    toggle = { "Clock ring", "A clock, always on screen: the time, the day and the date." },
    defaults = {
        -- Clock ring: always on screen once it's on. Top right, past the ammo ring.
        clockEnabled   = false, -- a ring that never goes away: off until you want it
        clock24        = false, -- 24-hour time
        clockRealm     = false, -- the realm's time instead of your computer's
        clockTicks     = true,  -- hour ticks around the ring
        clockSize      = 100,
        clockThickness = 8,
        clockOpacity   = 100,
        clockX         = 680,
        clockFromTop   = 55,
        clockHold      = 1,
        clockStyle     = "smooth",
        clockRotation  = 0,     -- 12 at the top (other rings default to 180: filling from the bottom)
        clockBorder    = 2,
        clockColors = {
            fill  = { r = 0.55, g = 0.75, b = 1.00 },
            hour  = { r = 1.00, g = 0.85, b = 0.35 },
            ticks = { r = 0.90, g = 0.90, b = 0.95 },
        },
    },
    page = { folder = "status", order = 4.7, build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(10.8, "Clock", "Clock Ring",
                "A clock that stays on screen: the ring fills as the hour goes by, a dot marks the hour, and the "
                .. "middle shows the time with the day and date. Off until you turn it on.",
                MergeTop(TopRow("clock", "clock ring", ns.PreviewClockRing, "Show the clock for a few seconds. Also /circ clock."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "clockEnabled", "Show clock ring", "Keep a clock on screen."),
                        h24 = Toggle(2, "clock24", "24-hour time", "18:30 instead of 6:30 PM."),
                        realm = Toggle(3, "clockRealm", "Realm time",
                            "The realm's time instead of your computer's. \"Realm\" shows under the time."),
                        ticks = Toggle(4, "clockTicks", "Hour ticks", "Ticks around the outside of the ring at every hour."),
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "clockColors", "fill", "Minutes", "The ring: how far through the hour."),
                        hour = Color(2, "clockColors", "hour", "Hour", "The dot marking the hour."),
                        ticks = Color(3, "clockColors", "ticks", "Ticks", "The hour ticks around the ring."),
                    }),
                    size = SizeBox(4, "clock", "clock ring", "Offset from the center of the screen. By default it sits top right."),
                }))
            if tab.args.size and tab.args.size.args.hold then tab.args.size.args.hold = nil end -- it never goes away
            return tab
        end },
})
