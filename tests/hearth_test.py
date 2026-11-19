from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
GetBindLocation = function() return "Goldshire" end
CASTING = nil -- { start, finish } seconds while casting
UnitCastingInfo = function(u) if CASTING then return "Hearthstone", "", 134414, CASTING[1] * 1000, CASTING[2] * 1000 end end
local n = 0
function Start(id, len) n = n + 1; GUID = "Cast-" .. n; CASTING = { NOW, NOW + (len or 10) }; Fire("UNIT_SPELLCAST_START", "player", GUID, id) end
function Done(id) CASTING = nil; Fire("UNIT_SPELLCAST_SUCCEEDED", "player", GUID, id); Fire("UNIT_SPELLCAST_STOP", "player", GUID, id) end
function Interrupt(id) CASTING = nil; Fire("UNIT_SPELLCAST_INTERRUPTED", "player", GUID, id); Fire("UNIT_SPELLCAST_STOP", "player", GUID, id) end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end')
NSX = lua.table(); lua.globals().NS = NSX; lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function Ring(key) for _, f in ipairs(allFrames) do if f.sqKey == key and f._shown then return f end end end
function Fill(f) local n = 0; if f then for _, l in ipairs(f.fill) do if l._shown ~= false and l._x1 then n = n + 1 end end end return n end
function C(key) local f = Ring(key or "hearth") return f and (T(f) .. " fill=" .. Fill(f)) or "(hidden)" end
function Fx()
  local p = NS.HearthFxParts(); if not p then return "fx none" end
  local m, c = 0, 0
  for _, x in ipairs(p.motes) do if x.tex._shown then m = m + 1 end end
  for _, x in ipairs(p.comets) do for _, t in ipairs(x.parts) do if t._shown then c = c + 1 end end end
  return "motes=" .. m .. " comet parts=" .. c .. " wave=" .. tostring(p.wave._shown and true or false)
end

P("nothing: " .. C())
Start(8690); Advance(2); P("2s into Hearthstone: " .. C() .. " | " .. Fx())
P("cast ring meanwhile: " .. C("cast"))
Advance(8); Done(8690); Advance(0.5); P("went off: " .. C() .. " | " .. Fx())
Advance(3); P("later: " .. C())
Start(8690); Advance(4); Interrupt(8690); Advance(0.3); P("interrupted: " .. C())
Advance(3); P("faded: " .. C())
Start(556, 10); Advance(3); P("Astral Recall: " .. C()); Advance(7); Done(556); Advance(3)
-- Off: the cast ring shows it instead.
CircletDB.hearthEnabled = false; Start(8690); Advance(2); P("ring off: " .. C() .. " | cast ring: " .. C("cast")); Interrupt(8690); Advance(3); CircletDB.hearthEnabled = true
CircletDB.hearthFx = false; Start(8690); Advance(2); P("fx off: " .. Fx()); Interrupt(8690); Advance(3); CircletDB.hearthFx = true
-- Another spell isn't a Hearthstone.
Start(2061, 1.5); Advance(1); P("Flash Heal: " .. C()); Done(2061); Advance(3)
Slash("hearth"); Advance(3); P("preview: " .. C()); Advance(5); P("preview 8s: " .. C()); Advance(10)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
