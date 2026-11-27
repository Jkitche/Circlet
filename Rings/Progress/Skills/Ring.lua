-- Circlet: Skill rings: the two rings, checking your skills for gains, and previews.
local _, ns = ...

local CreateProgressRing, WEAPON_GLYPHS, db = ns.CreateProgressRing, ns.WEAPON_GLYPHS, ns.db
local SK = ns.SkillRings
local SKILL_STYLE = SK.SKILL_STYLE
local ReadSkills = SK.ReadSkills
local SKILL_ICONS = SK.SKILL_ICONS
local IconPath = SK.IconPath
local SkillIconPath = SK.SkillIconPath
local SKILL_GLYPH = SK.SKILL_GLYPH
local SKILL_TIERS = SK.SKILL_TIERS
local Colors = SK.Colors
local KindColor = SK.KindColor
local DrawSkillFx = SK.DrawSkillFx
local DrawWeaponFx = SK.DrawWeaponFx

local function MakeSkillRing(key, samples)
    return CreateProgressRing({
        key = key,
        samples = samples,
        decorate = key == "weapon" and DrawWeaponFx or DrawSkillFx,
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
                return {
                    fill = c,
                    rank = c,
                    labelColor = cap,
                    label = tier and ("Now " .. tier .. "!") or ("New cap: " .. e.max),
                }
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

local skillRing = MakeSkillRing(
    "skill",
    function()
        return {
            { id = "edit-s2", skillID = 186, name = "Mining", kind = "profession", from = 112, to = 115, max = 150 },
            { id = "edit-s3", skillID = 356, name = "Fishing", kind = "secondary", from = 40, to = 41, max = 150 },
            {
                id = "edit-s4",
                skillID = 185,
                name = "Cooking",
                kind = "secondary",
                from = 74,
                to = 75,
                max = 75,
                editTime = 4,
            },
            {
                id = "edit-s5",
                skillID = 197,
                name = "Tailoring",
                kind = "profession",
                from = 75,
                to = 75,
                max = 150,
                change = "tier",
                segment = "tier150",
                gainText = "+75 cap",
                editTime = 4,
            },
        }
    end
)

local weaponRing = MakeSkillRing(
    "weapon",
    function()
        return {
            {
                id = "edit-w1",
                skillID = 43,
                name = "Swords",
                kind = "weapon",
                from = 141,
                to = 143,
                max = 150,
                glyph = "sword",
            },
            {
                id = "edit-w2",
                skillID = 45,
                name = "Bows",
                kind = "weapon",
                from = 88,
                to = 89,
                max = 150,
                glyph = "bow",
            },
            {
                id = "edit-w3",
                skillID = 95,
                name = "Defense",
                kind = "weapon",
                from = 148,
                to = 150,
                max = 150,
                editTime = 4,
            },
        }
    end
)

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
                ring.Queue({
                    id = id,
                    skillID = id,
                    name = s.name,
                    kind = s.kind,
                    from = was.rank,
                    to = s.rank,
                    max = s.max,
                    glyph = WEAPON_GLYPHS[id],
                })
            elseif s.max > was.max and s.kind ~= "weapon" then
                -- Trained to a new tier. (Weapon caps rise by themselves with every
                -- character level, so those are left out.)
                ring.Queue({
                    id = id,
                    skillID = id,
                    name = s.name,
                    kind = s.kind,
                    from = s.rank,
                    to = s.rank,
                    max = s.max,
                    change = "tier",
                    segment = "tier" .. s.max,
                    gainText = "+" .. (s.max - was.max) .. " cap",
                })
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
        {
            id = -4,
            skillID = 197,
            name = "Tailoring",
            kind = "profession",
            from = 75,
            to = 75,
            max = 150,
            change = "tier",
            segment = "tier150",
            gainText = "+75 cap",
        },
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

-- For the files loaded after this one.
SK.skillRing = skillRing
SK.weaponRing = weaponRing
SK.PreviewSkillRing = PreviewSkillRing
SK.PreviewWeaponRing = PreviewWeaponRing
