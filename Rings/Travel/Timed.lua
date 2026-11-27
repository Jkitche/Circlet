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

local function Num(v) return type(v) == "number" and not IsSecret(v) and v or nil end

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

local function Warn(left, total) return left <= (db.timedWarn or 60) or (total and left <= total * 0.1) end

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
        timed = true,
        timedWarn = warn,
        timesUp = left <= 0,
    }
end

---------------------------------------------------------------------------
-- The animation: an hourglass
---------------------------------------------------------------------------
-- With timedFx on, the ring is the glass: as its time drains, sand trickles from the end
-- of the fill down into the hollow and piles up in its bottom (behind the text), up to
-- about half way when time runs out. In the warning stretch the sand reddens and pours
-- faster; when time's up the stream stops and the pile flashes. Worked out from the time
-- and the fill, so edit mode's sample plays it too.
local SAND = { r = 0.88, g = 0.72, b = 0.42 }
local CHORDS, GRAINS = 16, 14
local timesUpAt -- when the current ring's time ran out (for the flash)
local sand -- made on first use

local function BuildSand(frame)
    sand = { chords = {}, grains = {} }
    for i = 1, CHORDS do
        local l = frame:CreateLine(nil, "BACKGROUND", nil, 2)
        if l.SetSnapToPixelGrid then
            l:SetSnapToPixelGrid(false)
            l:SetTexelSnappingBias(0)
        end
        l:Hide()
        sand.chords[i] = l
    end
    for i = 1, GRAINS do
        local t = frame:CreateTexture(nil, "ARTWORK", nil, 3)
        t:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        t:Hide()
        sand.grains[i] = t
    end
end

local function HideSand()
    if not sand then return end
    for _, l in ipairs(sand.chords) do
        l:Hide()
    end
    for _, t in ipairs(sand.grains) do
        t:Hide()
    end
end

local function DrawSand(st, frame, geom)
    if not (st and st.timed and db.timedFx) or not geom or geom.R <= 0 then
        timesUpAt = nil
        return HideSand()
    end
    if not sand then BuildSand(frame) end
    local now = GetTime()
    local T = math.max(3, geom.T)
    local ri = math.max(4, geom.R - geom.T / 2) - 1
    local frac = st.frac or 1
    local warn = st.timedWarn and 1 or 0
    if st.timesUp then
        timesUpAt = timesUpAt or now
    else
        timesUpAt = nil
    end
    local flash = timesUpAt and math.max(0, math.cos(math.pi * 3 * math.min(1, (now - timesUpAt) / 1.2))) or 0
    local wc = db.timedColors.warn
    local r = SAND.r + (wc.r - SAND.r) * warn * 0.5
    local g = SAND.g + (wc.g - SAND.g) * warn * 0.5
    local b = SAND.b + (wc.b - SAND.b) * warn * 0.5

    -- The pile: a segment of the hollow from the bottom up, in horizontal strips; its top
    -- strip a little brighter, like the light on the sand's surface.
    local h = (1 - frac) * ri
    local surface = -ri + h
    local step = h / CHORDS
    for i, l in ipairs(sand.chords) do
        local y = -ri + step * (i - 0.5)
        local half = math.sqrt(math.max(0, ri * ri - y * y)) * 0.96
        if h > 0.5 and half > 0.5 then
            local top = i == CHORDS
            local k = top and 1.25 or 1
            l:SetStartPoint("CENTER", frame, -half, y)
            l:SetEndPoint("CENTER", frame, half, y)
            l:SetThickness(step + 0.6)
            l:SetColorTexture(
                math.min(1, r * k + flash * 0.5),
                math.min(1, g * k + flash * 0.5),
                math.min(1, b * k + flash * 0.4),
                (top and 0.5 or 0.32) + flash * 0.3
            )
            l:Show()
        else
            l:Hide()
        end
    end

    -- The stream: grains falling from the end of the fill, drawn in toward the middle as they
    -- fall, onto the pile.
    local tx, ty = ns.RingPoint(geom, frac)
    local pouring = not st.timesUp and frac > 0
    local speed = 1.1 + 0.9 * warn
    for i, t in ipairs(sand.grains) do
        if pouring and ty > surface then
            local u = (now * speed + i / GRAINS) % 1
            local fall = u * u
            local x = tx + (tx * 0.15 - tx) * u + math.sin(i * 2.3 + now * 3) * T * 0.15
            local y = ty + (surface - ty) * fall
            local s = math.max(1.5, T * 0.32)
            t:ClearAllPoints()
            t:SetPoint("CENTER", frame, "CENTER", x, y)
            t:SetSize(s, s)
            t:SetVertexColor(math.min(1, r * 1.15), math.min(1, g * 1.15), math.min(1, b * 1.15))
            t:SetAlpha(math.min(1, u * 8) * 0.9)
            t:Show()
        else
            t:Hide()
        end
    end
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
    decorate = DrawSand,
})

local function PreviewTimedRing() timedRing.Preview(12) end

-- Shared with the files loaded after this one.
ns.timedRing = timedRing
ns.PreviewTimedRing = PreviewTimedRing
ns.TimedSandParts = function() return sand end -- for the tests

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "timed",
    name = "Timed quest",
    order = 9,
    ring = timedRing,
    preview = PreviewTimedRing,
    slash = { "timed" },
    help = "preview the timed quest ring",
    toggle = { "Timed quest ring", "Counts down escort and other timed quests." },
    gameBar = "the game's quest timer",
    defaults = {
        -- Timed quest ring: escort and other timed quests. Sits on the right, by the quest list.
        timedEnabled = true,
        timedWarn = 60, -- seconds left when it turns the warning color
        timedFx = true, -- the hourglass: sand pouring from the fill and piling up in the middle
        timedSize = 110,
        timedThickness = 11,
        timedOpacity = 100,
        timedX = 340, -- right of the flight ring
        timedFromTop = 260,
        timedHold = 3,
        timedStyle = "smooth",
        timedBorder = 2, -- black border width (0 = none)
        timedColors = {
            fill = { r = 0.95, g = 0.80, b = 0.25 },
            warn = { r = 0.95, g = 0.25, b = 0.15 },
        },
    },
    page = {
        folder = "travel",
        order = 2,
        build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(
                9,
                "Timed quests",
                "Timed Quest Ring",
                "Up while you have an escort or other timed quest: it drains as time runs out and turns the warning "
                    .. "color near the end. With more than one, it shows the one with the least time left.",
                MergeTop(
                    TopRow(
                        "timed",
                        "timed quest ring",
                        ns.PreviewTimedRing,
                        "Show a sample timer running down into the warning range. Also /circ timed."
                    ),
                    {
                        general = Box(2, "General", {
                            enabled = Toggle(1, "timedEnabled", "Show timed quest ring", "Count down timed quests."),
                            warn = Range(
                                2,
                                "timedWarn",
                                "Warn at (seconds left)",
                                10,
                                300,
                                10,
                                "Below this much time (or the last 10% of the quest's time) the ring turns the warning color."
                            ),
                            fx = Toggle(
                                3,
                                "timedFx",
                                "Animations",
                                "An hourglass: sand trickles from the end of the fill and piles up in the middle of the ring "
                                    .. "as time runs out, reddening and pouring faster near the end."
                            ),
                        }),
                        colors = Box(3, "Colors", {
                            fill = Color(1, "timedColors", "fill", "Time left", "Ring color while there's time."),
                            warn = Color(2, "timedColors", "warn", "Running out", "Ring and label color near the end."),
                        }),
                        size = SizeBox(
                            4,
                            "timed",
                            "timed quest ring",
                            "Offset from the center of the screen. The default sits on the right, by the quest list."
                        ),
                    }
                )
            )
            tab.args.size.args.hold.desc = "How long the ring stays after the time runs out."
            return tab
        end,
    },
})
