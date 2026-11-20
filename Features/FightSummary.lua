-- Circlet: Fight summary: a pane after each fight with what happened in it.
local ADDON_NAME, ns = ...

local db, Print, IsSecret, Clean, CleanNumber, SafeCall = ns.db, ns.Print, ns.IsSecret, ns.Clean, ns.CleanNumber, ns.SafeCall

---------------------------------------------------------------------------
-- Fight summary
---------------------------------------------------------------------------
-- When a fight ends, a small pane shows what happened in it, then fades away (it stays while
-- the mouse is over it; click the X to close it, drag it to move it):
--   * damage you dealt, your DPS and the damage you took, big across the top;
--   * how long it lasted, who you fought, XP gained and kills, your healing, your top
--     ability, what you avoided (dodges, parries, blocks, misses, absorbs, resists) out of
--     the attacks against you, crushing blows and crits you took, crits on your target,
--     interrupts and dispels, and how many spells you cast.
--
-- Where the numbers come from, since this client keeps the combat log from addons:
--   * damage, DPS, damage taken, healing, interrupts, dispels and the top ability: the
--     game's own damage meter (C_DamageMeter), your entry in the fight's session. Its numbers
--     are hidden in combat but readable once it's over; if one is still hidden it's shown as
--     it is (the game draws it) rather than worked with.
--   * what you avoided and the crits: UNIT_COMBAT, whose kind of hit (WOUND, DODGE, PARRY...)
--     and flag (CRITICAL, CRUSHING) are readable though the amounts aren't. So mitigation is
--     counted in attacks, not in damage prevented.
--   * XP from your XP before and after; kills from the "dies, you gain ... experience"
--     messages; fight time from entering and leaving combat.
-- Fights shorter than the minimum (default 4 seconds) don't get a pane.

local AVOID = { DODGE = "dodge", PARRY = "parry", BLOCK = "block", MISS = "miss", ABSORB = "absorb",
                RESIST = "resist", IMMUNE = "immune", DEFLECT = "deflect", EVADE = "evade" }
local AVOID_ORDER = { "dodge", "parry", "block", "miss", "absorb", "resist", "immune", "deflect", "evade" }
local PLURAL = { dodge = "dodges", parry = "parries", block = "blocks", miss = "misses", absorb = "absorbs",
                 resist = "resists", immune = "immune", deflect = "deflects", evade = "evades" }
local NOT_CASTS = { [75] = true, [5019] = true, [2764] = true, [6603] = true } -- auto attacks, not casts
local METER = { done = 0, dps = 1, healing = 2, interrupts = 5, dispels = 6, taken = 7 }
local W, PAD, ROW = 300, 14, 17

local fight      -- the fight under way
local last       -- the last fight's summary (shown again by /circ fight)

local function Now() return GetTime() end

local function XPNow()
    return CleanNumber(SafeCall(UnitXP, "player")) or 0, CleanNumber(SafeCall(UnitXPMax, "player")) or 0,
        CleanNumber(SafeCall(UnitLevel, "player")) or 0
end

local function TargetName()
    local n = Clean(SafeCall(UnitName, "target"))
    if type(n) == "string" and n ~= "" and SafeCall(UnitCanAttack, "player", "target") then return n end
end

---------------------------------------------------------------------------
-- During the fight
---------------------------------------------------------------------------
local function StartFight()
    local xp, max, level = XPNow()
    fight = { start = Now(), xp = xp, xpMax = max, level = level, avoided = {}, attacks = 0, crushing = 0,
              critsTaken = 0, critsDealt = 0, casts = 0, kills = 0, foes = {}, foeList = {} }
    local n = TargetName()
    if n then fight.foes[n] = true; table.insert(fight.foeList, n) end
end

local function Foe()
    local n = fight and TargetName()
    if n and not fight.foes[n] then fight.foes[n] = true; table.insert(fight.foeList, n) end
end

ns.Listen({ "PLAYER_REGEN_DISABLED" }, StartFight)
ns.Listen({ "PLAYER_TARGET_CHANGED" }, Foe)

ns.Listen({ "UNIT_COMBAT:player", "UNIT_COMBAT:target" }, function(_, unit, action, flag)
    if not fight then return end
    action, flag = Clean(action), Clean(flag)
    if unit == "player" then
        local a = action and AVOID[action]
        if a then
            fight.avoided[a] = (fight.avoided[a] or 0) + 1
            fight.attacks = fight.attacks + 1
        elseif action == "WOUND" then
            fight.attacks = fight.attacks + 1
            if flag == "CRUSHING" then fight.crushing = fight.crushing + 1 end
            if flag == "CRITICAL" then fight.critsTaken = fight.critsTaken + 1 end
        end
    elseif action == "WOUND" and flag == "CRITICAL" then
        fight.critsDealt = fight.critsDealt + 1
        Foe()
    end
end)

ns.Listen({ "UNIT_SPELLCAST_SUCCEEDED:player" }, function(_, _, _, spellID)
    if not fight then return end
    local id = CleanNumber(spellID)
    if id and NOT_CASTS[id] then return end
    fight.casts = fight.casts + 1
end)

-- Kills: the "<name> dies, you gain N experience" message (grey mobs give none, so aren't counted).
local xpMsg = CreateFrame("Frame")
pcall(xpMsg.RegisterEvent, xpMsg, "CHAT_MSG_COMBAT_XP_GAIN")
xpMsg:SetScript("OnEvent", function(_, _, text)
    text = Clean(text)
    -- The killing blow's message can come just after combat ends: that's still the last fight's.
    local f = fight or (last and Now() - last.ended < 3 and last.fight)
    if f and type(text) == "string" and text:find(" dies") then
        f.kills = f.kills + 1
        if last and f == last.fight then last.kills = f.kills end
    end
end)

---------------------------------------------------------------------------
-- The game's damage meter
---------------------------------------------------------------------------
-- Your entry for one meter type in the fight's session: total, per second, the session's
-- duration and your GUID (any of them may still be hidden: secret).
local function Meter(kind)
    local get = C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
    if not get then return nil end
    for _, sessionType in ipairs({ 1, 2 }) do -- Current, then Expired
        local ok, s = pcall(get, sessionType, kind)
        if ok and type(s) == "table" and type(s.combatSources) == "table" then
            for _, src in ipairs(s.combatSources) do
                if src.isLocalPlayer == true then
                    return src.totalAmount, src.amountPerSecond, s.durationSeconds, src.sourceGUID, sessionType
                end
            end
        end
    end
end

-- Your biggest damaging spell this fight: name and amount (nil if hidden or unknown).
local function TopAbility(guid, sessionType)
    local get = C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType
    if not (get and guid and sessionType) or IsSecret(guid) then return nil end
    local ok, src = pcall(get, sessionType, METER.done, guid)
    if not ok or type(src) ~= "table" or type(src.combatSpells) ~= "table" then return nil end
    local best, bestAmount
    for _, sp in ipairs(src.combatSpells) do
        local amt = sp.totalAmount
        if IsSecret(amt) or IsSecret(sp.spellID) then return nil end
        if type(amt) == "number" and (not bestAmount or amt > bestAmount) then best, bestAmount = sp.spellID, amt end
    end
    if not best then return nil end
    local name = best == 6603 and "Auto Attack" or ns.SpellName(best) or ("Spell " .. best)
    return name, bestAmount
end

---------------------------------------------------------------------------
-- The pane
---------------------------------------------------------------------------
local pane = CreateFrame("Frame", "CircletFightFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
pane:SetSize(W, 200)
pane:SetFrameStrata("MEDIUM")
pane:SetClampedToScreen(true)
pane:SetMovable(true)
pane:EnableMouse(true)
pane:RegisterForDrag("LeftButton")
pane:Hide()
ns.SkinPanel(pane, { header = 40 })

pane.title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
pane.title:SetPoint("TOPLEFT", pane, "TOPLEFT", 48, -8)
pane.title:SetTextColor(1, 0.86, 0.45)
pane.title:SetText("Fight summary")
pane.subtitle = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pane.subtitle:SetPoint("TOPLEFT", pane.title, "BOTTOMLEFT", 0, -2)
pane.subtitle:SetWidth(W - 90)
pane.subtitle:SetJustifyH("LEFT")
pane.subtitle:SetWordWrap(false)
pane.close = CreateFrame("Button", nil, pane, "UIPanelCloseButton")
pane.close:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -2, -2)

-- The three big numbers.
local bigs = {}
for i, label in ipairs({ "Damage", "DPS", "Taken" }) do
    local b = CreateFrame("Frame", nil, pane)
    b:SetSize((W - PAD * 2) / 3, 42)
    b:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD + (i - 1) * (W - PAD * 2) / 3, -48)
    b.value = b:CreateFontString(nil, "OVERLAY")
    b.value:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE")
    b.value:SetPoint("TOP", b, "TOP", 0, 0)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.label:SetPoint("TOP", b.value, "BOTTOM", 0, -3)
    b.label:SetText(label)
    bigs[i] = b
end
bigs[1].value:SetTextColor(1, 0.82, 0.35)
bigs[2].value:SetTextColor(1, 1, 1)
bigs[3].value:SetTextColor(1, 0.45, 0.40)

local rows = {}
local function Row(i)
    local r = rows[i]
    if r then return r end
    r = {}
    r.label = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.label:SetJustifyH("LEFT")
    r.value = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.value:SetJustifyH("RIGHT")
    r.value:SetWidth(W - PAD * 2 - 90)
    r.value:SetWordWrap(false)
    rows[i] = r
    return r
end

-- A number for display: grouped digits, or (still hidden) handed to the game to draw.
local function Num(v)
    if v == nil then return "–" end
    if IsSecret(v) then
        local ok, s = pcall(AbbreviateNumbers or tostring, v)
        return ok and s or "?"
    end
    if type(v) ~= "number" then return tostring(v) end
    v = math.floor(v + 0.5)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v)
end

local function Clock(secs)
    secs = math.max(0, math.floor(secs + 0.5))
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-- Fills the pane from a summary: { secs, foes, xp, kills, damage, dps, taken, healing,
-- interrupts, dispels, top, topAmount, avoided, attacks, crushing, critsTaken, critsDealt, casts }.
local function Draw(s)
    local foes = s.foes or {}
    local vs = foes[1] and ("vs " .. foes[1] .. (#foes > 1 and (" +" .. (#foes - 1)) or "")) or "Fight"
    pane.subtitle:SetText(vs .. "  ·  " .. Clock(s.secs or 0))
    bigs[1].value:SetText(Num(s.damage))
    bigs[2].value:SetText(Num(s.dps))
    bigs[3].value:SetText(Num(s.taken))

    local lines = {}
    local function Add(label, value) table.insert(lines, { label, value }) end
    if s.xp and s.xp > 0 then
        Add("XP gained", Num(s.xp) .. ((s.kills or 0) > 0 and ("  (" .. s.kills .. (s.kills == 1 and " kill)" or " kills)")) or ""))
    elseif (s.kills or 0) > 0 then
        Add("Kills", tostring(s.kills))
    end
    if s.top then Add("Top ability", s.top .. (s.topAmount and ("  " .. Num(s.topAmount)) or "")) end
    if s.healing ~= nil and (IsSecret(s.healing) or s.healing > 0) then Add("Healing", Num(s.healing)) end
    local parts, avoided = {}, 0
    for _, k in ipairs(AVOID_ORDER) do
        local n = s.avoided and s.avoided[k] or 0
        if n > 0 then
            avoided = avoided + n
            table.insert(parts, n .. " " .. (n == 1 and k or PLURAL[k]))
        end
    end
    if (s.attacks or 0) > 0 then
        Add("Avoided", avoided .. " of " .. s.attacks .. " attacks")
        if #parts > 0 then Add("", table.concat(parts, ", ")) end
    end
    if (s.crushing or 0) > 0 then Add("Crushing blows", tostring(s.crushing)) end
    if (s.critsTaken or 0) > 0 then Add("Crits taken", tostring(s.critsTaken)) end
    if (s.critsDealt or 0) > 0 then Add("Crits on target", tostring(s.critsDealt)) end
    if s.interrupts ~= nil and (IsSecret(s.interrupts) or s.interrupts > 0) then Add("Interrupts", Num(s.interrupts)) end
    if s.dispels ~= nil and (IsSecret(s.dispels) or s.dispels > 0) then Add("Dispels", Num(s.dispels)) end
    if (s.casts or 0) > 0 then Add("Spells cast", tostring(s.casts)) end

    local y = 48 + 42 + 8
    for i, line in ipairs(lines) do
        local r = Row(i)
        r.label:ClearAllPoints()
        r.label:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -y)
        r.label:SetText(line[1])
        r.value:ClearAllPoints()
        r.value:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -PAD, -y)
        r.value:SetText(line[2])
        r.label:Show(); r.value:Show()
        y = y + ROW
    end
    for i = #lines + 1, #rows do rows[i].label:Hide(); rows[i].value:Hide() end
    pane:SetHeight(y + PAD - 4)
end

-- Where the pane goes: <x> from the screen's center, its top <fromTop> below the screen's top.
local function Place()
    pane:ClearAllPoints()
    pane:SetPoint("TOP", UIParent, "TOP", db.fightX or 0, -(db.fightFromTop or 500))
    pane:SetScale((db.fightScale or 100) / 100)
end

pane:SetScript("OnDragStart", function(self) self:StartMoving() end)
pane:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local cx = (self:GetLeft() + self:GetWidth() / 2) * scale
    db.fightX = math.floor(cx - UIParent:GetWidth() / 2 + 0.5)
    db.fightFromTop = math.max(0, math.floor(UIParent:GetHeight() - self:GetTop() * scale + 0.5))
    ns.RefreshOptions()
    Place()
end)

---------------------------------------------------------------------------
-- Showing and fading
---------------------------------------------------------------------------
local shownAt, editing, refreshUntil = 0, false, 0

local function Show(s)
    pane.shownFor = s
    Place()
    Draw(s)
    pane:SetAlpha(1)
    pane:Show()
    shownAt = Now()
end

-- Reads the meter and the counts into the last fight's summary (again while numbers settle).
local function Collect(s)
    local f = s.fight
    local damage, dps, secs, guid, sessionType = Meter(METER.done)
    s.damage, s.dps = damage, dps
    s.taken = Meter(METER.taken)
    s.healing = Meter(METER.healing)
    s.interrupts = Meter(METER.interrupts)
    s.dispels = Meter(METER.dispels)
    s.top, s.topAmount = TopAbility(guid, sessionType)
    if (dps == nil or (not IsSecret(dps) and dps == 0)) and type(damage) == "number" and not IsSecret(damage) then
        s.dps = damage / math.max(1, s.secs) -- the meter's rate missing: ours
    end
    local xp, _, level = XPNow()
    if level == f.level then s.xp = xp - f.xp
    elseif level > f.level then s.xp = (f.xpMax - f.xp) + xp end -- one level up in the fight
    s.kills = f.kills
end

local function EndFight()
    local f = fight
    fight = nil
    if not f then return end
    local secs = Now() - f.start
    last = { fight = f, ended = Now(), secs = secs, foes = f.foeList, avoided = f.avoided, attacks = f.attacks,
             crushing = f.crushing, critsTaken = f.critsTaken, critsDealt = f.critsDealt, casts = f.casts }
    last.kills = f.kills
    Collect(last) -- even when it isn't shown: /circ fight shows it later
    if not db.fightEnabled or editing or secs < (db.fightMinSeconds or 4) then return end
    if db.fightOnlyDamage and not (IsSecret(last.damage) or (type(last.damage) == "number" and last.damage > 0)) then return end
    Show(last)
    refreshUntil = Now() + 3 -- the meter and kill XP can settle a moment after combat ends
end
ns.Listen({ "PLAYER_REGEN_ENABLED" }, EndFight)

local SAMPLE = { secs = 27, foes = { "Gray Bear", "Young Wolf" }, xp = 236, kills = 2, damage = 1843, dps = 68.3,
                 taken = 412, top = "Heroic Strike", topAmount = 642, avoided = { dodge = 2, parry = 1, block = 3, miss = 1 },
                 attacks = 19, crushing = 0, critsTaken = 1, critsDealt = 4, casts = 7 }

local function Preview() Show(SAMPLE); shownAt = Now() end

local ticker = CreateFrame("Frame")
ticker.t = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.t < 0.1 then return end
    self.t = 0
    if not pane:IsShown() then return end
    local now = Now()
    if editing then pane:SetAlpha(1) return end
    if last and now < refreshUntil and pane.shownFor == last then Collect(last); Draw(last) end
    local hold = db.fightSeconds or 12
    if hold <= 0 or pane:IsMouseOver() == true then shownAt = math.max(shownAt, now - math.min(hold, 1)) return end
    local age = now - shownAt
    if age >= hold + 1 then pane:Hide()
    elseif age > hold then pane:SetAlpha(1 - (age - hold)) end
end)

local function SetEditing(on)
    editing = on and true or false
    if editing then Show(SAMPLE) else pane:Hide() end
end

ns.Listen({ "PLAYER_LOGIN" }, Place)

ns.RegisterCommand({ "fight" }, function()
    if pane:IsShown() and not editing then pane:Hide() return end
    if last and last.damage ~= nil then Show(last) else Preview() end
end, "show the last fight's summary again (or a sample)")

ns.FightSummary = { pane = pane, Last = function() return last end, Preview = Preview, Collect = Collect } -- tests

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "fight", name = "Fight summary", order = 14.9, since = "1.4.0",
    edit = { set = SetEditing, get = function() return editing end },
    preview = Preview, help = "preview the fight summary",
    toggle = { "Fight summary", "After each fight, a pane with your damage, DPS, damage taken, XP, kills, what you avoided and more." },
    defaults = {
        fightEnabled     = true,
        fightSeconds     = 12,   -- how long it stays (0: until you close it)
        fightMinSeconds  = 4,    -- shorter fights don't get one
        fightOnlyDamage  = true, -- only after fights you dealt damage in
        fightScale       = 100,
        fightX           = 0,
        fightFromTop     = 500,
    },
    page = { folder = "combat", order = 9, build = function(O)
            local Toggle, Range, Box, Execute = O.Toggle, O.Range, O.Box, O.Execute
            local RingTab, MergeTop, TopRow = O.RingTab, O.MergeTop, O.TopRow
            return RingTab(13.95, "Fight summary", "Fight Summary",
                "When a fight ends, a pane shows your damage, DPS and damage taken, how long it lasted and who you "
                .. "fought, XP and kills, healing, your top ability, what you avoided (dodges, parries, blocks, misses) "
                .. "out of the attacks against you, crushing blows, crits, interrupts, dispels and spells cast. The "
                .. "numbers come from the game's own damage meter. The game hides how much damage a block or absorb "
                .. "stopped, so what you avoided is counted in attacks. It stays while the mouse is over it; drag it to "
                .. "move it. /circ fight shows the last one again.",
                MergeTop(TopRow("fight", "fight summary", Preview, "Show a sample summary. Also /circ fight."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "fightEnabled", "Show a summary after fights", "The pane after each fight."),
                        only = Toggle(2, "fightOnlyDamage", "Only fights you dealt damage in",
                            "Skip fights you took part in without hitting anything (a mob that hit you and ran)."),
                        seconds = Range(3, "fightSeconds", "Stays for (seconds)", 0, 60, 1,
                            "How long the pane stays before fading. 0: until you close it."),
                        min = Range(4, "fightMinSeconds", "Shortest fight (seconds)", 0, 30, 1,
                            "Fights shorter than this don't get a summary."),
                        scale = Range(5, "fightScale", "Size (%)", 60, 160, 5, "How big the pane is."),
                        reset = Execute(6, "Reset position", function()
                            db.fightX, db.fightFromTop = ns.DEFAULTS.fightX, ns.DEFAULTS.fightFromTop
                            Place()
                        end, "Put the pane back in its default spot."),
                    }),
                }))
        end },
})
