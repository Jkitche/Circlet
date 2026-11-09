from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
RESTING, GHOST, MONEY = false, false, 12345
function IsResting() return RESTING end
function UnitIsGhost() return GHOST end
function GetMoney() return MONEY end
function GetRealmName() return "Forever" end
time = os.time
FACING, DELAY = 0, 0
function GetPlayerFacing() return FACING end
function GetCorpseRecoveryDelay() return DELAY end
PX, PY, CX, CY = 0.50, 0.50, 0.50, 0.40
C_Map = { GetBestMapForUnit = function() return 1429 end,
  GetPlayerMapPosition = function() return { GetXY = function() return PX, PY end } end,
  GetMapWorldSize = function() return 4000, 2700 end }
C_DeathInfo = { GetCorpseMapPosition = function() return { GetXY = function() return CX, CY end } end }
TIMED = nil
C_QuestLog.GetTimeAllowed = function(id) if TIMED then return TIMED.total, TIMED.elapsed end end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end; RegionMethods.EnableMouse = function(s, v) s._mouse = v end')
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", lua.table())
lua.execute('''
DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME or {}; DEFAULT_CHAT_FRAME.AddMessage = function(_, m) P("chat: " .. tostring(m)) end
Fire("ADDON_LOADED", "Circlet"); XP = 300; XPMAX = 1000; Fire("PLAYER_ENTERING_WORLD", true, false); Fire("QUEST_LOG_UPDATE"); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function Live(key) for _, f in ipairs(allFrames) do if f.editHint and f.marker and f._key_probe == nil then end end end
function Rings() local t = {} for _, f in ipairs(allFrames) do if f.editHint and f._shown then table.insert(t, T(f)) end end return t end
function D(l) P(l) for _, x in ipairs(Rings()) do P("    " .. x) end end

-- timed quest
TIMED = { total = 150, elapsed = 20 }; Advance(1); D("timed quest, 130s left:")
TIMED.elapsed = 110; Advance(1); D("timed 40s left:")
TIMED = nil; Advance(6); D("timed done:")

-- corpse
GHOST = true; DELAY = 12; Advance(1); D("ghost, delay:")
DELAY = 0; FACING = 0; Advance(1)
local cr; for _, f in ipairs(allFrames) do if f.editHint and f.marker and f._shown then cr = f end end
local mp = cr.marker._points and cr.marker._points[1]
D("ghost walking:")
PY = 0.4005; Advance(1); D("ghost near:")
GHOST = false; Advance(2); D("alive:")

-- resting
RESTING = true; REST = 1500; Fire("UPDATE_EXHAUSTION"); Fire("PLAYER_UPDATE_RESTING"); Advance(1); D("resting at inn:")
RESTING = false; Fire("PLAYER_UPDATE_RESTING"); Advance(3); D("left inn:")

-- session data + summary
XP = 700; Fire("PLAYER_XP_UPDATE", "player"); Advance(3)
Fire("QUEST_TURNED_IN", 77, 500, 100); MONEY = 12345 + 23456; Fire("PLAYER_DEAD"); Advance(1)
Slash("summary"); Advance(0.2)
local s = CircletDB.sessions["Tester-Forever"] or select(2, next(CircletDB.sessions))
P(string.format("session: xp=%s quests=%s deaths=%s levels=%s", s.xp, s.quests, s.deaths, s.levels))
P("summary shown=" .. tostring(CircletSummaryFrame._shown) .. " title=" .. tostring(CircletSummaryFrame.title._text) .. " / " .. tostring(CircletSummaryFrame.subtitle._text))
for _, g in ipairs(ALL_FS) do if g._text and g._text ~= "" then local p = g._parent; while p and p ~= CircletSummaryFrame do p = p._parent end if p and g._parent ~= CircletSummaryFrame then P("   tile text: " .. tostring(g._text)) end end end
-- reload keeps session, new login resets
Fire("PLAYER_ENTERING_WORLD", false, true)
Slash("timed"); Advance(1); D("timed preview:"); Advance(14)
Slash("corpse"); Advance(1); D("corpse preview:"); Advance(14)
Slash("edit timed"); Slash("edit corpse"); Advance(1); D("editing:"); Slash("edit"); Advance(3)
Fire("PLAYER_CAMPING"); P("logout summary shown=" .. tostring(CircletSummaryFrame._shown))
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
