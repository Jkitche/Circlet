from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end
-- A party of five: you (Kaladin) and party1..4. RAID switches to a raid of the same people.
RAID = false
function SetParty()
  UNITS = { party1 = { name = "Thrall", guid = "G1" }, party2 = { name = "Jaina", guid = "G2" },
            party3 = { name = "Rexxar", guid = "G3" }, party4 = { name = "Cairne", guid = "G4" } }
end
function SetRaid()
  UNITS = { raid1 = { name = "Kaladin", guid = "G0" }, raid2 = { name = "Thrall", guid = "G1" }, raid3 = { name = "Jaina", guid = "G2" } }
  UNITS.player = UNITS.raid1
end
SetParty()
function GetNumGroupMembers() if RAID then return 3 end return 5 end
function IsInRaid() return RAID end
local un = UnitName; function UnitName(u) if UNITS[u] then return UNITS[u].name end return un(u) end
CHECK_ENDS = nil
function GetReadyCheckTimeLeft() return CHECK_ENDS and math.max(0, math.floor(CHECK_ENDS - NOW)) or 0 end
function GetReadyCheckStatus(u) if not CHECK_ENDS then return nil end return (UNITS[u] and UNITS[u].name == STARTER) and "ready" or "waiting" end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end; RegionMethods.EnableMouse = function(s, v) s._mouse = v end')
lua.execute('TEXS = {}; local ct = RegionMethods.CreateTexture; RegionMethods.CreateTexture = function(self, ...) local t = ct(self, ...); t._parent = self; table.insert(TEXS, t); return t end')
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", lua.table())
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD"); Advance(1)
local F; for _, f in ipairs(allFrames) do if f.sqKey == "ready" then F = f end end
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
-- The ready check icon shown on the ring (badge or background).
function Icon() for _, t in ipairs(TEXS) do local p = t._parent
  if p and (p == F or p._parent == F) and p._shown ~= false and t._texpath and tostring(t._texpath):match("ReadyCheck") then
    return (tostring(t._texpath):gsub(".*ReadyCheck%-", "")) end end return "none" end
function S(l) local n = 0 for _, x in ipairs(F.fill) do if x._shown ~= false and x._x1 then n = n + 1 end end
  P(string.format("%-30s shown=%s fill=%2d | %s | icon: %s", l, tostring(F._shown), n, T(F), F._shown and Icon() or "-")) end
function Begin(starter, secs) STARTER = starter; CHECK_ENDS = NOW + secs; Fire("READY_CHECK", starter, secs) end
function Answer(unit, ready) Fire("READY_CHECK_CONFIRM", unit, ready) end
function Finish() CHECK_ENDS = nil; Fire("READY_CHECK_FINISHED") end

S("idle")
-- Thrall starts one: he's ready, you haven't answered.
Begin("Thrall", 35); Advance(1); S("started by Thrall")
Answer("player", true); Advance(1); S("you're ready")
Answer("party3", true); Advance(1); S("Rexxar ready")
Answer("party2", false); Advance(1); S("Jaina not ready")
Answer("party4", true); Finish(); Advance(0.5); S("finished: one not ready")
Advance(4.5); S("result gone")
-- Everyone ready.
Begin("Thrall", 35); for _, u in ipairs({ "player", "party2", "party3", "party4" }) do Answer(u, true) end
Finish(); Advance(0.5); S("all ready (ended before it showed)")
Advance(5)
-- Rexxar never answers: the check runs out.
Begin("Jaina", 10); Answer("player", true); Answer("party1", true); Answer("party4", true); Advance(5); S("Rexxar AFK, 4s left")
Advance(5); Finish(); Advance(0.5); S("finished: one AFK")
Advance(5)
-- The game never says it finished: the ring gives up a little after the time.
Begin("Jaina", 5); Advance(4); S("5s check, 1s left")
CHECK_ENDS = nil; Advance(5); S("never finished: result")
Advance(4); S("then gone")
-- A raid.
RAID = true; SetRaid(); Begin("Kaladin", 35); Advance(1); S("raid, you started it")
Answer("raid2", true); Answer("raid3", true); Finish(); Advance(0.5); S("raid all ready")
Advance(5); RAID = false; SetParty()
-- Icon as background: the icon fills the middle, dimmed.
CircletDB.readyIconBg = true; Begin("Thrall", 35); Advance(1); S("icon as background")
local tex; for _, t in ipairs(TEXS) do if t._texpath and tostring(t._texpath):match("ReadyCheck") and t._parent and t._parent._shown ~= false then tex = t end end
P(string.format("  icon alpha %.2f (setting %d%%)", tex._alpha or 1, CircletDB.readyIconBgAlpha))
Finish(); Advance(5); CircletDB.readyIconBg = false
-- Turned off: nothing.
CircletDB.readyEnabled = false; Begin("Thrall", 35); Advance(1); S("ring off")
Finish(); Advance(5); CircletDB.readyEnabled = true
Slash("ready"); Advance(1); S("preview")
Advance(9); S("preview, one not ready")
Advance(3); S("preview result")
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
