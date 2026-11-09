-- Circlet: Breath ring: the game's breath, fatigue and Feign Death timers.
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing = ns.db, ns.IsSecret, ns.CreateLiveRing
local SafeCall, CleanNumber = ns.SafeCall, ns.CleanNumber

---------------------------------------------------------------------------
-- Breath ring
---------------------------------------------------------------------------
-- Underwater the ring drains with your breath, turning orange and then red as it runs
-- low, with bubbles rising off its edge (like the XP ring's resting zZZ). Surfacing, it
-- fills back up and goes away. Deep-water fatigue and a hunter's Feign Death use the
-- same timers and show the same way, without the bubbles.

local KINDS = {
    BREATH = { title = "Breath", label = "Underwater" },
    EXHAUSTION = { title = "Fatigue", label = "Turn back!" },
    FEIGNDEATH = { title = "Feign Death", label = "Playing dead" },
}

-- Timers as the events report them: name -> { value, max, scale, paused, at }.
-- value/max in seconds; scale < 0 while it's running down, > 0 while it refills.
local timers = {}

local function Track(name, value, maxValue, scale, paused)
    if type(name) ~= "string" or IsSecret(name) or not KINDS[name] then return end
    value, maxValue, scale = CleanNumber(value), CleanNumber(maxValue), CleanNumber(scale)
    if not (value and maxValue and maxValue > 0) then return end
    timers[name] = { value = value / 1000, max = maxValue / 1000, scale = scale or -1,
                     paused = paused and paused ~= 0 and paused ~= false, at = GetTime() }
end

-- Seconds left on a timer right now: the game's own count when it gives one, else ours.
local function Remaining(name, t, now)
    local ms = CleanNumber(SafeCall(GetMirrorTimerProgress, name))
    if ms then return math.max(0, math.min(t.max, ms / 1000)) end
    if t.paused then return t.value end
    return math.max(0, math.min(t.max, t.value + t.scale * (now - t.at)))
end

local bubbling = false -- the bubbles rise while this is set (read by the bubbles below)

local function State(name, left, maxLeft, refilling)
    local kind, c = KINDS[name], db.breathColors
    local frac = maxLeft > 0 and left / maxLeft or 0
    local st = { title = kind.title, frac = frac, hold = 1.5 }
    st.value = left >= 60 and string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
        or string.format("%ds", math.ceil(left))
    if name == "EXHAUSTION" then
        st.color = c.fatigue
    elseif name == "FEIGNDEATH" then
        st.color = c.feign
    elseif frac <= 0.15 then
        st.color = c.critical
    elseif frac <= 0.3 then
        st.color = c.low
    else
        st.color = c.fill
    end
    if refilling then
        st.label, st.color = "Catching your breath", c.fill
    else
        st.label = kind.label
    end
    if frac <= 0.15 and not refilling then st.labelColor = c.critical end
    bubbling = name == "BREATH" and not refilling and db.breathBubbles
    return st
end

local breathRing = CreateLiveRing({
    key = "breath",
    read = function(now)
        -- The most urgent running timer: breath first, then fatigue, then Feign Death.
        for _, name in ipairs({ "BREATH", "EXHAUSTION", "FEIGNDEATH" }) do
            local t = timers[name]
            if t then
                local left = Remaining(name, t, now)
                local refilling = t.scale > 0
                if refilling and left >= t.max - 0.05 then
                    timers[name] = nil -- full again: the game stops it shortly
                else
                    return State(name, left, t.max, refilling)
                end
            end
        end
        bubbling = false
        return nil
    end,
    sample = function(t)
        -- A dive: breath drains from 60s to 8s, then refills on surfacing.
        local cycle = t % 10
        if cycle < 7 then return State("BREATH", 60 - cycle * 7.4, 60, false) end
        return State("BREATH", 8 + (cycle - 7) * 17, 60, true)
    end,
})

---------------------------------------------------------------------------
-- Bubbles: little rings rising and wobbling off the top-right of the ring, the way
-- the resting zZZ sits on the XP ring. The game has no bubble animation of its own
-- (its breath bar is a plain bar), so these are drawn.
---------------------------------------------------------------------------
local BUBBLES, SIDES, CYCLE = 4, 12, 2.2
local holder = CreateFrame("Frame", nil, breathRing.frame)
holder:SetAllPoints()

local bubbles = {}
for i = 1, BUBBLES do
    local b = CreateFrame("Frame", nil, holder)
    b:SetSize(1, 1)
    b.lines = {}
    for s = 1, SIDES do
        local line = b:CreateLine(nil, "OVERLAY", nil, 6)
        if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(false); line:SetTexelSnappingBias(0) end
        line:SetColorTexture(0.80, 0.93, 1.00, 0.9)
        b.lines[s] = line
    end
    -- A glint on the upper left, like light on a bubble.
    b.glint = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.glint:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    b.glint:SetVertexColor(1, 1, 1, 0.9)
    b.phase = (i - 1) / BUBBLES
    b.wobble = (i % 2 == 0) and 1 or -1
    b:Hide()
    bubbles[i] = b
end

local function ShapeBubble(b, r)
    if b.r == r then return end
    b.r = r
    local thick = math.max(1, r * 0.22)
    for s = 1, SIDES do
        local a1, a2 = (s - 1) / SIDES * 2 * math.pi, s / SIDES * 2 * math.pi
        local line = b.lines[s]
        line:SetThickness(thick)
        line:SetStartPoint("CENTER", b, math.cos(a1) * r, math.sin(a1) * r)
        line:SetEndPoint("CENTER", b, math.cos(a2) * r, math.sin(a2) * r)
    end
    b.glint:SetSize(math.max(1.5, r * 0.5), math.max(1.5, r * 0.5))
    b.glint:ClearAllPoints()
    b.glint:SetPoint("CENTER", b, "CENTER", -r * 0.35, r * 0.35)
end

local clock = 0
holder:SetScript("OnUpdate", function(_, elapsed)
    if not bubbling then
        for _, b in ipairs(bubbles) do b:Hide() end
        return
    end
    clock = clock + elapsed
    local radius = (db.breathSize or 110) / 2
    -- Where the bubbles start: up and to the right of the ring, like the zZZ.
    local ox, oy = radius * 0.62, radius * 0.62
    local rise = radius * 0.75
    local base = math.max(2.5, radius * 0.07)
    for i, b in ipairs(bubbles) do
        local p = (clock / CYCLE + b.phase) % 1
        local size = base * (0.7 + 0.6 * p) * (1 + 0.15 * (i % 3))
        ShapeBubble(b, math.floor(size * 2 + 0.5) / 2)
        local x = ox + b.wobble * math.sin(p * math.pi * 3) * radius * 0.06 + (i - 2.5) * radius * 0.05
        local y = oy + p * rise
        b:ClearAllPoints()
        b:SetPoint("CENTER", holder, "CENTER", x, y)
        -- Fade in as it leaves the ring, fade out (pop) near the top.
        b:SetAlpha(p < 0.15 and p / 0.15 or (p > 0.8 and (1 - p) / 0.2 or 1))
        b:Show()
    end
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen({ "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "MIRROR_TIMER_PAUSE", "PLAYER_ENTERING_WORLD" }, function(event, name, value, maxValue, scale, paused)
    if event == "MIRROR_TIMER_START" then
        Track(name, value, maxValue, scale, paused)
    elseif event == "MIRROR_TIMER_STOP" then
        if type(name) == "string" and not IsSecret(name) then timers[name] = nil end
    elseif event == "MIRROR_TIMER_PAUSE" then
        -- Re-read the timers: pausing changes whether they're counting.
        for i = 1, (MIRRORTIMER_NUMTIMERS or 3) do
            local n, v, m, s, p = SafeCall(GetMirrorTimerInfo, i)
            if n and timers[n] then Track(n, v, m, s, p) end
        end
    else
        -- Logging in or zoning: pick up timers already running.
        wipe(timers)
        for i = 1, (MIRRORTIMER_NUMTIMERS or 3) do
            local n, v, m, s, p = SafeCall(GetMirrorTimerInfo, i)
            if n and n ~= "UNKNOWN" then Track(n, v, m, s, p) end
        end
    end
end)

-- Shared with the files loaded after this one.
ns.breathRing = breathRing
ns.PreviewBreathRing = function() breathRing.Preview(12) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "breath", name = "Breath", order = 11,
    ring = breathRing,
    preview = ns.PreviewBreathRing, slash = { "breath", "bubbles" }, help = "preview the breath ring",
    toggle = { "Breath ring", "Breath underwater, deep-water fatigue and Feign Death." },
    gameBar = "the game's breath bar",
    defaults = {
        -- Breath ring: breath, fatigue and Feign Death timers. Shares the corpse ring's
        -- spot (a ghost has no breath to hold).
        breathEnabled   = true,
        breathBubbles   = true, -- bubbles rising off the ring while you hold your breath
        breathSize      = 110,
        breathThickness = 11,
        breathOpacity   = 100,
        breathX         = -170,
        breathFromTop   = 260,
        breathHold      = 2,
        breathStyle     = "smooth",
        breathBorder    = 2,
        breathColors = {
            fill     = { r = 0.35, g = 0.75, b = 1.00 },
            low      = { r = 1.00, g = 0.60, b = 0.15 },
            critical = { r = 1.00, g = 0.20, b = 0.20 },
            fatigue  = { r = 0.85, g = 0.70, b = 0.30 },
            feign    = { r = 0.70, g = 0.70, b = 0.75 },
        },
    },
    page = { folder = "status", order = 4, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(10.5, "Breath", "Breath Ring",
                "Underwater, the ring drains with your breath (orange when it's low, red when it's nearly gone) with "
                .. "bubbles rising off it, then fills back up when you surface. Deep-water fatigue and Feign Death "
                .. "show the same way.",
                MergeTop(TopRow("breath", "breath ring", ns.PreviewBreathRing,
                    "Show a sample dive. Also /sq breath."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "breathEnabled", "Show breath ring", "Show the ring while a breath, fatigue or Feign Death timer runs."),
                        bubbles = Toggle(2, "breathBubbles", "Bubbles", "Little bubbles rising off the ring while you hold your breath."),
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "breathColors", "fill", "Breath", "Ring color with plenty of breath left, and while it refills."),
                        low = Color(2, "breathColors", "low", "Running low", "Ring color under 30% breath."),
                        critical = Color(3, "breathColors", "critical", "Nearly gone", "Ring color under 15% breath."),
                        fatigue = Color(4, "breathColors", "fatigue", "Fatigue", "Ring color in deep water, before fatigue sets in."),
                        feign = Color(5, "breathColors", "feign", "Feign Death", "Ring color while you play dead."),
                    }),
                    size = SizeBox(4, "breath", "breath ring",
                        "Offset from the center of the screen. By default it shares the corpse ring's spot."),
                }))
            tab.args.size.args.hold.desc = "How long the ring stays after the timer ends."
            return tab
        end },
})
