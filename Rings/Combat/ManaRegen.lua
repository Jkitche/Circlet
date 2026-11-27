-- Circlet: Mana regen ring: the five-second rule after you spend mana.
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing, SafeCall, Clean = ns.db, ns.IsSecret, ns.CreateLiveRing, ns.SafeCall, ns.Clean

---------------------------------------------------------------------------
-- Mana regen ring
---------------------------------------------------------------------------
-- Spending mana stops your spirit-based mana regen for five seconds (the "five-second
-- rule"). Each time you finish a spell that costs mana (or start channelling one), the ring
-- fills over those five seconds, counting down to when regen starts again, with the spell's
-- icon; another mana spell starts it over. When the five seconds are up it turns bright
-- ("Regenerating") for a moment and fades.
--
-- Your mana itself is secret to addons on this client, so the ring goes by what the spell
-- costs, from the game's spell data. Whether a spell costs mana is remembered
-- (db.manaSpells), so if the cost is hidden mid-fight a spell you've cast before still
-- counts. Free spells (a wand's Shoot, Auto Shot) and rage or energy abilities don't start it.
--
-- Some buffs make your next spell free, and a free cast doesn't stop regen: Clearcasting (the
-- mage's Arcane Concentration, the druid's Omen of Clarity, the shaman's Elemental Focus),
-- Inner Focus, and anything cast in Spirit of Redemption. The cast itself uses the buff up, so
-- the game may take it away just before or just after telling us about the cast. A cast counts
-- as free when one of these was on you and is gone within FREE_WINDOW of it; if it's still
-- there after (Omen of Clarity doesn't cover a buff like Mark of the Wild), the cast paid mana
-- and the countdown runs from the cast. Spirit of Redemption isn't used up, so it always counts.
-- During Innervate you regenerate even while casting: the countdown still shows, but says so.

local RULE = 5          -- seconds without regen after spending mana
local FREE_WINDOW = 0.5 -- a free-cast buff gone this soon before or after a cast was used on it
local REGEN_SHOW = 1.2  -- seconds the "Regenerating" ring stays before fading

local function Learned()
    db.manaSpells = db.manaSpells or {}
    return db.manaSpells
end

-- Whether a spell costs mana: true, false, or nil when it can't be told.
local function CostsMana(spellID)
    spellID = Clean(spellID)
    if type(spellID) ~= "number" then return nil end
    local getCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    local costs = getCost and SafeCall(getCost, spellID)
    if type(costs) == "table" and not IsSecret(costs) then
        local mana = false
        for _, c in ipairs(costs) do
            local ptype, amount = Clean(c.type), Clean(c.cost) or Clean(c.minCost) or 0
            local pct = Clean(c.costPercent) or 0
            if (ptype == 0 or Clean(c.name) == "MANA")
                and ((type(amount) == "number" and amount > 0) or (type(pct) == "number" and pct > 0)) then
                mana = true
            end
        end
        Learned()[spellID] = mana
        return mana
    end
    return Learned()[spellID] -- the cost can't be read right now: what we learned before
end

-- Buffs that make the next spell free (by spell ID; the shaman's Clearcasting is free in
-- Classic, unlike later versions' 40%), and ones that keep regen going while casting.
local FREE_CAST = {
    [12536] = "used",  -- Clearcasting: mage, Arcane Concentration
    [16870] = "used",  -- Clearcasting: druid, Omen of Clarity
    [16246] = "used",  -- Clearcasting: shaman, Elemental Focus
    [14751] = "used",  -- Inner Focus: priest
    [27827] = "always", -- Spirit of Redemption: priest, every spell free while it lasts
}
local REGEN_GOES_ON = { [29166] = true } -- Innervate

local freeUp, freeAlways, innervated = false, false, false
local freeGoneAt -- GetTime() a free-cast buff last went away

-- What's on you now, read whenever your buffs change (so we know when one goes away).
local function ScanBuffs()
    local used, always, innerv = false, false, false
    for i = 1, 40 do
        local id
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = SafeCall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not a then break end
            id = a.spellId
        elseif UnitBuff then
            local name, _, _, _, _, _, _, _, _, sid = SafeCall(UnitBuff, "player", i)
            if not name then break end
            id = sid
        else
            break
        end
        id = Clean(id)
        if type(id) == "number" then
            if FREE_CAST[id] == "used" then used = true
            elseif FREE_CAST[id] == "always" then always = true end
            if REGEN_GOES_ON[id] then innerv = true end
        end
    end
    if freeUp and not used then freeGoneAt = GetTime() end
    freeUp, freeAlways, innervated = used, always, innerv
end

local spent   -- { at = GetTime(), spellID, icon }: the last time you spent mana
local lastGUID

local function Start(at, spellID)
    spent = { at = at, spellID = spellID, icon = ns.SpellIcon(spellID) }
end

local function Spend(spellID, castGUID)
    castGUID = Clean(castGUID)
    if castGUID and castGUID == lastGUID then return end -- a channel's start and its success
    if not CostsMana(spellID) then return end
    lastGUID = castGUID
    spellID = Clean(spellID)
    local now = GetTime()
    if freeAlways then return end -- Spirit of Redemption: everything's free
    if freeGoneAt and now - freeGoneAt <= FREE_WINDOW then
        freeGoneAt = nil -- just used up on this cast: free
        return
    end
    if freeUp then
        -- It may be used up a moment from now (free), or still be there (this cast paid).
        C_Timer.After(FREE_WINDOW, function()
            if freeGoneAt and freeGoneAt >= now - 0.05 then freeGoneAt = nil return end
            Start(now, spellID)
        end)
        return
    end
    Start(now, spellID)
end

-- `start`: GetTime() the mana was spent (so the animation knows when regen started).
local function State(elapsed, icon, innerv, start)
    local c = db.regenColors
    if elapsed < RULE then
        local left = RULE - elapsed
        return { frac = elapsed / RULE, value = string.format("%.1fs", left), title = "Mana regen",
                 label = innerv and "Innervated" or "No regen", labelColor = innerv and c.regen or nil,
                 color = innerv and c.regen or c.waiting, icon = icon, hold = 0.6,
                 regen = true, flowFrom = innerv and start or nil, charge = elapsed / RULE }
    end
    return { frac = 1, value = "", title = "Mana regen", label = "Regenerating", labelColor = c.regen,
             color = c.regen, icon = icon, hold = 0.6,
             regen = true, flowFrom = start + RULE, doneAt = start + RULE, noBurst = not db.regenFx }
end

local SAMPLE_ICON = "Interface\\Icons\\Spell_Holy_FlashHeal"

local regenRing = CreateLiveRing({
    key = "regen",
    read = function(now)
        if not spent then return nil end
        local elapsed = now - spent.at
        if elapsed >= RULE + REGEN_SHOW then spent = nil return nil end
        return State(elapsed, spent.icon, innervated, spent.at)
    end,
    sample = function(t)
        local cycle = t % (RULE + REGEN_SHOW + 0.8)
        -- When this sample's mana was spent, rounded so it holds still from frame to frame.
        local start = math.floor((GetTime() - cycle) * 20 + 0.5) / 20
        return State(math.min(cycle, RULE + REGEN_SHOW), SAMPLE_ICON, false, start)
    end,
    decorate = function(st, frame, geom) ns.DrawRegenFx(st, frame, geom) end,
})

---------------------------------------------------------------------------
-- The animation: a dim glow while regen is held back, then mana flowing back in
---------------------------------------------------------------------------
-- While there's no regen, the ring charges up: a bright spark rides the end of the fill,
-- small motes are drawn into it, and a glow in the ring's color breathes in the middle,
-- all growing brighter as the five seconds run out. Once regen starts again (or all along during Innervate), the glow swells and motes of
-- mana spiral in from the ring to its middle; each mote starts its trip only after the
-- flow began, so they stream in rather than appearing everywhere at once. With the icon,
-- it also pops with the ring's usual burst. Worked out from the time, so previews play it.
local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR_TEX = "Interface\\Cooldown\\star4"
local MOTES = 12
local BITS = 6 -- motes drawn into the charging spark

local fx -- made on first use

local function Glow(frame, layer, sub)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    if t:SetTexture(GLOW_TEX) == false then t:SetTexture(STAR_TEX) end
    t:SetBlendMode("ADD")
    t:Hide()
    return t
end

local function Star(frame, sub)
    local t = frame:CreateTexture(nil, "OVERLAY", nil, sub)
    t:SetTexture(STAR_TEX)
    t:SetBlendMode("ADD")
    t:Hide()
    return t
end

local function BuildFx(frame)
    fx = { motes = {}, bits = {} }
    fx.glow = Glow(frame, "BACKGROUND", -5)
    fx.glow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    -- The charging spark at the end of the fill: a soft glow with a turning star on it.
    fx.tipGlow = Glow(frame, "OVERLAY", 4)
    fx.tipStar = Star(frame, 5)
    for i = 1, BITS do
        fx.bits[i] = { tex = Star(frame, 4), speed = 1 / (0.55 + (i * 0.29) % 0.35),
                       phase = (i * 0.618) % 1, angle = (i / BITS) * 2 * math.pi + (i * 0.73) % 0.6 }
    end
    for i = 1, MOTES do
        local t = frame:CreateTexture(nil, "ARTWORK", nil, 3)
        t:SetTexture(STAR_TEX)
        t:SetBlendMode("ADD")
        t:Hide()
        -- Fixed per mote so they don't move in lockstep.
        fx.motes[i] = { tex = t, speed = 1 / (0.9 + (i * 0.37) % 0.6), phase = (i * 0.618) % 1,
                        angle = (i / MOTES) * 2 * math.pi + (i * 0.41) % 0.5, size = 0.7 + (i * 0.53) % 0.5 }
    end
end

local function HideTip()
    fx.tipGlow:Hide()
    fx.tipStar:Hide()
    for _, b in ipairs(fx.bits) do b.tex:Hide() end
end

local function HideFx()
    if not fx then return end
    fx.glow:Hide()
    for _, m in ipairs(fx.motes) do m.tex:Hide() end
    HideTip()
end

-- Charging: the spark at the end of the fill (fraction `charge` round the ring), brighter
-- and bigger the nearer regen is, with motes drawn in to it from around.
local function DrawTip(frame, geom, charge, c, now)
    local x, y = ns.RingPoint(geom, charge)
    local k = 0.35 + 0.65 * charge -- how charged
    local pulse = 0.85 + 0.15 * math.sin(now * (6 + 10 * charge))
    local wr, wg, wb = c.r + (1 - c.r) * 0.6, c.g + (1 - c.g) * 0.6, c.b + (1 - c.b) * 0.6
    local T = math.max(3, geom.T)

    local gs = T * (2.6 + 1.6 * k) * pulse
    fx.tipGlow:ClearAllPoints()
    fx.tipGlow:SetPoint("CENTER", frame, "CENTER", x, y)
    fx.tipGlow:SetSize(gs, gs)
    fx.tipGlow:SetVertexColor(c.r, c.g, c.b)
    fx.tipGlow:SetAlpha(0.9 * k)
    fx.tipGlow:Show()

    local ss = T * (1.6 + 1.0 * k)
    fx.tipStar:ClearAllPoints()
    fx.tipStar:SetPoint("CENTER", frame, "CENTER", x, y)
    fx.tipStar:SetSize(ss, ss)
    fx.tipStar:SetVertexColor(wr, wg, wb)
    fx.tipStar:SetAlpha(k * pulse)
    if fx.tipStar.SetRotation then fx.tipStar:SetRotation(now * 2.5) end
    fx.tipStar:Show()

    for i, b in ipairs(fx.bits) do
        local u = (now * b.speed + b.phase) % 1
        local d = T * (1.2 + 2.6 * k) * (1 - u) ^ 1.5 -- from out around the spark, in to it
        local a = b.angle + u * 1.2
        local s = T * 0.7 * (1 - 0.5 * u)
        b.tex:ClearAllPoints()
        b.tex:SetPoint("CENTER", frame, "CENTER", x + math.cos(a) * d, y + math.sin(a) * d)
        b.tex:SetSize(s, s)
        b.tex:SetVertexColor(wr, wg, wb)
        b.tex:SetAlpha(k * math.min(1, u * 5) * (1 - u ^ 4))
        b.tex:Show()
    end
end

local function DrawRegenFx(st, frame, geom)
    if not (st and st.regen and db.regenFx) or not geom or geom.R <= 0 then return HideFx() end
    if not fx then BuildFx(frame) end
    local now = GetTime()
    local ri = math.max(4, geom.R - geom.T / 2)
    local c = st.color
    local flowing = st.flowFrom and now - st.flowFrom or nil
    if flowing and flowing < 0 then flowing = nil end

    -- The glow: faint and slow while regen is held back, swelling once it flows.
    local alpha, size
    if flowing then
        local k = math.min(1, flowing / 0.3)
        alpha = 0.18 + 0.32 * k + 0.05 * math.sin(now * 5)
        size = ri * (1.6 + 0.5 * k)
    else
        local charge = st.charge or 0
        alpha = 0.10 + 0.18 * charge + 0.06 * math.sin(now * (2.2 + 3 * charge))
        size = ri * (1.4 + 0.3 * charge)
    end
    fx.glow:SetSize(size, size)
    fx.glow:SetVertexColor(c.r, c.g, c.b)
    fx.glow:SetAlpha(alpha)
    fx.glow:Show()

    if st.charge then DrawTip(frame, geom, st.charge, c, now) else HideTip() end

    -- Motes: from the ring, spiralling in to the middle, brightening toward white.
    for i, m in ipairs(fx.motes) do
        local u = (now * m.speed + m.phase) % 1
        if flowing and now - u / m.speed >= st.flowFrom then
            local r = geom.R * (1 - 0.85 * u ^ 1.3)
            local a = m.angle + u * 1.4
            local s = ri * 0.22 * m.size * (1 - 0.45 * u)
            m.tex:ClearAllPoints()
            m.tex:SetPoint("CENTER", frame, "CENTER", math.sin(a) * r, math.cos(a) * r)
            m.tex:SetSize(s, s)
            m.tex:SetVertexColor(c.r + (1 - c.r) * u * 0.6, c.g + (1 - c.g) * u * 0.6, c.b + (1 - c.b) * u * 0.6)
            m.tex:SetAlpha(math.min(1, u * 6) * (1 - u ^ 3) * (0.8 + 0.2 * math.sin(now * 11 + i * 2.3)))
            m.tex:Show()
        else
            m.tex:Hide()
        end
    end
end
ns.DrawRegenFx = DrawRegenFx
ns.RegenFxParts = function() return fx end -- for the tests

ns.Listen({ "UNIT_AURA:player", "PLAYER_ENTERING_WORLD" }, function() ScanBuffs() end)

-- Your own spells: a success (instant or cast), or a channel starting.
ns.Listen({ "UNIT_SPELLCAST_SUCCEEDED:player", "UNIT_SPELLCAST_CHANNEL_START:player" }, function(event, _, castGUID, spellID)
    if not CircletDB or not db.regenEnabled then return end
    Spend(spellID, castGUID)
end)

-- Shared with the files loaded after this one.
ns.regenRing = regenRing
ns.PreviewRegenRing = function() regenRing.Preview(14) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "regen", name = "Mana regen", order = 14.9, since = "1.3.0",
    iconBg = true, -- "Icon as background": the spell's icon fills the ring's middle (Core/Settings.lua, UI/Options/Kit.lua)
    ring = regenRing,
    preview = ns.PreviewRegenRing, slash = { "regen", "fsr", "mana" }, help = "preview the mana regen ring",
    toggle = { "Mana regen ring", "The five-second rule: when your mana regen starts again after you spend mana." },
    defaults = {
        -- Mana regen ring: the five seconds without regen after spending mana. Right of the loot roll ring.
        regenEnabled   = true,
        regenFx        = true, -- the glow and the mana flowing back in
        regenSize      = 80,
        regenThickness = 8,
        regenOpacity   = 100,
        regenX         = 340,
        regenFromTop   = 385,
        regenHold      = 0.6,
        regenStyle     = "smooth",
        regenBorder    = 2,
        regenColors = {
            waiting = { r = 0.30, g = 0.45, b = 0.85 },
            regen   = { r = 0.45, g = 0.80, b = 1.00 },
        },
    },
    page = { folder = "combat", order = 5, build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(10.97, "Mana regen", "Mana Regen Ring",
                "The five-second rule: spending mana stops your mana regen for five seconds. Each time you cast a "
                .. "spell that costs mana, the ring fills over those five seconds, counting down to when regen "
                .. "starts again, then lights up and fades. Free spells and rage or energy abilities don't start it.",
                MergeTop(TopRow("regen", "mana regen ring", ns.PreviewRegenRing,
                    "Show a sample: five seconds without regen, then regen starting. Also /circ regen."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "regenEnabled", "Show mana regen ring",
                            "Count down the five seconds without mana regen after you spend mana."),
                        fx = Toggle(2, "regenFx", "Animations",
                            "While regen is held back, a spark charges up at the end of the fill; when it "
                            .. "starts again, motes of mana flow back in and the icon bursts."),
                    }),
                    colors = Box(3, "Colors", {
                        waiting = Color(1, "regenColors", "waiting", "No regen", "Ring color during the five seconds."),
                        regen = Color(2, "regenColors", "regen", "Regenerating", "Ring and label color once regen starts again."),
                    }),
                    size = SizeBox(4, "regen", "mana regen ring", "Offset from the center of the screen."),
                }))
            tab.args.size.args.hold.desc = "How long the ring stays after regen starts again."
            return tab
        end },
})
