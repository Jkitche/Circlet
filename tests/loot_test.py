from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end
-- Loot rolls: rollID -> { name, count, quality, ends (NOW when time runs out) }
ROLLS = {}
function GetLootRollItemInfo(id) local r = ROLLS[id]; if r then return 132300, r.name, r.count or 1, r.quality end end
function GetLootRollTimeLeft(id) local r = ROLLS[id]; return r and math.max(0, (r.ends - NOW) * 1000) or 0 end
function RollOnLoot(id, rollType) end
hooksecurefunc = hooksecurefunc or function(name, fn) local orig = _G[name]; _G[name] = function(...) orig(...) fn(...) end end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end; RegionMethods.EnableMouse = function(s, v) s._mouse = v end')
# Remember every texture and the frame it's on, to find the dice badge.
lua.execute('TEXS = {}; local ct = RegionMethods.CreateTexture; RegionMethods.CreateTexture = function(self, ...) local t = ct(self, ...); t._parent = self; table.insert(TEXS, t); return t end')
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", lua.table())
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD"); Advance(1)
local F; for _, f in ipairs(allFrames) do if f.sqKey == "loot" then F = f end end
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
-- The dice badge: a texture on a shown frame of the ring (the badge is a child frame) showing dice.
function Dice() for _, t in ipairs(TEXS) do local p = t._parent
  if p and (p == F or p._parent == F) and p._shown ~= false and t._texpath and tostring(t._texpath):match("Dice") then
    return tostring(t._texpath) end end return "none" end
function S(l) local n = 0 for _, x in ipairs(F.fill) do if x._shown ~= false and x._x1 then n = n + 1 end end
  P(string.format("%-28s shown=%s fill=%2d | %s | dice: %s", l, tostring(F._shown), n, T(F), F._shown and Dice() or "-")) end
function Start(id, name, quality, secs, count) ROLLS[id] = { name = name, quality = quality, ends = NOW + secs, count = count }; Fire("START_LOOT_ROLL", id, secs * 1000) end
function End(id) ROLLS[id] = nil; Fire("CANCEL_LOOT_ROLL", id) end

S("idle")
Start(1, "Cape of the Black Baron", 3, 60); Advance(1); S("rare up, 1s")
Advance(29); S("halfway")
Start(2, "Linen Cloth", 1, 60, 4); Advance(1); S("second roll comes up")
RollOnLoot(1, 1); Advance(0.5); S("rolled Need on the cape")
RollOnLoot(2, 0); Advance(0.5); S("passed on the cloth")
Advance(20); S("cape, 8s left (warning)")
End(1); End(2); Advance(2); S("rolls over (faded)")
-- Time runs out with no word from the game: gone a moment later.
Start(3, "Ironfoe", 4, 5); Advance(3); S("epic, 2s left")
Advance(2.5); S("time up, not cancelled yet")
Advance(4); S("never cancelled: gone")
-- All cancelled at once (left the group, say).
Start(4, "Black Lotus", 2, 60); Start(5, "Arcanite Bar", 2, 60); Advance(1); S("two up")
Fire("CANCEL_ALL_LOOT_ROLLS"); Advance(2); S("all cancelled (faded)")
-- Quality colors off: the plain fill color; in combat it still shows.
CircletDB.lootQuality = false; IN_COMBAT = true; Fire("PLAYER_REGEN_DISABLED")
Start(6, "Ironfoe", 4, 60); Advance(1); S("quality colors off, in combat")
End(6); Fire("PLAYER_REGEN_ENABLED"); IN_COMBAT = false; Advance(1)
-- Turned off: nothing.
CircletDB.lootEnabled = false; Start(7, "Ironfoe", 4, 60); Advance(1); S("ring off")
End(7); CircletDB.lootEnabled = true
Slash("loot"); Advance(1); S("preview")
Advance(8); S("preview, rolled")
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
