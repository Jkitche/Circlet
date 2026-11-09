exec(open('breath_test.py').read().split("lua.execute('''\nFire(\"ADDON_LOADED\"")[0])
lua.execute('''
local function F(name, parent) local f = CreateFrame("Frame", name, parent or UIParent); f._alpha = 1; f.IsMouseEnabled = function(s) return s._mouse ~= false end; f.EnableMouse = function(s, v) s._mouse = v end; return f end
StatusTrackingBarInfo = { BarsEnum = { Reputation = 1, Experience = 4 } }
local main = F("MainStatusTrackingBarContainer"); main.shownBarIndex = 4
local sec = F("SecondaryStatusTrackingBarContainer"); sec.shownBarIndex = 1
local cast = F("PlayerCastingBarFrame"); cast:Hide()
F("MirrorTimerContainer"); F("TotemFrame"); F("QuestTimerFrame")
C_Spell = C_Spell or {}; C_Spell.GetSpellName = function(id) return ({[2575]="Mining"})[id] end
UnitCastingInfo = function() if CASTING then return "Mining", "", 0, NOW*1000, NOW*1000 + 2000, false, "g", false, 2575 end end
''')
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
local function a(n) local f = _G[n]; return string.format("%s=%.0f%s", n:gsub("StatusTrackingBarContainer", ""), f:GetAlpha() or 1, f._mouse == false and "(nomouse)" or "") end
local function all() return table.concat({ a("MainStatusTrackingBarContainer"), a("SecondaryStatusTrackingBarContainer"), a("PlayerCastingBarFrame"), a("MirrorTimerContainer"), a("TotemFrame"), a("QuestTimerFrame") }, " ") end
P("defaults: " .. all())
CircletDB.xpHideDefault = true; Advance(0.5); P("xp hide: " .. all())
CircletDB.repHideDefault = true; CircletDB.breathHideDefault = true; CircletDB.totemHideDefault = true; CircletDB.timedHideDefault = true; Advance(0.5); P("all hide: " .. all())
MainStatusTrackingBarContainer.shownBarIndex = 1; SecondaryStatusTrackingBarContainer.shownBarIndex = 2; CircletDB.repHideDefault = false; Advance(0.5); P("main shows rep (rep off), sec honor: " .. all())
CircletDB.gatherHideDefault = true; CASTING = true; PlayerCastingBarFrame:Show(); Fire("UNIT_SPELLCAST_START", "player", "g", 2575); Advance(0.5); P("gathering: " .. a("PlayerCastingBarFrame"))
CASTING = nil; Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2575); Advance(0.5); P("done, bar still fading: " .. a("PlayerCastingBarFrame"))
PlayerCastingBarFrame:Hide(); Advance(0.5); P("bar hidden -> restored: " .. a("PlayerCastingBarFrame"))
for _, k in ipairs({"xp","rep","breath","totem","timed","gather"}) do CircletDB[k .. "HideDefault"] = false end; Advance(0.5); P("all off: " .. all())
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
