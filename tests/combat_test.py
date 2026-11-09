exec(open('breath_test.py').read().split("lua.execute('''\nFire(\"ADDON_LOADED\"")[0])
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
local ns = NS
function H(k) local h = ns.RingHolder(k); return string.format("%s a=%.2f shown=%s", k, h:GetAlpha(), tostring(h._shown ~= false)) end
CircletDB.repCombat = false; CircletDB.totemCombat = false; CircletDB.questOpacity = 50
ns.ApplyAllOpacity(); Advance(1)
P("before: " .. H("rep") .. " | " .. H("quest") .. " | " .. H("xp"))
Fire("PLAYER_REGEN_DISABLED"); Advance(0.15); P("mid-fade: " .. H("rep")); Advance(1)
P("combat: " .. H("rep") .. " | " .. H("quest") .. " | " .. H("xp") .. " | " .. H("totem1"))
Fire("PLAYER_REGEN_ENABLED"); Advance(1)
P("after: " .. H("rep") .. " | " .. H("quest") .. " | " .. H("totem1"))
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
