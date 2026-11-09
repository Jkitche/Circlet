-- Circlet: Timed quest ring: counts down escort and other timed quests.
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing, FormatTime = ns.db, ns.IsSecret, ns.CreateLiveRing, ns.FormatTime
local SafeCall = ns.SafeCall

---------------------------------------------------------------------------
-- Timed quest ring
---------------------------------------------------------------------------
-- Up for as long as you have a timed quest. The ring drains as time runs out, turns
-- the warning color in the last stretch, and shows the quest with the least time
-- left (with "+1 more" if there are others). By default it sits on the right, by
-- the quest list.

-- Total time per quest, for the fill: from C_QuestLog.GetTimeAllowed when the client
-- has it, otherwise the most time we've seen left on it.
local totals = {}

local function Num(v)
    return type(v) == "number" and not IsSecret(v) and v or nil
end

-- Every timed quest in the log: { title, left, total }.
local function ReadTimedQuests()
    local list = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo and C_QuestLog.GetTimeAllowed then
        local n = SafeCall(C_QuestLog.GetNumQuestLogEntries) or 0
        for i = 1, n do
            local info = SafeCall(C_QuestLog.GetInfo, i)
            if info and not info.isHeader and info.questID then
                local total, elapsed = SafeCall(C_QuestLog.GetTimeAllowed, info.questID)
                total, elapsed = Num(total), Num(elapsed)
                if total and elapsed and total > 0 then
                    table.insert(list, { title = info.title, left = total - elapsed, total = total })
                end
            end
        end
    end
    -- Older API: GetQuestTimers gives the time left on each timed quest.
    if #list == 0 and GetQuestTimers then
        local timers = { SafeCall(GetQuestTimers) }
        for i, left in ipairs(timers) do
            left = Num(left)
            if left then
                local index = GetQuestIndexForTimer and SafeCall(GetQuestIndexForTimer, i)
                local title = index and GetQuestLogTitle and SafeCall(GetQuestLogTitle, index)
                title = (type(title) == "string" and not IsSecret(title)) and title or "Timed quest"
                totals[title] = math.max(totals[title] or 0, left)
                table.insert(list, { title = title, left = left, total = totals[title] })
            end
        end
    end
    return list
end

local function Warn(left, total)
    return left <= (db.timedWarn or 60) or (total and left <= total * 0.1)
end

local function State(title, left, total, more)
    local warn = Warn(left, total)
    local c = warn and db.timedColors.warn or db.timedColors.fill
    return {
        title = title,
        value = FormatTime(left),
        label = more > 0 and ("+" .. more .. " more timed") or (left > 0 and "remaining" or "Time's up"),
        labelColor = warn and db.timedColors.warn or nil,
        frac = total and total > 0 and math.max(0, math.min(1, left / total)) or 1,
        color = c,
        hold = left <= 0 and (db.timedHold or 3) or 0,
    }
end

local timedRing = CreateLiveRing({
    key = "timed",
    read = function()
        local list = ReadTimedQuests()
        if #list == 0 then return nil end
        table.sort(list, function(a, b) return a.left < b.left end)
        local q = list[1]
        return State(q.title, q.left, q.total, #list - 1)
    end,
    sample = function(t)
        -- 2:30 escort counting down fast, into the warning range.
        local left = math.max(0, 150 - (t * 14) % 160)
        return State("Protecting the Shipment", left, 150, 0)
    end,
})

local function PreviewTimedRing() timedRing.Preview(12) end

-- Shared with the files loaded after this one.
ns.timedRing = timedRing
ns.PreviewTimedRing = PreviewTimedRing

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "timed", name = "Timed quest", order = 9,
    ring = timedRing,
    preview = PreviewTimedRing, slash = { "timed", "timer" }, help = "preview the timed quest ring",
    toggle = { "Timed quest ring", "Counts down escort and other timed quests." },
    gameBar = "the game's quest timer",
    defaults = {
        -- Timed quest ring: escort and other timed quests. Sits on the right, by the quest list.
        timedEnabled   = true,
        timedWarn      = 60, -- seconds left when it turns the warning color
        timedSize      = 110,
        timedThickness = 11,
        timedOpacity   = 100,
        timedX         = 340,  -- right of the flight ring
        timedFromTop   = 260,
        timedHold      = 3,
        timedStyle     = "smooth",
        timedBorder    = 2, -- black border width (0 = none)
        timedColors = {
            fill = { r = 0.95, g = 0.80, b = 0.25 },
            warn = { r = 0.95, g = 0.25, b = 0.15 },
        },
    },
    page = { folder = "status", order = 2, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(9, "Timed", "Timed Quest Ring",
                "Up while you have an escort or other timed quest: it drains as time runs out and turns the warning "
                .. "color near the end. With more than one, it shows the one with the least time left.",
                MergeTop(TopRow("timed", "timed quest ring", ns.PreviewTimedRing,
                    "Show a sample timer running down into the warning range. Also /sq timed."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "timedEnabled", "Show timed quest ring", "Count down timed quests."),
                        warn = Range(2, "timedWarn", "Warn at (seconds left)", 10, 300, 10,
                            "Below this much time (or the last 10% of the quest's time) the ring turns the warning color."),
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "timedColors", "fill", "Time left", "Ring color while there's time."),
                        warn = Color(2, "timedColors", "warn", "Running out", "Ring and label color near the end."),
                    }),
                    size = SizeBox(4, "timed", "timed quest ring",
                        "Offset from the center of the screen. The default sits on the right, by the quest list."),
                }))
            tab.args.size.args.hold.desc = "How long the ring stays after the time runs out."
            return tab
        end },
})
