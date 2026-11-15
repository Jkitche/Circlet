-- Circlet: Timer ring: a countdown you start yourself, with /circ timer 5m Tea.
local ADDON_NAME, ns = ...

local db, Print, CreateLiveRing, FormatTime = ns.db, ns.Print, ns.CreateLiveRing, ns.FormatTime

---------------------------------------------------------------------------
-- Timer ring
---------------------------------------------------------------------------
-- /circ timer <time> [label] starts it: the ring drains as the time runs out, with the
-- label (or "Timer") and the time left, and a pocket watch for its icon. In the last few
-- seconds (timerWarn) it pulses in the warning color. At zero it says "Time's up!" and
-- bursts, plays a sound and puts the label on screen (each optional), then fades after
-- timerHold seconds.
--   time: 90 (seconds), 90s, 5m, 1h, 1h30m, 2m30s, 1:30 (m:ss), 1:02:03 (h:mm:ss),
--         or a number and a unit word: 10 min, 2 hours
--   /circ timer +2m      adds time to the running timer (or starts one)
--   /circ timer stop     stops it (also cancel, clear, off)
--   /circ timer          says how long is left
-- The end time is saved (db.timerRun, as a clock time), so a timer keeps going through a
-- /reload or a relog; one that ran out while you were away is reported when you're back.

local ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local MAX = 24 * 3600 -- a day at most
local UNITS = { s = 1, sec = 1, secs = 1, second = 1, seconds = 1,
                m = 60, min = 60, mins = 60, minute = 60, minutes = 60,
                h = 3600, hr = 3600, hrs = 3600, hour = 3600, hours = 3600 }

-- Seconds for one word of time ("90", "5m", "1h30m", "1:30"), or nil.
local function ParseWord(w)
    if not w or w == "" then return nil end
    if w:find(":") then
        local parts = {}
        for p in w:gmatch("[^:]+") do
            local n = tonumber(p)
            if not n then return nil end
            table.insert(parts, n)
        end
        if #parts == 2 then return parts[1] * 60 + parts[2] end
        if #parts == 3 then return parts[1] * 3600 + parts[2] * 60 + parts[3] end
        return nil
    end
    local n = tonumber(w)
    if n then return n end
    local total, rest = 0, w:lower()
    for num, unit in w:lower():gmatch("(%d+%.?%d*)([hms])") do total = total + tonumber(num) * UNITS[unit] end
    rest = rest:gsub("%d+%.?%d*[hms]", "")
    if rest ~= "" or total == 0 then return nil end
    return total
end

-- "5m Tea" / "10 min Tea" / "1:30" -> seconds, label (nil if there's none).
local function Parse(text)
    local first, rest = text:match("^(%S+)%s*(.-)$")
    local secs = ParseWord(first)
    if not secs then return nil end
    local unit, after = rest:match("^(%a+)%s*(.-)$")
    if unit and tonumber(first) and UNITS[unit:lower()] then
        secs, rest = tonumber(first) * UNITS[unit:lower()], after
    end
    return secs, rest ~= "" and rest or nil
end

---------------------------------------------------------------- the running timer
local run -- { endsAt (GetTime), total, label, doneAt, resultAt }

-- From the saved end (a clock time, so it survives a reload or relog).
local function Load()
    if run or not db.timerRun then return end
    local saved = db.timerRun
    local left = (saved.endsAt or 0) - time()
    if left < -5 then
        -- Ran out while you were away.
        Print("Your timer" .. (saved.label and (" (" .. saved.label .. ")") or "") .. " ran out while you were away.")
        db.timerRun = nil
        return
    end
    run = { endsAt = GetTime() + left, total = saved.total or math.max(1, left), label = saved.label }
end

local function Save()
    if run and not run.doneAt then
        db.timerRun = { endsAt = time() + math.floor(run.endsAt - GetTime() + 0.5), total = run.total, label = run.label }
    else
        db.timerRun = nil
    end
end

local function Short(secs)
    secs = math.max(0, math.floor(secs + 0.5))
    local h, m, s = math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", math.floor(secs / 60), s)
end

-- Time's up: the sound and the big text on screen (each optional), and a chat line.
local function Ring()
    local name = run.label or "Timer"
    if db.timerSound and PlaySound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
    end
    if db.timerAlert and RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, name .. ": time's up!",
            (ChatTypeInfo and ChatTypeInfo.RAID_WARNING) or { r = 1, g = 0.8, b = 0.3 })
    end
    Print("Time's up: " .. name .. ".")
end

local function State(left, total, label, done, doneAt)
    local c = db.timerColors
    local st = { title = label or "Timer", icon = db.timerIcon and ICON or nil, frac = 0 }
    if done then
        st.value, st.label, st.labelColor, st.color = "0:00", "Time's up!", c.done, c.done
        st.frac, st.doneAt, st.hold = 1, doneAt, db.timerHold or 8
        st.iconColor = c.done
        return st
    end
    local warn = left <= (db.timerWarn or 10)
    local col = warn and c.warn or c.fill
    if warn then
        -- Pulse twice a second, brightening toward white.
        local p = 0.5 + 0.5 * math.sin(GetTime() * 2 * math.pi * 2)
        col = { r = col.r + (1 - col.r) * p * 0.5, g = col.g + (1 - col.g) * p * 0.5, b = col.b + (1 - col.b) * p * 0.5 }
    end
    st.value = left < 60 and tostring(math.ceil(left)) or Short(left)
    st.label = warn and "almost done" or "remaining"
    st.labelColor = warn and c.warn or nil
    st.color, st.iconColor = col, col
    st.frac = total > 0 and math.max(0, math.min(1, left / total)) or 0
    st.hold = 0.3
    return st
end

local timerRing = CreateLiveRing({
    key = "timer",
    read = function(now)
        now = now or GetTime()
        Load()
        if not run then return nil end
        local left = run.endsAt - now
        if left > 0 then return State(left, run.total, run.label) end
        if not run.doneAt then
            run.doneAt = now
            Ring()
            Save() -- (clears it)
        end
        -- The result is handed to the ring once, for a moment; the ring then holds it.
        run.resultAt = run.resultAt or now
        if now - run.resultAt > 0.1 then run = nil return nil end
        return State(0, run.total, run.label, true, run.doneAt)
    end,
    sample = function(t)
        -- Five minutes for the tea, sped up, into the warning, then time's up.
        local cycle = t % 14
        if cycle >= 11 then return State(0, 300, "Tea", true, GetTime() - (cycle - 11)) end
        local left = math.max(0.5, 300 - cycle * 27.2)
        return State(left, 300, "Tea")
    end,
})

local function Start(secs, label, add)
    Load()
    if add and run and not run.doneAt then
        run.endsAt = run.endsAt + secs
        run.total = run.total + secs
        if label then run.label = label end
    else
        run = { endsAt = GetTime() + secs, total = secs, label = label }
    end
    Save()
    timerRing.frame:Show()
    local left = run.endsAt - GetTime()
    Print((add and "Timer now " or "Timer started: ") .. Short(left) .. (run.label and (" (" .. run.label .. ")") or "") .. ".")
    if not db.timerEnabled then Print("The timer ring is turned off: turn it on in the options (Timer > Show timer ring).") end
end

local function Stop()
    Load()
    if not run or run.doneAt then Print("No timer running.") return end
    run = nil
    Save()
    Print("Timer stopped.")
end

local USAGE = "/circ timer <time> [label], e.g. 5m Tea, 1:30, 90, 1h20m, 10 min Pull; +2m adds time; stop."

local function Command(arg, raw)
    raw = strtrim(raw or arg or "")
    local word = raw:lower()
    if word == "" then
        Load()
        if run and not run.doneAt then
            Print("Timer: " .. Short(run.endsAt - GetTime()) .. " left" .. (run.label and (" (" .. run.label .. ")") or "") .. ".")
        else
            Print(USAGE)
        end
        return
    end
    if word == "stop" or word == "cancel" or word == "clear" or word == "off" then return Stop() end
    local add = raw:sub(1, 1) == "+"
    if add then raw = strtrim(raw:sub(2)) end
    local secs, label = Parse(raw)
    if not secs or secs <= 0 then Print("Couldn't read that time. " .. USAGE) return end
    if secs > MAX then Print("That's more than a day; the timer goes up to 24 hours.") return end
    Start(secs, label, add)
end

ns.RegisterCommand({ "timer", "countdown" }, Command,
    "start a countdown ring: 5m, 1:30, 90, 1h20m, with a label after; +2m adds time; stop",
    "timer <time> [label]")

local function PreviewTimerRing() timerRing.Preview(14) end

-- Shared with the files loaded after this one (and the tests).
ns.timerRing = timerRing
ns.PreviewTimerRing = PreviewTimerRing
ns.StartTimer = function(secs, label) Start(secs, label) end
ns.StopTimer = Stop
ns.ParseTimer = Parse

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "timer", name = "Timer", order = 11.8, since = "1.3.0",
    alwaysInCombat = true, -- a timer you started should stay up in a fight
    iconBg = true, -- "Icon as background": the pocket watch fills the ring's middle
    ring = timerRing,
    preview = PreviewTimerRing,
    toggle = { "Timer ring", "A countdown you start yourself: /circ timer 5m Tea." },
    defaults = {
        -- Timer ring: a countdown started with /circ timer. Right of the timed quest ring.
        timerEnabled   = true,
        timerIcon      = true, -- the pocket watch
        timerSound     = true, -- a sound when time's up
        timerAlert     = true, -- the label in big text on screen when time's up
        timerWarn      = 10,   -- seconds left when it starts pulsing in the warning color
        timerSize      = 110,
        timerThickness = 11,
        timerOpacity   = 100,
        timerX         = 510,
        timerFromTop   = 260,
        timerHold      = 8,    -- seconds "Time's up!" stays
        timerStyle     = "smooth",
        timerBorder    = 2,
        timerColors = {
            fill = { r = 0.40, g = 0.80, b = 1.00 },
            warn = { r = 1.00, g = 0.55, b = 0.20 },
            done = { r = 0.40, g = 0.90, b = 0.40 },
        },
    },
    page = { folder = "status", order = 4.75, build = function(O)
            local Toggle, Range, Color, Execute, Box = O.Toggle, O.Range, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(10.85, "Timer", "Timer Ring",
                "A countdown you start yourself. Type |cffffd100/circ timer 5m Tea|r (or 1:30, 90, 1h20m, "
                .. "10 min Pull...) or use the buttons below; |cffffd100/circ timer +2m|r adds time and "
                .. "|cffffd100/circ timer stop|r stops it. The ring drains as the time runs out, pulses near the end, "
                .. "and when time's up it bursts, plays a sound and shows the label on screen. It keeps going "
                .. "through a reload or a relog.",
                MergeTop(TopRow("timer", "timer ring", ns.PreviewTimerRing,
                    "Show a sample timer counting down to time's up."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "timerEnabled", "Show timer ring", "Show the ring while a timer runs."),
                        icon = Toggle(2, "timerIcon", "Show pocket watch icon", "The pocket watch on the ring."),
                        sound = Toggle(3, "timerSound", "Sound when time's up", "Play a sound when the timer runs out."),
                        alert = Toggle(4, "timerAlert", "Big text when time's up",
                            "Show the timer's label in large text on screen when it runs out."),
                        warn = Range(5, "timerWarn", "Pulse from (seconds left)", 0, 60, 1,
                            "In the last this many seconds the ring pulses in the warning color. 0: never."),
                    }),
                    start = Box(2.5, "Start a timer", {
                        one = Execute(1, "1 minute", function() ns.StartTimer(60) end, "Start a 1 minute timer."),
                        five = Execute(2, "5 minutes", function() ns.StartTimer(300) end, "Start a 5 minute timer."),
                        ten = Execute(3, "10 minutes", function() ns.StartTimer(600) end, "Start a 10 minute timer."),
                        stop = Execute(4, "Stop", function() ns.StopTimer() end, "Stop the running timer."),
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "timerColors", "fill", "Counting down", "Ring color while time is left."),
                        warn = Color(2, "timerColors", "warn", "Almost done", "Color it pulses in near the end."),
                        done = Color(3, "timerColors", "done", "Time's up", "Ring color when time's up."),
                    }),
                    size = SizeBox(4, "timer", "timer ring", "Offset from the center of the screen."),
                }))
            tab.args.size.args.hold.desc = "How long \"Time's up!\" stays before the ring fades."
            return tab
        end },
})
