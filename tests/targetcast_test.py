from lupa import LuaRuntime

def boot(before=''):
    """A game with Circlet loaded, an enemy target, and cooldowns that record what they're told."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open('mock.lua').read())
    lua.execute('local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; f._kind2 = k; return f end')
    s = open('liveedit_test.py').read()
    exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")], {'lua': lua})
    lua.execute('''
OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end
RegionMethods.EnableMouse = function(s, v) s._mouse = v end
print = function() end
-- Cooldowns: remember the swipe texture, how they were started, at what rate, and the numbers.
RegionMethods.SetSwipeTexture = function(s, t) s._swipe = t end
RegionMethods.SetCooldownFromDurationObject = function(s, d) s._fed = d.kind; s._rate = d.rate or 1 end
RegionMethods.SetCooldown = function(s, start, total, rate) if NO_SETCOOLDOWN then error("no") end s._fed = "SetCooldown"; s._rate = rate or 1 end
-- With NO_SETCOOLDOWN, every other way of setting a rate refuses too (as secret values might).
for _, m in ipairs({ "SetCooldownDuration", "SetCooldownModRate", "SetModRate" }) do
  RegionMethods[m] = function(s, a, b) if NO_SETCOOLDOWN then error("refused") end s._fed = m; s._rate = b or a end
end
RegionMethods.SetHideCountdownNumbers = function(s, v) s._hideNumbers = v end
RegionMethods.SetRotation = function(s, r) s._rot = r end
RegionMethods.SetSize = function(s, w, h) s._w, s._h = w, h end
-- An enemy casting, with its times hidden (secret) when HIDE is on.
SECRET = {}; issecretvalue = function(v) return v == SECRET end
UNITS.target = { name = "Venomweb Spider", guid = "G9", hostile = true }
CASTING = nil; HIDE = false
function UnitCastingInfo(u)
  if u ~= "target" or not CASTING then return nil end
  if HIDE then return SECRET, nil, SECRET, SECRET, SECRET, nil, nil, SECRET, SECRET end
  return "Venom Spit", nil, 136016, CASTING.start * 1000, (CASTING.start + 4) * 1000, nil, nil, false, 24011
end
function UnitChannelInfo() return nil end
-- The cast's duration, as an object the addon may pass on but not read.
function UnitCastingDuration(u)
  if not CASTING then return nil end
  return { kind = "the cast's duration", GetStartTime = function() return SECRET end, GetTotalDuration = function() return SECRET end }
end
C_DurationUtil = { CreateDuration = function() return { kind = "a slowed copy",
  SetTimeFromStart = function(self, start, total, rate) self.rate = rate end } end }
''')
    lua.execute(before)
    ns = lua.table()
    lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", ns)
    lua.globals().NS = ns
    lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD"); Advance(1)
F = nil; for _, f in ipairs(allFrames) do if f.sqKey == "targetCast" then F = f end end
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
function Timer()
  local w; for _, f in ipairs(allFrames) do if f._parent == F and f._kind2 == "Frame" and f.cd then w = f end end
  if not (w and w._shown) then return "no timer" end
  local cd = w.cd
  return string.format("timer %dx%d, swipe %s, fed %s at rate %s, numbers from %s",
    w._w or 0, w._h or 0, tostring(cd._swipe):gsub(".*\\\\", ""), tostring(cd._fed), tostring(cd._rate),
    cd._hideNumbers and "the second cooldown" or "the sweep")
end
function S(l) local n = 0 for _, x in ipairs(F.fill) do if x._shown ~= false and x._x1 then n = n + 1 end end
  P(string.format("%-34s fill=%2d | %s | %s", l, n, T(F), Timer())) end
function Cast() CASTING = { start = NOW }; Fire("UNIT_SPELLCAST_START", "target", "Cast-1", HIDE and SECRET or 24011) end
function StopCast() CASTING = nil; Fire("UNIT_SPELLCAST_STOP", "target", "Cast-1", HIDE and SECRET or 24011); Advance(3) end
''')
    return lua

def report(lua, title):
    print("######## " + title)
    print("\n".join(lua.eval("OUT").values()))
    d = lua.eval("CircletDB.targetCastDiag")
    print("diag:", sorted((k, v) for k, v in dict(d).items() if k != "at") if d else "none")  # (not its time)
    print("ERRORS:", dict(lua.eval("ERRORS")))

# 1. Times readable: the ring's own fill, no game timer.
lua = boot()
lua.execute('Cast(); Advance(2); S("readable, 2s of 4"); StopCast()')
report(lua, "readable")

# 2. Hidden, full ring: the game's sweep on the ring band at normal speed.
lua = boot()
lua.execute('HIDE = true; CircletDB.targetCastShape = "ring"; Cast(); Advance(1); S("hidden, ring"); StopCast(); S("after the cast")')
report(lua, "hidden ring")

# 3. Hidden, half arc: the sweep slowed to half, so it covers just the arc; numbers from the second cooldown.
lua = boot()
lua.execute('HIDE = true; CircletDB.targetCastShape = "half"; Cast(); Advance(1); S("hidden, half arc"); StopCast()')
lua.execute('CircletDB.targetCastShape = "arc"; Cast(); Advance(1); S("hidden, three-quarter arc"); StopCast()')
report(lua, "hidden arcs")

# 4. No C_DurationUtil: the cooldown's own rate instead.
lua = boot('C_DurationUtil = nil')
lua.execute('HIDE = true; CircletDB.targetCastShape = "half"; Cast(); Advance(1); S("half arc, SetCooldown rate"); StopCast()')
report(lua, "no duration util")

# 5. Neither works: a disc in the arc's middle.
lua = boot('C_DurationUtil = nil; NO_SETCOOLDOWN = true')
lua.execute('HIDE = true; CircletDB.targetCastShape = "half"; Cast(); Advance(1); S("half arc, can\'t slow it"); StopCast()')
report(lua, "disc fallback")
