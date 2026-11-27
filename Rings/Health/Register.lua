-- Circlet: Health rings: their settings, options pages and registration.
local _, ns = ...

local db = ns.db
local H = ns.HealthRings
local Badges = H.Badges
local playerRing = H.playerRing
local targetRing = H.targetRing
local totRing = H.totRing
local petRing = H.petRing

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
local SHOW_NAMES = { always = "Always", combat = "In combat, or when not full", combatOnly = "Only in combat" }
local SHOW_ORDER = { "always", "combat", "combatOnly" }
local TEXT_NAMES = { percent = "Percent", value = "Value", both = "Value and percent", none = "None" }
local TEXT_ORDER = { "percent", "value", "both", "none" }
local COLOR_MODES = { health = "Health color", class = "Class / reaction color" }
local COLOR_ORDER = { "health", "class" }

local function Colors()
    return {
        health = { r = 0.25, g = 0.85, b = 0.30 },
        mana   = { r = 0.25, g = 0.50, b = 1.00 },
        rage   = { r = 0.90, g = 0.20, b = 0.20 },
        energy = { r = 1.00, g = 0.85, b = 0.20 },
        focus  = { r = 1.00, g = 0.55, b = 0.25 },
    }
end

-- The effects (Rings/Health/Fx/): name, label, what it does, by the ring it's on.
local FX_ORDER = { "Combo", "Mark", "Aggro", "Execute", "LowHealth", "Death", "Flare", "Heal", "Jolt", "Avoid",
                   "EnergyTick", "Rage", "FullMana", "Skin", "Quest", "Range", "Tapped", "Loot", "Stance", "Faction" }
local FX_TEXT = {
    Combo = { "Combo points", "Five pips over the ring for your combo points, popping as they light and pulsing gold at five (rogues and druids)." },
    Mark = { "Raid marker", "The unit's raid marker (skull, cross, star...) at the top left of the ring." },
    Aggro = { "Aggro warning", "A red glare round the ring while your target is targeting you." },
    Execute = { "Execute range", "The ring throbs red-orange while your target is below 20% health." },
    LowHealth = { "Low health heartbeat", "A red heartbeat round your ring while you're below 30% health." },
    Death = { "Death", "Dead: the ring cracks and darkens, with a faded skull filling its middle (over the portrait, under the text). Your ghost: a pale glow with wisps drifting up." },
    Flare = { "Combat start", "A gold ring bursts outward from yours as combat starts." },
    Heal = { "Heal shimmer", "Green sparkles race up both sides of the ring when a heal lands." },
    Jolt = { "Jolt on crits", "The ring jolts when a critical or crushing hit lands." },
    Avoid = { "Block, dodge, parry", "A shield on a block, a whoosh round the ring on a dodge, crossed blades on a parry." },
    EnergyTick = { "Energy tick", "A spark runs round the energy band once per energy tick (every two seconds), so you can time abilities to it." },
    Rage = { "Rage embers", "Embers fly off the rage band as rage comes in." },
    FullMana = { "Full mana shine", "A soft shine on the mana band while it's full." },
    Range = { "Out of range", "The ring dims while your target is out of range of your class's main attacks (for a hunter, Auto Shot or Raptor Strike)." },
    Tapped = { "Tagged by others", "A mob someone else tagged first (no XP or loot for you) goes grey, whatever the color mode, and so does its portrait." },
    Loot = { "Lootable", "Gold glints run round the ring, with a coin at the right, while your dead target still has loot for you." },
    Stance = { "Stance or form", "Your stance, form, aura or stealth as a small badge at the bottom right of your ring." },
    Faction = { "Enemy faction", "The Alliance or Horde crest at the left of the ring when your target is a player of the other faction." },
    Quest = { "Quest target", "A yellow ! at the bottom left when your target is part of one of your active quests, with the objective's progress (3/10) under it when the game shows it." },
    Skin = { "Skinnable", "A pelt badge at the top right when your target's corpse can be skinned (or herbs, ore or parts gathered), glowing in the tooltip's difficulty color. Creatures seen skinnable before get a faint badge while alive or not yet looted." },
}

local function Register(spec)
    local key = spec.key
    local defaults = {
        [key .. "Enabled"]   = true,
        [key .. "Show"]      = spec.show,
        [key .. "Power"]     = true,
        [key .. "PowerSize"] = 55,   -- the power band's width, % of the health band's
        [key .. "Text"]      = "percent",
        [key .. "PowerText"] = true,
        [key .. "SplitText"] = false,      -- "Value and percent": the number and % on two lines
        [key .. "Smooth"]    = true,       -- transitions (see above)
        [key .. "Trail"]     = true,
        [key .. "BigHit"]    = spec.bigHit and true or false,
        [key .. "Menu"]      = true,       -- right-click menu
        -- (and <key>Fx<Name> for each effect it has: added below)
        [key .. "ClickTarget"] = (key == "playerHp") and true or nil, -- your ring: left-click targets you
        [key .. "BigHitSize"] = 15,
        [key .. "HealthTextSize"] = 100,   -- text sizes, % of the usual size for the ring
        [key .. "PowerTextSize"]  = 100,
        [key .. "NameTextSize"]   = 100,
        [key .. "LevelTextSize"]  = 100,
        [key .. "FloatTextSize"]  = 100,
        [key .. "Float"]     = spec.float and true or nil, -- damage and healing numbers floating off it
        [key .. "FloatDir"]  = spec.float and "up" or nil, -- which way they float: up, down, left, right
        -- Buffs and debuffs in an arc round the ring (Rings/Health/Auras.lua).
        [key .. "Auras"]     = spec.auras ~= nil and spec.auras or nil,
        [key .. "AuraDir"]   = spec.auras ~= nil and "down" or nil,
        [key .. "AuraShow"]  = spec.auras ~= nil and "both" or nil,
        [key .. "AuraMine"]  = spec.auras ~= nil and false or nil,
        [key .. "AuraMax"]   = spec.auras ~= nil and 8 or nil,
        [key .. "AuraSize"]  = spec.auras ~= nil and 100 or nil,
        [key .. "AuraGap"]   = spec.auras ~= nil and 2 or nil,    -- px between icons in a row
        [key .. "AuraRowGap"] = spec.auras ~= nil and 2 or nil,   -- px between the debuff and buff rows
        [key .. "AuraTime"]  = spec.auras ~= nil and true or nil,
        [key .. "AuraTextSize"] = spec.auras ~= nil and 100 or nil,
        [key .. "Level"]     = spec.level and true or false, -- level badge, bottom left
        [key .. "Elite"]     = (spec.level and key ~= "playerHp" and key ~= "petHp") and true or nil, -- wings on it for elites
        [key .. "CombatIcon"] = spec.combat and true or nil,  -- in-combat badge (your ring)
        [key .. "Portrait"]  = false,      -- the unit's portrait filling the middle
        [key .. "PortraitAlpha"] = 70,
        [key .. "Name"]      = spec.name,
        [key .. "ColorMode"] = spec.colorMode,
        [key .. "Size"]      = spec.size or 110,
        [key .. "Thickness"] = spec.thickness or 12,
        [key .. "Opacity"]   = 100,
        [key .. "X"]         = spec.x,
        [key .. "FromTop"]   = spec.fromTop or 470,
        [key .. "Hold"]      = 1,
        [key .. "Style"]     = "smooth",
        [key .. "Border"]    = 2,
        [key .. "Colors"]    = Colors(),
    }
    -- Its badges where they've always been.
    for badge, b in pairs(Badges.badges) do
        if b[key] then defaults[key .. "Pos" .. badge] = b[key] end
    end
    -- Its effects, all on.
    local fxOn = ns.VITALS_FX or {}
    for _, name in ipairs(FX_ORDER) do
        if fxOn[name] and fxOn[name][key] then defaults[key .. "Fx" .. name] = true end
    end
    ns.RegisterRing({
        key = key, name = spec.title, order = spec.order, since = spec.since or "1.5.0", class = spec.class,
        ring = spec.ring, alwaysInCombat = true,
        preview = spec.preview, slash = spec.slash, help = spec.help,
        toggle = { spec.toggleName, spec.toggleDesc },
        gameBar = spec.gameBar,
        defaults = defaults,
        page = { folder = "vitals", order = spec.pageOrder, build = function(O)
                local Toggle, Range, Select, Color, Box = O.Toggle, O.Range, O.Select, O.Color, O.Box
                local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
                local tab = RingTab(spec.pageOrder, spec.pageName, spec.header, spec.intro,
                    MergeTop(TopRow(key, spec.what, spec.preview, "Show sample health and power. Also /circ " .. spec.slash[1] .. "."), {
                        general = Box(2, "General", {
                            enabled = Toggle(1, key .. "Enabled", "Show " .. spec.what, spec.toggleDesc),
                            show = Select(2, key .. "Show", "Show", SHOW_NAMES, SHOW_ORDER, spec.showDesc),
                            clickTarget = key == "playerHp" and Toggle(8.4, key .. "ClickTarget", "Click to target yourself",
                                "Left-click your ring to target yourself, as on your player frame. Off: left clicks "
                                .. "go through to the world. In combat it stays where the ring was when the fight started.") or nil,
                            menu = Toggle(8.5, key .. "Menu", "Right-click menu",
                                "Right-click the ring for the game's own menu for " .. spec.menuWho .. ", as on its "
                                .. "frame (Set Focus, raid marks, whisper, inspect...). Left clicks still go through to "
                                .. "the world. In combat it stays where the ring was when the fight started."),
                        }),
                        bands = Box(2.1, "Bands & text", {
                            power = Toggle(1, key .. "Power", "Power band",
                                "A thinner band inside the health band for mana, rage, energy or focus."),
                            powerSize = Range(2, key .. "PowerSize", "Power band width (%)", 25, 100, 5,
                                "How wide the power band is, compared with the health band.",
                                { disabled = function() return not db[key .. "Power"] end }),
                            text = Select(3, key .. "Text", "Health text", TEXT_NAMES, TEXT_ORDER,
                                "What the middle of the ring says: the health as a percentage, the number, both, or "
                                .. "nothing."),
                            split = Toggle(4, key .. "SplitText", "Number and % on two lines",
                                "With Health text on Value and percent: the number on one line and the percentage "
                                .. "on a second, smaller line under it, instead of side by side."),
                            powerText = Toggle(5, key .. "PowerText", "Power text",
                                "Mana as a percentage (rage, energy and focus as the number) under the health."),
                            name = Toggle(6, key .. "Name", spec.nameLabel, spec.nameDesc),
                        }),
                        portrait = Box(2.2, "Portrait", {
                            portrait = Toggle(1, key .. "Portrait", spec.portraitLabel, spec.portraitDesc),
                            portraitAlpha = Range(2, key .. "PortraitAlpha", "Portrait opacity", 10, 100, 5,
                                "How strongly the portrait shows. Lower keeps the numbers on it easier to read.",
                                { disabled = function() return not db[key .. "Portrait"] end }),
                        }),
                        badges = (function()
                            -- Each badge: its switch, then where it sits (one of eight spots; a spot
                            -- another badge has swaps the two), side by side.
                            local args, n = {}, 0
                            local SWITCH = {
                                Level = { key .. "Level", "Level badge", "The level on a small disc on the ring"
                                    .. ((key == "playerHp" or key == "petHp") and "." or ", in the game's difficulty "
                                    .. "colors (\"??\" when it's too high to tell). The name then leaves its level off.") },
                                Combat = { key .. "CombatIcon", "In-combat indicator",
                                    "Crossed swords on a small disc while you're in combat. Edit mode and previews show "
                                    .. "it so you can see where it sits." },
                            }
                            for i, badge in ipairs(Badges.order) do
                                local b = Badges.badges[badge]
                                local has = b[key] and (badge == "Level" or (badge == "Combat" and spec.combat)
                                    or (fxOn[badge] and fxOn[badge][key]))
                                if has then
                                    n = n + 1
                                    local sw = SWITCH[badge]
                                    if sw then
                                        args["on" .. badge] = Toggle(i * 2 - 1, sw[1], sw[2], sw[3])
                                    else
                                        args["on" .. badge] = Toggle(i * 2 - 1, key .. "Fx" .. badge, FX_TEXT[badge][1], FX_TEXT[badge][2])
                                    end
                                    local o = Select(i * 2, key .. "Pos" .. badge, "Where",
                                        Badges.spotNames, Badges.spotOrder,
                                        "Where the " .. b[1]:lower() .. " sits on the ring. Picking a spot another "
                                        .. "badge has swaps the two.")
                                    o.get = function() return Badges.Spot(key, badge) end
                                    o.set = function(_, spot) Badges.Set(key, badge, spot) end
                                    args["pos" .. badge] = o
                                end
                            end
                            if n == 0 then return nil end
                            if key ~= "playerHp" and key ~= "petHp" and spec.level then
                                local t = Toggle(90, key .. "Elite", "Elite dragon",
                                    "The game's target-frame dragon round the level badge: gold for elites and world "
                                    .. "bosses, silver for rare elites, and the silver frame for rares.")
                                t.disabled = function() return not db[key .. "Level"] end
                                args.elite = t
                            end
                            args.reset = { type = "execute", order = 91, name = "Default positions", width = 1.2,
                                desc = "Put every badge back where it started.",
                                func = function()
                                    for badge, b in pairs(Badges.badges) do
                                        if b[key] then db[key .. "Pos" .. badge] = b[key] end
                                    end
                                end }
                            return Box(2.3, "Badges", args)
                        end)(),
                        anim = Box(2.5, "Animations", {
                            smooth = Toggle(1, key .. "Smooth", "Smooth changes",
                                "The bands ease to a new value instead of jumping, like the XP ring. When the game "
                                .. "hides the values (WoW Forever always hides your own), it does the easing itself; "
                                .. "the band is then one solid color, and the Segmented style can't ease."),
                            bigHit = Toggle(3, key .. "BigHit", "Flash on big hits",
                                "The health band flashes red for a moment on a big hit. When the game hides the "
                                .. "values (always for your own, in combat for others) it won't say how big a hit was, "
                                .. "so then critical and crushing hits count as big."),
                            bigHitSize = Range(4, key .. "BigHitSize", "Big hit (% of health)", 5, 50, 1,
                                "How much one hit has to take to count as big, when the values can be read.",
                                { disabled = function() return not db[key .. "BigHit"] end }),
                            trail = Toggle(2, key .. "Trail", "Damage trail and heal glow",
                                "Health you lose stays behind as a red trail for a moment, then drains away after the "
                                .. "band; health you gain glows softly as it fills in. Power does the same. Only when "
                                .. "the values can be read (the game must say how much changed)."),
                        }),
                        floats = spec.float and Box(2.4, "Damage & healing numbers", {
                            float = Toggle(1, key .. "Float", "Show",
                                "Each hit and heal " .. (key == "playerHp" and "you take" or "your target takes")
                                .. " floats off the ring: damage, crits bigger and gold, heals in green, and misses "
                                .. "as words (Dodge, Parry, Block...)."),
                            floatDir = (function()
                                local o = Select(2, key .. "FloatDir", "Direction",
                                    { up = "Up", down = "Down", left = "Left", right = "Right" }, { "up", "down", "left", "right" },
                                    "Which side of the ring the numbers start on and float away from.")
                                o.disabled = function() return not db[key .. "Float"] end
                                return o
                            end)(),
                        }) or nil,
                        effects = (function()
                            local args, n = {}, 0
                            for i, name in ipairs(FX_ORDER) do
                                -- (the badges have their own box)
                                if fxOn[name] and fxOn[name][key] and not Badges.badges[name] then
                                    n = n + 1
                                    args["fx" .. name] = Toggle(i, key .. "Fx" .. name, FX_TEXT[name][1], FX_TEXT[name][2])
                                end
                            end
                            return n > 0 and Box(2.7, "Effects", args) or nil
                        end)(),
                        auras = spec.auras ~= nil and (function()
                            local function Off() return not db[key .. "Auras"] end
                            local whose = key == "playerHp" and "your" or "your target's"
                            local args = {
                                on = Toggle(1, key .. "Auras", "Buffs and debuffs",
                                    "An arc of " .. whose .. " buffs and debuffs round the ring, with the time left as "
                                    .. "a sweep and stack counts: debuffs on the inner row (bordered in their type's "
                                    .. "color), buffs outside them."),
                                dir = Select(2, key .. "AuraDir", "Direction",
                                    { up = "Up", down = "Down", left = "Left", right = "Right" }, { "up", "down", "left", "right" },
                                    "Which side of the ring the arc sits on."),
                                show = Select(3, key .. "AuraShow", "Show",
                                    { both = "Buffs and debuffs", buffs = "Buffs only", debuffs = "Debuffs only" },
                                    { "both", "buffs", "debuffs" }, "Which kinds to show."),
                                mine = Toggle(4, key .. "AuraMine", "Only yours",
                                    "Only the buffs and debuffs you cast (and your pet's)."),
                                time = Toggle(5, key .. "AuraTime", "Time left as numbers",
                                    "The game's countdown numbers on the icons, as well as the sweep. These follow the "
                                    .. "game's own setting for cooldown numbers."),
                                max = Range(6, key .. "AuraMax", "Most of each kind", 1, 16, 1,
                                    "How many buffs, and how many debuffs, at most. Only as many as fit round half the "
                                    .. "ring show."),
                                size = Range(7, key .. "AuraSize", "Icon size (%)", 50, 200, 5,
                                    "The icons' size, as a % of the usual size for the ring."),
                                gap = Range(8, key .. "AuraGap", "Icon spacing", 0, 20, 1,
                                    "Space between neighbouring icons, in pixels."),
                                rowGap = Range(9, key .. "AuraRowGap", "Buff / debuff gap", 0, 40, 1,
                                    "Space between the row of debuffs and the row of buffs, in pixels."),
                            }
                            for name, a in pairs(args) do
                                if name ~= "on" then a.disabled = Off end
                            end
                            return Box(2.35, "Buffs & debuffs", args)
                        end)() or nil,
                        colors = Box(3, "Colors", {
                            mode = Select(0.5, key .. "ColorMode", "Health band color", COLOR_MODES, COLOR_ORDER,
                                "Health color: the color below. Class / reaction: players in their class color, "
                                .. "creatures red, yellow or green by how they feel about you."),
                            health = Color(1, key .. "Colors", "health", "Health", "Health band color.",
                                { disabled = function() return db[key .. "ColorMode"] == "class" end }),
                            mana = Color(2, key .. "Colors", "mana", "Mana", "Power band color for mana."),
                            rage = Color(3, key .. "Colors", "rage", "Rage", "Power band color for rage."),
                            energy = Color(4, key .. "Colors", "energy", "Energy", "Power band color for energy."),
                            focus = Color(5, key .. "Colors", "focus", "Focus", "Power band color for focus (hunter pets)."),
                        }),
                        size = SizeBox(4, key, spec.what, "Offset from the center of the screen."),
                    }))
                local g = tab.args.bands.args
                g.powerText.disabled = function() return not db[key .. "Power"] end
                g.split.disabled = function() return db[key .. "Text"] ~= "both" end

                return tab
            end },
    })
end

Register({
    key = "playerHp", ring = playerRing, title = "Health", order = 12.9, pageOrder = 1,
    show = "combat", name = false, colorMode = "health", x = -230, bigHit = true, level = true, combat = true, float = true, auras = false, menuWho = "yourself",
    preview = ns.PreviewPlayerHpRing, slash = { "health", "hp" }, help = "preview your health and power ring",
    toggleName = "Health ring", toggleDesc = "Your health, with your mana, rage or energy inside it.",
    gameBar = "the game's player frame",
    pageName = "Health & power", header = "Health & Power Ring", what = "health ring",
    intro = "Your health round the ring, and your mana, rage or energy in a thinner band inside it, with both "
        .. "in the middle. In combat the game can hide these from addons; the ring still fills and shows the "
        .. "numbers then, but can't compare them, so it counts hidden values as not full.",
    showDesc = "Always; in combat, or when your health or power isn't full (rage: when you have some); or only in "
        .. "combat.",
    nameLabel = "Show your name", nameDesc = "Your name above the health.",
    portraitLabel = "Use player portrait as center frame",
    portraitDesc = "Your character's portrait fills the middle of the ring, behind the numbers.",
})

Register({
    key = "targetHp", ring = targetRing, title = "Target health", order = 12.95, pageOrder = 2,
    show = "always", name = true, colorMode = "class", x = 230, bigHit = true, level = true, float = true, auras = true, menuWho = "your target",
    preview = ns.PreviewTargetHpRing, slash = { "targethealth", "thp" }, help = "preview the target health ring",
    toggleName = "Target health ring", toggleDesc = "Your target's health and power, with its name.",
    gameBar = "the game's target frame",
    pageName = "Target health", header = "Target Health Ring", what = "target health ring",
    intro = "Your target's health round the ring and its mana, rage or energy in a thinner band inside it, with "
        .. "its name and level. Players show in their class color and creatures by how they feel about you (with "
        .. "Class / reaction color). In combat the game can hide these from addons; the ring still fills and shows "
        .. "the numbers then.",
    showDesc = "Whenever you have a target; when you're in combat or it isn't at full health; or only in combat.",
    nameLabel = "Show name and level", nameDesc = "The target's name, and its level, above the health.",
    portraitLabel = "Use target portrait as center frame",
    portraitDesc = "Your target's portrait fills the middle of the ring, behind the numbers, and changes with your "
        .. "target. In edit mode and previews your own portrait stands in.",
})

Register({
    key = "totHp", ring = totRing, title = "Target of target", order = 12.97, pageOrder = 3,
    show = "always", name = true, colorMode = "class", x = 330, fromTop = 490, size = 70, thickness = 8, menuWho = "it",
    preview = ns.PreviewTotHpRing, slash = { "tot", "targettarget" }, help = "preview the target of target ring",
    toggleName = "Target of target ring", toggleDesc = "A small ring for your target's target: who it's after.",
    gameBar = "the game's target of target frame",
    pageName = "Target of target", header = "Target of Target Ring", what = "target of target ring",
    intro = "A smaller ring beside the target ring for your target's target: who your target is after, so you "
        .. "can see at a glance when it turns on you or a healer. Its health round the ring and its power inside, "
        .. "with its name. The game sends no updates for this unit, so the ring checks it several times a second.",
    showDesc = "Whenever your target has a target; when you're in combat or it isn't at full health; or only in "
        .. "combat.",
    nameLabel = "Show name and level", nameDesc = "The name, and level, above the health.",
    portraitLabel = "Use its portrait as center frame",
    portraitDesc = "Its portrait fills the middle of the ring, behind the numbers. In edit mode and previews your "
        .. "own portrait stands in.",
})

Register({
    key = "petHp", ring = petRing, title = "Pet health", order = 12.98, pageOrder = 4,
    since = "1.5.0", -- every class: charmed and mind-controlled mobs, and other temporary pets, count too
    show = "always", name = true, colorMode = "health", x = -360, fromTop = 490, size = 70, thickness = 8,
    level = true, float = true, menuWho = "your pet",
    preview = ns.PreviewPetHpRing, slash = { "pethp", "pethealth" }, help = "preview the pet health ring",
    toggleName = "Pet health ring", toggleDesc = "A small ring for your pet's health and power.",
    gameBar = "the game's pet frame",
    pageName = "Pet health", header = "Pet Health Ring", what = "pet health ring",
    intro = "A smaller ring beside yours for your pet: its health round the ring and its focus, energy or mana "
        .. "in a thinner band inside it, with its name. Hidden when you have no pet out. For every class: "
        .. "a mob you've charmed or mind-controlled counts as your pet too.",
    showDesc = "Whenever your pet is out; when you're in combat or it isn't at full health; or only in combat.",
    nameLabel = "Show name and level", nameDesc = "Your pet's name, and its level, above the health.",
    portraitLabel = "Use pet portrait as center frame",
    portraitDesc = "Your pet's portrait fills the middle of the ring, behind the numbers, and changes when you "
        .. "summon another. In edit mode and previews your own portrait stands in.",
})
