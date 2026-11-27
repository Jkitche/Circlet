# Health & power rings (Rings/Health/, effects in Rings/Health/Fx/): readable values fill the ring directly; hidden
# (secret) values fill it segment by segment through step curves and SetAlpha, and their
# text goes to the font string unread. Also: what shows when (Show setting), death, no
# power, edit mode samples, and the hide-the-game's-frame options.
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
RegionMethods.SetAttribute = function(s, k, v) s["_attr_" .. k] = v end
RegionMethods.SetPassThroughButtons = function(s, ...) local t = { ... } s._pass = #t > 0 and table.concat(t, "+") or "none" end
DRIVERS = {}
RegisterStateDriver = function(f, what, cond) DRIVERS[f] = cond end
UnregisterStateDriver = function(f, what) DRIVERS[f] = nil end
-- Units: { hp, max, power, pmax, ptype, token, dead, name, level, reaction, player, class }
UNITS = {}
SECRET = false -- hide health and power (as in combat)
COMBAT = false
issecretvalue = function(v) return type(v) == "table" and v.secret == true end
local function S(v) if SECRET then return { secret = true, v = v } end return v end
UnitExists = function(u) return UNITS[u] ~= nil end
UnitHealth = function(u) return S(UNITS[u].hp) end
UnitHealthMax = function(u) return S(UNITS[u].max) end
UnitPower = function(u) return S(UNITS[u].power) end
UnitPowerMax = function(u) return S(UNITS[u].pmax) end
UnitPowerType = function(u) return UNITS[u].ptype, UNITS[u].token end
UnitIsDeadOrGhost = function(u) return UNITS[u].dead or false end
UnitIsGhost = function() return false end
UnitName = function(u) return UNITS[u].name end
UnitLevel = function(u) return UNITS[u].level or 1 end
UnitReaction = function(u) return UNITS[u].reaction or 2 end
UnitIsPlayer = function(u) return UNITS[u].player or false end
UnitIsTapDenied = function() return false end
UnitClass = function(u) return "Mage", UNITS[u] and UNITS[u].class or "MAGE" end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
UnitAffectingCombat = function() return COMBAT end
InCombatLockdown = function() return COMBAT end
-- 12.0-style curves: a step curve's points; the percent functions run 0..1 through it and
-- hand back a hidden result (a table the mock's SetAlpha records as given).
C_CurveUtil = { CreateCurve = function()
  local c = { pts = {} }
  function c:SetType() end
  function c:AddPoint(x, y) table.insert(self.pts, { x, y }) end
  -- As in the game, Evaluate refuses a hidden value from addon code ("Secret values are only
  -- allowed during untainted execution for this argument").
  function c:Evaluate(x)
    if issecretvalue(x) then error("bad argument #2 to 'Evaluate' (Secret values are only allowed during untainted execution for this argument.)") end
    local y = 0 for _, p in ipairs(self.pts) do if x >= p[1] then y = p[2] end end
    return y end
  return c end }
Enum = { LuaCurveType = { Step = 1 } }
-- As in the game, a masked texture refuses tex coords.
RegionMethods.SetMask = function(s, m) s._mask = m end
local realTC = RegionMethods.SetTexCoord
RegionMethods.SetTexCoord = function(s, ...)
  if s._mask then error("Texture:SetTexCoord(): Cannot set tex coords when texture has mask.") end
  return realTC(s, ...) end
-- SetSpriteSheetCell takes a hidden cell from addon code (as the game's docs say).
RegionMethods.SetSpriteSheetCell = function(s, cell, rows, cols)
  s._cell = issecretvalue(cell) and ("<" .. tostring(cell.v) .. ">") or ("[" .. tostring(cell) .. "]") end
CurveConstants = { ScaleTo100 = { Evaluate = function(_, x) return x * 100 end } }
local function Pct(cur, max, curve)
  local p = max > 0 and cur / max or 0
  local v = curve and curve:Evaluate(p) or p
  return SECRET and { secret = true, v = v } or v
end
UnitHealthPercent = function(u, _, curve) return Pct(UNITS[u].hp, UNITS[u].max, curve) end
UnitPowerPercent = function(u, _, _, curve) return Pct(UNITS[u].power, UNITS[u].pmax, curve) end
-- Font strings: hidden values are recorded as <hidden v>, so the test can see what the
-- game would draw without the addon having read it.
local function Show(v) if issecretvalue(v) then return "<" .. string.format("%.0f", v.v) .. ">" end return tostring(v) end
RegionMethods.SetFormattedText = function(s, fmt, ...)
  local args = { ... }
  for i, a in ipairs(args) do if issecretvalue(a) then args[i] = a.v end end
  local ok, txt = pcall(string.format, fmt, unpack(args))
  s._text = ok and txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or "?"
  for _, a in ipairs({ ... }) do if issecretvalue(a) then s._text = s._text .. " (hidden)" break end end
end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w") : s.index("chunk = lua.eval")])
lua.execute(
    'OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end'
)
# The mock's SetText records plain values; a hidden one shows as <v>.
lua.execute('''
local origFS = RegionMethods.CreateFontString
RegionMethods.CreateFontString = function(self, ...)
  local f = origFS(self, ...)
  f.SetText = function(me, t) if issecretvalue(t) then me._text = "<" .. tostring(t.v) .. "> (hidden)" else me._text = t end end
  f.SetFormattedText = RegionMethods.SetFormattedText
  return f
end
''')
NSX = lua.table()
lua.globals().NS = NSX
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
UNITS.player = { hp = 900, max = 1000, power = 60, pmax = 100, ptype = 3, token = "ENERGY", name = "Valeera", level = 20, player = true, class = "ROGUE" }
CP, MARKS, CLASSIF = 0, {}, {}
GetComboPoints = function() return CP end
GetRaidTargetIndex = function(u) return MARKS[u] end
UnitCanAttack = function(_, u) return UNITS[u] ~= nil and not UNITS[u].friend end
UnitIsUnit = function(a, b) if a == "targettarget" and b == "player" then return UNITS.target and UNITS.target.onMe or false end return a == b end
UnitClassification = function(u) return CLASSIF[u] or "normal" end
UnitIsGhost = function(u) return UNITS[u] and UNITS[u].ghost or false end
-- Anchors as the game keeps them, so a jolt can be checked to put the ring back.
local setPoint = RegionMethods.SetPoint
RegionMethods.SetPoint = function(s, p, rel, rp, x, y)
  setPoint(s, p, rel, rp, x, y)
  if type(rp) == "number" then x, y, rp = rp, x, nil end
  s._anchor = { p, rel, rp or p, x or 0, y or 0 }
end
RegionMethods.ClearAllPoints = function(s) s._anchor = nil end
RegionMethods.GetNumPoints = function(s) return s._anchor and 1 or 0 end
RegionMethods.GetPoint = function(s) local a = s._anchor if a then return a[1], a[2], a[3], a[4], a[5] end end
-- Unit tooltips: plain unless a test sets their lines (TIP_LINES).
TIP_LINES = nil
C_TooltipInfo.GetUnit = function(u) return TIP_LINES and { lines = TIP_LINES } or { lines = {} } end
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function Ring(key) for _, f in ipairs(allFrames) do if f.sqKey == key and f._shown and f._alpha > 0 then return f end end end

-- What the effects are drawing on a ring: its shown effect pieces, by name (gated ones show
-- their hidden alpha as <v>).
function Fx(key)
  local f = Ring(key)
  if not f or not f.vit or not f.vit.fx then return "(none)" end
  local fx, out = f.vit.fx, {}
  for name, t in pairs(fx.t) do
    if t._shown ~= false and t.used then
      local a = t._alpha
      local parent = t:GetParent()
      local hiddenParent = parent and parent ~= fx.root and parent._shown == false
      if not hiddenParent then
        local nm = t._cell and (name .. "@" .. t._cell) or name
        if issecretvalue(a) then table.insert(out, nm .. "<" .. tostring(a.v) .. ">")
        elseif (a or 1) > 0.01 then table.insert(out, nm) end
      end
    end
  end
  table.sort(out)
  -- Collapse numbered pieces: cpP1 cpP2 -> cpP x2
  local counts, order = {}, {}
  for _, n in ipairs(out) do local b = n:gsub("%d+$", "") if not counts[b] then table.insert(order, b) end counts[b] = (counts[b] or 0) + 1 end
  local t = {}
  for _, b in ipairs(order) do t[#t + 1] = counts[b] > 1 and (b .. " x" .. counts[b]) or b end
  return #t > 0 and table.concat(t, " ") or "(none)"
end
CircletDB.playerHpShow = "always"; CircletDB.targetHpShow = "always"
UNITS.target = { hp = 800, max = 1000, power = 0, pmax = 0, ptype = 1, token = "RAGE", name = "Defias Thug", level = 18, reaction = 2 }
Fire("PLAYER_TARGET_CHANGED"); Advance(0.1)
Advance(1); P("target, nothing going on: " .. Fx("targetHp"))
CP = 3; Advance(0.3); P("3 combo points: " .. Fx("targetHp"))
CP = 5; Advance(0.3); P("5 combo points: " .. Fx("targetHp")); CP = 0
MARKS.target = 8; UNITS.target.onMe = true; Advance(0.3); P("skull, targeting you: " .. Fx("targetHp"))
MARKS.target = nil; UNITS.target.onMe = false
-- WoW Forever hides the marker (a secret, even out of combat): the hidden index goes
-- straight to the icon sheet's cell, as Blizzard's target frame does.
MARKS.target = { secret = true, v = 8 }; Advance(0.3); P("hidden skull: " .. Fx("targetHp"))
MARKS.target = { secret = true, v = 2 }; Advance(0.3); P("hidden circle: " .. Fx("targetHp"))
MARKS.target = nil
UNITS.target.hp = 150; Advance(0.3); P("target at 15%: " .. Fx("targetHp"))
SECRET = true; Advance(0.3); P("  hidden, 15%: " .. Fx("targetHp"))
UNITS.target.hp = 500; Advance(0.3); P("  hidden, 50%: " .. Fx("targetHp")); SECRET = false
Fire("UNIT_COMBAT", "target", "HEAL", "", 50, 2); Advance(0.2); P("heal on target: " .. Fx("targetHp")); Advance(1)
Fire("UNIT_COMBAT", "target", "BLOCK", "", 0, 1); Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1); Fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1)
Advance(0.1); P("block, dodge, parry: " .. Fx("targetHp")); Advance(1)
local function Spot(f) local a = f._anchor return a and string.format("%s %.1f,%.1f", a[1], a[4], a[5]) or "none" end
local tf = Ring("targetHp")
local before = Spot(tf)
Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 300, 1); Advance(0.08)
local during = Spot(tf)
Advance(0.4)
P("crit jolt: before " .. before .. ", during moved " .. tostring(during ~= before) .. ", after " .. Spot(tf) .. " (back: " .. tostring(Spot(tf) == before) .. ")")
-- Laid out again mid-jolt (moved in edit mode, auto-arrange): it settles at the new spot.
Fire("UNIT_COMBAT", "target", "WOUND", "CRUSHING", 300, 1); Advance(0.08)
local p, rel, rp = tf:GetPoint(1); tf:SetPoint(p, rel, rp, 123, -45); Advance(0.4)
P("  moved mid-jolt: ends where its own layout puts it: " .. Spot(tf))
UNITS.target.dead = true; UNITS.target.hp = 0; Advance(0.6); P("target dead: " .. Fx("targetHp"))
UNITS.target.dead = false; UNITS.target.hp = 800; Advance(0.3)
-- Skinnable: only a looted corpse's tooltip says so; the kind of creature is remembered.
-- (No skills list at first: counts as being able to gather it; checked further down.)
local mockSkills = C_SkillInfo; C_SkillInfo = nil
UNITS.target.guid = "Creature-0-1-2-3-1131-000ABC"
Advance(0.3); P("wolf, nothing learned: " .. Fx("targetHp"))
UNITS.target.dead = true; UNITS.target.hp = 0; Advance(0.6); P("wolf corpse, loot left: " .. Fx("targetHp"))
TIP_LINES = { { leftText = "Young Wolf" }, { leftText = "Skinnable", leftColor = { r = 0.25, g = 0.75, b = 0.25 } } }
Advance(0.6); P("looted, skinnable (green): " .. Fx("targetHp") .. " glow " .. string.format("%.2f,%.2f,%.2f", unpack(Ring("targetHp").vit.fx.t.skinGlow._vc or {0,0,0})))
TIP_LINES = { { leftText = "Young Wolf" } }; Advance(0.6); P("skinned already: " .. Fx("targetHp"))
UNITS.target.dead = false; UNITS.target.hp = 800; UNITS.target.guid = "Creature-0-1-2-3-1131-000DEF"; Advance(0.3)
local sk = Ring("targetHp").vit.fx.t.skinCursor
P("next wolf, alive: " .. Fx("targetHp") .. " alpha " .. tostring(sk._alpha) .. ", " .. tostring(sk.skinFile))
TIP_LINES = { { leftText = "Requires Mining", leftColor = { r = 1, g = 0.5, b = 0.25 } } }
UNITS.target.guid = "Creature-0-1-2-3-2725-000111"; UNITS.target.dead = true; Advance(0.6)
P("rock elemental corpse: " .. Fx("targetHp") .. " " .. tostring(Ring("targetHp").vit.fx.t.skinCursor.skinFile))
-- No such cursor file in this client: the icon instead.
local fx = Ring("targetHp").vit.fx; fx.t.skinCursor.skinFile = nil
local setTex = fx.t.skinCursor.SetTexture; fx.t.skinCursor.SetTexture = function(t, f) return false end
Advance(0.6); P("  no cursor file: " .. Fx("targetHp") .. " " .. tostring(fx.t.skin and fx.t.skin.skinFile))
fx.t.skinCursor.SetTexture = setTex; fx.t.skinCursor.skinFile = nil
-- Can you gather it yourself? Needs the profession, and a line not in red (beyond your skill).
SKILLS = {}
C_SkillInfo = { GetSkillLineInfoByID = function(id) return SKILLS[id] and { rank = SKILLS[id] } or nil end,
                GetNumSkillLines = function() return 0 end, GetSkillLineInfo = function() return nil end }
local function Grey() local r = Ring("targetHp"); if not r then return "(ring hidden)" end local t = r.vit.fx.t; return tostring(t.skinCursor and t.skinCursor._desat or false) .. ", glow " .. tostring(t.skinGlow ~= nil and t.skinGlow._shown ~= false and t.skinGlow.used == true) .. " | " .. Fx("targetHp") end
RegionMethods.SetDesaturated = function(s, v) s._desat = v end
Advance(2.1); P("no Mining: grey " .. Grey())
SKILLS[186] = 120; Advance(2.1); P("with Mining: grey " .. Grey())
TIP_LINES = { { leftText = "Requires Mining", leftColor = { r = 1, g = 0.13, b = 0.13 } } }; Advance(0.6)
P("  red line (beyond your skill): grey " .. Grey())
C_SkillInfo = mockSkills
CircletDB.targetHpFxSkin = false; Advance(0.6); P("skinnable off: " .. Fx("targetHp")); CircletDB.targetHpFxSkin = true
TIP_LINES = nil; UNITS.target.dead = false; UNITS.target.hp = 800; UNITS.target.guid = nil; Advance(0.3)
-- Quest target: the tooltip's quest lines (title, objectives) or the game's own check.
local function QT() local fs = Ring("targetHp").vit.fx.questText return (fs and fs._shown ~= false and fs._text) or "-" end
UNITS.target.guid = "Creature-0-1-2-3-299-0000AA"
TIP_LINES = { { leftText = "Young Wolf" }, { leftText = "Wolves Across the Border", type = 17 }, { leftText = " - Young Wolf slain: 3/10", type = 8 } }
Advance(1.1); P("quest wolf: " .. Fx("targetHp") .. " text " .. QT())
TIP_LINES = { { leftText = "Young Wolf" }, { leftText = "Wolves Across the Border", type = 17 }, { leftText = " - Young Wolf slain: 10/10", type = 8 } }
Fire("QUEST_LOG_UPDATE"); Advance(0.1); P("objective done: " .. Fx("targetHp") .. " text " .. QT())
TIP_LINES = { { leftText = "Kobold Miner" } }; UNITS.target.guid = "Creature-0-1-2-3-40-0000BB"
Advance(1.1); P("plain mob: " .. Fx("targetHp") .. " text " .. QT())
C_QuestLog = C_QuestLog or {}; C_QuestLog.UnitIsRelatedToActiveQuest = function(u) return u == "target" end
Fire("QUEST_LOG_UPDATE"); Advance(0.1); P("game says related: " .. Fx("targetHp") .. " text " .. QT())
CircletDB.targetHpFxQuest = false; Advance(0.3); P("quest target off: " .. Fx("targetHp")); CircletDB.targetHpFxQuest = true
C_QuestLog.UnitIsRelatedToActiveQuest = nil; TIP_LINES = nil; UNITS.target.guid = nil; Fire("QUEST_LOG_UPDATE"); Advance(0.3)
-- Out of range: the ring dims (its own fade) while none of your main attacks reach.
local function HolderA() return string.format("%.2f", NS.RingHolder("targetHp"):GetAlpha()) end
INRANGE = { [1752] = true, [2098] = true }
C_Spell = C_Spell or {}
C_Spell.IsSpellInRange = function(id, u) return INRANGE[id] end
C_SpellBook = C_SpellBook or {}; C_SpellBook.IsSpellKnown = function(id) return id == 1752 or id == 2098 end
Advance(1); P("in range: ring at " .. HolderA())
INRANGE = { [1752] = false, [2098] = false }; Advance(0.1); local mid = HolderA(); Advance(1)
P("out of range: ring at " .. mid .. " -> " .. HolderA())
INRANGE = { [1752] = false, [2098] = true }; Advance(1); P("one spell reaches: ring at " .. HolderA())
INRANGE = { [1752] = false, [2098] = false }; Advance(1)
CircletDB.targetHpFxRange = false; Advance(1); P("out of range, effect off: ring at " .. HolderA())
CircletDB.targetHpFxRange = true; INRANGE = {}; Advance(1); P("can't be checked (friendly): ring at " .. HolderA())
-- Tagged by someone else: grey, whatever the color mode.
local function HealthRGB() local f = Ring("targetHp"); local c = f and f.vit and f.vit.lastColor
  return c and string.format("%.2f,%.2f,%.2f", c.r, c.g, c.b) or "?" end
TAPPED = false; UnitIsTapDenied = function(u) return u == "target" and TAPPED end
CircletDB.targetHpColorMode = "health"; Advance(0.3); P("not tagged: health " .. HealthRGB())
TAPPED = true; Advance(0.3); P("tagged by someone else: health " .. HealthRGB())
CircletDB.targetHpFxTapped = false; Advance(0.3); P("tagged, effect off: health " .. HealthRGB())
CircletDB.targetHpFxTapped = true; TAPPED = false; CircletDB.targetHpColorMode = "class"; Advance(0.3)
-- Lootable: glints round a corpse with loot for you.
LOOT = false; CanLootUnit = function(g) return LOOT, LOOT end
UNITS.target.guid = "Creature-0-1-2-3-299-0000AA"
UNITS.target.dead = true; UNITS.target.hp = 0; Advance(0.6); P("corpse, no loot: " .. Fx("targetHp"))
LOOT = true; Advance(0.6); P("corpse with loot: " .. Fx("targetHp"))
LOOT = false; Advance(0.6); P("looted: " .. Fx("targetHp"))
do local sk = Ring("targetHp").vit.fx.t.skull
  P(string.format("dead skull: at %.0f,%.0f, %spx across, alpha %s",
    sk._pt.x, sk._pt.y, tostring(sk._w), tostring(sk._alpha))) end
UNITS.target.dead = false; UNITS.target.hp = 800; UNITS.target.guid = nil; Advance(0.3)
-- Stance or form: a badge at the bottom right of your ring.
FORM = 0; GetShapeshiftForm = function() return FORM end
GetShapeshiftFormInfo = function(i) return "Interface\\\\Icons\\\\Ability_Druid_CatForm", true, true, 768 end
Advance(0.3); P("no form: " .. Fx("playerHp"))
FORM = 2; Advance(0.3); P("cat form: " .. Fx("playerHp") .. " " .. tostring(Ring("playerHp").vit.fx.t.stance.iconFile))
CircletDB.playerHpFxStance = false; Advance(0.3); P("stance off: " .. Fx("playerHp")); CircletDB.playerHpFxStance = true
FORM = 0; Advance(0.3)
-- Enemy faction: the other faction's crest at the left of the target ring, players only.
FACTION = { player = "Alliance", target = "Horde" }; IS_PLAYER = true
UnitFactionGroup = function(u) return FACTION[u] end
local IsPlayerBefore = UnitIsPlayer
UnitIsPlayer = function(u) return u == "player" or (u == "target" and IS_PLAYER) end
local function Crest()
  local t = Ring("targetHp").vit.fx.t.faction
  if not (t and t._shown) then return "none" end
  local tc = t._tc4 or {}
  return string.format("%s (crop %s,%s,%s,%s) at %.0f,%.0f", tostring(t._texpath), tostring(tc[1]), tostring(tc[2]),
    tostring(tc[3]), tostring(tc[4]), t._pt.x, t._pt.y)
end
Fire("PLAYER_TARGET_CHANGED"); Advance(0.3); P("horde player (you alliance): " .. Crest())
FACTION.target = "Alliance"; Fire("PLAYER_TARGET_CHANGED"); Advance(0.3); P("alliance player: " .. Crest())
FACTION.target = "Horde"; IS_PLAYER = false; Fire("PLAYER_TARGET_CHANGED"); Advance(0.3); P("horde npc: " .. Crest())
IS_PLAYER = true; Fire("PLAYER_TARGET_CHANGED"); Advance(0.3)
FACTION.target = nil; Advance(0.3); P("faction hidden after it was read: " .. Crest())
Fire("PLAYER_TARGET_CHANGED"); Advance(0.3); P("new target, faction hidden: " .. Crest())
FACTION.target = "Horde"; CircletDB.targetHpFxFaction = false; Advance(0.3); P("effect off: " .. Crest())
CircletDB.targetHpFxFaction = true; Advance(0.3)
P("spot: " .. NS.VitalsBadges.Spot("targetHp", "Faction") .. ", on by default: " .. tostring(CircletDB.targetHpFxFaction))
UnitIsPlayer = IsPlayerBefore; UnitFactionGroup = nil; Fire("PLAYER_TARGET_CHANGED"); Advance(0.3)
-- Badge positions: each badge at its chosen spot; a taken spot swaps.
local B = NS.VitalsBadges
local function Where(key, b) return B.Spot(key, b) .. "(" .. B.Angle(key, b) .. ")" end
P("defaults: target mark " .. Where("targetHp", "Mark") .. ", skin " .. Where("targetHp", "Skin") .. ", quest " .. Where("targetHp", "Quest")
  .. ", level " .. Where("targetHp", "Level") .. ", loot " .. Where("targetHp", "Loot") .. "; you: level " .. Where("playerHp", "Level")
  .. ", combat " .. Where("playerHp", "Combat") .. ", stance " .. Where("playerHp", "Stance"))
FORM = 2; Advance(0.3)
local function At(key, name) local t = Ring(key).vit.fx.t[name]; return t and t._pt and string.format("%.0f,%.0f", t._pt.x, t._pt.y) or "-" end
local before = At("playerHp", "stance")
B.Set("playerHp", "Stance", "left"); Advance(0.3)
P("stance moved to the left: " .. before .. " -> " .. At("playerHp", "stance") .. " (" .. Where("playerHp", "Stance") .. ")")
B.Set("playerHp", "Stance", "topright"); Advance(0.3)
P("stance onto the combat icon's spot: stance " .. Where("playerHp", "Stance") .. ", combat " .. Where("playerHp", "Combat"))
B.Set("targetHp", "Level", "topleft")
P("target level onto the mark's spot: level " .. Where("targetHp", "Level") .. ", mark " .. Where("targetHp", "Mark"))
for badge, b in pairs(B.badges) do for k, spot in pairs(b) do if type(k) == "string" and k:find("Hp$") then CircletDB[k .. "Pos" .. badge] = spot end end end
FORM = 0; Advance(0.3)
P("back to defaults: you stance " .. Where("playerHp", "Stance") .. ", combat " .. Where("playerHp", "Combat"))
-- Your ring.
P("you (rogue, energy), no tick seen: " .. Fx("playerHp"))
Fire("UNIT_POWER_FREQUENT", "player", "ENERGY"); Advance(0.1); P("energy tick: " .. Fx("playerHp")); Advance(0.6)
P("  0.7s on: " .. Fx("playerHp"))
local _, tick = NS.VitalsFxState()
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 1752); Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
local _, tick2 = NS.VitalsFxState(); P("  energy spent by a cast isn't a tick: " .. tostring(tick == tick2))
Fire("PLAYER_REGEN_DISABLED"); COMBAT = true; Advance(0.1); P("combat starts: " .. Fx("playerHp")); Advance(1)
UNITS.player.hp = 200; Advance(0.1); P("you at 20%: " .. Fx("playerHp"))
SECRET = true; Advance(0.1); P("  hidden: " .. Fx("playerHp"))
-- The gate is the halo's only alpha: no vertex-color alpha on it (in game that showed the glow
-- whatever the gate said); the pulse is on its own frame.
do
  local vc = RegionMethods.SetVertexColor
  local halo = Ring("playerHp").vit.fx.t.lowHalo
  local four = false
  halo.SetVertexColor = function(s, r, g, b, a) if a ~= nil then four = true end return vc(s, r, g, b) end
  Advance(0.1); halo.SetVertexColor = nil
  P("  halo: vertex alpha set " .. tostring(four))
end
SECRET = false; UNITS.player.hp = 900; Advance(0.1)
COMBAT = false; Fire("PLAYER_REGEN_ENABLED")
-- A warrior's rage; a mage's full mana.
UNITS.player.token, UNITS.player.ptype, UNITS.player.power = "RAGE", 1, 30
Fire("UNIT_POWER_FREQUENT", "player", "RAGE"); Advance(0.2); P("rage gain: " .. Fx("playerHp")); Advance(1)
UNITS.player.token, UNITS.player.ptype, UNITS.player.power, UNITS.player.pmax = "MANA", 0, 1200, 1200
Advance(0.3); P("full mana: " .. Fx("playerHp"))
SECRET = true; Advance(0.1); P("  hidden: " .. Fx("playerHp")); SECRET = false
UNITS.player.power = 600; Advance(0.3); P("half mana: " .. Fx("playerHp"))
UNITS.player.dead, UNITS.player.ghost, UNITS.player.hp = true, true, 0; Advance(0.6); P("your ghost: " .. Fx("playerHp"))
UNITS.player.dead, UNITS.player.ghost, UNITS.player.hp = false, false, 900; Advance(0.3)
-- Settings: each off.
CircletDB.targetHpFxMark = false; MARKS.target = 2; Advance(0.3); P("raid marker off: " .. Fx("targetHp")); MARKS.target = nil
CircletDB.targetHpFxMark = true
local tf2 = Ring("targetHp"); local b2 = Spot(tf2)
CircletDB.targetHpFxJolt = false; Fire("UNIT_COMBAT", "target", "WOUND", "CRUSHING", 300, 1); Advance(0.08)
P("jolt off: moved " .. tostring(Spot(tf2) ~= b2))
''')
print("\n".join(lua.eval("OUT").values()))
print("ERRORS:", dict(lua.eval("ERRORS")))
