# Health & power rings (Rings/Vitals.lua): readable values fill the ring directly; hidden
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
  -- Evaluate takes a stored hidden value too (handing back a hidden result), as the lagging
  -- trail hopes the game allows.
  function c:Evaluate(x)
    local hid = issecretvalue(x); if hid then x = x.v end
    local y = 0 for _, p in ipairs(self.pts) do if x >= p[1] then y = p[2] end end
    if hid then return { secret = true, v = y } end
    return y end
  return c end }
Enum = { LuaCurveType = { Step = 1 } }
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
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end')
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
NSX = lua.table(); lua.globals().NS = NSX
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
UNITS.player = { hp = 900, max = 1000, power = 300, pmax = 1200, ptype = 0, token = "MANA", name = "Jaina", level = 20, player = true }
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function Ring(key) for _, f in ipairs(allFrames) do if f.sqKey == key and f._shown and f._alpha > 0 then return f end end end
local function Lit(lines)
  local n, hidden = 0, 0
  for _, l in ipairs(lines or {}) do
    if l._shown ~= false and l._x1 then
      if issecretvalue(l._alpha) then hidden = hidden + 1; if l._alpha.v > 0 then n = n + 1 end
      elseif (l._alpha or 1) > 0 then n = n + 1 end
    end
  end
  return n, hidden
end
function C(key)
  local f = Ring(key)
  if not f then return "(hidden)" end
  local v = f.vit or {}
  local hp, hh = Lit(f.fill)
  local pw, ph = Lit(v.fill)
  local t = function(fs) return fs and fs._text and fs._text ~= "" and tostring(fs._text) or "-" end
  local health = t(v.hp) .. (v.hp2 and v.hp2._text and v.hp2._text ~= "" and (" // " .. tostring(v.hp2._text)) or "")
  return string.format("health %d segs%s, power %d segs%s | %s / %s / %s", hp, hh > 0 and " (gated)" or "", pw,
    ph > 0 and " (gated)" or "", t(v.name), health, t(v.pw))
end

-- Your ring: out of combat at 90% health, 25% mana: not full, so it shows.
P("you, not full: " .. C("playerHp"))
UNITS.player.hp, UNITS.player.power = 1000, 1200; Advance(2); P("you, full, out of combat: " .. C("playerHp"))
COMBAT = true; Advance(0.5); P("you, full, in combat: " .. C("playerHp"))
-- Hidden in combat: the ring fills segment by segment, text handed over unread.
UNITS.player.hp, UNITS.player.power = 400, 600; SECRET = true; Advance(0.5); P("you, hidden (40%, 50%): " .. C("playerHp"))
CircletDB.playerHpText = "both"; Advance(0.2); P("you, hidden, value and percent: " .. C("playerHp"))
CircletDB.playerHpText = "value"; Advance(0.2); P("you, hidden, value: " .. C("playerHp")); CircletDB.playerHpText = "percent"
SECRET = false; COMBAT = false; UNITS.player.hp, UNITS.player.power = 1000, 1200; Advance(3)

-- A warrior: rage from empty shows only while there's some.
UNITS.player.ptype, UNITS.player.token, UNITS.player.power, UNITS.player.pmax = 1, "RAGE", 0, 100; Advance(2)
P("warrior, full health, no rage: " .. C("playerHp"))
UNITS.player.power = 35; Advance(0.5); P("warrior, 35 rage: " .. C("playerHp"))
UNITS.player.power = 0; UNITS.player.ptype, UNITS.player.token, UNITS.player.pmax = 0, "MANA", 1200; UNITS.player.power = 1200; Advance(3)

-- Target: whenever you have one, with name, level and reaction color.
UNITS.target = { hp = 300, max = 1200, power = 0, pmax = 0, ptype = 1, token = "RAGE", name = "Defias Bandit", level = 18, reaction = 2 }
Advance(0.5); P("target, hostile, no power: " .. C("targetHp"))
local f = Ring("targetHp"); local c = f and f.fill[1]._c
P("  hostile color: " .. (c and string.format("%.2f %.2f %.2f", c[1], c[2], c[3]) or "?"))
UNITS.target.dead = true; Advance(0.3); P("target dead: " .. C("targetHp")); UNITS.target.dead = nil
SECRET = true; COMBAT = true; Advance(0.3); P("target hidden (25%): " .. C("targetHp")); SECRET = false; COMBAT = false
UNITS.target = nil; Advance(2); P("no target: " .. C("targetHp"))
CircletDB.targetHpShow = "combatOnly"; UNITS.target = { hp = 600, max = 1200, power = 50, pmax = 100, ptype = 0, token = "MANA", name = "Kobold", level = 5, reaction = 4 }
Advance(1); P("target, only in combat, out of combat: " .. C("targetHp"))
COMBAT = true; Advance(0.5); P("target, only in combat, in combat: " .. C("targetHp")); COMBAT = false; CircletDB.targetHpShow = "always"
CircletDB.targetHpPower = false; Advance(0.3); P("target, power band off: " .. C("targetHp")); CircletDB.targetHpPower = true
UNITS.target = nil; Advance(2)

-- A client without the percent functions: hidden values can't fill, but nothing breaks.
local uhp, upp = UnitHealthPercent, UnitPowerPercent
UnitHealthPercent, UnitPowerPercent = nil, nil; SECRET = true; COMBAT = true; Advance(0.5)
P("no percent functions, hidden: " .. C("playerHp"))
UnitHealthPercent, UnitPowerPercent = uhp, upp; SECRET = false; COMBAT = false; Advance(3)

-- Edit mode samples (and previews), both rings.
NS.SetRingEditing("playerHp", true, true); NS.SetRingEditing("targetHp", true, true); Advance(1)
P("edit, you: " .. C("playerHp")); P("edit, target: " .. C("targetHp"))
NS.SetRingEditing("playerHp", false, true); NS.SetRingEditing("targetHp", false, true); Advance(3)

-- Portraits in the middle, and the power text moved about.
PORTRAITS = 0
SetPortraitTexture = function(tex, unit) tex._portrait = unit; PORTRAITS = PORTRAITS + 1 end
local function Portrait(key) local f = Ring(key); local p = f and f.vit and f.vit.portrait
  return p and p._shown and (tostring(p._portrait) .. " at " .. string.format("%.2f", p._alpha)) or "none" end
UNITS.target = { hp = 600, max = 1200, power = 50, pmax = 100, ptype = 0, token = "MANA", name = "Kobold", level = 5, reaction = 4 }
Advance(0.5); P("portrait off: " .. Portrait("targetHp"))
CircletDB.targetHpPortrait = true; Advance(0.5); P("target portrait: " .. Portrait("targetHp"))
local n = PORTRAITS; Advance(1); P("redrawn while nothing changed: " .. (PORTRAITS - n))
Fire("PLAYER_TARGET_CHANGED"); Advance(0.2); P("new target: redrawn " .. (PORTRAITS - n) .. " time(s)")
CircletDB.targetHpPortraitAlpha = 40; Advance(0.2); P("dimmer: " .. Portrait("targetHp"))
CircletDB.playerHpPortrait = true; CircletDB.playerHpShow = "always"; Advance(0.5); P("your portrait: " .. Portrait("playerHp"))
CircletDB.playerHpShow = "combat"
CircletDB.targetHpPortrait = false; CircletDB.playerHpPortrait = false
UNITS.target = nil; Advance(2)

-- Number and % on two lines (only with Value and percent).
UNITS.player.hp = 650; Advance(0.5)
CircletDB.playerHpSplitText = true; Advance(0.2); P("split, but text is percent: " .. C("playerHp"))
CircletDB.playerHpText = "both"; Advance(0.2); P("value and percent, split: " .. C("playerHp"))
SECRET = true; COMBAT = true; Advance(0.3); P("split, hidden: " .. C("playerHp")); SECRET = false; COMBAT = false
CircletDB.playerHpSplitText = false; Advance(0.2); P("value and percent, one line: " .. C("playerHp"))
CircletDB.playerHpText = "percent"; UNITS.player.hp = 1000; Advance(3)

-- Transitions. Readable: a hit leaves a trail (and a big one flashes), the fill glides
-- down, the trail drains after it; a heal glows in.
local function FX(key)
  local f = Ring(key); local v = f and f.vit; if not v then return "none" end
  local function n(lines) local a, b = Lit(lines); return a end
  return string.format("fill %d, trail %d, glow %d", n(f.fill), n(v.h.trail), n(v.h.glow))
end
CircletDB.playerHpShow = "always"; UNITS.player.hp = 1000; Advance(1)
UNITS.player.hp = 500; Advance(0.1); P("hit 100% -> 50%, just after: " .. FX("playerHp"))
-- The ease, as the XP ring's: fast at first, settling (fill segments every 0.1 s).
local steps = {}
for i = 1, 9 do Advance(0.1); local f = Ring("playerHp"); local fl = Lit(f.fill); local tr = Lit(f.vit.h.trail); steps[#steps + 1] = fl .. "+" .. tr end
P("  easing down, fill+trail every 0.1 s: " .. table.concat(steps, " "))
Advance(1.5); P("  2 s on: " .. FX("playerHp"))
UNITS.player.hp = 800; Advance(0.15); P("healed to 80%: " .. FX("playerHp"))
Advance(1.5); P("  settled: " .. FX("playerHp"))
UNITS.player.hp = 750; Advance(0.1); P("small hit (5%): " .. FX("playerHp"))
CircletDB.playerHpSmooth = false; UNITS.player.hp = 600; Advance(0.05); P("smooth off: jumps: " .. FX("playerHp"))
CircletDB.playerHpSmooth = true; CircletDB.playerHpTrail = false; UNITS.player.hp = 400; Advance(0.1)
P("trail off: " .. FX("playerHp")); CircletDB.playerHpTrail = true; Advance(2)
-- Hidden (the segmented-style fallback here: this mock has no eased status bars): the band
-- steps, and nothing flashes. (Eased bands: vitals_eased_test.py.)
local ev = CircletCurveEvaluate
SECRET = true; COMBAT = true; Advance(1)
Fire("UNIT_HEALTH", "player"); Advance(0.1); P("hidden, a change: nothing flashes: " .. FX("playerHp"))
Advance(0.5); P("  later: " .. FX("playerHp"))
UNITS.player.hp = 200; Fire("UNIT_HEALTH", "player"); Advance(0.1); P("hidden hit 40% -> 20%, 0.1 s: " .. FX("playerHp"))
Advance(0.2); P("  at 0.3 s: " .. FX("playerHp"))
Advance(0.8); P("  1 s on, caught up: " .. FX("playerHp"))
SECRET = false; COMBAT = false; UNITS.player.hp = 1000; CircletDB.playerHpShow = "combat"; Advance(3)

-- Big hits: the health band flashes red. Readable: a loss of 15% or more at once; hidden: a
-- critical or crushing hit (UNIT_COMBAT says the kind, not the size).
local function Flash(key) local f = Ring(key); return f and f.vit and (Lit(f.vit.h.flash)) or 0 end
CircletDB.playerHpShow = "always"; UNITS.player.hp = 1000; Advance(2)
UNITS.player.hp = 900; Advance(0.1); P("readable, 10% hit: flash " .. Flash("playerHp")); Advance(1)
UNITS.player.hp = 650; Advance(0.1); P("readable, 25% hit: flash " .. Flash("playerHp")); Advance(0.6)
P("  0.7 s on: flash " .. Flash("playerHp")); Advance(1)
SECRET = true; COMBAT = true; Advance(0.5)
Fire("UNIT_COMBAT", "player", "WOUND", "", 120, 1); Advance(0.1); P("hidden, ordinary hit: flash " .. Flash("playerHp")); Advance(1)
Fire("UNIT_COMBAT", "player", "WOUND", "CRITICAL", 400, 1); Advance(0.1); P("hidden, critical hit: flash " .. Flash("playerHp")); Advance(1)
Fire("UNIT_COMBAT", "player", "WOUND", "CRUSHING", 400, 1); Advance(0.1); P("hidden, crushing blow: flash " .. Flash("playerHp")); Advance(1)
Fire("UNIT_COMBAT", "player", "DODGE", "", 0, 1); Advance(0.1); P("hidden, dodged: flash " .. Flash("playerHp")); Advance(1)
CircletDB.playerHpBigHit = false; Fire("UNIT_COMBAT", "player", "WOUND", "CRITICAL", 400, 1); Advance(0.1)
P("option off, critical: flash " .. Flash("playerHp")); CircletDB.playerHpBigHit = true
SECRET = false; COMBAT = false; CircletDB.playerHpShow = "combat"; Advance(2)
P("defaults: you " .. tostring(CircletDB.playerHpBigHit) .. ", target " .. tostring(CircletDB.targetHpBigHit) .. ", target of target " .. tostring(CircletDB.totHpBigHit))

-- Right-click menus: a secure unit button per ring. Out of combat it follows the ring and shows
-- while the ring does; when combat starts the game takes over (a state driver).
RegionMethods.IsVisible = function(s) return s._shown end
RegionMethods.GetCenter = function(s) return s._cx, s._cy end
RegionMethods.SetPoint = function(s, p, rel, rp, x, y) s._pt = { p, rp, x, y } end
local function Spot(b) return b._pt and table.concat({ tostring(b._pt[1]), tostring(b._pt[2]), tostring(b._pt[3]), tostring(b._pt[4]) }, " ") or "-" end
CircletDB.targetHpShow = "always"; UNITS.target = { hp = 600, max = 1200, power = 50, pmax = 100, ptype = 0, token = "MANA", name = "Kobold", level = 5, reaction = 2 }
Advance(1)
local mb = CircletTargetHpMenu
P("target menu: " .. tostring(mb ~= nil) .. ", unit " .. tostring(mb and mb._attr_unit) .. ", right-click " .. tostring(mb and mb["_attr_*type2"])
  .. ", shown " .. tostring(mb and mb:IsShown()))
local tf = Ring("targetHp"); tf._cx, tf._cy = 900, 500; Advance(0.3)
P("  ring moved (auto-arrange): at " .. Spot(mb))
tf._cx, tf._cy = nil, nil
UNITS.target = nil; Advance(2); P("  no target, ring gone: shown " .. tostring(mb:IsShown()))
UNITS.target = { hp = 600, max = 1200, power = 50, pmax = 100, ptype = 0, token = "MANA", name = "Kobold", level = 5, reaction = 2 }
Advance(1); P("  target again: shown " .. tostring(mb:IsShown()))
NS.SetRingEditing("targetHp", true, true); Advance(0.3); P("  edit mode: shown " .. tostring(mb:IsShown()))
NS.SetRingEditing("targetHp", false, true); Advance(1)
Fire("PLAYER_REGEN_DISABLED"); COMBAT = true; Advance(0.3); P("  combat: driver " .. tostring(DRIVERS[mb]))
CircletDB.targetHpMenu = false; Advance(0.3); P("  turned off in combat: driver still " .. tostring(DRIVERS[mb] ~= nil) .. " (waits)")
COMBAT = false; Fire("PLAYER_REGEN_ENABLED"); Advance(0.3); P("  after combat: driver " .. tostring(DRIVERS[mb]) .. ", shown " .. tostring(mb:IsShown()))
CircletDB.targetHpMenu = true; Advance(0.3)
CircletDB.playerHpShow = "always"; Advance(1)
P("your menu: unit " .. tostring(CircletPlayerHpMenu and CircletPlayerHpMenu._attr_unit) .. ", shown " .. tostring(CircletPlayerHpMenu and CircletPlayerHpMenu:IsShown()))
local pm = CircletPlayerHpMenu
local function Clicks(b) return string.format("left %s, right %s, passes %s", tostring(b["_attr_*type1"]), tostring(b["_attr_*type2"]), tostring(b._pass)) end
P("  your ring clicks: " .. Clicks(pm))
P("  target ring clicks: " .. Clicks(mb))
CircletDB.playerHpClickTarget = false; Advance(0.3); P("  click to target off: " .. Clicks(pm))
CircletDB.playerHpClickTarget = true; CircletDB.playerHpMenu = false; Advance(0.3); P("  menu off, click on: " .. Clicks(pm) .. ", shown " .. tostring(pm:IsShown()))
CircletDB.playerHpClickTarget = false; Advance(0.3); P("  both off: shown " .. tostring(pm:IsShown()))
CircletDB.playerHpClickTarget = true; CircletDB.playerHpMenu = true; Advance(0.3)
CircletDB.playerHpShow = "combat"; Advance(3); UNITS.player.power = UNITS.player.pmax; UNITS.player.hp = UNITS.player.max; Advance(3); P("  ring hidden (full, out of combat): ring " .. tostring(Ring("playerHp") ~= nil) .. ", menu shown " .. tostring(CircletPlayerHpMenu:IsShown()))
P("defaults: menus " .. tostring(CircletDB.playerHpMenu) .. "/" .. tostring(CircletDB.targetHpMenu) .. "/" .. tostring(CircletDB.totHpMenu))

-- Badges: the level (bottom left) and, on your ring, crossed swords while in combat.
CircletDB.playerHpShow = "always"; UNITS.player.level = 42; Advance(1)
local pv = Ring("playerHp").vit
P("level badge: " .. tostring(pv.lvl.text._text) .. ", disc " .. tostring(pv.lvl.fill:IsShown()) .. ", combat badge " .. tostring(pv.cmb.icon:IsShown()))
COMBAT = true; Advance(0.3); P("  in combat: combat badge " .. tostring(pv.cmb.icon:IsShown())); COMBAT = false; Advance(0.3)
CircletDB.playerHpCombatIcon = false; COMBAT = true; Advance(0.3); P("  option off: combat badge " .. tostring(pv.cmb.icon:IsShown())); COMBAT = false; CircletDB.playerHpCombatIcon = true
CircletDB.playerHpLevel = false; Advance(0.3); P("  level off: disc " .. tostring(pv.lvl.fill:IsShown())); CircletDB.playerHpLevel = true
local tv = Ring("targetHp").vit
-- The target's: bottom right, on by default; creature difficulty colors, yellow for friends.
UnitIsFriend = function(_, u) return UNITS[u] and UNITS[u].friend or false end
GetCreatureDifficultyColor = function(l) if l <= 3 then return { r = 0.25, g = 0.75, b = 0.25 } end return { r = 1, g = 0.1, b = 0.1 } end
local function TC(fs) return fs._tc and string.format("%.2f,%.2f,%.2f", fs._tc[1], fs._tc[2], fs._tc[3]) or "-" end
Advance(0.3)
P("target: level badge on by default: " .. tostring(tv.lvl.text._text) .. " in " .. TC(tv.lvl.text) .. ", name " .. tostring(tv.name._text))
UNITS.target.level = 2; Advance(0.3); P("  low level foe: " .. TC(tv.lvl.text))
UNITS.target.friend = true; Advance(0.3); P("  friendly: " .. TC(tv.lvl.text)); UNITS.target.friend = nil; UNITS.target.level = 5
CircletDB.targetHpLevel = false; Advance(0.3)
P("  off: disc " .. tostring(tv.lvl.fill:IsShown()) .. ", name " .. tostring(tv.name._text)); CircletDB.targetHpLevel = true
-- Elite marker: wings on the level badge, gold for elites and bosses, silver for rares.
UnitClassification = function(u) return UNITS[u] and UNITS[u].class or "normal" end
local function VC(t) return t._vc and string.format("%.2f,%.2f,%.2f", t._vc[1], t._vc[2], t._vc[3]) or "-" end
local function Elite()
  local dr = tv.lvl.dragon
  local art = dr:IsShown() and (tostring(dr._texpath):match("UI%-TargetingFrame%-(.+)$") or "?") or "none"
  return string.format("dragon %s, wings %s, rim %s", art, tostring(tv.lvl.wingL:IsShown()), VC(tv.lvl.rim)) end
Advance(0.3); P("elite: normal mob: " .. Elite())
for _, c in ipairs({ "elite", "rare", "rareelite", "worldboss" }) do UNITS.target.class = c; Advance(0.3); P("elite: " .. c .. ": " .. Elite()) end
CircletDB.targetHpElite = false; Advance(0.3); P("elite: setting off (worldboss): " .. Elite()); CircletDB.targetHpElite = true
CircletDB.targetHpLevel = false; Advance(0.3); P("elite: level badge off: " .. Elite()); CircletDB.targetHpLevel = true
-- A client without the dragon art: our wings instead (and none for plain rares, like the game).
local realSet = RegionMethods.SetTexture
RegionMethods.SetTexture = function(s, t) if type(t) == "string" and t:find("UI%-TargetingFrame") then s._texpath = nil return false end return realSet(s, t) end
tv.lvl.dragonFile = nil
UNITS.target.class = "elite"; Advance(0.3); P("elite: no dragon art, elite: " .. Elite())
UNITS.target.class = "rare"; tv.lvl.dragonFile = nil; Advance(0.3); P("elite: no dragon art, rare: " .. Elite())
RegionMethods.SetTexture = realSet; tv.lvl.dragonFile = nil
-- Damage and healing numbers floating off the target ring.
issecretvalue = issecretvalue or function() return false end
local realSecret = issecretvalue
issecretvalue = function(x) return x == "SECRET" or realSecret(x) end
RegionMethods.SetFormattedText = function(s, fmt, ...) s._text = string.format(fmt, tostring((...))) .. " (drawn)" end
local function Floats(v)
  local t = {}
  for _, fs in ipairs(v.floats or {}) do
    if fs._shown ~= false and fs._text then
      table.insert(t, string.format("%s[%s %dpx a%.1f]", tostring(fs._text), fs._tc and string.format("%.1f,%.1f,%.1f", fs._tc[1], fs._tc[2], fs._tc[3]) or "-", fs.px or 0, fs._alpha or 1))
    end
  end
  return #t > 0 and table.concat(t, " ") or "(none)"
end
Fire("UNIT_COMBAT", "target", "WOUND", "", 123, 1)
Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 456, 1)
Fire("UNIT_COMBAT", "target", "HEAL", "", 15000, 2)
Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
Advance(0.05); P("floats: hit, crit, heal, dodge: " .. Floats(tv))
Fire("UNIT_COMBAT", "target", "WOUND", "", "SECRET", 1); Advance(0.05); P("floats: hidden amount: " .. Floats(tv))
Advance(1.2); P("floats: fading: " .. Floats(tv))
Advance(0.5); P("floats: gone: " .. Floats(tv))
Fire("UNIT_COMBAT", "player", "WOUND", "", 77, 1); Fire("UNIT_COMBAT", "player", "HEAL", "CRITICAL", 300, 2)
Advance(0.05); P("floats on your ring: " .. Floats(pv))
-- Direction: where they start and which way they go (relative to the ring's center).
-- Only the axis it floats along (the sideways drift is a little random).
local function Where(v, dir) local fs = v.floats and v.floats[1]; if not (fs and fs._pt) then return "-" end
  return (dir == "up" or dir == "down") and string.format("y=%.0f", fs._pt[4]) or string.format("x=%.0f", fs._pt[3]) end
Advance(2)
for _, dir in ipairs({ "up", "down", "left", "right" }) do
  CircletDB.targetHpFloatDir = dir
  Fire("UNIT_COMBAT", "target", "WOUND", "", 10, 1); Advance(0.05); local a = Where(tv, dir); Advance(0.6)
  P("floats " .. dir .. ": " .. a .. " -> " .. Where(tv, dir)); Advance(1.5)
end
CircletDB.targetHpFloatDir = "up"
CircletDB.targetHpFloat = false; Fire("UNIT_COMBAT", "target", "WOUND", "", 99, 1); Advance(0.05); P("floats: off: " .. Floats(tv)); CircletDB.targetHpFloat = true
Fire("UNIT_COMBAT", "target", "WOUND", "", 55, 1); Advance(0.05); Fire("PLAYER_TARGET_CHANGED"); Advance(0.05); P("floats: new target clears them: " .. Floats(tv))
Advance(2); issecretvalue = realSecret
UNITS.target.class = nil; Advance(0.3)
CircletDB.playerHpShow = "combat"; Advance(2)

-- Target of target: a small ring for who your target is after; no events, so it keeps checking.
UNITS.target = { hp = 600, max = 1200, power = 50, pmax = 100, ptype = 0, token = "MANA", name = "Kobold", level = 5, reaction = 2 }
UNITS.targettarget = { hp = 300, max = 1000, power = 200, pmax = 400, ptype = 0, token = "MANA", name = "Jaina", level = 20, player = true }
Advance(0.5); P("target of target: " .. C("totHp"))
UNITS.targettarget.hp = 700; Advance(1); P("  its health changed (no event): " .. C("totHp"))
UNITS.targettarget = nil; Advance(2); P("  target has no target: " .. C("totHp"))
UNITS.target = nil; Advance(2)
TargetFrameToT = CreateFrame("Frame", "TargetFrameToT"); CircletDB.totHpHideDefault = true; Advance(0.3)
P("target of target frame hidden: alpha " .. TargetFrameToT:GetAlpha()); CircletDB.totHpHideDefault = false; Advance(0.3)

-- Buffs and debuffs in an arc round the target ring: debuffs on the inner row, buffs outside.
AURAS = { target = { HARMFUL = { { icon = 136118, applications = 3, dispelName = "Magic", duration = 10, expirationTime = GetTime() + 6, auraInstanceID = 11 } },
                     HELPFUL = { { icon = 135987, duration = 0, expirationTime = 0, auraInstanceID = 12 }, { icon = 136085, auraInstanceID = 13 } } } }
local mockAuras = C_UnitAuras
C_UnitAuras = { GetAuraDataByIndex = function(u, i, f)
  local kind = f:find("HARMFUL") and "HARMFUL" or "HELPFUL"
  if f:find("PLAYER") then return nil end -- none of these are yours
  local l = AURAS[u] and AURAS[u][kind]; return l and l[i] or nil end }
DebuffTypeColor = { Magic = { r = 0.2, g = 0.6, b = 1 } }
UNITS.target = { hp = 600, max = 1200, power = 50, pmax = 100, ptype = 0, token = "MANA", name = "Kobold", level = 5, reaction = 2 }
CircletDB.targetHpShow = "always"; Fire("PLAYER_TARGET_CHANGED"); Advance(1.2)
local AV = Ring("targetHp").vit.auras
local function Auras()
  local t, rows = {}, AV.rows and #AV.rows or 0
  for _, b in ipairs(AV.icons) do if b._shown then t[#t + 1] = "[" .. tostring(b.count._text) .. "]" end end
  return #t .. " shown in " .. rows .. " row(s) " .. table.concat(t, "")
end
P("target auras: " .. Auras())
CircletDB.targetHpAuraShow = "debuffs"; Advance(1.2); P("  debuffs only: " .. Auras())
CircletDB.targetHpAuraShow = "both"; CircletDB.targetHpAuraMine = true; Advance(1.2); P("  only yours: " .. Auras())
CircletDB.targetHpAuraMine = false; CircletDB.targetHpAuras = false; Advance(0.3); P("  off: " .. Auras())
CircletDB.targetHpAuras = true; Advance(1.2)
P("aura defaults: you " .. tostring(CircletDB.playerHpAuras) .. ", target " .. tostring(CircletDB.targetHpAuras) .. ", direction " .. tostring(CircletDB.targetHpAuraDir))
-- Spacing: the gap between neighbouring icons (edge to edge, along the arc) and between rows.
local function Spacing()
  local row1, row2 = AV.rows[1], AV.rows[2]
  local function xy(b) return b._pt[3], b._pt[4] end
  local function dist(a, b) local ax, ay = xy(a); local bx, by = xy(b); return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
  local s = row1[1]._w or 0
  local function rad(b) local x, y = xy(b); return math.sqrt(x * x + y * y) end
  local pair = (#row1 >= 2 and row1) or row2
  return string.format("icons %.0f apart (size %d), rows %.0f apart", dist(pair[1], pair[2]), s, rad(row2[1]) - rad(row1[1]))
end
P("aura spacing, default: " .. Spacing())
CircletDB.targetHpAuraGap = 10; CircletDB.targetHpAuraRowGap = 20; Advance(0.1)
P("aura spacing, 10 / 20: " .. Spacing())
CircletDB.targetHpAuraGap = 0; CircletDB.targetHpAuraRowGap = 0; Advance(0.1)
P("aura spacing, 0 / 0: " .. Spacing())
CircletDB.targetHpAuraGap = 2; CircletDB.targetHpAuraRowGap = 2; Advance(0.1)
C_UnitAuras = mockAuras; UNITS.target = nil; Advance(1)

-- Hide the game's frames.
PlayerFrame = CreateFrame("Frame", "PlayerFrame"); TargetFrame = CreateFrame("Frame", "TargetFrame")
CircletDB.playerHpHideDefault = true; Advance(0.3)
P("player frame alpha " .. PlayerFrame:GetAlpha() .. ", target frame alpha " .. TargetFrame:GetAlpha())
CircletDB.playerHpHideDefault = false; Advance(0.3); P("player frame back: " .. PlayerFrame:GetAlpha())
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
