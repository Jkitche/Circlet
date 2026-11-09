exec(open('breath_test.py').read().split("lua.execute('''\nFire(\"ADDON_LOADED\"")[0].replace("lua.eval('function(s) return load(s, \"@b\") end')","PRE = 1; lua.eval('function(s) return load(s, \"@b\") end')"))
lua.execute('''
UnitName = function() return CHAR or "Jae" end; GetRealmName = function() return "Forever" end
''')
lua.execute('''
-- existing install: settings already in CircletDB, no profiles yet
CircletDB = { xpSize = 222, craftSingleDefaultOn = true }
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD", true, false); Advance(1)
local ns = NS
P("first load: profile=" .. ns.CurrentProfile() .. " xpSize=" .. CircletDB.xpSize .. " default saved=" .. tostring(CircletProfiles.profiles.Default.xpSize))
ns.NewProfile("  Hunter  "); P("new: " .. ns.CurrentProfile() .. " xpSize=" .. CircletDB.xpSize)
CircletDB.xpSize = 150; CircletDB.repColors.custom = { r = 0, g = 0, b = 1 }
ns.SwitchProfile("Default"); P("back to Default: xpSize=" .. CircletDB.xpSize .. " exalted.b=" .. CircletDB.repColors.custom.b)
ns.SwitchProfile("Hunter"); P("Hunter again: xpSize=" .. CircletDB.xpSize .. " exalted.b=" .. CircletDB.repColors.custom.b)
CircletDB.flightTimes = { a = 1 }
ns.CopyProfile("Default"); P("copied Default into Hunter: xpSize=" .. CircletDB.xpSize .. " flightTimes kept=" .. tostring(CircletDB.flightTimes.a))
CircletDB.xpSize = 175; ns.RenameProfile("Alt"); P("renamed: " .. ns.CurrentProfile() .. " chars=" .. CircletProfiles.chars["Jae - Forever"] .. " hunter gone=" .. tostring(CircletProfiles.profiles.Hunter == nil) .. " saved=" .. CircletProfiles.profiles.Alt.xpSize)
Fire("PLAYER_LOGOUT")
-- second character logs in (simulate reload with the saved tables)
CHAR = "Other"; ns.LoadProfile(); ns.FillDefaults(); P("Other logs in: " .. ns.CurrentProfile() .. " xpSize=" .. CircletDB.xpSize)
ns.ProfileStore().newChars = "Alt"; CHAR = "Third"; ns.LoadProfile(); ns.FillDefaults(); P("Third (new chars=Alt): " .. ns.CurrentProfile() .. " xpSize=" .. CircletDB.xpSize)
CHAR = "Jae"; ns.LoadProfile(); P("Jae again: " .. ns.CurrentProfile() .. " xpSize=" .. CircletDB.xpSize)
ns.SwitchProfile("Default"); ns.DeleteProfile("Alt"); P("deleted Alt: profiles=" .. table.concat(select(2, ns.ProfileList()), ",") .. " Jae=" .. tostring(CircletProfiles.chars["Jae - Forever"]) .. " Third=" .. tostring(CircletProfiles.chars["Third - Forever"]))
Slash("profile"); Slash("profile nope"); ns.NewProfile("PvP"); Slash("profile default"); P("slash switched: " .. ns.CurrentProfile())
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
