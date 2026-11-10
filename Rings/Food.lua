-- Circlet: Food & Drink ring: eating and drinking, with an animation for each.
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall, Clean, CleanNumber = ns.db, ns.CreateLiveRing, ns.SafeCall, ns.Clean, ns.CleanNumber

---------------------------------------------------------------------------
-- Food & Drink ring
---------------------------------------------------------------------------
-- While the game's Food or Drink buff is on you, the ring fills with your health (eating)
-- or mana (drinking), counts down the buff and bursts when you're full. Eating and
-- drinking at once fills with whichever is further from full. With foodFx on it plays:
--   eating:   a chomp every CHOMP seconds throws crumbs off the top of the ring, which arc
--             out, tumble and fall; a warm glow pulses in the middle with each bite.
--   drinking: bubbles rise through the middle like a fizzy drink, and every GULP seconds a
--             gulp sends a ripple rolling out from the centre.
-- All worked out from the time, so edit mode's sample plays them too.

local CHOMP, GULP = 1.3, 1.6
local CRUMBS, BUBBLES, BUBBLE_SIDES = 7, 6, 10

-- The buffs, by name (every rank shares one): the game's own names, read from the spells,
-- plus the English ones in case a name can't be read yet.
local FOOD_SPELL, DRINK_SPELL = 433, 430
local names
local function KindOf(name)
    if not names then
        local food, drink = ns.SpellName(FOOD_SPELL), ns.SpellName(DRINK_SPELL)
        names = { ["Food"] = "eat", ["Drink"] = "drink", ["Food & Drink"] = "both", ["Refreshment"] = "both" }
        if food then names[food] = "eat" end
        if drink then names[drink] = "drink" end
        if not (food and drink) then
            local found = names
            names = nil -- read the spell names again next time
            return found[name]
        end
    end
    return names[name]
end

-- The buffs you have now: { eat = aura, drink = aura } (aura = { icon, expires, duration }).
local buffs, dirty = {}, true
local function Scan()
    dirty = false
    wipe(buffs)
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
        local kind = type(Clean(name)) == "string" and KindOf(name)
        if kind then
            local aura = { icon = Clean(icon), duration = CleanNumber(duration), expires = CleanNumber(expires) }
            if kind == "eat" or kind == "both" then buffs.eat = buffs.eat or aura end
            if kind == "drink" or kind == "both" then buffs.drink = buffs.drink or aura end
        end
    end
end

local function Pct(f) return string.format("%d%%", math.floor(f * 100 + 0.5)) end

local function Frac(cur, max)
    cur, max = CleanNumber(cur), CleanNumber(max)
    if not (cur and max and max > 0) then return nil end
    return math.max(0, math.min(1, cur / max))
end

local fullAt -- when what you're refilling reached full (for the burst); nil while it isn't

-- kinds: "eat", "drink" or "both"; health / mana: fractions (nil if unknown); left: seconds.
local function State(kinds, health, mana, left, icon, doneAt)
    local c = db.foodColors
    local st = { kinds = kinds, icon = icon, hold = 1.5 }
    local eat, drink = kinds ~= "drink", kinds ~= "eat"
    st.title = (eat and drink) and "Eating & drinking" or (eat and "Eating" or "Drinking")
    local frac
    if eat and drink then
        frac = (health and mana) and math.min(health, mana) or health or mana
        st.label = (health and Pct(health) or "?") .. " · " .. (mana and Pct(mana) or "?")
    elseif eat then
        frac, st.label = health, health and ("Health " .. Pct(health)) or "Health"
    else
        frac, st.label = mana, mana and ("Mana " .. Pct(mana)) or "Mana"
    end
    st.frac = frac
    st.color = drink and not eat and c.drink or c.eat
    if eat and drink then st.color = c.both end
    if frac and frac >= 0.999 then
        st.color, st.label, st.labelColor = c.full, "Full!", c.full
        st.doneAt = doneAt
    end
    if left then
        st.value = left >= 60 and string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
            or string.format("%ds", math.ceil(left))
    else
        st.value = ""
    end
    return st
end

local SAMPLE_ICONS = { eat = "Interface\\Icons\\INV_Misc_Food_15", drink = "Interface\\Icons\\INV_Drink_07",
                       both = "Interface\\Icons\\INV_Misc_Food_73CinnamonRoll" }

local foodRing = CreateLiveRing({
    key = "food",
    read = function(now)
        if dirty then Scan() end
        local eat, drink = buffs.eat, buffs.drink
        if not (eat or drink) then fullAt = nil return nil end
        local kinds = (eat and drink) and "both" or (eat and "eat" or "drink")
        local health = Frac(SafeCall(UnitHealth, "player"), SafeCall(UnitHealthMax, "player"))
        local mana = Frac(SafeCall(UnitPower, "player", 0), SafeCall(UnitPowerMax, "player", 0))
        local expires = math.max(eat and eat.expires or 0, drink and drink.expires or 0)
        local left = expires > 0 and math.max(0, expires - now) or nil
        local st = State(kinds, health, mana, left, (eat or drink).icon, nil)
        if st.frac and st.frac >= 0.999 then
            fullAt = fullAt or now
            st.doneAt = fullAt
        else
            fullAt = nil
        end
        return st
    end,
    sample = function(t)
        -- Eat back to full, then drink, then both at once: 7 seconds each.
        local cycle = t % 21
        local kinds = cycle < 7 and "eat" or (cycle < 14 and "drink" or "both")
        local u = (cycle % 7) / 5.5
        local frac = math.min(1, 0.25 + 0.75 * u)
        local health = kinds ~= "drink" and frac or nil
        local mana = kinds ~= "eat" and math.min(1, 0.15 + 0.85 * u) or nil
        local left = 18 - (cycle % 7) * 2
        local start = t - (cycle % 7)
        return State(kinds, health, mana, left, SAMPLE_ICONS[kinds], start + 5.5)
    end,
    decorate = function(st, frame, geom) ns.DrawFoodFx(st, frame, geom) end,
})

---------------------------------------------------------------------------
-- The animations
---------------------------------------------------------------------------
local TAU = 2 * math.pi
local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR_TEX = "Interface\\Cooldown\\star4"
local CIRCLE_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CRUMB_COLORS = { { 0.85, 0.62, 0.30 }, { 0.70, 0.45, 0.20 }, { 0.95, 0.80, 0.50 } }

local fx -- textures and lines on the ring's frame, made on first use

local function Build(frame)
    fx = { crumbs = {}, bubbles = {} }
    fx.glow = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    if fx.glow:SetTexture(GLOW_TEX) == false then fx.glow:SetTexture(STAR_TEX) end
    fx.glow:SetBlendMode("ADD")
    fx.glow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    fx.glow:Hide()
    for i = 1, CRUMBS do
        local t = frame:CreateTexture(nil, "ARTWORK", nil, 3)
        t:SetColorTexture(1, 1, 1, 1)
        t:Hide()
        local c = CRUMB_COLORS[(i % #CRUMB_COLORS) + 1]
        -- Fixed per crumb: which way it flies, how hard, how big and how fast it turns.
        fx.crumbs[i] = { tex = t, c = c, angle = -1.1 + 2.2 * ((i * 0.618) % 1), speed = 0.8 + (i * 0.37) % 0.5,
                         size = 0.7 + (i * 0.53) % 0.6, spin = ((i % 2 == 0) and 1 or -1) * (4 + i % 3 * 2) }
    end
    for i = 1, BUBBLES do
        local b = CreateFrame("Frame", nil, frame)
        b:SetSize(1, 1)
        b.lines = {}
        for s = 1, BUBBLE_SIDES do
            local line = b:CreateLine(nil, "ARTWORK", nil, 3)
            if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(false); line:SetTexelSnappingBias(0) end
            b.lines[s] = line
        end
        b.glint = b:CreateTexture(nil, "ARTWORK", nil, 4)
        b.glint:SetTexture(CIRCLE_TEX)
        b.speed, b.phase = 1 / (1.8 + (i * 0.41) % 1.0), (i * 0.618) % 1
        b.x, b.size = ((i * 0.437) % 1) * 2 - 1, 0.7 + (i * 0.53) % 0.6
        b:Hide()
        fx.bubbles[i] = b
    end
    fx.ripple = ns.NewRingLayer("ARTWORK", 2, { r = 1, g = 1, b = 1 }, 1, frame)
    fx.rippleGeom = {}
    for _, l in ipairs(fx.ripple) do l:Hide() end
end

local function HideAll()
    if not fx then return end
    fx.glow:Hide()
    for _, cr in ipairs(fx.crumbs) do cr.tex:Hide() end
    for _, b in ipairs(fx.bubbles) do b:Hide() end
    for _, l in ipairs(fx.ripple) do l:Hide() end
end

local function ShapeBubble(b, r, a)
    local thick = math.max(1, r * 0.25)
    for s = 1, BUBBLE_SIDES do
        local a1, a2 = (s - 1) / BUBBLE_SIDES * TAU, s / BUBBLE_SIDES * TAU
        local line = b.lines[s]
        line:SetThickness(thick)
        line:SetStartPoint("CENTER", b, math.cos(a1) * r, math.sin(a1) * r)
        line:SetEndPoint("CENTER", b, math.cos(a2) * r, math.sin(a2) * r)
        line:SetColorTexture(0.80, 0.93, 1.00, 0.85 * a)
    end
    local g = math.max(1.5, r * 0.5)
    b.glint:SetSize(g, g)
    b.glint:ClearAllPoints()
    b.glint:SetPoint("CENTER", b, "CENTER", -r * 0.35, r * 0.35)
    b.glint:SetVertexColor(1, 1, 1, 0.9 * a)
end

-- Crumbs from the latest chomp: thrown up and out from the ring's top edge, arcing over
-- its sides and falling away past it.
local function DrawCrumbs(frame, now, ri, ro)
    local since = now % CHOMP
    local life = CHOMP * 0.9
    local g = ro * 6 -- gravity, in ring sizes per second squared
    for i, cr in ipairs(fx.crumbs) do
        local t = since - (i % 3) * 0.03 -- a few leave a moment later
        if t > 0 and t < life then
            local u = t / life
            local v = ro * 2.1 * cr.speed
            local x = math.sin(cr.angle) * v * t
            local y = (ri + ro) / 2 + math.cos(cr.angle) * v * t - 0.5 * g * t * t
            local size = math.max(2, ri * 0.13 * cr.size)
            cr.tex:ClearAllPoints()
            cr.tex:SetPoint("CENTER", frame, "CENTER", x, y)
            cr.tex:SetSize(size, size)
            cr.tex:SetVertexColor(cr.c[1], cr.c[2], cr.c[3])
            if cr.tex.SetRotation then cr.tex:SetRotation(cr.spin * t) end
            cr.tex:SetAlpha(math.min(1, u * 10) * (1 - u ^ 3))
            cr.tex:Show()
        else
            cr.tex:Hide()
        end
    end
end

-- Bubbles rising through the hollow, swaying, popping near the top.
local function DrawBubbles(frame, now, ri)
    for _, b in ipairs(fx.bubbles) do
        local u = (now * b.speed + b.phase) % 1
        local y = ri * (-0.85 + 1.6 * u)
        local half = math.sqrt(math.max(0, 1 - (y / ri) ^ 2)) * ri * 0.75 -- keep inside the hollow
        local x = b.x * half + math.sin(now * 3 + b.phase * TAU) * ri * 0.05
        local r = math.max(1.5, ri * 0.075 * b.size * (0.8 + 0.4 * u))
        local a = math.min(1, u * 5) * (u > 0.85 and (1 - u) / 0.15 or 1)
        ShapeBubble(b, r, a)
        b:ClearAllPoints()
        b:SetPoint("CENTER", frame, "CENTER", x, y)
        b:Show()
    end
end

-- A gulp: a ripple rolling out from the middle to the ring, fading as it goes.
local function DrawRipple(frame, geom, now, ri, c)
    local u = (now % GULP) / (GULP * 0.7)
    if u >= 1 then
        for _, l in ipairs(fx.ripple) do l:Hide() end
        return
    end
    local g = fx.rippleGeom
    g.R, g.T, g.step = math.max(2, ri * (0.15 + 0.85 * u)), math.max(1, geom.T * 0.25 * (1 - u * 0.5)), geom.step
    g.start, g.sweep, g.reverse = 0, 1, nil
    for _, l in ipairs(fx.ripple) do l:SetColorTexture(c.r, c.g, c.b, 0.7 * (1 - u)) end
    ns.DrawArc(fx.ripple, 0, 1, frame, g, true)
end

local function DrawFoodFx(st, frame, geom)
    if not (st and st.kinds and db.foodFx) or not geom or geom.R <= 0 then return HideAll() end
    if not fx then Build(frame) end
    local now = GetTime()
    local ri = math.max(4, geom.R - geom.T / 2) -- the hollow
    local ro = geom.R + geom.T / 2              -- the ring's outer edge
    local eat, drink = st.kinds ~= "drink", st.kinds ~= "eat"
    local c = db.foodColors

    -- A warm (or cool) glow in the middle: swells with each bite or gulp.
    local beat = eat and (now % CHOMP) / CHOMP or (now % GULP) / GULP
    local pulse = 0.55 + 0.45 * math.max(0, 1 - beat * 3)
    local gc = eat and c.eat or c.drink
    local size = ri * 2.2 * (0.9 + 0.1 * pulse)
    fx.glow:SetSize(size, size)
    fx.glow:SetVertexColor(gc.r, gc.g, gc.b)
    fx.glow:SetAlpha(0.35 * pulse)
    fx.glow:Show()

    if eat then DrawCrumbs(frame, now, ri, ro) else for _, cr in ipairs(fx.crumbs) do cr.tex:Hide() end end
    if drink then
        DrawBubbles(frame, now, ri)
        DrawRipple(frame, geom, now, ri, c.drink)
    else
        for _, b in ipairs(fx.bubbles) do b:Hide() end
        for _, l in ipairs(fx.ripple) do l:Hide() end
    end
end
ns.DrawFoodFx = DrawFoodFx

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen({ "UNIT_AURA:player", "PLAYER_ENTERING_WORLD" }, function() dirty = true end)

-- Shared with the files loaded after this one.
ns.foodRing = foodRing
ns.PreviewFoodRing = function() foodRing.Preview(21) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "food", name = "Food & Drink", order = 11.5,
    iconBg = true, -- the icon can be the ring's background (Core/Settings.lua, UI/OptionsKit.lua)
    ring = foodRing,
    preview = ns.PreviewFoodRing, slash = { "food", "drink", "eat" }, help = "preview the food & drink ring",
    toggle = { "Food & Drink ring", "Eating and drinking: your health or mana filling back up." },
    defaults = {
        -- Food & Drink ring: while you eat or drink. Left of the breath ring.
        foodEnabled   = true,
        foodFx        = true, -- the eating and drinking animations
        foodSize      = 110,
        foodThickness = 11,
        foodOpacity   = 100,
        foodX         = -340,
        foodFromTop   = 260,
        foodHold      = 2,
        foodStyle     = "smooth",
        foodBorder    = 2,
        foodColors = {
            eat   = { r = 0.95, g = 0.60, b = 0.25 },
            drink = { r = 0.35, g = 0.65, b = 1.00 },
            both  = { r = 0.80, g = 0.55, b = 0.90 },
            full  = { r = 0.35, g = 0.90, b = 0.40 },
        },
    },
    page = { folder = "status", order = 4.5, build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(10.6, "Food & Drink", "Food & Drink Ring",
                "While you eat or drink, the ring fills with your health or mana and counts down the buff, then "
                .. "bursts when you're full. Eating throws crumbs off the ring with every bite; drinking sends "
                .. "bubbles up through it and a ripple out with every gulp.",
                MergeTop(TopRow("food", "food & drink ring", ns.PreviewFoodRing,
                    "Show a sample meal: eating, drinking, then both. Also /circ food."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "foodEnabled", "Show food & drink ring",
                            "Show the ring while you're eating or drinking."),
                        fx = Toggle(2, "foodFx", "Animations",
                            "Crumbs flying with each bite while you eat; bubbles and a ripple with each gulp while "
                            .. "you drink."),
                    }),
                    colors = Box(3, "Colors", {
                        eat = Color(1, "foodColors", "eat", "Eating", "Ring color while you eat (and the glow behind it)."),
                        drink = Color(2, "foodColors", "drink", "Drinking", "Ring color while you drink, and the ripple."),
                        both = Color(3, "foodColors", "both", "Both", "Ring color while you eat and drink at once."),
                        full = Color(4, "foodColors", "full", "Full", "Ring and label color once you're full."),
                    }),
                    size = SizeBox(4, "food", "food & drink ring",
                        "Offset from the center of the screen. By default it sits left of the breath ring."),
                }))
            tab.args.size.args.hold.desc = "How long the ring stays after you stop eating or drinking."
            return tab
        end },
})
