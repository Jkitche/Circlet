from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
SPEED = 3.3
UnitAttackSpeed = function() return SPEED end
GetInventoryItemTexture = function() return "Interface\\\\Icons\\\\INV_Axe_09" end
local names = { [8042] = "Earth Shock", [17364] = "Stormstrike", [10466] = "Lesser Healing Wave", [78] = "Heroic Strike", [285] = "Heroic Strike" }
GetSpellInfo = function(id) return names[id] end
local n = 0
function Hit(action, flag, school) Fire("UNIT_COMBAT", "target", action, flag or "", 25, school or 1) end
function Cast(id) n = n + 1; Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. n, id) end
function CastTime(id, secs) n = n + 1; Fire("UNIT_SPELLCAST_START", "player", "Cast-" .. n, id); Advance(secs)
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. n, id); Fire("UNIT_SPELLCAST_STOP", "player", "Cast-" .. n, id) end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end')
NSX = lua.table(); lua.globals().NS = NSX; lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function Ring() for _, f in ipairs(allFrames) do if f.sqKey == "swing" and f._shown and f._alpha > 0 then return f end end end
function Fill(f) local n = 0; if f then for _, l in ipairs(f.fill) do if l._shown ~= false and l._x1 then n = n + 1 end end end return n end
function C() local f = Ring() return f and (T(f) .. " fill=" .. Fill(f)) or "(hidden)" end

P("idle: " .. C())
Fire("PLAYER_ENTER_COMBAT"); Advance(0.2); P("auto-attack on, no swing yet: " .. C())
Hit("WOUND", "GLANCING"); Advance(1); P("1s after a glancing swing: " .. C())
Advance(2.2); P("3.2s: " .. C())
Advance(0.5); P("3.7s, out of range: " .. C())
Hit("WOUND"); Advance(0.05)
Cast(8042); Hit("WOUND", "", 8); Advance(0.5); P("Earth Shock (nature) 0.5s into a swing: " .. C())
Hit("DODGE"); Advance(0.3); P("someone else's hit too soon: " .. C())
Advance(2.6); Hit("DODGE"); Advance(0.3); P("dodged: " .. C())
Advance(1); Cast(17364); Hit("WOUND"); Advance(0.3); P("Stormstrike's hit isn't a swing: " .. C())
CastTime(10466, 1.5); Advance(0.3); P("after Lesser Healing Wave: " .. C())
n = 0; Fire("UNIT_SPELLCAST_START", "player", "x", 10466); Advance(0.5); P("while casting: " .. C())
Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "x", 10466); Fire("UNIT_SPELLCAST_STOP", "player", "x", 10466); Advance(0.3); P("interrupted: " .. C())
Advance(3.2); Hit("WOUND", "CRITICAL"); Advance(0.3); P("crit: " .. C())
-- Haste halfway through: 3.3 -> 2.2.
Advance(1.35); SPEED = 2.2; Fire("UNIT_ATTACK_SPEED", "player"); Advance(0.05); P("hasted halfway: " .. C())
SPEED = 3.3; Fire("UNIT_ATTACK_SPEED", "player")
Fire("PLAYER_LEAVE_COMBAT"); Advance(2); P("auto-attack off: " .. C())
-- A warrior's Heroic Strike is the swing.
SPEED = 2.6; Fire("PLAYER_ENTER_COMBAT"); Hit("WOUND"); Advance(2.7)
Cast(285); Hit("WOUND", "CRITICAL"); Advance(0.5); P("Heroic Strike (rank 2): " .. C())
Fire("PLAYER_LEAVE_COMBAT"); Advance(2)
CircletDB.swingResult = false; Fire("PLAYER_ENTER_COMBAT"); Hit("PARRY"); Advance(0.5); P("results off: " .. C())
Fire("PLAYER_LEAVE_COMBAT"); Advance(2); CircletDB.swingResult = true
CircletDB.swingEnabled = false; Fire("PLAYER_ENTER_COMBAT"); Hit("WOUND"); Advance(0.5); P("ring off: " .. C())
Fire("PLAYER_LEAVE_COMBAT"); Advance(2); CircletDB.swingEnabled = true
Slash("swing"); Advance(1.3); P("preview: " .. C()); Advance(2.6); P("preview later: " .. C()); Advance(12)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
