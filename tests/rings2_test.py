from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('''
OUT = {}; function P(...) local t = {} for i=1,select('#',...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t,' ')) end
RegionMethods.EnableMouse = function(s, v) s._mouse = v end
-- ammo / pet mocks
AMMO = 600; INVSLOT_AMMO = 0
GetInventoryItemID = function(u, slot) if slot == 0 and AMMO then return 2515 end end
GetInventoryItemCount = function(u, slot) return AMMO end
GetInventoryItemTexture = function() return 132382 end
GetItemInfo = function(id) return id == 2515 and "Sharp Arrow" or "Soul Shard" end
PET = nil
GetPetExperience = function() if PET then return PET.cur, PET.max end return 0, 0 end
GetPetIcon = function() return 132203 end
local ue, ul, un, ug = UnitExists, UnitLevel, UnitName, UnitGUID
UnitExists = function(u) if u == "pet" then return PET ~= nil end return ue(u) end
UnitLevel = function(u) if u == "pet" then return PET and PET.level end return ul(u) end
UnitName = function(u) if u == "pet" then return "Wolf" end return un(u) end
UnitGUID = function(u) if u == "pet" then return "Pet-1" end return ug(u) end
QUEST = { objectives = { { text = "7/8 Screecher Feather", type = "item", numFulfilled = 7, numRequired = 8, finished = false },
                         { text = "Raptor slain: 3/3", type = "monster", numFulfilled = 3, numRequired = 3, finished = true } } }
C_QuestLog.GetQuestObjectives = function(id) return QUEST.objectives end
''')
chunk = lua.eval('function(s) return load(s, "@SideQuest.lua") end')((__import__('subprocess').run(['python3','make_bundle.py']), open('bundle.lua').read())[1])
chunk("Circlet", lua.table())
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); XP = 300; XPMAX = 1000; Fire("PLAYER_ENTERING_WORLD"); Fire("QUEST_LOG_UPDATE"); Advance(1)
RINGS = {}
function RingByText(pat)
  for _, f in ipairs(allFrames) do if f.editHint then
    for _, g in ipairs(ALL_FS) do if g._parent == f and tostring(g._text or ""):match(pat) then return f end end
  end end
end
function Texts(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and g ~= f.editHint then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function Shown() local t = {} for _, f in ipairs(allFrames) do if f.editHint and f._shown then table.insert(t, Texts(f) .. string.format(" @x=%.0f", f.arrangeX or 0)) end end return t end
function Dump(label) P(label) for _, l in ipairs(Shown()) do P("   " .. l) end end

-- turn-in alert
QUEST.objectives[1].numFulfilled = 8; QUEST.objectives[1].finished = true; QUEST.objectives[1].text = "8/8 Screecher Feather"
Fire("QUEST_LOG_UPDATE"); Advance(1.2); Dump("objective done:")
Advance(5); Dump("then turn-in:")
Advance(8)

-- ammo: drops through warn levels
for _, n in ipairs({ 450, 300, 210, 199, 190, 160, 140, 90, 40, 0 }) do AMMO = n; Fire("UNIT_INVENTORY_CHANGED", "player"); Advance(0.4)
  local f = RingByText("Sharp Arrow"); P(string.format("ammo %d -> %s", n, f and f._shown and Texts(f) or "(hidden)")) end
Advance(8)
AMMO = 1000; Fire("UNIT_INVENTORY_CHANGED", "player"); Advance(1.5); Dump("restock:")
Advance(8)

-- ammo, always show: every shot counts down, flashing at or below 15% of a full supply
function FillColors(f)
  local t = {} for _, l in ipairs(ALL_LINES) do if l._parent == f and l._layer == "ARTWORK" and l._sub == 0 and l._shown and l._c then
    table.insert(t, string.format("%.2f,%.2f,%.2f", l._c[1], l._c[2], l._c[3])) end end
  return t[#t] or "-"
end
CircletDB.ammoAlways = true
for _, n in ipairs({ 999, 998, 990 }) do AMMO = n; Fire("UNIT_INVENTORY_CHANGED", "player"); Advance(0.6)
  local f = RingByText("Sharp Arrow"); P(string.format("always %d -> %s", n, f and f._shown and Texts(f) or "(hidden)")) end
Advance(8)
local f = RingByText("Sharp Arrow"); P("after the hold: " .. (f and f._shown and Texts(f) or "(hidden)"))
SECRET = {}; issecretvalue = function(v) return v == SECRET end
AMMO = SECRET; Fire("UNIT_INVENTORY_CHANGED", "player"); Advance(0.6)
f = RingByText("Sharp Arrow"); P("count hidden: " .. (f and f._shown and Texts(f) or "(hidden)"))
AMMO = 980; Fire("UNIT_INVENTORY_CHANGED", "player"); Advance(0.6)
f = RingByText("Sharp Arrow"); P("readable again: " .. (f and f._shown and Texts(f) or "(hidden)"))
Advance(8)
AMMO = 200; Fire("UNIT_INVENTORY_CHANGED", "player"); Advance(2)
f = RingByText("Sharp Arrow"); local a = FillColors(f); Advance(0.33); local b = FillColors(f)
P("at 20% (" .. Texts(f) .. "): flashing " .. tostring(a ~= b))
AMMO = 140; Fire("UNIT_INVENTORY_CHANGED", "player"); Advance(2)
a = FillColors(f); Advance(0.33); b = FillColors(f)
P("at 14% (" .. Texts(f) .. "): flashing " .. tostring(a ~= b))
CircletDB.ammoFlash = 0; Advance(0.1); a = FillColors(f); Advance(0.33); b = FillColors(f)
P("flash set to 0: flashing " .. tostring(a ~= b))
CircletDB.ammoFlash = 15; CircletDB.ammoAlways = false; issecretvalue = nil
Advance(8)

-- pet
PET = { cur = 4200, max = 9800, level = 23 }; Fire("UNIT_PET", "player"); Advance(0.5)
PET.cur = 4600; Fire("UNIT_PET_EXPERIENCE", "player"); Advance(1.5); Dump("pet gain:")
Advance(6)
PET.cur = 300; PET.max = 10600; PET.level = 24; Fire("UNIT_PET_EXPERIENCE", "player"); Advance(2.5); Dump("pet level:")
Advance(8)

-- auto-arrange: put pet on top of skill ring; show both
CircletDB.petX = 180; CircletDB.petFromTop = 50
Slash("skill"); Advance(0.3); Slash("pet"); Advance(1.0); Dump("overlap (pet should be pushed):")
Advance(30); Slash("pet"); Advance(0.5); Dump("pet alone (home):")
CircletDB.autoArrange = false; Advance(10); Slash("skill"); Advance(0.3); Slash("pet"); Advance(1); Dump("arrange off:")
CircletDB.autoArrange = true; Advance(30)

-- styles
CircletDB.questStyle = "segmented"; Slash("quest"); Advance(1)
local q = RingByText("Feathers for Grek")
local vis = 0 for _, l in ipairs(ALL_LINES) do if l._parent == q and l._shown ~= false then vis = vis + 1 end end
P("segmented quest ring visible lines: " .. vis)
CircletDB.questStyle = "thin"; Advance(0.2)
P("thin thickness ok")
Advance(20)
Slash("edit"); Advance(1); Dump("edit all:"); Slash("edit"); Advance(10)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
