from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
XP, XPMAX, LEVEL = 1000, 4000, 12
UnitXP = function() return XP end
UnitXPMax = function() return XPMAX end
UnitLevel = function() return LEVEL end
UnitCanAttack = function() return true end
GetSpellInfo = function(id) return ({ [78] = "Heroic Strike", [285] = "Heroic Strike", [6603] = "Attack", [772] = "Rend" })[id] end
BreakUpLargeNumbers = function(n) local s = tostring(n) local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse() return (r:gsub("^,", "")) end
SECRET = {}
issecretvalue = function(v) return v == SECRET end
AbbreviateNumbers = function(v) return v == SECRET and "<drawn by game>" or tostring(v) end
METER = { [0] = 1843, [1] = 68.3, [2] = 0, [5] = 0, [6] = 0, [7] = 412 }
C_DamageMeter = {
  GetCombatSessionFromType = function(st, kind)
    if st ~= 1 then return { combatSources = {} } end
    local v = METER[kind]; if v == nil then return nil end
    return { durationSeconds = 27, combatSources = { { isLocalPlayer = false, totalAmount = 999 },
      { isLocalPlayer = true, totalAmount = v, amountPerSecond = kind == 0 and METER[1] or 0, sourceGUID = "Player-1" } } }
  end,
  GetCombatSessionSourceFromType = function(st, kind, guid)
    return { combatSpells = { { spellID = 6603, totalAmount = 900 }, { spellID = 285, totalAmount = 642 }, { spellID = 772, totalAmount = 301 } } }
  end,
}
local n = 0
function Hit(unit, action, flag) Fire("UNIT_COMBAT", unit, action, flag or "", 25, 1) end
function Cast(id) n = n + 1; Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. n, id) end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end')
NSX = lua.table(); lua.globals().NS = NSX; lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Fire("PLAYER_LOGIN"); Advance(1)
local FS = NS.FightSummary
function Pane()
  local p = FS.pane
  if not p._shown then return "(no pane)" end
  local t = {}
  for _, g in ipairs(ALL_FS) do
    local q = g._parent
    while q and q ~= p do q = q._parent end
    if q == p and g._shown ~= false and g._text and g._text ~= "" then table.insert(t, tostring(g._text)) end
  end
  return table.concat(t, " | ") .. string.format("  [alpha %.2f]", p._alpha or 1)
end
UNITS.target = { guid = "Mob-1", name = "Gray Bear", hostile = true }
Fire("PLAYER_REGEN_DISABLED")
Hit("player", "WOUND"); Hit("player", "DODGE"); Hit("player", "PARRY"); Hit("player", "WOUND", "CRUSHING")
Hit("player", "BLOCK"); Hit("player", "BLOCK"); Hit("player", "MISS"); Hit("player", "WOUND", "CRITICAL")
Hit("target", "WOUND", "CRITICAL"); Hit("target", "WOUND"); Hit("target", "WOUND", "CRITICAL")
Cast(285); Cast(772); Cast(6603)
Advance(10)
UNITS.target = { guid = "Mob-2", name = "Young Wolf", hostile = true }; Fire("PLAYER_TARGET_CHANGED")
Fire("CHAT_MSG_COMBAT_XP_GAIN", "Gray Bear dies, you gain 120 experience.")
XP = 1236
Advance(17)
Fire("PLAYER_REGEN_ENABLED")
Fire("CHAT_MSG_COMBAT_XP_GAIN", "Young Wolf dies, you gain 116 experience.") -- just after combat ends
Advance(0.5)
P("after the fight: " .. Pane())
Advance(12); P("12.5s later, fading: " .. Pane()); Advance(1); P("gone: " .. Pane())
-- Too short: no pane.
Fire("PLAYER_REGEN_DISABLED"); Advance(2); Fire("PLAYER_REGEN_ENABLED"); Advance(0.3); P("2s fight: " .. Pane())
-- Hit nothing: no pane (only fights you dealt damage in).
METER[0] = 0; METER[1] = 0
Fire("PLAYER_REGEN_DISABLED"); Hit("player", "WOUND"); Advance(6); Fire("PLAYER_REGEN_ENABLED"); Advance(0.3); P("no damage dealt: " .. Pane())
-- Still hidden right after combat: the game draws it; then it settles.
METER[0] = SECRET; METER[1] = SECRET
Fire("PLAYER_REGEN_DISABLED"); Advance(6); Fire("PLAYER_REGEN_ENABLED"); Advance(0.3); P("meter still hidden: " .. Pane())
METER[0] = 950; METER[1] = 158.3; Advance(1); P("settled: " .. Pane())
Advance(15)
-- A level up in the fight.
METER[0] = 500; METER[1] = 50; XP, XPMAX, LEVEL = 3900, 4000, 12
Fire("PLAYER_REGEN_DISABLED"); Advance(5); XP, XPMAX, LEVEL = 60, 4400, 13; Fire("PLAYER_REGEN_ENABLED"); Advance(0.3)
P("level up: " .. Pane()); Advance(15)
-- Off.
CircletDB.fightEnabled = false; Fire("PLAYER_REGEN_DISABLED"); Advance(6); Fire("PLAYER_REGEN_ENABLED"); Advance(0.3); P("off: " .. Pane())
CircletDB.fightEnabled = true
Slash("fight"); Advance(0.2); P("/circ fight: " .. Pane()); Slash("fight"); Advance(0.2)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
