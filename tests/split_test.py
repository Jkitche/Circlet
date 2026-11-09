exec(open('breath_test.py').read().split("lua.execute('''\nFire(\"ADDON_LOADED\"")[0])
lua.execute('''
LINES = { {name="Swords", skillID=43, rank=10, maxRank=50, skillLineCategoryID=6}, {name="Mining", skillID=186, rank=20, maxRank=75, skillLineCategoryID=11} }
C_SkillInfo = { GetNumSkillLines = function() return #LINES end, GetSkillLineInfo = function(i) return LINES[i] end }
''')
lua.execute('''
CircletDB = { skillWeapons = true, skillColors = { weapon = { r = 0.1, g = 0.2, b = 0.3 }, profession = { r = 0.32, g = 0.82, b = 0.36 } }, skillSize = 150, skillStyle = "segmented" }
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
P("migrated: weaponColors.fill.b=" .. CircletDB.weaponColors.fill.b .. " weaponSize=" .. CircletDB.weaponSize .. " weaponStyle=" .. CircletDB.weaponStyle .. " skillColors.weapon=" .. tostring(CircletDB.skillColors.weapon) .. " weaponX=" .. CircletDB.weaponX)
local function ShownRing() local t = {} for _, f in ipairs(allFrames) do if f.editHint and f._shown and f.sqKey then table.insert(t, f.sqKey) end end return table.concat(t, ",") end
Fire("SKILL_LINES_CHANGED"); Advance(0.5)
LINES[1].rank = 11; Fire("SKILL_LINES_CHANGED"); Advance(0.5); P("sword up: " .. ShownRing()); Advance(8)
LINES[2].rank = 21; Fire("SKILL_LINES_CHANGED"); Advance(0.5); P("mining up: " .. ShownRing()); Advance(8)
Fire("PLAYER_REGEN_DISABLED"); LINES[1].rank = 12; Fire("SKILL_LINES_CHANGED"); Advance(1); P("sword in combat: " .. ShownRing())
Fire("PLAYER_REGEN_ENABLED"); Advance(1); P("after combat: " .. ShownRing()); Advance(8)
CircletDB.weaponEnabled = false; LINES[1].rank = 13; Fire("SKILL_LINES_CHANGED"); Advance(1); P("weapon ring off: '" .. ShownRing() .. "'")
Slash("weapon"); Advance(1); P("preview weapon: " .. ShownRing()); Advance(15); Slash("skill"); Advance(1); P("preview skill: " .. ShownRing())
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
