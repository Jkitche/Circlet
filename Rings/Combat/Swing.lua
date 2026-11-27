-- Circlet: Swing timer ring: time to your next melee swing.
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall, Clean, CleanNumber = ns.db, ns.CreateLiveRing, ns.SafeCall, ns.Clean, ns.CleanNumber

---------------------------------------------------------------------------
-- Swing timer ring
---------------------------------------------------------------------------
-- While you auto-attack, the ring fills over your weapon's speed and shows the time to your
-- next swing, then "Ready" until it lands. The label says how the last swing went (Hit,
-- Crit, Glancing, Miss, Dodged, Parried, Blocked).
--
-- This client keeps the combat log from addons, so swings are worked out from what it does
-- tell us:
--   * UNIT_COMBAT on your target: every hit or miss it takes, with the kind (WOUND, MISS,
--     DODGE...), a flag (CRITICAL, GLANCING) and the school; the amount is hidden, but the
--     timing is all we need. A physical one while you auto-attack is taken as your swing,
--     unless it comes with one of your own casts (Stormstrike, Sinister Strike...) or too
--     soon after the last swing to be yours (someone else hitting it, or an extra attack
--     like Windfury's).
--   * Heroic Strike, Cleave, Maul and Raptor Strike replace a swing: their cast is the swing.
--   * Finishing a spell with a cast time restarts the swing (no swings while casting).
--   * Auto-attack starting and stopping (PLAYER_ENTER_COMBAT / PLAYER_LEAVE_COMBAT), and
--     your attack speed (UnitAttackSpeed, rescaled when it changes: haste, slows).
-- Main hand only: an off-hand's swings can't be told apart from the main hand's.

local NEXT_SWING = { 78, 845, 6807, 2973 } -- Heroic Strike, Cleave, Maul, Raptor Strike (every rank by name)
local RESULTS = {
    WOUND = "Hit",
    MISS = "Miss",
    DODGE = "Dodged",
    PARRY = "Parried",
    BLOCK = "Blocked",
    DEFLECT = "Deflected",
    IMMUNE = "Immune",
    EVADE = "Evaded",
    ABSORB = "Absorbed",
}
local FLAGS = { CRITICAL = "Crit", GLANCING = "Glancing", CRUSHING = "Crushing" }
local MISSED = {
    Miss = true,
    Dodged = true,
    Parried = true,
    Blocked = true,
    Deflected = true,
    Immune = true,
    Evaded = true,
    Absorbed = true,
}
local WITH_CAST = 0.15 -- a hit this close to one of your casts is the cast's, not a swing
local TOO_SOON = 0.6 -- a hit sooner than this share of your speed after a swing isn't yours
local SAMPLE_SPEED = 2.6

local attacking = false
local last, result -- GetTime() of your last swing, and how it went
local casting -- GetTime() a cast with a cast time started, while it lasts
local lastCastAt = 0
local measured -- seconds between your last two swings, if UnitAttackSpeed is hidden

local function Speed()
    local s = CleanNumber(SafeCall(UnitAttackSpeed, "player"))
    if s and s > 0 then return s end
    return measured or 2
end

local nextSwingByID, nextSwingByName = {}, nil
for _, id in ipairs(NEXT_SWING) do
    nextSwingByID[id] = true
end

local function IsNextSwing(spellID)
    if not spellID then return false end
    if nextSwingByID[spellID] then return true end
    if not nextSwingByName then
        local names, any = {}, false
        for id in pairs(nextSwingByID) do
            local n = ns.SpellName(id)
            if n then
                names[n], any = true, true
            end
        end
        if not any then return false end
        nextSwingByName = names
    end
    local n = ns.SpellName(spellID)
    return n and nextSwingByName[n] or false
end

local function Swing(now, how)
    if last then
        local gap = now - last
        if gap > 0.5 and gap < 6 then measured = gap end
    end
    last, result = now, how
end

local function WeaponIcon() return SafeCall(GetInventoryItemTexture, "player", 16) or "Interface\\Icons\\INV_Sword_04" end

local function State(elapsed, speed, how, icon)
    local c = db.swingColors
    local left = speed - elapsed
    local missed = how and MISSED[how]
    local st = { title = "Swing", icon = icon, hold = 0.4 }
    if left > 0.05 then
        st.frac = math.min(1, elapsed / speed)
        st.value = string.format("%.1f", left)
        st.color = c.fill
    else
        st.frac, st.value, st.color = 1, "Ready", c.ready
    end
    st.label = how or ""
    st.labelColor = (how == "Crit" and c.crit) or (missed and c.miss) or nil
    return st
end

local swingRing = CreateLiveRing({
    key = "swing",
    watchEvery = 0.1,
    read = function(now)
        if not attacking then return nil end
        if casting then
            return {
                title = "Swing",
                frac = 0,
                value = "",
                label = "Casting",
                color = db.swingColors.fill,
                icon = WeaponIcon(),
                hold = 0.4,
            }
        end
        local speed = Speed()
        if not last then return State(speed, speed, nil, WeaponIcon()) end -- first swing: ready
        return State(now - last, speed, db.swingResult and result or nil, WeaponIcon())
    end,
    sample = function(t)
        local hows = { "Hit", "Crit", "Glancing", "Dodged", "Hit", "Parried" }
        local n = math.floor(t / SAMPLE_SPEED)
        local elapsed = t - n * SAMPLE_SPEED
        return State(
            elapsed,
            SAMPLE_SPEED,
            db.swingResult and hows[n % #hows + 1] or nil,
            "Interface\\Icons\\INV_Sword_04"
        )
    end,
})

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen({ "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT" }, function(event)
    attacking = event == "PLAYER_ENTER_COMBAT"
    if not attacking then casting = nil end
end)

-- Hits and misses your target takes.
ns.Listen({ "UNIT_COMBAT:target" }, function(_, unit, action, flag, _, school)
    if not attacking or casting then return end
    action, flag, school = Clean(action), Clean(flag), CleanNumber(school)
    local how = action and RESULTS[action]
    if not how then return end
    if school and school ~= 1 then return end -- not physical: a spell, not your weapon
    local now = GetTime()
    if now - lastCastAt <= WITH_CAST then return end -- your own strike (Stormstrike, Sinister Strike...)
    if last and now - last < Speed() * TOO_SOON then return end -- someone else, or an extra attack
    if how == "Hit" and flag and FLAGS[flag] then how = FLAGS[flag] end
    Swing(now, how)
end)

ns.Listen({
    "UNIT_SPELLCAST_START:player",
    "UNIT_SPELLCAST_STOP:player",
    "UNIT_SPELLCAST_SUCCEEDED:player",
    "UNIT_SPELLCAST_INTERRUPTED:player",
    "UNIT_SPELLCAST_FAILED:player",
}, function(event, _, _, spellID)
    local now = GetTime()
    if event == "UNIT_SPELLCAST_START" then
        casting = now
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        lastCastAt = now
        local id = CleanNumber(spellID)
        if IsNextSwing(id) then
            Swing(now, ns.SpellName(id) or "Hit")
        elseif casting then
            casting = nil
            if attacking then
                last, result = now, nil
            end -- a finished cast restarts the swing
        end
    elseif casting then -- stopped, interrupted or failed
        casting = nil
        if attacking and event ~= "UNIT_SPELLCAST_STOP" then
            last, result = now, nil
        end
    end
end)

-- Haste or a slow: keep how far through the swing you are, at the new speed.
local lastSpeed
ns.Listen({ "UNIT_ATTACK_SPEED:player", "PLAYER_ENTERING_WORLD" }, function()
    local s = CleanNumber(SafeCall(UnitAttackSpeed, "player"))
    if s and lastSpeed and last and s ~= lastSpeed then
        local now = GetTime()
        local frac = math.min(1, (now - last) / lastSpeed)
        last = now - frac * s
    end
    lastSpeed = s or lastSpeed
end)

ns.swingRing = swingRing
ns.PreviewSwingRing = function() swingRing.Preview(SAMPLE_SPEED * 4) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "swing",
    name = "Swing",
    order = 14.2,
    since = "1.4.0",
    iconBg = true,
    ring = swingRing,
    gameBar = "the game's swing timer bars", -- WoW Forever's own (Features/DefaultUI.lua)
    alwaysInCombat = true,
    preview = ns.PreviewSwingRing,
    slash = { "swing" },
    help = "preview the swing timer ring",
    toggle = { "Swing timer ring", "Time to your next melee swing while you auto-attack." },
    defaults = {
        -- Swing timer ring: left of the target cast ring.
        swingEnabled = true,
        swingResult = true, -- how the last swing went (Hit, Crit, Dodged...)
        swingSize = 80,
        swingThickness = 8,
        swingOpacity = 100,
        swingX = -170,
        swingFromTop = 385,
        swingHold = 0.4,
        swingStyle = "smooth",
        swingBorder = 2,
        swingColors = {
            fill = { r = 0.90, g = 0.75, b = 0.35 },
            ready = { r = 1.00, g = 0.95, b = 0.60 },
            crit = { r = 1.00, g = 0.55, b = 0.15 },
            miss = { r = 0.65, g = 0.65, b = 0.70 },
        },
    },
    page = {
        folder = "combat",
        order = 3,
        build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            return RingTab(
                13.2,
                "Swing timer",
                "Swing Timer Ring",
                "While you auto-attack, the ring fills over your weapon's speed and counts down to your next melee "
                    .. "swing, then says Ready until it lands, with how the last one went underneath. Heroic Strike, "
                    .. "Cleave, Maul and Raptor Strike count as the swing, and finishing a spell with a cast time "
                    .. "restarts it. The game doesn't let addons read the combat log, so swings are spotted from the hits "
                    .. "your target takes: in a group someone else's hit can now and then be taken for yours. Main hand only.",
                MergeTop(
                    TopRow(
                        "swing",
                        "swing timer ring",
                        ns.PreviewSwingRing,
                        "Show a few sample swings. Also /circ swing."
                    ),
                    {
                        general = Box(2, "General", {
                            enabled = Toggle(
                                1,
                                "swingEnabled",
                                "Show swing timer ring",
                                "Show the ring while you auto-attack."
                            ),
                            result = Toggle(
                                2,
                                "swingResult",
                                "Show how the last swing went",
                                "Hit, Crit, Glancing, Miss, Dodged, Parried or Blocked under the time."
                            ),
                        }),
                        colors = Box(3, "Colors", {
                            fill = Color(
                                1,
                                "swingColors",
                                "fill",
                                "Swinging",
                                "Ring color while the swing comes round."
                            ),
                            ready = Color(2, "swingColors", "ready", "Ready", "Ring color once the swing is ready."),
                            crit = Color(3, "swingColors", "crit", "Crit", "Label color for a critical hit."),
                            miss = Color(
                                4,
                                "swingColors",
                                "miss",
                                "Missed",
                                "Label color for a miss, dodge, parry or block."
                            ),
                        }),
                        size = SizeBox(4, "swing", "swing timer ring", "Offset from the center of the screen."),
                    }
                )
            )
        end,
    },
})
