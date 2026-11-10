from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
MENUS = {}
Menu = { ModifyMenu = function(tag, fn) MENUS[tag] = fn end }
QUESTS = { [77] = { title = "The Defias Brotherhood", obj = {
  { text = "Defias Thug slain: 9/12", numFulfilled = 9, numRequired = 12, finished = false },
  { text = "Red Leather Bandana: 2/4", numFulfilled = 2, numRequired = 4, finished = false } } },
  [88] = { title = "Feathers for Grek", obj = { { text = "Screecher Feather: 3/8", numFulfilled = 3, numRequired = 8, finished = false } } } }
ORDER = { 77, 88 }
C_QuestLog.GetNumQuestLogEntries = function() return #ORDER end
C_QuestLog.GetInfo = function(i) local id = ORDER[i]; return id and { questID = id, title = QUESTS[id].title } end
C_QuestLog.GetQuestObjectives = function(id) return QUESTS[id] and QUESTS[id].obj end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end; RegionMethods.EnableMouse = function(s, v) s._mouse = v end')
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", lua.table())
lua.execute('''
DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME or {}; DEFAULT_CHAT_FRAME.AddMessage = function(_, m) P("chat: " .. tostring(m)) end
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
P("pinX from screen: " .. tostring(CircletDB.pinX))
local tags = {} for t in pairs(MENUS) do table.insert(tags, t) end table.sort(tags) P("menus hooked: " .. table.concat(tags, ", "))
function Menu1(qid)
  local root = { items = {} }
  function root:CreateDivider() end
  function root:CreateButton(text, fn) table.insert(self.items, { text = text, fn = fn }) end
  MENUS.MENU_QUEST_MAP_LOG_TITLE({ questID = qid }, root, nil)
  return root.items[1]
end
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function Pins() local t = {} for _, f in ipairs(allFrames) do if f.editHint and f.marker and f._shown and f.sqKey and f.sqKey:match("^pin") then
  local n = 0 for _, l in ipairs(f.bg) do if l._shown ~= false and l._x1 then n = n + 1 end end
  table.insert(t, string.format("%s [%s] bgsegs=%d", f.sqKey, T(f), n)) end end table.sort(t) return t end
function D(l) P(l) for _, x in ipairs(Pins()) do P("   " .. x) end end
local item = Menu1(77); P("menu item: " .. item.text); item.fn(); Advance(1); D("after pinning 77:")
Menu1(88).fn(); Advance(1); D("after pinning 88:")
P("menu on pinned: " .. Menu1(77).text)
QUESTS[77].obj[1].numFulfilled = 12; QUESTS[77].obj[1].finished = true; QUESTS[77].obj[2].numFulfilled = 4; QUESTS[77].obj[2].finished = true; Advance(1); D("77 complete:")
table.remove(ORDER, 1); QUESTS[77] = nil; Advance(3); D("77 turned in:")
P("pinned list: " .. table.concat(select(2, next(CircletDB.pinned)), ","))
-- drag ring 1 (now 88) → stack origin moves
Slash("edit pin"); Advance(1); D("editing (samples):"); Slash("edit pin"); Advance(3)

Slash("ring feath"); Advance(1)
local f2; for _, f in ipairs(allFrames) do if f.sqKey == "pin2" then f2 = f end end
UIParent.GetEffectiveScale = function() return 1 end
f2._cx, f2._cy = 600, 500; CURSOR_X, CURSOR_Y = 600, 500; f2._scripts.OnDragStart(f2); CURSOR_X, CURSOR_Y = 700, 700; f2._scripts.OnDragStop(f2)
P("dragged pin2 centre to y=700 -> pinX=" .. CircletDB.pinX .. " pinFromTop=" .. CircletDB.pinFromTop .. " (ring 2 top = " .. (CircletDB.pinFromTop + 112) .. ", expect " .. (1080 - 700 - 50) .. ")")
Slash("resetpos pin"); P("after reset: pinX=" .. CircletDB.pinX .. " pinFromTop=" .. CircletDB.pinFromTop)
Slash("ring feathers"); Advance(1); D("after /circ ring feathers (unpin):")
Slash("ring feath"); Advance(1); D("after /circ ring feath (pin):")
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
