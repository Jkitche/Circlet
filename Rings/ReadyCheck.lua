-- Circlet: Ready check ring: time left to answer a ready check, and who's ready.
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing, FormatTime = ns.db, ns.IsSecret, ns.CreateLiveRing, ns.FormatTime
local SafeCall, Clean = ns.SafeCall, ns.Clean

---------------------------------------------------------------------------
-- Ready check ring
---------------------------------------------------------------------------
-- Up while a ready check runs in your group: the ring drains over the time left to answer,
-- with who started it, the seconds left and how many are ready ("3/5 ready"). Until you
-- answer it asks "Are you ready?"; as soon as anyone says they're not, it turns red. The
-- game's own ready check icon sits on the ring (waiting, ready or not ready), as a badge on
-- its top edge or, with Icon as background, filling its middle behind the text.
-- When the check ends the ring fills and holds the result for a moment: "All ready!" in
-- green, or how many weren't ready and how many never answered, in red.
--
-- Who's ready comes from READY_CHECK_CONFIRM as people answer (the starter is ready from
-- the start); the time from GetReadyCheckTimeLeft while it's readable, else the check's
-- own time limit counted from when it began.

local ICONS = {
    waiting  = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    ready    = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}

local check -- { started, total, initiator, order = { key... }, status = { key -> state }, you, endedAt }

local function Num(v) return type(v) == "number" and not IsSecret(v) and v or nil end

-- A stable key for a unit: its GUID, else its name.
local function Key(unit)
    return Clean(SafeCall(UnitGUID, unit)) or Clean(SafeCall(UnitName, unit))
end

-- Everyone in the group (you included), as unit tokens.
local function GroupUnits()
    local units = { "player" }
    local n = Num(SafeCall(GetNumGroupMembers)) or 0
    if SafeCall(IsInRaid) then
        for i = 1, n do
            local u = "raid" .. i
            if not SafeCall(UnitIsUnit, u, "player") then table.insert(units, u) end
        end
    else
        for i = 1, math.max(0, n - 1) do table.insert(units, "party" .. i) end
    end
    return units
end

local function Count()
    local ready, notready, waiting = 0, 0, 0
    for _, k in ipairs(check.order) do
        local s = check.status[k]
        if s == "ready" then ready = ready + 1
        elseif s == "notready" then notready = notready + 1
        else waiting = waiting + 1 end
    end
    return ready, notready, waiting
end

local function State(c)
    local col = db.readyColors
    local ready, notready, waiting = c.ready, c.notready, c.waiting
    local total = ready + notready + waiting
    if c.ended then
        local all = notready == 0 and waiting == 0
        local label
        if all then
            label = "All ready!"
        else
            local parts = {}
            if notready > 0 then table.insert(parts, notready .. " not ready") end
            if waiting > 0 then table.insert(parts, waiting .. " AFK") end
            label = table.concat(parts, ", ")
        end
        local color = all and col.ready or col.notready
        return { title = "Ready check", value = ready .. "/" .. total, label = label, labelColor = color,
                 frac = 1, color = color, icon = all and ICONS.ready or ICONS.notready, iconColor = color,
                 hold = db.readyHold or 3 }
    end
    local color = notready > 0 and col.notready or col.waiting
    local label = c.youWaiting and "Are you ready?" or (ready .. "/" .. total .. " ready")
    return {
        title = c.initiator and ("Ready check: " .. c.initiator) or "Ready check",
        value = c.left >= 60 and FormatTime(c.left) or tostring(math.ceil(c.left)),
        label = label,
        labelColor = c.youWaiting and col.ready or (notready > 0 and col.notready or nil),
        frac = c.total > 0 and math.max(0, math.min(1, c.left / c.total)) or 0,
        color = color,
        icon = notready > 0 and ICONS.notready or ICONS.waiting,
        iconColor = color,
        hold = 0.2,
    }
end

local readyRing = CreateLiveRing({
    key = "ready",
    read = function(now)
        now = now or GetTime()
        if not check then return nil end
        local ready, notready, waiting = Count()
        if check.endedAt then
            -- The result is handed to the ring once (for a moment, from the first time it's
            -- read, even if the check ended while the ring was hidden); the ring then holds it.
            check.resultAt = check.resultAt or now
            if now - check.resultAt > 0.1 then check = nil return nil end
            return State({ ended = true, ready = ready, notready = notready, waiting = waiting })
        end
        local left = Num(SafeCall(GetReadyCheckTimeLeft))
        if not left then left = math.max(0, check.started + check.total - now) end
        if left <= 0 and now > check.started + check.total + 3 then
            check.endedAt = now -- the game never said it finished
        end
        return State({ ready = ready, notready = notready, waiting = waiting, left = left, total = check.total,
                       initiator = check.initiator, youWaiting = check.you and check.status[check.you] == "waiting" })
    end,
    sample = function(t)
        -- Five of you: answers come in, one says not ready, then the result.
        local cycle = t % 16
        if cycle >= 12 then
            return State({ ended = true, ready = 4, notready = 1, waiting = 0 })
        end
        local ready = math.min(5, 1 + math.floor(cycle / 2))
        local notready = cycle >= 9 and 1 or 0
        if notready > 0 then ready = 4 end
        return State({ ready = ready, notready = notready, waiting = 5 - ready - notready, left = 35 - cycle * 2.5,
                       total = 35, initiator = "Thrall", youWaiting = cycle < 2 })
    end,
})

-- A ready check starts: who's in the group, who started it, its time limit.
local function Start(initiator, seconds)
    if not db.readyEnabled then check = nil return end
    initiator = Clean(initiator)
    check = { started = GetTime(), total = Num(seconds) or Num(SafeCall(GetReadyCheckTimeLeft)) or 35,
              initiator = initiator, order = {}, status = {} }
    for _, u in ipairs(GroupUnits()) do
        local k = Key(u)
        if k and not check.status[k] then
            table.insert(check.order, k)
            local name = Clean(SafeCall(UnitName, u))
            local s = Clean(SafeCall(GetReadyCheckStatus, u))
            if name and initiator and name == initiator then s = "ready" end -- the starter is ready
            check.status[k] = (s == "ready" or s == "notready") and s or "waiting"
        end
    end
    check.you = Key("player")
end

local function Confirm(unit, isReady)
    if not check or check.endedAt then return end
    local k = Clean(unit) and Key(unit)
    if not k then return end
    if not check.status[k] then table.insert(check.order, k) end
    check.status[k] = Clean(isReady) and "ready" or "notready"
end

ns.Listen({ "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED" }, function(event, a1, a2)
    if not CircletDB then return end
    if event == "READY_CHECK" then
        Start(a1, a2)
    elseif event == "READY_CHECK_CONFIRM" then
        Confirm(a1, a2)
    elseif check and not check.endedAt then
        check.endedAt = GetTime()
    end
end)

local function PreviewReadyRing() readyRing.Preview(16) end

-- Shared with the files loaded after this one.
ns.readyRing = readyRing
ns.PreviewReadyRing = PreviewReadyRing

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "ready", name = "Ready check", order = 14.8, since = "1.2.0",
    iconBg = true, -- "Icon as background": the ready check icon fills the ring's middle (Core/Settings.lua, UI/OptionsKit.lua)
    ring = readyRing,
    preview = PreviewReadyRing, slash = { "ready", "readycheck" }, help = "preview the ready check ring",
    toggle = { "Ready check ring", "Time left to answer a ready check, and how many are ready." },
    defaults = {
        -- Ready check ring: time to answer a ready check, and who's ready. Left of the target cast ring.
        readyEnabled   = true,
        readySize      = 110,
        readyThickness = 11,
        readyOpacity   = 100,
        readyX         = -170,
        readyFromTop   = 385,
        readyHold      = 3,   -- seconds the result stays after the check ends
        readyStyle     = "smooth",
        readyBorder    = 2,
        readyColors = {
            waiting  = { r = 1.00, g = 0.82, b = 0.25 },
            ready    = { r = 0.35, g = 0.90, b = 0.35 },
            notready = { r = 1.00, g = 0.30, b = 0.25 },
        },
    },
    page = { folder = "status", order = 4.9, build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(10.95, "Ready checks", "Ready Check Ring",
                "Up while a ready check runs: the ring drains over the time left to answer, with who started it, "
                .. "the seconds left and how many are ready, and the game's ready check icon (as a badge, or behind "
                .. "the text with Icon as background). It asks \"Are you ready?\" until you answer and turns red if "
                .. "anyone isn't. When the check ends it shows the result for a moment.",
                MergeTop(TopRow("ready", "ready check ring", ns.PreviewReadyRing,
                    "Show a sample ready check with answers coming in. Also /circ ready."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "readyEnabled", "Show ready check ring", "Count down ready checks."),
                    }),
                    colors = Box(3, "Colors", {
                        waiting = Color(1, "readyColors", "waiting", "Waiting", "Ring color while answers come in."),
                        ready = Color(2, "readyColors", "ready", "All ready", "Color when everyone is ready (and for \"Are you ready?\")."),
                        notready = Color(3, "readyColors", "notready", "Not ready", "Color once anyone isn't ready."),
                    }),
                    size = SizeBox(4, "ready", "ready check ring", "Offset from the center of the screen."),
                }))
            tab.args.size.args.hold.desc = "How long the result stays after the ready check ends."
            return tab
        end },
})
