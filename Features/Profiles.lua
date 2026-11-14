-- Circlet: Profiles: named sets of settings, chosen per character.
local ADDON_NAME, ns = ...

local DEFAULTS, Print = ns.DEFAULTS, ns.Print

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
-- Settings live in CircletDB as before; a profile is a saved copy of them. Each
-- character uses one profile (CircletProfiles.chars), "Default" unless you pick another.
-- On login the character's profile is copied into CircletDB; on logout (and before
-- switching) CircletDB is copied back into it. Things the addon learns as you play
-- (flight times, reputation seen, sessions, ...) aren't settings: every profile shares them.

-- Saved data the addon learns as you play, not settings: not part of profiles, and
-- resets leave it alone.
local LEARNED = { repKnown = true, flightTimes = true, sessions = true, restBase = true, pinned = true,
                  lastSeen = true, totemSpells = true, castTimes = true, targetCastTimes = true,
                  setupDone = true, seenNew = true } -- the setup wizard and New in page (Features/Setup.lua)

local current -- this character's profile name

local Copy = ns.Copy

local function CharKey()
    local name = UnitName and UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or "?"
    return (name or "?") .. " - " .. (realm or "?")
end

local function Store()
    CircletProfiles = CircletProfiles or {}
    local P = CircletProfiles
    P.profiles, P.chars = P.profiles or {}, P.chars or {}
    return P
end

-- The settings in CircletDB right now, as a profile.
local function Snapshot()
    local t = {}
    for k in pairs(DEFAULTS) do
        if not LEARNED[k] and CircletDB[k] ~= nil then t[k] = Copy(CircletDB[k]) end
    end
    return t
end

-- Puts a profile's settings into CircletDB. Settings it lacks are cleared, for the
-- defaults to fill in (at login that happens right after; when switching, here).
local function Apply(profile, fill)
    for k in pairs(DEFAULTS) do
        if not LEARNED[k] then CircletDB[k] = Copy(profile[k]) end
    end
    if fill and ns.FillDefaults then ns.FillDefaults() end
end

-- After settings change under the rings: the bits that don't re-read them every frame.
local function Refresh()
    if ns.ApplyAllOpacity then ns.ApplyAllOpacity() end
    if ns.OnXPAlwaysChanged then ns.OnXPAlwaysChanged() end
    if ns.RefreshPinClicks then ns.RefreshPinClicks() end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Login: pick this character's profile and load it. The very first time, the settings
-- you already have become the "Default" profile.
local function LoadProfile()
    local P = Store()
    if not next(P.profiles) then P.profiles.Default = Snapshot() end
    local me = CharKey()
    local name = P.chars[me]
    if not (name and P.profiles[name]) then
        name = (P.newChars and P.profiles[P.newChars]) and P.newChars or "Default"
        P.profiles[name] = P.profiles[name] or Snapshot()
        P.chars[me] = name
    end
    current = name
    Apply(P.profiles[name])
end

-- Saves the live settings into the current profile.
local function SaveProfile()
    if not (current and CircletDB) then return end
    Store().profiles[current] = Snapshot()
end

local function SwitchProfile(name)
    local P = Store()
    if not P.profiles[name] or name == current then return end
    SaveProfile()
    current = name
    P.chars[CharKey()] = name
    Apply(P.profiles[name], true)
    Refresh()
    Print("Using profile |cffffd100" .. name .. "|r.")
end

local function CleanName(name)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    return name ~= "" and name or nil
end

-- A new profile starting from the current settings, switched to.
local function NewProfile(name)
    name = CleanName(name)
    if not name then return end
    local P = Store()
    if P.profiles[name] then Print("There's already a profile called " .. name .. ".") return end
    SaveProfile()
    P.profiles[name] = Snapshot()
    SwitchProfile(name)
end

-- Replaces the current profile's settings with another profile's.
local function CopyProfile(from)
    local P = Store()
    if not P.profiles[from] or from == current then return end
    Apply(P.profiles[from], true)
    SaveProfile()
    Refresh()
    Print("Copied the settings of |cffffd100" .. from .. "|r into |cffffd100" .. current .. "|r.")
end

local function DeleteProfile(name)
    local P = Store()
    if not P.profiles[name] or name == current then return end
    P.profiles[name] = nil
    -- Characters that used it go back to the profile for new characters (or Default).
    for char, used in pairs(P.chars) do
        if used == name then P.chars[char] = nil end
    end
    if P.newChars == name then P.newChars = nil end
    if not P.profiles.Default and current ~= "Default" and not next(P.profiles) then P.profiles.Default = Snapshot() end
    Print("Deleted profile " .. name .. ".")
    if ns.RefreshOptions then ns.RefreshOptions() end
end

local function RenameProfile(name)
    name = CleanName(name)
    local P = Store()
    if not name or name == current then return end
    if P.profiles[name] then Print("There's already a profile called " .. name .. ".") return end
    SaveProfile()
    P.profiles[name], P.profiles[current] = P.profiles[current], nil
    for char, used in pairs(P.chars) do
        if used == current then P.chars[char] = name end
    end
    if P.newChars == current then P.newChars = name end
    Print("Renamed profile " .. current .. " to |cffffd100" .. name .. "|r.")
    current = name
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Profile names, for the options' drop-downs.
local function ProfileList(except)
    local list, order = {}, {}
    for name in pairs(Store().profiles) do
        if name ~= except then list[name] = name; table.insert(order, name) end
    end
    table.sort(order)
    return list, order
end

-- Which characters use a profile.
local function CharsUsing(name)
    local t = {}
    for char, used in pairs(Store().chars) do
        if used == name then table.insert(t, char) end
    end
    table.sort(t)
    return t
end

ns.Listen({ "PLAYER_LOGOUT" }, SaveProfile)

-- /circ profile: list the profiles; /circ profile <name>: switch.
ns.RegisterCommand({ "profile", "profiles" }, function(arg)
    if arg ~= "" then
        local match
        for name in pairs((ProfileList())) do if name:lower() == arg:lower() then match = name end end
        if match then SwitchProfile(match) else Print("No profile called " .. arg .. ".") end
    else
        local _, order = ProfileList()
        Print("Profile: |cffffd100" .. tostring(current) .. "|r. All: " .. table.concat(order, ", ")
            .. ". Switch with /circ profile <name>.")
    end
end, "show or switch profiles", "profile [name]")

-- Shared with the files loaded after this one.
ns.LEARNED = LEARNED
ns.LoadProfile = LoadProfile
ns.SaveProfile = SaveProfile
ns.SwitchProfile = SwitchProfile
ns.NewProfile = NewProfile
ns.CopyProfile = CopyProfile
ns.DeleteProfile = DeleteProfile
ns.RenameProfile = RenameProfile
ns.ProfileList = ProfileList
ns.CharsUsing = CharsUsing
ns.CurrentProfile = function() return current end
ns.ProfileStore = Store
