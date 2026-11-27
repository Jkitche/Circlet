-- Circlet: Health ring effects about the target: skinnable or gatherable, quest target, out of range, lootable, its faction, and your stance.
local _, ns = ...

local db, SafeCall, Clean, CleanNumber, IsSecret = ns.db, ns.SafeCall, ns.Clean, ns.CleanNumber, ns.IsSecret
local FX = ns.HealthFx
local SOFT = FX.SOFT
local DISC = FX.DISC
local BadgeAngle = FX.BadgeAngle
local Tex = FX.Tex
local At = FX.At
local Polar = FX.Polar

-- Skinnable. The game doesn't tell addons whether a creature can be skinned; the only word is
-- the "Skinnable" line on a looted corpse's tooltip (or "Requires Herbalism / Mining /
-- Engineering"), colored by how hard it is for you. So a dead target's tooltip is read (twice
-- a second while it's dead), and each kind of creature (by its NPC id) seen skinnable is
-- remembered (skinKnown), so the next live one, or a corpse not looted yet, gets a faint badge.
-- Each kind shows the cursor the game gives you over such a corpse (the knife, the herb, the
-- pick), cropped to leave out the pointer arrow in its top-left corner; the icon is the
-- fallback if this client has no such cursor file.
local CURSOR_CROP = 0.3 -- the arrow's share of the cursor image, from its top-left corner
local SKIN_KINDS = {
    {
        kind = "leather",
        text = UNIT_SKINNABLE_LEATHER or "Skinnable",
        icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
        cursor = "Interface\\Cursor\\Skin",
    },
    {
        kind = "herb",
        text = UNIT_SKINNABLE_HERB or "Requires Herbalism",
        icon = "Interface\\Icons\\INV_Misc_Flower_02",
        cursor = "Interface\\Cursor\\GatherHerbs",
    },
    {
        kind = "rock",
        text = UNIT_SKINNABLE_ROCK or "Requires Mining",
        icon = "Interface\\Icons\\Trade_Mining",
        cursor = "Interface\\Cursor\\Mine",
    },
    {
        kind = "bolts",
        text = UNIT_SKINNABLE_BOLTS or "Requires Engineering",
        icon = "Interface\\Icons\\Trade_Engineering",
    },
}
local SKIN_BY = {}
for _, k in ipairs(SKIN_KINDS) do
    SKIN_BY[k.kind] = k
end

-- Whether you can gather it yourself: you need the profession (Skinning 393, Herbalism 182,
-- Mining 186, Engineering 202; looked up by ID, else by name in your skills list, as Forever
-- may number them its own way), and the corpse's tooltip line turns red when it's beyond your
-- skill. If the client won't say what skills you have, it counts as yes.
local SKILL_OF = {
    leather = { 393, "Skinning" },
    herb = { 182, "Herbalism" },
    rock = { 186, "Mining" },
    bolts = { 202, "Engineering" },
}
local skillCache, skillAt = {}, -math.huge
local function HasSkill(kind, now)
    if now - skillAt > 2 then
        skillCache, skillAt = {}, now
    end
    if skillCache[kind] ~= nil then return skillCache[kind] end
    local s, has = SKILL_OF[kind], nil
    local api = C_SkillInfo
    if s and api then
        if api.GetSkillLineInfoByID then
            local ok, info = pcall(api.GetSkillLineInfoByID, s[1])
            if ok and type(info) == "table" then
                local rank = Clean(info.rank)
                if type(rank) == "number" and rank > 0 then has = true end
            end
        end
        if not has and api.GetNumSkillLines and api.GetSkillLineInfo then
            has = false
            for i = 1, (CleanNumber(SafeCall(api.GetNumSkillLines)) or 0) do
                local info = SafeCall(api.GetSkillLineInfo, i)
                if type(info) == "table" and Clean(info.name) == s[2] and not info.isHeader then
                    local rank = Clean(info.rank)
                    has = type(rank) ~= "number" or rank > 0
                    break
                end
            end
        end
    end
    if has == nil then has = true end
    skillCache[kind] = has
    return has
end

local function TooHard(color) return color and color[1] > 0.9 and color[2] < 0.35 and color[3] < 0.35 end

local function NpcId(unit)
    local guid = Clean(SafeCall(UnitGUID, unit))
    if type(guid) ~= "string" then return nil end
    return tonumber(
        guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)") or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    ),
        guid
end

-- The corpse's tooltip line: kind and its color, or nil.
local function SkinFromTooltip(unit)
    local get = C_TooltipInfo and C_TooltipInfo.GetUnit
    local data = get and SafeCall(get, unit)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        local text = Clean(line.leftText)
        if type(text) == "string" then
            for _, k in ipairs(SKIN_KINDS) do
                if text == k.text then
                    local c = line.leftColor
                    local r, g, b = c and Clean(c.r), c and Clean(c.g), c and Clean(c.b)
                    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
                        r, g, b = 1, 0.82, 0
                    end
                    return k.kind, { r, g, b }
                end
            end
        end
    end
end

-- A corpse that said so and no longer does has been skinned: no badge on it after that.
local skinSeen = {} -- unit -> { guid, dead, at, kind, color, done }
local function SkinState(unit, dead, now)
    local id, guid = NpcId(unit)
    local s = skinSeen[unit]
    if not s or s.guid ~= guid or s.dead ~= dead then
        s = { guid = guid, dead = dead, at = -math.huge }
        skinSeen[unit] = s
    end
    if dead and now - s.at >= 0.5 then
        s.at = now
        local was = s.kind
        s.kind, s.color = SkinFromTooltip(unit)
        if was and not s.kind then s.done = true end
        if s.kind and id then
            db.skinKnown = db.skinKnown or {}
            db.skinKnown[id] = s.kind
        end
    end
    if s.kind then return s.kind, s.color, true end
    if s.done then return nil end
    local known = id and db.skinKnown and db.skinKnown[id]
    if known then return known, nil, false end
end

local function DrawSkin(key, fx, st, frame, geom, d, now)
    local kind, color, sure
    if st.unit then
        kind, color, sure = SkinState(st.unit, st.dead and true or false, now)
    else
        kind, color, sure = "leather", { 1, 0.82, 0 }, true -- previews
    end
    local k = kind and SKIN_BY[kind]
    if not k then return end
    local x, y = Polar(BadgeAngle(key, "Skin"), geom.R)
    -- The cursor, if the client has it (SetTexture says so).
    local cur = k.cursor and Tex(fx, "skinCursor", nil, "OVERLAY", 3)
    if cur then
        if cur.skinFile ~= k.cursor then
            cur.skinFile = k.cursor
            cur.skinOk = cur:SetTexture(k.cursor) ~= false
            cur:SetTexCoord(CURSOR_CROP, 1, CURSOR_CROP, 1) -- leave out the arrow
        end
        if not cur.skinOk then
            cur.used = false
            cur = nil
        end
    end
    local icon = not cur and Tex(fx, "skin", k.icon, "OVERLAY", 3)
    if cur then
        icon = cur
    elseif icon.skinFile ~= k.icon then
        icon.skinFile = k.icon
        icon:SetTexture(k.icon)
        -- Crop the icon's border, then mask it round: the game won't set tex coords on a
        -- texture once it has a mask (the mask stays on through later SetTexture calls).
        if not icon.masked then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon.masked = true
            pcall(icon.SetMask, icon, DISC)
        end
    end
    At(icon, frame, x, y, d * (cur and 1.35 or 1.1))
    -- Not one you can gather yourself: grey, no glow.
    local can = not st.unit or (HasSkill(kind, now) and not TooHard(color))
    if not can then
        icon:SetAlpha(sure and 0.85 or 0.45)
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.6, 0.6, 0.6)
    elseif sure then
        icon:SetVertexColor(1, 1, 1)
        icon:SetAlpha(1)
        icon:SetDesaturated(false)
        local glow = Tex(fx, "skinGlow", SOFT, "OVERLAY", 2, true)
        At(glow, frame, x, y, d * 2.2)
        glow:SetVertexColor(color[1], color[2], color[3])
        glow:SetAlpha(0.55 + 0.3 * math.sin(now * 3))
    else
        icon:SetVertexColor(1, 1, 1)
        icon:SetAlpha(0.5)
        icon:SetDesaturated(true)
    end
end
ns.VitalsFxSkinKinds = SKIN_KINDS -- tests

-- Quest target. The game's C_QuestLog.UnitIsRelatedToActiveQuest (what its nameplates use)
-- says whether the unit is part of one of your active quests; the unit's tooltip has the
-- quest's own lines (title, then objectives like "Young Wolf slain: 3/10"), which give the
-- progress, and do as the answer where that function isn't there. Read once a second, and
-- again when your quest log changes.
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local LINE_OBJ = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective) or 8
local LINE_TITLE = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle) or 17

-- From the tooltip: whether it has quest lines, and the first unfinished objective's x/y.
local function QuestFromTooltip(unit)
    local get = C_TooltipInfo and C_TooltipInfo.GetUnit
    local data = get and SafeCall(get, unit)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    local any, progress, done
    for _, line in ipairs(data.lines) do
        local kind = Clean(line.type)
        if kind == LINE_OBJ or kind == LINE_TITLE then
            any = true
            local text = Clean(line.leftText)
            if kind == LINE_OBJ and type(text) == "string" then
                local have, need = text:match("(%d+)%s*/%s*(%d+)")
                have, need = tonumber(have), tonumber(need)
                if have and need then
                    if have < need then
                        progress = progress or (have .. "/" .. need)
                    else
                        done = done or (have .. "/" .. need)
                    end
                end
            end
        end
    end
    return any, progress or done
end

local questSeen = {} -- unit -> { guid, at, on, progress }
local function QuestState(unit, now)
    local guid = Clean(SafeCall(UnitGUID, unit))
    local q = questSeen[unit]
    if not q or q.guid ~= guid then
        q = { guid = guid, at = -math.huge }
        questSeen[unit] = q
    end
    if now - q.at >= 1 then
        q.at = now
        local tipOn, progress = QuestFromTooltip(unit)
        local api = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
        local apiOn = api and Clean(SafeCall(api, unit))
        q.on = (apiOn == true) or tipOn
        q.progress = progress
    end
    return q.on, q.progress
end
ns.Listen({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_WATCH_UPDATE" }, function()
    for _, q in pairs(questSeen) do
        q.at = -math.huge
    end
end)

local function DrawQuest(key, fx, st, frame, geom, d, now)
    local on, progress
    if st.unit then
        on, progress = QuestState(st.unit, now)
    else
        on, progress = true, "3/10"
    end -- previews
    if not on then return end
    local x, y = Polar(BadgeAngle(key, "Quest"), geom.R)
    local icon = Tex(fx, "quest", QUEST_ICON, "OVERLAY", 3)
    At(icon, frame, x, y + d * 0.1, d * 1.1)
    icon:SetAlpha(1)
    local glow = Tex(fx, "questGlow", SOFT, "OVERLAY", 2, true)
    At(glow, frame, x, y + d * 0.1, d * 2)
    glow:SetVertexColor(1, 0.85, 0.2)
    glow:SetAlpha(0.35 + 0.2 * math.sin(now * 2.5))
    if progress then
        local fs = fx.questText
        if not fs then
            fs = fx.root:CreateFontString(nil, "OVERLAY")
            fs:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
            fx.questText = fs
        end
        local px = math.max(8, math.floor(d * 0.55 + 0.5))
        if fs.px ~= px then
            fs.px = px
            fs:SetFont(STANDARD_TEXT_FONT, px, "OUTLINE")
        end
        fs:SetText(progress)
        fs:SetTextColor(1, 0.85, 0.2)
        fs:ClearAllPoints()
        fs:SetPoint("TOP", icon, "BOTTOM", 0, 1)
        fs:Show()
        fx.questTextUsed = true
    end
end
ns.VitalsFxQuest = QuestFromTooltip -- tests

-- A round icon: cropped first, then masked (the game won't crop a masked texture).
local function RoundIcon(fx, name, file, layer, sub)
    local t = Tex(fx, name, file, layer or "OVERLAY", sub or 3)
    if t.iconFile ~= file then
        t.iconFile = file
        t:SetTexture(file)
        if not t.masked then
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            t.masked = true
            pcall(t.SetMask, t, DISC)
        end
    end
    return t
end

-- Range: whether your class's main attacks reach the target (C_Spell.IsSpellInRange, which the
-- game doesn't hide), checked five times a second. In range if any of them reach (a hunter's
-- Auto Shot or Raptor Strike, so the dead zone between doesn't count as out); out if none do;
-- left alone if none can be checked (a friendly target, a class with none known yet). The dim
-- is the ring's own fade (ns.SetRingDim), so it eases and goes with its opacity setting.
local RANGE_SPELLS = {
    MAGE = { 133, 116, 5143 }, -- Fireball, Frostbolt, Arcane Missiles
    WARLOCK = { 686, 172 }, -- Shadow Bolt, Corruption
    PRIEST = { 585, 589, 8092 }, -- Smite, Shadow Word: Pain, Mind Blast
    DRUID = { 5176, 8921 }, -- Wrath, Moonfire
    SHAMAN = { 403, 8042 }, -- Lightning Bolt, Earth Shock
    HUNTER = { 75, 3044, 2973 }, -- Auto Shot, Arcane Shot, Raptor Strike
    ROGUE = { 1752, 2098 }, -- Sinister Strike, Eviscerate
    WARRIOR = { 78, 772 }, -- Heroic Strike, Rend
    PALADIN = { 20271, 35395 }, -- Judgement, Crusader Strike
    DEATHKNIGHT = { 45477, 49998 }, -- Icy Touch, Death Strike
}
local function Knows(id)
    local f = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsPlayerSpell or IsSpellKnown
    return f and Clean(SafeCall(f, id)) and true or false
end
local function InRange(id, unit)
    if C_Spell and C_Spell.IsSpellInRange then
        local v = Clean(SafeCall(C_Spell.IsSpellInRange, id, unit))
        if v == nil or IsSecret(v) then return nil end
        return v == true or v == 1
    end
    if IsSpellInRange and GetSpellInfo then
        local name = Clean(SafeCall(GetSpellInfo, id))
        local v = name and Clean(SafeCall(IsSpellInRange, name, unit))
        if v == nil or IsSecret(v) then return nil end
        return v == 1 or v == true
    end
end
local rangeAt, rangeOut = -math.huge, nil
local function DrawRange(key, fx, st, frame, geom, d, now)
    local out = false
    if st.unit and not st.dead and Clean(SafeCall(UnitCanAttack, "player", st.unit)) then
        if now - rangeAt >= 0.2 then
            rangeAt = now
            local _, class = UnitClass("player")
            local any, reach = false, false
            for _, id in ipairs(RANGE_SPELLS[Clean(class) or ""] or {}) do
                if Knows(id) then
                    local v = InRange(id, st.unit)
                    if v ~= nil then
                        any = true
                        if v then
                            reach = true
                            break
                        end
                    end
                end
            end
            rangeOut = any and not reach
        end
        out = rangeOut and true or false
    end
    if ns.SetRingDim then ns.SetRingDim(key, out and 0.4 or 1) end
end
ns.VitalsRangeSpells = RANGE_SPELLS -- tests
ns.Listen({ "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED" }, function() rangeAt = -math.huge end)

-- Loot: gold glints running round a corpse that still has loot for you (CanLootUnit), and a
-- coin at the right. Checked twice a second.
local lootAt, lootHas, lootGuid = -math.huge, false, nil
local function DrawLoot(key, fx, st, frame, geom, d, now)
    local has
    if not st.unit then
        has = false -- previews: nothing (they're alive)
    elseif st.dead then
        local guid = Clean(SafeCall(UnitGUID, st.unit))
        if guid ~= lootGuid or now - lootAt >= 0.5 then
            lootGuid, lootAt = guid, now
            local h = guid and CanLootUnit and Clean(SafeCall(CanLootUnit, guid))
            lootHas = h == true
        end
        has = lootHas
    end
    if not has then return end
    local coin = RoundIcon(fx, "loot", "Interface\\Icons\\INV_Misc_Coin_01")
    local x, y = Polar(BadgeAngle(key, "Loot"), geom.R)
    At(coin, frame, x, y, d * 1.05)
    coin:SetAlpha(1)
    local halo = Tex(fx, "lootGlow", SOFT, "OVERLAY", 2, true)
    At(halo, frame, x, y, d * 2)
    halo:SetVertexColor(1, 0.8, 0.25)
    halo:SetAlpha(0.4 + 0.25 * math.sin(now * 3))
    for i = 1, 3 do
        local g = Tex(fx, "lootGlint" .. i, SOFT, "OVERLAY", 4, true)
        local deg = (now * 70 + i * 120) % 360
        local gx, gy = Polar(deg, geom.R)
        local tw = 0.5 + 0.5 * math.sin(now * 6 + i * 2)
        At(g, frame, gx, gy, geom.T * (1.2 + tw))
        g:SetVertexColor(1, 0.85, 0.35)
        g:SetAlpha(0.35 + 0.5 * tw)
    end
end

-- Stance: your stance, form, aura or stealth (the game's stance bar: GetShapeshiftForm) as a
-- round badge at the bottom right of your ring. Previews show Battle Stance.
local function DrawStance(key, fx, st, frame, geom, d, now)
    local icon
    if st.unit then
        local idx = CleanNumber(SafeCall(GetShapeshiftForm))
        if idx and idx > 0 and GetShapeshiftFormInfo then icon = Clean(SafeCall(GetShapeshiftFormInfo, idx)) end
    else
        icon = "Interface\\Icons\\Ability_Warrior_OffensiveStance"
    end
    if not icon or IsSecret(icon) then return end
    local x, y = Polar(BadgeAngle(key, "Stance"), geom.R)
    local back = Tex(fx, "stanceBack", DISC, "OVERLAY", 2)
    At(back, frame, x, y, d * 1.25)
    back:SetVertexColor(0, 0, 0)
    back:SetAlpha(0.85)
    local t = RoundIcon(fx, "stance", icon)
    At(t, frame, x, y, d * 1.05)
    t:SetAlpha(1)
end

-- Faction: when your target is a player of the other faction, its crest (the game's own, as on
-- the target frame's PvP flag: the Alliance lion, the Horde emblem) on its own, at the left of
-- the target ring. The game may hide the faction in combat; the last one read for this
-- target is kept until you change targets. Previews show the other faction to yours. The
-- crest sits in the top left of its texture: crop holds where.
local FACTIONS = {
    Alliance = { icon = "Interface\\TargetingFrame\\UI-PVP-Alliance", crop = { 0.07, 0.58, 0.06, 0.57 } },
    Horde = { icon = "Interface\\TargetingFrame\\UI-PVP-Horde", crop = { 0.08, 0.58, 0.045, 0.545 } },
}
local OTHER = { Alliance = "Horde", Horde = "Alliance" }
local targetFaction -- the faction last read for the current target (false: not a player)
ns.Listen({ "PLAYER_TARGET_CHANGED" }, function() targetFaction = nil end)

local function EnemyFaction(st)
    local mine = Clean(SafeCall(UnitFactionGroup, "player"))
    if not FACTIONS[mine] then return nil end
    if not st.unit then return OTHER[mine] end -- previews
    local isPlayer = Clean(SafeCall(UnitIsPlayer, st.unit))
    local theirs = isPlayer and Clean(SafeCall(UnitFactionGroup, st.unit))
    if isPlayer == false then
        targetFaction = false
    elseif FACTIONS[theirs] then
        targetFaction = theirs
    end
    -- nil (hidden right now): keep what was read for this target
    if targetFaction and targetFaction ~= mine then return targetFaction end
end

local function DrawFaction(key, fx, st, frame, geom, d, now)
    local faction = EnemyFaction(st)
    local f = faction and FACTIONS[faction]
    if not f then return end
    local x, y = Polar(BadgeAngle(key, "Faction"), geom.R)
    local t = Tex(fx, "faction", f.icon, "OVERLAY", 3)
    if t.faction ~= faction then
        t.faction = faction
        t:SetTexture(f.icon)
        t:SetTexCoord(unpack(f.crop))
    end
    At(t, frame, x, y, d * 1.4)
    t:SetAlpha(1)
end
ns.VitalsFxFaction = EnemyFaction -- tests

-- For the files loaded after this one.
FX.DrawSkin = DrawSkin
FX.DrawQuest = DrawQuest
FX.DrawRange = DrawRange
FX.DrawLoot = DrawLoot
FX.DrawStance = DrawStance
FX.DrawFaction = DrawFaction
