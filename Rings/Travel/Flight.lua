-- Circlet: Flight ring: a countdown to landing while you're on a flight path.
local ADDON_NAME, ns = ...

local db, IsSecret = ns.db, ns.IsSecret
local NewRingLayer, DrawArc = ns.NewRingLayer, ns.DrawArc
local EDIT_STRATA = ns.EDIT_STRATA
local FormatTime = ns.FormatTime

---------------------------------------------------------------------------
-- Flight ring
---------------------------------------------------------------------------
-- Flight times come only from the game's own data: Rings/Travel/FlightPaths.lua holds the
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
-- files have path lengths but not the speed, so it's measured from real flights in this
-- client (the flight log, /circ flightlog): 13 flights of one and two hops, 2,599 to
-- 13,299 yards, all flew at 29.9 to 30.0 yards a second (fitted 29.99), within half a
-- second of yards / 30 on every one, with no extra time per flight or per hop.
local SPEED = 30

---------------------------------------------------------------- times from the game's flight paths
-- Node IDs by English name: the backup for when the flight map can't say a node's ID.
local nodeByName
local function NodeIDByName(name)
    if not name then return nil end
    if not nodeByName then
        nodeByName = {}
        for id, n in pairs(ns.FLIGHT_NODES or {}) do
            nodeByName[n] = id
        end
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
                if n.slotIndex == slot and type(n.nodeID) == "number" and not IsSecret(n.nodeID) then
                    return n.nodeID
                end
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
    local yards, delay = type(p) == "table" and p[1] or p, type(p) == "table" and (p[2] or 0) or 0
    return yards / SPEED + delay, yards, delay
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
    -- What the trip was made of, for the flight log: node IDs, yards, stop seconds.
    local info = { nodes = {}, yards = 0, delay = 0 }
    local hops = GetNumRoutes and ns.SafeCall(GetNumRoutes, dest)
    if type(hops) == "number" and not IsSecret(hops) and hops >= 1 and TaxiGetNodeSlot then
        total = 0
        for hop = 1, hops do
            local a = NodeIDForSlot(TaxiGetNodeSlot(dest, hop, true))
            local b = NodeIDForSlot(TaxiGetNodeSlot(dest, hop, false))
            local s, yards, delay = HopSeconds(a, b)
            if hop == 1 then info.nodes[1] = a or "?" end
            info.nodes[hop + 1] = b or "?"
            if not s then
                total = nil
                break
            end
            total, info.yards, info.delay = total + s, info.yards + yards, info.delay + delay
        end
    end
    if not total then -- a direct flight
        local a, b = NodeIDForSlot(CurrentSlot()), NodeIDForSlot(dest)
        local s, yards, delay = HopSeconds(a, b)
        info = { nodes = { a or "?", b or "?" }, yards = yards or 0, delay = delay or 0, direct = true }
        total = s
    end
    info.hops = #info.nodes - 1
    return total and total > 0 and math.floor(total + 0.5) or nil, info
end

local flight = ns.NewRingFrame("flight")
local geom = flight.geom
flight.fill = NewRingLayer("ARTWORK", 0, { r = 1, g = 1, b = 1 }, 1, flight)
flight.fill2 = NewRingLayer("ARTWORK", 0, { r = 1, g = 1, b = 1 }, 1, flight) -- the spinner's wrap-around piece

flight.dest = ns.RingText(flight) -- destination, small, above the time
flight.time = ns.RingText(flight) -- 1:23, big
flight.label = ns.RingText(flight) -- "remaining" / "No route data" / "Arrived"

-- What's being shown. Real flights fill `trip`; edit mode and previews use samples.
local trip = nil -- { dest, start, total (nil = not in the data), landed }
local pendingRoute = nil -- { dest, total, at } picked on the flight map, waiting for takeoff
local editing, previewUntil, sampleT = false, 0, 0
local holdUntil = 0

-- Short place name: "Ironforge, Dun Morogh" -> "Ironforge".
local function ShortName(name) return name and (name:match("^([^,]+)") or name) or nil end

-- Picking a destination on the flight map: work out the trip now, while the map (and
-- its hops) can still be read, and keep it until takeoff.
local LogFlight -- (below)
local function OnTakeTaxiNode(index)
    if not TaxiNodeName then return end
    local dest = TaxiNodeName(index)
    if IsSecret(dest) then dest = nil end
    local ok, total, info = pcall(TripSeconds, index)
    local here = CurrentSlot()
    local from = here and TaxiNodeName(here)
    if IsSecret(from) then from = nil end
    pendingRoute = { dest = dest, from = from, total = ok and total or nil, info = ok and info or nil, at = GetTime() }
end
if hooksecurefunc and TakeTaxiNode then hooksecurefunc("TakeTaxiNode", OnTakeTaxiNode) end

---------------------------------------------------------------- drawing
-- The flight ring's texts, top to bottom, for their size settings.
ns.RegisterTextRoles("flight", {
    { id = "Dest", name = "Destination", desc = "The top line: where you're flying to." },
    { id = "Time", name = "Time left", desc = "The big countdown in the middle." },
    { id = "Label", name = "Bottom line", desc = "Under the time: the route, or why there's no time." },
})

local function Layout()
    local size = db.flightSize
    ns.PlaceRing(flight, "flight", size)
    local inner = ns.UpdateGeometry(flight, "flight", size)
    if not inner then return end
    flight.time:SetFont(STANDARD_TEXT_FONT, ns.FontSize("flight", "Time", inner * 0.27, 10), "OUTLINE")
    flight.dest:SetFont(STANDARD_TEXT_FONT, ns.FontSize("flight", "Dest", inner * 0.13, 7), "OUTLINE")
    flight.label:SetFont(STANDARD_TEXT_FONT, ns.FontSize("flight", "Label", inner * 0.12, 7), "OUTLINE")
    flight.dest:SetWidth(inner * 0.92)
    flight.dest:SetWordWrap(false)
    flight.time:ClearAllPoints()
    flight.time:SetPoint("CENTER", flight, "CENTER", 0, -math.floor(inner * 0.02))
    flight.dest:ClearAllPoints()
    flight.dest:SetPoint("BOTTOM", flight.time, "TOP", 0, 2)
    flight.label:ClearAllPoints()
    flight.label:SetPoint("TOP", flight.time, "BOTTOM", 0, -2)
end

---------------------------------------------------------------- the animation
-- With flightFx on: the player arrow flies along the ring at the end of the fill (or the
-- head of the circling arc on a route not in the data), pointing the way it's going, with a
-- contrail fading out behind it. Clouds drift through the middle of the ring and wind
-- streaks rush past. On landing the arrow touches down in a glow and a puff of dust, and
-- the clouds part and fade. Worked out from the time, so edit mode's sample plays it too.
local CLOUDS, STREAKS, TRAIL, DUST = 6, 4, 12, 6
local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local TOUCHDOWN = 1.2 -- seconds the landing plays
local fx -- made on first use

local function FxTex(tex, layer, sub, blend)
    local t = flight:CreateTexture(nil, layer, nil, sub)
    if t:SetTexture(tex) == false then t:SetTexture("Interface\\Cooldown\\star4") end
    t:SetBlendMode(blend)
    t:Hide()
    return t
end

local function BuildFx()
    fx = { clouds = {}, streaks = {}, trail = {}, dust = {} }
    for i = 1, CLOUDS do
        fx.clouds[i] = FxTex(GLOW_TEX, "BACKGROUND", -4, "BLEND")
    end
    for i = 1, STREAKS do
        local l = flight:CreateLine(nil, "ARTWORK", nil, 1)
        if l.SetBlendMode then l:SetBlendMode("ADD") end
        l:Hide()
        fx.streaks[i] = l
    end
    for i = 1, TRAIL do
        local l = flight:CreateLine(nil, "ARTWORK", nil, 2)
        if l.SetBlendMode then l:SetBlendMode("ADD") end
        l:Hide()
        fx.trail[i] = l
    end
    for i = 1, DUST do
        fx.dust[i] = FxTex(GLOW_TEX, "ARTWORK", 3, "BLEND")
    end
    fx.glow = FxTex(GLOW_TEX, "ARTWORK", 4, "ADD")
    fx.arrow = flight:CreateTexture(nil, "OVERLAY", nil, 7)
    fx.isArrow = fx.arrow:SetTexture("Interface\\Minimap\\MinimapArrow") ~= false
    if not fx.isArrow then fx.arrow:SetTexture("Interface\\Cooldown\\star4") end
    fx.arrow:Hide()
end

local function HideFx()
    if not fx then return end
    for _, t in ipairs(fx.clouds) do
        t:Hide()
    end
    for _, l in ipairs(fx.streaks) do
        l:Hide()
    end
    for _, l in ipairs(fx.trail) do
        l:Hide()
    end
    for _, t in ipairs(fx.dust) do
        t:Hide()
    end
    fx.glow:Hide()
    fx.arrow:Hide()
end

local function Hash(n)
    local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)
end

-- head: where the arrow is (a fraction round the ring); landedAge: seconds since landing.
local function DrawFlightFx(now, head, c, landedAge)
    if not db.flightFx or not geom or geom.R <= 0 then return HideFx() end
    if not fx then BuildFx() end
    local R, T = geom.R, math.max(3, geom.T)
    local ri = math.max(4, R - T / 2)
    local landing = landedAge and math.min(1, landedAge / TOUCHDOWN) or 0
    if landedAge and landedAge >= TOUCHDOWN then return HideFx() end
    local k = 1 - landing

    -- Clouds: soft puffs drifting right to left at their own heights and speeds, fading in
    -- and out at the sides of the hollow. Landing, they part outward and fade.
    for i, t in ipairs(fx.clouds) do
        local speed = 0.05 + 0.05 * Hash(i)
        local u = (now * speed + Hash(i + 10)) % 1
        local x = (1 - 2 * u) * ri * 0.9
        local y = (Hash(i + 20) * 2 - 1) * ri * 0.55
        local part = 1 + landing * 0.8
        local edge = math.max(0, 1 - (math.abs(x) / (ri * 0.9)) ^ 3)
        local s = ri * (0.55 + 0.35 * Hash(i + 30))
        t:ClearAllPoints()
        t:SetPoint("CENTER", flight, "CENTER", x * part, y * part)
        t:SetSize(s * 1.5, s)
        t:SetVertexColor(0.95, 0.97, 1)
        t:SetAlpha(0.32 * edge * k)
        t:Show()
    end
    -- Wind streaks: thin lines rushing past.
    for i, l in ipairs(fx.streaks) do
        local u = (now * (0.6 + 0.3 * Hash(i + 40)) + Hash(i + 50)) % 1
        local x = (1 - 2 * u) * ri * 0.95
        local y = (Hash(i + 60 + math.floor(now * (0.6 + 0.3 * Hash(i + 40)) + Hash(i + 50))) * 2 - 1) * ri * 0.6
        local len = ri * 0.35
        local a = math.sin(math.pi * u) * 0.35 * k
        l:SetStartPoint("CENTER", flight, x, y)
        l:SetEndPoint("CENTER", flight, x + len, y)
        l:SetThickness(math.max(1, T * 0.12))
        l:SetColorTexture(1, 1, 1, a)
        l:SetShown(a > 0.01)
    end

    -- The arrow, and its contrail behind it along the ring.
    local x, y = ns.RingPoint(geom, head)
    local x2, y2 = ns.RingPoint(geom, math.min(1, head + 0.004))
    if head >= 0.996 then
        local xb, yb = ns.RingPoint(geom, head - 0.004)
        x2, y2 = x + (x - xb), y + (y - yb)
    end
    local ang = math.atan2 and math.atan2(y2 - y, x2 - x) or math.atan(y2 - y, x2 - x)
    local px, py = x, y
    for i, l in ipairs(fx.trail) do
        local f = head - i * 0.012
        if f < 0 then f = f + 1 end
        local qx, qy = ns.RingPoint(geom, f)
        local a = (1 - i / TRAIL) * 0.75 * k
        l:SetStartPoint("CENTER", flight, px, py)
        l:SetEndPoint("CENTER", flight, qx, qy)
        l:SetThickness(math.max(1, T * 0.4 * (1 - i / TRAIL)))
        l:SetColorTexture(1, 1, 1, a)
        l:SetShown(a > 0.01)
        px, py = qx, qy
    end
    local bob = math.sin(now * 3) * T * 0.15 * k -- a little rise and fall in the air
    local s = T * (fx.isArrow and 2.6 or 1.8) * (1 - 0.35 * landing)
    fx.arrow:ClearAllPoints()
    fx.arrow:SetPoint("CENTER", flight, "CENTER", x + bob * x / R, y + bob * y / R)
    fx.arrow:SetSize(s, s)
    fx.arrow:SetVertexColor(1, 1, 1)
    if fx.arrow.SetRotation then fx.arrow:SetRotation(ang - math.pi / 2) end -- it points up at 0
    fx.arrow:SetAlpha(1 - landing ^ 2)
    fx.arrow:Show()
    -- A glow under it, flaring as it touches down.
    local flare = landedAge and math.sin(math.pi * math.min(1, landedAge / 0.6)) or 0
    fx.glow:ClearAllPoints()
    fx.glow:SetPoint("CENTER", flight, "CENTER", x, y)
    local gs = T * (3 + 4 * flare)
    fx.glow:SetSize(gs, gs)
    fx.glow:SetVertexColor(c.r, c.g, c.b)
    fx.glow:SetAlpha((0.5 + 0.5 * flare) * (landedAge and (1 - landing) or 1))
    fx.glow:Show()
    -- Landing: a puff of dust spreading from where it touched down.
    for i, t in ipairs(fx.dust) do
        if landedAge then
            local a2 = i / DUST * 2 * math.pi
            local d = T * 3 * (1 - (1 - landing) ^ 2)
            t:ClearAllPoints()
            t:SetPoint("CENTER", flight, "CENTER", x + math.cos(a2) * d, y + math.sin(a2) * d * 0.6)
            local ds = T * (1.5 + 2 * landing)
            t:SetSize(ds, ds)
            t:SetVertexColor(0.85, 0.8, 0.7)
            t:SetAlpha(0.5 * (1 - landing))
            t:Show()
        else
            t:Hide()
        end
    end
end

-- What to draw right now: dest, elapsed, total (nil = not in the data), landed.
local function Current(now)
    if editing or now < previewUntil then
        -- A route in the data counting down, then one that isn't counting up.
        local cycle = sampleT % 16
        if cycle < 10 then return "Ironforge", 30 + cycle * 9, 150, false end
        return "Southshore", (cycle - 10) * 7 + 12, nil, false
    end
    if not trip then return nil end
    local elapsed = (trip.landed or now) - trip.start
    return ShortName(trip.dest), elapsed, trip.total, trip.landed ~= nil
end

local function Draw(now)
    Layout()
    local dest, elapsed, total, landed = Current(now)
    if not elapsed then return HideFx() end
    local c = db.flightColors
    for _, l in ipairs(flight.fill2) do
        l:Hide()
    end

    if landed then
        for _, l in ipairs(flight.fill) do
            l:SetColorTexture(c.fill.r, c.fill.g, c.fill.b, 1)
        end
        DrawArc(flight.fill, 0, 1, flight, geom, nil, ns.Shade("flight", c.fill))
        flight.time:SetText(FormatTime(elapsed))
        flight.time:SetTextColor(1, 1, 1)
        flight.label:SetText("Arrived")
        flight.label:SetTextColor(c.fill.r, c.fill.g, c.fill.b)
        DrawFlightFx(now, 1, c.fill, trip and trip.landed and now - trip.landed or TOUCHDOWN)
    elseif total then
        local frac = math.min(1, elapsed / math.max(1, total))
        for _, l in ipairs(flight.fill) do
            l:SetColorTexture(c.fill.r, c.fill.g, c.fill.b, 1)
        end
        DrawArc(flight.fill, 0, frac, flight, geom, nil, ns.Shade("flight", c.fill))
        local left = total - elapsed
        flight.time:SetText(left > 0 and FormatTime(left) or "0:00")
        flight.time:SetTextColor(1, 1, 1)
        flight.label:SetText(left > 0 and "remaining" or "landing")
        flight.label:SetTextColor(0.8, 0.8, 0.8)
        DrawFlightFx(now, frac, c.fill)
    else
        -- Route not in the data: a quarter arc circling, and the time in the air.
        local spin = (elapsed * 0.35) % 1
        for _, l in ipairs(flight.fill) do
            l:SetColorTexture(c.learning.r, c.learning.g, c.learning.b, 1)
        end
        DrawArc(flight.fill, spin, math.min(1, spin + 0.25), flight, geom)
        if spin + 0.25 > 1 then
            -- Wraps past 12 o'clock: the rest goes on the second layer.
            for _, l in ipairs(flight.fill2) do
                l:SetColorTexture(c.learning.r, c.learning.g, c.learning.b, 1)
            end
            DrawArc(flight.fill2, 0, spin + 0.25 - 1, flight, geom)
        end
        flight.time:SetText(FormatTime(elapsed))
        flight.time:SetTextColor(1, 1, 1)
        flight.label:SetText("No route data")
        flight.label:SetTextColor(c.learning.r, c.learning.g, c.learning.b)
        DrawFlightFx(now, (spin + 0.25) % 1, c.learning)
    end
    flight.dest:SetText(dest and ("to " .. dest) or "Flying")
    flight.dest:SetTextColor(1, 0.82, 0)
end

---------------------------------------------------------------- flights
-- The flight log (db.flightLog, the last LOG_SIZE flights): each flight's route, the mined
-- yards and stop seconds it was timed from, and how long it really took. It's only a record
-- for checking SPEED against real flights (/circ flightlog); the ring's times never use it.
local LOG_SIZE = 40
LogFlight = function(t, duration)
    if duration < 5 or not t.info then return end
    db.flightLog = db.flightLog or {}
    local i = t.info
    table.insert(db.flightLog, {
        when = date and date("%Y-%m-%d %H:%M") or "?",
        from = t.from,
        to = t.dest,
        nodes = table.concat(i.nodes, ">"),
        hops = i.hops,
        yards = i.yards,
        stops = i.delay,
        predicted = t.total,
        actual = math.floor(duration * 10 + 0.5) / 10,
        speed = SPEED,
    })
    while #db.flightLog > LOG_SIZE do
        table.remove(db.flightLog, 1)
    end
end

local function StartFlight(now)
    local route = pendingRoute
    pendingRoute = nil
    -- Only trust a route picked in the last minute (the map click that started this).
    if route and now - route.at > 60 then route = nil end
    trip = {
        dest = route and route.dest,
        from = route and route.from,
        start = now,
        total = route and route.total,
        info = route and route.info,
    }
end

local function EndFlight(now)
    if not trip or trip.landed then return end
    trip.landed = now
    local duration = now - trip.start
    if ns.SessionAdd and duration >= 5 then -- shorter: cancelled right away
        ns.SessionAdd("flights", nil, 1)
        ns.SessionAdd("flightTime", nil, duration)
    end
    LogFlight(trip, duration)
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

-- /circ flightlog: the last flights, predicted against real, with the speed each implies.
local function ShowFlightLog()
    local log = db.flightLog or {}
    if #log == 0 then
        ns.Print("No flights logged yet: fly somewhere and check again.")
        return
    end
    ns.Print(string.format("Last %d flights (timed at %.1f yards/second):", math.min(10, #log), SPEED))
    local yards, secs = 0, 0
    for i = math.max(1, #log - 9), #log do
        local f = log[i]
        local flying = f.actual - (f.stops or 0)
        print(
            string.format(
                "  %s > %s: %d hop%s, %d yd%s  predicted %s, took %.1fs (%+.1fs)  = %.1f yd/s",
                ShortName(f.from) or "?",
                ShortName(f.to) or "?",
                f.hops or 0,
                (f.hops or 0) == 1 and "" or "s",
                f.yards or 0,
                (f.stops or 0) > 0 and (" + " .. f.stops .. "s stops") or "",
                f.predicted and (f.predicted .. "s") or "?",
                f.actual,
                f.actual - (f.predicted or f.actual),
                flying > 0 and (f.yards or 0) / flying or 0
            )
        )
    end
    for _, f in ipairs(log) do
        if (f.yards or 0) > 0 then
            yards, secs = yards + f.yards, secs + f.actual - (f.stops or 0)
        end
    end
    if secs > 0 then
        ns.Print(string.format("All %d logged flights together: %.1f yards/second.", #log, yards / secs))
    end
end
ns.RegisterCommand({ "flightlog" }, ShowFlightLog) -- the flight log (for checking the speed)

-- Shared with the files loaded after this one.
ns.SetFlightEditing = SetFlightEditing
ns.IsFlightEditing = function() return editing end
ns.PreviewFlightRing = PreviewFlightRing
ns.FlightFxParts = function() return fx end -- for the tests

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "flight",
    name = "Flight",
    order = 8,
    edit = { set = SetFlightEditing, get = ns.IsFlightEditing },
    preview = PreviewFlightRing,
    slash = { "flight", "taxi" },
    help = "preview the flight ring",
    toggle = { "Flight ring", "Counts down to landing while you're on a flight path." },
    defaults = {
        -- Flight ring: a countdown to landing on flight paths.
        flightEnabled = true,
        flightFx = true, -- the arrow and contrail, clouds and wind, and the touchdown
        flightSize = 120,
        flightThickness = 12,
        flightOpacity = 100,
        flightX = 170, -- right of the crafting ring
        flightFromTop = 255,
        flightHold = 3, -- seconds it stays after landing
        flightStyle = "smooth",
        flightBorder = 2, -- black border width (0 = none)
        flightColors = {
            fill = { r = 0.45, g = 0.75, b = 1.00 },
            learning = { r = 0.75, g = 0.75, b = 0.80 }, -- a route not in the data
        },
    },
    page = {
        folder = "travel",
        order = 1,
        build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(
                8,
                "Flight",
                "Flight Ring",
                "Counts down to landing while you're on a flight path. Flight times come from the game's own "
                    .. "flight path data (the length of every hop of the trip, at flying speed). A route that isn't in "
                    .. "the data counts up the time in the air instead.",
                MergeTop(
                    TopRow(
                        "flight",
                        "flight ring",
                        ns.PreviewFlightRing,
                        "Show the ring counting down a route, then one that isn't in the data. Also /circ flight."
                    ),
                    {
                        general = Box(2, "General", {
                            enabled = Toggle(
                                1,
                                "flightEnabled",
                                "Show flight ring",
                                "Show the ring while you're on a flight path."
                            ),
                            fx = Toggle(
                                2,
                                "flightFx",
                                "Animations",
                                "The player arrow flies along the end of the fill with a contrail behind it, clouds drift "
                                    .. "through the middle of the ring and wind streaks past, and when you land the arrow touches "
                                    .. "down in a glow and a puff of dust as the clouds part."
                            ),
                        }),
                        colors = Box(3, "Colors", {
                            fill = Color(
                                1,
                                "flightColors",
                                "fill",
                                "Countdown",
                                "Ring color while counting down to landing."
                            ),
                            learning = Color(
                                2,
                                "flightColors",
                                "learning",
                                "No route data",
                                "Color of the circling arc on a route that isn't in the flight data."
                            ),
                        }),
                        size = SizeBox(4, "flight", "flight ring", "Offset from the center of the screen."),
                    }
                )
            )
            tab.args.size.args.hold.desc = "How long the ring stays after you land."
            return tab
        end,
    },
})
