exec(open('breath_test.py').read().split("lua.execute('''\nFire(\"ADDON_LOADED\"")[0])
lua.execute('''
local names = { [133]="Fireball", [5143]="Arcane Missiles", [2575]="Mining" }
C_Spell = C_Spell or {}; C_Spell.GetSpellName = function(id) return names[id] end
C_Spell.GetSpellTexture = function(id) return "icon" .. id end
C_Spell.GetSpellInfo = function(id) return { castTime = id == 133 and 2500 or 0 } end
CAST = nil; CHAN = nil; SECRET = false; local sv = {}
issecretvalue = function(v) return v == sv end
function UnitCastingInfo() if CAST then return "x", "", "tex", SECRET and sv or CAST.s * 1000, SECRET and sv or CAST.e * 1000 end end
function UnitChannelInfo() if CHAN then return "x", "", "tex", SECRET and sv or CHAN.s * 1000, SECRET and sv or CHAN.e * 1000 end end
''')
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function C() for _, f in ipairs(allFrames) do if f.editHint and f.sqKey == "cast" then return f._shown and T(f) or "(hidden)" end end end
-- out of combat: real times (3s with haste... real says 2.0)
CAST = { s = NOW, e = NOW + 2.0 }; Fire("UNIT_SPELLCAST_START", "player", "g1", 133); Advance(1); P("ooc cast 1s: " .. C())
CAST = nil; Fire("UNIT_SPELLCAST_STOP", "player", "g1", 133); Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g1", 133); Advance(0.3); P("ooc done: " .. C() .. " learned=" .. tostring(CircletDB.castTimes[133])); Advance(3)
-- in combat: secret; uses listed 2.5
SECRET = true; CAST = { s = NOW, e = NOW + 2.5 }; Fire("UNIT_SPELLCAST_START", "player", "g2", 133); Advance(1); P("combat cast 1s: " .. C())
Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "g2", 133); CAST = nil; Fire("UNIT_SPELLCAST_STOP", "player", "g2", 133); Advance(0.3); P("interrupted: " .. C()); Advance(3)
-- instant spell SUCCEEDED with no START doesn't show
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g3", 999); Advance(0.3); P("instant: " .. C())
-- channel: learn out of combat, then combat
SECRET = false; CHAN = { s = NOW, e = NOW + 5 }; Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "g4", 5143); Advance(2); P("ooc channel 2s: " .. C()); CHAN = nil; Advance(3.2); Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "g4", 5143); Advance(0.3); P("channel done: " .. C()); Advance(3)
SECRET = true; CHAN = { s = NOW, e = NOW + 5 }; Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "g5", 5143); Advance(1); P("combat channel 1s: " .. C()); Advance(1); Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "g5", 5143); Advance(0.3); P("channel cut short: " .. C()); Advance(3)
Slash("cast"); Advance(1); P("preview: " .. C())
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
