-- Circlet: Reputation ring: gains, losses and new standings.
local ADDON_NAME, ns = ...

local CreateProgressRing, IconPath, IsSecret, db = ns.CreateProgressRing, ns.IconPath, ns.IsSecret, ns.db

---------------------------------------------------------------------------
-- Reputation ring: the same donut for reputation gains and losses
---------------------------------------------------------------------------
-- Forever's C_Reputation gives each faction its standing (reaction 1-8, Hated to
-- Exalted), currentStanding and the thresholds of that standing. The ring shows
-- progress through the current standing. Crossing into a new standing shows the
-- new standing filling from its start, labelled "Now Honored!".

local STANDING_NAMES = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
-- One distinct color per standing (Blizzard's own bar colors are green for everything
-- Friendly and up, which wouldn't tell standings apart on the ring).
local STANDING_COLORS = {
    { r = 0.70, g = 0.10, b = 0.10 }, -- Hated
    { r = 0.90, g = 0.25, b = 0.20 }, -- Hostile
    { r = 0.95, g = 0.50, b = 0.15 }, -- Unfriendly
    { r = 0.95, g = 0.82, b = 0.15 }, -- Neutral
    { r = 0.30, g = 0.80, b = 0.30 }, -- Friendly
    { r = 0.20, g = 0.80, b = 0.65 }, -- Honored
    { r = 0.30, g = 0.55, b = 1.00 }, -- Revered
    { r = 0.70, g = 0.40, b = 1.00 }, -- Exalted
}

local function StandingName(reaction)
    local label
    if GetText then
        local ok, text = pcall(GetText, "FACTION_STANDING_LABEL" .. reaction, UnitSex and UnitSex("player") or nil)
        if ok and type(text) == "string" and text ~= "" then label = text end
    end
    return label or _G["FACTION_STANDING_LABEL" .. reaction] or STANDING_NAMES[reaction] or "?"
end

local function StandingColor(reaction)
    if db.repUseStanding then
        return STANDING_COLORS[reaction] or STANDING_COLORS[4]
    end
    return db.repColors.custom
end

-- Faction icons: the game's own art, chosen per faction (there's no icon in the
-- reputation API). Missing or unlisted factions fall back to their group's icon
-- (Alliance / Horde banner, goblin coin for Steamwheedle); otherwise no badge.
local FACTION_ICONS = {
    -- Alliance capitals
    [72]  = "Achievement_Character_Human_Male",     -- Stormwind
    [47]  = "Achievement_Character_Dwarf_Male",     -- Ironforge
    [69]  = "Achievement_Character_Nightelf_Female", -- Darnassus
    [54]  = "Achievement_Character_Gnome_Male",     -- Gnomeregan Exiles
    -- Horde capitals
    [76]  = "Achievement_Character_Orc_Male",       -- Orgrimmar
    [81]  = "Achievement_Character_Tauren_Male",    -- Thunder Bluff
    [68]  = "Achievement_Character_Undead_Female",  -- Undercity
    [530] = "Achievement_Character_Troll_Male",     -- Darkspear Trolls
    -- Steamwheedle Cartel towns
    [21]  = "INV_Misc_Coin_01", [369] = "INV_Misc_Coin_01",  -- Booty Bay, Gadgetzan
    [470] = "INV_Misc_Coin_01", [577] = "INV_Misc_Coin_01",  -- Ratchet, Everlook
    -- Other vanilla factions
    [529] = "INV_Jewelry_Talisman_07",              -- Argent Dawn
    [59]  = "INV_Ingot_07",                         -- Thorium Brotherhood
    [576] = "INV_Misc_Horn_01",                     -- Timbermaw Hold
    [609] = "Spell_Nature_Regeneration",            -- Cenarion Circle
    [270] = "INV_Misc_Coin_08",                     -- Zandalar Tribe
    [749] = "Spell_Frost_SummonWaterElemental",     -- Hydraxian Waterlords
    [910] = "INV_Misc_Head_Dragon_Bronze",          -- Brood of Nozdormu
    [87]  = "INV_Misc_Bandana_03",                  -- Bloodsail Buccaneers
    [349] = "Ability_Stealth",                      -- Ravenholdt
    [589] = "Ability_Mount_WhiteTiger",             -- Wintersaber Trainers
    [809] = "INV_Misc_Book_11",                     -- Shen'dralar
    -- Battleground factions
    [890] = "INV_BannerPVP_02", [730] = "INV_BannerPVP_02", [509] = "INV_BannerPVP_02", -- Silverwing, Stormpike, Arathor
    [889] = "INV_BannerPVP_01", [729] = "INV_BannerPVP_01", [510] = "INV_BannerPVP_01", -- Warsong, Frostwolf, Defilers
}
local FACTION_GROUP_ICONS = { alliance = "INV_BannerPVP_02", horde = "INV_BannerPVP_01", goblin = "INV_Misc_Coin_01" }
local LOSS_COLOR = { r = 0.90, g = 0.20, b = 0.20 }

-- Which group a Reputation-tab header stands for, if any.
local function FactionGroup(headerName)
    if type(headerName) ~= "string" or IsSecret(headerName) then return nil end
    local n = headerName:lower()
    local alliance = (FACTION_ALLIANCE or "Alliance"):lower()
    local horde = (FACTION_HORDE or "Horde"):lower()
    if n == alliance or n:find("^" .. alliance) then return "alliance" end
    if n == horde or n:find("^" .. horde) then return "horde" end
    if n:find("steamwheedle") then return "goblin" end
    return nil
end

local function FactionIconPath(factionID, group)
    return IconPath(FACTION_ICONS[factionID]) or IconPath(FACTION_GROUP_ICONS[group])
end

local repRing = CreateProgressRing({
    key = "rep",
    samples = function()
        return {
            { id = "edit-r1", factionID = 72, group = "alliance", name = "Stormwind", reaction = 5, segment = 5,
              from = 2150, to = 2400, max = 6000 },
            { id = "edit-r2", factionID = 69, group = "alliance", name = "Darnassus", reaction = 6, segment = 6,
              from = 0, to = 350, max = 12000, change = "up", gainOffset = 120, editTime = 4 },
            { id = "edit-r3", factionID = 21, group = "goblin", name = "Booty Bay", reaction = 4, segment = 4,
              from = 1800, to = 1775, max = 3000 },
        }
    end,
    icon = function(e)
        if not db.repIcons then return nil end
        local texture = FactionIconPath(e.factionID or e.id, e.group)
        if not texture then return nil end -- no drawn fallback for factions
        local loss = e.change == "down" or e.to < e.from
        return { texture = texture, color = loss and LOSS_COLOR or StandingColor(e.reaction),
                 celebrate = e.change == "up" }
    end,
    style = function(e, finished)
        local c = StandingColor(e.reaction)
        local label = StandingName(e.reaction)
        if finished and e.change == "up" then
            label = "Now " .. label .. "!"
        elseif finished and e.change == "down" then
            label = "Dropped to " .. label
        end
        return { fill = c, rank = c, label = label, labelColor = c }
    end,
})

local function FactionSnapshot(d)
    if type(d) ~= "table" then return nil end
    if d.isHeader and not d.isHeaderWithRep then return nil end
    local id, name, reaction = d.factionID, d.name, d.reaction
    local low, high, cur = d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding
    for _, v in ipairs({ id, name, reaction, low, high, cur }) do
        if IsSecret(v) then return nil end
    end
    if not (id and reaction and low and high and cur) or high <= low then return nil end
    return { id = id, name = name or "?", reaction = reaction, cur = cur, low = low, high = high }
end

-- db.repKnown[id] is true, or the faction's group ("alliance" / "horde" / "goblin")
-- once it has been seen under a recognised header.

local function ReadFactions()
    if not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then
        return nil
    end
    local out = {}
    local group -- group of the header we're under
    for i = 1, C_Reputation.GetNumFactions() do
        local d = C_Reputation.GetFactionDataByIndex(i)
        if type(d) == "table" and d.isHeader then
            local g = FactionGroup(d.name)
            if g then group = g elseif not d.isChild then group = nil end
        end
        local s = FactionSnapshot(d)
        if s then
            s.group = group
            out[s.id] = s
            db.repKnown[s.id] = group or true
        end
    end
    if C_Reputation.GetWatchedFactionData then
        local ok, d = pcall(C_Reputation.GetWatchedFactionData)
        local s = ok and FactionSnapshot(d)
        if s then db.repKnown[s.id] = true end
    end
    -- Factions under a collapsed header aren't listed; look up the ones seen before by ID
    -- (never touching the player's Reputation tab).
    if C_Reputation.GetFactionDataByID then
        for id in pairs(db.repKnown) do
            if not out[id] then
                local ok, d = pcall(C_Reputation.GetFactionDataByID, id)
                local s = ok and FactionSnapshot(d) or nil
                if s and type(db.repKnown[id]) == "string" then s.group = db.repKnown[id] end
                out[id] = s
            end
        end
    end
    return out
end

local factionSnapshot

local function CheckFactions()
    local snap = ReadFactions()
    if not snap then return end
    local prev = factionSnapshot
    factionSnapshot = snap
    if not prev then return end -- first read is just the baseline

    for id, s in pairs(snap) do
        local was = prev[id]
        if was and s.cur ~= was.cur then
            if ns.SessionAdd then ns.SessionAdd("rep", s.name, s.cur - was.cur) end -- session summary
            local entry = { id = id, factionID = id, group = s.group, name = s.name, reaction = s.reaction,
                            segment = s.reaction, to = s.cur - s.low, max = s.high - s.low }
            if s.reaction > was.reaction then
                entry.from, entry.change = 0, "up"
                entry.gainOffset = was.high - was.cur -- the part earned finishing the old standing
            elseif s.reaction < was.reaction then
                entry.from, entry.change = entry.max, "down"
                entry.gainOffset = was.low - was.cur  -- the part lost emptying the old standing
            else
                entry.from = was.cur - was.low
            end
            repRing.Queue(entry)
        end
    end
end

local factionsQueued = false
local function QueueCheckFactions()
    if factionsQueued then return end
    factionsQueued = true
    C_Timer.After(0.2, function()
        factionsQueued = false
        CheckFactions()
    end)
end

local function PreviewRepRing()
    repRing.Preview({
        { id = -11, factionID = 72, group = "alliance", name = "Stormwind", reaction = 5, segment = 5,
          from = 2150, to = 2400, max = 6000 },
        { id = -12, factionID = 69, group = "alliance", name = "Darnassus", reaction = 6, segment = 6,
          from = 0, to = 350, max = 12000, change = "up", gainOffset = 120 },
        { id = -13, factionID = 21, group = "goblin", name = "Booty Bay", reaction = 4, segment = 4,
          from = 1800, to = 1775, max = 3000 },
    })
end

-- Shared with the files loaded after this one.
ns.FACTION_ICONS = FACTION_ICONS
ns.PreviewRepRing = PreviewRepRing
ns.QueueCheckFactions = QueueCheckFactions
ns.repRing = repRing
