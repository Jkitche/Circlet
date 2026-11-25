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
UNITS.player = { hp = 900, max = 1000, power = 60, pmax = 100, ptype = 3, token = "ENERGY", name = "Valeera", level = 20, player = true, class = "ROGUE" }
CP, MARKS, CLASSIF = 0, {}, {}
GetComboPoints = function() return CP end
GetRaidTargetIndex = function(u) return MARKS[u] end
UnitCanAttack = function(_, u) return UNITS[u] ~= nil and not UNITS[u].friend end
UnitIsUnit = function(a, b) if a == "targettarget" and b == "player" then return UNITS.target and UNITS.target.onMe or false end return a == b end
UnitClassification = function(u) return CLASSIF[u] or "normal" end
UnitIsGhost = function(u) return UNITS[u] and UNITS[u].ghost or false end
JOLT = {}
RegionMethods.AdjustPointsOffset = function(s, x, y) JOLT[#JOLT + 1] = string.format("%.1f,%.1f", x, y) end
RegionMethods.ClearPointsOffset = function(s) end
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
        if issecretvalue(a) then table.insert(out, name .. "<" .. tostring(a.v) .. ">")
        elseif (a or 1) > 0.01 then table.insert(out, name) end
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
CLASSIF.target = "elite"; Advance(0.3); P("elite: " .. Fx("targetHp")); CLASSIF.target = nil
UNITS.target.hp = 150; Advance(0.3); P("target at 15%: " .. Fx("targetHp"))
SECRET = true; Advance(0.3); P("  hidden, 15%: " .. Fx("targetHp"))
UNITS.target.hp = 500; Advance(0.3); P("  hidden, 50%: " .. Fx("targetHp")); SECRET = false
Fire("UNIT_COMBAT", "target", "HEAL", "", 50, 2); Advance(0.2); P("heal on target: " .. Fx("targetHp")); Advance(1)
Fire("UNIT_COMBAT", "target", "BLOCK", "", 0, 1); Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1); Fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1)
Advance(0.1); P("block, dodge, parry: " .. Fx("targetHp")); Advance(1)
JOLT = {}; Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 300, 1); Advance(0.3)
P("crit jolt: " .. #JOLT .. " nudges, first " .. tostring(JOLT[1]))
UNITS.target.dead = true; UNITS.target.hp = 0; Advance(0.6); P("target dead: " .. Fx("targetHp"))
UNITS.target.dead = false; UNITS.target.hp = 800; Advance(0.3)
-- Your ring.
P("you (rogue, energy), no tick seen: " .. Fx("playerHp"))
Fire("UNIT_POWER_FREQUENT", "player", "ENERGY"); Advance(0.1); P("energy tick: " .. Fx("playerHp")); Advance(0.6)
P("  0.7s on: " .. Fx("playerHp"))
local _, tick = NS.VitalsFxState()
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 1752); Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
local _, tick2 = NS.VitalsFxState(); P("  energy spent by a cast isn't a tick: " .. tostring(tick == tick2))
Fire("PLAYER_REGEN_DISABLED"); COMBAT = true; Advance(0.1); P("combat starts: " .. Fx("playerHp")); Advance(1)
UNITS.player.hp = 200; Advance(0.1); P("you at 20%: " .. Fx("playerHp"))
SECRET = true; Advance(0.1); P("  hidden: " .. Fx("playerHp")); SECRET = false; UNITS.player.hp = 900; Advance(0.1)
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
CircletDB.targetHpFxJolt = false; JOLT = {}; Fire("UNIT_COMBAT", "target", "WOUND", "CRUSHING", 300, 1); Advance(0.3); P("jolt off: " .. #JOLT .. " nudges")
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
