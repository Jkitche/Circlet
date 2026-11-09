from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end; RegionMethods.EnableMouse = function(s, v) s._mouse = v end')
import subprocess; subprocess.run(['python3','make_bundle.py'])
chunk = lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())
chunk("Circlet", lua.table())
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); XP = 300; XPMAX = 1000; Fire("PLAYER_ENTERING_WORLD"); Advance(1)
UIParent.GetEffectiveScale = function() return 0.8 end
-- the grid frame: one with many textures
function GridDebug() local t = {} for _, f in ipairs(allFrames) do if f.lines then table.insert(t, tostring(f._strata) .. ":" .. #f.lines .. ":" .. tostring(f._shown)) end end return table.concat(t, " ") end
function GridLines() local best, n = nil, 0
  for _, f in ipairs(allFrames) do if f.lines and f._strata == "LOW" then best = f end end
  if not best then return "no grid" end
  local shown = 0 for _, l in ipairs(best.lines) do if l._shown ~= false then shown = shown + 1 end end
  return string.format("grid shown=%s lines=%d", tostring(best._shown), shown) end
P("before edit: " .. GridLines() .. " snap=" .. tostring(CircletDB.snapGrid) .. " size=" .. tostring(CircletDB.gridSize))
 Slash("edit xp"); Advance(0.3)
local X
for _, f in ipairs(allFrames) do if f.editHint then for _, g in ipairs(ALL_FS) do if g._parent == f and tostring(g._text or ""):match("^Level") then X = f end end end end
P("editing: " .. GridLines() .. " | " .. GridDebug() .. " bar=" .. tostring(CircletEditModeFrame._shown))
-- drag: ring center at (960, 1080-40-70=970); grab at center; move cursor to (1213, 703)*scale
X._cx, X._cy = 960, 970
CURSOR_X, CURSOR_Y = 960 * 0.8, 970 * 0.8
X._scripts.OnDragStart(X)
CURSOR_X, CURSOR_Y = 1213 * 0.8, 703 * 0.8; Advance(0.1)
local p = X._points and X._points[1]
X._scripts.OnDragStop(X)
P(string.format("snapped drop: xpX=%s xpFromTop=%s  (center %d,%d from screen centre)", CircletDB.xpX, CircletDB.xpFromTop, CircletDB.xpX, 540 - (CircletDB.xpFromTop + 70)))
SHIFT = true
CURSOR_X, CURSOR_Y = 960*0.8, 970*0.8; X._cx, X._cy = 960, 970; X._scripts.OnDragStart(X); CURSOR_X, CURSOR_Y = 1213 * 0.8, 703 * 0.8; Advance(0.1); X._scripts.OnDragStop(X)
P(string.format("shift drop: xpX=%s xpFromTop=%s", CircletDB.xpX, CircletDB.xpFromTop))
SHIFT = false
CircletDB.gridSize = 50; Advance(0.5); P("grid 50: " .. GridLines())
CircletDB.snapGrid = false; Advance(0.5); P("snap off: " .. GridLines())
CircletDB.snapGrid = true; Slash("edit xp"); Advance(0.3); P("after edit off: " .. GridLines())
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
