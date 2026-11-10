from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
AURAS = {} -- the player's buffs: { name, icon, duration, expirationTime }
C_UnitAuras = { GetAuraDataByIndex = function(u, i, f) return AURAS[i] end }
function Buff(name, dur) table.insert(AURAS, { name = name, icon = 135805, duration = dur, expirationTime = dur and NOW + dur or 0 }); Fire("UNIT_AURA", "player") end
function Drop(name) for i = #AURAS, 1, -1 do if AURAS[i].name == name then table.remove(AURAS, i) end end; Fire("UNIT_AURA", "player") end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end')
NSX = lua.table(); lua.globals().NS = NSX; lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function Ring() for _, f in ipairs(allFrames) do if f.editHint and f._shown and (T(f):match("Resting") or T(f):match("Campfire")) then return f end end end
function C() local f = Ring() return f and T(f) or "(hidden)" end
function Fill() local r = Ring() local n = 0 for _, l in ipairs(ALL_LINES) do if r and l._parent == r and l._layer == "ARTWORK" and l._sub == 0 and l._shown then n = n + 1 end end return n end

P("nothing: " .. C())
Buff("Welcoming Campfire", 60); Advance(1); P("sat down: " .. C() .. " fill=" .. Fill())
Advance(29); P("30s: " .. C() .. " fill=" .. Fill())
Advance(29.5); Drop("Welcoming Campfire"); Buff("Well Rested", 3600); Advance(0.5); P("rested: " .. C() .. " fill=" .. Fill())
Advance(4); P("after a few seconds: " .. C()); Advance(4); P("gone: " .. C())
Drop("Well Rested")
Buff("Welcoming Campfire", 60); Advance(20); Drop("Welcoming Campfire"); Advance(0.5); P("stood up early: " .. C()); Advance(5); P("faded: " .. C())
Buff("Welcoming Campfire", 60); Advance(59); Buff("Well Rested", 3600); Advance(0.5); P("rested while the timer's still on: " .. C()); Advance(5)
Drop("Welcoming Campfire"); Advance(1); P("then it ends: " .. C()); Drop("Well Rested"); Advance(4)
Buff("Well Rested", 3600); Advance(1); P("sleeping bag's Well Rested alone: " .. C()); Drop("Well Rested"); Advance(4)
-- The buff's times secret: timed from when it showed up, over a minute.
SECRET = {}; issecretvalue = function(v) return v == SECRET end
AURAS[1] = { name = "Welcoming Campfire", icon = 135805, duration = SECRET, expirationTime = SECRET }; Fire("UNIT_AURA", "player")
Advance(1); P("secret times 1s: " .. C()); Advance(29); P("secret times 30s: " .. C() .. " fill=" .. Fill())
Drop("Welcoming Campfire"); Advance(5); issecretvalue = nil
CircletDB.campEnabled = false; Buff("Welcoming Campfire", 60); Advance(1); P("ring off: " .. C()); Drop("Welcoming Campfire"); CircletDB.campEnabled = true; Advance(4)
Slash("camp"); Advance(1); P("preview: " .. C()); Advance(8.5); P("preview 9.5s: " .. C()); Advance(12)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
