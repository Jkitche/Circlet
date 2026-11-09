from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
hooksecurefunc = hooksecurefunc or function() end
C_Spell = C_Spell or {}; C_Spell.GetSpellName = function(id) return ({[2575]="Mining",[2366]="Herb Gathering",[8613]="Skinning",[7620]="Fishing",[2656]="Smelting"})[id] end
C_Item = C_Item or {}; C_Item.GetItemIconByID = function(id) return "icon"..id end
LOOT_ITEM_SELF = "You receive loot: %s."; LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
CAST = nil; CHAN = nil
function UnitCastingInfo() if CAST then return CAST.name, "", 0, CAST.s * 1000, CAST.e * 1000, false, "g", false, CAST.id end end
function UnitChannelInfo() if CHAN then return CHAN.name, "", 0, CHAN.s * 1000, CHAN.e * 1000, false, false, CHAN.id end end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end; RegionMethods.EnableMouse = function(s, v) s._mouse = v end')
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", lua.table())
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function C() for _, f in ipairs(allFrames) do if f.editHint and f.marker and f._shown then return T(f) end end return "(hidden)" end
function Cast(name, id, len) CAST = { name = name, s = NOW, e = NOW + len, id = id }; Fire("UNIT_SPELLCAST_START", "player", "g", id) end
Cast("Mining", 2575, 2); Advance(1); P("mining half: " .. C()); CAST = nil; Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2575)
Advance(0.3); Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2770::|h[Copper Ore]|h|rx2."); Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:774::|h[Malachite]|h|r."); Advance(0.5)
P("mined: " .. C()); Advance(5); P("later: " .. C())
Cast("Herb Gathering", 2366, 2); Advance(1.2); CAST = nil; Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "g", 2366); Advance(0.2); P("herb interrupted: " .. C()); Advance(5)
Cast("Smelting", 2656, 2); Advance(1); P("smelting (should be hidden): " .. C()); CAST=nil; Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2656); Advance(4)
CHAN = { name = "Fishing", s = NOW, e = NOW + 20, id = 7620 }; Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "g", 7620); Advance(5); P("fishing: " .. C())
CHAN = nil; Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "g", 7620); Advance(0.4); P("reeling: " .. C()); Fire("CHAT_MSG_LOOT", "You receive loot: |Hitem:6291::|h[Raw Brilliant Smallfish]|h."); Advance(1); P("caught: " .. C()); Advance(5)
CHAN = { name = "Fishing", s = NOW, e = NOW + 20, id = 7620 }; Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "g", 7620); Advance(3); CHAN=nil; Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "g", 7620); Advance(2.5); P("no catch: " .. C()); Advance(5)
P("session gathers: " .. tostring(select(2, next(CircletDB.sessions)).gathers))
Slash("gather"); Advance(1); P("preview: " .. C()); Advance(3); P("preview2: " .. C())
Slash("edit gather"); Advance(0.5); P("edit: " .. C()); Slash("edit gather"); Advance(2)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
