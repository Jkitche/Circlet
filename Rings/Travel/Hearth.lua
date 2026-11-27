-- Circlet: Hearthstone ring: casting your Hearthstone home, with a swirling portal.
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall, Clean = ns.db, ns.CreateLiveRing, ns.SafeCall, ns.Clean

---------------------------------------------------------------------------
-- Hearthstone ring
---------------------------------------------------------------------------
-- While you cast Hearthstone (or a shaman's Astral Recall) the ring fills over the cast,
-- counting down, with the stone's icon and the place you're bound to. The cast ring leaves
-- these casts to it. When the cast goes off it says "Home!" and bursts; interrupted or
-- moved, it says so and fades out showing how far it got.
--
-- With hearthFx on, a portal swirls in the middle: three spiral arms of arcane motes turn
-- and sink into its heart, two comets with tails race round the ring, and a glow breathes
-- under it all, everything faster and brighter as the cast nears its end. When it goes off
-- the swirl collapses into a flash, a shockwave rolls outward and the motes fly apart.
-- Interrupted, it slows and scatters. Worked out from the time, so previews play it too.

local HEARTH_SPELLS = { [8690] = true, [556] = true } -- Hearthstone, Astral Recall
local DEFAULT_CAST = 10 -- seconds, when the cast's own timing can't be read
local DONE_SHOW = 2.2 -- seconds "Home!" stays up
local LOST_SHOW = 1.5 -- seconds an interrupted cast stays up

local hearthNames -- built on first use, once spell names can be read
local function IsHearth(spellID)
    spellID = Clean(spellID)
    if type(spellID) ~= "number" then return false end
    if HEARTH_SPELLS[spellID] then return true end
    if not hearthNames then
        local names, any = {}, false
        for id in pairs(HEARTH_SPELLS) do
            local n = ns.SpellName(id)
            if n then
                names[n], any = true, true
            end
        end
        if not any then return false end
        hearthNames = names
    end
    local name = ns.SpellName(spellID)
    return name ~= nil and hearthNames[name] == true
end

local cast -- { guid, spellID, icon, start, finish, endedAt, how, lost }

local function BindLocation()
    local loc = GetBindLocation and Clean(SafeCall(GetBindLocation))
    return type(loc) == "string" and loc ~= "" and loc or nil
end

local function Begin(spellID, guid)
    spellID = Clean(spellID)
    local now = GetTime()
    local start, finish = now, now + DEFAULT_CAST
    local _, _, _, startMS, endMS = SafeCall(UnitCastingInfo, "player")
    startMS, endMS = Clean(startMS), Clean(endMS)
    if type(startMS) == "number" and type(endMS) == "number" and endMS > startMS then
        start, finish = startMS / 1000, endMS / 1000
    end
    cast = {
        guid = Clean(guid),
        spellID = spellID,
        icon = ns.SpellIcon(spellID),
        start = start,
        finish = finish,
        name = ns.SpellName(spellID),
        home = BindLocation(),
    }
end

local function Finish(how)
    if not cast or cast.endedAt then return end
    local now = GetTime()
    cast.how, cast.endedAt = how, now
    if how ~= "done" then cast.lost = math.max(0, math.min(1, (now - cast.start) / (cast.finish - cast.start))) end
end

local function Ours(guid)
    if not cast or cast.endedAt then return false end
    guid = Clean(guid)
    return not (guid and cast.guid) or guid == cast.guid
end

-- phase: "cast" (frac 0..1, left seconds), "done" or "lost" (age: seconds since it ended).
-- doneAt: GetTime() it went off (for the icon's burst; held still from frame to frame).
local function State(phase, frac, left, age, icon, home, doneAt, name)
    local c = db.hearthColors
    local st = {
        hearth = true,
        phase = phase,
        frac = frac,
        age = age,
        icon = icon,
        hold = 0.6,
        title = name or "Hearthstone",
        color = c.fill,
    }
    if phase == "cast" then
        st.value = string.format("%.1fs", left)
        st.label = home or "Going home"
    elseif phase == "done" then
        st.frac, st.value, st.label = 1, "", "Home!"
        st.color, st.labelColor = c.home, c.home
        st.doneAt = doneAt
    else
        st.value, st.label = "", "Interrupted"
        st.labelColor = { r = 1, g = 0.35, b = 0.3 }
    end
    return st
end

local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_Rune_01"
local SAMPLE_CAST = 7 -- a sample's ten-second cast plays in this many seconds

local hearthRing = CreateLiveRing({
    key = "hearth",
    read = function(now)
        local h = cast
        if not h then return nil end
        if h.endedAt then
            local age = now - h.endedAt
            if h.how == "done" then
                if age < DONE_SHOW then return State("done", 1, 0, age, h.icon, h.home, h.endedAt, h.name) end
            elseif age < LOST_SHOW then
                return State("lost", h.lost or 0, 0, age, h.icon, h.home, nil, h.name)
            end
            cast = nil
            return nil
        end
        local span = h.finish - h.start
        local frac = math.max(0, math.min(1, (now - h.start) / span))
        if now > h.finish + 3 then
            cast = nil
            return nil
        end -- never heard how it ended
        return State("cast", frac, math.max(0, h.finish - now), nil, h.icon, h.home, nil, h.name)
    end,
    sample = function(t)
        local cycle = t % (SAMPLE_CAST + DONE_SHOW + 0.8)
        if cycle < SAMPLE_CAST then
            local frac = cycle / SAMPLE_CAST
            return State("cast", frac, DEFAULT_CAST * (1 - frac), nil, SAMPLE_ICON, "Goldshire")
        end
        local age = math.min(cycle - SAMPLE_CAST, DONE_SHOW)
        return State("done", 1, 0, age, SAMPLE_ICON, nil, math.floor((GetTime() - age) * 20 + 0.5) / 20)
    end,
    decorate = function(st, frame, geom) ns.DrawHearthFx(st, frame, geom) end,
})

---------------------------------------------------------------------------
-- The animation: a swirling portal
---------------------------------------------------------------------------
local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR_TEX = "Interface\\Cooldown\\star4"
local ARMS, PER_ARM = 3, 10
local COMETS, TAIL = 2, 7
local TAU = 2 * math.pi

local VIOLET = { r = 0.70, g = 0.40, b = 1.00 }
local function Mix(a, b, t) return a + (b - a) * t end
local function MixC(c1, c2, t) return Mix(c1.r, c2.r, t), Mix(c1.g, c2.g, t), Mix(c1.b, c2.b, t) end

local fx -- made on first use

local function Tex(frame, layer, sub, glow)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    if not glow or t:SetTexture(GLOW_TEX) == false then t:SetTexture(STAR_TEX) end
    t:SetBlendMode("ADD")
    t:Hide()
    return t
end

local function BuildFx(frame)
    fx = { motes = {}, comets = {}, spin = 0, orbit = 0, last = nil }
    fx.glow = Tex(frame, "BACKGROUND", -5, true)
    fx.core = Tex(frame, "ARTWORK", 2, true)
    fx.wave = Tex(frame, "OVERLAY", 2, true)
    for i = 1, ARMS * PER_ARM do
        fx.motes[i] = {
            tex = Tex(frame, "ARTWORK", 3),
            arm = (i - 1) % ARMS,
            k = math.floor((i - 1) / ARMS) / PER_ARM,
            size = 0.7 + (i * 0.53) % 0.6,
            wobble = (i * 0.37) % 1,
        }
    end
    for c = 1, COMETS do
        local comet = { offset = (c - 1) / COMETS, parts = {} }
        for j = 1, TAIL do
            comet.parts[j] = Tex(frame, "OVERLAY", 3)
        end
        fx.comets[c] = comet
    end
end

local function HideFx()
    if not fx then return end
    fx.glow:Hide()
    fx.core:Hide()
    fx.wave:Hide()
    for _, m in ipairs(fx.motes) do
        m.tex:Hide()
    end
    for _, c in ipairs(fx.comets) do
        for _, p in ipairs(c.parts) do
            p:Hide()
        end
    end
    fx.last = nil
end

local function Put(tex, frame, x, y, size, r, g, b, a)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", frame, "CENTER", x, y)
    tex:SetSize(size, size)
    tex:SetVertexColor(r, g, b)
    tex:SetAlpha(math.max(0, math.min(1, a)))
    tex:Show()
end

local function DrawHearthFx(st, frame, geom)
    if not (st and st.hearth and db.hearthFx) or not geom or geom.R <= 0 then return HideFx() end
    if not fx then BuildFx(frame) end
    local now = GetTime()
    local dt = fx.last and math.min(0.1, now - fx.last) or 0
    fx.last = now
    local ri = math.max(4, geom.R - geom.T / 2)
    local c = st.color
    local phase, age = st.phase, st.age or 0

    -- How charged the portal is (0..1), and how fast it turns.
    local charge, fade, collapse, scatter = st.frac or 0, 1, 0, 0
    if phase == "done" then
        charge = 1
        collapse = math.min(1, age / 0.3) -- motes rush into the heart...
        scatter = math.max(0, (age - 0.3) / 1.1) -- ...then fly apart
        fade = 1 - math.min(1, math.max(0, (age - 0.3) / 1.4))
    elseif phase == "lost" then
        fade = 1 - math.min(1, age / 0.8)
        scatter = math.min(1, age / 0.8) * 0.5
    end
    local speed = (0.25 + 1.6 * charge ^ 1.5) * (phase == "lost" and fade or 1) * (phase == "done" and 2.5 or 1)
    fx.spin = (fx.spin + dt * speed * TAU) % TAU
    fx.orbit = (fx.orbit + dt * (0.35 + 1.1 * charge) * (phase == "lost" and fade or 1)) % 1

    -- The glow under it all, breathing faster as it charges.
    local breathe = 0.85 + 0.15 * math.sin(now * (2 + 6 * charge))
    local gr, gg, gb = MixC(c, VIOLET, 0.5 + 0.5 * math.sin(now * 1.3))
    Put(fx.glow, frame, 0, 0, ri * (1.5 + 0.5 * charge) * breathe, gr, gg, gb, (0.2 + 0.4 * charge) * fade)

    -- The portal's heart: a bright core that grows as it charges; the flash when it goes off.
    local coreSize, coreAlpha = ri * (0.35 + 0.35 * charge) * breathe, (0.35 + 0.5 * charge) * fade
    if phase == "done" then
        local f = math.min(1, age / 0.45)
        coreSize = ri * (0.7 + 2.0 * math.sin(math.pi * math.min(1, f))) -- swell and settle
        coreAlpha = 1 - math.min(1, math.max(0, (age - 0.2) / 0.8))
    end
    Put(fx.core, frame, 0, 0, coreSize, Mix(c.r, 1, 0.6), Mix(c.g, 1, 0.6), Mix(c.b, 1, 0.6), coreAlpha)

    -- Shockwave: rolls out from the ring when it goes off.
    if phase == "done" and age > 0.2 and age < 1.2 then
        local w = (age - 0.2) / 1.0
        local wr, wg, wb = MixC(c, VIOLET, 0.3)
        Put(fx.wave, frame, 0, 0, geom.R * 2 * (1 + 1.2 * (1 - (1 - w) ^ 2)), wr, wg, wb, 0.8 * (1 - w))
    else
        fx.wave:Hide()
    end

    -- Spiral arms: each mote rides one of three arms in to the heart, wound tighter near it.
    for _, m in ipairs(fx.motes) do
        local u = (m.k + now * (0.25 + 0.5 * charge)) % 1 -- 0 at the rim, 1 at the heart
        local r = ri * 0.95 * (1 - u) ^ 0.9
        local a = fx.spin + m.arm * TAU / ARMS + (u ^ 1.2) * 2.6 + 0.15 * math.sin(now * 3 + m.wobble * TAU)
        if collapse > 0 then r = r * (1 - collapse) end
        if scatter > 0 then r = r + (geom.R * 1.6) * (1 - (1 - scatter) ^ 2) * (0.6 + m.wobble * 0.8) end
        local x, y = math.sin(a) * r, math.cos(a) * r
        local size = ri * 0.2 * m.size * (0.6 + 0.6 * charge) * (1 - 0.4 * u)
        local cr, cg, cb = MixC(c, VIOLET, (m.arm / (ARMS - 1)) * 0.8)
        cr, cg, cb = Mix(cr, 1, u * 0.6), Mix(cg, 1, u * 0.6), Mix(cb, 1, u * 0.6)
        local alpha = math.min(1, u * 5) * (1 - u ^ 3) * (0.45 + 0.55 * charge)
        if scatter > 0 then alpha = (0.5 + 0.5 * alpha) * (1 - scatter) end
        Put(m.tex, frame, x, y, size, cr, cg, cb, alpha * (phase == "done" and 1 or fade))
    end

    -- Comets: race round the ring, tails fading behind them.
    for _, comet in ipairs(fx.comets) do
        local head = fx.orbit + comet.offset
        for j, p in ipairs(comet.parts) do
            local back = (j - 1) * (0.012 + 0.012 * charge)
            local a = (head - back) * TAU
            local k = 1 - (j - 1) / TAIL
            local s = geom.T * (0.9 + 1.1 * charge) * (0.4 + 0.6 * k)
            local cr, cg, cb = MixC(c, VIOLET, (j - 1) / TAIL)
            Put(
                p,
                frame,
                math.sin(a) * geom.R,
                math.cos(a) * geom.R,
                s,
                Mix(cr, 1, 0.5 * k),
                Mix(cg, 1, 0.5 * k),
                Mix(cb, 1, 0.5 * k),
                k * (0.5 + 0.5 * charge) * (phase == "done" and (1 - collapse) or fade)
            )
        end
    end
end
ns.DrawHearthFx = DrawHearthFx
ns.HearthFxParts = function() return fx end -- for the tests

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen({
    "UNIT_SPELLCAST_START:player",
    "UNIT_SPELLCAST_STOP:player",
    "UNIT_SPELLCAST_SUCCEEDED:player",
    "UNIT_SPELLCAST_INTERRUPTED:player",
    "UNIT_SPELLCAST_FAILED:player",
}, function(event, _, guid, spellID)
    if not CircletDB or not db.hearthEnabled then return end
    if event == "UNIT_SPELLCAST_START" then
        if IsHearth(spellID) then Begin(spellID, guid) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_STOP" then
        -- Interrupts and failures arrive first as their own events (as in the cast ring).
        if Ours(guid) then Finish("done") end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        if Ours(guid) then Finish("lost") end
    end
end)

-- Shared with the files loaded after this one (the cast ring leaves Hearthstones to this one).
ns.IsHearthCast = function(spellID) return db.hearthEnabled and IsHearth(spellID) end
ns.hearthRing = hearthRing
ns.PreviewHearthRing = function() hearthRing.Preview(SAMPLE_CAST + DONE_SHOW + 0.5) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "hearth",
    name = "Hearthstone",
    order = 11.65,
    since = "1.4.0",
    iconBg = true, -- the icon can be the ring's background (Core/Settings.lua, UI/Options/Kit.lua)
    ring = hearthRing,
    preview = ns.PreviewHearthRing,
    slash = { "hearth", "hs" },
    help = "preview the hearthstone ring",
    toggle = { "Hearthstone ring", "Casting your Hearthstone home, with a swirling portal." },
    defaults = {
        -- Hearthstone ring: in the cast ring's place (the cast ring leaves Hearthstones to it).
        hearthEnabled = true,
        hearthFx = true, -- the swirling portal
        hearthSize = 120,
        hearthThickness = 10,
        hearthOpacity = 100,
        hearthX = 0,
        hearthFromTop = 265,
        hearthHold = 0.6,
        hearthStyle = "smooth",
        hearthBorder = 2,
        hearthColors = {
            fill = { r = 0.35, g = 0.60, b = 1.00 },
            home = { r = 0.55, g = 0.95, b = 1.00 },
        },
    },
    page = {
        folder = "travel",
        order = 1.5,
        build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(
                10.75,
                "Hearthstone",
                "Hearthstone Ring",
                "While you cast your Hearthstone (or Astral Recall), the ring fills and counts down with "
                    .. "where you're bound to, then says Home! and bursts. The cast ring leaves these casts to it.",
                MergeTop(
                    TopRow(
                        "hearth",
                        "hearthstone ring",
                        ns.PreviewHearthRing,
                        "Show a sample Hearthstone cast. Also /circ hearth."
                    ),
                    {
                        general = Box(2, "General", {
                            enabled = Toggle(
                                1,
                                "hearthEnabled",
                                "Show hearthstone ring",
                                "Show the ring while you cast your Hearthstone. Off: the cast ring shows it instead."
                            ),
                            fx = Toggle(
                                2,
                                "hearthFx",
                                "Swirling portal",
                                "Spiral arms of arcane motes turn in the middle, comets race round the ring, and it "
                                    .. "collapses into a flash and a shockwave when you go home."
                            ),
                        }),
                        colors = Box(3, "Colors", {
                            fill = Color(1, "hearthColors", "fill", "Casting", "Ring color while you cast."),
                            home = Color(
                                2,
                                "hearthColors",
                                "home",
                                "Home",
                                "Ring and label color when the cast goes off."
                            ),
                        }),
                        size = SizeBox(
                            4,
                            "hearth",
                            "hearthstone ring",
                            "Offset from the center of the screen. By default it sits where the cast ring does."
                        ),
                    }
                )
            )
            tab.args.size.args.hold.desc = "How long the ring stays after the cast ends."
            return tab
        end,
    },
})
