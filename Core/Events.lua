-- Circlet: Startup: load the saved settings and build the options window.
local ADDON_NAME, ns = ...

local Print = ns.Print

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
-- Every ring listens for its own events (ns.Listen); this only gets the saved settings
-- ready once the game has loaded them: this character's profile, one-time migrations,
-- then defaults for anything missing.

ns.Listen({ "ADDON_LOADED" }, function(_, name)
    if name ~= ADDON_NAME or ns.loaded then return end
    ns.loaded = true
    ns.FinalizeDefaults()   -- every ring has registered by now
    CircletDB = CircletDB or {}
    ns.LoadProfile()        -- this character's profile into CircletDB
    ns.RunMigrations()
    ns.FillDefaults()
    for _, def in ipairs(ns.RINGS) do
        if def.onLoaded then def.onLoaded() end
    end
    for _, fn in ipairs(ns.LOADED) do fn() end

    -- If the options libraries misbehave on this client, don't take the whole addon down.
    local ok, err = ns.TrySetupOptions()
    if not ok then Print("Couldn't build the options window:", err) end
end)
