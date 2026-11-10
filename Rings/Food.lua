-- Circlet: Food & Drink ring: eating and drinking, with an animation for each.
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall, Clean, CleanNumber = ns.db, ns.CreateLiveRing, ns.SafeCall, ns.Clean, ns.CleanNumber

---------------------------------------------------------------------------
-- Food & Drink ring
---------------------------------------------------------------------------
-- While the game's Food or Drink buff is on you, the ring fills with how far through the buff
-- you are, counts down what's left and bursts when it's done. (A full buff restores you over
-- its length; the client keeps your health and mana themselves secret from addons.) When the
-- buff's own times are secret too, it's timed from when the buff showed up. Eating and
-- drinking at once fills with whichever is further from full. With foodFx on it plays:
--   eating:   steam curls up from a warm glow in the middle, rising past the top of the
--             ring. Every CHOMP seconds a chomp takes a tooth-marked bite out of the end of
--             the fill (circles in the track's color, kept inside the band so they never
--             cover the world behind), with crumbs and impact lines bursting out from it;
--             the bite closes over again as you chew.
--   drinking: the middle of the ring fills with water, rising with the buff as you drink.
--             Its surface rocks with a gentle wave, and every GULP seconds a gulp sloshes it.
-- All worked out from the time, so edit mode's sample plays them too.

local CHOMP, GULP = 1.3, 1.6
local CRUMBS = 7
local WISPS, PUFFS = 3, 8   -- steam: columns, and soft puffs travelling up each one
local TEETH = 3             -- tooth marks along a bite's edge
local BITE_HOLD, BITE_FADE = 0.55, 0.35 -- a bite stays this long, then closes over this fast
local COLUMNS, SURFACE = 48, 18 -- the water: vertical strips, and segments along its surface

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
local since = {} -- kind -> GetTime() when that buff was first seen (for when its times are secret)
local DEFAULT_DURATION = 24 -- seconds, for a buff whose duration can't be read (food runs 18-30)
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
    local now = GetTime()
    for _, k in ipairs({ "eat", "drink" }) do
        local aura = buffs[k]
        if not aura then
            since[k] = nil
        else
            -- A buff that's been renewed (eating again) starts over.
            if aura.expires and aura.duration then
                local start = aura.expires - aura.duration
                if not since[k] or math.abs(since[k] - start) > 0.5 then since[k] = start end
            elseif not since[k] then
                since[k] = now
            end
        end
    end
end

local fullAt -- when the buff finished (for the burst); nil until it has

-- How far through a buff (0..1) and the seconds left, from its own times when they can be read.
local function Progress(kind, aura, now)
    local duration = aura.duration and aura.duration > 0 and aura.duration or DEFAULT_DURATION
    local start = since[kind] or now
    local left = aura.expires and math.max(0, aura.expires - now) or math.max(0, start + duration - now)
    return math.max(0, math.min(1, 1 - left / duration)), left
end

-- kinds: "eat", "drink" or "both"; frac: how far through the buff (0..1); left: seconds.
local function State(kinds, frac, left, icon, doneAt)
    local c = db.foodColors
    local st = { kinds = kinds, icon = icon, hold = 1.5, frac = frac }
    local eat, drink = kinds ~= "drink", kinds ~= "eat"
    st.title = (eat and drink) and "Eating & drinking" or (eat and "Eating" or "Drinking")
    st.label = (eat and drink) and "Restoring" or (eat and "Restoring health" or "Restoring mana")
    st.color = (eat and drink) and c.both or (eat and c.eat or c.drink)
    if frac >= 0.999 then
        st.color, st.label, st.labelColor = c.full, "Full!", c.full
        st.doneAt = doneAt
    end
    st.value = left >= 60 and string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
        or string.format("%ds", math.ceil(left - 0.05))
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
        -- How far through the buff: the one with longer to go, when you eat and drink at once.
        local frac, left = 1, 0
        for kind, aura in pairs(buffs) do
            local p, l = Progress(kind, aura, now)
            frac, left = math.min(frac, p), math.max(left, l)
        end
        -- The game removes the buff the moment it runs out, so its last moments count as done.
        if frac >= 0.97 then frac = 1 end
        local st = State(kinds, frac, left, (eat or drink).icon, nil)
        if frac >= 0.999 then
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
        local frac = math.min(1, 0.1 + (cycle % 7) / 5.5 * 0.9)
        local left = math.max(0, 5.5 - (cycle % 7))
        local start = t - (cycle % 7)
        return State(kinds, frac, left, SAMPLE_ICONS[kinds], start + 5.5)
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
    fx = { crumbs = {}, steam = {}, bite = {}, impact = {} }
    fx.glow = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    if fx.glow:SetTexture(GLOW_TEX) == false then fx.glow:SetTexture(STAR_TEX) end
    fx.glow:SetBlendMode("ADD")
    fx.glow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    fx.glow:Hide()
    -- Steam: soft puffs, a column of them per wisp, each travelling up and fading.
    for w = 1, WISPS do
        for j = 1, PUFFS do
            local t = frame:CreateTexture(nil, "ARTWORK", nil, 6)
            if t:SetTexture(GLOW_TEX) == false then t:SetTexture(STAR_TEX) end
            t:SetBlendMode("BLEND") -- plain see-through white: shows on bright ground too, unlike added light
            t:Hide()
            table.insert(fx.steam, { tex = t, wisp = w, phase = (j - 1) / PUFFS + w * 0.13 })
        end
    end
    -- The bite: a round chunk and tooth marks along its edge, in the track's color.
    for i = 1, 1 + TEETH do
        local t = frame:CreateTexture(nil, "ARTWORK", nil, 5)
        t:SetTexture(CIRCLE_TEX)
        t:Hide()
        fx.bite[i] = t
    end
    for i = 1, 3 do
        local l = frame:CreateLine(nil, "ARTWORK", nil, 4)
        if l.SetSnapToPixelGrid then l:SetSnapToPixelGrid(false); l:SetTexelSnappingBias(0) end
        l:Hide()
        fx.impact[i] = l
    end
    for i = 1, CRUMBS do
        local t = frame:CreateTexture(nil, "ARTWORK", nil, 3)
        t:SetColorTexture(1, 1, 1, 1)
        t:Hide()
        local c = CRUMB_COLORS[(i % #CRUMB_COLORS) + 1]
        -- Fixed per crumb: which way it flies, how hard, how big and how fast it turns.
        fx.crumbs[i] = { tex = t, c = c, angle = -1.1 + 2.2 * ((i * 0.618) % 1), speed = 0.8 + (i * 0.37) % 0.5,
                         size = 0.7 + (i * 0.53) % 0.6, spin = ((i % 2 == 0) and 1 or -1) * (4 + i % 3 * 2) }
    end
    -- The water: strips from the bottom of the hollow up to the surface, and a bright line
    -- along the surface. Lines, worked out to stay inside the circle, so no mask is needed.
    local function Line(sub)
        local l = frame:CreateLine(nil, "BORDER", nil, sub)
        if l.SetSnapToPixelGrid then l:SetSnapToPixelGrid(false); l:SetTexelSnappingBias(0) end
        l:Hide()
        return l
    end
    fx.water, fx.shallow, fx.surface = {}, {}, {}
    for i = 1, COLUMNS do fx.water[i], fx.shallow[i] = Line(1), Line(2) end
    for i = 1, SURFACE do fx.surface[i] = Line(3) end
end

local function HideAll()
    if not fx then return end
    fx.glow:Hide()
    for _, cr in ipairs(fx.crumbs) do cr.tex:Hide() end
    for _, p in ipairs(fx.steam) do p.tex:Hide() end
    for _, t in ipairs(fx.bite) do t:Hide() end
    for _, l in ipairs(fx.impact) do l:Hide() end
    for _, l in ipairs(fx.water) do l:Hide() end
    for _, l in ipairs(fx.shallow) do l:Hide() end
    for _, l in ipairs(fx.surface) do l:Hide() end
end

-- Steam: wisps curling up from the bottom of the hollow, past the top of the ring,
-- swaying more and spreading as they rise.
local function DrawSteam(frame, now, ri, ro)
    for _, p in ipairs(fx.steam) do
        local u = (now * 0.32 + p.phase) % 1
        local ox = (p.wisp - (WISPS + 1) / 2) * ri * 0.42
        local x = ox + math.sin(u * 6.5 + now * 1.3 + p.wisp * 1.9) * ri * (0.04 + 0.22 * u)
        local y = -ri * 0.45 + u * (ri * 0.45 + ro * 1.45)
        local size = ri * (0.45 + 0.85 * u)
        p.tex:ClearAllPoints()
        p.tex:SetPoint("CENTER", frame, "CENTER", x, y)
        p.tex:SetSize(size, size)
        p.tex:SetVertexColor(0.95, 0.92, 0.88)
        p.tex:SetAlpha(0.32 * math.sin(math.pi * u))
        p.tex:Show()
    end
end

-- A chomp at the end of the fill: the bite, crumbs bursting out from it and a few impact
-- lines. frac: how full the ring is (the bite goes at its head).
local function DrawChomp(frame, geom, now, ri, ro, frac)
    local since = now % CHOMP
    local R, T = geom.R, geom.T
    if not frac or frac <= 0.02 or frac >= 0.995 then
        for _, t in ipairs(fx.bite) do t:Hide() end
        for _, l in ipairs(fx.impact) do l:Hide() end
        for _, cr in ipairs(fx.crumbs) do cr.tex:Hide() end
        return
    end
    -- Where the fill ends, which way is out from the ring there, and along it.
    local hx, hy = ns.RingPoint(geom, frac)
    local ox, oy = hx / R, hy / R
    local bx, by = ns.RingPoint(geom, math.max(0, frac - 0.004)) -- a little back: which way the fill runs
    local tx, ty = hx - bx, hy - by
    local tl = math.sqrt(tx * tx + ty * ty)
    if tl < 1e-6 then tx, ty = -oy, ox else tx, ty = tx / tl, ty / tl end

    -- The bite: a chunk over the end of the fill, tooth marks along its edge toward the
    -- filled side. Track-colored, all inside the band.
    local a = since < BITE_HOLD and 1 or math.max(0, 1 - (since - BITE_HOLD) / BITE_FADE)
    local tc = ns.TRACK
    local chunk = T * 0.5
    local cx, cy = hx - tx * chunk * 0.35, hy - ty * chunk * 0.35
    local main = fx.bite[1]
    main:ClearAllPoints()
    main:SetPoint("CENTER", frame, "CENTER", cx, cy)
    main:SetSize(chunk * 2, chunk * 2)
    main:SetVertexColor(tc.r, tc.g, tc.b)
    main:SetAlpha(a)
    main:SetShown(a > 0)
    for k = 1, TEETH do
        local across = (k - (TEETH + 1) / 2) * T * 0.27 -- spread across the band
        local back = chunk * (0.95 - 0.12 * math.abs(k - (TEETH + 1) / 2))
        local t = fx.bite[1 + k]
        local r = T * 0.2
        t:ClearAllPoints()
        t:SetPoint("CENTER", frame, "CENTER", cx - tx * back + ox * across, cy - ty * back + oy * across)
        t:SetSize(r * 2, r * 2)
        t:SetVertexColor(tc.r, tc.g, tc.b)
        t:SetAlpha(a)
        t:SetShown(a > 0)
    end

    -- Impact lines: a quick flash of short strokes out from the bite.
    local ia = math.max(0, 1 - since / 0.28)
    for k, l in ipairs(fx.impact) do
        if ia > 0 then
            local spread = (k - 2) * 0.45
            local dx = ox * math.cos(spread) + tx * math.sin(spread)
            local dy = oy * math.cos(spread) + ty * math.sin(spread)
            local d0 = T * 0.9 + since * ro * 0.6
            local len = T * (0.9 + 0.6 * (1 - ia))
            l:SetThickness(math.max(1.5, T * 0.16))
            l:SetStartPoint("CENTER", frame, hx + dx * d0, hy + dy * d0)
            l:SetEndPoint("CENTER", frame, hx + dx * (d0 + len), hy + dy * (d0 + len))
            l:SetColorTexture(1, 0.9, 0.65, 0.9 * ia)
            l:Show()
        else
            l:Hide()
        end
    end

    -- Crumbs: thrown out from the bite (outward from the ring, spread along it), then falling.
    local life = CHOMP * 0.85
    local g = ro * 6
    for i, cr in ipairs(fx.crumbs) do
        local t = since - (i % 3) * 0.03 -- a few leave a moment later
        if t > 0 and t < life then
            local u = t / life
            local v = ro * 1.6 * cr.speed
            local dx = ox * math.cos(cr.angle) + tx * math.sin(cr.angle)
            local dy = oy * math.cos(cr.angle) + ty * math.sin(cr.angle)
            local x = hx + dx * v * t
            local y = hy + dy * v * t - 0.5 * g * t * t
            local size = math.max(2, ri * 0.12 * cr.size)
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

-- The water: filling the hollow up to `level` (0..1 of its height, eased toward how far
-- through the drink you are), its surface rocking, and sloshing harder just after each gulp.
local shownLevel
local function DrawWater(frame, now, ri, level, c)
    shownLevel = shownLevel and (shownLevel + (level - shownLevel) * 0.08) or level
    local lv = shownLevel
    local since = now % GULP
    local amp = ri * (0.035 + 0.09 * math.exp(-since * 2.8)) -- a gentle rock, a slosh after a gulp
    local tilt = ri * 0.06 * math.sin(since * 4.5) * math.exp(-since * 1.8) -- the slosh leans side to side
    local base = -ri + 2 * ri * lv
    local function Surface(x)
        local u = x / ri
        return base + amp * math.sin(u * 2.4 + now * 2.2) + amp * 0.4 * math.sin(u * 5.3 - now * 3.1) + tilt * u
    end
    -- Body: deep and dark, with a lighter band just under the surface.
    local w = 2 * ri / COLUMNS
    local band = ri * 0.22
    for i, l in ipairs(fx.water) do
        local x = -ri + (i - 0.5) * w
        local outer = math.abs(x) + w / 2 -- the strip's side nearest the edge stays inside the circle
        local edge = math.sqrt(math.max(0, ri * ri - outer * outer))
        local top = math.min(edge, Surface(x))
        local shallow = fx.shallow[i]
        if top > -edge + 0.5 then
            local mid = math.max(-edge, top - band)
            l:SetThickness(w)
            l:SetStartPoint("CENTER", frame, x, -edge)
            l:SetEndPoint("CENTER", frame, x, mid)
            l:SetColorTexture(c.r * 0.3, c.g * 0.32, c.b * 0.45, 0.7)
            l:SetShown(mid > -edge + 0.5)
            shallow:SetThickness(w)
            shallow:SetStartPoint("CENTER", frame, x, mid)
            shallow:SetEndPoint("CENTER", frame, x, top)
            shallow:SetColorTexture(c.r * 0.55, c.g * 0.58, c.b * 0.7, 0.6)
            shallow:Show()
        else
            l:Hide()
            shallow:Hide()
        end
    end
    -- Surface: a light line along the top of the water, inside the circle.
    local sw = 2 * ri / SURFACE
    for i, l in ipairs(fx.surface) do
        local x1, x2 = -ri + (i - 1) * sw, -ri + i * sw
        local y1, y2 = Surface(x1), Surface(x2)
        local e1, e2 = math.sqrt(math.max(0, ri * ri - x1 * x1)), math.sqrt(math.max(0, ri * ri - x2 * x2))
        if math.abs(y1) < e1 - 1 and math.abs(y2) < e2 - 1 then
            l:SetThickness(math.max(1.5, ri * 0.045))
            l:SetStartPoint("CENTER", frame, x1, y1)
            l:SetEndPoint("CENTER", frame, x2, y2)
            l:SetColorTexture(math.min(1, c.r * 0.5 + 0.5), math.min(1, c.g * 0.5 + 0.5), math.min(1, c.b * 0.4 + 0.6), 0.85)
            l:Show()
        else
            l:Hide()
        end
    end
end

local function DrawFoodFx(st, frame, geom)
    if not (st and st.kinds and db.foodFx) or not geom or geom.R <= 0 then return HideAll() end
    if not fx then Build(frame) end
    local now = GetTime()
    local ri = math.max(4, geom.R - geom.T / 2) -- the hollow
    local ro = geom.R + geom.T / 2              -- the ring's outer edge
    local eat, drink = st.kinds ~= "drink", st.kinds ~= "eat"
    local c = db.foodColors

    -- While eating: a warm glow low in the middle (the steam's source), swelling a little
    -- with each bite, the steam, and the chomp.
    if eat then
        local pulse = 0.7 + 0.3 * math.max(0, 1 - (now % CHOMP) / CHOMP * 3)
        local size = ri * 1.9 * (0.92 + 0.08 * pulse)
        fx.glow:ClearAllPoints()
        fx.glow:SetPoint("CENTER", frame, "CENTER", 0, -ri * 0.3)
        fx.glow:SetSize(size, size)
        fx.glow:SetVertexColor(c.eat.r, c.eat.g, c.eat.b)
        fx.glow:SetAlpha(0.4 * pulse)
        fx.glow:Show()
        DrawSteam(frame, now, ri, ro)
        DrawChomp(frame, geom, now, ri, ro, st.frac)
    else
        fx.glow:Hide()
        for _, p in ipairs(fx.steam) do p.tex:Hide() end
        for _, t in ipairs(fx.bite) do t:Hide() end
        for _, l in ipairs(fx.impact) do l:Hide() end
        for _, cr in ipairs(fx.crumbs) do cr.tex:Hide() end
    end
    if drink then
        DrawWater(frame, now, ri, st.frac or 0.5, c.drink)
    else
        shownLevel = nil
        for _, l in ipairs(fx.water) do l:Hide() end
        for _, l in ipairs(fx.shallow) do l:Hide() end
        for _, l in ipairs(fx.surface) do l:Hide() end
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
    toggle = { "Food & Drink ring", "Eating and drinking: the food or drink buff filling up." },
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
                "While you eat or drink, the ring fills as the food or drink buff runs and counts down what's "
                .. "left, then bursts when it's done. Eating sends up steam and takes a bite out of the ring with every "
                .. "chomp; drinking fills the "
                .. "middle with water that rises as you drink and sloshes with every gulp.",
                MergeTop(TopRow("food", "food & drink ring", ns.PreviewFoodRing,
                    "Show a sample meal: eating, drinking, then both. Also /circ food."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "foodEnabled", "Show food & drink ring",
                            "Show the ring while you're eating or drinking."),
                        fx = Toggle(2, "foodFx", "Animations",
                            "Steam and bites (with crumbs flying) while you eat; water filling the ring and sloshing with "
                            .. "each gulp while you drink."),
                    }),
                    colors = Box(3, "Colors", {
                        eat = Color(1, "foodColors", "eat", "Eating", "Ring color while you eat (and the glow behind it)."),
                        drink = Color(2, "foodColors", "drink", "Drinking", "Ring color while you drink, and the water's."),
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
