-- Circlet: The options window (AceConfig / AceGUI, like Questie's).
local ADDON_NAME, ns = ...

local db, Print = ns.db, ns.Print
local O = ns.O
local Toggle, Range, Execute, Box, Spacer, Intro = O.Toggle, O.Range, O.Execute, O.Box, O.Spacer, O.Intro

---------------------------------------------------------------------------
-- Options window  (/circ, or Esc > Options > AddOns > Circlet)
---------------------------------------------------------------------------
-- A standalone window built with AceConfig/AceGUI (embedded in Libs), the same toolkit
-- Questie's options use: a list of pages on the left. The General and Profiles pages
-- are here; every ring's page comes from its own file (its registry entry's page.build).

local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
local AceConfigRegistry = LibStub and LibStub("AceConfigRegistry-3.0", true)
local AceConfigDialog = LibStub and LibStub("AceConfigDialog-3.0", true)
local APP = "Circlet"
local configFrame

-- The folders in the list on the left, and what their pages say.
local FOLDERS = {
    progress = { order = 2, name = "Progress rings",
        text = "Rings that pop up and fill as you gain XP, advance quests, raise skills and reputation, "
            .. "and level your pet." },
    status = { order = 3, name = "Travel & status",
        text = "Rings that count down or keep watch: flights, timed quests, corpse runs, breath and ammo." },
    professions = { order = 4, name = "Professions & casting",
        text = "Rings for crafting batches, gathering (mining, herbalism, skinning, fishing) and casting." },
}

local function Hidden(def)
    return function() return ns.HiddenForClass(def) end
end

-- General page: a checkbox per ring, then layout, effects, summary and reset.
local function GeneralPage()
    local rings = {}
    for _, def in ipairs(ns.RINGS) do
        if def.toggle then
            local t = def.toggle
            local option = Toggle(def.order, def.key .. "Enabled", t[1], t[2], t[3])
            if def.class then option.hidden = Hidden(def) end
            rings[def.key] = option
        end
    end
    return {
        type = "group", order = 1, name = "General",
        args = {
            header = { type = "header", order = 0, name = "Circlet" },
            intro = Intro(0.5, "Progress rings for quests, XP, skills, reputation and more. Each ring has its own "
                .. "page in the list on the left, with its colors, look and position. While a ring's page is open "
                .. "the ring is in |cffffd100edit mode|r: it's on screen showing your changes, and you can drag it "
                .. "into place."),
            spacer = Spacer(1),
            setup = Box(1.5, "Setup", {
                wizard = {
                    type = "execute", order = 1, width = 1.1, name = "Setup wizard",
                    desc = "Pick your rings, hide the game bars they replace, and set their look and layout, in "
                        .. "four short steps. Also /circ setup.",
                    func = function() ns.OpenSetup() end,
                },
                whatsNew = {
                    type = "execute", order = 2, width = 1.1, name = "What's new",
                    desc = "The rings and features added in the latest version, to try them out. Also /circ new.",
                    func = function() ns.OpenWhatsNew() end,
                },
            }),
            rings = Box(2, "Rings", rings),
            layout = Box(3, "Layout", {
                editAll = {
                    type = "execute", order = 1, width = 1.1,
                    name = function()
                        for _, def in ipairs(ns.RINGS) do
                            if def.edit.get() then return "|cff33ff33Finish editing|r" end
                        end
                        return "Edit all rings"
                    end,
                    desc = "Put every ring on screen at once to arrange them. Also /circ edit.",
                    func = function() ns.ToggleAllEditing() end,
                },
                autoEdit = Toggle(0.4, "optionsAutoEdit", "Edit mode on ring pages",
                    "Opening a ring's page here puts that ring in edit mode, so it's on screen showing your "
                    .. "changes as you make them. It goes back to normal when you leave the page or close the window."),
                arrange = Toggle(0.5, "autoArrange", "Auto-arrange",
                    "When rings pop up at the same time and would overlap, the newer one slides sideways "
                    .. "to clear the other, then slides back home once it's gone."),
                snap = Toggle(1, "snapGrid", "Snap to grid",
                    "In edit mode, show a grid and snap rings to it while you drag them, so they line up. "
                    .. "Hold Shift while dragging to place a ring freely.",
                    function() ns.RefreshEditGrid() end),
                gridSize = Range(1.5, "gridSize", "Grid size", 4, 64, 2,
                    "Spacing of the snap grid. It's measured out from the centre of the screen.",
                    { disabled = function() return not db.snapGrid end }),
                resetAll = Execute(2, "Reset all positions", function() ns.ResetPositions() end,
                    "Move every ring back to its default spot across the top of the screen. Also /circ resetpos."),
            }),
            effects = Box(3.4, "Effects", {
                discover = Toggle(1, "discoverFx", "Discovered area animation",
                    "When you discover a new area, a gold compass ring sweeps closed under the zone text with "
                    .. "the area's name and the exploration XP."),
                preview = Execute(2, "Preview", function() ns.PreviewDiscovery() end,
                    "Play the discovered area animation. Also /circ discover."),
                login = Toggle(3, "loginFx", "Welcome animation",
                    "When you log in (not on /reload), rings in the addon's colors spin open, your name types "
                    .. "itself out, and your level, zone, rested XP and when you last played fade in."),
                loginPreview = Execute(4, "Preview welcome", function() ns.PreviewWelcome() end,
                    "Play the welcome animation. Also /circ hello."),
            }),
            summary = Box(3.5, "Session summary", {
                show = Execute(1, "Show summary", function() ns.ToggleSummary() end,
                    "Everything you've gained this session: XP, quests, money, skill-ups, reputation, flights. "
                    .. "Also /circ summary."),
                onLogout = Toggle(2, "summaryOnLogout", "Show when logging out",
                    "Pop up the summary when the logout countdown starts."),
            }),
            reset = Box(4, "Reset", {
                defaults = {
                    type = "execute", order = 1, width = 1.1, name = "Reset to defaults",
                    desc = "Restore every Circlet setting, color and position to its default.",
                    confirm = true, confirmText = "Reset every Circlet setting to its default?",
                    func = function() ns.ResetDefaults() end,
                },
            }),
        },
    }
end

-- Profiles: named sets of settings, chosen per character.
local function ProfilesPage()
    -- Profiles: named sets of settings, chosen per character.
    local function CurrentName() return ns.CurrentProfile() or "Default" end
    return {
        type = "group", order = 90, name = "Profiles",
        args = {
            header = { type = "header", order = 0, name = "Profiles" },
            intro = Intro(0.5, "A profile is a whole set of Circlet settings: which rings show, their colors, look "
                .. "and positions. Each character uses one profile, and switching is instant. Things Circlet "
                .. "learns as you play (flight times, reputations seen, session history) are shared by every "
                .. "profile."),
            current = Box(1, "This character", {
                info = { type = "description", order = 0, fontSize = "medium",
                    name = function()
                        local users = ns.CharsUsing(CurrentName())
                        return "Using |cffffd100" .. CurrentName() .. "|r"
                            .. (#users > 1 and (", shared with " .. (#users - 1) .. " other character"
                                .. (#users > 2 and "s" or "")) or "") .. "."
                    end },
                profile = {
                    type = "select", order = 1, name = "Profile", width = 1.4,
                    desc = "The profile this character uses.",
                    values = function() return (ns.ProfileList()) end,
                    sorting = function() return select(2, ns.ProfileList()) end,
                    get = CurrentName,
                    set = function(_, v) ns.SwitchProfile(v) end,
                },
                new = {
                    type = "input", order = 2, name = "New profile", width = 1.4,
                    desc = "Type a name and press Enter: a new profile starting from your current settings, "
                        .. "which this character then uses.",
                    get = function() return "" end,
                    set = function(_, v) ns.NewProfile(v) end,
                },
            }),
            manage = Box(2, "Manage", {
                copy = {
                    type = "select", order = 1, name = "Copy settings from", width = 1.4,
                    desc = "Replace this profile's settings with another profile's.",
                    values = function() return (ns.ProfileList(CurrentName())) end,
                    sorting = function() return select(2, ns.ProfileList(CurrentName())) end,
                    get = function() return nil end,
                    set = function(_, v) ns.CopyProfile(v) end,
                    confirm = function(_, v) return "Replace every setting in " .. CurrentName() .. " with " .. tostring(v) .. "'s?" end,
                    disabled = function() return next((ns.ProfileList(CurrentName()))) == nil end,
                },
                rename = {
                    type = "input", order = 2, name = "Rename this profile", width = 1.4,
                    desc = "Type a new name for the current profile and press Enter.",
                    get = function() return CurrentName() end,
                    set = function(_, v) ns.RenameProfile(v) end,
                },
                delete = {
                    type = "select", order = 3, name = "Delete a profile", width = 1.4,
                    desc = "Delete another profile. Characters that used it switch to the profile for new "
                        .. "characters the next time they log in.",
                    values = function() return (ns.ProfileList(CurrentName())) end,
                    sorting = function() return select(2, ns.ProfileList(CurrentName())) end,
                    get = function() return nil end,
                    set = function(_, v) ns.DeleteProfile(v) end,
                    confirm = function(_, v) return "Delete the profile " .. tostring(v) .. "?" end,
                    disabled = function() return next((ns.ProfileList(CurrentName()))) == nil end,
                },
                newChars = {
                    type = "select", order = 4, name = "New characters use", width = 1.4,
                    desc = "The profile a character starts with the first time it logs in with Circlet.",
                    values = function() return (ns.ProfileList()) end,
                    sorting = function() return select(2, ns.ProfileList()) end,
                    get = function()
                        local P = ns.ProfileStore()
                        return (P.newChars and P.profiles[P.newChars]) and P.newChars or "Default"
                    end,
                    set = function(_, v) ns.ProfileStore().newChars = v end,
                },
                resetNote = { type = "description", order = 5, name = "\nTo put this profile's settings back to "
                    .. "the defaults, use |cffffd100Reset to defaults|r on the General page." },
            }),
        },
    }
end

---------------------------------------------------------------- the table
local function BuildOptionsTable()
    local args = { general = GeneralPage(), profiles = ProfilesPage() }
    for key, f in pairs(FOLDERS) do
        args[key] = { type = "group", order = f.order, name = f.name, childGroups = "tree",
                      args = { header = { type = "header", order = 0, name = f.name }, intro = Intro(0.5, f.text) } }
    end
    for _, def in ipairs(ns.RINGS) do
        if def.page then
            local page = def.page.build(O)
            page.order = def.page.order
            if def.class then page.hidden = Hidden(def) end
            local parent = def.page.folder and args[def.page.folder].args or args
            parent[def.key] = page
        end
    end
    return { type = "group", name = "Circlet", childGroups = "tree", args = args }
end

---------------------------------------------------------------- the window
local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = get and get(ADDON_NAME, "Version") or nil
    -- A copy straight from the repository, not a packaged release.
    if version and version:find("@project%-version@") then version = "dev" end
    return version
end

local function SetupOptions()
    if not (AceGUI and AceConfigRegistry and AceConfigDialog) then
        error("the embedded AceConfig/AceGUI libraries didn't load")
    end
    AceConfigRegistry:RegisterOptionsTable(APP, BuildOptionsTable())

    -- The window, like Questie's: an AceGUI frame that AceConfigDialog fills with tabs.
    configFrame = AceGUI:Create("Frame")
    configFrame:Hide()
    configFrame:SetTitle("Circlet")
    local version = Version()
    configFrame:SetStatusText(version and ("Version " .. version .. "   ·   /circ help for commands") or "/circ help for commands")
    configFrame:SetLayout("Fill")
    configFrame:SetWidth(820)
    configFrame:SetHeight(660)
    AceConfigDialog:SetDefaultSize(APP, 820, 660)
    -- The list on the left: folders open, and wide enough for the page names.
    local status = AceConfigDialog:GetStatusTable(APP)
    status.groups = status.groups or {}
    status.groups.treewidth = status.groups.treewidth or 180
    status.groups.groups = status.groups.groups or { progress = true, status = true, professions = true }
    _G.CircletConfigFrame = configFrame
    table.insert(UISpecialFrames, "CircletConfigFrame") -- Esc closes it

    ns.RefreshOptions = function()
        if configFrame:IsShown() then AceConfigRegistry:NotifyChange(APP) end
    end

    -- Edit mode follows the page: opening a ring's page puts that ring in edit mode, and
    -- leaving the page (or closing the window) ends it. Only rings it started itself.
    local autoKey, lastPage = nil, nil
    local function StopAuto()
        if autoKey then ns.SetRingEditing(autoKey, false, true) end
        autoKey = nil
    end
    local watcher = CreateFrame("Frame")
    watcher.t = 0
    watcher:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        if self.t < 0.2 then return end
        self.t = 0
        local page = nil
        if configFrame:IsShown() then
            local selected = status.groups and status.groups.selected
            if type(selected) == "string" then page = selected:match("([^\001]+)$") end
            page = page or "general"
        end
        if page == lastPage then return end
        lastPage = page
        local def = page and ns.FindRing(page)
        local key = def and def.key == page and page or nil
        if autoKey and autoKey ~= key then StopAuto() end
        if key and db.optionsAutoEdit and not def.edit.get() then
            ns.SetRingEditing(key, true, true)
            autoKey = key
        end
    end)

    -- Esc > Options > AddOns > Circlet: a short page that opens the window.
    if Settings and Settings.RegisterVerticalLayoutCategory then
        local category, layout = Settings.RegisterVerticalLayoutCategory("Circlet")
        layout:AddInitializer(CreateSettingsButtonInitializer("Circlet options", "Open options", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            if not configFrame:IsShown() then
                configFrame:Show()
                AceConfigDialog:Open(APP, configFrame)
            end
        end, "Open the Circlet options window. Also /circ.", true))
        Settings.RegisterAddOnCategory(category)
    end
end

-- Builds the window; if the options libraries misbehave on this client, the rest of
-- the addon still works.
local function TrySetupOptions()
    local ok, err = pcall(SetupOptions)
    if not ok then configFrame = nil end
    return ok, err
end

local function OpenOptions()
    if not configFrame then
        Print("The options window failed to load; slash commands still work (/circ help).")
    elseif configFrame:IsShown() then
        configFrame:Hide()
    else
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 852)
        configFrame:Show()
        AceConfigDialog:Open(APP, configFrame)
    end
end

-- The game's addon button by the minimap (set up in Circlet.toc).
function Circlet_OnAddonCompartmentClick()
    OpenOptions()
end

function Circlet_OnAddonCompartmentEnter(_, button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("Circlet")
    GameTooltip:AddLine("Click to open the options.", 1, 1, 1)
    GameTooltip:AddLine("/circ help for commands", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function Circlet_OnAddonCompartmentLeave()
    if GameTooltip then GameTooltip:Hide() end
end

-- Shared with the files loaded after this one.
ns.OpenOptions = OpenOptions
ns.TrySetupOptions = TrySetupOptions
