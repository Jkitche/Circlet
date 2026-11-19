# Crafting animations: the profession comes from the open trade skill window, and each one draws.
from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute(r'''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
hooksecurefunc = function(a, b, c)
  if type(a) == "table" then local orig = a[b]; a[b] = function(...) orig(...) c(...) end
  else local orig = _G[a]; _G[a] = function(...) orig(...) b(...) end end
end
C_TradeSkillUI = { CraftRecipe = function(recipeID, count) end }
PROF = "Alchemy"
GetTradeSkillLine = function() return PROF, 100, 300 end
DoCraft = function(index) end
GetCraftDisplaySkillLine = function() return "Enchanting", 50, 300 end
CAST = nil
function UnitCastingInfo() if CAST then return CAST.name, "", 0, CAST.s * 1000, CAST.e * 1000, false, "g", false, CAST.id end end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end')
NSX = lua.table(); lua.globals().NS = NSX
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute(r'''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function Fx()
  local p = NS.CraftFxParts(); if not p then return "fx none" end
  local out = {}
  for _, k in ipairs({ "glow", "star", "dot", "puff", "line", "spark" }) do
    local n = 0 for _, t in ipairs(p[k]) do if t._shown then n = n + 1 end end
    if n > 0 then table.insert(out, k .. "=" .. n) end
  end
  if p.tool._shown then table.insert(out, "tool") end
  return #out > 0 and table.concat(out, " ") or "nothing"
end
function Cast() CAST = { name = "Thing", s = NOW, e = NOW + 1.5, id = 999 }; Fire("UNIT_SPELLCAST_START", "player", "g", 999) end
function Done() CAST = nil; Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 999) end
for _, prof in ipairs({ "Alchemy", "Blacksmithing", "Engineering", "Enchanting", "Tailoring", "Leatherworking", "Cooking",
                        "First Aid", "Mining", "Poisons", "Fishing" }) do
  PROF = prof
  C_TradeSkillUI.CraftRecipe(1, 3)
  Cast(); Advance(1.1); local mid = Fx()
  Advance(0.4); Done(); Advance(0.1); local pop = Fx()
  Cast(); Advance(1.5); Done(); Cast(); Advance(1.5); Done(); Advance(0.3); local burst = Fx()
  Advance(5)
  P(prof .. ": crafting " .. mid .. " | item made " .. pop .. " | done " .. burst .. " | after " .. Fx())
end
-- Stopped partway: the effect fades out, no burst.
PROF = "Tailoring"; C_TradeSkillUI.CraftRecipe(1, 3); Cast(); Advance(1.5); Done(); Cast(); Advance(0.5)
CAST = nil; Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "g", 999); Advance(0.2); P("stopped: " .. Fx()); Advance(1); P("stopped 1.2s: " .. Fx()); Advance(5)
-- The older Craft window (Enchanting).
DoCraft(3); Cast(); Advance(1); P("DoCraft enchanting: " .. Fx()); Advance(0.5); Done(); Advance(5)
CircletDB.craftFx = false; PROF = "Alchemy"; C_TradeSkillUI.CraftRecipe(1, 2); Cast(); Advance(1); P("fx off: " .. Fx()); Advance(0.5); Done(); Cast(); Advance(1.5); Done(); Advance(5); CircletDB.craftFx = true
-- The preview runs every profession in turn without errors.
Slash("craft"); Advance(1); P("preview: " .. Fx()); Advance(9 * 12)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
