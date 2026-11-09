-- Circlet: Options window (AceConfig / AceGUI, like Questie's).
local ADDON_NAME, ns = ...

local ADDON_NAME, DEFAULTS, EDIT_ORDER, OnXPAlwaysChanged, PreviewAmmoRing = ns.ADDON_NAME, ns.DEFAULTS, ns.EDIT_ORDER, ns.OnXPAlwaysChanged, ns.PreviewAmmoRing
local PreviewLevelUp, PreviewPetRing, PreviewQuestRing, PreviewRepRing, PreviewSkillRing = ns.PreviewLevelUp, ns.PreviewPetRing, ns.PreviewQuestRing, ns.PreviewRepRing, ns.PreviewSkillRing
local PreviewXPRing, Print, RING_EDITORS, RING_STYLE_NAMES, RING_STYLE_ORDER = ns.PreviewXPRing, ns.Print, ns.RING_EDITORS, ns.RING_STYLE_NAMES, ns.RING_STYLE_ORDER
local ResetPosition, ResetPositions, ToggleAllEditing, ToggleIconGrid, ToggleRingEditing = ns.ResetPosition, ns.ResetPositions, ns.ToggleAllEditing, ns.ToggleIconGrid, ns.ToggleRingEditing
local db, ns = ns.db, ns.ns

---------------------------------------------------------------------------
-- Options window  (/sq, or Esc > Options > AddOns > Circlet)
---------------------------------------------------------------------------
-- A standalone tabbed window built with AceConfig/AceGUI (embedded in Libs), the
-- same toolkit Questie's options use. One tab per ring; each tab groups its
-- settings into boxes. Rings read db every frame, so most settings need no callback.

local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
local AceConfigRegistry = LibStub and LibStub("AceConfigRegistry-3.0", true)
local AceConfigDialog = LibStub and LibStub("AceConfigDialog-3.0", true)
local APP = "Circlet"
local configFrame

-- Saved data the addon learns as you play, not settings: resets leave it alone.
local LEARNED = ns.LEARNED

local function ResetDefaults()
    for key, value in pairs(DEFAULTS) do
        if not LEARNED[key] then
            db[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
    OnXPAlwaysChanged()
    ns.RefreshOptions()
    Print("Settings reset to defaults.")
end

---------------------------------------------------------------- option builders
local function Toggle(order, key, name, desc, onSet)
    return {
        type = "toggle", order = order, name = name, desc = desc, descStyle = "inline", width = "full",
        get = function() return db[key] end,
        set = function(_, value)
            db[key] = value
            if onSet then onSet(value) end
        end,
    }
end

local function Range(order, key, name, min, max, step, desc, extra)
    local option = {
        type = "range", order = order, name = name, desc = desc, width = 1.55,
        min = min, max = max, step = step, bigStep = step,
        get = function() return db[key] end,
        set = function(_, value) db[key] = value end,
    }
    for k, v in pairs(extra or {}) do option[k] = v end
    return option
end

local function Select(order, key, name, values, sorting, desc)
    return {
        type = "select", order = order, name = name, desc = desc, style = "dropdown", width = 1.2,
        values = values, sorting = sorting,
        get = function() return db[key] end,
        set = function(_, value) db[key] = value end,
    }
end

-- group/name: db[group][name] is the {r,g,b} table (looked up each time, since
-- Reset replaces the tables).
local function Color(order, group, name, label, desc, extra)
    local option = {
        type = "color", order = order, name = label, desc = desc, hasAlpha = false, width = 1.1,
        get = function()
            local c = db[group][name]
            return c.r, c.g, c.b
        end,
        set = function(_, r, g, b)
            local c = db[group][name]
            c.r, c.g, c.b = r, g, b
        end,
    }
    for k, v in pairs(extra or {}) do option[k] = v end
    return option
end

local function Execute(order, name, func, desc, width)
    return { type = "execute", order = order, name = name, desc = desc, func = func, width = width or 1.1 }
end

local function Box(order, name, args)
    return { type = "group", inline = true, order = order, name = name, args = args }
end

local function Spacer(order)
    return { type = "description", order = order, name = " ", fontSize = "small", width = "full" }
end

local function Intro(order, text)
    return { type = "description", order = order, name = text, fontSize = "medium", width = "full" }
end

-- Puts one ring's settings (colors, look, options and position) back to defaults.
-- Quest and totem rings: the whole group.
local function ResetRing(key)
    for k, value in pairs(DEFAULTS) do
        if not LEARNED[k] and k:sub(1, #key) == key and k:sub(#key + 1, #key + 1):match("%u") then
            db[k] = type(value) == "table" and CopyTable(value) or value
        end
    end
    -- Per-ring overrides inside a group (pin1X, totem2Size, ...).
    for k in pairs(CircletDB) do
        if type(k) == "string" and k:match("^" .. key .. "%d+%u") then CircletDB[k] = nil end
    end
    ResetPosition(key, true)
    if key == "xp" then OnXPAlwaysChanged() end
    if key == "pin" and ns.RefreshPinClicks then ns.RefreshPinClicks() end
    ns.RefreshOptions()
    Print((ns.RING_NAMES[key] or key) .. " ring reset to defaults.")
end

-- The settings that make up a ring's look, copied by "Apply this look to all rings".
local LOOK_FIELDS = { "Style", "Fill", "Shape", "Rotation", "Thickness", "Border", "Opacity", "Gradient" }

local function ApplyLookToAll(key)
    for _, other in ipairs(EDIT_ORDER) do
        if other ~= key then
            for _, field in ipairs(LOOK_FIELDS) do db[other .. field] = db[key .. field] end
        end
    end
    ns.RefreshOptions()
    Print("Applied the " .. (ns.RING_NAMES[key] or key) .. " ring's look to every ring.")
end

-- Pages that only matter to some classes are hidden for the others (their settings
-- are kept). Unknown classes see everything.
local function PlayerClass()
    local _, class = UnitClass("player")
    return class
end
local CLASS_RINGS = {
    pet = { HUNTER = true },                                            -- only hunter pets gain XP
    ammo = { HUNTER = true, ROGUE = true, WARRIOR = true, WARLOCK = true }, -- ammo, thrown, soul shards
    totem = { SHAMAN = true },
}
local function HiddenForClass(key)
    local classes, class = CLASS_RINGS[key], PlayerClass()
    return classes ~= nil and class ~= nil and not classes[class]
end

-- Hides an option (or page) for classes it doesn't apply to.
local function Hide(key, option)
    option.hidden = function() return HiddenForClass(key) end
    return option
end

-- The top row of every ring tab: Edit mode (live preview + drag) and the preview.
local function TopRow(key, what, preview, previewDesc)
    return {
        edit = {
            type = "execute", order = 1, width = 1.1,
            name = function() return RING_EDITORS[key].get() and "|cff33ff33Finish editing|r" or "Edit mode" end,
            desc = "Keep the " .. what .. " on screen cycling through sample changes, so color, size and other "
                .. "settings show live as you change them here, and drag the ring to move it "
                .. "(right-click it to reset its position). Also /sq edit " .. key .. ".",
            func = function() ToggleRingEditing(key) end,
        },
        preview = Execute(2, "Preview", preview, previewDesc),
        resetRing = {
            type = "execute", order = 3, width = 1.1, name = "Reset this ring",
            desc = "Put this ring's colors, look, options and position back to their defaults.",
            confirm = true, confirmText = "Reset every setting of the " .. what .. " to its default?",
            func = function() ResetRing(key) end,
        },
    }
end

-- The Appearance box every ring has; its Position box rides along in _position and
-- RingTab puts it on the page right after.
local function SizeBox(order, key, what, xTip)
    local look = Box(order, "Appearance", {
        style     = Select(0.5, key .. "Style", "Ring style", RING_STYLE_NAMES, RING_STYLE_ORDER,
            "Smooth: a solid band. Segmented: 24 notches with small gaps. Thin: a slim band around the edge."),
        fill      = Select(0.52, key .. "Fill", "Fill", { solid = "Solid", gradient = "Gradient" }, { "solid", "gradient" },
            "Solid: one flat color. Gradient: the color shades from darker at the ring's start to full at its end."),
        shape     = Select(0.55, key .. "Shape", "Shape", ns.RING_SHAPE_NAMES, ns.RING_SHAPE_ORDER,
            "Ring: a full circle. Arc: three quarters of a circle. Half arc: half a circle. "
            .. "The ring fills clockwise from one end to the other."),
        rotation  = Range(0.58, key .. "Rotation", "Rotation (degrees)", 0, 359, 1,
            "Turn the " .. what .. " clockwise by this many degrees. At 0 a ring's fill starts at 12 o'clock "
            .. "and an arc opens at the bottom; at the default, 180, the fill starts at 6 o'clock and an arc "
            .. "opens at the top. Drag snaps to 15 degrees; type in the box under the slider for any value.",
            { bigStep = 15, get = function() return (tonumber(db[key .. "Rotation"]) or 0) % 360 end }),
        styleGap  = { type = "description", order = 0.6, name = "", width = "full" },
        size      = Range(1, key .. "Size", "Ring size", 60, 300, 10, "Diameter of the " .. what .. "."),
        thickness = Range(2, key .. "Thickness", "Ring thickness", 4, 40, 2, "Width of the " .. what .. "."),
        border    = Range(2.5, key .. "Border", "Black border", 0, 6, 1,
            "A black outline around the " .. what .. " and its icon, so they stand out against bright "
            .. "backgrounds. With the segmented style each notch gets its own outline. 0 turns it off."),
        opacity   = Range(3, key .. "Opacity", "Opacity", 10, 100, 5,
            "How see-through the " .. what .. " is, including its text and icon."),
        gradient  = Range(3.5, key .. "Gradient", "Gradient strength", 0, 100, 5,
            "How much darker the start of the " .. what .. " is than its end, with the gradient fill.",
            { hidden = function() return db[key .. "Fill"] ~= "gradient" end }),
        hold      = Range(4, key .. "Hold", "Stay on screen (seconds)", 1, 10, 1,
            "How long the ring stays after a change."),
        applyAll  = {
            type = "execute", order = 9, width = 1.6, name = "Apply this look to all rings",
            desc = "Copy this ring's style, shape, rotation, thickness, border, opacity and fill to every other ring. "
                .. "Sizes, colors and positions stay as they are.",
            confirm = true, confirmText = "Give every ring the " .. what .. "'s style, shape, rotation, "
                .. "thickness, border, opacity and fill?",
            func = function() ApplyLookToAll(key) end,
        },
    })
    look._key = key
    look._position = Box(order + 0.5, "Position", {
        x         = Range(5, key .. "X", "Horizontal position", -1600, 1600, 10, xTip),
        fromTop   = Range(6, key .. "FromTop", "Distance from top", 0, 1400, 10,
            "Gap between the top of the screen and the top of the ring."),
        reset     = Execute(7, "Reset position", function() ResetPosition(key) end,
            "Move only the " .. what .. " back to its default spot. Also /sq resetpos " .. key .. "."),
    })
    return look
end

local function RingTab(order, name, header, intro, args)
    args.header = { type = "header", order = 0, name = header }
    args.intro = Intro(0.5, intro)
    args.spacer = Spacer(1.5)
    if args.size and args.size._position then
        args.position, args.size._position = args.size._position, nil
    end
    -- Every ring: whether it stays up during combat.
    local key = args.size and args.size._key
    if key then
        args.size._key = nil
        local box = args.general or args.size
        local gameBar = ns.DEFAULT_UI and ns.DEFAULT_UI[key]
        if gameBar then
            box.args.hideDefault = {
                type = "toggle", order = 49, width = "full", name = "Hide " .. gameBar,
                desc = "Hide " .. gameBar .. ", since this ring shows the same thing. Turn it off to bring it back.",
                get = function() return db[key .. "HideDefault"] end,
                set = function(_, v) db[key .. "HideDefault"] = v end,
            }
        end
        box.args.combat = {
            type = "toggle", order = 50, width = "full", name = "Show in combat",
            desc = "Keep this ring on screen while you're in combat. Off: it fades out when combat starts "
                .. "and comes back when it ends.",
            get = function() return db[key .. "Combat"] ~= false end,
            set = function(_, v) db[key .. "Combat"] = v; ns.ApplyAllOpacity() end,
        }
    end
    return { type = "group", order = order, name = name, args = args }
end

local function MergeTop(top, rest)
    for k, v in pairs(top) do rest[k] = v end
    return rest
end

---------------------------------------------------------------- the table
local function BuildOptionsTable()
    local general = {
        type = "group", order = 1, name = "General",
        args = {
            header = { type = "header", order = 0, name = "Circlet" },
            intro = Intro(0.5, "Progress rings for quests, XP, skills, reputation and more. Each ring has its own "
                .. "page in the list on the left, with its colors, look and position. While a ring's page is open "
                .. "the ring is in |cffffd100edit mode|r: it's on screen showing your changes, and you can drag it "
                .. "into place."),
            spacer = Spacer(1),
            rings = Box(2, "Rings", {
                xp    = Toggle(1, "xpEnabled", "XP ring", "Fills when you gain experience.", OnXPAlwaysChanged),
                quest = Toggle(2, "questEnabled", "Quest ring", "Fills when a kill or drop advances a quest objective."),
                skill = Toggle(3, "skillEnabled", "Profession ring", "Fills when a profession or secondary skill goes up."),
                weapon = Toggle(3.1, "weaponEnabled", "Weapon skill ring", "Fills when a weapon skill or Defense goes up."),
                rep   = Toggle(4, "repEnabled", "Reputation ring", "Fills (or drains) when your reputation changes."),
                pet   = Hide("pet", Toggle(5, "petEnabled", "Pet ring", "Fills when your pet gains experience.")),
                ammo  = Hide("ammo", Toggle(6, "ammoEnabled", "Ammo ring", "Pops up when you're running low on ammo or soul shards.")),
                flight = Toggle(7, "flightEnabled", "Flight ring", "Counts down to landing while you're on a flight path."),
                timed = Toggle(8, "timedEnabled", "Timed quest ring", "Counts down escort and other timed quests."),
                breath = Toggle(9.5, "breathEnabled", "Breath ring", "Breath underwater, deep-water fatigue and Feign Death."),
                corpse = Toggle(9, "corpseEnabled", "Corpse ring", "Distance and direction to your corpse while you're a ghost."),
                craft = Toggle(10, "craftEnabled", "Crafting ring", "Progress through a batch of crafts."),
                pin = Toggle(11, "pinEnabled", "Quest rings", "Quests you've pinned from the quest log's right-click menu."),
                cast = Toggle(10.6, "castEnabled", "Cast ring", "Your casts and channels, timed even in combat."),
                gather = Toggle(10.5, "gatherEnabled", "Gathering ring", "Mining, herbalism, skinning and fishing, then what you got."),
                totem = Hide("totem", Toggle(12, "totemEnabled", "Totem rings", "Shamans: a small ring for each totem you have down.")),
            }),
            layout = Box(3, "Layout", {
                editAll = {
                    type = "execute", order = 1, width = 1.1,
                    name = function()
                        for _, key in ipairs(EDIT_ORDER) do
                            if RING_EDITORS[key].get() then return "|cff33ff33Finish editing|r" end
                        end
                        return "Edit all rings"
                    end,
                    desc = "Put every ring on screen at once to arrange them. Also /sq edit.",
                    func = function() ToggleAllEditing() end,
                },
                autoEdit = Toggle(0.4, "optionsAutoEdit", "Edit mode on ring pages",
                    "Opening a ring's page here puts that ring in edit mode, so it's on screen showing your "
                    .. "changes as you make them. It goes back to normal when you leave the page or close the window."),
                arrange = Toggle(0.5, "autoArrange", "Auto-arrange",
                    "When rings pop up at the same time and would overlap, the newer one slides sideways "
                    .. "to clear the other, then slides back home once it's gone."),
                snap = Toggle(1, "snapGrid", "Snap to grid",
                    "In edit mode, show a grid and snap rings to it while you drag them, so they line up. "
                    .. "Hold Shift while dragging to place a ring freely.",
                    function() ns.RefreshEditGrid() end),
                gridSize = Range(1.5, "gridSize", "Grid size", 4, 64, 2,
                    "Spacing of the snap grid. It's measured out from the centre of the screen.",
                    { disabled = function() return not db.snapGrid end }),
                resetAll = Execute(2, "Reset all positions", ResetPositions,
                    "Move every ring back to its default spot across the top of the screen. Also /sq resetpos."),
            }),
            effects = Box(3.4, "Effects", {
                discover = Toggle(1, "discoverFx", "Discovered area animation",
                    "When you discover a new area, a gold compass ring sweeps closed under the zone text with "
                    .. "the area's name and the exploration XP."),
                preview = Execute(2, "Preview", function() ns.PreviewDiscovery() end,
                    "Play the discovered area animation. Also /sq discover."),
                login = Toggle(3, "loginFx", "Welcome animation",
                    "When you log in (not on /reload), rings in the addon's colors spin open, your name types "
                    .. "itself out, and your level, zone, rested XP and when you last played fade in."),
                loginPreview = Execute(4, "Preview welcome", function() ns.PreviewWelcome() end,
                    "Play the welcome animation. Also /sq hello."),
            }),
            summary = Box(3.5, "Session summary", {
                show = Execute(1, "Show summary", function() ns.ToggleSummary() end,
                    "Everything you've gained this session: XP, quests, money, skill-ups, reputation, flights. "
                    .. "Also /sq summary."),
                onLogout = Toggle(2, "summaryOnLogout", "Show when logging out",
                    "Pop up the summary when the logout countdown starts."),
            }),
            reset = Box(4, "Reset", {
                defaults = {
                    type = "execute", order = 1, width = 1.1, name = "Reset to defaults",
                    desc = "Restore every Circlet setting, color and position to its default.",
                    confirm = true, confirmText = "Reset every Circlet setting to its default?",
                    func = ResetDefaults,
                },
            }),
        },
    }

    local xp = RingTab(2, "XP", "XP Ring",
        "A donut that pops up and fills when you gain experience, colored by rest state.",
        MergeTop(TopRow("xp", "XP ring", PreviewXPRing, "Show example XP gains: rested, rested running out, "
            .. "and a level-up. Also /sq xp."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "xpEnabled", "Show XP ring", "Pop up and fill when you gain experience.",
                    OnXPAlwaysChanged),
                always = Toggle(2, "xpAlways", "Always show",
                    "Keep the XP ring on screen permanently. Gains still animate and count up.", OnXPAlwaysChanged),
                minimap = Toggle(2.05, "xpMinimap", "Show as minimap border",
                    "Wrap the XP ring around your minimap, as an XP bar that's always there. Its text sits below "
                    .. "the map (and hides when idle, below). Size and position settings don't apply then; "
                    .. "thickness, style and colors do.", OnXPAlwaysChanged),
                minimapGap = {
                    type = "range", order = 2.07, name = "Distance from the map", min = -10, max = 30, step = 1,
                    desc = "Gap between the edge of the minimap and the ring. Negative values overlap the map's edge.",
                    get = function() return db.xpMinimapGap or 2 end,
                    set = function(_, v) db.xpMinimapGap = v end,
                    disabled = function() return not db.xpMinimap end,
                },
                minimapBehind = {
                    type = "toggle", order = 2.08, name = "Behind the minimap",
                    desc = "Draw the ring behind the minimap, so the map, its border and its buttons sit on top of "
                        .. "it. Off: the ring draws over them.",
                    get = function() return db.xpMinimapBehind end,
                    set = function(_, v) db.xpMinimapBehind = v end,
                    disabled = function() return not db.xpMinimap end,
                },
                hideText = {
                    type = "toggle", order = 2.1, name = "Hide text when idle",
                    desc = "With Always show on: out in the world, the ring's text fades out once nothing has changed "
                        .. "for a few seconds, so the ring works as a plain XP bar. The text comes back when you gain "
                        .. "XP or put the mouse over the ring, and stays while you're resting (it shows your rested XP).",
                    get = function() return db.xpHideText end,
                    set = function(_, v) db.xpHideText = v end,
                    disabled = function() return not (db.xpAlways or db.xpMinimap) end,
                },
                hideDelay = {
                    type = "range", order = 2.2, name = "Hide text after (seconds)", min = 1, max = 30, step = 1,
                    desc = "How long the always-on ring shows its text after a change before fading it out.",
                    get = function() return db.xpHideTextDelay or 3 end,
                    set = function(_, v) db.xpHideTextDelay = v end,
                    disabled = function() return not ((db.xpAlways or db.xpMinimap) and db.xpHideText) end,
                },
                resting = Toggle(2.5, "xpRestedRing", "Show while resting",
                    "At an inn or in a city, keep the ring up showing your rested XP building (the blue band) "
                    .. "and roughly how long until you're fully rested.", function() ns.OnRestingChanged() end),
                restIcon = Toggle(2.55, "xpRestIcon", "Resting zZZ",
                    "While you're resting, the animated zZZ from your player portrait sits on the ring's "
                    .. "top-right edge."),
                restedGain = Toggle(2.6, "xpRestedGain", "Show rested XP gained",
                    "When you leave an inn or city, the ring pops up with the rested band growing by the rested "
                    .. "XP you gained there (including while logged out), e.g. +1,240 rested."),
                afterCombat = Toggle(3, "xpAfterCombat", "Wait until combat ends",
                    "Add up all XP earned during a fight and show the total once combat ends."),
                delta = Toggle(4, "xpShowDelta", "Show gain as %",
                    "Add a line under the gain showing it as a share of the level, e.g. +4.2%."),
            }),
            levelUp = Box(3, "Level-up effect", {
                style = Select(1, "xpLevelFxStyle", "Effect",
                    { gold = "Gold", rainbow = "Rainbow", none = "Off" }, { "gold", "rainbow", "none" },
                    "Gold: a gold flash, shockwaves and sparks. Rainbow: a rainbow swirl around the ring, "
                    .. "then a rainbow flash, shockwaves and sparks. Off: no effect."),
                preview = Execute(2, "Preview level-up", PreviewLevelUp,
                    "Show a level-up with the selected effect. Also /sq levelup."),
                restedPreview = Execute(3, "Preview rested gain", function() ns.PreviewRestedGain() end,
                    "Show what leaving an inn looks like after gaining rested XP. Also /sq rested."),
            }),
            size = SizeBox(4, "xp", "XP ring", "Offset from the center of the screen."),
        }))

    local quest = RingTab(3, "Quest", "Quest Ring",
        "A donut that fills when a kill or drop advances a quest objective, e.g. Screecher Feather 5 / 8.",
        MergeTop(TopRow("quest", "quest ring", PreviewQuestRing, "Show example progress: a drop, a percentage "
            .. "objective, and an objective finishing. Also /sq quest."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "questEnabled", "Show quest ring", "Pop up and fill when an objective advances."),
                afterCombat = Toggle(2, "questAfterCombat", "Wait until combat ends",
                    "Hold objective progress made in a fight and show it once combat ends."),
                delta = Toggle(3, "questShowDelta", "Show gain as %",
                    "Add a line under the gain showing it as a share of the objective, e.g. +4.2%."),
                completeFx = Toggle(4, "questCompleteFx", "Complete animation",
                    "A quest-giver \"!\" pops up in the middle of the ring, behind the text, when an objective is finished."),
                turnIn = Toggle(5, "questTurnIn", "Turn-in alert",
                    "Once every objective of a quest is done, the ring shows the quest as \"Ready to turn in\" "
                    .. "(with a \"?\" if the complete animation is on)."),
            }),
            colors = Box(3, "Colors", {
                progress = Color(1, "questColors", "progress", "In progress", "Ring and count color while an objective is in progress."),
                complete = Color(2, "questColors", "complete", "Complete", "Ring color when an objective is finished."),
            }),
            size = SizeBox(4, "quest", "quest ring",
                "Offset from the center of the screen. The default sits just left of the XP ring."),
        }))

    local skill = RingTab(4, "Professions", "Profession Ring",
        "Pops up and fills when a profession (Mining, Tailoring...) or secondary skill (Cooking, First Aid, "
        .. "Fishing, Riding) goes up, or you train to a new tier. Weapon skills have their own ring.",
        MergeTop(TopRow("skill", "profession ring", PreviewSkillRing, "Show example skill-ups: a profession, a "
            .. "secondary skill hitting its cap, and a profession trained to a new tier. Also /sq skill."), {
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
                list = Execute(3, "Show icon list", ToggleIconGrid,
                    "Show every game icon the rings use, marked found or missing in this client. Also /sq icons."),
            }),
            colors = Box(5, "Colors", {
                profession = Color(2, "skillColors", "profession", "Professions", "Ring and rank color for professions."),
                secondary = Color(3, "skillColors", "secondary", "Secondary skills", "Ring and rank color for secondary skills."),
                capped = Color(4, "skillColors", "capped", "Capped", "Ring color when a skill reaches its cap."),
            }),
            size = SizeBox(6, "skill", "profession ring",
                "Offset from the center of the screen. The default sits just right of the XP ring."),
        }))

    local weapon = RingTab(4.5, "Weapon skills", "Weapon Skill Ring",
        "Pops up and fills when a weapon skill (Swords, Bows...) or Defense goes up. They mostly rise in "
        .. "fights, so by default they wait until combat ends.",
        MergeTop(TopRow("weapon", "weapon skill ring", ns.PreviewWeaponRing, "Show example skill-ups, including "
            .. "Defense reaching its cap for your level. Also /sq weapon."), {
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

    local rep = RingTab(5, "Reputation", "Reputation Ring",
        "A donut that fills (or drains) when your reputation with a faction changes, colored by standing.",
        MergeTop(TopRow("rep", "reputation ring", PreviewRepRing, "Show examples: a gain, reaching a new "
            .. "standing, and a loss. Also /sq rep."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "repEnabled", "Show reputation ring", "Pop up and fill when your reputation changes."),
                afterCombat = Toggle(2, "repAfterCombat", "Wait until combat ends",
                    "Hold reputation earned in a fight and show it once combat ends."),
                delta = Toggle(3, "repShowDelta", "Show gain as %",
                    "Add a line under the gain showing it as a share of the current standing, e.g. +4.2%."),
                icons = Toggle(4, "repIcons", "Show faction icon",
                    "The faction's icon as a round badge on the ring's top edge. Border in the standing color, red for a loss."),
                list = Execute(5, "Show icon list", function() ToggleIconGrid() end,
                    "Show every game icon the rings use, marked found or missing in this client. Also /sq icons."),
            }),
            colors = Box(3, "Colors", {
                standing = Toggle(1, "repUseStanding", "Color by standing",
                    "Hated red through Exalted purple. Turn off to use one color for every faction."),
                custom = Color(2, "repColors", "custom", "Single color", "Ring color when Color by standing is off.",
                    { disabled = function() return db.repUseStanding end }),
            }),
            size = SizeBox(4, "rep", "reputation ring",
                "Offset from the center of the screen. The default sits just left of the quest ring."),
        }))

    local pet = RingTab(6, "Pet", "Pet Ring",
        "A donut that fills when your pet gains experience, and celebrates when it levels up.",
        MergeTop(TopRow("pet", "pet ring", PreviewPetRing, "Show example pet XP: a gain and a level-up. Also /sq pet."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "petEnabled", "Show pet ring", "Pop up and fill when your pet gains experience."),
                afterCombat = Toggle(2, "petAfterCombat", "Wait until combat ends",
                    "Add up your pet's XP from a fight and show the total once combat ends."),
                delta = Toggle(3, "petShowDelta", "Show gain as %",
                    "Add a line under the gain showing it as a share of the pet's level, e.g. +4.2%."),
                portrait = Toggle(4, "petPortrait", "Show pet portrait",
                    "Your pet's portrait, as on its unit frame, as a round badge on the ring's top edge. "
                    .. "Border in the ring color, gold on a level-up."),
            }),
            colors = Box(3, "Colors", {
                xp = Color(1, "petColors", "xp", "Experience", "Ring and count color."),
                level = Color(2, "petColors", "level", "Level up", "Label and icon border color on a level-up."),
            }),
            size = SizeBox(4, "pet", "pet ring",
                "Offset from the center of the screen. The default sits right of the skill ring."),
        }))

    local ammo = RingTab(7, "Ammo", "Ammo Ring",
        "Stays out of the way while you have plenty. At or below the warning level it pops up each time "
        .. "you're another quarter of the way down, again when you run out, and when you restock.",
        MergeTop(TopRow("ammo", "ammo ring", PreviewAmmoRing, "Show examples: running low, running out, "
            .. "and restocking. Also /sq ammo."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "ammoEnabled", "Show ammo ring",
                    "Arrows, bullets and thrown weapons in your ammo or ranged slot."),
                warn = Range(2, "ammoWarn", "Warn at or below", 20, 1000, 10,
                    "How much ammo is left when the ring starts showing up."),
                afterCombat = Toggle(3, "ammoAfterCombat", "Wait until combat ends",
                    "Hold the warnings until the fight is over. Off by default: running low mid-fight is when it matters."),
                delta = Toggle(4, "ammoShowDelta", "Show change as %",
                    "Add a line under the change showing it as a share of a full supply."),
                icon = Toggle(5, "ammoIcon", "Show ammo icon",
                    "The icon of the ammo you have equipped (or your soul shards) as a round badge on the "
                    .. "ring's top edge. Border in the ring color."),
            }),
            shards = Box(3, "Soul shards (warlocks)", {
                enabled = Toggle(1, "ammoShards", "Track soul shards", "Use the same ring for your soul shards."),
                warn = Range(2, "ammoShardWarn", "Warn at or below", 1, 20, 1,
                    "How many shards are left when the ring starts showing up.",
                    { disabled = function() return not db.ammoShards end }),
            }),
            colors = Box(4, "Colors", {
                normal = Color(1, "ammoColors", "normal", "Plenty", "Ring color above the warning level."),
                low = Color(2, "ammoColors", "low", "Low", "Ring color at or below the warning level."),
                out = Color(3, "ammoColors", "out", "Out", "Ring color when you've run out."),
                restock = Color(4, "ammoColors", "restock", "Restocked", "Ring color when you buy or loot more."),
            }),
            size = SizeBox(5, "ammo", "ammo ring",
                "Offset from the center of the screen. The default sits at the right end of the row."),
        }))

    local flightTab = RingTab(8, "Flight", "Flight Ring",
        "Counts down to landing while you're on a flight path. The game doesn't give flight times, so the "
        .. "first trip on each route is timed (the ring circles and counts up); after that it counts down.",
        MergeTop(TopRow("flight", "flight ring", ns.PreviewFlightRing,
            "Show the ring counting down a known route, then timing a new one. Also /sq flight."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "flightEnabled", "Show flight ring", "Show the ring while you're on a flight path."),
                notice = Toggle(2, "flightLearnNotice", "Announce new route times",
                    "Print a chat line when a route has been timed for the first time."),
                routes = {
                    type = "description", order = 3, fontSize = "medium", width = "full",
                    name = function()
                        local n = ns.KnownRouteCount()
                        return n == 1 and "1 route timed so far." or (n .. " routes timed so far.")
                    end,
                },
                forget = {
                    type = "execute", order = 4, width = 1.1, name = "Forget flight times",
                    desc = "Clear every learned route time, so each is timed again the next time you fly it.",
                    confirm = true, confirmText = "Forget all learned flight times?",
                    func = function() ns.ForgetFlightTimes() ns.RefreshOptions() end,
                },
            }),
            colors = Box(3, "Colors", {
                fill = Color(1, "flightColors", "fill", "Countdown", "Ring color on a route with a known time."),
                learning = Color(2, "flightColors", "learning", "Timing a route",
                    "Color of the circling arc while a new route is being timed."),
            }),
            size = SizeBox(4, "flight", "flight ring", "Offset from the center of the screen."),
        }))
    flightTab.args.size.args.hold.desc = "How long the ring stays after you land."

    local timedTab = RingTab(9, "Timed", "Timed Quest Ring",
        "Up while you have an escort or other timed quest: it drains as time runs out and turns the warning "
        .. "color near the end. With more than one, it shows the one with the least time left.",
        MergeTop(TopRow("timed", "timed quest ring", ns.PreviewTimedRing,
            "Show a sample timer running down into the warning range. Also /sq timed."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "timedEnabled", "Show timed quest ring", "Count down timed quests."),
                warn = Range(2, "timedWarn", "Warn at (seconds left)", 10, 300, 10,
                    "Below this much time (or the last 10% of the quest's time) the ring turns the warning color."),
            }),
            colors = Box(3, "Colors", {
                fill = Color(1, "timedColors", "fill", "Time left", "Ring color while there's time."),
                warn = Color(2, "timedColors", "warn", "Running out", "Ring and label color near the end."),
            }),
            size = SizeBox(4, "timed", "timed quest ring",
                "Offset from the center of the screen. The default sits on the right, by the quest list."),
        }))
    timedTab.args.size.args.hold.desc = "How long the ring stays after the time runs out."

    local breathTab = RingTab(10.5, "Breath", "Breath Ring",
        "Underwater, the ring drains with your breath (orange when it's low, red when it's nearly gone) with "
        .. "bubbles rising off it, then fills back up when you surface. Deep-water fatigue and Feign Death "
        .. "show the same way.",
        MergeTop(TopRow("breath", "breath ring", ns.PreviewBreathRing,
            "Show a sample dive. Also /sq breath."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "breathEnabled", "Show breath ring", "Show the ring while a breath, fatigue or Feign Death timer runs."),
                bubbles = Toggle(2, "breathBubbles", "Bubbles", "Little bubbles rising off the ring while you hold your breath."),
            }),
            colors = Box(3, "Colors", {
                fill = Color(1, "breathColors", "fill", "Breath", "Ring color with plenty of breath left, and while it refills."),
                low = Color(2, "breathColors", "low", "Running low", "Ring color under 30% breath."),
                critical = Color(3, "breathColors", "critical", "Nearly gone", "Ring color under 15% breath."),
                fatigue = Color(4, "breathColors", "fatigue", "Fatigue", "Ring color in deep water, before fatigue sets in."),
                feign = Color(5, "breathColors", "feign", "Feign Death", "Ring color while you play dead."),
            }),
            size = SizeBox(4, "breath", "breath ring",
                "Offset from the center of the screen. By default it shares the corpse ring's spot."),
        }))
    breathTab.args.size.args.hold.desc = "How long the ring stays after the timer ends."

    local corpseTab = RingTab(10, "Corpse", "Corpse Ring",
        "While you're a ghost: how far your corpse is (filling as you get closer), an arrow on the ring pointing "
        .. "toward it (straight up = ahead), and when you can resurrect.",
        MergeTop(TopRow("corpse", "corpse ring", ns.PreviewCorpseRing,
            "Show a sample corpse run. Also /sq corpse."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "corpseEnabled", "Show corpse ring", "Show the ring while you're a ghost."),
            }),
            colors = Box(3, "Colors", {
                fill = Color(1, "corpseColors", "fill", "Distance", "Ring color on the way back."),
                ready = Color(2, "corpseColors", "ready", "In range", "Ring color once you can resurrect."),
                marker = Color(3, "corpseColors", "marker", "Direction arrow", "Tint of the arrow pointing at your corpse."),
            }),
            size = SizeBox(4, "corpse", "corpse ring", "Offset from the center of the screen."),
        }))
    corpseTab.args.size.args.hold = nil

    local craftTab = RingTab(11, "Crafting", "Crafting Ring",
        "When you craft several at once (Create All, or a count), the ring fills through the batch, "
        .. "including the current cast, and shows how many are done. It ends with Done! (or Stopped).",
        MergeTop(TopRow("craft", "crafting ring", ns.PreviewCraftRing,
            "Show a sample batch of eight. Also /sq craft."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "craftEnabled", "Show crafting ring", "Show the ring while crafting a batch."),
                single = Toggle(2, "craftSingle", "Single crafts too",
                    "Also show it when you make just one, not only for batches."),
                icon = Toggle(3, "craftIcon", "Show item icon",
                    "The icon of what you're crafting as a round badge on the ring's top edge, "
                    .. "bordered in the ring color."),
            }),
            colors = Box(3, "Colors", {
                fill = Color(1, "craftColors", "fill", "Crafting", "Ring color while the batch is going."),
                done = Color(2, "craftColors", "done", "Done", "Ring and label color when the batch finishes."),
            }),
            size = SizeBox(4, "craft", "crafting ring", "Offset from the center of the screen."),
        }))
    craftTab.args.size.args.hold.desc = "How long the ring stays after the batch ends."

    local castTab = RingTab(13, "Casting", "Cast Ring",
        "Fills while you cast and drains while you channel, with the spell's icon and the time left. In combat "
        .. "the game hides cast timing from addons, so the ring keeps its own time from the spell's cast time "
        .. "(or how long it took when it last could see), and snaps to the real end when the cast goes off or "
        .. "is interrupted. It can't see pushback in combat, so a pushed-back cast runs a little long. A * after "
        .. "\"Casting\" means the time is the ring's own. Crafts and gathers use their own rings.",
        MergeTop(TopRow("cast", "cast ring", ns.PreviewCastRing,
            "Show a sample cast that goes off, then one that's interrupted. Also /sq cast."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "castEnabled", "Show cast ring", "Show the ring while you cast or channel."),
                icon = Toggle(2, "castIcon", "Show spell icon", "The spell's icon on the ring."),
            }),
            colors = Box(3, "Colors", {
                cast = Color(1, "castColors", "cast", "Casting", "Ring color while casting."),
                channel = Color(2, "castColors", "channel", "Channeling", "Ring color while channeling."),
                done = Color(3, "castColors", "done", "Done", "Ring color when the cast goes off."),
                interrupted = Color(4, "castColors", "interrupted", "Interrupted", "Ring color when it's interrupted or fails."),
            }),
            size = SizeBox(4, "cast", "cast ring",
                "Offset from the center of the screen. By default it shares the crafting ring's spot."),
        }))
    castTab.args.size.args.hold.desc = "How long the ring stays after the cast ends."
    castTab.args.size.args.hold.min = 0.5
    castTab.args.size.args.hold.step = 0.5

    local gatherTab = RingTab(12, "Gathering", "Gathering Ring",
        "While you mine, pick herbs or skin, the ring fills with the cast and shows the profession's icon. "
        .. "Fishing drains as the bobber waits. When it finishes it shows what you got (Copper Ore ×2). "
        .. "Interrupting a gather flashes the progress you lost.",
        MergeTop(TopRow("gather", "gathering ring", ns.PreviewGatherRing,
            "Show a sample mining and herb gather. Also /sq gather."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "gatherEnabled", "Show gathering ring", "Show the ring while gathering or fishing."),
                icon = Toggle(2, "gatherIcon", "Show icon",
                    "The profession's icon while gathering, and the item's icon when it's done."),
                loot = Toggle(3, "gatherLoot", "Show what you got",
                    "When the gather finishes, show the item and how many you got."),
            }),
            colors = Box(3, "Colors", {
                fill = Color(1, "gatherColors", "fill", "Gathering", "Ring color while mining, picking or skinning."),
                fishing = Color(2, "gatherColors", "fishing", "Fishing", "Ring color while fishing."),
                done = Color(3, "gatherColors", "done", "Done", "Ring and label color when you get the goods."),
            }),
            size = SizeBox(4, "gather", "gathering ring",
                "Offset from the center of the screen. By default it shares the crafting ring's spot."),
        }))
    gatherTab.args.size.args.hold.desc = "How long the ring stays after the gather ends."

    local pinTab = RingTab(5, "Quest rings", "Quest Rings",
        "Right-click a quest in your quest log and choose Create Quest Ring to give it its own ring, stacked "
        .. "by the quest list. Each shows objectives done, with one notch per objective (segmented style), and "
        .. "the next objective to do. It goes away once the quest leaves your log. Up to 5; also /sq ring <name>.",
        MergeTop(TopRow("pin", "quest rings", ns.PreviewPins, "Show two sample quest rings."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "pinEnabled", "Show quest rings", "Show the rings for pinned quests."),
                menu = Toggle(1.2, "pinMenu", "Right-click menu",
                    "Right-click a quest ring for a menu to remove it. Turn off so the rings ignore the mouse "
                    .. "entirely (remove them from the quest log's menu or /sq ring instead).",
                    function() ns.RefreshPinClicks() end),
                movable = Toggle(1.4, "pinMovable", "Movable",
                    "Let the quest rings be dragged (and reset with right-click) in edit mode. Turn off to lock "
                    .. "them in place; the position sliders below still work."),
                clear = {
                    type = "execute", order = 2, width = 1.1, name = "Remove all quest rings",
                    confirm = true, confirmText = "Remove every quest ring on this character?",
                    func = function() ns.ClearPins() end,
                },
            }),
            size = SizeBox(3, "pin", "quest rings",
                "Offset from the center of the screen. The rings stack downward from here; by default they "
                .. "start just left of the quest list."),
        }))
    pinTab.args.size.args.hold = nil
    pinTab.args.position.args.fromTop.desc = "Gap between the top of the screen and the top of the first ring."

    local totemTab = RingTab(6, "Totems", "Totem Rings",
        "Shamans: a small ring for each totem you have down, in the totem bar's order (earth, fire, water, "
        .. "air). The totem's icon sits in the middle with the time left, and the ring drains in the element's "
        .. "color.",
        MergeTop(TopRow("totem", "totem rings", ns.PreviewTotems, "Show four sample totems. Also /sq totems."), {
            general = Box(2, "General", {
                enabled = Toggle(1, "totemEnabled", "Show totem rings", "Show a ring for each active totem."),
                warn = Toggle(2, "totemWarn", "Pulse when ending", "Pulse a totem's ring in its last 10 seconds."),
            }),
            colors = Box(3, "Colors", {
                earth = Color(1, "totemColors", "earth", "Earth", "Earth totem ring color."),
                fire = Color(2, "totemColors", "fire", "Fire", "Fire totem ring color."),
                water = Color(3, "totemColors", "water", "Water", "Water totem ring color."),
                air = Color(4, "totemColors", "air", "Air", "Air totem ring color."),
            }),
            size = SizeBox(4, "totem", "totem rings",
                "Offset from the center of the screen to the first (earth) ring; the others line up to its right."),
        }))
    totemTab.args.size.args.hold = nil
    totemTab.args.size.args.size.min = 30
    totemTab.args.size.args.size.max = 120
    totemTab.args.size.args.size.step = 2

    pet.hidden = function() return HiddenForClass("pet") end
    ammo.hidden = function() return HiddenForClass("ammo") end
    totemTab.hidden = function() return HiddenForClass("totem") end
    ammo.order, flightTab.order, timedTab.order, corpseTab.order, breathTab.order = 5, 1, 2, 3, 4

    -- A folder in the list on the left: its own page just names what's inside.
    local function Folder(order, name, text, children)
        local args = { header = { type = "header", order = 0, name = name }, intro = Intro(0.5, text) }
        for k, v in pairs(children) do args[k] = v end
        return { type = "group", order = order, name = name, childGroups = "tree", args = args }
    end

    -- Profiles: named sets of settings, chosen per character.
    local function CurrentName() return ns.CurrentProfile() or "Default" end
    local profiles = {
        type = "group", order = 90, name = "Profiles",
        args = {
            header = { type = "header", order = 0, name = "Profiles" },
            intro = Intro(0.5, "A profile is a whole set of Circlet settings: which rings show, their colors, look "
                .. "and positions. Each character uses one profile, and switching is instant. Things Circlet "
                .. "learns as you play (flight times, reputations seen, session history) are shared by every "
                .. "profile."),
            current = Box(1, "This character", {
                info = { type = "description", order = 0, fontSize = "medium",
                    name = function()
                        local users = ns.CharsUsing(CurrentName())
                        return "Using |cffffd100" .. CurrentName() .. "|r"
                            .. (#users > 1 and (", shared with " .. (#users - 1) .. " other character"
                                .. (#users > 2 and "s" or "")) or "") .. "."
                    end },
                profile = {
                    type = "select", order = 1, name = "Profile", width = 1.4,
                    desc = "The profile this character uses.",
                    values = function() return (ns.ProfileList()) end,
                    sorting = function() return select(2, ns.ProfileList()) end,
                    get = CurrentName,
                    set = function(_, v) ns.SwitchProfile(v) end,
                },
                new = {
                    type = "input", order = 2, name = "New profile", width = 1.4,
                    desc = "Type a name and press Enter: a new profile starting from your current settings, "
                        .. "which this character then uses.",
                    get = function() return "" end,
                    set = function(_, v) ns.NewProfile(v) end,
                },
            }),
            manage = Box(2, "Manage", {
                copy = {
                    type = "select", order = 1, name = "Copy settings from", width = 1.4,
                    desc = "Replace this profile's settings with another profile's.",
                    values = function() return (ns.ProfileList(CurrentName())) end,
                    sorting = function() return select(2, ns.ProfileList(CurrentName())) end,
                    get = function() return nil end,
                    set = function(_, v) ns.CopyProfile(v) end,
                    confirm = function(_, v) return "Replace every setting in " .. CurrentName() .. " with " .. tostring(v) .. "'s?" end,
                    disabled = function() return next((ns.ProfileList(CurrentName()))) == nil end,
                },
                rename = {
                    type = "input", order = 2, name = "Rename this profile", width = 1.4,
                    desc = "Type a new name for the current profile and press Enter.",
                    get = function() return CurrentName() end,
                    set = function(_, v) ns.RenameProfile(v) end,
                },
                delete = {
                    type = "select", order = 3, name = "Delete a profile", width = 1.4,
                    desc = "Delete another profile. Characters that used it switch to the profile for new "
                        .. "characters the next time they log in.",
                    values = function() return (ns.ProfileList(CurrentName())) end,
                    sorting = function() return select(2, ns.ProfileList(CurrentName())) end,
                    get = function() return nil end,
                    set = function(_, v) ns.DeleteProfile(v) end,
                    confirm = function(_, v) return "Delete the profile " .. tostring(v) .. "?" end,
                    disabled = function() return next((ns.ProfileList(CurrentName()))) == nil end,
                },
                newChars = {
                    type = "select", order = 4, name = "New characters use", width = 1.4,
                    desc = "The profile a character starts with the first time it logs in with Circlet.",
                    values = function() return (ns.ProfileList()) end,
                    sorting = function() return select(2, ns.ProfileList()) end,
                    get = function()
                        local P = ns.ProfileStore()
                        return (P.newChars and P.profiles[P.newChars]) and P.newChars or "Default"
                    end,
                    set = function(_, v) ns.ProfileStore().newChars = v end,
                },
                resetNote = { type = "description", order = 5, name = "\nTo put this profile's settings back to "
                    .. "the defaults, use |cffffd100Reset to defaults|r on the General page." },
            }),
        },
    }

    return {
        type = "group", name = "Circlet", childGroups = "tree",
        args = {
            general = general,
            progress = Folder(2, "Progress rings",
                "Rings that pop up and fill as you gain XP, advance quests, raise skills and reputation, "
                .. "and level your pet.",
                { xp = xp, quest = quest, skill = skill, weapon = weapon, rep = rep, pet = pet }),
            status = Folder(3, "Travel & status",
                "Rings that count down or keep watch: flights, timed quests, corpse runs, breath and ammo.",
                { flight = flightTab, timed = timedTab, corpse = corpseTab, breath = breathTab, ammo = ammo }),
            professions = Folder(4, "Professions & casting",
                "Rings for crafting batches, gathering (mining, herbalism, skinning, fishing) and casting.",
                { craft = craftTab, gather = gatherTab, cast = castTab }),
            pin = pinTab,
            totem = totemTab,
            profiles = profiles,
        },
    }
end

---------------------------------------------------------------- the window
local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ADDON_NAME, "Version") or nil
end

local function SetupOptions()
    if not (AceGUI and AceConfigRegistry and AceConfigDialog) then
        error("the embedded AceConfig/AceGUI libraries didn't load")
    end
    AceConfigRegistry:RegisterOptionsTable(APP, BuildOptionsTable())

    -- The window, like Questie's: an AceGUI frame that AceConfigDialog fills with tabs.
    configFrame = AceGUI:Create("Frame")
    configFrame:Hide()
    configFrame:SetTitle("Circlet")
    local version = Version()
    configFrame:SetStatusText(version and ("Version " .. version .. "   ·   /sq help for commands") or "/sq help for commands")
    configFrame:SetLayout("Fill")
    configFrame:SetWidth(820)
    configFrame:SetHeight(660)
    AceConfigDialog:SetDefaultSize(APP, 820, 660)
    -- The list on the left: folders open, and wide enough for the page names.
    local status = AceConfigDialog:GetStatusTable(APP)
    status.groups = status.groups or {}
    status.groups.treewidth = status.groups.treewidth or 180
    status.groups.groups = status.groups.groups or { progress = true, status = true, professions = true }
    _G.CircletConfigFrame = configFrame
    table.insert(UISpecialFrames, "CircletConfigFrame") -- Esc closes it

    ns.RefreshOptions = function()
        if configFrame:IsShown() then AceConfigRegistry:NotifyChange(APP) end
    end

    -- Edit mode follows the page: opening a ring's page puts that ring in edit mode, and
    -- leaving the page (or closing the window) ends it. Only rings it started itself.
    local autoKey, lastPage = nil, nil
    local function StopAuto()
        if autoKey then ns.SetRingEditing(autoKey, false, true) end
        autoKey = nil
    end
    local watcher = CreateFrame("Frame")
    watcher.t = 0
    watcher:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        if self.t < 0.2 then return end
        self.t = 0
        local page = nil
        if configFrame:IsShown() then
            local selected = status.groups and status.groups.selected
            if type(selected) == "string" then page = selected:match("([^\001]+)$") end
            page = page or "general"
        end
        if page == lastPage then return end
        lastPage = page
        local key = page and RING_EDITORS[page] and page or nil
        if autoKey and autoKey ~= key then StopAuto() end
        if key and db.optionsAutoEdit and not RING_EDITORS[key].get() then
            ns.SetRingEditing(key, true, true)
            autoKey = key
        end
    end)

    -- Esc > Options > AddOns > Circlet: a short page that opens the window.
    if Settings and Settings.RegisterVerticalLayoutCategory then
        local category, layout = Settings.RegisterVerticalLayoutCategory("Circlet")
        layout:AddInitializer(CreateSettingsButtonInitializer("Circlet options", "Open options", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            if not configFrame:IsShown() then
                configFrame:Show()
                AceConfigDialog:Open(APP, configFrame)
            end
        end, "Open the Circlet options window. Also /sq.", true))
        Settings.RegisterAddOnCategory(category)
    end
end

-- Builds the window; if the options libraries misbehave on this client, the rest of
-- the addon still works.
local function TrySetupOptions()
    local ok, err = pcall(SetupOptions)
    if not ok then configFrame = nil end
    return ok, err
end

local function OpenOptions()
    if not configFrame then
        Print("The options window failed to load; slash commands still work (/sq help).")
    elseif configFrame:IsShown() then
        configFrame:Hide()
    else
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 852)
        configFrame:Show()
        AceConfigDialog:Open(APP, configFrame)
    end
end

-- The game's addon button by the minimap (set up in Circlet.toc).
function Circlet_OnAddonCompartmentClick()
    OpenOptions()
end

function Circlet_OnAddonCompartmentEnter(_, button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("Circlet")
    GameTooltip:AddLine("Click to open the options.", 1, 1, 1)
    GameTooltip:AddLine("/sq help for commands", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function Circlet_OnAddonCompartmentLeave()
    if GameTooltip then GameTooltip:Hide() end
end

-- Shared with the files loaded after this one.
ns.OpenOptions = OpenOptions
ns.TrySetupOptions = TrySetupOptions
