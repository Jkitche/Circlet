from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
UnitClass = function() return "Shaman", "SHAMAN", 7 end
local origTex = RegionMethods.CreateTexture
RegionMethods.CreateTexture = function(self, ...) local t = origTex(self, ...); t._parent = self; ALL_TEX = ALL_TEX or {}; table.insert(ALL_TEX, t); return t end
RegionMethods.SetTexture = function(s, t) s._tex = t end
local names = { [8024] = "Flametongue Weapon", [8027] = "Flametongue Weapon", [8017] = "Rockbiter Weapon",
  [8033] = "Frostbrand Weapon", [8232] = "Windfury Weapon", [403] = "Lightning Bolt" }
GetSpellInfo = function(id) return names[id] end
ENCH = nil -- { left seconds, enchantID }; nil: none
SECRETW = false
issecretvalue = function(v) return v == "SECRET" end
GetWeaponEnchantInfo = function()
  if SECRETW then return "SECRET", "SECRET", 0, "SECRET" end
  if not ENCH then return false end
  return true, math.floor((ENCH.endsAt - NOW) * 1000), 0, ENCH.id end
TOOLTIP = nil
C_TooltipInfo = { GetInventoryItem = function() if TOOLTIP then return { lines = { { leftText = "Grizzled Axe" }, { leftText = TOOLTIP } } } end end }
local n = 0
function Cast(id) n = n + 1; Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. n, id) end
function Imbue(secs, id) ENCH = { endsAt = NOW + secs, id = id } end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end')
NSX = lua.table(); lua.globals().NS = NSX; lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function Ring() for _, f in ipairs(allFrames) do if f.sqKey == "imbue" and f._shown and f._alpha > 0 then return f end end end
function Fill(f) local n = 0; if f then for _, l in ipairs(f.fill) do if l._shown ~= false and l._x1 then n = n + 1 end end end return n end
-- What the animation is drawing: textures on the ring frame that are shown, by texture file.
function Fx(f)
  if not f then return "" end
  local counts = {}
  for _, t in ipairs(ALL_TEX or {}) do
    if t._parent == f and t._shown and t._tex and (t._alpha or 1) > 0 then
      local k = tostring(t._tex):match("([^\\\\]+)$")
      if k and k:match("^Rock%d$") then k = "Rock" end
      if k == "star4" or k == "GenericGlow64" or k == "Rock" then counts[k] = (counts[k] or 0) + 1 end
    end
  end
  local out = {}
  for _, k in ipairs({ "GenericGlow64", "star4", "Rock" }) do if counts[k] then table.insert(out, k .. "=" .. counts[k]) end end
  return " fx[" .. table.concat(out, " ") .. "]"
end
function C() local f = Ring() return f and (T(f) .. " fill=" .. Fill(f) .. Fx(f)) or "(hidden)" end

P("no imbue: " .. C())
Imbue(300, 5); Advance(1.2); P("Flametongue (known enchant): " .. C())
Advance(120); P("2 minutes on: " .. C())
Cast(8017); Imbue(300, 29); Advance(1.2); P("Rockbiter cast over it: " .. C())
Cast(8033); Imbue(300, 9999); Advance(1.2); P("Frostbrand, unknown enchant (learned from the cast): " .. C())
ENCH = nil; Advance(1.2); P("removed: " .. C())
Advance(5); Imbue(300, 9999); Advance(1.2); P("same enchant again, no cast (learned): " .. C())
ENCH = nil; Advance(6)
TOOLTIP = "Windfury 3 (5 min)"; Imbue(300, 7777); Advance(1.2); P("unknown, from the tooltip: " .. C())
ENCH.endsAt = NOW + 25; Advance(1.2); P("last 25s: " .. C())
SECRETW = true; Advance(10); P("hidden in combat, clock runs: " .. C())
SECRETW = false; Advance(16); P("ran out: " .. C())
Advance(5); P("then: " .. C())
CircletDB.imbueAlways = false; Imbue(300, 5); Advance(1.2); P("just put on, always off: " .. C())
Advance(10); P("mid-way, always off: " .. C()); CircletDB.imbueAlways = true
CircletDB.imbueFx = false; Advance(1.2); P("animations off: " .. C()); CircletDB.imbueFx = true
ENCH = nil; Advance(6)
Slash("imbue"); Advance(1); P("preview: " .. C()); Advance(4); P("preview: " .. C()); Advance(4); P("preview: " .. C()); Advance(4); P("preview: " .. C()); Advance(6)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
