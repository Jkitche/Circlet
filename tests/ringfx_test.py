# Ring animations: loot roll dice, the timed quest hourglass, the flight ring's arrow and
# clouds, and the profession / weapon skill effects. Each ring's preview, with and without
# its Animations option, counting the pieces drawn.
from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; if n then _G[n] = f end return f end
wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
''')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
lua.execute('OUT = {}; function P(...) local t = {} for i=1,select("#",...) do t[i]=tostring((select(i,...))) end table.insert(OUT, table.concat(t," ")) end')
NSX = lua.table(); lua.globals().NS = NSX
lua.eval('function(s) return load(s, "@b") end')(open('bundle.lua').read())("Circlet", NSX)
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
local function Shown(list) local n = 0 for _, t in pairs(list or {}) do if t._shown then n = n + 1 end end return n end

function Dice()
  local p = NS.LootFxParts(); if not p then return "none" end
  local body, pips, glints = 0, 0, 0
  for _, d in ipairs(p.dice) do
    if d.body._shown then body = body + 1 end
    pips = pips + Shown(d.pips)
    if d.glint._shown then glints = glints + 1 end
  end
  return string.format("dice=%d pips=%d glints=%d redglow=%s sparkles=%d", body, pips, glints,
    tostring(p.glow._shown and true or false), Shown(p.sparkles))
end
function Sand()
  local p = NS.TimedSandParts(); if not p then return "none" end
  return string.format("pile=%d grains=%d", Shown(p.chords), Shown(p.grains))
end
function Flight()
  local p = NS.FlightFxParts(); if not p then return "none" end
  return string.format("arrow=%s trail=%d clouds=%d streaks=%d dust=%d", tostring(p.arrow._shown and true or false),
    Shown(p.trail), Shown(p.clouds), Shown(p.streaks), Shown(p.dust))
end
function Skill(key)
  for _, f in ipairs(allFrames) do
    if f.sqKey == key then
      local p = NS.SkillFxPools()[f]; if not p then return "none" end
      return string.format("glows=%d stars=%d lines=%d", Shown(p.glow), Shown(p.star), Shown(p.line))
    end
  end
  return "no ring"
end

-- Loot: rattling while you decide (an epic: sparkles), then tossed when you roll at 6 s.
Slash("loot"); Advance(1); P("loot deciding:  " .. Dice())
Advance(5.3); P("loot tossed:    " .. Dice())
Advance(0.8); P("loot settling:  " .. Dice())
Advance(5); P("loot rolled, late: " .. Dice()); Advance(20)
CircletDB.lootFx = false; Slash("loot"); Advance(1); P("loot fx off:    " .. Dice()); Advance(20); CircletDB.lootFx = true

-- Timed: the pile grows as time drains, grains pouring onto it.
Slash("timed"); Advance(0.5); P("timed start (fill end under the sand): " .. Sand())
Advance(6); P("timed later:    " .. Sand()); Advance(20)
CircletDB.timedFx = false; Slash("timed"); Advance(3); P("timed fx off:   " .. Sand()); Advance(20); CircletDB.timedFx = true

-- Flight: the arrow and contrail at the end of the fill, clouds and wind.
Slash("flight"); Advance(2); P("flight:         " .. Flight())
Advance(10); P("flight no data: " .. Flight()); Advance(20)
CircletDB.flightFx = false; Slash("flight"); Advance(2); P("flight fx off:  " .. Flight()); Advance(20); CircletDB.flightFx = true

-- Skills: the spark while the fill rises, the burst when it lands.
Slash("skill"); Advance(0.3); P("skill rising:   " .. Skill("skill"))
Advance(1.2); P("skill landed:   " .. Skill("skill")); Advance(30)
Slash("weapon"); Advance(0.3); P("weapon rising:  " .. Skill("weapon"))
Advance(1.2); P("weapon landed:  " .. Skill("weapon")); Advance(30)
CircletDB.skillFx = false; CircletDB.weaponFx = false
Slash("skill"); Slash("weapon"); Advance(0.3); P("skills fx off:  " .. Skill("skill") .. " | " .. Skill("weapon")); Advance(30)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
