-- Circlet: Line-drawn ring icons (the "Drawn" skill icon style).
local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Ring icons: simple line-drawn glyphs that sit in a ring's centre
---------------------------------------------------------------------------
-- Drawn from lines like the rings, so they stay crisp at any size and take any
-- color. Each stroke is { x1, y1, x2, y2, width } in a -1..1 box; the whole glyph
-- is then rotated by its tilt (radians).

local function ArcStrokes(cx, cy, r, a1, a2, steps, width)
    local strokes = {}
    local step = math.rad(math.abs(a2 - a1) / steps)
    local miter = (width / 2) * math.tan(step / 2) -- overlap so the joints have no notches
    for i = 1, steps do
        local s = math.rad(a1 + (a2 - a1) * (i - 1) / steps)
        local e = math.rad(a1 + (a2 - a1) * i / steps)
        local x1, y1 = cx + r * math.cos(s), cy + r * math.sin(s)
        local x2, y2 = cx + r * math.cos(e), cy + r * math.sin(e)
        local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        local ux, uy = (x2 - x1) / len * miter, (y2 - y1) / len * miter
        table.insert(strokes, { x1 - ux, y1 - uy, x2 + ux, y2 + uy, width })
    end
    return strokes
end

local GLYPHS = {
    -- Weapon skills: a sword.
    sword = {
        tilt = math.rad(-45),
        strokes = {
            { 0, -0.22, 0, 0.82, 0.17 },   -- blade
            { 0, 0.80, 0, 1.00, 0.08 },    -- tip
            { -0.40, -0.24, 0.40, -0.24, 0.13 }, -- crossguard
            { 0, -0.24, 0, -0.70, 0.10 },  -- grip
            { 0, -0.70, 0, -0.88, 0.20 },  -- pommel
        },
    },
    -- Professions: a smithing hammer.
    hammer = {
        tilt = math.rad(35),
        strokes = {
            { 0, -0.95, 0, 0.42, 0.13 },   -- handle
            { -0.48, 0.62, 0.40, 0.62, 0.36 }, -- head
            { 0.40, 0.62, 0.58, 0.62, 0.26 },  -- striking face
            { -0.48, 0.62, -0.62, 0.62, 0.18 }, -- peen
        },
    },
    -- Secondary skills: a fishing hook.
    hook = {
        tilt = math.rad(10),
        strokes = (function()
            local s = ArcStrokes(0.18, 0.86, 0.11, 0, 360, 8, 0.07) -- eye
            table.insert(s, { 0.18, 0.75, 0.18, -0.30, 0.11 })        -- shank
            for _, a in ipairs(ArcStrokes(-0.14, -0.30, 0.32, 0, -180, 9, 0.11)) do
                table.insert(s, a)                                       -- bend
            end
            table.insert(s, { -0.46, -0.30, -0.46, 0.10, 0.10 })      -- point
            table.insert(s, { -0.46, 0.10, -0.30, -0.10, 0.08 })      -- barb
            return s
        end)(),
    },
}

-- One glyph per weapon skill (vanilla skill line IDs). Same -1..1 box and stroke
-- format as above. Anything not listed falls back to the plain sword.
local function Merge(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, s in ipairs(list) do table.insert(out, s) end
    end
    return out
end

GLYPHS.greatsword = {
    tilt = math.rad(-45),
    strokes = {
        { 0, -0.12, 0, 0.86, 0.22 },          -- broad blade
        { 0, 0.84, 0, 1.00, 0.11 },           -- tip
        { -0.50, -0.14, 0.50, -0.14, 0.13 },  -- wide crossguard
        { 0, -0.14, 0, -0.80, 0.11 },         -- long two-hand grip
        { -0.09, -0.36, 0.09, -0.36, 0.05 },  -- grip wraps
        { -0.09, -0.56, 0.09, -0.56, 0.05 },
        { 0, -0.80, 0, -0.97, 0.20 },         -- pommel
    },
}
-- An axe blade flaring out from the handle at height y, on side dir (1 = right).
local function AxeBlade(y, dir)
    return Merge({
        { 0.02 * dir, y, 0.14 * dir, y, 0.24 },
        { 0.14 * dir, y, 0.26 * dir, y, 0.40 },
        { 0.26 * dir, y, 0.38 * dir, y, 0.56 },
    }, ArcStrokes(0.16 * dir, y, 0.38, dir > 0 and -60 or 120, dir > 0 and 60 or 240, 6, 0.12))
end

GLYPHS.axe = {
    tilt = math.rad(30),
    strokes = Merge({ { 0, -0.95, 0, 0.78, 0.12 } }, AxeBlade(0.50, 1)),
}
GLYPHS.greataxe = {
    tilt = math.rad(30),
    strokes = Merge({ { 0, -1.00, 0, 0.84, 0.12 } }, AxeBlade(0.54, 1), AxeBlade(0.54, -1)),
}
GLYPHS.mace = {
    tilt = math.rad(30),
    strokes = {
        { 0, -0.95, 0, 0.30, 0.12 },          -- handle
        { 0, 0.30, 0, 0.84, 0.36 },           -- head
        { -0.30, 0.46, 0.30, 0.46, 0.10 },    -- flanges
        { -0.30, 0.68, 0.30, 0.68, 0.10 },
        { 0, 0.84, 0, 0.98, 0.10 },           -- top spike
    },
}
GLYPHS.maul = {
    tilt = math.rad(30),
    strokes = {
        { 0, -1.00, 0, 0.36, 0.12 },          -- long handle
        { -0.42, 0.62, 0.42, 0.62, 0.52 },    -- heavy block head
        { -0.42, 0.62, -0.50, 0.62, 0.40 },   -- striking faces
        { 0.42, 0.62, 0.50, 0.62, 0.40 },
        { 0, -0.70, 0, -0.98, 0.17 },         -- grip
    },
}
GLYPHS.dagger = {
    tilt = math.rad(-45),
    strokes = {
        { 0, -0.10, 0, 0.62, 0.17 },          -- short blade
        { 0, 0.60, 0, 0.76, 0.08 },           -- tip
        { -0.26, -0.12, 0.26, -0.12, 0.11 },  -- guard
        { 0, -0.12, 0, -0.46, 0.10 },         -- grip
        { 0, -0.46, 0, -0.58, 0.17 },         -- pommel
    },
}
GLYPHS.staff = {
    tilt = math.rad(-30),
    strokes = Merge({
        { 0, -1.00, 0, 0.62, 0.11 },          -- shaft
        { -0.08, -0.30, 0.08, -0.30, 0.05 },  -- grip bands
        { -0.08, -0.12, 0.08, -0.12, 0.05 },
    }, ArcStrokes(0, 0.80, 0.18, 0, 360, 10, 0.08)), -- ring top
}
GLYPHS.polearm = {
    tilt = math.rad(30),
    strokes = {
        { 0, -1.00, 0, 0.62, 0.10 },          -- long shaft
        { 0, 0.60, 0, 1.00, 0.13 },           -- spear point
        { 0.02, 0.42, 0.36, 0.42, 0.34 },     -- axe blade
        { -0.02, 0.42, -0.20, 0.42, 0.10 },   -- back spike
    },
}
GLYPHS.bow = {
    tilt = 0,
    strokes = Merge(
        ArcStrokes(-0.62, 0, 0.98, -55, 55, 10, 0.11), -- stave
        {
            { -0.06, -0.80, -0.06, 0.80, 0.035 },        -- string
            { -0.06, 0, 0.82, 0, 0.05 },                 -- arrow shaft
            { 0.82, 0, 0.66, 0.10, 0.06 },               -- arrowhead
            { 0.82, 0, 0.66, -0.10, 0.06 },
            { -0.06, 0, -0.18, 0.08, 0.05 },             -- fletching
            { -0.06, 0, -0.18, -0.08, 0.05 },
        }),
}
GLYPHS.crossbow = {
    tilt = 0,
    strokes = Merge(
        { { 0, -0.95, 0, 0.62, 0.15 } },                 -- stock
        ArcStrokes(0, -0.05, 0.78, 25, 155, 10, 0.11),   -- prod (the bow part)
        {
            { -0.71, 0.28, 0, 0.12, 0.035 },             -- string
            { 0.71, 0.28, 0, 0.12, 0.035 },
            { 0, 0.12, 0, 0.88, 0.05 },                  -- loaded bolt
            { 0.07, -0.42, 0.18, -0.52, 0.07 },          -- trigger
        }),
}
GLYPHS.gun = {
    tilt = math.rad(15),
    strokes = Merge({
        { -0.66, 0.18, 0.92, 0.18, 0.15 },    -- barrel
        { 0.80, 0.18, 0.80, 0.28, 0.07 },     -- front sight
        { -0.60, 0.14, -0.95, -0.28, 0.30 },  -- stock
        { -0.62, 0.10, 0.30, 0.10, 0.12 },    -- body under the barrel
    }, ArcStrokes(-0.20, -0.02, 0.12, 180, 360, 5, 0.05)), -- trigger guard
}
GLYPHS.thrown = {
    tilt = math.rad(12),
    strokes = Merge({
        { -0.88, 0, 0.88, 0, 0.14 },          -- four-point throwing star
        { 0, -0.88, 0, 0.88, 0.14 },
        { -0.40, 0, 0.40, 0, 0.34 },          -- thicker body near the middle
        { 0, -0.40, 0, 0.40, 0.34 },
    }, ArcStrokes(0, 0, 0.12, 0, 360, 8, 0.06)),
}
GLYPHS.wand = {
    tilt = 0,
    strokes = {
        { -0.78, -0.78, 0.40, 0.40, 0.11 },   -- rod
        { -0.78, -0.78, -0.58, -0.58, 0.17 }, -- handle end
        { 0.62, 0.36, 0.62, 0.92, 0.07 },     -- sparkle at the tip
        { 0.34, 0.64, 0.90, 0.64, 0.07 },
        { 0.48, 0.50, 0.76, 0.78, 0.05 },
        { 0.48, 0.78, 0.76, 0.50, 0.05 },
    },
}
GLYPHS.fist = {
    tilt = math.rad(-10),
    strokes = {
        { -0.52, -0.28, 0.52, -0.28, 0.30 },  -- knuckle bar
        { -0.34, -0.15, -0.24, 0.78, 0.13 },  -- three claws
        { 0, -0.15, 0, 0.92, 0.13 },
        { 0.34, -0.15, 0.24, 0.78, 0.13 },
        { 0, -0.45, 0, -0.85, 0.26 },         -- grip
    },
}
GLYPHS.unarmed = {
    tilt = 0,
    strokes = {
        { -0.33, 0.05, -0.33, 0.42, 0.18 },   -- four knuckles
        { -0.11, 0.05, -0.11, 0.48, 0.18 },
        { 0.11, 0.05, 0.11, 0.46, 0.18 },
        { 0.33, 0.05, 0.33, 0.38, 0.18 },
        { -0.42, -0.22, 0.42, -0.22, 0.50 },  -- back of the hand
        { -0.42, -0.08, -0.60, 0.20, 0.17 },  -- thumb
        { 0, -0.45, 0, -0.88, 0.42 },         -- wrist
    },
}
GLYPHS.shield = {
    tilt = 0,
    strokes = {
        { -0.62, 0.66, 0.62, 0.66, 0.12 },    -- top edge
        { -0.62, 0.66, -0.62, 0.10, 0.12 },   -- sides
        { 0.62, 0.66, 0.62, 0.10, 0.12 },
        { -0.62, 0.12, 0, -0.88, 0.12 },      -- tapering to a point
        { 0.62, 0.12, 0, -0.88, 0.12 },
        { 0, 0.56, 0, -0.66, 0.08 },          -- centre bands
        { -0.50, 0.24, 0.50, 0.24, 0.08 },
    },
}

local WEAPON_GLYPHS = {
    [43] = "sword", [55] = "greatsword", [44] = "axe", [172] = "greataxe",
    [54] = "mace", [160] = "maul", [173] = "dagger", [136] = "staff", [229] = "polearm",
    [45] = "bow", [226] = "crossbow", [46] = "gun", [176] = "thrown", [228] = "wand",
    [473] = "fist", [162] = "unarmed", [95] = "shield",
}

-- Draws glyph `name` into holder (lines are created on demand), centred on the
-- holder, `size` units across, rotated by `rotation` on top of the glyph's tilt.
local function DrawGlyph(holder, name, size, rotation, c)
    local glyph = GLYPHS[name]
    holder.glyphLines = holder.glyphLines or {}
    local lines = holder.glyphLines
    local half = size / 2
    local rot = glyph.tilt + (rotation or 0)
    local cosr, sinr = math.cos(rot), math.sin(rot)
    for i, s in ipairs(glyph.strokes) do
        local line = lines[i]
        if not line then
            line = holder:CreateLine(nil, "ARTWORK")
            lines[i] = line
        end
        local x1 = (s[1] * cosr - s[2] * sinr) * half
        local y1 = (s[1] * sinr + s[2] * cosr) * half
        local x2 = (s[3] * cosr - s[4] * sinr) * half
        local y2 = (s[3] * sinr + s[4] * cosr) * half
        line:SetStartPoint("CENTER", holder, x1, y1)
        line:SetEndPoint("CENTER", holder, x2, y2)
        line:SetThickness(math.max(1, s[5] * half))
        line:SetColorTexture(c.r, c.g, c.b, 1)
        line:Show()
    end
    for i = #glyph.strokes + 1, #lines do lines[i]:Hide() end
end

-- How a ring icon animates when it "celebrates" (skill cap reached, new tier):
-- springs in with an overshoot, wiggles, pulses with a glow, then settles.
local ICON_CELEBRATE = 2.2

local function IconPose(t, resting)
    -- returns scale, rotation, strength (0..1 opacity of the icon), glow (0..1);
    -- after the pop it settles back to the resting opacity.
    local scale
    if t < 0.22 then
        scale = 1.3 * (1 - (1 - t / 0.22) ^ 2)
    elseif t < 0.4 then
        scale = 1.3 - 0.3 * ((t - 0.22) / 0.18)
    else
        scale = 1 + ((t < ICON_CELEBRATE) and math.sin((t - 0.4) * 2 * math.pi * 1.4) * 0.04 or 0)
    end
    local rotation = (t < 1.0) and math.sin(t * 2 * math.pi * 3) * 0.3 * (1 - t) or 0
    local strength = (t < 0.4) and 1 or math.max(resting, 1 - (t - 0.4) / 0.6 * (1 - resting))
    local glow = (t < ICON_CELEBRATE) and math.min(1, t / 0.3) * (0.85 + 0.15 * math.sin(t * 2 * math.pi * 1.4))
        * (1 - math.max(0, (t - (ICON_CELEBRATE - 0.6)) / 0.6)) or 0
    return scale, rotation, strength, glow
end

-- Shared with the files loaded after this one.
ns.DrawGlyph = DrawGlyph
ns.ICON_CELEBRATE = ICON_CELEBRATE
ns.IconPose = IconPose
ns.WEAPON_GLYPHS = WEAPON_GLYPHS
