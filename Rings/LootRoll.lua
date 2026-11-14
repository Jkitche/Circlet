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
            if ok and id then dice = path break end
        end
    end
    return dice
end

-- Item quality colors (the game's table if it has one).
local QUALITY = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 },
    [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 },
    [4] = { r = 0.64, g = 0.21, b = 0.93 }, [5] = { r = 1, g = 0.5, b = 0 },
}
local function QualityColor(q)
    local c = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[q]
    if type(c) == "table" and c.r then return { r = c.r, g = c.g, b = c.b } end
    return QUALITY[q]
end

local function Hex(c)
    return string.format("%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

local rolls = {} -- rollID -> { started, total, name, count, quality, rolled }

local function Num(v) return type(v) == "number" and not IsSecret(v) and v or nil end

-- Seconds left on a roll.
local function TimeLeft(id, r, now)
    local ms = GetLootRollTimeLeft and Num(SafeCall(GetLootRollTimeLeft, id))
    if ms then return math.max(0, ms / 1000) end
    return math.max(0, r.started + r.total - now)
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
    if r.rolled then label = "Rolled " .. r.rolled else label = "Need or Greed?" end
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
    sample = function(t)
        -- An epic up for grabs: 60 s draining fast, rolled Need halfway, into the warning.
        local cycle = t % 14
        local left = math.max(0, 60 - cycle * 4.6)
        local r = { name = "Ironfoe", quality = 4, total = 60, rolled = cycle > 6 and "Need" or nil }
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
    rolls[id] = { started = GetTime(), total = total or 60, name = Clean(name),
                  count = Num(count), quality = Num(quality) }
end

-- You rolled (the game's Need / Greed / Pass buttons call RollOnLoot).
local function OnRoll(id, rollType)
    local r = rolls[Num(id) or -1]
    if r then r.rolled = ROLL_NAMES[Num(rollType) or -1] or "?" end
end
if hooksecurefunc and RollOnLoot then hooksecurefunc("RollOnLoot", OnRoll) end

ns.Listen({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS" }, function(event, id, ms)
    if not CircletDB then return end
    if event == "START_LOOT_ROLL" then
        if db.lootEnabled then StartRoll(id, ms) end
    elseif event == "CANCEL_LOOT_ROLL" then
        rolls[Num(id) or -1] = nil
    else
        for k in pairs(rolls) do rolls[k] = nil end
    end
end)

local function PreviewLootRing() lootRing.Preview(14) end

-- Shared with the files loaded after this one.
ns.lootRing = lootRing
ns.PreviewLootRing = PreviewLootRing
ns.LootDiceTexture = DiceTexture

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "loot", name = "Loot roll", order = 14.7,
    alwaysInCombat = true, -- rolls are short and come up in fights: never faded out
    iconBg = true, -- "Icon as background": the dice fills the ring's middle (Core/Settings.lua, UI/OptionsKit.lua)
    ring = lootRing,
    preview = PreviewLootRing, slash = { "loot", "roll" }, help = "preview the loot roll ring",
    toggle = { "Loot roll ring", "Counts down the time left to roll Need or Greed on an item." },
    defaults = {
        -- Loot roll ring: time left to roll on an item. Right of the target cast ring.
        lootEnabled   = true,
        lootWarn      = 10,   -- seconds left when it turns the warning color
        lootQuality   = true, -- the ring (and item name) in the item's quality color
        lootSize      = 100,
        lootThickness = 10,
        lootOpacity   = 100,
        lootX         = 170,
        lootFromTop   = 385,
        lootHold      = 0.5,
        lootStyle     = "smooth",
        lootBorder    = 2,
        lootColors = {
            fill   = { r = 0.95, g = 0.80, b = 0.30 }, -- with quality colors off
            warn   = { r = 1.00, g = 0.30, b = 0.25 },
            rolled = { r = 0.55, g = 0.85, b = 0.55 },
        },
    },
    page = { folder = "status", order = 4.8, build = function(O)
            local Toggle, Range, Color, Box = O.Toggle, O.Range, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(10.9, "Loot rolls", "Loot Roll Ring",
                "Up while an item is being rolled for: the ring drains over the time left to roll, with the Need "
                .. "roll's dice (as a badge, or behind the text with Icon as background), the item's name and the seconds left, turning the warning color near the end. Once you roll "
                .. "it shows your pick; pass and that roll drops off. With several rolls, the ones you still have to "
                .. "answer come first.",
                MergeTop(TopRow("loot", "loot roll ring", ns.PreviewLootRing,
                    "Show a sample roll counting down. Also /circ loot."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "lootEnabled", "Show loot roll ring", "Count down loot rolls."),
                        quality = Toggle(2, "lootQuality", "Item quality colors",
                            "Color the ring and the item's name by its quality (green, blue, purple...)."),
                        warn = Range(3, "lootWarn", "Warn at (seconds left)", 3, 30, 1,
                            "Below this much time the ring turns the warning color."),
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "lootColors", "fill", "Time left", "Ring color with item quality colors off."),
                        warn = Color(2, "lootColors", "warn", "Running out", "Ring and label color near the end."),
                        rolled = Color(3, "lootColors", "rolled", "Rolled", "Label color once you've rolled."),
                    }),
                    size = SizeBox(4, "loot", "loot roll ring", "Offset from the center of the screen."),
                }))
            tab.args.size.args.hold.desc = "How long the ring stays after the last roll ends."
            return tab
        end },
})
