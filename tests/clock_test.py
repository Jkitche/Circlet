import math
from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
-- A fixed clock: Friday 13 November 2026, 18:29:40 on the computer; the realm runs 3 hours ahead.
EPOCH = os.time({ year = 2026, month = 11, day = 13, hour = 18, min = 29, sec = 40 })
date = function(f, t) return os.date(f, t or (EPOCH + math.floor(NOW))) end
REALM_AHEAD = 3
GetGameTime = function() local t = os.date("*t", EPOCH + math.floor(NOW)); return (t.hour + REALM_AHEAD) % 24, t.min end
ALL_TEX = {}
local ct = RegionMethods.CreateTexture
RegionMethods.CreateTexture = function(self, ...) local t = ct(self, ...); t._parent = self; table.insert(ALL_TEX, t); return t end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end')
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", lua.table())
lua.execute('''
NOW = 0
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function Ring() for _, f in ipairs(allFrames) do if f.sqKey == "clock" and f._shown then return f end end end
function Face()
  local f = Ring(); if not f then return "(hidden)" end
  local fill, ticks = 0, 0
  for _, l in ipairs(f.fill) do if l._shown ~= false and l._x1 then fill = fill + 1 end end
  for _, l in ipairs(ALL_LINES) do if l._parent == f and l._layer == "OVERLAY" and l._shown then ticks = ticks + 1 end end
  local dot = "-"
  for _, t in ipairs(ALL_TEX) do if t._parent == f and t._shown and t._pt and t._pt.x then -- the dot (and its rim and glow)
    -- which way the dot is from the centre, as a clock position
    local a = math.atan(t._pt.x, t._pt.y); if a < 0 then a = a + 2 * math.pi end
    dot = string.format("%.1f o'clock", a / (2 * math.pi) * 12) end end
  return T(f) .. " | fill=" .. fill .. " ticks=" .. ticks .. " hour dot at " .. dot
end
P("off by default: " .. Face())
CircletDB.clockEnabled = true; Advance(1.5); P("on: " .. Face())
Advance(30); P("half a minute on: " .. Face())
CircletDB.clock24 = true; Advance(0.5); P("24-hour: " .. Face())
CircletDB.clockRealm = true; Advance(0.5); P("realm time (+3h): " .. Face())
CircletDB.clock24, CircletDB.clockRealm = false, false
CircletDB.clockTicks = false; Advance(0.5); P("ticks off: " .. Face())
CircletDB.clockTicks = true
NOW = NOW + 3600 * 6 - 1800; Advance(0.5); P("six hours later: " .. Face())
CircletDB.clockEnabled = false; Advance(2); P("turned off: " .. Face())
Slash("clock"); Advance(1); P("preview while off: " .. Face()); Advance(9); P("preview over: " .. Face())
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
