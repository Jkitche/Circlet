-- Circlet: Campfire ring: resting at a camp until you're Well Rested.
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall, Clean, CleanNumber = ns.db, ns.CreateLiveRing, ns.SafeCall, ns.Clean, ns.CleanNumber

---------------------------------------------------------------------------
-- Campfire ring
---------------------------------------------------------------------------
-- Sitting at a campsite gives you the Welcoming Campfire buff, which counts down while you
-- rest; when it's done you're Well Rested and get the camp's buffs. While Welcoming
-- Campfire is on you, the ring fills as its timer runs and counts down what's left. When
-- Well Rested shows up (soon after Welcoming Campfire), it turns "Well Rested!" and bursts.
-- Stand up early and it fades out showing how far you got. Well Rested on its own (a
-- sleeping bag gives it too) doesn't show the ring.
-- With campFx on: the middle flickers with firelight and embers rise up through the ring.
-- Worked out from the time, so edit mode's sample plays it too.
--
-- The buffs are found by name (English; this client's own names when they can be read).
-- When a buff's times are secret, it's timed from when it showed up over DEFAULT_DURATION.

local WELCOMING = { ["Welcoming Campfire"] = true }
local RESTED = { ["Well Rested"] = true, ["Well-Rested"] = true }
local DEFAULT_DURATION = 60 -- seconds of rest before the camp's buffs (the usual minute)
local RESTED_WINDOW = 5     -- Well Rested this soon after Welcoming Campfire ends counts as finishing it
local EMBERS = 14

local welcome, rested, dirty = nil, false, true -- welcome: { icon, duration, expires }
local since         -- GetTime() when Welcoming Campfire was first seen
local lastWelcome   -- GetTime() when Welcoming Campfire was last on you (for RESTED_WINDOW)
local doneAt        -- when you became Well Rested from this rest (for the burst)
local doneIcon

local function Scan()
    dirty = false
    local found, isRested = nil, false
    for i = 1, 40 do
        local name, icon, duration, expires
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = SafeCall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not a then break end
            name, icon, duration, expires = a.name, a.icon, a.duration, a.expirationTime
        elseif UnitBuff then
            local n, ic, _, _, dur, exp = SafeCall(UnitBuff, "player", i)
            if not n then break end
            name, icon, duration, expires = n, ic, dur, exp
        else
            break
        end
        name = Clean(name)
        if type(name) == "string" then
            if WELCOMING[name] and not found then
                found = { icon = Clean(icon), duration = CleanNumber(duration), expires = CleanNumber(expires) }
            elseif RESTED[name] then
                isRested = true
            end
        end
    end
    local now = GetTime()
    if found then
        if found.expires and found.duration then
            local start = found.expires - found.duration
            if not since or math.abs(since - start) > 0.5 then since = start end
        elseif not welcome then
            since = now
        end
        lastWelcome = now
        if not welcome then doneAt = nil end -- a new rest
    elseif welcome then
        lastWelcome = now -- it was on you until just now
    end
    -- Well Rested from this rest: it arrived while (or just after) Welcoming Campfire ran.
    if isRested and not rested and lastWelcome and now - lastWelcome <= RESTED_WINDOW then
        doneAt = now
        doneIcon = (found or welcome or {}).icon
    end
    if not found then since = nil end
    welcome, rested = found, isRested
end

-- How far through the rest (0..1) and the seconds left.
local function Progress(now)
    local duration = welcome.duration and welcome.duration > 0 and welcome.duration or DEFAULT_DURATION
    local start = since or now
    local left = welcome.expires and math.max(0, welcome.expires - now) or math.max(0, start + duration - now)
    return math.max(0, math.min(1, 1 - left / duration)), left
end

local function State(frac, left, icon, finishedAt)
    local c = db.campColors
    local st = { camp = true, frac = frac, icon = icon, hold = 1.5, title = "Resting", color = c.fill }
    if finishedAt then
        st.frac, st.value, st.title = 1, "", "Campfire"
        st.color, st.label, st.labelColor = c.rested, "Well Rested!", c.rested
        st.doneAt = finishedAt
        return st
    end
    st.value = left >= 60 and string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
        or string.format("%ds", math.ceil(left - 0.05))
    st.label = "By the fire"
    return st
end

local SAMPLE_ICON = "Interface\\Icons\\Spell_Fire_Fire"
local FINISHED_SHOW = 3 -- seconds the "Well Rested!" ring stays up

local campRing = CreateLiveRing({
    key = "camp",
    read = function(now)
        if dirty then Scan() end
        if doneAt then -- Well Rested (even if Welcoming Campfire is still ticking down)
            if now - doneAt < FINISHED_SHOW then return State(1, 0, doneIcon, doneAt) end
            return nil
        end
        if welcome then
            local frac, left = Progress(now)
            return State(frac, left, welcome.icon)
        end
        return nil
    end,
    sample = function(t)
        -- A rest: a minute squeezed into 8 seconds, then Well Rested.
        local cycle = t % 11
        local start = t - cycle
        if cycle < 8 then return State(cycle / 8, 60 - cycle * 7.5, SAMPLE_ICON) end
        return State(1, 0, SAMPLE_ICON, start + 8)
    end,
    decorate = function(st, frame, geom) ns.DrawCampFx(st, frame, geom) end,
})

---------------------------------------------------------------------------
-- The animation: firelight flickering in the middle, embers rising through the ring
---------------------------------------------------------------------------
local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR_TEX = "Interface\\Cooldown\\star4"

local function Mix(a, b, t) return a + (b - a) * t end

local fx -- made on first use

local function Build(frame)
    fx = { embers = {} }
    fx.glow = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    if fx.glow:SetTexture(GLOW_TEX) == false then fx.glow:SetTexture(STAR_TEX) end
    fx.glow:SetBlendMode("ADD")
    fx.glow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    fx.glow:Hide()
    for i = 1, EMBERS do
        local t = frame:CreateTexture(nil, "ARTWORK", nil, 3)
        t:SetTexture(STAR_TEX)
        t:SetBlendMode("ADD")
        t:Hide()
        -- Fixed per ember so they don't move in lockstep.
        fx.embers[i] = { tex = t, speed = 1 / (1.6 + (i * 0.37) % 1.2), phase = (i * 0.618) % 1,
                         side = ((i * 0.437) % 1) * 2 - 1, size = 0.6 + (i * 0.53) % 0.7 }
    end
end

local function HideAll()
    if not fx then return end
    fx.glow:Hide()
    for _, e in ipairs(fx.embers) do e.tex:Hide() end
end

local function DrawCampFx(st, frame, geom)
    if not (st and st.camp and db.campFx) or not geom or geom.R <= 0 then return HideAll() end
    if not fx then Build(frame) end
    local now = GetTime()
    local ri = math.max(4, geom.R - geom.T / 2)
    local ro = geom.R + geom.T / 2

    -- Firelight: a warm glow low in the middle, flickering.
    local flicker = 0.8 + 0.1 * (math.sin(now * 9.7) + math.sin(now * 14.3 + 1.1))
    local size = ri * 2.1 * (0.95 + 0.05 * flicker)
    fx.glow:ClearAllPoints()
    fx.glow:SetPoint("CENTER", frame, "CENTER", 0, -ri * 0.25)
    fx.glow:SetSize(size, size)
    fx.glow:SetVertexColor(1, 0.55, 0.15)
    fx.glow:SetAlpha(0.55 * flicker)
    fx.glow:Show()

    -- Embers: rising from the bottom of the hollow, drifting and flickering from yellow to
    -- deep red, out past the top of the ring.
    for i, e in ipairs(fx.embers) do
        local u = (now * e.speed * 0.8 + e.phase) % 1
        local y = -ri * 0.8 + u * (ri * 0.8 + ro * 1.4)
        local spread = math.sqrt(math.max(0, 1 - (math.min(math.abs(y), ri) / ri) ^ 2))
        local x = e.side * ri * 0.55 * math.max(spread, 0.35) + math.sin(now * 3 + i * 1.7) * ri * 0.08 * u
        local r, g, b = 1, Mix(0.85, 0.25, u), Mix(0.4, 0.05, u)
        local twinkle = 0.75 + 0.25 * math.sin(now * 12 + i * 2.3)
        local s = ri * 0.2 * e.size * (1 - 0.5 * u)
        e.tex:ClearAllPoints()
        e.tex:SetPoint("CENTER", frame, "CENTER", x, y)
        e.tex:SetSize(s, s)
        e.tex:SetVertexColor(r, g, b)
        e.tex:SetAlpha(math.min(1, u * 6) * (1 - u ^ 2) * twinkle)
        e.tex:Show()
    end
end
ns.DrawCampFx = DrawCampFx

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen({ "UNIT_AURA:player", "PLAYER_ENTERING_WORLD" }, function() dirty = true end)

-- Shared with the files loaded after this one.
ns.campRing = campRing
ns.PreviewCampRing = function() campRing.Preview(11) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "camp", name = "Campfire", order = 11.6,
    iconBg = true, -- the icon can be the ring's background (Core/Settings.lua, UI/OptionsKit.lua)
    ring = campRing,
    preview = ns.PreviewCampRing, slash = { "camp", "campfire" }, help = "preview the campfire ring",
    toggle = { "Campfire ring", "Resting at a campfire until you're Well Rested." },
    defaults = {
        -- Campfire ring: while you rest at a camp. Left of the food & drink ring.
        campEnabled   = true,
        campFx        = true, -- firelight and rising embers
        campSize      = 110,
        campThickness = 11,
        campOpacity   = 100,
        campX         = -510,
        campFromTop   = 260,
        campHold      = 2,
        campStyle     = "smooth",
        campBorder    = 2,
        campColors = {
            fill   = { r = 1.00, g = 0.55, b = 0.20 },
            rested = { r = 0.35, g = 0.90, b = 0.40 },
        },
    },
    page = { folder = "status", order = 4.6, build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(10.7, "Campfire", "Campfire Ring",
                "While you rest at a campfire (the Welcoming Campfire buff), the ring fills and counts down "
                .. "until you're Well Rested, then bursts. Stand up early and it fades out showing how far you got.",
                MergeTop(TopRow("camp", "campfire ring", ns.PreviewCampRing,
                    "Show a sample rest. Also /circ camp."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "campEnabled", "Show campfire ring",
                            "Show the ring while you rest at a campfire."),
                        fx = Toggle(2, "campFx", "Firelight and embers",
                            "A flickering glow in the middle of the ring with embers rising through it."),
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "campColors", "fill", "Resting", "Ring color while you rest."),
                        rested = Color(2, "campColors", "rested", "Well Rested", "Ring and label color once you're Well Rested."),
                    }),
                    size = SizeBox(4, "camp", "campfire ring",
                        "Offset from the center of the screen. By default it sits left of the food & drink ring."),
                }))
            tab.args.size.args.hold.desc = "How long the ring stays after you stand up."
            return tab
        end },
})
