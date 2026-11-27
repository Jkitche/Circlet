from lupa import LuaRuntime


def boot(before=''):
    """A fresh game with Circlet loaded; `before` runs first (saved variables, say)."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open('mock.lua').read())
    lua.execute(
        'local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end'
    )
    s = open('liveedit_test.py').read()
    exec(s[s.index("lua.execute('''\nUIParent._w") : s.index("chunk = lua.eval")], {'lua': lua})
    lua.execute('''
OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end
RegionMethods.EnableMouse = function(s, v) s._mouse = v end
-- Chat lines, sounds and the big on-screen text, as lines of the output.
print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
  local line = table.concat(t, " "); if not line:find("options window") then P("chat: " .. line) end end -- (the mock has no options libraries)
PlaySound = function(id, channel) P("sound: " .. tostring(id) .. " " .. tostring(channel)) end
SOUNDKIT = { RAID_WARNING = 8959 }
RaidWarningFrame = {}
RaidNotice_AddMessage = function(_, text) P("on screen: " .. text) end
-- The clock time, in step with the game's time.
CLOCK = 1800000000; time = function() return CLOCK + math.floor(NOW) end
''')
    lua.execute(before)
    ns = lua.table()
    lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", ns)
    lua.globals().NS = ns
    lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD"); Advance(1)
F = nil; for _, f in ipairs(allFrames) do if f.sqKey == "timer" then F = f end end
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function S(l) local n = 0 for _, x in ipairs(F.fill) do if x._shown ~= false and x._x1 then n = n + 1 end end
  P(string.format("%-34s shown=%s fill=%2d | %s", l, tostring(F._shown), n, T(F))) end
''')
    return lua


def report(lua, title):
    print("######## " + title)
    print("\n".join(lua.eval("OUT").values()))
    print("ERRORS:", dict(lua.eval("ERRORS")))


# 1. Reading times.
lua = boot()
lua.execute('''
for _, text in ipairs({ "90", "90s", "5m Tea", "5M", "1h", "1h30m", "2m30s", "1:30", "1:02:03 Long raid",
                        "10 min Pull", "2 hours", "2.5m", "soon", "5x", "1:2:3:4", "0" }) do
  local secs, label = NS.ParseTimer(text)
  P(string.format("%-20s -> %s %s", text, tostring(secs), label and ("[" .. label .. "]") or ""))
end
''')
report(lua, "parsing")

# 2. Start, run down, time's up, gone.
lua = boot()
lua.execute('''
S("idle")
Slash("timer 5m Tea"); Advance(1); S("5m Tea, 1s in")
Advance(150); S("halfway")
Advance(140); S("9s left (pulsing)")
Slash("timer"); Advance(0.1)
Advance(10); S("time's up")
P("saved after time's up: " .. tostring(CircletDB.timerRun))
Advance(10); S("after the hold")
-- +2m with nothing running starts one; +1m adds to it.
Slash("timer +2m"); Advance(1); S("+2m (started)")
Slash("timer +1m Stew"); Advance(1); S("+1m Stew (added, relabelled)")
Slash("timer stop"); Advance(2); S("stopped")
Slash("timer stop"); Slash("timer")
Slash("timer soon"); Slash("timer 25h"); Slash("timer 0")
Slash("countdown 1:30 Pull"); Advance(1); S("countdown 1:30 Pull")
Slash("timer cancel"); Advance(2)
-- Sound and big text off: just the chat line.
CircletDB.timerSound = false; CircletDB.timerAlert = false
Slash("timer 3"); Advance(4); S("3s, sound and text off")
Advance(10)
-- Turned off: it still runs (and says so), but there's no ring.
CircletDB.timerEnabled = false; Slash("timer 1m"); Advance(1); S("ring off")
Slash("timer stop"); CircletDB.timerEnabled = true
Slash("timer"); Slash("help")
''')
report(lua, "running")

# 3. Through a reload: the saved end time picks up where it left off (the mock clock starts at 1000 s).
lua = boot('CircletDB = { timerRun = { endsAt = 1800000000 + 1000 + 120, total = 300, label = "Raid" } }')
lua.execute('''
S("after a reload, 2 min of 5 left")
Advance(119); S("2s before the end")
Advance(3); S("time's up")
''')
report(lua, "reload")

# 4. It ran out while you were logged out.
lua = boot('CircletDB = { timerRun = { endsAt = 1800000000 - 600, total = 300, label = "Mailbox" } }')
lua.execute('''
S("logged back in")
P("saved: " .. tostring(CircletDB.timerRun))
Slash("timer"); Slash("edit timer"); Advance(1); S("edit mode sample"); Slash("edit timer"); Advance(2)
''')
report(lua, "away")
