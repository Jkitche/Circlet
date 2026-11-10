-- Circlet: Skill rings: professions and secondary skills, and weapon skills.
local ADDON_NAME, ns = ...

local CreateProgressRing, IsSecret, WEAPON_GLYPHS, db = ns.CreateProgressRing, ns.IsSecret, ns.WEAPON_GLYPHS, ns.db

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

local function MakeSkillRing(key, samples)
    return CreateProgressRing({
        key = key,
        samples = samples,
        icon = function(e)
            local capped = e.to >= e.max
            local celebrate = capped or e.change == "tier"
            local color = celebrate and Colors(key).capped or KindColor(key, e)
            local texture = (db[key .. "IconStyle"] == "game") and (e.icon or SkillIconPath(e.skillID, e.kind)) or nil
            return { glyph = e.glyph or SKILL_GLYPH[e.kind], texture = texture, color = color, celebrate = celebrate }
        end,
        style = function(e, finished)
            local c, cap = KindColor(key, e), Colors(key).capped
            local capped = e.to >= e.max
            local label, labelColor = SKILL_STYLE[e.kind].label, c
            if e.change == "tier" then
                local tier = SKILL_TIERS[e.max]
                return { fill = c, rank = c, labelColor = cap,
                         label = tier and ("Now " .. tier .. "!") or ("New cap: " .. e.max) }
            end
            if capped and finished then
                -- Kept short to fit inside the ring.
                label = (e.kind == "weapon") and "Capped for level" or "Visit a trainer"
                labelColor = cap
            end
            return { fill = capped and cap or c, rank = c, label = label, labelColor = labelColor }
        end,
    })
end

local skillRing = MakeSkillRing("skill", function()
    return {
        { id = "edit-s2", skillID = 186, name = "Mining", kind = "profession", from = 112, to = 115, max = 150 },
        { id = "edit-s3", skillID = 356, name = "Fishing", kind = "secondary", from = 40, to = 41, max = 150 },
        { id = "edit-s4", skillID = 185, name = "Cooking", kind = "secondary", from = 74, to = 75, max = 75,
          editTime = 4 },
        { id = "edit-s5", skillID = 197, name = "Tailoring", kind = "profession", from = 75, to = 75, max = 150,
          change = "tier", segment = "tier150", gainText = "+75 cap", editTime = 4 },
    }
end)

local weaponRing = MakeSkillRing("weapon", function()
    return {
        { id = "edit-w1", skillID = 43, name = "Swords", kind = "weapon", from = 141, to = 143, max = 150, glyph = "sword" },
        { id = "edit-w2", skillID = 45, name = "Bows", kind = "weapon", from = 88, to = 89, max = 150, glyph = "bow" },
        { id = "edit-w3", skillID = 95, name = "Defense", kind = "weapon", from = 148, to = 150, max = 150,
          editTime = 4 },
    }
end)

local skillSnapshot

local function CheckSkills()
    local snap = ReadSkills()
    if not snap then return end
    local prev = skillSnapshot
    skillSnapshot = snap
    if not prev then return end -- first read is just the baseline

    for id, s in pairs(snap) do
        local was = prev[id]
        if was and s.rank > was.rank and ns.SessionAdd then
            ns.SessionAdd("skills", s.name, s.rank - was.rank) -- for the session summary
        end
        local ring = s.kind == "weapon" and weaponRing or skillRing
        if was and (s.kind == "weapon" or db[SKILL_STYLE[s.kind].opt]) then
            if s.rank > was.rank then
                ring.Queue({ id = id, skillID = id, name = s.name, kind = s.kind, from = was.rank, to = s.rank,
                                  max = s.max, glyph = WEAPON_GLYPHS[id] })
            elseif s.max > was.max and s.kind ~= "weapon" then
                -- Trained to a new tier. (Weapon caps rise by themselves with every
                -- character level, so those are left out.)
                ring.Queue({ id = id, skillID = id, name = s.name, kind = s.kind, from = s.rank, to = s.rank,
                                  max = s.max, change = "tier", segment = "tier" .. s.max,
                                  gainText = "+" .. (s.max - was.max) .. " cap" })
            end
        end
    end
end

local skillsQueued = false
local function QueueCheckSkills()
    if skillsQueued then return end
    skillsQueued = true
    C_Timer.After(0.15, function()
        skillsQueued = false
        CheckSkills()
    end)
end

local function PreviewSkillRing()
    skillRing.Preview({
        { id = -2, skillID = 186, name = "Mining", kind = "profession", from = 112, to = 115, max = 150 },
        { id = -3, skillID = 185, name = "Cooking", kind = "secondary", from = 74, to = 75, max = 75 },
        { id = -4, skillID = 197, name = "Tailoring", kind = "profession", from = 75, to = 75, max = 150,
          change = "tier", segment = "tier150", gainText = "+75 cap" },
    })
end

local function PreviewWeaponRing()
    weaponRing.Preview({
        { id = -1, skillID = 43, name = "Swords", kind = "weapon", from = 141, to = 143, max = 150, glyph = "sword" },
        { id = -5, skillID = 45, name = "Bows", kind = "weapon", from = 88, to = 89, max = 150, glyph = "bow" },
        { id = -6, skillID = 95, name = "Defense", kind = "weapon", from = 148, to = 150, max = 150 },
    })
end

-- Skill changes, and a first read on login.
ns.Listen({ "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "PLAYER_ENTERING_WORLD" }, function() QueueCheckSkills() end)

-- Shared with the files loaded after this one.
ns.IconPath = IconPath
ns.PreviewSkillRing = PreviewSkillRing
ns.QueueCheckSkills = QueueCheckSkills
ns.SKILL_ICONS = SKILL_ICONS
ns.skillRing = skillRing
ns.weaponRing = weaponRing
ns.PreviewWeaponRing = PreviewWeaponRing

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "skill", name = "Profession", order = 4,
    -- The icon can be the ring's background (Core/Settings.lua, UI/OptionsKit.lua).
    iconBg = { disabled = function() return db.skillIconStyle ~= "game" end,
               note = "With game icons only (drawn icons already sit behind the text)." },
    ring = skillRing,
    preview = PreviewSkillRing, slash = { "skill", "skills", "professions" }, help = "preview the profession ring",
    toggle = { "Profession ring", "Fills when a profession or secondary skill goes up." },
    defaults = {
        skillEnabled     = true,
        skillAfterCombat = true,
        skillShowDelta   = false,
        skillIconAlpha   = 80, -- % opacity of the drawn skill-type icon behind the ring's text
        skillIconStyle   = "game", -- "game": the game's own icons as a badge; "drawn": line-drawn glyphs
        skillProfessions = true,
        skillSecondary   = true,
        skillSize        = 120,
        skillThickness   = 12,
        skillOpacity     = 100, -- percent
        skillX           = 170,
        skillFromTop     = 50,
        skillHold        = 3,
        skillStyle       = "smooth",
        skillBorder      = 2, -- black border width (0 = none)
        skillColors = {
            profession = { r = 0.32, g = 0.82, b = 0.36 },
            secondary  = { r = 0.26, g = 0.78, b = 0.86 },
            capped     = { r = 1.00, g = 0.82, b = 0.00 },
        },
    },
    page = { folder = "progress", order = 4, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(4, "Professions", "Profession Ring",
                "Pops up and fills when a profession (Mining, Tailoring...) or secondary skill (Cooking, First Aid, "
                .. "Fishing, Riding) goes up, or you train to a new tier. Weapon skills have their own ring.",
                MergeTop(TopRow("skill", "profession ring", PreviewSkillRing, "Show example skill-ups: a profession, a "
                    .. "secondary skill hitting its cap, and a profession trained to a new tier. Also /circ skill."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "skillEnabled", "Show profession ring", "Pop up and fill when a profession or secondary skill goes up."),
                        afterCombat = Toggle(2, "skillAfterCombat", "Wait until combat ends",
                            "Hold skill-ups earned in a fight (skinning or First Aid, say) and show them once combat ends."),
                        delta = Toggle(3, "skillShowDelta", "Show gain as %",
                            "Add a line under the gain showing it as a share of the skill's current cap, e.g. +4.2%."),
                    }),
                    types = Box(3, "Skill types", {
                        professions = Toggle(2, "skillProfessions", "Professions", "Mining, Tailoring, Alchemy and the like."),
                        secondary = Toggle(3, "skillSecondary", "Secondary skills", "Cooking, First Aid, Fishing and Riding."),
                    }),
                    icons = Box(4, "Icons", {
                        style = Select(1, "skillIconStyle", "Icon style", { game = "Game icons", drawn = "Drawn" },
                            { "game", "drawn" }, "Game icons: the game's own skill icons, as a round badge on the ring's "
                            .. "top edge. Drawn: simple line icons in the ring's centre, in the skill type's color."),
                        alpha = Range(2, "skillIconAlpha", "Drawn icon opacity", 10, 100, 5,
                            "How strongly a drawn icon shows behind the text. Lower it if the text gets hard to read.",
                            { disabled = function() return db.skillIconStyle ~= "drawn" end }),
                        list = Execute(3, "Show icon list", function() ns.ToggleIconGrid() end,
                            "Show every game icon the rings use, marked found or missing in this client. Also /circ icons."),
                    }),
                    colors = Box(5, "Colors", {
                        profession = Color(2, "skillColors", "profession", "Professions", "Ring and rank color for professions."),
                        secondary = Color(3, "skillColors", "secondary", "Secondary skills", "Ring and rank color for secondary skills."),
                        capped = Color(4, "skillColors", "capped", "Capped", "Ring color when a skill reaches its cap."),
                    }),
                    size = SizeBox(6, "skill", "profession ring",
                        "Offset from the center of the screen. The default sits just right of the XP ring."),
                }))
            return tab
        end },
})

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "weapon", name = "Weapon skill", order = 5,
    -- The icon can be the ring's background (Core/Settings.lua, UI/OptionsKit.lua).
    iconBg = { disabled = function() return db.weaponIconStyle ~= "game" end,
               note = "With game icons only (drawn icons already sit behind the text)." },
    ring = weaponRing,
    preview = PreviewWeaponRing, slash = { "weapon", "weapons" }, help = "preview the weapon skill ring",
    toggle = { "Weapon skill ring", "Fills when a weapon skill or Defense goes up." },
    defaults = {
        -- Weapon skill ring: weapon skills and Defense (the skill ring above is professions
        -- and secondary skills). Left of the reputation ring.
        weaponEnabled     = true,
        weaponAfterCombat = true,  -- weapon skills mostly go up mid-fight
        weaponShowDelta   = false,
        weaponIconAlpha   = 80,
        weaponIconStyle   = "game",
        weaponSize        = 120,
        weaponThickness   = 12,
        weaponOpacity     = 100,
        weaponX           = -510,
        weaponFromTop     = 50,
        weaponHold        = 3,
        weaponStyle       = "smooth",
        weaponBorder      = 2,
        weaponColors = {
            fill   = { r = 0.92, g = 0.40, b = 0.26 },
            capped = { r = 1.00, g = 0.82, b = 0.00 },
        },
    },
    page = { folder = "progress", order = 4.5, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(4.5, "Weapon skills", "Weapon Skill Ring",
                "Pops up and fills when a weapon skill (Swords, Bows...) or Defense goes up. They mostly rise in "
                .. "fights, so by default they wait until combat ends.",
                MergeTop(TopRow("weapon", "weapon skill ring", ns.PreviewWeaponRing, "Show example skill-ups, including "
                    .. "Defense reaching its cap for your level. Also /circ weapon."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "weaponEnabled", "Show weapon skill ring", "Pop up and fill when a weapon skill goes up."),
                        afterCombat = Toggle(2, "weaponAfterCombat", "Wait until combat ends",
                            "Hold weapon skill-ups earned in a fight and show them once combat ends."),
                        delta = Toggle(3, "weaponShowDelta", "Show gain as %",
                            "Add a line under the gain showing it as a share of the skill's current cap, e.g. +0.7%."),
                    }),
                    icons = Box(4, "Icons", {
                        style = Select(1, "weaponIconStyle", "Icon style", { game = "Game icons", drawn = "Drawn" },
                            { "game", "drawn" }, "Game icons: the game's own weapon icons, as a round badge on the ring's "
                            .. "top edge. Drawn: simple line icons in the ring's centre."),
                        alpha = Range(2, "weaponIconAlpha", "Drawn icon opacity", 10, 100, 5,
                            "How strongly a drawn icon shows behind the text. Lower it if the text gets hard to read.",
                            { disabled = function() return db.weaponIconStyle ~= "drawn" end }),
                    }),
                    colors = Box(5, "Colors", {
                        fill = Color(1, "weaponColors", "fill", "Weapon skills", "Ring and rank color."),
                        capped = Color(2, "weaponColors", "capped", "Capped", "Ring color when a skill reaches the cap for your level."),
                    }),
                    size = SizeBox(6, "weapon", "weapon skill ring",
                        "Offset from the center of the screen. The default sits left of the reputation ring."),
                }))
            return tab
        end },
})
