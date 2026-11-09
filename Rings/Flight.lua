-- Circlet: Flight ring: a countdown to landing while you're on a flight path.
local ADDON_NAME, ns = ...

local db, Print, IsSecret = ns.db, ns.Print, ns.IsSecret
local NewRingLayer, DrawArc = ns.NewRingLayer, ns.DrawArc
local EDIT_STRATA = ns.EDIT_STRATA
local FormatTime = ns.FormatTime

---------------------------------------------------------------------------
-- Flight ring
---------------------------------------------------------------------------
-- The game doesn't say how long a flight takes, so the ring learns: the first time
-- you fly a route it counts up and times the trip ("Timing route"); after that it
-- counts down and fills toward landing. Times are kept per route (from -> to) in
-- db.flightTimes, shared by all your characters.
--
-- The route comes from hooking TakeTaxiNode (what the flight map calls when you
-- pick a destination); the flight itself is seen by polling UnitOnTaxi.

local MIN_FLIGHT = 5 -- shorter trips (cancelled right away) aren't saved as a route time

local flight = ns.NewRingFrame("flight")
local geom = flight.geom
flight.fill = NewRingLayer("ARTWORK", 0, { r = 1, g = 1, b = 1 }, 1, flight)
flight.fill2 = NewRingLayer("ARTWORK", 0, { r = 1, g = 1, b = 1 }, 1, flight) -- the spinner's wrap-around piece

flight.dest = ns.RingText(flight)  -- destination, small, above the time
flight.time = ns.RingText(flight)  -- 1:23, big
flight.label = ns.RingText(flight) -- "remaining" / "Timing route" / "Arrived"

-- What's being shown. Real flights fill `trip`; edit mode and previews use samples.
local trip = nil      -- { origin, dest, key, start, total (nil = unknown), landed }
local pendingRoute = nil -- { origin, dest } picked on the flight map, waiting for takeoff
local editing, previewUntil, sampleT = false, 0, 0
local holdUntil = 0

local function RouteKey(origin, dest)
    if not origin or not dest then return nil end
    return origin .. " -> " .. dest
end

-- Short place name: "Ironforge, Dun Morogh" -> "Ironforge".
local function ShortName(name)
    return name and (name:match("^([^,]+)") or name) or nil
end

-- Picking a destination on the flight map: remember the route until takeoff.
local function OnTakeTaxiNode(index)
    if not (NumTaxiNodes and TaxiNodeName and TaxiNodeGetType) then return end
    local origin
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) == "CURRENT" then origin = TaxiNodeName(i) break end
    end
    local dest = TaxiNodeName(index)
    if IsSecret(origin) or IsSecret(dest) then return end
    pendingRoute = { origin = origin, dest = dest, at = GetTime() }
end
if hooksecurefunc and TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", OnTakeTaxiNode)
end

---------------------------------------------------------------- drawing
local function Layout()
    local size = db.flightSize
    ns.PlaceRing(flight, "flight", size)
    local inner = ns.UpdateGeometry(flight, "flight", size)
    if not inner then return end
    flight.time:SetFont(STANDARD_TEXT_FONT, math.max(10, math.floor(inner * 0.27)), "OUTLINE")
    flight.dest:SetFont(STANDARD_TEXT_FONT, math.max(7, math.floor(inner * 0.13)), "OUTLINE")
    flight.label:SetFont(STANDARD_TEXT_FONT, math.max(7, math.floor(inner * 0.12)), "OUTLINE")
    flight.dest:SetWidth(inner * 0.92)
    flight.dest:SetWordWrap(false)
    flight.time:ClearAllPoints()
    flight.time:SetPoint("CENTER", flight, "CENTER", 0, -math.floor(inner * 0.02))
    flight.dest:ClearAllPoints()
    flight.dest:SetPoint("BOTTOM", flight.time, "TOP", 0, 2)
    flight.label:ClearAllPoints()
    flight.label:SetPoint("TOP", flight.time, "BOTTOM", 0, -2)
end

-- What to draw right now: dest, elapsed, total (nil = still learning), landed.
local function Current(now)
    if editing or now < previewUntil then
        -- Alternate a known route counting down and a new one being timed.
        local cycle = sampleT % 16
        if cycle < 10 then
            return "Ironforge", 30 + cycle * 9, 150, false
        end
        return "Southshore", (cycle - 10) * 7 + 12, nil, false
    end
    if not trip then return nil end
    local elapsed = (trip.landed or now) - trip.start
    return ShortName(trip.dest), elapsed, trip.total, trip.landed ~= nil
end

local function Draw(now)
    Layout()
    local dest, elapsed, total, landed = Current(now)
    if not elapsed then return end
    local c = db.flightColors
    for _, l in ipairs(flight.fill2) do l:Hide() end

    if landed then
        for _, l in ipairs(flight.fill) do l:SetColorTexture(c.fill.r, c.fill.g, c.fill.b, 1) end
        DrawArc(flight.fill, 0, 1, flight, geom, nil, ns.Shade("flight", c.fill))
        flight.time:SetText(FormatTime(elapsed))
        flight.time:SetTextColor(1, 1, 1)
        flight.label:SetText("Arrived")
        flight.label:SetTextColor(c.fill.r, c.fill.g, c.fill.b)
    elseif total then
        local frac = math.min(1, elapsed / math.max(1, total))
        for _, l in ipairs(flight.fill) do l:SetColorTexture(c.fill.r, c.fill.g, c.fill.b, 1) end
        DrawArc(flight.fill, 0, frac, flight, geom, nil, ns.Shade("flight", c.fill))
        local left = total - elapsed
        flight.time:SetText(left > 0 and FormatTime(left) or "0:00")
        flight.time:SetTextColor(1, 1, 1)
        flight.label:SetText(left > 0 and "remaining" or "landing")
        flight.label:SetTextColor(0.8, 0.8, 0.8)
    else
        -- Route not timed yet: a quarter arc circling, and the time so far.
        local spin = (elapsed * 0.35) % 1
        for _, l in ipairs(flight.fill) do l:SetColorTexture(c.learning.r, c.learning.g, c.learning.b, 1) end
        DrawArc(flight.fill, spin, math.min(1, spin + 0.25), flight, geom)
        if spin + 0.25 > 1 then
            -- Wraps past 12 o'clock: the rest goes on the second layer.
            for _, l in ipairs(flight.fill2) do l:SetColorTexture(c.learning.r, c.learning.g, c.learning.b, 1) end
            DrawArc(flight.fill2, 0, spin + 0.25 - 1, flight, geom)
        end
        flight.time:SetText(FormatTime(elapsed))
        flight.time:SetTextColor(1, 1, 1)
        flight.label:SetText("Timing route")
        flight.label:SetTextColor(c.learning.r, c.learning.g, c.learning.b)
    end
    flight.dest:SetText(dest and ("to " .. dest) or "Flying")
    flight.dest:SetTextColor(1, 0.82, 0)
end

---------------------------------------------------------------- flights
local function StartFlight(now)
    local route = pendingRoute
    pendingRoute = nil
    -- Only trust a route picked in the last minute (the map click that started this).
    if route and now - route.at > 60 then route = nil end
    local key = route and RouteKey(route.origin, route.dest)
    trip = {
        origin = route and route.origin,
        dest = route and route.dest,
        key = key,
        start = now,
        total = key and db.flightTimes[key] or nil,
    }
end

local function EndFlight(now)
    if not trip or trip.landed then return end
    trip.landed = now
    local duration = now - trip.start
    if ns.SessionAdd and duration >= MIN_FLIGHT then
        ns.SessionAdd("flights", nil, 1)
        ns.SessionAdd("flightTime", nil, duration)
    end
    if trip.key and duration >= MIN_FLIGHT then
        local known = db.flightTimes[trip.key]
        -- Keep the newest time, nudged by the old one so one odd trip doesn't throw it off.
        db.flightTimes[trip.key] = known and math.floor((known + duration * 3) / 4 + 0.5)
            or math.floor(duration + 0.5)
        if not known and db.flightLearnNotice then
            Print(string.format("Timed %s: %s. Next time the flight ring counts down.",
                trip.key, FormatTime(duration)))
        end
    end
    holdUntil = now + (db.flightHold or 3)
end

flight:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()
    if editing or now < previewUntil then sampleT = sampleT + elapsed end
    Draw(now)

    local a = self:GetAlpha()
    local onFlight = trip and not trip.landed
    if editing or now < previewUntil or onFlight or now < holdUntil then
        if a < 1 then self:SetAlpha(math.min(1, a + elapsed / 0.25)) end
    else
        a = a - elapsed / 0.5
        if a <= 0 then
            self:SetAlpha(0)
            self:Hide()
            if trip and trip.landed then trip = nil end
            return
        end
        self:SetAlpha(a)
    end
end)

-- Watches for takeoff and landing (the ring's own OnUpdate only runs while it's up).
local watcher = CreateFrame("Frame")
watcher.t = 0
watcher:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.t < 0.1 then return end
    self.t = 0
    if not (CircletDB and UnitOnTaxi) then return end
    local now = GetTime()
    local onTaxi = UnitOnTaxi("player")
    if onTaxi and not (trip and not trip.landed) then
        StartFlight(now)
        if db.flightEnabled then
            flight:Show()
            Draw(now)
        end
    elseif not onTaxi and trip and not trip.landed then
        EndFlight(now)
    end
end)

---------------------------------------------------------------- edit mode / preview
local function SetFlightEditing(on)
    editing = on and true or false
    flight.isEditing = editing
    flight:EnableMouse(editing)
    flight.editHint:SetShown(editing)
    flight:SetFrameStrata(editing and EDIT_STRATA or "HIGH")
    flight.layoutKey = nil
    if editing then
        sampleT = 0
        flight:Show()
    end
end

local function PreviewFlightRing()
    previewUntil = GetTime() + 16
    sampleT = 0
    flight:Show()
end

-- How many routes have been timed (for the options page).
local function KnownRouteCount()
    local n = 0
    for _ in pairs(db.flightTimes) do n = n + 1 end
    return n
end

local function ForgetFlightTimes()
    wipe(db.flightTimes)
    Print("Forgot all flight times; each route is timed again the next time you fly it.")
end

-- Shared with the files loaded after this one.
ns.SetFlightEditing = SetFlightEditing
ns.IsFlightEditing = function() return editing end
ns.PreviewFlightRing = PreviewFlightRing
ns.KnownRouteCount = KnownRouteCount
ns.ForgetFlightTimes = ForgetFlightTimes

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "flight", name = "Flight", order = 8,
    edit = { set = SetFlightEditing, get = ns.IsFlightEditing },
    preview = PreviewFlightRing, slash = { "flight", "taxi" }, help = "preview the flight ring",
    toggle = { "Flight ring", "Counts down to landing while you're on a flight path." },
    defaults = {
        -- Flight ring: a countdown to landing on flight paths.
        flightEnabled     = true,
        flightLearnNotice = true, -- chat line when a new route has been timed
        flightSize        = 120,
        flightThickness   = 12,
        flightOpacity     = 100,
        flightX           = 170,  -- right of the crafting ring
        flightFromTop     = 255,
        flightHold        = 3,    -- seconds it stays after landing
        flightStyle       = "smooth",
        flightBorder      = 2, -- black border width (0 = none)
        flightColors = {
            fill     = { r = 0.45, g = 0.75, b = 1.00 },
            learning = { r = 0.75, g = 0.75, b = 0.80 },
        },
        flightTimes = {},
    },
    page = { folder = "status", order = 1, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(8, "Flight", "Flight Ring",
                "Counts down to landing while you're on a flight path. The game doesn't give flight times, so the "
                .. "first trip on each route is timed (the ring circles and counts up); after that it counts down.",
                MergeTop(TopRow("flight", "flight ring", ns.PreviewFlightRing,
                    "Show the ring counting down a known route, then timing a new one. Also /sq flight."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "flightEnabled", "Show flight ring", "Show the ring while you're on a flight path."),
                        notice = Toggle(2, "flightLearnNotice", "Announce new route times",
                            "Print a chat line when a route has been timed for the first time."),
                        routes = {
                            type = "description", order = 3, fontSize = "medium", width = "full",
                            name = function()
                                local n = ns.KnownRouteCount()
                                return n == 1 and "1 route timed so far." or (n .. " routes timed so far.")
                            end,
                        },
                        forget = {
                            type = "execute", order = 4, width = 1.1, name = "Forget flight times",
                            desc = "Clear every learned route time, so each is timed again the next time you fly it.",
                            confirm = true, confirmText = "Forget all learned flight times?",
                            func = function() ns.ForgetFlightTimes() ns.RefreshOptions() end,
                        },
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "flightColors", "fill", "Countdown", "Ring color on a route with a known time."),
                        learning = Color(2, "flightColors", "learning", "Timing a route",
                            "Color of the circling arc while a new route is being timed."),
                    }),
                    size = SizeBox(4, "flight", "flight ring", "Offset from the center of the screen."),
                }))
            tab.args.size.args.hold.desc = "How long the ring stays after you land."
            return tab
        end },
})
