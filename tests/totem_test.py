import math
from lupa import LuaRuntime
from PIL import Image, ImageDraw
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end
UnitClass = function() return "Shaman", "SHAMAN" end
TOTEMS = {}
GetTotemInfo = function(slot) local t = TOTEMS[slot]; if t then return true, t.name, t.start, t.dur, t.icon, nil, t.spell end return false, "", 0, 0, nil end
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
Advance(15); TOTEMS = {}; Advance(2)

-- Hidden times (in combat). HIDE: "all" hides everything; "times" says whether a totem is
-- there but hides its times.
SECRET = {}; issecretvalue = function(v) return v == SECRET end
HIDE = nil
GetTotemDuration = function(slot) return {} end
local gti = GetTotemInfo
GetTotemInfo = function(slot)
  if HIDE == "all" then return SECRET, SECRET, SECRET, SECRET, SECRET, SECRET, SECRET end
  local have = gti(slot)
  if HIDE == "times" then return have, SECRET, SECRET, SECRET, SECRET, SECRET, SECRET end
  return gti(slot)
end
function Cast(spellID) Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", spellID) end

-- 1. A totem we've never seen, dropped mid-fight: the game's own display.
IN_COMBAT = true; HIDE = "all"
Cast(8190); TOTEMS[1] = { name = "Magma Totem", start = NOW, dur = 20, icon = 135826 }; Fire("PLAYER_TOTEM_UPDATE", 1)
Advance(1); D("unlearned totem mid-fight (game's display):")
-- It's destroyed: no cast, so the slot clears.
TOTEMS[1] = nil; Fire("PLAYER_TOTEM_UPDATE", 1); Advance(1.5); D("destroyed mid-fight:")

-- 2. The stuck case: a totem expires just as you cast something else, so it looks like a new
-- totem; after the fight the game says the slot is empty but still hides its times.
Cast(8190); TOTEMS[1] = { name = "Magma Totem", start = NOW, dur = 20, icon = 135826 }; Fire("PLAYER_TOTEM_UPDATE", 1)
Advance(19.8); Cast(403); TOTEMS[1] = nil; Fire("PLAYER_TOTEM_UPDATE", 1); Advance(1); D("expired as you cast (looks new):")
IN_COMBAT = false; HIDE = "times"; Fire("PLAYER_REGEN_ENABLED"); Advance(2); D("after the fight, slot empty, times still hidden:")

-- 3. Times stay hidden and the slot's state can't be read at all: the fallback gives up
-- after the longest totem you've used.
HIDE = "all"; Cast(403); Fire("PLAYER_TOTEM_UPDATE", 1); Advance(1); D("hidden, looks new:")
Advance(130); D("130s later (nothing learned: kept up to 5 min):")
Advance(180); D("5 min later:")

-- 4. A learned totem cast mid-fight keeps its own countdown.
HIDE = nil; IN_COMBAT = false; TOTEMS[2] = { name = "Stoneskin Totem", start = NOW, dur = 120, icon = 136098, spell = 8071 }; Cast(8071); Fire("PLAYER_TOTEM_UPDATE", 2); Advance(1)
TOTEMS[2] = nil; Fire("PLAYER_TOTEM_UPDATE", 2); Advance(1)
HIDE = "all"; IN_COMBAT = true; Cast(8071); TOTEMS[2] = { name = "Stoneskin Totem", start = NOW, dur = 120, icon = 136098 }; Fire("PLAYER_TOTEM_UPDATE", 2)
Advance(5); D("learned totem mid-fight (own countdown):")
IN_COMBAT = false; HIDE = nil; issecretvalue = nil
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
