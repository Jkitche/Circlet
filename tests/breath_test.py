from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
MT = {}
function GetMirrorTimerProgress(n) local t = MT[n]; if t then return math.max(0, t.v + t.s * (NOW - t.at) * 1000) end return 0 end
function GetMirrorTimerInfo(i) return "UNKNOWN", 0, 0, 0, 0, "" end
wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end')
NSX = lua.table(); lua.globals().NS = NSX; lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function C() for _, f in ipairs(allFrames) do if f.editHint and f.marker and f._shown then return T(f) end end return "(hidden)" end
function Bub() local n = 0 for _, f in ipairs(allFrames) do if f.lines and f.glint and f._shown then n = n + 1 end end return n end
function Start(n, v, m, s) MT[n] = { v = v, s = s, at = NOW }; Fire("MIRROR_TIMER_START", n, v, m, s, 0, n) end
Start("BREATH", 60000, 60000, -1); Advance(10); P("10s under: " .. C() .. " bubbles=" .. Bub())
Advance(35); P("45s under: " .. C()); Advance(7); P("52s: " .. C())
Start("BREATH", GetMirrorTimerProgress("BREATH"), 60000, 10); Advance(2); P("surfacing: " .. C() .. " bubbles=" .. Bub())
Advance(5); P("refilled: " .. C()); MT.BREATH = nil; Fire("MIRROR_TIMER_STOP", "BREATH"); Advance(4); P("after: " .. C())
Start("EXHAUSTION", 60000, 60000, -1); Advance(5); P("fatigue: " .. C() .. " bubbles=" .. Bub()); MT.EXHAUSTION = nil; Fire("MIRROR_TIMER_STOP", "EXHAUSTION"); Advance(4)
Start("FEIGNDEATH", 360000, 360000, -1); Advance(3); P("feign: " .. C()); MT.FEIGNDEATH=nil; Fire("MIRROR_TIMER_STOP", "FEIGNDEATH"); Advance(4)
Slash("breath"); Advance(1); P("preview: " .. C() .. " bubbles=" .. Bub()); Advance(12)
Slash("edit breath"); Advance(0.5); P("edit: " .. C()); Slash("edit breath"); Advance(3); P("done: " .. C() .. " bubbles=" .. Bub())
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
