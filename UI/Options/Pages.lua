-- Circlet: The options window's pages: its folders, the General and Profiles pages, and the table of them all.
local ADDON_NAME, ns = ...

local db, Print = ns.db, ns.Print

-- Shared by the options window's files (UI/Options/*.lua), which load in this order: Pages,
-- Model, Cells, Sidebar, Window, Frame.
ns.OptionsUI = ns.OptionsUI or {}
local UI = ns.OptionsUI
local O = ns.O
local Toggle, Range, Execute, Box, Spacer, Intro = O.Toggle, O.Range, O.Execute, O.Box, O.Spacer, O.Intro

---------------------------------------------------------------------------
-- Options window  (/circ, or Esc > Options > AddOns > Circlet)
---------------------------------------------------------------------------
-- The pages are option tables in AceConfig's format: the General and Profiles pages are
-- here, and every ring's page comes from its own file (its registry entry's page.build).
-- The window that draws them is in the files after this one (Model.lua onwards).

local APP = "Circlet"

-- The folders in the list on the left, and what their pages say.
-- The same groups as the welcome setup's ring list (Features/Setup/Items.lua).
local FOLDERS = {
    progress = { order = 2, name = "Progress",
        text = "Rings that pop up and fill as you gain XP, advance quests, and raise skills and reputation." },
    vitals = { order = 3, name = "Health rings",
        text = "Health and power round a ring, with portraits, badges, buffs and effects: yours, your "
            .. "target's, its target's and your pet's." },
    combat = { order = 3.5, name = "Combat & casting",
        text = "Rings for your casts and your target's, your melee swings and shots, the five-second rule "
            .. "on mana, and your ammo." },
    class = { order = 4, name = "Classes",
        text = "Rings for one class's own tools, under a heading for each class: shaman totems and weapon "
            .. "imbues, the warlock's soulstone and the hunter's pet. Only your class's show." },
    group = { order = 5, name = "Group",
        text = "Rings for playing with others: loot rolls and ready checks." },
    travel = { order = 6, name = "Travel & survival",
        text = "Rings for getting around and staying alive: flights, your Hearthstone, timed quests, "
            .. "corpse runs and breath." },
    professions = { order = 7, name = "Professions",
        text = "Rings for crafting batches and gathering: mining, herbalism, skinning and fishing." },
    comfort = { order = 8, name = "Rest & utility",
        text = "Rings for downtime: eating and drinking, resting at a campfire, the clock and timers." },
}

local function Hidden(def)
    return function() return ns.HiddenForClass(def) end
end

-- Rings in the Classes folder show for every class, greyed out with a warning for the
-- classes that can't use them; rings elsewhere that only some classes use stay hidden.
local NOT_AVAILABLE = "|cffff5555Not available to this class|r"
local function ClassFolder(def) return def.page and def.page.folder == "class" end
local function Gate(option, def)
    if not def.class then return option end
    if ClassFolder(def) then option.disabled = Hidden(def) else option.hidden = Hidden(def) end
    return option
end

-- The General page's ring checkboxes: one box per folder, three to a row, in the same
-- order as the list on the left. "XP ring" shows as "XP", since the box title says rings.
-- A ring with no page of its own could name its box here (all of them have pages now).
local BOX_FOR = {}
-- Each ring's switch is labelled with its page's name (filled in as the pages are built), so a
-- ring is called the same thing everywhere.
local LABEL_FOR = {}
local function Label(def)
    return function() return LABEL_FOR[def.key] or (def.toggle[1]:gsub(" rings?$", "")) end
end

local function RingBoxes()
    local boxes = {}
    for _, def in ipairs(ns.RINGS) do
        if def.toggle then
            local folder = def.page and def.page.folder or BOX_FOR[def.key] or "other"
            if not boxes[folder] then
                local f = FOLDERS[folder]
                boxes[folder] = Box(2 + (f and f.order or 9) / 100, f and f.name or "Other rings", {})
            end
            local t = def.toggle
            local option = Toggle(def.page and def.page.order or def.order, def.key .. "Enabled",
                Label(def), t[1] .. ": " .. t[2], t[3])
            option.width = 1
            boxes[folder].args[def.key] = Gate(option, def)
        end
    end
    return boxes
end

-- General page: the ring checkboxes, then layout, effects, summary and reset.
local function GeneralPage()
    local page = {
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
            layout = Box(3, "Layout", {
                editAll = {
                    type = "execute", order = 0.3, width = 1.1,
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
    for folder, box in pairs(RingBoxes()) do page.args["rings_" .. folder] = box end
    return page
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

-- A folder's own page: a switch for each of its rings. The Classes folder gets a box per
-- class (named by the class's first ring classes, sorted), hidden when none of its rings show.
local function FolderRings(folder)
    local args = {}
    for _, def in ipairs(ns.RINGS) do
        if def.toggle and def.page and def.page.folder == folder then
            local t = def.toggle
            local option = Toggle(def.page.order, def.key .. "Enabled",
                Label(def), t[1] .. ": " .. t[2], t[3])
            args[def.key] = Gate(option, def)
        end
    end
    if folder ~= "class" then return { rings = Box(1, "Rings in this group", args) } end
    local boxes = {}
    for key, option in pairs(args) do
        local def = ns.FindRing(key)
        local classes = {}
        for class in pairs(def and def.class or { OTHER = true }) do classes[#classes + 1] = class end
        table.sort(classes)
        local class = classes[1]
        local box = boxes[class]
        if not box then
            local names = LOCALIZED_CLASS_NAMES_MALE
            local name = class == "OTHER" and "Other" or (names and names[class])
                or (class:sub(1, 1) .. class:sub(2):lower())
            box = Box(1, name, {})
            boxes[class] = box
        end
        box.args[key] = option
    end
    local out = {}
    for class, box in pairs(boxes) do out["rings_" .. class] = box end
    return out
end

---------------------------------------------------------------- the table
local function BuildOptionsTable()
    local args = { general = GeneralPage(), profiles = ProfilesPage() }
    for key, f in pairs(FOLDERS) do
        local folderArgs = { header = { type = "header", order = 0, name = f.name }, intro = Intro(0.5, f.text) }
        for k, box in pairs(FolderRings(key)) do folderArgs[k] = box end
        args[key] = { type = "group", order = f.order, name = f.name, childGroups = "tree", args = folderArgs }
    end
    for _, def in ipairs(ns.RINGS) do
        if def.page then
            local page = def.page.build(O)
            page.order = def.page.order
            if type(page.name) == "string" then LABEL_FOR[def.key] = page.name end
            Gate(page, def)
            local parent = def.page.folder and args[def.page.folder].args or args
            parent[def.key] = page
        end
    end
    return { type = "group", name = "Circlet", childGroups = "tree", args = args }
end

-- For the files loaded after this one.
UI.NOT_AVAILABLE = NOT_AVAILABLE
UI.FOLDERS = FOLDERS
UI.APP = APP
UI.BuildOptionsTable = BuildOptionsTable
