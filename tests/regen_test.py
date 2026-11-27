from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
-- Spell costs: Flash Heal (mana), Shoot (free), Heroic Strike (rage), Mind Flay (channelled, mana).
COSTS = {
  [2061]  = { { type = 0, name = "MANA", cost = 125 } },
  [5019]  = {},
  [78]    = { { type = 1, name = "RAGE", cost = 15 } },
  [15407] = { { type = 0, name = "MANA", cost = 45 } },
  [9999]  = { { type = 0, name = "MANA", cost = 0, costPercent = 6 } }, -- a percentage cost
}
SECRET = {}
issecretvalue = function(v) return v == SECRET end
HIDE_COSTS = false
C_Spell = C_Spell or {}
C_Spell.GetSpellPowerCost = function(id) if HIDE_COSTS then return SECRET end return COSTS[id] end
AURAS = {}
C_UnitAuras = { GetAuraDataByIndex = function(u, i) return AURAS[i] end }
function Buff(id, name) table.insert(AURAS, { name = name, spellId = id }); Fire("UNIT_AURA", "player") end
function Unbuff(id) for i = #AURAS, 1, -1 do if AURAS[i].spellId == id then table.remove(AURAS, i) end end; Fire("UNIT_AURA", "player") end
local n = 0
function Cast(id) n = n + 1; Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. n, id) end
function Channel(id) n = n + 1; local g = "Cast-" .. n; Fire("UNIT_SPELLCAST_CHANNEL_START", "player", g, id); Fire("UNIT_SPELLCAST_SUCCEEDED", "player", g, id) end
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
function Ring() for _, f in ipairs(allFrames) do if f.sqKey == "regen" and f._shown then return f end end end
function Fill() local f = Ring(); local n = 0; if f then for _, l in ipairs(f.fill) do if l._shown ~= false and l._x1 then n = n + 1 end end end return n end
function C() local f = Ring() return f and (T(f) .. " fill=" .. Fill()) or "(hidden)" end
function Fx() local p = NS.RegenFxParts(); if not p then return "fx none" end local n = 0 for _, m in ipairs(p.motes) do if m.tex._shown then n = n + 1 end end local b = 0 for _, m in ipairs(p.bits) do if m.tex._shown then b = b + 1 end end return "glow=" .. tostring(p.glow._shown and true or false) .. " spark=" .. tostring(p.tipStar._shown and true or false) .. " bits=" .. b .. " motes=" .. n end

P("nothing cast: " .. C())
Cast(2061); Advance(1); P("Flash Heal, 1s: " .. C())
Advance(2.5); P("3.5s: " .. C())
Cast(2061); Advance(0.5); P("cast again, 0.5s: " .. C())
Advance(4.6); P("5.1s after: " .. C())
Advance(2); P("then: " .. C())
Cast(5019); Advance(1); P("Shoot (free): " .. C())
Cast(78); Advance(1); P("Heroic Strike (rage): " .. C())
Cast(9999); Advance(1); P("a percentage mana cost: " .. C()); Advance(7)
Channel(15407); Advance(1); P("Mind Flay channel, 1s: " .. C()); Advance(7)
-- In a fight the costs are hidden: what was learned still counts; a new spell can't be told.
HIDE_COSTS = true
Cast(2061); Advance(1); P("cost hidden, Flash Heal (learned): " .. C()); Advance(7)
COSTS[2050] = { { type = 0, name = "MANA", cost = 60 } }
Cast(2050); Advance(1); P("cost hidden, a spell never seen: " .. C())
HIDE_COSTS = false; Advance(7)
CircletDB.regenEnabled = false; Cast(2061); Advance(1); P("ring off: " .. C()); CircletDB.regenEnabled = true; Advance(7)
P("learned: Flash Heal=" .. tostring(CircletDB.manaSpells[2061]) .. " Shoot=" .. tostring(CircletDB.manaSpells[5019]) .. " Heroic Strike=" .. tostring(CircletDB.manaSpells[78]))
-- Free-cast buffs: a cast that uses one up doesn't stop regen.
Advance(7)
Buff(12536, "Clearcasting"); Advance(1)
Unbuff(12536); Cast(2061); Advance(1); P("Clearcasting used up just before the cast is reported: " .. C()); Advance(7)
Buff(12536, "Clearcasting"); Advance(1)
Cast(2061); Advance(0.2); Unbuff(12536); Advance(1); P("Clearcasting used up just after: " .. C()); Advance(7)
Buff(16870, "Clearcasting"); Advance(1)
Cast(2061); Advance(1); P("Clearcasting still up after the cast (it paid): " .. C())
Advance(1); P("2s after: " .. C()); Unbuff(16870); Advance(7)
Buff(14751, "Inner Focus"); Advance(1); Cast(2061); Unbuff(14751); Advance(1); P("Inner Focus: " .. C()); Advance(7)
Buff(16246, "Clearcasting"); Advance(1); Cast(2061); Unbuff(16246); Advance(1); P("shaman Clearcasting: " .. C()); Advance(7)
Buff(27827, "Spirit of Redemption"); Advance(1); Cast(2061); Advance(1); P("Spirit of Redemption: " .. C()); Unbuff(27827); Advance(7)
Buff(29166, "Innervate"); Advance(1); Cast(2061); Advance(1); P("Innervate: " .. C()); Unbuff(29166); Advance(0.5); P("Innervate ends: " .. C()); Advance(7)
Buff(12536, "Clearcasting"); Advance(1); Cast(2061); Unbuff(12536); Advance(0.3); Cast(2061); Advance(1); P("free cast, then a paid one right after: " .. C()); Advance(7)

-- The animation: a glow while waiting, motes flowing in once regen starts (or during Innervate).
Cast(2061); Advance(2); P("fx waiting: " .. Fx()); Advance(3.5); P("fx regen 0.5s: " .. Fx()); Advance(7)
Buff(29166, "Innervate"); Advance(1); Cast(2061); Advance(1.5); P("fx innervated: " .. Fx()); Unbuff(29166); Advance(7)
CircletDB.regenFx = false; Cast(2061); Advance(5.5); P("fx off: " .. Fx()); CircletDB.regenFx = true; Advance(7)
Slash("regen"); Advance(2); P("preview: " .. C()); Advance(4); P("preview 6s: " .. C()); Advance(15)
''')
print("\n".join(lua.eval("OUT").values()))
print("ERRORS:", dict(lua.eval("ERRORS")))
