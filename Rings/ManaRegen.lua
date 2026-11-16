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

local function State(elapsed, icon, innerv)
    local c = db.regenColors
    if elapsed < RULE then
        local left = RULE - elapsed
        return { frac = elapsed / RULE, value = string.format("%.1fs", left), title = "Mana regen",
                 label = innerv and "Innervated" or "No regen", labelColor = innerv and c.regen or nil,
                 color = innerv and c.regen or c.waiting, icon = icon, hold = 0.6 }
    end
    return { frac = 1, value = "", title = "Mana regen", label = "Regenerating", labelColor = c.regen,
             color = c.regen, icon = icon, hold = 0.6 }
end

local SAMPLE_ICON = "Interface\\Icons\\Spell_Holy_FlashHeal"

local regenRing = CreateLiveRing({
    key = "regen",
    read = function(now)
        if not spent then return nil end
        local elapsed = now - spent.at
        if elapsed >= RULE + REGEN_SHOW then spent = nil return nil end
        return State(elapsed, spent.icon, innervated)
    end,
    sample = function(t)
        local cycle = t % (RULE + REGEN_SHOW + 0.8)
        return State(math.min(cycle, RULE + REGEN_SHOW), SAMPLE_ICON)
    end,
})

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
    iconBg = true, -- "Icon as background": the spell's icon fills the ring's middle (Core/Settings.lua, UI/OptionsKit.lua)
    ring = regenRing,
    preview = ns.PreviewRegenRing, slash = { "regen", "fsr", "mana" }, help = "preview the mana regen ring",
    toggle = { "Mana regen ring", "The five-second rule: when your mana regen starts again after you spend mana." },
    defaults = {
        -- Mana regen ring: the five seconds without regen after spending mana. Right of the loot roll ring.
        regenEnabled   = true,
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
    page = { folder = "status", order = 4.95, build = function(O)
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
