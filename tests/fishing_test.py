from lupa import LuaRuntime

def boot(before=''):
    """A game with Circlet loaded, fishing, bindings and CVars the test can watch."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open('mock.lua').read())
    lua.execute('local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end')
    s = open('liveedit_test.py').read()
    exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")], {'lua': lua})
    lua.execute('''
OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end
RegionMethods.EnableMouse = function(s, v) s._mouse = v end
print = function() end
-- Where the ring is anchored (to see it bob).
RegionMethods.SetPoint = function(s, p, rel, rp, x, y) s._pt = { p = p, rel = rel, rp = rp, x = x, y = y } end
RegionMethods.GetPoint = function(s) local pt = s._pt; if pt then return pt.p, pt.rel, pt.rp, pt.x, pt.y end end
math.random = function() return 0.42 end -- the same bob every run
-- Fishing: a 30 s channel.
FISHING = nil
function UnitChannelInfo(u) if u == "player" and FISHING then return "Fishing", nil, 136245, FISHING * 1000, (FISHING + 30) * 1000 end end
function CastLine() FISHING = NOW; Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-F", 7620) end
function LineIn() FISHING = nil; Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-F", 7620) end
function Loot(item) Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:6291::::::::|h[" .. item .. "]|h|r.") end
-- Bindings and CVars.
BIND = {}; CVARS = { SoftTargetInteract = "1", SoftTargetInteractArc = "0", SoftTargetInteractRange = "10" }
SetOverrideBinding = function(owner, prio, key, cmd) if IN_COMBAT then error("combat") end BIND[key] = cmd end
ClearOverrideBindings = function(owner) if IN_COMBAT then error("combat") end BIND = {} end
C_CVar = { GetCVar = function(n) return CVARS[n] end, SetCVar = function(n, v) CVARS[n] = tostring(v) end }
function Reel() return string.format("right-click=%s interact=%s/%s/%s", tostring(BIND.BUTTON2), CVARS.SoftTargetInteract,
  CVARS.SoftTargetInteractArc, CVARS.SoftTargetInteractRange) end
''')
    lua.execute(before)
    ns = lua.table()
    lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", ns)
    lua.globals().NS = ns
    lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD"); Advance(1)
F = nil; G = nil
for _, fr in ipairs(allFrames) do if fr.sqKey == "fish" then F = fr end if fr.sqKey == "gather" then G = fr end end
function T(fr) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == fr and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
BASE_Y = nil
function S(l)
  local n, fl = 0, 0
  for _, x in ipairs(F.fill) do if x._shown ~= false and x._x1 then n = n + 1 end end
  for _, x in ipairs(F.flash) do if x._shown ~= false and x._x1 then fl = fl + 1 end end
  local y = F._pt and F._pt.y or 0
  P(string.format("%-30s shown=%s fill=%2d flash=%s y=%6.1f | %s | gather shown=%s", l, tostring(F._shown), n,
    fl > 0 and "yes" or "no", y, T(F), tostring(G and G._shown)))
end
-- The fill's end against the plain countdown, while the line is out.
function Edge(l)
  local left = FISHING and (FISHING + 30 - NOW) or 0
  local n = 0
  for _, x in ipairs(F.fill) do if x._shown ~= false and x._x1 then n = n + 1 end end
  P(string.format("%-30s countdown=%.3f fill segments=%d y=%6.1f", l, left / 30, n, F._pt and F._pt.y or 0))
end
''')
    return lua

def report(lua, title):
    print("######## " + title)
    print("\n".join(lua.eval("OUT").values()))
    print("ERRORS:", dict(lua.eval("ERRORS")))

# 1. A cast: bobbing while waiting, flashing in the bite windows, then a catch.
lua = boot()
lua.execute('''
S("idle")
CastLine(); Advance(1); S("line out, 29s left")
for i = 1, 8 do Advance(0.25); Edge("bobbing " .. i) end
Advance(10.2); S("17s left: watch!")
Advance(1.8); S("15s left")
Advance(2.2); S("13s left: watch!")
Advance(1); LineIn(); Advance(0.3); S("reeled in, loot coming")
Loot("Raw Brilliant Smallfish"); Advance(0.3); S("caught")
Advance(6); S("after the hold")
''')
report(lua, "a catch")

# 2. Time runs out; reeled in with nothing; the windows off; the gathering ring leaves fishing alone.
lua = boot()
lua.execute('''
CastLine(); Advance(30.2); LineIn(); Advance(2); S("ran out: got away")
Advance(6)
CircletDB.fishWindows = false
CastLine(); Advance(13); S("17s left, windows off")
LineIn(); Advance(2); S("reeled in, nothing")
Advance(6)
-- The fishing ring off: the gathering ring takes fishing back.
CircletDB.fishEnabled = false; CastLine(); Advance(2); S("fishing ring off")
LineIn(); Advance(6)
''')
report(lua, "misses")

# 3. Right-click to reel in: on while the line is out, off after, given back in a fight.
lua = boot()
lua.execute('''
P("before: " .. Reel())
CastLine(); Advance(1); P("reel off, line out: " .. Reel()); LineIn(); Advance(6)
CircletDB.fishReel = true
CastLine(); Advance(1); P("reel on, line out: " .. Reel()); S("label")
LineIn(); Advance(0.5); P("line in, loot window: " .. Reel())
Advance(1); P("a second later: " .. Reel())
Advance(6)
-- A fight starts mid-cast: right-click comes back at once, and returns after.
CastLine(); Advance(1)
Fire("PLAYER_REGEN_DISABLED"); IN_COMBAT = true; P("fight (the event comes just before the lockdown): " .. Reel())
Advance(2); IN_COMBAT = false; Fire("PLAYER_REGEN_ENABLED"); P("fight over, still fishing: " .. Reel())
LineIn(); Advance(2); P("done: " .. Reel())
''')
report(lua, "reel in")

# 4. The game closed mid-cast with the reel on: the CVars are put back at the next login.
lua = boot('CircletDB = { fishReel = true, fishSavedCVars = { SoftTargetInteract = "1", SoftTargetInteractArc = "0", SoftTargetInteractRange = "10" } }; CVARS = { SoftTargetInteract = "3", SoftTargetInteractArc = "2", SoftTargetInteractRange = "60" }')
lua.execute('P("after login: " .. Reel() .. " saved=" .. tostring(CircletDB.fishSavedCVars))')
report(lua, "restored after a crash")

# 5. The preview.
lua = boot()
lua.execute('Slash("fish"); Advance(1); S("preview"); Advance(2.2); S("preview, 17s left: watch!"); Advance(9); S("preview, the catch")')
report(lua, "preview")
