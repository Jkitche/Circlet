from lupa import LuaRuntime

def boot(before=''):
    """A fresh game with Circlet loaded; `before` runs first (saved variables, say)."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open('mock.lua').read())
    lua.execute('local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end')
    s = open('liveedit_test.py').read()
    exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")], {'lua': lua})
    lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end; RegionMethods.EnableMouse = function(s, v) s._mouse = v end')
    lua.execute(before)
    ns = lua.table()
    lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", ns)
    lua.globals().NS = ns
    lua.execute('''
function Page(label) P("--- " .. label) for _, l in ipairs(NS.Setup.Lines()) do P("  " .. l) end end
function Open() return NS.Setup.frame._shown and true or false end
function Editing() local t = {} for _, def in ipairs(NS.RINGS) do if def.edit.get() then table.insert(t, def.key) end end return table.concat(t, ",") end
function Click(id) NS.Setup.Click(id) end
''')
    return lua

def report(lua, title):
    print("######## " + title)
    print("\n".join(lua.eval("OUT").values()))
    print("ERRORS:", dict(lua.eval("ERRORS")))

# 1. First run: nothing saved anywhere. The wizard opens a few seconds after login.
lua = boot()
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(2)
P("2s after login, open: " .. tostring(Open()))
Advance(6); P("8s after login, open: " .. tostring(Open()))
Page("step 1")
Click("ring:clock"); Click("ring:pet"); Click("show:loot")
P("clicked clock on, pet off, Show loot -> editing: " .. Editing() .. " clock=" .. tostring(CircletDB.clockEnabled) .. " pet=" .. tostring(CircletDB.petEnabled))
Page("step 1 after clicks")
Click("next"); P("next -> editing: '" .. Editing() .. "'")
Page("step 2")
Click("bar:xp"); P("hide XP bar: " .. tostring(CircletDB.xpHideDefault))
Click("next"); Page("step 3")
Click("style:segmented"); Click("size:larger")
P(string.format("segmented + larger: xp %s %d, cast %s %d, pin %s", CircletDB.xpStyle, CircletDB.xpSize, CircletDB.castStyle, CircletDB.castSize, CircletDB.pinStyle))
Click("style:keep"); Click("size:keep")
P(string.format("back to keep: xp %s %d, cast %s %d, pin %s", CircletDB.xpStyle, CircletDB.xpSize, CircletDB.castStyle, CircletDB.castSize, CircletDB.pinStyle))
Click("showall"); P("show all -> editing: " .. Editing())
Click("back"); P("back -> step 2, editing: '" .. Editing() .. "'")
Click("next"); Click("next"); Page("step 4")
Click("place:arrange"); Click("next")
P("finished: open=" .. tostring(Open()) .. " setupDone=" .. tostring(CircletDB.setupDone) .. " seen loot=" .. tostring(CircletDB.seenNew and CircletDB.seenNew.loot))
P("arrange -> editing: " .. Editing())
Slash("edit"); Advance(1); P("after /circ edit: editing '" .. Editing() .. "'")
-- A reload or the next login: nothing opens.
Fire("PLAYER_ENTERING_WORLD", false, true); Advance(8); P("after a reload, open: " .. tostring(Open()))
-- /circ setup brings it back; Esc (hiding it) closes it.
Slash("setup"); P("/circ setup, open: " .. tostring(Open())); NS.Setup.frame:Hide()
Slash("new"); Page("/circ new (all seen: the newest release anyway)"); Click("done"); P("done, open: " .. tostring(Open()))
''')
report(lua, "first run")

# 2. An existing player updates: settings saved before, no New in tracking yet.
lua = boot('CircletDB = { xpSize = 150, loginFx = false }; CircletProfiles = { profiles = {}, chars = {} }')
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(3)
P("existing player, 3s after login: open=" .. tostring(Open()) .. " setupDone=" .. tostring(CircletDB.setupDone))
Page("new in")
Click("new:loot"); Click("shownew:ready"); P("loot off, show ready -> loot=" .. tostring(CircletDB.lootEnabled) .. " editing: " .. Editing())
Click("done"); P("done: open=" .. tostring(Open()) .. " editing: '" .. Editing() .. "' seen ready=" .. tostring(CircletDB.seenNew.ready))
Fire("PLAYER_ENTERING_WORLD", true, false); Advance(3); P("next login, open: " .. tostring(Open()))
-- A later release adds something: only that is new.
NS.RegisterRing({ key = "fake", name = "Fake", since = "1.3.0", toggle = { "Fake ring", "A ring from the future." },
                  defaults = { fakeEnabled = true }, edit = { set = function() end, get = function() return false end } })
Fire("PLAYER_ENTERING_WORLD", true, false); Advance(3); Page("a later release")
Click("full"); Page("full setup from the New in page")
''')
report(lua, "update")

# 3. First run in combat: it waits for the fight to end.
lua = boot('IN_COMBAT = true')
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(8)
P("in combat, 8s after login, open: " .. tostring(Open()))
IN_COMBAT = false; Fire("PLAYER_REGEN_ENABLED"); Advance(0.1); P("combat over, open: " .. tostring(Open()))
''')
report(lua, "combat")
