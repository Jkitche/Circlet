-- Circlet: XP ring: its settings, options page and registration.
local _, ns = ...

local db = ns.db
local XP = ns.XPRing
local AlwaysOn = XP.AlwaysOn
local gainFx = XP.gainFx
local restIcon = XP.restIcon
local SetXPEditing = XP.SetXPEditing
local OnXPAlwaysChanged = XP.OnXPAlwaysChanged
local PreviewLevelUp = XP.PreviewLevelUp
local PreviewXPRing = XP.PreviewXPRing

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "xp",
    name = "XP",
    order = 3,
    edit = { set = SetXPEditing, get = function() return XP.xpEditing end },
    preview = PreviewXPRing,
    slash = { "xp" },
    help = "preview the XP ring",
    toggle = { "XP ring", "Fills when you gain experience.", OnXPAlwaysChanged },
    gameBar = "the game's XP bar",
    onReset = function() OnXPAlwaysChanged() end,
    defaults = {
        xpEnabled = true,
        xpSize = 140,
        xpThickness = 14,
        xpOpacity = 100, -- percent
        xpX = 0,
        xpFromTop = 40,
        xpHold = 3,
        xpStyle = "smooth",
        xpBorder = 2, -- black border width (0 = none)
        xpRestedRing = true, -- at an inn or city, keep the ring up showing rested XP building
        xpRestedGain = true, -- leaving a rest area, show how much rested XP you gained there
        xpRestIcon = true, -- the animated "zZZ" on the ring while you're resting
        restBase = {}, -- per character: rested XP when you entered the current rest area
        xpAfterCombat = true,
        xpShowDelta = true, -- "+23.6%" under the XP gain
        xpLevelFxStyle = "gold", -- level-up effect: "gold", "rainbow" or "none"
        xpGainFx = true, -- a comet riding the fill as XP comes in, with a flare where it lands
        xpAlways = false, -- keep the XP ring on screen permanently
        xpMinimap = false, -- draw the XP ring around the minimap (always on; text below the map)
        xpMinimapGap = 2, -- gap between the minimap's edge and the ring
        xpMinimapBehind = true, -- draw the ring behind the minimap (its border and buttons go on top)
        xpHideText = true, -- always-on ring out in the world: fade its text out after xpHideTextDelay idle seconds
        xpHideTextDelay = 3,
    },
    page = {
        folder = "progress",
        order = 2,
        build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(
                2,
                "XP",
                "XP Ring",
                "A donut that pops up and fills when you gain experience, colored by rest state.",
                MergeTop(
                    TopRow(
                        "xp",
                        "XP ring",
                        PreviewXPRing,
                        "Show example XP gains: rested, rested running out, " .. "and a level-up. Also /circ xp."
                    ),
                    {
                        general = Box(2, "General", {
                            enabled = Toggle(
                                1,
                                "xpEnabled",
                                "Show XP ring",
                                "Pop up and fill when you gain experience.",
                                OnXPAlwaysChanged
                            ),
                            afterCombat = Toggle(
                                3,
                                "xpAfterCombat",
                                "Wait until combat ends",
                                "Add up all XP earned during a fight and show the total once combat ends."
                            ),
                            delta = Toggle(
                                4,
                                "xpShowDelta",
                                "Show gain as %",
                                "Add a line under the gain showing it as a share of the level, e.g. +4.2%."
                            ),
                        }),
                        display = Box(2.2, "Always on & minimap", {
                            always = Toggle(
                                2,
                                "xpAlways",
                                "Always show",
                                "Keep the XP ring on screen permanently. Gains still animate and count up.",
                                OnXPAlwaysChanged
                            ),
                            minimap = Toggle(
                                2.05,
                                "xpMinimap",
                                "Show as minimap border",
                                "Wrap the XP ring around your minimap, as an XP bar that's always there. Its text sits below "
                                    .. "the map (and hides when idle, below). Size and position settings don't apply then; "
                                    .. "thickness, style and colors do.",
                                OnXPAlwaysChanged
                            ),
                            minimapGap = {
                                type = "range",
                                order = 2.07,
                                name = "Distance from the map",
                                min = -10,
                                max = 30,
                                step = 1,
                                desc = "Gap between the edge of the minimap and the ring. Negative values overlap the map's edge.",
                                get = function() return db.xpMinimapGap or 2 end,
                                set = function(_, v) db.xpMinimapGap = v end,
                                disabled = function() return not db.xpMinimap end,
                            },
                            minimapBehind = {
                                type = "toggle",
                                order = 2.08,
                                name = "Behind the minimap",
                                desc = "Draw the ring behind the minimap, so the map, its border and its buttons sit on top of "
                                    .. "it. Off: the ring draws over them.",
                                get = function() return db.xpMinimapBehind end,
                                set = function(_, v) db.xpMinimapBehind = v end,
                                disabled = function() return not db.xpMinimap end,
                            },
                            hideText = {
                                type = "toggle",
                                order = 2.1,
                                name = "Hide text when idle",
                                desc = "With Always show on: out in the world, the ring's text fades out once nothing has changed "
                                    .. "for a few seconds, so the ring works as a plain XP bar. The text comes back when you gain "
                                    .. "XP or put the mouse over the ring, and stays while you're resting (it shows your rested XP).",
                                get = function() return db.xpHideText end,
                                set = function(_, v) db.xpHideText = v end,
                                disabled = function() return not (db.xpAlways or db.xpMinimap) end,
                            },
                            hideDelay = {
                                type = "range",
                                order = 2.2,
                                name = "Hide text after (seconds)",
                                min = 1,
                                max = 30,
                                step = 1,
                                desc = "How long the always-on ring shows its text after a change before fading it out.",
                                get = function() return db.xpHideTextDelay or 3 end,
                                set = function(_, v) db.xpHideTextDelay = v end,
                                disabled = function() return not ((db.xpAlways or db.xpMinimap) and db.xpHideText) end,
                            },
                        }),
                        rest = Box(2.3, "Resting", {
                            resting = Toggle(
                                2.5,
                                "xpRestedRing",
                                "Show while resting",
                                "At an inn or in a city, keep the ring up showing your rested XP building (the blue band) "
                                    .. "and roughly how long until you're fully rested.",
                                function() ns.OnRestingChanged() end
                            ),
                            restIcon = Toggle(
                                2.55,
                                "xpRestIcon",
                                "Resting zZZ",
                                "While you're resting, the animated zZZ from your player portrait sits on the ring's "
                                    .. "top-right edge."
                            ),
                            restedGain = Toggle(
                                2.6,
                                "xpRestedGain",
                                "Show rested XP gained",
                                "When you leave an inn or city, the ring pops up with the rested band growing by the rested "
                                    .. "XP you gained there (including while logged out), e.g. +1,240 rested."
                            ),
                        }),
                        levelUp = Box(3, "Effects", {
                            gainFx = Toggle(
                                0.5,
                                "xpGainFx",
                                "Gain effect",
                                "As XP comes in, a glowing comet rides the end of the fill shedding sparkles, "
                                    .. "with a flare where it lands."
                            ),
                            style = Select(
                                1,
                                "xpLevelFxStyle",
                                "Effect",
                                { gold = "Gold", rainbow = "Rainbow", none = "Off" },
                                { "gold", "rainbow", "none" },
                                "Gold: a gold flash, shockwaves and sparks. Rainbow: a rainbow swirl around the ring, "
                                    .. "then a rainbow flash, shockwaves and sparks. Off: no effect."
                            ),
                            preview = Execute(
                                2,
                                "Preview level-up",
                                PreviewLevelUp,
                                "Show a level-up with the selected effect. Also /circ levelup."
                            ),
                            restedPreview = Execute(
                                3,
                                "Preview rested gain",
                                function() ns.PreviewRestedGain() end,
                                "Show what leaving an inn looks like after gaining rested XP. Also /circ rested."
                            ),
                        }),
                        size = SizeBox(4, "xp", "XP ring", "Offset from the center of the screen."),
                    }
                )
            )
            -- Settings only show when they do something: the minimap border's own settings with
            -- it on; idle-text settings when the ring is always up; pop-up settings (how long it
            -- stays, showing while resting) only when it isn't; size and position not around the map.
            local function AlwaysOn() return db.xpAlways or db.xpMinimap end
            local general, look = tab.args.display.args, tab.args.size.args
            local rest = tab.args.rest.args
            general.always.hidden = function() return db.xpMinimap end
            general.minimapGap.hidden = function() return not db.xpMinimap end
            general.minimapBehind.hidden = function() return not db.xpMinimap end
            general.hideText.hidden = function() return not AlwaysOn() end
            general.hideDelay.hidden = function() return not AlwaysOn() end
            rest.resting.hidden = AlwaysOn
            look.hold.hidden = AlwaysOn
            look.size.hidden = function() return db.xpMinimap end
            if tab.args.position then tab.args.position.hidden = function() return db.xpMinimap end end
            return tab
        end,
    },
})
