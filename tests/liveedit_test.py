from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
UIParent._w, UIParent._h = 1920, 1080
RegionMethods.GetCenter = function(s) return s._cx, s._cy end
UNDEF = {}
setmetatable(_G, { __index = function(t, k) UNDEF[k] = (UNDEF[k] or 0) + 1 end })
ERRORS = {}
local function guard(where, fn, ...) local ok, err = pcall(fn, ...); if not ok then local k = where..": "..tostring(err); ERRORS[k] = (ERRORS[k] or 0) + 1 end end
function Fire(event, ...) for _, f in ipairs(allFrames) do if f._events and f._events[event] and f._scripts.OnEvent then guard("OnEvent "..event, f._scripts.OnEvent, f, event, ...) end end end
function Advance(seconds, fps) fps = fps or 30
  for _ = 1, math.floor(seconds * fps) do NOW = NOW + 1 / fps
    local due = {} for i = #pendingTimers, 1, -1 do if pendingTimers[i].at <= NOW then table.insert(due, table.remove(pendingTimers, i)) end end
    for _, t in ipairs(due) do guard("timer", t.fn) end
    for _, f in ipairs(allFrames) do if f._shown and f._scripts.OnUpdate then guard("OnUpdate", f._scripts.OnUpdate, f, 1 / fps) end end
  end end
function Slash(c) guard("slash "..c, SlashCmdList.CIRCLET, c) end
''')
chunk = lua.eval('function(s) return load(s, "@SideQuest.lua") end')((__import__('subprocess').run(['python3','make_bundle.py']), open('bundle.lua').read())[1])
chunk("Circlet", lua.table())
lua.execute('''
OUT = {}; function P(...) local t = {} for i=1,select('#',...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t,' ')) end
RegionMethods.EnableMouse = function(s, v) s._mouse = v end
CHAT = {}; DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME or {}; DEFAULT_CHAT_FRAME.AddMessage = function(_, m) table.insert(OUT, 'chat: '..tostring(m)) end
Fire("ADDON_LOADED", "Circlet"); XP = 300; XPMAX = 1000; Fire("PLAYER_ENTERING_WORLD"); Advance(1)
RINGS = {}
for _, f in ipairs(allFrames) do if f.editHint then table.insert(RINGS, f) end end
function Dump(label)
  local parts = {}
  for i, f in ipairs(RINGS) do
    local texts = {}
    for _, g in ipairs(ALL_FS) do if g._parent == f and g._shown ~= false and g._text and g._text ~= "" then table.insert(texts, tostring(g._text)) end end
    table.insert(parts, string.format("  #%d shown=%s a=%.2f strata=%s mouse=%s | %s", i, tostring(f._shown), f._alpha or 1, tostring(f._strata), tostring(f._mouse), table.concat(texts, " / ")))
  end
  P(label); P(table.concat(parts, "\\n"))
end
''')
lua.execute('P("rings found:", #RINGS)')
lua.execute('Slash("edit quest"); Advance(0.5); Dump("quest editing t=0.5")')
lua.execute('Advance(3.5); Dump("quest editing t=4")')
lua.execute('Advance(4); Dump("quest t=8")')
# real quest progress during edit should wait
lua.execute('Slash("edit skill"); Advance(1); Dump("quest+skill")')
lua.execute('for i=1,5 do Advance(3.6) end; Dump("skill cycled")')
lua.execute('Slash("edit rep"); Slash("edit xp"); Advance(1); Dump("all four")')
lua.execute('XP = 500; Fire("PLAYER_XP_UPDATE", "player"); Advance(4); Dump("xp gain during edit (should keep sample)")')
# drag xp
lua.execute('''
local x
for _, f in ipairs(RINGS) do for _, g in ipairs(ALL_FS) do if g._parent == f and tostring(g._text):match("^Level") then x = f end end end
XPF = x
x._cx, x._cy = 960, 970; CURSOR_X, CURSOR_Y = 960 * 0.8, 970 * 0.8; UIParent.GetEffectiveScale = function() return 0.8 end; x._scripts.OnDragStart(x); CURSOR_X, CURSOR_Y = 1500 * 0.8, 700 * 0.8; x._scripts.OnDragStop(x)
P("xpX, xpFromTop:", CircletDB.xpX, CircletDB.xpFromTop)
x._scripts.OnMouseUp(x, "RightButton")
P("after right-click:", CircletDB.xpX, CircletDB.xpFromTop)
''')
# settings change live
lua.execute('CircletDB.questSize = 200; Advance(0.2)')
lua.execute('Slash("edit"); Advance(0.3); Dump("after /sq edit (all off)")')
lua.execute('Advance(4); Dump("t+4 after edit off (xp queued gain should play)")')
lua.execute('Advance(8); Dump("settled")')
lua.execute('Slash("edit"); Advance(0.3); Dump("all on again"); local bar = _G.CircletEditModeFrame; bar._scripts.OnHide(bar); Advance(0.2); Dump("after Esc")')
lua.execute('Slash("edit bogus")')
print("\n".join(lua.eval("OUT").values()))
print("ERRORS:", dict(lua.eval('ERRORS')))
u = dict(lua.eval('UNDEF')); print("UNDEF:", sorted(u))
