-- Circlet: Event handling and the /sq slash command.
local ADDON_NAME, ns = ...

local ADDON_NAME, DEFAULTS, OBSOLETE, OnRestedChanged, OnXPCombatEnd = ns.ADDON_NAME, ns.DEFAULTS, ns.OBSOLETE, ns.OnRestedChanged, ns.OnXPCombatEnd
local OnXPCombatStart, OnXPUpdate, OpenOptions, PreviewAmmoRing, PreviewLevelUp = ns.OnXPCombatStart, ns.OnXPUpdate, ns.OpenOptions, ns.PreviewAmmoRing, ns.PreviewLevelUp
local PreviewPetRing, PreviewQuestComplete, PreviewQuestRing, PreviewRepRing, PreviewSkillRing = ns.PreviewPetRing, ns.PreviewQuestComplete, ns.PreviewQuestRing, ns.PreviewRepRing, ns.PreviewSkillRing
local PreviewXPRing, Print, QueueCheckAmmo, QueueCheckFactions, QueueCheckPet = ns.PreviewXPRing, ns.Print, ns.QueueCheckAmmo, ns.QueueCheckFactions, ns.QueueCheckPet
local QueueCheckProgress, QueueCheckSkills, ResetPosition, ResetPositions, ShowXPIdle = ns.QueueCheckProgress, ns.QueueCheckSkills, ns.ResetPosition, ns.ResetPositions, ns.ShowXPIdle
local ToggleAllEditing, ToggleIconGrid, ToggleRingEditing, TrySetupOptions, ammoRing = ns.ToggleAllEditing, ns.ToggleIconGrid, ns.ToggleRingEditing, ns.TrySetupOptions, ns.ammoRing
local petRing, questRing, repRing, skillRing, xpState = ns.petRing, ns.questRing, ns.repRing, ns.skillRing, ns.xpState

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------


-- Fills in every setting missing from CircletDB with its default.
local function FillDefaults()
    for k, v in pairs(DEFAULTS) do
        if CircletDB[k] == nil then
            CircletDB[k] = (type(v) == "table") and CopyTable(v) or v
        end
    end
    -- Fill in any color missing from a saved color table (e.g. one added in an update).
    for _, group in ipairs({ "skillColors", "weaponColors", "questColors", "repColors", "ammoColors", "petColors", "flightColors",
                           "timedColors", "corpseColors", "breathColors", "craftColors", "gatherColors", "castColors",
                           "totemColors" }) do
        for name, color in pairs(DEFAULTS[group]) do
            if type(CircletDB[group][name]) ~= "table" then
                CircletDB[group][name] = CopyTable(color)
            end
        end
    end
end
ns.FillDefaults = FillDefaults

local events = CreateFrame("Frame")

local function OnEvent(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        CircletDB = CircletDB or {}
        ns.LoadProfile() -- this character's profile into CircletDB (migrations and defaults follow)
        -- The level-up effect used to be an on/off checkbox; keep "off" if it was off.
        if CircletDB.xpLevelFx == false and CircletDB.xpLevelFxStyle == nil then
            CircletDB.xpLevelFxStyle = "none"
        end
        -- Single crafts used to be off by default; they're on now (once, so turning it
        -- off again sticks).
        if not CircletDB.craftSingleDefaultOn then
            CircletDB.craftSingle = true
            CircletDB.craftSingleDefaultOn = true
        end
        -- Rotation briefly defaulted to 0; it's 180 now. Rings left at 0 move to the new
        -- default (once, so choosing 0 again sticks).
        -- "Hide text when idle" (0.58) is on by default from 0.58.1.
        if not CircletDB.xpHideTextDefaultOn then
            CircletDB.xpHideText = nil
            CircletDB.xpHideTextDefaultOn = true
        end
        -- The skill ring split in two (0.57): weapon skills moved to their own ring, which
        -- starts with the skill ring's look and the weapon settings you had.
        if not CircletDB.weaponSplit then
            if CircletDB.skillWeapons == false then CircletDB.weaponEnabled = false end
            if CircletDB.skillEnabled == false then CircletDB.weaponEnabled = false end
            local sc = CircletDB.skillColors
            if type(sc) == "table" and type(sc.weapon) == "table" then
                CircletDB.weaponColors = { fill = CopyTable(sc.weapon),
                    capped = type(sc.capped) == "table" and CopyTable(sc.capped) or nil }
                sc.weapon = nil
            end
            for _, f in ipairs({ "AfterCombat", "ShowDelta", "IconAlpha", "IconStyle", "Size", "Thickness", "Opacity",
                                 "Hold", "Style", "Border", "Shape", "Rotation", "Fill", "Gradient", "Combat" }) do
                if CircletDB["skill" .. f] ~= nil and CircletDB["weapon" .. f] == nil then
                    CircletDB["weapon" .. f] = CircletDB["skill" .. f]
                end
            end
            CircletDB.weaponAfterCombat = true
            CircletDB.skillWeapons = nil
            CircletDB.weaponSplit = true
        end
        -- Settings for features taken out again: icon in front / behind (0.53.0) and the
        -- shaman shield and weapon rings (0.54.0).
        for k in pairs(CircletDB) do
            if type(k) == "string" and (k:match("IconLayer$") or k:match("^shaman%u")) then CircletDB[k] = nil end
        end
        if not CircletDB.rotationDefault180 then
            for k, v in pairs(CircletDB) do
                if type(k) == "string" and k:match("Rotation$") and v == 0 then CircletDB[k] = nil end
            end
            CircletDB.rotationDefault180 = true
        end
        -- The corpse, flight and timed quest rings used to start on top of the crafting
        -- ring; move them to their new spots unless they've been placed by hand.
        if not CircletDB.rowLayout2 then
            for key, old in pairs({ corpse = { 0, 200 }, flight = { 0, 200 }, timed = { 640, 190 } }) do
                if CircletDB[key .. "X"] == old[1] and CircletDB[key .. "FromTop"] == old[2] then
                    CircletDB[key .. "X"], CircletDB[key .. "FromTop"] = nil, nil -- defaults fill in below
                end
            end
            CircletDB.rowLayout2 = true
        end
        -- Second row, spaced like the first (170 apart, centres level): the corpse ring
        -- left of the crafting ring, then flight and timed quest to its right. Lined up
        -- on the crafting ring's current spot.
        if not CircletDB.rowLayout3 then
            local craftX = CircletDB.craftX or DEFAULTS.craftX
            local centre = (CircletDB.craftFromTop or DEFAULTS.craftFromTop)
                + (CircletDB.craftSize or DEFAULTS.craftSize) / 2
            for key, offset in pairs({ corpse = -170, flight = 170, timed = 340 }) do
                CircletDB[key .. "X"] = craftX + offset
                CircletDB[key .. "FromTop"] = math.floor(centre - (CircletDB[key .. "Size"] or DEFAULTS[key .. "Size"]) / 2 + 0.5)
            end
            CircletDB.rowLayout3 = true
        end
        -- Quest rings start just left of where the quest list sits on the right edge.
        if CircletDB.pinX == nil and UIParent and UIParent.GetWidth then
            CircletDB.pinX = math.max(0, math.floor(UIParent:GetWidth() / 2 - 330))
        end
        for _, key in ipairs(OBSOLETE) do
            CircletDB[key] = nil
        end
        ns.FillDefaults()
        events:UnregisterEvent("ADDON_LOADED")
        ns.RefreshPinClicks() -- quest rings' right-click setting, now that settings are loaded

        -- If the options libraries misbehave on this client, don't take the whole addon down.
        local ok, err = TrySetupOptions()
        if not ok then
            Print("Couldn't build the options window:", err)
        end

    elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
        QueueCheckProgress()

    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        QueueCheckSkills()

    elseif event == "UPDATE_FACTION" or event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        QueueCheckFactions()

    elseif event == "PLAYER_REGEN_ENABLED" then
        OnXPCombatEnd()
        skillRing.CombatEnd()
        ns.weaponRing.CombatEnd()
        questRing.CombatEnd()
        repRing.CombatEnd()
        ammoRing.CombatEnd()
        petRing.CombatEnd()

    elseif event == "PLAYER_REGEN_DISABLED" then
        OnXPCombatStart()
        skillRing.CombatStart()
        ns.weaponRing.CombatStart()
        questRing.CombatStart()
        repRing.CombatStart()
        ammoRing.CombatStart()
        petRing.CombatStart()

    elseif event == "PLAYER_ENTERING_WORLD" then
        OnXPUpdate() -- baseline (or catch up after a loading screen)
        ShowXPIdle()  -- permanent XP ring, if turned on
        if IsResting and IsResting() then ns.OnRestingChanged() end -- rested baseline if logging in at an inn
        QueueCheckSkills()
        QueueCheckFactions()
        QueueCheckAmmo()
        QueueCheckPet()

    elseif event == "UNIT_INVENTORY_CHANGED" or event == "BAG_UPDATE_DELAYED"
        or event == "PLAYER_EQUIPMENT_CHANGED" then
        QueueCheckAmmo()

    elseif event == "UNIT_PET_EXPERIENCE" or event == "UNIT_PET" or event == "PET_UI_UPDATE"
        or (event == "UNIT_LEVEL" and arg1 == "pet") then
        QueueCheckPet()

    elseif event == "PLAYER_XP_UPDATE" then
        OnXPUpdate()

    elseif event == "UPDATE_EXHAUSTION" or event == "PLAYER_UPDATE_RESTING" then
        OnRestedChanged()
        if event == "PLAYER_UPDATE_RESTING" then ns.OnRestingChanged() end

    elseif event == "PLAYER_LEVEL_UP" then
        -- UnitLevel can lag a moment behind this event; remember the new level.
        xpState.pendingLevel = tonumber(arg1)
    end
end

events:SetScript("OnEvent", OnEvent)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterUnitEvent("UNIT_QUEST_LOG_CHANGED", "player")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterUnitEvent("PLAYER_XP_UPDATE", "player")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("UPDATE_EXHAUSTION")
events:RegisterEvent("PLAYER_UPDATE_RESTING")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("CHAT_MSG_SKILL")
events:RegisterEvent("UPDATE_FACTION")
events:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
-- Events this client might not have: registering an unknown one is an error, so try each.
for _, e in ipairs({ { "UNIT_INVENTORY_CHANGED", "player" }, { "BAG_UPDATE_DELAYED" }, { "PLAYER_EQUIPMENT_CHANGED" },
                     { "UNIT_PET_EXPERIENCE", "player" }, { "UNIT_PET", "player" }, { "PET_UI_UPDATE" },
                     { "UNIT_LEVEL", "pet" } }) do
    if e[2] then
        pcall(events.RegisterUnitEvent, events, e[1], e[2])
    else
        pcall(events.RegisterEvent, events, e[1])
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_CIRCLET1 = "/sq" -- short; kept from the addon's working name
SLASH_CIRCLET2 = "/circlet"
SLASH_CIRCLET3 = "/circ"
SlashCmdList.CIRCLET = function(msg)
    local cmd = strtrim(msg or ""):lower()
    local arg
    cmd, arg = cmd:match("^(%S*)%s*(.-)$")

    if cmd == "" or cmd == "config" or cmd == "options" then
        OpenOptions()
    elseif cmd == "quest" or cmd == "pop" then
        PreviewQuestRing()
    elseif cmd == "complete" then
        PreviewQuestComplete()
    elseif cmd == "xp" then
        PreviewXPRing()
    elseif cmd == "levelup" then
        PreviewLevelUp()
    elseif cmd == "edit" or cmd == "move" or cmd == "unlock" or cmd == "lock" then
        local ring = ({ xp = "xp", quest = "quest", skill = "skill", skills = "skill", professions = "skill", weapon = "weapon", weapons = "weapon",
                        rep = "rep", reputation = "rep", ammo = "ammo", pet = "pet",
                        flight = "flight", taxi = "flight", timed = "timed", timer = "timed",
                        corpse = "corpse", ghost = "corpse", breath = "breath", craft = "craft",
                        crafting = "craft", gather = "gather", gathering = "gather", cast = "cast", casting = "cast", pin = "pin", pins = "pin", rings = "pin",
                        totem = "totem", totems = "totem" })[arg]
        if ring then
            ToggleRingEditing(ring)
        elseif arg == "" or arg == "all" then
            ToggleAllEditing()
        else
            Print("Unknown ring '" .. arg .. "'. Use xp, quest, skill, weapon, rep, pet, ammo, flight, timed, corpse, breath, craft, gather, cast, pins, totems or all.")
        end
    elseif cmd == "resetpos" or cmd == "resetpositions" then
        local ring = ({ xp = "xp", quest = "quest", skill = "skill", skills = "skill", professions = "skill", weapon = "weapon", weapons = "weapon",
                        rep = "rep", reputation = "rep", ammo = "ammo", pet = "pet",
                        flight = "flight", taxi = "flight", timed = "timed", timer = "timed",
                        corpse = "corpse", ghost = "corpse", breath = "breath", craft = "craft",
                        crafting = "craft", gather = "gather", gathering = "gather", cast = "cast", casting = "cast", pin = "pin", pins = "pin", rings = "pin",
                        totem = "totem", totems = "totem" })[arg]
        if ring then
            ResetPosition(ring)
        elseif arg == "" or arg == "all" then
            ResetPositions()
        else
            Print("Unknown ring '" .. arg .. "'. Use xp, quest, skill, weapon, rep, pet, ammo, flight, timed, corpse, breath, craft, gather, cast, pins, totems or all.")
        end
    elseif cmd == "skill" or cmd == "skills" or cmd == "professions" then
        PreviewSkillRing()
    elseif cmd == "weapon" or cmd == "weapons" then
        ns.PreviewWeaponRing()
    elseif cmd == "icons" then
        ToggleIconGrid()
    elseif cmd == "rep" or cmd == "reputation" then
        PreviewRepRing()
    elseif cmd == "ammo" then
        PreviewAmmoRing()
    elseif cmd == "flight" or cmd == "taxi" then
        ns.PreviewFlightRing()
    elseif cmd == "timed" or cmd == "timer" then
        ns.PreviewTimedRing()
    elseif cmd == "profile" or cmd == "profiles" then
        if arg ~= "" then
            local list = ns.ProfileList()
            local match
            for name in pairs(list) do if name:lower() == arg:lower() then match = name end end
            if match then ns.SwitchProfile(match) else Print("No profile called " .. arg .. ".") end
        else
            local _, order = ns.ProfileList()
            Print("Profile: |cffffd100" .. tostring(ns.CurrentProfile()) .. "|r. All: " .. table.concat(order, ", ")
                .. ". Switch with /sq profile <name>.")
        end
    elseif cmd == "breath" or cmd == "bubbles" then
        ns.PreviewBreathRing()
    elseif cmd == "corpse" or cmd == "ghost" then
        ns.PreviewCorpseRing()
    elseif cmd == "totemdebug" then
        ns.TotemDebug()
    elseif cmd == "totem" or cmd == "totems" then
        ns.PreviewTotems()
    elseif cmd == "hello" or cmd == "welcome" then
        ns.PreviewWelcome()
    elseif cmd == "discover" or cmd == "discovered" or cmd == "explore" then
        ns.PreviewDiscovery()
    elseif cmd == "ring" then
        ns.SlashRing(arg)
    elseif cmd == "craft" or cmd == "crafting" then
        ns.PreviewCraftRing()
    elseif cmd == "cast" or cmd == "casting" then
        ns.PreviewCastRing()
    elseif cmd == "gather" or cmd == "gathering" then
        ns.PreviewGatherRing()
    elseif cmd == "rested" then
        ns.PreviewRestedGain()
    elseif cmd == "summary" or cmd == "session" then
        ns.ToggleSummary()
    elseif cmd == "pet" then
        PreviewPetRing()
    else
        Print("commands:")
        print("  /sq             - open the options panel")
        print("  /sq quest       - preview the quest ring")
        print("  /sq complete    - preview the objective-complete animation")
        print("  /sq xp          - preview the XP ring")
        print("  /sq levelup     - preview the level-up effect")
        print("  /sq skill       - preview the profession ring")
        print("  /sq weapon      - preview the weapon skill ring")
        print("  /sq icons       - list the game icons the rings use (found / missing)")
        print("  /sq rep         - preview the reputation ring")
        print("  /sq pet         - preview the pet ring")
        print("  /sq ammo        - preview the ammo ring")
        print("  /sq flight      - preview the flight ring")
        print("  /sq timed       - preview the timed quest ring")
        print("  /sq corpse      - preview the corpse ring")
        print("  /sq breath      - preview the breath ring")
        print("  /sq profile [name] - show or switch profiles")
        print("  /sq rested      - preview the rested XP gained ring")
        print("  /sq craft       - preview the crafting ring")
        print("  /sq gather      - preview the gathering ring")
        print("  /sq cast        - preview the cast ring")
        print("  /sq ring <name> - pin a quest to its own ring (or right-click it in the quest log); /sq ring clear")
        print("  /sq summary     - this session's summary")
        print("  /sq discover    - preview the discovered area animation")
        print("  /sq hello       - preview the welcome animation")
        print("  /sq totems      - preview the totem rings")
        print("  /sq edit [ring] - edit mode for one ring or all")
        print("  /sq resetpos [ring] - move one ring (or all) back to its default spot")
    end
end
