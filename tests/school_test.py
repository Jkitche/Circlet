HOOK = '''
ALL_TEX = {}
local orig = RegionMethods.CreateTexture
RegionMethods.CreateTexture = function(self, ...) local t = orig(self, ...); t._parent = self; table.insert(ALL_TEX, t); return t end
'''
head = open('breath_test.py').read().split("lua.execute('''\nFire(\"ADDON_LOADED\"")[0]
head = head.replace("lua.execute(open('mock.lua').read())", "lua.execute(open('mock.lua').read())\nlua.execute(HOOK)", 1)
exec(head)
lua.execute('''
-- 133/116 are on the built-in list; 9001 "Glacial Spike" and 9002 "Mystery Bolt" aren't.
local names = { [133]="Fireball", [116]="Frostbolt", [9001]="Glacial Spike", [9002]="Mystery Bolt",
  [9003]="Heroic Strike", [9004]="Vile Hex", [2006]="Resurrection", [585]="Smite" }
local icons = { [9001] = "Interface\\\\Icons\\\\Spell_Frost_IceShard", [9002] = 136000 }
C_Spell = C_Spell or {}; C_Spell.GetSpellName = function(id) return names[id] end
C_Spell.GetSpellTexture = function(id) return icons[id] or ("Interface\\\\Icons\\\\X" .. id) end
C_Spell.GetSpellInfo = function(id) return { castTime = 2000 } end
CAST = nil
function UnitCastingInfo() if CAST then return CAST.name, "", "tex", CAST.s * 1000, CAST.e * 1000 end end
function UnitChannelInfo() end
function UnitGUID(u) if u == "player" then return "Player-1" end end
-- The addon must never touch the combat log (only Blizzard's UI may here): any use fails.
COMBAT_LOG_TOUCHED = false
function CombatLogGetCurrentEventInfo() COMBAT_LOG_TOUCHED = true end
local reg = RegionMethods.RegisterEvent
RegionMethods.RegisterEvent = function(s, e) if e == "COMBAT_LOG_EVENT_UNFILTERED" then COMBAT_LOG_TOUCHED = true end return reg(s, e) end
''')
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
local ring; for _, f in ipairs(allFrames) do if f.editHint and f.sqKey == "cast" then ring = f end end
-- The effect showing: which motes, their color, and the extras (halo, dark core, rays).
function FX()
  if not ring._shown then return "(hidden)" end
  local motes, col, halo, core, rays = 0, nil, false, false, false
  for _, t in ipairs(ALL_TEX) do
    if t._parent == ring and t._shown and (t._alpha or 0) > 0.01 then
      local p = tostring(t._texpath)
      if t._layer == nil and p:match("star4") and t._blend ~= "BLEND" then end
      if p:match("Glow") then if t._blendmode == "BLEND" then core = true else halo = true end
      elseif p:match("star4") then
        if (t._w or 0) > 40 then rays = true else motes = motes + 1; col = col or t._vc end
      end
    end
  end
  local c = col and string.format(" (%.1f,%.1f,%.1f)", col[1], col[2], col[3]) or ""
  return string.format("%d motes%s%s%s%s", motes, c, halo and ", halo" or "", core and ", dark core" or "", rays and ", rays" or "")
end
local sb = RegionMethods.SetBlendMode
RegionMethods.SetBlendMode = function(s, m) s._blendmode = m; if sb then return sb(s, m) end end
local n = 0
function Go(id, name)
  n = n + 1; CAST = { name = name, s = NOW, e = NOW + 2 }; Fire("UNIT_SPELLCAST_START", "player", "c" .. n, id); return "c" .. n
end
function Done(cg, id) CAST = nil; Fire("UNIT_SPELLCAST_STOP", "player", cg, id); Fire("UNIT_SPELLCAST_SUCCEEDED", "player", cg, id) end
function Cut(cg, id) CAST = nil; Fire("UNIT_SPELLCAST_INTERRUPTED", "player", cg, id); Fire("UNIT_SPELLCAST_STOP", "player", cg, id) end
function Try(label, id, name)
  local cg = Go(id, name)
  Advance(1); P(label .. ": " .. FX())
  return cg
end

local c = Try("fireball (built-in list)", 133, "Fireball"); Advance(0.9); Done(c, 133)
Advance(0.2); P("  done +0.2s: " .. FX()); Advance(0.3); P("  done +0.5s: " .. FX()); Advance(4)
c = Try("frostbolt (built-in list)", 116, "Frostbolt"); Cut(c, 116); Advance(0.15); P("  interrupted +0.15s: " .. FX()); Advance(0.3); P("  interrupted +0.45s: " .. FX()); Advance(4)
c = Try("glacial spike (icon name)", 9001, "Glacial Spike"); Cut(c, 9001); Advance(4)
c = Try("mystery bolt (nothing known)", 9002, "Mystery Bolt"); Cut(c, 9002); Advance(4)
c = Try("smite", 585, "Smite"); Cut(c, 585); Advance(4)
c = Try("resurrection (its own animation)", 2006, "Resurrection"); Cut(c, 2006); Advance(4)
CircletDB.castSchoolFx = false
c = Try("fireball, effects off", 133, "Fireball"); Cut(c, 133); Advance(4)
CircletDB.castSchoolFx = true
-- Edit mode's samples go round every school (the first cast of each round goes off).
CircletDB.castRezFx = false
for _, f in ipairs(allFrames) do end
Slash("edit"); local seen, order = {}, {}
for i = 1, 140 do
  Advance(0.3)
  local title; for _, g in ipairs(ALL_FS) do if g._parent == ring and g._text and g._text ~= "" and not tostring(g._text):match("Drag") then title = title or tostring(g._text) end end
  local fx = FX()
  if title and not seen[title] and fx:match("motes %(") then seen[title] = fx; table.insert(order, title .. ": " .. fx) end
end
for _, line in ipairs(order) do P("sample " .. line) end
P("combat log touched: " .. tostring(COMBAT_LOG_TOUCHED))
Slash("edit")
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
