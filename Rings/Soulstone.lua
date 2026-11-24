-- Circlet: Soulstone ring (warlocks): who has your soulstone, and for how long.
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall, Clean, CleanNumber = ns.db, ns.CreateLiveRing, ns.SafeCall, ns.Clean, ns.CleanNumber

---------------------------------------------------------------------------
-- Soulstone ring
---------------------------------------------------------------------------
-- When you put a soulstone on someone (Soulstone Resurrection, any rank) the ring drains
-- over its 30 minutes with their name and the time left, turning the warning color in the
-- last few minutes. When it runs out it says Expired; if it's gone early (they used it,
-- died with it, or it was dispelled) it says Used. With soulstoneRemind on, out of combat,
-- when no stone is out but you have one in your bags off cooldown, it says No soulstone.
--
-- The cast tells us who and when (UNIT_SPELLCAST_SENT has the target's name). Out of combat
-- we can read buffs, so whenever we can see them we look for Soulstone Resurrection on that
-- person (you, your target, focus, party or raid) and set the time from the buff, or find
-- it gone. In combat buffs are hidden from addons, so the clock just runs. The stone's
-- holder and end time are saved (by the clock, time()), so they survive a reload or logout.

local DURATION = 30 * 60
local WARN = 5 * 60          -- the last five minutes: warning color
local SHOW_DONE = 8          -- how long Expired / Used stays up
local STONE_SPELLS = { 20707, 20762, 20763, 20764, 20765 } -- Soulstone Resurrection, Minor .. Major
local STONE_ITEMS = { 5232, 16892, 16893, 16895, 16896 }     -- Minor .. Major Soulstone
local ICON = "Interface\\Icons\\Spell_Shadow_SoulGem"

local stoneByID, stoneByName = {}, nil
for _, id in ipairs(STONE_SPELLS) do stoneByID[id] = true end

local function IsStone(spellID)
    spellID = CleanNumber(spellID)
    if not spellID then return false end
    if stoneByID[spellID] then return true end
    if not stoneByName then
        local names, any = {}, false
        for id in pairs(stoneByID) do
            local n = ns.SpellName(id)
            if n then names[n], any = true, true end
        end
        if not any then return false end
        stoneByName = names
    end
    local n = ns.SpellName(spellID)
    return n ~= nil and stoneByName[n] == true
end

local function StoneName()
    for _, id in ipairs(STONE_SPELLS) do
        local n = ns.SpellName(id)
        if n then return n end
    end
    return "Soulstone Resurrection"
end

local pendingTarget         -- the name from UNIT_SPELLCAST_SENT, until the cast succeeds
local done                  -- { how = "Expired" | "Used", who, at }

-- The stone that's out: db.soulstoneRun = { who, endsAt (time()) }.
local function Run()
    local r = db.soulstoneRun
    if type(r) ~= "table" or type(r.endsAt) ~= "number" then return nil end
    return r
end

local function Left(r) return r.endsAt - time() end

local function Finish(how)
    local r = Run()
    if not r then return end
    done = { how = how, who = r.who, at = GetTime() }
    db.soulstoneRun = nil
end

---------------------------------------------------------------------------
-- Reading the buff (out of combat)
---------------------------------------------------------------------------
-- The units we might see the holder as.
local function Units()
    local list = { "player", "target", "focus", "mouseover" }
    local raid = CleanNumber(SafeCall(GetNumGroupMembers)) or 0
    if SafeCall(IsInRaid) then
        for i = 1, raid do list[#list + 1] = "raid" .. i end
    else
        for i = 1, 4 do list[#list + 1] = "party" .. i end
    end
    return list
end

local function UnitFor(who)
    for _, unit in ipairs(Units()) do
        local n = Clean(SafeCall(UnitName, unit))
        if n and n == who then return unit end
    end
end

-- The stone buff on unit: found (true/false) and its end time (GetTime()), or nil if we
-- can't tell (hidden, too far away to see buffs).
local function BuffOn(unit)
    if InCombatLockdown and InCombatLockdown() then return nil end
    if SafeCall(UnitIsVisible, unit) == false then return nil end
    local want = StoneName()
    for i = 1, 40 do
        local name, expires
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = SafeCall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not a then break end
            name, expires = a.name, a.expirationTime
        elseif UnitBuff then
            local n, _, _, _, _, exp = SafeCall(UnitBuff, unit, i)
            if not n then break end
            name, expires = n, exp
        else
            return nil
        end
        name = Clean(name)
        if name == nil then return nil end -- hidden: can't tell
        if name == want then return true, CleanNumber(expires) end
    end
    return false
end

-- Checks the holder's buff, if we can see them: sets the time left from it, or finishes
-- the run as Used when it's gone.
local function Check()
    local r = Run()
    if not r or not r.who then return end
    local unit = UnitFor(r.who)
    if not unit then return end
    local found, expires = BuffOn(unit)
    if found == true then
        if expires and expires > 0 then
            r.endsAt = time() + math.floor(expires - GetTime() + 0.5)
        end
    elseif found == false and time() - (r.placedAt or 0) > 3 then -- the buff can lag the cast
        if Left(r) > 2 then Finish("Used") else Finish("Expired") end
    end
end

---------------------------------------------------------------------------
-- Bags: a stone to place?
---------------------------------------------------------------------------
local function StoneReady()
    for _, id in ipairs(STONE_ITEMS) do
        local count = CleanNumber((C_Item and C_Item.GetItemCount and SafeCall(C_Item.GetItemCount, id))
            or (GetItemCount and SafeCall(GetItemCount, id))) or 0
        if count > 0 then
            local getCD = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
            local start, duration = SafeCall(getCD, id)
            start, duration = CleanNumber(start), CleanNumber(duration)
            if not start or start == 0 or not duration or duration <= 1.5
                or start + duration - GetTime() <= 0 then
                return true, id
            end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- The ring
---------------------------------------------------------------------------
local function Clock(secs)
    secs = math.max(0, secs)
    if secs >= 60 then return string.format("%dm", math.ceil(secs / 60 - 0.01)) end
    return string.format("%ds", math.ceil(secs))
end

local function ActiveState(who, left)
    local c = db.soulstoneColors
    local warn = left <= WARN
    return { title = "Soulstone", icon = ICON, frac = math.max(0, math.min(1, left / DURATION)),
             value = Clock(left), label = who or "", color = warn and c.warn or c.fill,
             labelColor = warn and c.warn or nil, hold = 1 }
end

local lastCheck = 0
local stoneRing = CreateLiveRing({
    key = "soulstone",
    watchEvery = 1,
    read = function(now)
        if now - lastCheck >= 5 then lastCheck = now; Check() end
        local r = Run()
        if r then
            local left = Left(r)
            if left <= 0 then Finish("Expired")
            elseif db.soulstoneAlways or left <= WARN or (r.placedAt and time() - r.placedAt < 6) then
                return ActiveState(r.who, left)
            else
                return nil
            end
        end
        if done and now - done.at < SHOW_DONE then
            local c = db.soulstoneColors
            return { title = "Soulstone", icon = ICON, frac = 0, value = done.how, label = done.who or "",
                     color = c.warn, labelColor = c.warn, hold = 1 }
        end
        if db.soulstoneRemind and not (InCombatLockdown and InCombatLockdown())
            and not SafeCall(UnitIsDeadOrGhost, "player") and StoneReady() then
            local c = db.soulstoneColors
            return { title = "Soulstone", icon = ICON, frac = 1, value = "None out", label = "Ready to place",
                     color = c.ready, hold = 1 }
        end
        return nil
    end,
    sample = function(t)
        -- A stone running down quickly, then into the warning, then used.
        local left = DURATION * (1 - (t % 8) / 8)
        if t % 24 > 16 then return ActiveState("Thrall", WARN * (1 - (t % 8) / 8)) end
        return ActiveState("Thrall", left)
    end,
})

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen({ "UNIT_SPELLCAST_SENT:player" }, function(_, _, target, _, spellID)
    if IsStone(spellID) then pendingTarget = Clean(target) end
end)

ns.Listen({ "UNIT_SPELLCAST_SUCCEEDED:player" }, function(_, _, _, spellID)
    if not IsStone(spellID) then return end
    local who = pendingTarget
    if type(who) ~= "string" or who == "" then who = Clean(SafeCall(UnitName, "target")) end
    if type(who) ~= "string" or who == "" then who = Clean(SafeCall(UnitName, "player")) end
    if type(who) == "string" then who = who:match("^[^%-]+") or who end -- "Name-Realm": just the name
    pendingTarget = nil
    done = nil
    db.soulstoneRun = { who = who, endsAt = time() + DURATION, placedAt = time() }
end)

-- Buffs can be read again: check the holder now.
ns.Listen({ "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }, function()
    lastCheck = 0
end)

ns.soulstoneRing = stoneRing
ns.PreviewSoulstoneRing = function() stoneRing.Preview(24) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "soulstone", name = "Soulstone", order = 13.5, since = "1.5.0",
    class = { WARLOCK = true },
    iconBg = true,
    ring = stoneRing,
    preview = ns.PreviewSoulstoneRing, slash = { "soulstone", "ss" }, help = "preview the soulstone ring",
    toggle = { "Soulstone ring", "Who has your soulstone and how long it has left." },
    defaults = {
        -- Soulstone ring (warlocks): where the shaman's totem rings go.
        soulstoneEnabled   = true,
        soulstoneAlways    = true,  -- the whole 30 minutes; off: just the last five, and when it's placed
        soulstoneRemind    = true,  -- out of combat: a stone in your bags, none out
        soulstoneSize      = 80,
        soulstoneThickness = 8,
        soulstoneOpacity   = 100,
        soulstoneX         = -96,
        soulstoneFromTop   = 400,
        soulstoneHold      = 1,
        soulstoneStyle     = "smooth",
        soulstoneBorder    = 2,
        soulstoneColors = {
            fill  = { r = 0.62, g = 0.35, b = 0.95 },
            warn  = { r = 1.00, g = 0.35, b = 0.30 },
            ready = { r = 0.75, g = 0.60, b = 1.00 },
        },
    },
    page = { folder = "group", order = 3, build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            return RingTab(12.3, "Soulstone", "Soulstone Ring",
                "When you put a soulstone on someone, the ring drains over its 30 minutes with their name and the "
                .. "time left, turning red in the last five. It says Expired when it runs out, or Used if it's gone "
                .. "early. Buffs can only be read out of combat, so that's when it checks the stone is still there. "
                .. "It survives a reload or logging out.",
                MergeTop(TopRow("soulstone", "soulstone ring", ns.PreviewSoulstoneRing,
                    "Show a sample soulstone. Also /circ soulstone."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "soulstoneEnabled", "Show soulstone ring",
                            "Show the ring while one of your soulstones is out."),
                        always = Toggle(2, "soulstoneAlways", "Show for the whole 30 minutes",
                            "Off: only when you place it, in its last five minutes, and when it's gone."),
                        remind = Toggle(3, "soulstoneRemind", "Remind me when none is out",
                            "Out of combat, when you have a soulstone in your bags off cooldown and none is out, "
                            .. "the ring says None out."),
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "soulstoneColors", "fill", "Active", "Ring color while the stone is out."),
                        warn = Color(2, "soulstoneColors", "warn", "Running out",
                            "Ring color in the last five minutes, and when it's expired or used."),
                        ready = Color(3, "soulstoneColors", "ready", "Reminder", "Ring color for the None out reminder."),
                    }),
                    size = SizeBox(4, "soulstone", "soulstone ring", "Offset from the center of the screen."),
                }))
        end },
})
