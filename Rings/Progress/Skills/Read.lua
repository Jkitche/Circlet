-- Circlet: Skill rings: professions and secondary skills, and weapon skills.
local ADDON_NAME, ns = ...

local CreateProgressRing, IsSecret, WEAPON_GLYPHS, db = ns.CreateProgressRing, ns.IsSecret, ns.WEAPON_GLYPHS, ns.db

-- Shared by Rings/Progress/Skills/*.lua, which load in this order: Read, Fx, Ring, Register.
ns.SkillRings = ns.SkillRings or {}
local SK = ns.SkillRings

---------------------------------------------------------------------------
-- Skill ring: the same donut for professions, secondary skills and weapon skills
---------------------------------------------------------------------------
-- Forever replaced the global skill-line API with C_SkillInfo, whose lines carry
-- rank, maxRank and skillLineCategoryID. Skill-ups are found by diffing ranks on
-- SKILL_LINES_CHANGED, the same way progress pops diff the quest log.

-- SkillLineCategory IDs from the game data.
local SKILL_CATEGORY = { [6] = "weapon", [9] = "secondary", [11] = "profession" }

-- Vanilla skill line IDs, used when a line has no category and to find skills
-- hidden under collapsed headers in the Skills tab.
local KNOWN_SKILLS = {
    -- Weapon skills (and Defense)
    [43] = "weapon", [44] = "weapon", [45] = "weapon", [46] = "weapon", [54] = "weapon",
    [55] = "weapon", [95] = "weapon", [136] = "weapon", [160] = "weapon", [162] = "weapon",
    [172] = "weapon", [173] = "weapon", [176] = "weapon", [226] = "weapon", [228] = "weapon",
    [229] = "weapon", [473] = "weapon",
    -- Professions
    [164] = "profession", [165] = "profession", [171] = "profession", [182] = "profession",
    [186] = "profession", [197] = "profession", [202] = "profession", [333] = "profession",
    [393] = "profession",
    -- Secondary skills: First Aid, Cooking, Fishing, Riding
    [129] = "secondary", [185] = "secondary", [356] = "secondary", [762] = "secondary",
}

local SKILL_STYLE = {
    -- Colors live in db.skillColors so they can be changed in the options panel.
    weapon     = { label = "Weapon skill" },
    profession = { label = "Profession",      opt = "skillProfessions" },
    secondary  = { label = "Secondary skill", opt = "skillSecondary" },
}

-- Header names as a last resort (English, plus the game's own strings if present).
local function HeaderKind(name)
    if type(name) ~= "string" or IsSecret(name) then return nil end
    local n = name:lower()
    if (TRADE_SKILLS and n == TRADE_SKILLS:lower()) or n:find("profession") then return "profession" end
    if (SECONDARY_SKILLS and n == SECONDARY_SKILLS:lower()) or n:find("secondary") then return "secondary" end
    if n:find("weapon") then return "weapon" end
    return nil
end

local skillKinds = {} -- skillID -> kind, for every skill seen (seeded with the known IDs)
for id, kind in pairs(KNOWN_SKILLS) do skillKinds[id] = kind end

local function SnapshotLine(info, kind)
    local rank, max, name = info.rank, info.maxRank, info.name
    if IsSecret(rank) or IsSecret(max) or IsSecret(name) then return nil end
    if not rank or not max or max <= 1 then return nil end -- proficiencies (armor etc.) have no ranks
    return { name = name or "?", rank = rank, max = max, kind = kind }
end

local function ReadSkills()
    if not (C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo) then
        return nil
    end
    local out = {}
    local headerKind
    for i = 1, C_SkillInfo.GetNumSkillLines() do
        local info = C_SkillInfo.GetSkillLineInfo(i)
        if info then
            if info.isHeader then
                headerKind = HeaderKind(info.name)
            elseif info.skillID and not IsSecret(info.skillID) then
                local category = info.skillLineCategoryID
                if IsSecret(category) then category = nil end
                local kind = SKILL_CATEGORY[category] or KNOWN_SKILLS[info.skillID] or headerKind
                if kind then
                    skillKinds[info.skillID] = kind
                    out[info.skillID] = SnapshotLine(info, kind)
                end
            end
        end
    end
    -- Lines under a collapsed header aren't listed; look those up by ID instead
    -- (never touching the player's Skills tab).
    if C_SkillInfo.GetSkillLineInfoByID then
        for id, kind in pairs(skillKinds) do
            if out[id] == nil then
                local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, id)
                if ok and type(info) == "table" then
                    out[id] = SnapshotLine(info, kind)
                end
            end
        end
    end
    -- The same skill can turn up twice: under the ID the list gives it (Forever may use
    -- its own) and under the classic ID looked up above. That would pop two rings for one
    -- skill-up, the first with the generic icon. Keep one per name, preferring a classic
    -- ID (it has the skill's own icon), else the lower ID so the choice never flips.
    local byName = {}
    for id, s in pairs(out) do
        if s.name and s.name ~= "?" then
            local other = byName[s.name]
            if not other then
                byName[s.name] = id
            else
                local keep
                if KNOWN_SKILLS[id] and not KNOWN_SKILLS[other] then keep = id
                elseif KNOWN_SKILLS[other] and not KNOWN_SKILLS[id] then keep = other
                else keep = math.min(id, other) end
                out[keep == id and other or id] = nil
                byName[s.name] = keep
            end
        end
    end
    return out
end

-- Ring --------------------------------------------------------------------

-- The game's own icons for each skill (file paths under Interface\Icons). Each one
-- is checked before use; anything this client doesn't have falls back to its skill
-- type's icon, then to the drawn glyph.
local SKILL_ICONS = {
    -- Professions
    [164] = "Trade_BlackSmithing", [165] = "Trade_LeatherWorking", [171] = "Trade_Alchemy",
    [182] = "Trade_Herbalism", [186] = "Trade_Mining", [197] = "Trade_Tailoring",
    [202] = "Trade_Engineering", [333] = "Trade_Engraving", [393] = "INV_Misc_Pelt_Wolf_01",
    -- Secondary skills
    [129] = "Spell_Holy_SealOfSacrifice", [185] = "INV_Misc_Food_15", [356] = "Trade_Fishing",
    [762] = "Spell_Nature_Swiftness",
    -- Weapon skills
    [43] = "INV_Sword_04", [55] = "INV_Sword_39", [44] = "INV_Axe_01", [172] = "INV_Axe_09",
    [54] = "INV_Mace_01", [160] = "INV_Hammer_16", [173] = "INV_Weapon_ShortBlade_05",
    [136] = "INV_Staff_08", [229] = "INV_Spear_06", [45] = "INV_Weapon_Bow_02",
    [226] = "INV_Weapon_Crossbow_01", [46] = "INV_Weapon_Rifle_01", [176] = "INV_ThrowingKnife_02",
    [228] = "INV_Wand_04", [473] = "INV_Misc_MonsterClaw_02", [162] = "INV_Gauntlets_04",
    [95] = "Ability_Defend",
}
local SKILL_TYPE_ICONS = { weapon = "INV_Sword_04", profession = "Trade_BlackSmithing", secondary = "Trade_Fishing" }

local iconExists = {} -- path -> true/false, so each is only checked once
local function IconPath(name)
    if not name then return nil end
    local path = "Interface\\Icons\\" .. name
    if iconExists[path] == nil then
        if GetFileIDFromPath then
            local ok, id = pcall(GetFileIDFromPath, path)
            iconExists[path] = (ok and id ~= nil) and true or false
        else
            iconExists[path] = true -- can't check on this client; trust the table
        end
    end
    return iconExists[path] and path or nil
end

-- The game icon for a skill line, or nil if neither it nor its type's icon exists.
local function SkillIconPath(skillID, kind)
    return IconPath(SKILL_ICONS[skillID]) or IconPath(SKILL_TYPE_ICONS[kind])
end

local SKILL_GLYPH = { weapon = "sword", profession = "hammer", secondary = "hook" }
-- Profession / secondary skill tiers, by the cap training raises you to.
local SKILL_TIERS = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }

-- Two rings: "skill" for professions and secondary skills, "weapon" for weapon skills
-- (and Defense). Same look; each has its own settings and colors.
local function Colors(key) return key == "weapon" and db.weaponColors or db.skillColors end
local function KindColor(key, e)
    local c = Colors(key)
    return key == "weapon" and c.fill or c[e.kind] or c.profession
end

-- For the files loaded after this one.
SK.SKILL_STYLE = SKILL_STYLE
SK.ReadSkills = ReadSkills
SK.SKILL_ICONS = SKILL_ICONS
SK.IconPath = IconPath
SK.SkillIconPath = SkillIconPath
SK.SKILL_GLYPH = SKILL_GLYPH
SK.SKILL_TIERS = SKILL_TIERS
SK.Colors = Colors
SK.KindColor = KindColor
