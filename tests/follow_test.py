exec(open('breath_test.py').read().split("lua.execute('''\nFire(\"ADDON_LOADED\"")[0])
lua.execute('''
local names = { [8613]="Skinning", [2575]="Mining", [2366]="Herb Gathering", [7620]="Fishing", [3365]="Opening", [8690]="Hearthstone", [133]="Fireball" }
C_Spell = C_Spell or {}; C_Spell.GetSpellName = function(id) return names[id] end
C_Spell.GetSpellTexture = function(id) return "icon" .. id end
C_Spell.GetSpellInfo = function(id) return { castTime = 2000 } end
CAST = nil
function UnitCastingInfo() if CAST then return CAST.name, "", "tex", CAST.s * 1000, CAST.e * 1000 end end
function UnitChannelInfo() end
CVARS = { SoftTargetNameplateInteract = "0", SoftTargetInteract = "3" }
function GetCVar(k) return CVARS[k] end
function SetCVar(k, v) CVARS[k] = tostring(v) end
-- The world: things with GUIDs and names; which one is the soft-interact target; which
-- have a visible nameplate (and where).
THINGS = {}
SOFT = nil
function UnitGUID(u) if u == "softinteract" then return SOFT end local t = THINGS[u] return t and t.guid end
function UnitName(u) local g = (u == "softinteract") and SOFT or (THINGS[u] and THINGS[u].guid) if g then return THINGS[g].name end end
PLATES = {}
local tokens = 0
local function Plate(guid, token)
  local p = CreateFrame("Frame"); p._shown = true; p.guid = guid; p.namePlateUnitToken = token
  p.GetCenter = function(s) return THINGS[s.guid].x, THINGS[s.guid].y end
  p.GetEffectiveScale = function() return 1.0 end
  p.IsVisible = function(s) return s._shown end
  return p
end
function Thing(guid, name, x, y, plate)
  tokens = tokens + 1
  local token = "nameplate" .. tokens
  THINGS[guid] = { guid = guid, name = name, x = x, y = y }
  THINGS[token] = THINGS[guid]
  if plate then PLATES[guid] = Plate(guid, token) end
end
C_NamePlate = {
  GetNamePlateForUnit = function(u) local g = UnitGUID(u) return g and PLATES[g] end,
  GetNamePlates = function() local t = {} for _, p in pairs(PLATES) do table.insert(t, p) end return t end,
}
''')
lua.execute('''
CircletDB = CircletDB or {}; CircletDB.gatherFollow = true -- saved by an older version
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
local sp = RegionMethods.SetPoint
RegionMethods.SetPoint = function(s, p, rel, rp, x, y) s._rel, s._anchor = rel, rp; return sp(s, p, rel, rp, x, y) end
function Ring(key) for _, f in ipairs(allFrames) do if f.editHint and f.sqKey == key then return f end end end
function Where(key)
  local f = Ring(key); if not f._shown then return "(hidden)" end
  if f._rel == UIParent and f._pt and f._anchor == "BOTTOMLEFT" then
    return string.format("on it at %.0f,%.0f", f._pt.x * 0.8, f._pt.y * 0.8) end
  return "home spot"
end
function Face(guid) SOFT = guid; Fire("PLAYER_SOFT_INTERACT_CHANGED", nil, guid) end
local n = 0
-- Sends a cast at target (a name), then starts it; softAtStart = what the soft target is
-- once the cast has begun ("same" keeps it).
function Cast(spell, name, target, softAtStart)
  n = n + 1; local cg = "cast" .. n
  Fire("UNIT_SPELLCAST_SENT", "player", target or "", cg, spell)
  if softAtStart ~= "same" then Face(softAtStart) end
  CAST = { name = name, s = NOW, e = NOW + 2 }; Fire("UNIT_SPELLCAST_START", "player", cg, spell)
  return cg
end
function Done(cg, spell) CAST = nil; Fire("UNIT_SPELLCAST_STOP", "player", cg, spell); Fire("UNIT_SPELLCAST_SUCCEEDED", "player", cg, spell) end
function Stop(cg, spell) CAST = nil; Fire("UNIT_SPELLCAST_INTERRUPTED", "player", cg, spell); Fire("UNIT_SPELLCAST_STOP", "player", cg, spell) end

Thing("Creature-wolf", "Plainstrider", 500, 400, true)
Thing("Creature-boar", "Mottled Boar", 900, 500, true)
Thing("GameObject-vein", "Copper Vein", 700, 300, true)
Thing("GameObject-chest", "Battered Chest", 650, 350, true)
Thing("GameObject-far", "Peacebloom", 100, 100, false)

P("cvar before: " .. CVARS.SoftTargetNameplateInteract)
Face("Creature-wolf"); local c = Cast(8613, "Skinning", "Plainstrider", "same"); Advance(0.5); P("option off, skinning: " .. Where("gather")); Done(c, 8613); Advance(5)

-- Gathering never follows (the option was removed); an old saved setting is cleared on load.
P("old gatherFollow cleared: " .. tostring(CircletDB.gatherFollow))
Face("GameObject-vein"); c = Cast(2575, "Mining", "Copper Vein", "same"); Advance(0.5); P("mining: " .. Where("gather")); Done(c, 2575); Advance(5)
Face(nil)

-- Interactions in the cast ring.
Face("GameObject-chest"); c = Cast(3365, "Opening", "Battered Chest", "same"); Advance(0.5); P("opening a chest, option off: " .. Where("cast")); Stop(c, 3365); Advance(5)
CircletDB.castFollow = true; Fire("PLAYER_ENTERING_WORLD") -- as the option does (ApplyFollowCVar)
c = Cast(3365, "Opening", "Battered Chest", "same"); Advance(0.5); P("opening a chest: " .. Where("cast")); Done(c, 3365); Advance(5)
c = Cast(8690, "Hearthstone", "", "same"); Advance(0.5); P("hearthstone by the chest: " .. Where("cast")); Stop(c, 8690); Advance(5)
c = Cast(133, "Fireball", "Kobold Vermin", "same"); Advance(0.5); P("fireball at a mob by the chest: " .. Where("cast")); Stop(c, 133); Advance(5)
Face(nil)
Slash("gather"); Advance(1); P("preview: " .. Where("gather")); Advance(14)
Slash("follow")

P("interactions on: " .. CVARS.SoftTargetNameplateInteract)
CircletDB.castFollow = false; IN_COMBAT = true; Fire("PLAYER_ENTERING_WORLD"); P("off, in combat: " .. CVARS.SoftTargetNameplateInteract)
IN_COMBAT = false; Fire("PLAYER_REGEN_ENABLED"); P("off, after combat: " .. CVARS.SoftTargetNameplateInteract .. " saved=" .. tostring(CircletDB.gatherFollowCVar))
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
