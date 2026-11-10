# Textures are tracked from the start (the badges are made when the rings load).
HOOK = '''
ALL_TEX = {}
local orig = RegionMethods.CreateTexture
RegionMethods.CreateTexture = function(self, ...) local t = orig(self, ...); t._parent = self; table.insert(ALL_TEX, t); return t end
'''
head = open('breath_test.py').read().split("lua.execute('''\nFire(\"ADDON_LOADED\"")[0]
head = head.replace("lua.execute(open('mock.lua').read())", "lua.execute(open('mock.lua').read())\nlua.execute(HOOK)", 1)
exec(head)
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function Ring(key) for _, f in ipairs(allFrames) do if f.editHint and f.sqKey == key then return f end end end
-- The ring's icon: where its badge sits, how big, above or below the ring, how opaque.
function Icon(key, path)
  local ring = Ring(key)
  for _, t in ipairs(ALL_TEX) do
    local b = t._parent
    if t._texpath and tostring(t._texpath):match(path) and b and b._shown and b._pt and (b._parent == ring or b._parent == ring._parent) then
      local where = math.abs(b._pt.y) < 0.01 and "middle" or string.format("top edge (y=%.0f)", b._pt.y)
      local layer = (b._level or 1) < (ring._level or 1) and "behind the ring" or "over the ring"
      local alpha = (t._alpha or 1) * (b._alpha or 1) / math.max(ring._alpha or 1, 0.01)
      return string.format("%s, %.0f wide, %s, alpha %.2f", where, t._w or 0, layer, alpha)
    end
  end
  return "(no icon)"
end
local function Show(label, key, path, slash)
  Slash(slash); Advance(1.2); P(label .. ": " .. Icon(key, path)); Advance(16)
end
Show("cast, badge", "cast", "FlameBolt", "cast")
CircletDB.castIconBg = true
Show("cast, background", "cast", "FlameBolt", "cast")
CircletDB.castIconBgAlpha = 70
Show("cast, background 70%", "cast", "FlameBolt", "cast")
CircletDB.castIconBg = false
Show("cast, back to badge", "cast", "FlameBolt", "cast")
CircletDB.gatherIconBg = true
Show("gather, background", "gather", "Mining", "gather")
CircletDB.skillIconStyle = "game"
Show("skill, badge", "skill", "Icons", "skill")
CircletDB.skillIconBg = true
Show("skill, background", "skill", "Icons", "skill")
CircletDB.skillIconBg = false
Show("skill, back to badge", "skill", "Icons", "skill")
P("totem has no option: " .. tostring(CircletDB.totem1IconBg) .. " " .. tostring(CircletDB.totemIconBg))
P("xp has no option: " .. tostring(CircletDB.xpIconBg))
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
