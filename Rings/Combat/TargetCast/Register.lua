-- Circlet: Target cast ring: its settings, options page and registration.
local _, ns = ...

local TC = ns.TargetCastRing
local targetCastRing = TC.targetCastRing

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "targetCast",
    name = "Target Cast",
    order = 14.5,
    since = "1.2.0",
    iconBg = true, -- the icon can be the ring's background (Core/Settings.lua, UI/Options/Kit.lua)
    ring = targetCastRing,
    preview = ns.PreviewTargetCastRing,
    slash = { "target", "targetcast" },
    help = "preview the target cast ring",
    toggle = { "Target cast ring", "What your target is casting, and whether you can interrupt it." },
    gameBar = "the game's target cast bar",
    alwaysInCombat = true, -- mostly for combat: no "Show in combat" option, never faded out in a fight
    defaults = {
        -- Target cast ring: your target's casts and channels. Below the cast ring.
        targetCastEnabled = true,
        targetCastIcon = true,
        targetCastName = true, -- the caster's name under the time
        targetCastHostileOnly = false, -- only targets you can attack
        targetCastSelf = true, -- targeting yourself: show your own casts too
        targetCastSize = 100,
        targetCastThickness = 10,
        targetCastOpacity = 100,
        targetCastX = 0,
        targetCastFromTop = 385,
        targetCastHold = 1,
        targetCastStyle = "smooth",
        targetCastBorder = 2,
        targetCastColors = {
            cast = { r = 1.00, g = 0.55, b = 0.20 },
            channel = { r = 0.40, g = 0.80, b = 1.00 },
            shielded = { r = 0.62, g = 0.62, b = 0.68 },
            done = { r = 0.40, g = 0.90, b = 0.40 },
            interrupted = { r = 1.00, g = 0.30, b = 0.30 },
        },
    },
    page = {
        folder = "combat",
        order = 2,
        build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(
                13.5,
                "Target casting",
                "Target Cast Ring",
                "Fills while your target casts and drains while it channels, with the spell's icon, the time left "
                    .. "and who's casting. A cast you can't interrupt turns the ring gray. When it ends the ring turns "
                    .. "green (it went off) or red (interrupted), and an interrupted cast flashes the part it lost. If "
                    .. "the game hides the target's cast timing, the ring keeps its own from the spell's cast time, and a * "
                    .. "after the label means the time is the ring's own.",
                MergeTop(
                    TopRow(
                        "targetCast",
                        "target cast ring",
                        ns.PreviewTargetCastRing,
                        "Show a sample cast that goes off, one that's interrupted, then a channel you can't interrupt. "
                            .. "Also /circ target."
                    ),
                    {
                        general = Box(2, "General", {
                            enabled = Toggle(
                                1,
                                "targetCastEnabled",
                                "Show target cast ring",
                                "Show the ring while your target casts or channels."
                            ),
                            icon = Toggle(2, "targetCastIcon", "Show spell icon", "The spell's icon on the ring."),
                            name = Toggle(
                                3,
                                "targetCastName",
                                "Show caster's name",
                                "Your target's name under the time (the label says \"Can't interrupt\" instead when it can't be)."
                            ),
                            hostile = Toggle(
                                4,
                                "targetCastHostileOnly",
                                "Enemies only",
                                "Only for targets you can attack, not friendly players or NPCs."
                            ),
                            self = Toggle(
                                5,
                                "targetCastSelf",
                                "Include yourself",
                                "When you target yourself, show your own casts here too (the cast ring shows them as well).",
                                nil
                            ),
                        }),
                        colors = Box(3, "Colors", {
                            cast = Color(
                                1,
                                "targetCastColors",
                                "cast",
                                "Casting",
                                "Ring color while your target casts."
                            ),
                            channel = Color(
                                2,
                                "targetCastColors",
                                "channel",
                                "Channeling",
                                "Ring color while it channels."
                            ),
                            shielded = Color(
                                3,
                                "targetCastColors",
                                "shielded",
                                "Can't interrupt",
                                "Ring color for a cast or channel you can't interrupt."
                            ),
                            done = Color(4, "targetCastColors", "done", "Done", "Ring color when the cast goes off."),
                            interrupted = Color(
                                5,
                                "targetCastColors",
                                "interrupted",
                                "Interrupted",
                                "Ring color when it's interrupted or fails."
                            ),
                        }),
                        size = SizeBox(
                            4,
                            "targetCast",
                            "target cast ring",
                            "Offset from the center of the screen. By default it sits below the cast ring."
                        ),
                    }
                )
            )
            tab.args.size.args.hold.desc = "How long the ring stays after the cast ends."
            tab.args.size.args.hold.min = 0.5
            tab.args.size.args.hold.step = 0.5
            return tab
        end,
    },
})
