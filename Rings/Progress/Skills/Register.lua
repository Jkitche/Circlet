-- Circlet: Skill rings: their settings, options pages and registration.
local _, ns = ...

local db = ns.db
local SK = ns.SkillRings
local skillRing = SK.skillRing
local weaponRing = SK.weaponRing
local PreviewSkillRing = SK.PreviewSkillRing
local PreviewWeaponRing = SK.PreviewWeaponRing

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "skill", name = "Profession", order = 4,
    -- The icon can be the ring's background (Core/Settings.lua, UI/Options/Kit.lua).
    iconBg = { disabled = function() return db.skillIconStyle ~= "game" end,
               note = "With game icons only (drawn icons already sit behind the text)." },
    ring = skillRing,
    preview = PreviewSkillRing, slash = { "skill", "skills", "professions" }, help = "preview the profession ring",
    toggle = { "Profession ring", "Fills when a profession or secondary skill goes up." },
    defaults = {
        skillEnabled     = true,
        skillFx          = true, -- the spark, glitter and burst (and the gold shimmer for a tier or the cap)
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
            local tab = RingTab(4, "Profession skills", "Profession Ring",
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
                        fx = Toggle(4, "skillFx", "Animations",
                            "A spark rides the end of the fill shedding glitter in the profession's colors, then bursts "
                            .. "with motes floating up; a new tier or the cap sends a gold shimmer round the ring."),
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
    -- The icon can be the ring's background (Core/Settings.lua, UI/Options/Kit.lua).
    iconBg = { disabled = function() return db.weaponIconStyle ~= "game" end,
               note = "With game icons only (drawn icons already sit behind the text)." },
    ring = weaponRing,
    preview = PreviewWeaponRing, slash = { "weapon", "weapons" }, help = "preview the weapon skill ring",
    toggle = { "Weapon skill ring", "Fills when a weapon skill or Defense goes up." },
    defaults = {
        -- Weapon skill ring: weapon skills and Defense (the skill ring above is professions
        -- and secondary skills). Left of the reputation ring.
        weaponEnabled     = true,
        weaponFx          = true, -- the swoosh, the clang and sparks (and the glint when capped)
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
                        fx = Toggle(4, "weaponFx", "Animations",
                            "A steel swoosh slices across the end of the fill as it rises, then a clang and a spray of "
                            .. "sparks; capped, a blade glint sweeps round the ring."),
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
