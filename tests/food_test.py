from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
AURAS = {} -- the player's buffs: { name, icon, duration, expirationTime }
C_UnitAuras = { GetAuraDataByIndex = function(u, i, f) return AURAS[i] end }
C_Spell = C_Spell or {}
C_Spell.GetSpellName = function(id) return ({ [433] = "Food", [430] = "Drink" })[id] end
function Buff(name, dur) table.insert(AURAS, { name = name, icon = 133945, duration = dur, expirationTime = NOW + dur }); Fire("UNIT_AURA", "player") end
function Unbuff() wipe(AURAS); Fire("UNIT_AURA", "player") end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end')
NSX = lua.table(); lua.globals().NS = NSX; lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function Ring() for _, f in ipairs(allFrames) do if f.editHint and f._shown and T(f):match("ating") or (f.editHint and f._shown and T(f):match("rinking")) then return f end end end
-- What's animating: crumbs (square textures), bubbles (frames with lines + glint), ripple lines.
function Fx()
  local water = 0
  local r = Ring()
  for _, l in ipairs(ALL_LINES) do if r and l._parent == r and l._layer == "BORDER" and l._shown then water = water + 1 end end
  return "water=" .. (water > 0 and "yes" or "no")
end
function C() local f = Ring() return f and T(f) or "(hidden)" end

function Fill() local r = Ring() local n = 0 for _, l in ipairs(ALL_LINES) do if r and l._parent == r and l._layer == "ARTWORK" and l._sub == 0 and l._shown then n = n + 1 end end return n end
function Level() local r = Ring() local top for _, l in ipairs(ALL_LINES) do if r and l._parent == r and l._layer == "BORDER" and l._shown and l._y2 then top = math.max(top or -999, l._y2) end end return top and string.format("%.0f", top) or "-" end
P("not eating: " .. C())
Buff("Food", 20); Advance(1); P("eating 1s: " .. C() .. " fill=" .. Fill() .. " " .. Fx())
Advance(9); P("eating 10s: " .. C() .. " fill=" .. Fill())
Advance(9.5); P("eating 19.5s: " .. C() .. " fill=" .. Fill())
Unbuff(); Advance(0.5); P("buff gone: " .. C()); Advance(4); P("after the hold: " .. C())
Buff("Food", 20); Advance(5); Unbuff(); Advance(0.5); P("stood up early: " .. C()); Advance(4)
Buff("Drink", 20); Advance(1); P("drinking 1s: " .. C() .. " water top=" .. Level() .. " " .. Fx())
Advance(9); P("drinking 10s: water top=" .. Level())
Advance(8); P("drinking 18s: water top=" .. Level())
Unbuff(); Advance(4)
Buff("Food", 30); Advance(10); Buff("Drink", 30); Advance(6); P("both (drink started later): " .. C() .. " " .. Fx())
CircletDB.foodFx = false; Advance(0.2); P("animations off: " .. Fx())
CircletDB.foodFx = true; Unbuff(); Advance(4)
Buff("Mark of the Wild", 1800); Advance(1); P("another buff: " .. C()); Unbuff(); Advance(1)
CircletDB.foodEnabled = false; Buff("Food", 18); Advance(1); P("ring off: " .. C()); Unbuff(); CircletDB.foodEnabled = true; Advance(4)
-- The buff's times secret too: timed from when it showed up, over a usual 24 seconds.
SECRET = {}; issecretvalue = function(v) return v == SECRET end
AURAS[1] = { name = "Food", icon = 133945, duration = SECRET, expirationTime = SECRET }; Fire("UNIT_AURA", "player")
Advance(1); P("secret times, eating 1s: " .. C())
Advance(11); P("secret times, eating 12s: " .. C() .. " fill=" .. Fill())
Unbuff(); Advance(4); issecretvalue = nil

Slash("food"); Advance(1); P("preview: " .. C() .. " " .. Fx()); Advance(7); P("preview 8s: " .. C()); Advance(14)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
