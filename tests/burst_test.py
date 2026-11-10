HOOK = '''
ALL_TEX = {}
local orig = RegionMethods.CreateTexture
RegionMethods.CreateTexture = function(self, ...) local t = orig(self, ...); t._parent = self; table.insert(ALL_TEX, t); return t end
'''
head = open('breath_test.py').read().split("lua.execute('''\nFire(\"ADDON_LOADED\"")[0]
head = head.replace("lua.execute(open('mock.lua').read())", "lua.execute(open('mock.lua').read())\nlua.execute(HOOK)", 1)
exec(head)
lua.execute('''
local names = { [3365]="Opening", [133]="Fireball", [2575]="Mining", [7620]="Fishing", [3275]="Linen Bandage" }
C_Spell = C_Spell or {}; C_Spell.GetSpellName = function(id) return names[id] end
C_Spell.GetSpellTexture = function(id) return "Interface\\\\Icons\\\\Spell" .. id end
C_Spell.GetSpellInfo = function(id) return { castTime = 2000 } end
CAST, CHAN = nil, nil
function UnitCastingInfo() if CAST then return CAST.name, "", "tex", CAST.s * 1000, CAST.e * 1000 end end
function UnitChannelInfo() if CHAN then return CHAN.name, "", "tex", CHAN.s * 1000, CHAN.e * 1000 end end
SOFT = nil -- the soft-interact target: { guid, name }
function UnitGUID(u) if u == "softinteract" and SOFT then return SOFT.guid end end
function UnitName(u) if u == "softinteract" and SOFT then return SOFT.name end end
C_NamePlate = { GetNamePlateForUnit = function() end, GetNamePlates = function() return {} end }
C_Item = { GetItemIconByID = function(id) return "Interface\\\\Icons\\\\Item" .. id end }
''')
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
function Ring(key) for _, f in ipairs(allFrames) do if f.editHint and f.sqKey == key then return f end end end
-- The ring's icon (its size and opacity) and the burst (glow, how many sparks showing).
function Icon(key)
  local ring = Ring(key)
  if not ring._shown then return "(hidden)" end
  local icon, glow, sparks = nil, false, 0
  for _, t in ipairs(ALL_TEX) do
    local b = t._parent
    if b and b._parent == ring and b._shown and t._shown ~= false then
      local p = tostring(t._texpath or "")
      if p:match("Icons") then icon = t
      elseif p:match("Glow") and (t._alpha or 0) > 0.01 then glow = true
      elseif p:match("star4") and (t._alpha or 0) > 0.01 then sparks = sparks + 1 end
    end
  end
  if not icon then return "(no icon)" end
  return string.format("icon %s %.0f wide, alpha %.2f | burst: glow %s, %d sparks",
    tostring(icon._texpath):match("[^\\\\]+$"), icon._w or 0, icon._alpha or 1, glow and "yes" or "no", sparks)
end
local n = 0
local function Go(spell, name, dur) n = n + 1; CAST = { name = name, s = NOW, e = NOW + dur }; Fire("UNIT_SPELLCAST_START", "player", "c" .. n, spell); return "c" .. n end
local function Done(cg, spell) CAST = nil; Fire("UNIT_SPELLCAST_STOP", "player", cg, spell); Fire("UNIT_SPELLCAST_SUCCEEDED", "player", cg, spell) end

-- Cast ring, icon as a badge: a spell doesn't burst.
local c = Go(133, "Fireball", 2); Advance(1.5); P("cast, casting:      " .. Icon("cast"))
Advance(0.45); Done(c, 133); Advance(1/30); P("cast, just done:    " .. Icon("cast"))
Advance(0.15); P("cast, +0.17s:       " .. Icon("cast"))
Advance(0.4); P("cast, +0.57s:       " .. Icon("cast"))
Advance(0.3); P("cast, +0.87s:       " .. Icon("cast")); Advance(4)
-- Interrupted: no burst.
c = Go(133, "Fireball", 2); Advance(1); CAST = nil; Fire("UNIT_SPELLCAST_INTERRUPTED", "player", c, 133); Fire("UNIT_SPELLCAST_STOP", "player", c, 133)
Advance(0.17); P("cast, interrupted:  " .. Icon("cast")); Advance(4)

-- Icon as background: dimmed while casting, opaque once done (no burst for a spell).
CircletDB.castIconBg = true
c = Go(133, "Fireball", 2); Advance(1.5); P("bg, casting:        " .. Icon("cast"))
Advance(0.45); Done(c, 133); Advance(0.17); P("bg, +0.17s:         " .. Icon("cast"))
Advance(0.6); P("bg, +0.77s:         " .. Icon("cast")); Advance(4)
c = Go(133, "Fireball", 2); Advance(1); CAST = nil; Fire("UNIT_SPELLCAST_INTERRUPTED", "player", c, 133); Fire("UNIT_SPELLCAST_STOP", "player", c, 133)
Advance(0.17); P("bg, interrupted:    " .. Icon("cast")); Advance(4)

-- An interaction in the cast ring (opening a chest) does burst.
CircletDB.castIconBg = false
SOFT = { guid = "GameObject-chest", name = "Battered Chest" }
n = n + 1; Fire("UNIT_SPELLCAST_SENT", "player", "Battered Chest", "c" .. n, 3365)
CAST = { name = "Opening", s = NOW, e = NOW + 2 }; Fire("UNIT_SPELLCAST_START", "player", "c" .. n, 3365); Advance(1.95)
Done("c" .. n, 3365); Advance(0.17); P("opening a chest:    " .. Icon("cast")); SOFT = nil; Advance(5)
-- A spell cast while facing the chest still doesn't.
SOFT = { guid = "GameObject-chest", name = "Battered Chest" }
n = n + 1; Fire("UNIT_SPELLCAST_SENT", "player", "Kobold Vermin", "c" .. n, 133)
CAST = { name = "Fireball", s = NOW, e = NOW + 2 }; Fire("UNIT_SPELLCAST_START", "player", "c" .. n, 133); Advance(1.95)
Done("c" .. n, 133); Advance(0.17); P("fireball by chest:  " .. Icon("cast")); SOFT = nil; Advance(5)

-- Gathering: bursts when it's done; the item's icon takes over mid-burst.
c = Go(2575, "Mining", 2); Advance(1.95); Done(c, 2575); Advance(0.1)
Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2770::::::::|h[Copper Ore]|h|rx2."); Advance(0.07); P("mining, loot in:    " .. Icon("gather"))
Advance(0.8); P("mining, +1s:        " .. Icon("gather")); Advance(5)
-- Fishing: bursts on a catch, not when it gets away.
CHAN = { name = "Fishing", s = NOW, e = NOW + 20 }; Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "f1", 7620); Advance(3)
CHAN = nil; Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "f1", 7620); Advance(0.3); P("fishing, reeling:   " .. Icon("gather"))
Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:6303::::::::|h[Raw Slitherskin Mackerel]|h|r."); Advance(0.1); P("fishing, caught:    " .. Icon("gather")); Advance(5)
CHAN = { name = "Fishing", s = NOW, e = NOW + 20 }; Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "f2", 7620); Advance(3)
CHAN = nil; Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "f2", 7620); Advance(2); P("fishing, got away:  " .. Icon("gather")); Advance(5)

-- Crafting previews: the batch that finishes bursts.
CircletDB.craftIconBg = true; Slash("craft"); Advance(12.1); P("craft, batch done:  " .. Icon("craft")); Advance(0.6); P("craft, +0.7s:       " .. Icon("craft")); Advance(20)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
