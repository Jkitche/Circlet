from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
hooksecurefunc = function(a, b, c)
  if type(a) == "table" then local orig = a[b]; a[b] = function(...) orig(...) c(...) end
  else local orig = _G[a]; _G[a] = function(...) orig(...) b(...) end end
end
C_TradeSkillUI = { CraftRecipe = function(recipeID, count) end }
CAST = nil
function UnitCastingInfo() if CAST then return CAST.name, "", 0, CAST.s * 1000, CAST.e * 1000, false, "g", false, CAST.id end end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end; RegionMethods.EnableMouse = function(s, v) s._mouse = v end')
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", lua.table())
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function C() for _, f in ipairs(allFrames) do if f.editHint and f.marker and f._shown then local n = 0 for _, l in ipairs(f.fill) do if l._shown ~= false and l._x1 then n = n + 1 end end return T(f) .. "  fillsegs=" .. n end end return "(hidden)" end
function Cast() CAST = { name = "Heavy Linen Bandage", s = NOW, e = NOW + 1.5, id = 7929 }; Fire("UNIT_SPELLCAST_START", "player", "g", 7929) end
function Done() CAST = nil; Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 7929) end
C_TradeSkillUI.CraftRecipe(123, 4)
for i = 1, 4 do Cast(); Advance(0.75); P("cast " .. i .. " halfway: " .. C()); Advance(0.75); Done(); Advance(0.05) end
P("after batch: " .. C()); Advance(4); P("4s later: " .. C())
P("session crafts: " .. tostring(select(2, next(CircletDB.sessions)).crafts))
-- interrupted batch
C_TradeSkillUI.CraftRecipe(123, 5); Cast(); Advance(1.5); Done(); Cast(); Advance(0.5); CAST = nil; Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "g", 7929); Advance(0.2)
P("interrupted: " .. C()); Advance(5); P("later: " .. C())
-- single craft: hidden by default
C_TradeSkillUI.CraftRecipe(123, 1); Cast(); Advance(0.7); P("single: " .. C()); Advance(1); Done(); Advance(4)
CircletDB.craftSingle = true; C_TradeSkillUI.CraftRecipe(123, 1); Cast(); Advance(0.7); P("single on: " .. C()); Advance(1); Done(); Advance(5)
Slash("craft"); Advance(2); P("preview: " .. C())
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
