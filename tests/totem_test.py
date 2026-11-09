import math
from lupa import LuaRuntime
from PIL import Image, ImageDraw
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end
UnitClass = function() return "Shaman", "SHAMAN" end
TOTEMS = {}
GetTotemInfo = function(slot) local t = TOTEMS[slot]; if t then return true, t.name, t.start, t.dur, t.icon end return false, "", 0, 0, nil end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end; RegionMethods.EnableMouse = function(s, v) s._mouse = v end')
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", lua.table())
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function Totems() local t = {} for _, f in ipairs(allFrames) do if f.sqKey and f.sqKey:match("^totem") and f._shown then
  local n = 0 for _, l in ipairs(f.fill) do if l._shown ~= false and l._x1 then n = n + 1 end end
  table.insert(t, string.format("%s x=%s [%s] fill=%d", f.sqKey, tostring(f._pt and math.floor(f._pt.x) or "?"), T(f), n)) end end table.sort(t) return t end
function D(l) P(l) for _, x in ipairs(Totems()) do P("   " .. x) end end
D("none down:")
TOTEMS[1] = { name = "Searing Totem", start = NOW, dur = 30, icon = 135825 }
TOTEMS[2] = { name = "Stoneskin Totem", start = NOW, dur = 120, icon = 136098 }
Advance(1); D("fire + earth:")
Advance(22); D("fire at ~7s (pulsing):")
Advance(8); D("fire expired:")
Slash("totems"); Advance(1); D("preview:")
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
