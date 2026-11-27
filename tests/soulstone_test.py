from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
UnitClass = function() return "Warlock", "WARLOCK", 9 end
time = function() return CLOCK_EPOCH + math.floor(NOW) end
GetSpellInfo = function(id) if id == 20707 or id == 20765 then return "Soulstone Resurrection" end if id == 686 then return "Shadow Bolt" end end
BAGS, CD = { [16896] = 1 }, {}
GetItemCount = function(id) return BAGS[id] or 0 end
GetItemCooldown = function(id) local c = CD[id]; if c then return c[1], c[2], 1 end return 0, 0, 1 end
COMBAT = false
InCombatLockdown = function() return COMBAT end
UnitIsDeadOrGhost = function() return false end
UnitIsVisible = function() return true end
IsInRaid = function() return false end
GetNumGroupMembers = function() return 2 end
BUFFS = {} -- unit -> expirationTime of the stone buff
UNITNAMES = { player = "Gul'dan", party1 = "Thrall" }
UnitName = function(u) return UNITNAMES[u] end
C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
  if i == 1 and BUFFS[unit] then return { name = "Soulstone Resurrection", expirationTime = BUFFS[unit] } end end }
local n = 0
function Cast(id, target) n = n + 1
  Fire("UNIT_SPELLCAST_SENT", "player", target, "Cast-" .. n, id)
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. n, id) end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w") : s.index("chunk = lua.eval")])
lua.execute(
    'OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end'
)
NSX = lua.table()
lua.globals().NS = NSX
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function Ring() for _, f in ipairs(allFrames) do if f.sqKey == "soulstone" and f._shown and f._alpha > 0 then return f end end end
function Fill(f) local n = 0; if f then for _, l in ipairs(f.fill) do if l._shown ~= false and l._x1 then n = n + 1 end end end return n end
function C() local f = Ring() return f and (T(f) .. " fill=" .. Fill(f)) or "(hidden)" end

Advance(1.2); P("a stone in the bags, none out: " .. C())
CircletDB.soulstoneRemind = false; Advance(2); P("reminder off: " .. C()); CircletDB.soulstoneRemind = true
Cast(686, "Young Wolf"); Advance(1.2); P("Shadow Bolt isn't a stone: " .. C())
CD[16896] = { NOW, 1800 }
Cast(20765, "Thrall-Forever"); BUFFS.party1 = NOW + 1800; Advance(1.2); P("placed on Thrall: " .. C())
Advance(600); P("10 minutes on: " .. C())
-- Reload: the run is saved by the clock.
P("saved: " .. tostring(CircletDB.soulstoneRun and CircletDB.soulstoneRun.who))
-- Out of combat the buff says 18 minutes left: the ring takes the buff's time.
BUFFS.party1 = NOW + 18 * 60; Advance(6); P("buff says 18m: " .. C())
-- In combat buffs can't be read: the clock runs; the buff vanishing isn't noticed yet.
COMBAT = true; BUFFS.party1 = nil; Advance(30); P("in combat, buff gone (unseen): " .. C())
COMBAT = false; Fire("PLAYER_REGEN_ENABLED"); Advance(1.2); P("out of combat, it's gone: " .. C())
Advance(9); P("later, stone on cooldown: " .. C())
-- A stone on yourself, left to run out.
CD[16896] = nil; Cast(20707, "Gul'dan"); BUFFS.player = NOW + 1800; Advance(1.2); P("on yourself: " .. C())
CircletDB.soulstoneAlways = false; Advance(10); P("mid-stone, always off: " .. C())
Advance(1800 - 11 - 240); P("last 4 minutes: " .. C())
BUFFS.player = nil; COMBAT = true; Advance(243); P("ran out: " .. C())
COMBAT = false; Advance(9); P("then: " .. C())
CircletDB.soulstoneAlways = true
-- Out of combat with nothing in the bags: nothing.
BAGS = {}; Advance(2); P("no stone in the bags: " .. C())
Slash("soulstone"); Advance(1.2); P("preview: " .. C()); Advance(17); P("preview later: " .. C()); Advance(10)
''')
print("\n".join(lua.eval("OUT").values()))
print("ERRORS:", dict(lua.eval("ERRORS")))
