-- Circlet: Loot roll ring: how long is left to roll Need or Greed, with a dice badge.
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing, FormatTime = ns.db, ns.IsSecret, ns.CreateLiveRing, ns.FormatTime
local SafeCall, Clean = ns.SafeCall, ns.Clean

---------------------------------------------------------------------------
-- Loot roll ring
---------------------------------------------------------------------------
-- Up while an item is being rolled for in your group: the ring drains over the roll's time
-- limit, with the Need roll's dice as a badge on its top edge (or, with Icon as background,
-- filling the ring's middle behind the text), the item's name in its quality color and the
-- seconds left. In the last few seconds (lootWarn) it turns the warning color. Once you
-- roll it says what you picked ("Rolled Need"); pass and that roll drops off. With several
-- rolls at once it shows the most urgent, the ones you still have to answer first, with
-- "+N" for the others.
--
-- The time comes from GetLootRollTimeLeft while it's readable, else from the roll's time
-- limit counted from when it started. A roll ends when the game cancels it (everyone has
-- rolled, or time ran out), or a moment after its time is up.

local ROLL_NAMES = { [0] = "Pass", [1] = "Need", [2] = "Greed", [3] = "Disenchant", [4] = "Transmog" }

-- The dice: the Need button's icon from the game's group loot window, else a dice item icon.
local DICE_CANDIDATES = {
    "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    "Interface\\Icons\\INV_Misc_Dice_02",
    "Interface\\Icons\\INV_Misc_Dice_01",
}
local dice
local function DiceTexture()
    if dice then return dice end
    dice = DICE_CANDIDATES[1]
    if GetFileIDFromPath then
        for _, path in ipairs(DICE_CANDIDATES) do
            local ok, id = pcall(GetFileIDFromPath, path)
            if ok and id then
                dice = path
                break
            end
        end
    end
    return dice
end

-- Item quality colors (the game's table if it has one).
local QUALITY = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 },
    [1] = { r = 1, g = 1, b = 1 },
    [2] = { r = 0.12, g = 1, b = 0 },
    [3] = { r = 0, g = 0.44, b = 0.87 },
    [4] = { r = 0.64, g = 0.21, b = 0.93 },
    [5] = { r = 1, g = 0.5, b = 0 },
}
local function QualityColor(q)
    local c = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[q]
    if type(c) == "table" and c.r then return { r = c.r, g = c.g, b = c.b } end
    return QUALITY[q]
end

local function Hex(c)
    return string.format(
        "%02x%02x%02x",
        math.floor(c.r * 255 + 0.5),
        math.floor(c.g * 255 + 0.5),
        math.floor(c.b * 255 + 0.5)
    )
end

local rolls = {} -- rollID -> { started, total, name, count, quality, rolled }

local function Num(v) return type(v) == "number" and not IsSecret(v) and v or nil end

-- Seconds left on a roll.
local function TimeLeft(id, r, now)
    local ms = GetLootRollTimeLeft and Num(SafeCall(GetLootRollTimeLeft, id))
    if ms then return math.max(0, ms / 1000) end
    return math.max(0, r.started + r.total - now)
end

---------------------------------------------------------------------------
-- The animation: dice
---------------------------------------------------------------------------
-- With lootFx on, two dice sit on the "table" just under the ring. Before you roll they
-- rattle and now and then hop, shaking harder (with a red glow under them) once it's into
-- the warning time. When you roll they're tossed up, tumble with their faces flicking and
-- bounce to a stop on their numbers, with a glint. For rare items and better, a few sparkles
-- in the item's quality color twinkle round the ring. Worked out from the time, so edit
-- mode's sample plays it too.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DOT = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GLOW = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR = "Interface\\Cooldown\\star4"
local TUMBLE = 1.1 -- seconds the toss takes to settle
local PIPS = { -- face -> pip spots on a 3x3 grid (-1..1)
    [1] = { { 0, 0 } },
    [2] = { { -1, 1 }, { 1, -1 } },
    [3] = { { -1, 1 }, { 0, 0 }, { 1, -1 } },
    [4] = { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } },
    [5] = { { -1, 1 }, { 1, 1 }, { 0, 0 }, { -1, -1 }, { 1, -1 } },
    [6] = { { -1, 1 }, { 1, 1 }, { -1, 0 }, { 1, 0 }, { -1, -1 }, { 1, -1 } },
}
local SPARKLES = 6

local function Hash(n)
    local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)
end

local fx -- made on first use
local function Tex(frame, tex, layer, sub, blend)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    if t:SetTexture(tex) == false then t:SetTexture(STAR) end
    if blend then t:SetBlendMode(blend) end
    t:Hide()
    return t
end
local function BuildFx(frame)
    fx = { dice = {}, sparkles = {} }
    fx.glow = Tex(frame, GLOW, "ARTWORK", 1, "ADD")
    for d = 1, 2 do
        local die = { pips = {} }
        die.shadow = Tex(frame, DOT, "ARTWORK", 2)
        die.edge = Tex(frame, WHITE, "ARTWORK", 3)
        die.body = Tex(frame, WHITE, "ARTWORK", 4)
        for p = 1, 6 do
            die.pips[p] = Tex(frame, DOT, "ARTWORK", 5)
        end
        die.glint = Tex(frame, STAR, "ARTWORK", 6, "ADD")
        fx.dice[d] = die
    end
    for i = 1, SPARKLES do
        fx.sparkles[i] = Tex(frame, STAR, "OVERLAY", 6, "ADD")
    end
end
local function HideFx()
    if not fx then return end
    fx.glow:Hide()
    for _, die in ipairs(fx.dice) do
        die.shadow:Hide()
        die.edge:Hide()
        die.body:Hide()
        die.glint:Hide()
        for _, p in ipairs(die.pips) do
            p:Hide()
        end
    end
    for _, s in ipairs(fx.sparkles) do
        s:Hide()
    end
end

local function Put(t, frame, x, y, w, h, rot, r, g, b, a)
    t:ClearAllPoints()
    t:SetPoint("CENTER", frame, "CENTER", x, y)
    t:SetSize(w, h)
    if t.SetRotation then t:SetRotation(rot) end
    t:SetVertexColor(r, g, b)
    t:SetAlpha(math.max(0, math.min(1, a)))
    t:Show()
end

-- One die at (x, y), `size` across, turned by rot, showing `face`.
local function DrawDie(frame, die, x, y, floorY, size, rot, face, a)
    local lift = math.max(0, y - floorY)
    Put(
        die.shadow,
        frame,
        x,
        floorY - size * 0.45,
        size * (1.1 - math.min(0.5, lift / (size * 4))),
        size * 0.35,
        0,
        0,
        0,
        0,
        0.45 * a * (1 - math.min(0.7, lift / (size * 3)))
    )
    Put(die.edge, frame, x, y, size * 1.12, size * 1.12, rot, 0.15, 0.12, 0.10, a)
    Put(die.body, frame, x, y, size, size, rot, 0.96, 0.93, 0.85, a)
    local spots = PIPS[face] or PIPS[1]
    local cs, sn = math.cos(rot), math.sin(rot)
    for i, p in ipairs(die.pips) do
        local spot = spots[i]
        if spot then
            local px, py = spot[1] * size * 0.27, spot[2] * size * 0.27
            local red = face == 1 -- a one's single pip is red, like real dice
            Put(
                p,
                frame,
                x + px * cs - py * sn,
                y + px * sn + py * cs,
                size * (red and 0.3 or 0.2),
                size * (red and 0.3 or 0.2),
                0,
                red and 0.8 or 0.12,
                red and 0.1 or 0.1,
                red and 0.1 or 0.1,
                a
            )
        else
            p:Hide()
        end
    end
end

local function DrawLootFx(st, frame, geom)
    if not (st and st.lootFx) or not geom or geom.R <= 0 then return HideFx() end
    if not fx then BuildFx(frame) end
    local now = GetTime()
    local R, T = geom.R, math.max(3, geom.T)
    local size = math.max(9, R * 0.26)
    local floorY = -(R + T / 2 + size * 0.75) -- the table, just under the ring
    local seed = st.lootSeed or 1
    local age = st.rolledAt and now - st.rolledAt -- since you rolled
    if age and age < 0 then age = nil end

    -- A red glow on the table while time's running out (not once you've rolled).
    if st.lootWarn and not age then
        local pulse = 0.5 + 0.5 * math.sin(now * 10)
        Put(fx.glow, frame, 0, floorY, size * 5, size * 2.2, 0, 1, 0.25, 0.2, 0.35 + 0.35 * pulse)
    else
        fx.glow:Hide()
    end

    for d, die in ipairs(fx.dice) do
        local side = d == 1 and -1 or 1
        local restX = side * size * 0.8
        local finalFace = 1 + math.floor(Hash(seed * 7 + d) * 6)
        local x, y, rot, face = restX, floorY, side * 0.12 + (Hash(seed + d * 3) - 0.5) * 0.3, finalFace
        if age and age < TUMBLE then
            -- Tossed: up and over from the other side, bouncing lower each time, spinning down.
            local t = age / TUMBLE
            local bounce = math.abs(math.cos(math.pi * 2.5 * t)) * (1 - t) ^ 2
            x = restX - side * size * 1.6 * (1 - t) ^ 2
            y = floorY + bounce * size * 3.2
            rot = rot + side * (1 - t) ^ 2 * 14
            face = t < 0.85 and (1 + math.floor(Hash(math.floor(age / 0.07) * 13 + d) * 6)) or finalFace
        elseif not age then
            -- Waiting: a rattle, and a little hop every so often (harder near the end).
            local hard = st.lootWarn and 2.2 or 1
            local period = st.lootWarn and 0.6 or 1.6
            local h = ((now + d * 0.23) % period) / period
            local hop = h < 0.18 and math.sin(math.pi * h / 0.18) or 0
            y = floorY + hop * size * 0.5 * hard
            rot = rot + math.sin(now * 21 + d * 2) * 0.05 * hard + hop * side * 0.6
            x = x + math.sin(now * 17 + d) * size * 0.04 * hard
            face = 1 + math.floor(Hash(math.floor((now + d * 0.23) / period) * 5 + d + seed) * 6) -- turns over each hop
        end
        DrawDie(frame, die, x, y, floorY, size, rot, face, 1)
        -- A glint as they settle.
        local g = age and (age - TUMBLE * 0.85) / 0.5
        if g and g > 0 and g < 1 then
            Put(
                die.glint,
                frame,
                x + size * 0.3,
                y + size * 0.3,
                size * 1.4 * (1 - g * 0.5),
                size * 1.4 * (1 - g * 0.5),
                g * 3,
                1,
                1,
                0.9,
                1 - g
            )
        else
            die.glint:Hide()
        end
    end

    -- Sparkles for rare and better: twinkling at points round the ring in the quality color.
    local q = st.lootQualityColor
    for i, s in ipairs(fx.sparkles) do
        if q then
            local cyc = math.floor(now / 1.3 + Hash(i))
            local life = (now / 1.3 + Hash(i)) % 1
            local x, y = ns.RingPoint(geom, Hash(cyc * 11 + i))
            local tw = math.sin(math.pi * life)
            Put(
                s,
                frame,
                x,
                y,
                T * 2.2 * tw,
                T * 2.2 * tw,
                life * 2,
                q.r + (1 - q.r) * 0.4,
                q.g + (1 - q.g) * 0.4,
                q.b + (1 - q.b) * 0.4,
                tw
            )
        else
            s:Hide()
        end
    end
end

local function State(r, left, more)
    local c = db.lootColors
    local q = db.lootQuality and r.quality and QualityColor(r.quality)
    local warn = left <= (db.lootWarn or 10)
    local color = warn and c.warn or q or c.fill
    local name = r.name or "Loot roll"
    if r.count and r.count > 1 then name = name .. " x" .. r.count end
    if q then name = "|cff" .. Hex(q) .. name .. "|r" end
    local label
    if r.rolled then
        label = "Rolled " .. r.rolled
    else
        label = "Need or Greed?"
    end
    if more > 0 then label = label .. "  +" .. more end
    return {
        title = name,
        value = left >= 60 and FormatTime(left) or tostring(math.ceil(left)),
        label = label,
        labelColor = warn and c.warn or (r.rolled and c.rolled) or nil,
        frac = r.total > 0 and math.max(0, math.min(1, left / r.total)) or 0,
        color = color,
        icon = DiceTexture(),
        iconColor = color,
        hold = db.lootHold or 0.5,
        -- The dice animation (above).
        lootFx = db.lootFx or nil,
        lootWarn = warn and not r.rolled,
        rolledAt = r.rolledAt,
        lootSeed = r.seed,
        lootQualityColor = r.quality and r.quality >= 3 and QualityColor(r.quality) or nil,
    }
end

local lootRing = CreateLiveRing({
    key = "loot",
    read = function(now)
        now = now or GetTime()
        local list = {}
        for id, r in pairs(rolls) do
            local left = TimeLeft(id, r, now)
            if left <= 0 and now > r.started + r.total + 2 then
                rolls[id] = nil -- the game never said it ended: it's over by now
            elseif r.rolled ~= "Pass" then
                table.insert(list, { id = id, r = r, left = left })
            end
        end
        if #list == 0 then return nil end
        -- Rolls you still have to answer first, then the least time left.
        table.sort(list, function(a, b)
            if (a.r.rolled == nil) ~= (b.r.rolled == nil) then return a.r.rolled == nil end
            if a.left ~= b.left then return a.left < b.left end
            return a.id < b.id
        end)
        return State(list[1].r, list[1].left, #list - 1)
    end,
    decorate = function(st, frame, geom) DrawLootFx(st, frame, geom) end,
    sample = function(t)
        -- An epic up for grabs: 60 s draining fast, rolled Need halfway, into the warning.
        local cycle = t % 14
        local left = math.max(0, 60 - cycle * 4.6)
        local r = {
            name = "Ironfoe",
            quality = 4,
            total = 60,
            rolled = cycle > 6 and "Need" or nil,
            seed = math.floor(t / 14) + 3,
        }
        -- When it was rolled, on the real clock, rounded so it holds still from frame to frame.
        if r.rolled then r.rolledAt = math.floor((GetTime() - (cycle - 6)) * 20 + 0.5) / 20 end
        return State(r, left, cycle < 3 and 1 or 0)
    end,
})

-- A roll starts: remember its time limit and the item.
local function StartRoll(id, ms)
    id = Num(id)
    if not id then return end
    local total = Num(ms) and ms / 1000 or nil
    if not total and GetLootRollTimeLeft then
        local left = Num(SafeCall(GetLootRollTimeLeft, id))
        total = left and left / 1000
    end
    local _, name, count, quality = SafeCall(GetLootRollItemInfo, id)
    rolls[id] = {
        started = GetTime(),
        total = total or 60,
        name = Clean(name),
        count = Num(count),
        quality = Num(quality),
        seed = id,
    }
end

-- You rolled (the game's Need / Greed / Pass buttons call RollOnLoot).
local function OnRoll(id, rollType)
    local r = rolls[Num(id) or -1]
    if r then
        r.rolled, r.rolledAt = ROLL_NAMES[Num(rollType) or -1] or "?", GetTime()
    end
end
if hooksecurefunc and RollOnLoot then hooksecurefunc("RollOnLoot", OnRoll) end

ns.Listen({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS" }, function(event, id, ms)
    if not CircletDB then return end
    if event == "START_LOOT_ROLL" then
        if db.lootEnabled then StartRoll(id, ms) end
    elseif event == "CANCEL_LOOT_ROLL" then
        rolls[Num(id) or -1] = nil
    else
        for k in pairs(rolls) do
            rolls[k] = nil
        end
    end
end)

local function PreviewLootRing() lootRing.Preview(14) end

-- Shared with the files loaded after this one.
ns.lootRing = lootRing
ns.PreviewLootRing = PreviewLootRing
ns.LootDiceTexture = DiceTexture
ns.LootFxParts = function() return fx end -- for the tests

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "loot",
    name = "Loot roll",
    order = 14.7,
    since = "1.2.0",
    alwaysInCombat = true, -- rolls are short and come up in fights: never faded out
    iconBg = true, -- "Icon as background": the dice fills the ring's middle (Core/Settings.lua, UI/Options/Kit.lua)
    ring = lootRing,
    preview = PreviewLootRing,
    slash = { "loot", "roll" },
    help = "preview the loot roll ring",
    toggle = { "Loot roll ring", "Counts down the time left to roll Need or Greed on an item." },
    defaults = {
        -- Loot roll ring: time left to roll on an item. Right of the target cast ring.
        lootEnabled = true,
        lootWarn = 10, -- seconds left when it turns the warning color
        lootQuality = true, -- the ring (and item name) in the item's quality color
        lootFx = true, -- the dice under the ring, and sparkles for rare and better
        lootSize = 100,
        lootThickness = 10,
        lootOpacity = 100,
        lootX = 170,
        lootFromTop = 385,
        lootHold = 0.5,
        lootStyle = "smooth",
        lootBorder = 2,
        lootColors = {
            fill = { r = 0.95, g = 0.80, b = 0.30 }, -- with quality colors off
            warn = { r = 1.00, g = 0.30, b = 0.25 },
            rolled = { r = 0.55, g = 0.85, b = 0.55 },
        },
    },
    page = {
        folder = "group",
        order = 1,
        build = function(O)
            local Toggle, Range, Color, Box = O.Toggle, O.Range, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(
                10.9,
                "Loot rolls",
                "Loot Roll Ring",
                "Up while an item is being rolled for: the ring drains over the time left to roll, with the Need "
                    .. "roll's dice (as a badge, or behind the text with Icon as background), the item's name and the seconds left, turning the warning color near the end. Once you roll "
                    .. "it shows your pick; pass and that roll drops off. With several rolls, the ones you still have to "
                    .. "answer come first.",
                MergeTop(
                    TopRow(
                        "loot",
                        "loot roll ring",
                        ns.PreviewLootRing,
                        "Show a sample roll counting down. Also /circ loot."
                    ),
                    {
                        general = Box(2, "General", {
                            enabled = Toggle(1, "lootEnabled", "Show loot roll ring", "Count down loot rolls."),
                            quality = Toggle(
                                2,
                                "lootQuality",
                                "Item quality colors",
                                "Color the ring and the item's name by its quality (green, blue, purple...)."
                            ),
                            warn = Range(
                                3,
                                "lootWarn",
                                "Warn at (seconds left)",
                                3,
                                30,
                                1,
                                "Below this much time the ring turns the warning color."
                            ),
                            fx = Toggle(
                                4,
                                "lootFx",
                                "Animations",
                                "Two dice under the ring rattle and hop while you decide (harder, with a red glow, when "
                                    .. "time's nearly up), then tumble and land on their numbers when you roll. Rare items "
                                    .. "and better get sparkles in their quality color round the ring."
                            ),
                        }),
                        colors = Box(3, "Colors", {
                            fill = Color(
                                1,
                                "lootColors",
                                "fill",
                                "Time left",
                                "Ring color with item quality colors off."
                            ),
                            warn = Color(2, "lootColors", "warn", "Running out", "Ring and label color near the end."),
                            rolled = Color(3, "lootColors", "rolled", "Rolled", "Label color once you've rolled."),
                        }),
                        size = SizeBox(4, "loot", "loot roll ring", "Offset from the center of the screen."),
                    }
                )
            )
            tab.args.size.args.hold.desc = "How long the ring stays after the last roll ends."
            return tab
        end,
    },
})
