from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
SPEED = 2.8; MOVING = 0
UnitRangedDamage = function() return SPEED end
GetUnitSpeed = function() return MOVING end
GetInventoryItemTexture = function() return "Interface\\\\Icons\\\\INV_Weapon_Bow_02" end
local names = { [75] = "Auto Shot", [5019] = "Shoot", [19434] = "Aimed Shot", [2643] = "Multi-Shot" }
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
function Ring() for _, f in ipairs(allFrames) do if f.sqKey == "shot" and f._shown and f._alpha > 0 then return f end end end
function Fill(f) local n = 0; if f then for _, l in ipairs(f.fill) do if l._shown ~= false and l._x1 then n = n + 1 end end end return n end
function Col(f) if not f then return "" end for _, l in ipairs(f.fill) do if l._shown ~= false and l._c then return string.format(" color=%.2f,%.2f,%.2f", l._c[1], l._c[2], l._c[3]) end end return "" end
function C() local f = Ring() return f and (T(f) .. " fill=" .. Fill(f) .. Col(f)) or "(hidden)" end

P("idle: " .. C())
Fire("START_AUTOREPEAT_SPELL"); Advance(0.2); P("Auto Shot on: " .. C())
Cast(75); Advance(1); P("1s after a shot: " .. C())
Advance(1.5); P("aiming: " .. C())
MOVING = 7; Advance(0.1); P("moving while aiming: " .. C())
Advance(0.5); P("held back (still moving): " .. C()); MOVING = 0
Cast(75); Advance(0.5); P("next shot: " .. C())
CastTime(19434, 3); Advance(0.1); P("after Aimed Shot: " .. C())
n = 0; Fire("UNIT_SPELLCAST_START", "player", "x", 19434); Advance(1); P("during Aimed Shot: " .. C())
Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "x", 19434); Fire("UNIT_SPELLCAST_STOP", "player", "x", 19434); Advance(0.1); P("Aimed Shot interrupted: " .. C())
Cast(2643); Advance(0.2); P("Multi-Shot (instant): " .. C())
Fire("STOP_AUTOREPEAT_SPELL"); Advance(2); P("stopped: " .. C())
-- A wand: no aim.
SPEED = 1.6; Fire("START_AUTOREPEAT_SPELL"); Cast(5019); Advance(1.4); P("wand near the end: " .. C())
Fire("STOP_AUTOREPEAT_SPELL"); Advance(2)
CircletDB.shotAim = false; SPEED = 2.8; Fire("START_AUTOREPEAT_SPELL"); Cast(75); Advance(2.5); P("aim off: " .. C())
Fire("STOP_AUTOREPEAT_SPELL"); Advance(2); CircletDB.shotAim = true
CircletDB.shotEnabled = false; Fire("START_AUTOREPEAT_SPELL"); Cast(75); Advance(0.5); P("ring off: " .. C())
Fire("STOP_AUTOREPEAT_SPELL"); Advance(2); CircletDB.shotEnabled = true
Slash("shot"); Advance(1); P("preview: " .. C()); Advance(1.5); P("preview aiming: " .. C()); Advance(10)
-- Hiding the game's own swing timer bars (found by name), and the setting when there are none.
CVARS = { showSwingTimer = "1" }
C_CVar = { GetCVar = function(k) return CVARS[k] end, SetCVar = function(k, v) CVARS[k] = v end }
local function Bars() return string.format("melee a=%s ranged a=%s cvar=%s", tostring(MH and MH._alpha), tostring(RG and RG._alpha), CVARS.showSwingTimer) end
EnumerateFrames = function(prev) if NOFRAMES then return nil end
  local i = 0; if prev then for k, f in ipairs(allFrames) do if f == prev then i = k end end end
  local f = allFrames[i + 1]; return f end
RegionMethods.GetName = function(s) return s._name end
NOFRAMES = true
CircletDB.swingHideDefault = true; Advance(12); P("no bars found, hide melee: " .. Bars())
CircletDB.swingHideDefault = false; Advance(0.3); P("option off again: " .. Bars())
NOFRAMES = false
MH = CreateFrame("Frame"); MH._name = "ForeverSwingTimerMainHand"; MH._alpha = 1
RG = CreateFrame("Frame"); RG._name = "ForeverSwingTimerRangedBar"; RG._alpha = 1
CircletDB.swingHideDefault = true; Advance(6); P("bars found, hide melee: " .. Bars())
CircletDB.shotHideDefault = true; Advance(0.3); P("hide ranged too: " .. Bars())
CircletDB.swingHideDefault = false; CircletDB.shotHideDefault = false; Advance(0.3); P("both off: " .. Bars())
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
