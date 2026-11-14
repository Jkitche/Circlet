-- Circlet: Flight ring: a countdown to landing while you're on a flight path.
local ADDON_NAME, ns = ...

local db, IsSecret = ns.db, ns.IsSecret
local NewRingLayer, DrawArc = ns.NewRingLayer, ns.DrawArc
local EDIT_STRATA = ns.EDIT_STRATA
local FormatTime = ns.FormatTime

---------------------------------------------------------------------------
-- Flight ring
---------------------------------------------------------------------------
-- Flight times come only from the game's own data: Data/FlightPaths.lua holds the
-- length of every direct flight path, mined from the client's TaxiNodes, TaxiPath and
-- TaxiPathNode tables by tools/flight-data. A trip's time is the length of every hop the
-- game will fly, added up, at the taxi's flying speed, plus any stops on the way.
-- Nothing is learned or estimated from your flights. A route the data doesn't cover
-- (a new flight master after a patch, say, until the data is regenerated) just counts
-- up the time in the air.
--
-- The route comes from hooking TakeTaxiNode (what the flight map calls when you pick a
-- destination), while the map's hops can still be read; the flight itself is seen by
-- polling UnitOnTaxi.

-- Taxi flying speed in yards per second, taking off and landing included. The game
-- files have path lengths but not the speed, so this was measured once in this client:
-- Orgrimmar -> Crossroads -> Sun Rock Retreat, 4252 + 4495 yards, took 260 seconds.
local SPEED = 33.6

---------------------------------------------------------------- times from the game's flight paths
-- Node IDs by English name: the backup for when the flight map can't say a node's ID.
local nodeByName
local function NodeIDByName(name)
    if not name then return nil end
    if not nodeByName then
        nodeByName = {}
        for id, n in pairs(ns.FLIGHT_NODES or {}) do nodeByName[n] = id end
    end
    return nodeByName[name]
end

-- The node ID of flight map slot `slot` (what TakeTaxiNode and TaxiNodeName take).
local function NodeIDForSlot(slot)
    if not slot or IsSecret(slot) then return nil end
    if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
        local nodes = ns.SafeCall(C_TaxiMap.GetAllTaxiNodes, GetTaxiMapID())
        if type(nodes) == "table" then
            for _, n in ipairs(nodes) do
                if n.slotIndex == slot and type(n.nodeID) == "number" and not IsSecret(n.nodeID) then return n.nodeID end
            end
        end
    end
    local name = TaxiNodeName and TaxiNodeName(slot)
    if IsSecret(name) then return nil end
    return NodeIDByName(name)
end

-- Seconds for one hop from node to node (with its stops), or nil if the data lacks it.
local function HopSeconds(from, to)
    local p = from and to and ns.FLIGHT_PATHS and ns.FLIGHT_PATHS[from] and ns.FLIGHT_PATHS[from][to]
    if not p then return nil end
    if type(p) == "table" then return p[1] / SPEED + (p[2] or 0) end
    return p / SPEED
end

-- The current node's flight map slot.
local function CurrentSlot()
    if not (NumTaxiNodes and TaxiNodeGetType) then return nil end
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) == "CURRENT" then return i end
    end
end

-- Seconds for flying to map slot `dest`: every hop the game will fly, added up. nil if
-- the data doesn't have every hop.
local function TripSeconds(dest)
    local total
    local hops = GetNumRoutes and ns.SafeCall(GetNumRoutes, dest)
    if type(hops) == "number" and not IsSecret(hops) and hops >= 1 and TaxiGetNodeSlot then
        total = 0
        for hop = 1, hops do
            local s = HopSeconds(NodeIDForSlot(TaxiGetNodeSlot(dest, hop, true)),
                                 NodeIDForSlot(TaxiGetNodeSlot(dest, hop, false)))
            if not s then total = nil break end
            total = total + s
        end
    end
    total = total or HopSeconds(NodeIDForSlot(CurrentSlot()), NodeIDForSlot(dest)) -- a direct flight
    return total and total > 0 and math.floor(total + 0.5) or nil
end

local flight = ns.NewRingFrame("flight")
local geom = flight.geom
flight.fill = NewRingLayer("ARTWORK", 0, { r = 1, g = 1, b = 1 }, 1, flight)
flight.fill2 = NewRingLayer("ARTWORK", 0, { r = 1, g = 1, b = 1 }, 1, flight) -- the spinner's wrap-around piece

flight.dest = ns.RingText(flight)  -- destination, small, above the time
flight.time = ns.RingText(flight)  -- 1:23, big
flight.label = ns.RingText(flight) -- "remaining" / "No route data" / "Arrived"

-- What's being shown. Real flights fill `trip`; edit mode and previews use samples.
local trip = nil      -- { dest, start, total (nil = not in the data), landed }
local pendingRoute = nil -- { dest, total, at } picked on the flight map, waiting for takeoff
local editing, previewUntil, sampleT = false, 0, 0
local holdUntil = 0

-- Short place name: "Ironforge, Dun Morogh" -> "Ironforge".
local function ShortName(name)
    return name and (name:match("^([^,]+)") or name) or nil
end

-- Picking a destination on the flight map: work out the trip now, while the map (and
-- its hops) can still be read, and keep it until takeoff.
local function OnTakeTaxiNode(index)
    if not TaxiNodeName then return end
    local dest = TaxiNodeName(index)
    if IsSecret(dest) then dest = nil end
    local ok, total = pcall(TripSeconds, index)
    pendingRoute = { dest = dest, total = ok and total or nil, at = GetTime() }
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

-- What to draw right now: dest, elapsed, total (nil = not in the data), landed.
local function Current(now)
    if editing or now < previewUntil then
        -- A route in the data counting down, then one that isn't counting up.
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
        -- Route not in the data: a quarter arc circling, and the time in the air.
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
        flight.label:SetText("No route data")
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
    trip = { dest = route and route.dest, start = now, total = route and route.total }
end

local function EndFlight(now)
    if not trip or trip.landed then return end
    trip.landed = now
    local duration = now - trip.start
    if ns.SessionAdd and duration >= 5 then -- shorter: cancelled right away
        ns.SessionAdd("flights", nil, 1)
        ns.SessionAdd("flightTime", nil, duration)
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
    flight:SetFrameStrata(editing and EDIT_STRATA or ns.RING_STRATA)
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

-- Shared with the files loaded after this one.
ns.SetFlightEditing = SetFlightEditing
ns.IsFlightEditing = function() return editing end
ns.PreviewFlightRing = PreviewFlightRing

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
            learning = { r = 0.75, g = 0.75, b = 0.80 }, -- a route not in the data
        },
    },
    page = { folder = "status", order = 1, build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(8, "Flight", "Flight Ring",
                "Counts down to landing while you're on a flight path. Flight times come from the game's own "
                .. "flight path data (the length of every hop of the trip, at flying speed). A route that isn't in "
                .. "the data counts up the time in the air instead.",
                MergeTop(TopRow("flight", "flight ring", ns.PreviewFlightRing,
                    "Show the ring counting down a route, then one that isn't in the data. Also /circ flight."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "flightEnabled", "Show flight ring", "Show the ring while you're on a flight path."),
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "flightColors", "fill", "Countdown", "Ring color while counting down to landing."),
                        learning = Color(2, "flightColors", "learning", "No route data",
                            "Color of the circling arc on a route that isn't in the flight data."),
                    }),
                    size = SizeBox(4, "flight", "flight ring", "Offset from the center of the screen."),
                }))
            tab.args.size.args.hold.desc = "How long the ring stays after you land."
            return tab
        end },
})
