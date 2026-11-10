exec(open('breath_test.py').read().split("lua.execute('''\nFire(\"ADDON_LOADED\"")[0])
lua.execute('''
local names = { [133]="Fireball", [2006]="Resurrection", [99999]="Resurrection", [7328]="Redemption" }
C_Spell = C_Spell or {}; C_Spell.GetSpellName = function(id) return names[id] end
C_Spell.GetSpellTexture = function(id) return "icon" .. id end
C_Spell.GetSpellInfo = function(id) return { castTime = (id == 133 and 2500) or 10000 } end
CAST = nil
function UnitCastingInfo() if CAST then return "x", "", "tex", CAST.s * 1000, CAST.e * 1000 end end
function UnitChannelInfo() end
ALL_TEX = {}
local orig = RegionMethods.CreateTexture
RegionMethods.CreateTexture = function(self, ...) local t = orig(self, ...); t._parent = self; table.insert(ALL_TEX, t); return t end
''')
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
CircletDB.castSchoolFx = false -- only the resurrection animation here (see school_test)
function Ring() for _, f in ipairs(allFrames) do if f.editHint and f.sqKey == "cast" then return f end end end
function T(f) local t = {} for _, g in ipairs(ALL_FS) do if g._parent == f and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then table.insert(t, tostring(g._text)) end end return table.concat(t, " / ") end
-- What the effect is showing: motes / halo / pillar / ring glow+wave lines.
function FX()
  local f = Ring(); if not f._shown then return "(hidden)" end
  local motes, glows, big = 0, 0, 0
  for _, t in ipairs(ALL_TEX) do
    if t._parent == f and t._shown and t._texpath and (t._alpha or 1) > 0.01 then
      if t._texpath:match("star4") then motes = motes + 1
      elseif t._texpath:match("Glow") then glows = glows + 1; if (t._h or 0) > (t._w or 0) * 1.5 then big = big + 1 end end
    end
  end
  local lines = 0
  for _, l in ipairs(ALL_LINES) do if l._parent == f and l._shown and l._layer == "OVERLAY" then lines = lines + 1 end end
  return string.format("[%s] motes=%d glows=%d pillar=%s ringfx=%s", T(f), motes, glows, big > 0 and "yes" or "no", lines > 0 and "yes" or "no")
end
local function Go(id, g, dur, how)
  CAST = { s = NOW, e = NOW + dur }; Fire("UNIT_SPELLCAST_START", "player", g, id)
  Advance(dur * 0.6); P(id .. " casting: " .. FX())
  if how == "done" then
    Advance(dur * 0.4 - 0.05); CAST = nil
    Fire("UNIT_SPELLCAST_STOP", "player", g, id); Fire("UNIT_SPELLCAST_SUCCEEDED", "player", g, id)
  else
    Fire("UNIT_SPELLCAST_INTERRUPTED", "player", g, id); CAST = nil; Fire("UNIT_SPELLCAST_STOP", "player", g, id)
  end
  Advance(0.3); P(id .. " " .. how .. " +0.3s: " .. FX())
  Advance(1.0); P(id .. " " .. how .. " +1.3s: " .. FX())
  Advance(4); P(id .. " later: " .. FX())
end
Go(133, "g1", 2.5, "done")      -- an ordinary cast: no effect
Go(2006, "g2", 10, "done")      -- Resurrection: motes while casting, then the burst
Go(99999, "g3", 10, "done")     -- an unlisted rank, matched by name
Go(7328, "g4", 10, "interrupted")
CircletDB.castRezFx = false
Go(2006, "g5", 10, "done")      -- animation off: the plain ring
CircletDB.castRezFx = true
Slash("cast"); Advance(7.5); P("preview rez: " .. FX()); Advance(2.0); P("preview rez done: " .. FX())
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
