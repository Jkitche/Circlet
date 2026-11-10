-- Circlet: Option builders shared by every ring's options page (AceConfig tables).
local ADDON_NAME, ns = ...

local db, DEFAULTS, Print = ns.db, ns.DEFAULTS, ns.Print

---------------------------------------------------------------------------
-- Option builders
---------------------------------------------------------------------------
-- Each ring's file builds its own options page from these (its registry entry's
-- page.build gets this table as O). Rings read db every frame, so most settings need no
-- callback. Helpers that act on rings (edit mode, positions) are looked up in ns when
-- they're used, since those files load later.

-- Saved data the addon learns as you play, not settings: resets leave it alone.
local function Learned() return ns.LEARNED end

local function ResetDefaults()
    for key, value in pairs(DEFAULTS) do
        if not Learned()[key] then db[key] = ns.Copy(value) end
    end
    ns.OnXPAlwaysChanged()
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
        if not Learned()[k] and k:sub(1, #key) == key and k:sub(#key + 1, #key + 1):match("%u") then
            db[k] = ns.Copy(value)
        end
    end
    -- Per-ring overrides inside a group (pin1X, totem2Size, ...).
    for k in pairs(CircletDB) do
        if type(k) == "string" and k:match("^" .. key .. "%d+%u") then CircletDB[k] = nil end
    end
    ns.ResetPosition(key, true)
    local def = ns.FindRing(key)
    if def and def.onReset then def.onReset() end
    ns.RefreshOptions()
    Print(((def and def.name) or key) .. " ring reset to defaults.")
end

-- The settings that make up a ring's look, copied by "Apply this look to all rings".
local LOOK_FIELDS = { "Style", "Fill", "Shape", "Rotation", "Thickness", "Border", "Opacity", "Gradient" }

local function ApplyLookToAll(key)
    for _, def in ipairs(ns.RINGS) do
        if def.key ~= key then
            for _, field in ipairs(LOOK_FIELDS) do db[def.key .. field] = db[key .. field] end
        end
    end
    ns.RefreshOptions()
    Print("Applied the " .. ((ns.FindRing(key) or {}).name or key) .. " ring's look to every ring.")
end

-- The top row of every ring tab: Edit mode (live preview + drag), the preview and reset.
local function TopRow(key, what, preview, previewDesc)
    return {
        edit = {
            type = "execute", order = 1, width = 1.1,
            name = function() return ns.FindRing(key).edit.get() and "|cff33ff33Finish editing|r" or "Edit mode" end,
            desc = "Keep the " .. what .. " on screen cycling through sample changes, so color, size and other "
                .. "settings show live as you change them here, and drag the ring to move it "
                .. "(right-click it to reset its position). Also /sq edit " .. key .. ".",
            func = function() ns.ToggleRingEditing(key) end,
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
        style     = Select(0.5, key .. "Style", "Ring style", ns.RING_STYLE_NAMES, ns.RING_STYLE_ORDER,
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
        reset     = Execute(7, "Reset position", function() ns.ResetPosition(key) end,
            "Move only the " .. what .. " back to its default spot. Also /sq resetpos " .. key .. "."),
    })
    return look
end

-- A ring's options page. args: its boxes (general, colors, size = SizeBox(...), ...).
-- Adds the header, intro, the Position box (from SizeBox), and to the General box (or
-- Appearance, if it has none) "Hide the game's ..." when the ring has a game bar, and
-- "Show in combat".
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
        local def = ns.FindRing(key) or {}
        local gameBar = def.gameBar
        if def.iconBg then
            -- def.iconBg: true, or { disabled = fn, note = "..." } when it only applies sometimes.
            local ib = type(def.iconBg) == "table" and def.iconBg or {}
            box.args.iconBg = {
                type = "toggle", order = 45, width = "full", name = "Icon as background",
                desc = "Show the icon filling the middle of the ring, behind its text, instead of as a badge "
                    .. "on its top edge." .. (ib.note and (" " .. ib.note) or ""),
                get = function() return db[key .. "IconBg"] end,
                set = function(_, v) db[key .. "IconBg"] = v end,
                disabled = ib.disabled,
            }
            box.args.iconBgAlpha = Range(46, key .. "IconBgAlpha", "Background icon opacity", 10, 100, 5,
                "How strongly the background icon shows. Lower keeps the ring's text easier to read.",
                { disabled = function() return not db[key .. "IconBg"] or (ib.disabled and ib.disabled()) end })
        end
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

-- Shared with the files loaded after this one.
ns.O = {
    Toggle = Toggle, Range = Range, Select = Select, Color = Color, Execute = Execute, Box = Box,
    Spacer = Spacer, Intro = Intro, TopRow = TopRow, SizeBox = SizeBox, RingTab = RingTab, MergeTop = MergeTop,
}
ns.ResetDefaults = ResetDefaults
ns.ResetRing = ResetRing
