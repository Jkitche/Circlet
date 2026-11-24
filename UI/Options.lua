-- Circlet: The options window: a sidebar of pages, and each page's settings in two columns.
local ADDON_NAME, ns = ...

local db, Print = ns.db, ns.Print
local O = ns.O
local Toggle, Range, Execute, Box, Spacer, Intro = O.Toggle, O.Range, O.Execute, O.Box, O.Spacer, O.Intro

---------------------------------------------------------------------------
-- Options window  (/circ, or Esc > Options > AddOns > Circlet)
---------------------------------------------------------------------------
-- The pages are option tables in AceConfig's format: the General and Profiles pages are
-- here, and every ring's page comes from its own file (its registry entry's page.build).
-- The window that draws them is further down.

local APP = "Circlet"

-- The folders in the list on the left, and what their pages say.
-- The same groups as the welcome setup's ring list (Features/Setup.lua).
local FOLDERS = {
    progress = { order = 2, name = "Progress",
        text = "Rings that pop up and fill as you gain XP, advance quests, raise skills and reputation, "
            .. "and level your pet." },
    combat = { order = 3, name = "Combat & casting",
        text = "Rings for your casts and your target's, your melee swings and shots, the five-second rule "
            .. "on mana, your ammo, and (for shamans) totems and weapon imbues." },
    group = { order = 4, name = "Group",
        text = "Rings for playing with others: loot rolls, ready checks and (for warlocks) your soulstone." },
    travel = { order = 5, name = "Travel & survival",
        text = "Rings for getting around and staying alive: flights, your Hearthstone, timed quests, "
            .. "corpse runs and breath." },
    professions = { order = 6, name = "Professions",
        text = "Rings for crafting batches and gathering: mining, herbalism, skinning and fishing." },
    comfort = { order = 7, name = "Rest & utility",
        text = "Rings for downtime: eating and drinking, resting at a campfire, the clock and timers." },
}

local function Hidden(def)
    return function() return ns.HiddenForClass(def) end
end

-- The General page's ring checkboxes: one box per folder, three to a row, in the same
-- order as the list on the left. "XP ring" shows as "XP", since the box title says rings.
-- A ring with no page of its own could name its box here (all of them have pages now).
local BOX_FOR = {}
local LABEL_FOR = { pin = "Pinned quests", totem = "Totems" }

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
                LABEL_FOR[def.key] or (t[1]:gsub(" rings?$", "")), t[1] .. ": " .. t[2], t[3])
            option.width = 1
            if def.class then option.hidden = Hidden(def) end
            boxes[folder].args[def.key] = option
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

-- A folder's own page: a switch for each of its rings.
local function FolderRings(folder)
    local args = {}
    for _, def in ipairs(ns.RINGS) do
        if def.toggle and def.page and def.page.folder == folder then
            local t = def.toggle
            local option = Toggle(def.page.order, def.key .. "Enabled",
                LABEL_FOR[def.key] or (t[1]:gsub(" rings?$", "")), t[1] .. ": " .. t[2], t[3])
            if def.class then option.hidden = Hidden(def) end
            args[def.key] = option
        end
    end
    return Box(1, "Rings in this group", args)
end

---------------------------------------------------------------- the table
local function BuildOptionsTable()
    local args = { general = GeneralPage(), profiles = ProfilesPage() }
    for key, f in pairs(FOLDERS) do
        args[key] = { type = "group", order = f.order, name = f.name, childGroups = "tree",
                      args = { header = { type = "header", order = 0, name = f.name }, intro = Intro(0.5, f.text),
                               rings = FolderRings(key) } }
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

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
-- Laid out like EllesmereUI's options: a sidebar on the left (logo, General / Profiles and
-- a few actions, a search box, then every ring under its folder with an on/off dot), and
-- on the right the page's title and description, tabs, its settings in titled sections of
-- two columns (label on the left of each cell, control on the right), and a footer with
-- the page's buttons (Edit mode, Preview, Reset) and Close.
-- The pages are the same option tables as before (AceConfig format, built by each ring's
-- page.build with UI/OptionsKit.lua), drawn with UI/Widgets.lua.

local W = ns.W
local A = W.ACCENT
local GOLD = ns.SKIN_GOLD

local WIN_W, WIN_H = 1060, 700
local SIDE_W, FOOT_H, PAD = 240, 58, 28
local CONTENT_W = WIN_W - SIDE_W
local BODY_W = CONTENT_W - PAD * 2 - 12 -- the scrollbar sits in the last 12
local COL_W = BODY_W / 2
local ROW_H = 46

local root, win
local current = "general" -- the page shown: "general", "profiles", "<folder>" or "<folder>.<ring>"
local tabOf = {}          -- page -> the tab picked on it
local lastSig
local Refresh, SelectPage

local function Eval(v, info, ...)
    if type(v) == "function" then return v(info, ...) end
    return v
end

local function Num(v, default) return tonumber(v) or default end

local function Sorted(args)
    local list = {}
    for key, opt in pairs(args or {}) do
        if type(opt) == "table" then list[#list + 1] = { key = key, opt = opt } end
    end
    table.sort(list, function(a, b)
        local oa, ob = tonumber(a.opt.order) or 100, tonumber(b.opt.order) or 100
        if oa ~= ob then return oa < ob end
        return tostring(a.key) < tostring(b.key)
    end)
    return list
end

local function PageAt(path)
    local node = root
    for part in path:gmatch("[^.]+") do node = node and node.args and node.args[part] end
    return node
end

-- The info table AceConfig passes to get/set/name/...: the path to the option, and the option.
local function Info(opt, ...)
    local info = { ... }
    info.option, info.type, info.arg, info.options = opt, opt.type, opt.arg, root
    return info
end

---------------------------------------------------------------- a page, taken apart
-- { title, intro, name, buttons = { entries }, sections = { { key, title, group, items } } }
local function PageModel(path)
    local page = PageAt(path)
    local m = { buttons = {}, sections = {} }
    if not page then return m end
    local parts = {}
    for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
    local pinfo = Info(page, unpack(parts))
    m.name = Eval(page.name, pinfo)
    m.title = m.name
    local loose
    local function Add(list, e, ...)
        e.info = Info(e.opt, ...)
        if not Eval(e.opt.hidden, e.info) then list[#list + 1] = e end
    end
    for _, e in ipairs(Sorted(page.args)) do
        local key, opt = e.key, e.opt
        local info = Info(opt, path, key)
        if Eval(opt.hidden, info) then
            -- hidden
        elseif opt.type == "header" and key == "header" then
            m.title = Eval(opt.name, info)
        elseif opt.type == "description" and key == "intro" then
            m.intro = Eval(opt.name, info)
        elseif opt.type == "execute" then
            e.info = info
            m.buttons[#m.buttons + 1] = e
        elseif opt.type == "group" then
            loose = nil
            if opt.inline then -- other groups are pages of their own, in the sidebar
                local section = { key = key, title = Eval(opt.name, info), group = opt, items = {} }
                for _, c in ipairs(Sorted(opt.args)) do Add(section.items, c, path, key, c.key) end
                if #section.items > 0 then m.sections[#m.sections + 1] = section end
            end
        elseif opt.type == "description" and not tostring(Eval(opt.name, info) or ""):find("%S") then
            -- a spacer
        else
            if not loose then
                loose = { key = "_" .. key, items = {} }
                m.sections[#m.sections + 1] = loose
            end
            e.info = info
            loose.items[#loose.items + 1] = e
        end
    end
    return m
end

-- Long pages split into tabs: a ring's look and position, and the General page's ring list.
local TAB_ORDER = { Settings = 1, Rings = 2, ["Look & position"] = 3 }
local function TabOf(path, section)
    if section.key == "size" or section.key == "text" or section.key == "position" then return "Look & position" end
    if path == "general" and section.key:find("^rings_") then return "Rings" end
    return "Settings"
end

local function Tabs(m)
    local seen, tabs = {}, {}
    for _, s in ipairs(m.sections) do
        local t = TabOf(current, s)
        s.tab = t
        if not seen[t] then seen[t] = true; tabs[#tabs + 1] = t end
    end
    table.sort(tabs, function(a, b) return (TAB_ORDER[a] or 9) < (TAB_ORDER[b] or 9) end)
    local pick = tabOf[current]
    if not seen[pick] then pick = tabs[1] end
    return tabs, pick
end

local function Signature(m, tab)
    local parts = { current, tostring(tab) }
    for _, s in ipairs(m.sections) do
        if s.tab == tab then
            parts[#parts + 1] = s.key
            for _, e in ipairs(s.items) do parts[#parts + 1] = e.key end
        end
    end
    parts[#parts + 1] = "|"
    for _, e in ipairs(m.buttons) do parts[#parts + 1] = e.key end
    return table.concat(parts, ",")
end

---------------------------------------------------------------- changing a setting
-- (Only our own key: assigning the StaticPopupDialogs global itself, even to the same table,
-- would taint it for every Blizzard popup.)
StaticPopupDialogs.CIRCLET_OPTIONS_CONFIRM = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, data) if data then data() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Sets an option (or runs a button), asking first if it has a confirm.
local function Commit(opt, info, ...)
    local n, args = select("#", ...), { ... }
    local function Go()
        if opt.type == "execute" then
            opt.func(info)
        else
            opt.set(info, unpack(args, 1, n))
        end
        Refresh()
    end
    local confirm = opt.confirm
    if type(confirm) == "function" then confirm = confirm(info, ...) end
    if confirm then
        local text = type(confirm) == "string" and confirm or opt.confirmText or (tostring(Eval(opt.name, info)) .. "?")
        StaticPopup_Show("CIRCLET_OPTIONS_CONFIRM", text, nil, Go)
    else
        Go()
    end
end

local function Fmt(v, opt)
    v = tonumber(v) or 0
    if opt.isPercent then return string.format("%d%%", math.floor(v * 100 + 0.5)) end
    if math.abs(v - math.floor(v + 0.5)) < 0.0001 then return tostring(math.floor(v + 0.5)) end
    return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
end

---------------------------------------------------------------- cells
-- One setting: a label on the left and its control on the right, half the width of the
-- page (or all of it, for text). Pooled by kind and reused as pages change.
local pools, used = {}, {}
local BUILD = {}

local function CellUpdateCommon(c)
    local opt, info = c.opt, c.info
    c.isDisabled = (Eval(opt.disabled, info) or (c.group and Eval(c.group.disabled, info))) and true or false
    c:SetAlpha(c.isDisabled and 0.38 or 1)
    if c.label then c.label:SetText(tostring(Eval(opt.name, info) or "")) end
end

local function NewCell(kind, parent)
    local c = CreateFrame("Button", nil, parent)
    c.kind = kind
    c.bg = W.Solid(c, "BACKGROUND", 1, 1, 1, 0.03)
    c.bg:SetAllPoints()
    c.hover = W.Solid(c, "BACKGROUND", 1, 1, 1, 0.035, 1)
    c.hover:SetAllPoints()
    c.hover:Hide()
    c.divider = W.Solid(c, "BORDER", 1, 1, 1, 0.07)
    c.divider:SetWidth(1)
    c.divider:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, -8)
    c.divider:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 8)
    c.label = W.Text(c, 13, 0.93, 0.93, 0.93)
    c.label:SetPoint("LEFT", c, "LEFT", 18, 0)
    c.label:SetWordWrap(true)
    c.tipTitle = function() return c.opt and tostring(Eval(c.opt.name, c.info) or "") end
    c.tipText = function() return c.opt and Eval(c.opt.desc, c.info) end
    function c:OnHover(on)
        self.hover:SetShown(on and not self.isText and not self.isDisabled)
        if on and not self.isText then W.ShowTip(self, self.tipTitle, self.tipText) else W.HideTip() end
    end
    c:SetScript("OnEnter", function(self) self:OnHover(true) end)
    c:SetScript("OnLeave", function(self) self:OnHover(false) end)
    BUILD[kind](c)
    return c
end

local function Acquire(kind, parent)
    pools[kind] = pools[kind] or {}
    used[kind] = (used[kind] or 0) + 1
    local c = pools[kind][used[kind]]
    if not c then
        c = NewCell(kind, parent)
        pools[kind][used[kind]] = c
    end
    c:ClearAllPoints()
    c:Show()
    return c
end

local function ReleaseAll()
    for kind, list in pairs(pools) do
        for _, c in ipairs(list) do c:Hide(); c.opt = nil end
        used[kind] = 0
    end
end

local function EachCell(fn)
    for kind, list in pairs(pools) do
        for i = 1, used[kind] or 0 do fn(list[i]) end
    end
end

BUILD.toggle = function(c)
    c.switch = W.Switch(c, function(_, v) if not c.isDisabled then Commit(c.opt, c.info, v) end end)
    c.switch:SetPoint("RIGHT", c, "RIGHT", -18, 0)
    W.PassHover(c.switch, c)
    c.label:SetPoint("RIGHT", c.switch, "LEFT", -14, 0)
    c:SetScript("OnClick", function(self) if not self.isDisabled then self.switch:Click() end end)
    c.Update = function(self)
        CellUpdateCommon(self)
        self.switch:SetOn(self.opt.get(self.info))
        self.switch:EnableMouse(not self.isDisabled)
    end
end

-- A number typed in the box: clamped to the option's range and rounded to its step.
local function ParseNumber(opt, text)
    local v = tonumber((tostring(text or ""):gsub("%%", "")))
    if not v then return nil end
    if opt.isPercent then v = v / 100 end
    local min, max = opt.min or -math.huge, opt.max or math.huge
    if opt.step and opt.step > 0 and opt.min then v = opt.min + math.floor((v - opt.min) / opt.step + 0.5) * opt.step end
    return math.max(min, math.min(max, v))
end

BUILD.range = function(c)
    c.box = W.EditBox(c, 54, "CENTER", function(text)
        local v = ParseNumber(c.opt, text)
        if v and not c.isDisabled then Commit(c.opt, c.info, v) end
    end)
    c.box:SetPoint("RIGHT", c, "RIGHT", -18, 0)
    c.box.revert = function() return c.opt and Fmt(c.opt.get(c.info), c.opt) or "" end
    W.PassHover(c.box, c)
    c.slider = W.Slider(c, 120, function(v)
        c.box:SetText(Fmt(v, c.opt))
        c.opt.set(c.info, v)
    end, function() Refresh() end)
    c.slider:SetPoint("RIGHT", c.box, "LEFT", -16, 0)
    W.PassHover(c.slider, c)
    c.label:SetPoint("RIGHT", c.slider, "LEFT", -14, 0)
    c.Update = function(self)
        CellUpdateCommon(self)
        local opt = self.opt
        local min, max = opt.softMin or opt.min or 0, opt.softMax or opt.max or 100
        self.slider:SetRange(min, max, opt.step, opt.bigStep)
        local v = Num(opt.get(self.info), min)
        if not self.slider.dragging then self.slider:SetValue(v) end
        if not self.box:HasFocus() then self.box:SetText(Fmt(v, opt)) end
        self.slider.disabled = self.isDisabled
        self.box:EnableMouse(not self.isDisabled)
    end
end

BUILD.select = function(c)
    c.drop = W.Dropdown(c, 184, function(v) if not c.isDisabled then Commit(c.opt, c.info, v) end end)
    c.drop:SetPoint("RIGHT", c, "RIGHT", -18, 0)
    W.PassHover(c.drop, c)
    c.label:SetPoint("RIGHT", c.drop, "LEFT", -14, 0)
    c.Update = function(self)
        CellUpdateCommon(self)
        local opt, info = self.opt, self.info
        local values = Eval(opt.values, info) or {}
        local sorting = Eval(opt.sorting, info)
        local items = {}
        if type(sorting) == "table" then
            for _, k in ipairs(sorting) do
                if values[k] ~= nil then items[#items + 1] = { k, tostring(values[k]) } end
            end
        else
            for k, text in pairs(values) do items[#items + 1] = { k, tostring(text) } end
            table.sort(items, function(a, b) return a[2] < b[2] end)
        end
        local value = opt.get(info)
        self.drop:SetItems(items, value)
        if value == nil or values[value] == nil then
            self.drop.label:SetText("|cff777a80Choose...|r")
        end
        self.drop.disabled = self.isDisabled
    end
end

BUILD.color = function(c)
    c.swatch = W.Swatch(c, function()
        if c.isDisabled then return end
        local opt, info = c.opt, c.info
        local r, g, b = opt.get(info)
        W.PickColor(r or 1, g or 1, b or 1, function(nr, ng, nb)
            opt.set(info, nr, ng, nb, 1)
            c.swatch:SetColor(nr, ng, nb)
        end)
    end)
    c.swatch:SetPoint("RIGHT", c, "RIGHT", -18, 0)
    W.PassHover(c.swatch, c)
    c.label:SetPoint("RIGHT", c.swatch, "LEFT", -14, 0)
    c:SetScript("OnClick", function(self) self.swatch:Click() end)
    c.Update = function(self)
        CellUpdateCommon(self)
        self.swatch:SetColor(self.opt.get(self.info))
    end
end

BUILD.input = function(c)
    c.edit = W.EditBox(c, 184, "LEFT", function(text)
        if not c.isDisabled then Commit(c.opt, c.info, text) end
    end)
    c.edit:SetPoint("RIGHT", c, "RIGHT", -18, 0)
    c.edit.revert = function() return c.opt and tostring(c.opt.get(c.info) or "") or "" end
    W.PassHover(c.edit, c)
    c.label:SetPoint("RIGHT", c.edit, "LEFT", -14, 0)
    c.Update = function(self)
        CellUpdateCommon(self)
        if not self.edit:HasFocus() then self.edit:SetText(tostring(self.opt.get(self.info) or "")) end
        self.edit:EnableMouse(not self.isDisabled)
    end
end

BUILD.execute = function(c)
    c.label:Hide()
    c.button = W.Button(c, COL_W - 36, 28, "", function() Commit(c.opt, c.info) end)
    c.button:SetPoint("CENTER")
    c.button.tipTitle, c.button.tipText = c.tipTitle, c.tipText
    c:SetScript("OnClick", function(self) if not self.isDisabled then self.button:Click() end end)
    c.Update = function(self)
        CellUpdateCommon(self)
        self:SetAlpha(1)
        self.button:SetText(tostring(Eval(self.opt.name, self.info) or ""))
        self.button:SetEnabled(not self.isDisabled)
    end
end

-- Text across the whole page (descriptions), and small headings inside a section.
BUILD.text = function(c)
    c.isText = true
    c.divider:Hide()
    c.label:ClearAllPoints()
    c.label:SetPoint("TOPLEFT", c, "TOPLEFT", 18, -12)
    c.label:SetWidth(BODY_W - 36)
    c.label:SetTextColor(0.74, 0.76, 0.8)
    c.Update = function(self)
        CellUpdateCommon(self)
        self:SetAlpha(1)
        local h = Num(self.label:GetStringHeight(), 14)
        self:SetHeight(math.max(ROW_H - 8, h + 24))
    end
end

BUILD.subhead = function(c)
    c.isText = true
    c.divider:Hide()
    c.bg:Hide()
    c.label:ClearAllPoints()
    c.label:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 4, 6)
    c.label:SetTextColor(0.68, 0.58, 0.48)
    c.Update = function(self)
        CellUpdateCommon(self)
        self:SetAlpha(1)
        self.label:SetText(tostring(Eval(self.opt.name, self.info) or ""):upper())
    end
end

local CELL_KIND = { toggle = "toggle", range = "range", select = "select", color = "color", input = "input",
                    execute = "execute", description = "text", header = "subhead" }

---------------------------------------------------------------- section titles
local heads, headsUsed = {}, 0
local function Head(parent)
    headsUsed = headsUsed + 1
    local h = heads[headsUsed]
    if not h then
        h = W.Text(parent, 11, 0.68, 0.58, 0.48)
        heads[headsUsed] = h
    end
    h:ClearAllPoints()
    h:Show()
    return h
end

---------------------------------------------------------------- the sidebar
local NAV = {
    { path = "general", text = "General", icon = "Interface\\Icons\\INV_Misc_Gear_01" },
    { path = "profiles", text = "Profiles", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { text = "Edit all rings", icon = "Interface\\Icons\\INV_Jewelry_Ring_03",
      tip = "Put every ring on screen at once to arrange them. Also /circ edit.",
      func = function() ns.ToggleAllEditing() end,
      active = function()
          for _, def in ipairs(ns.RINGS) do if def.edit.get() then return true end end
      end },
    { text = "What's new", icon = "Interface\\Icons\\INV_Scroll_03",
      tip = "The rings and features added in the latest version. Also /circ new.",
      func = function() win:Hide(); ns.OpenWhatsNew() end },
    { text = "Setup wizard", icon = "Interface\\Icons\\Trade_Engineering",
      tip = "Pick your rings, hide the game bars they replace, and set their look, in four short steps. Also /circ setup.",
      func = function() win:Hide(); ns.OpenSetup() end },
}

local function SideRow(parent, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(h)
    b.hi = W.Solid(b, "BACKGROUND", 1, 1, 1, 0.045)
    b.hi:SetAllPoints()
    b.hi:Hide()
    b.sel = W.Solid(b, "BACKGROUND", A.r, A.g, A.b, 0.16, 1)
    b.sel:SetAllPoints()
    b.bar = W.Solid(b, "ARTWORK", A.r, A.g, A.b, 1)
    b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(3)
    b.text = W.Text(b, 13, 0.85, 0.86, 0.88)
    b.text:SetWordWrap(false)
    function b:SetSelected(on)
        self.selected = on
        self.sel:SetShown(on)
        self.bar:SetShown(on)
    end
    b:SetScript("OnEnter", function(self)
        if not self.selected then self.hi:Show() end
        if self.tip then W.ShowTip(self, self.text:GetText(), self.tip) end
    end)
    b:SetScript("OnLeave", function(self) self.hi:Hide(); W.HideTip() end)
    b:SetSelected(false)
    return b
end

local sideRows, sideUsed = {}, 0
local search = ""

local function RingRow(parent)
    sideUsed = sideUsed + 1
    local b = sideRows[sideUsed]
    if not b then
        b = SideRow(parent, 26)
        b.dot = CreateFrame("Button", nil, b)
        b.dot:SetSize(22, 22)
        b.dot:SetPoint("RIGHT", b, "RIGHT", -10, 0)
        b.dot.ring = W.Solid(b.dot, "ARTWORK", 1, 1, 1, 1)
        b.dot.ring:SetTexture(W.DOT)
        b.dot.ring:SetSize(10, 10)
        b.dot.ring:SetPoint("CENTER")
        b.dot:SetScript("OnClick", function(self)
            local def = self.def
            local key = def.key .. "Enabled"
            db[key] = not db[key]
            if def.toggle[3] then def.toggle[3](db[key]) end
            Refresh()
        end)
        b.dot:SetScript("OnEnter", function(self)
            local on = db[self.def.key .. "Enabled"]
            W.ShowTip(self, self.def.toggle[1], (on and "|cff33ff33On|r" or "|cff999999Off|r") .. ": click to turn "
                .. (on and "off." or "on.") .. "\n" .. self.def.toggle[2])
        end)
        b.dot:SetScript("OnLeave", W.HideTip)
        b.chev = W.Chevron(b, 7, 0.78, 0.62, 1, true)
        sideRows[sideUsed] = b
    end
    b:ClearAllPoints()
    b:Show()
    b.tip = nil
    return b
end

local function RefreshSidebar()
    local list = win.ringList
    for i = 1, #sideRows do sideRows[i]:Hide() end
    sideUsed = 0
    local child = list.child
    local y = -4
    local needle = search:lower()
    local folders = {}
    for key, f in pairs(FOLDERS) do folders[#folders + 1] = { key = key, f = f } end
    table.sort(folders, function(a, b) return a.f.order < b.f.order end)
    for _, entry in ipairs(folders) do
        local folderPage = root.args[entry.key]
        local rings = {}
        for _, e in ipairs(Sorted(folderPage.args)) do
            if e.opt.type == "group" and not e.opt.inline and not Eval(e.opt.hidden, Info(e.opt, entry.key, e.key)) then
                local name = tostring(Eval(e.opt.name, Info(e.opt, entry.key, e.key)) or e.key)
                if needle == "" or name:lower():find(needle, 1, true) or entry.f.name:lower():find(needle, 1, true) then
                    rings[#rings + 1] = { key = e.key, name = name }
                end
            end
        end
        if #rings > 0 then
            local head = RingRow(child)
            head:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y - 6)
            head:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            head:SetHeight(30)
            head.text:ClearAllPoints()
            head.text:SetPoint("LEFT", head, "LEFT", 18, 0)
            head.text:SetText(entry.f.name)
            head.text:SetTextColor(0.80, 0.66, 1) -- the logo's violet
            head.dot:Hide()
            head.chev:Hide()
            head.tip = entry.f.text
            head:SetSelected(current == entry.key)
            head:SetScript("OnClick", function() SelectPage(entry.key) end)
            y = y - 36
            for _, r in ipairs(rings) do
                local path = entry.key .. "." .. r.key
                local row = RingRow(child)
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
                row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
                row:SetHeight(26)
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row, "LEFT", 30, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -34, 0)
                row.text:SetText(r.name)
                local def = ns.FindRing(r.key)
                local selected = current == path
                row:SetSelected(selected)
                row.chev:Hide()
                if def and def.key == r.key and def.toggle then
                    local on = db[def.key .. "Enabled"]
                    row.dot.def = def
                    row.dot.ring:SetVertexColor(on and 0.35 or 0.32, on and 0.85 or 0.33, on and 0.45 or 0.36, 1)
                    row.dot:Show()
                    row.text:SetTextColor(selected and 1 or (on and 0.86 or 0.55), selected and 1 or (on and 0.87 or 0.56),
                        selected and 1 or (on and 0.89 or 0.6))
                else
                    row.dot:Hide()
                    row.text:SetTextColor(selected and 1 or 0.86, selected and 1 or 0.87, selected and 1 or 0.89)
                end
                row:SetScript("OnClick", function() SelectPage(path) end)
                y = y - 26
            end
        end
    end
    if sideUsed == 0 then
        local row = RingRow(child)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y - 6)
        row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", 18, 0)
        row.text:SetText("No rings match.")
        row.text:SetTextColor(0.5, 0.5, 0.55)
        row.dot:Hide(); row.chev:Hide()
        row:SetSelected(false)
        row:SetScript("OnClick", nil)
        y = y - 30
    end
    child:SetWidth(SIDE_W - 14)
    child:SetHeight(-y + 8)
    list:Update()

    for _, b in ipairs(win.nav) do
        local item = b.item
        b:SetSelected(item.path ~= nil and current == item.path)
        local active = item.active and item.active()
        b.text:SetText(active and "|cff33ff33Finish editing|r" or item.text)
    end
end

---------------------------------------------------------------- the page
local tabButtons, footButtons = {}, {}

local function TabButton(i)
    local b = tabButtons[i]
    if not b then
        b = CreateFrame("Button", nil, win)
        b:SetHeight(34)
        b.text = W.Text(b, 14, 1, 1, 1, "OVERLAY", W.TITLE_FONT)
        b.text:SetPoint("CENTER", b, "CENTER", 0, 2)
        b.line = W.Solid(b, "ARTWORK", A.r, A.g, A.b, 1)
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT"); b.line:SetPoint("BOTTOMRIGHT")
        b:SetScript("OnClick", function(self)
            tabOf[current] = self.tab
            lastSig = nil
            win.body:ScrollTo(0)
            Refresh()
        end)
        b:SetScript("OnEnter", function(self) if not self.selected then self.text:SetTextColor(0.9, 0.9, 0.92) end end)
        b:SetScript("OnLeave", function(self) if not self.selected then self.text:SetTextColor(0.6, 0.62, 0.66) end end)
        tabButtons[i] = b
    end
    b:Show()
    return b
end

local function FootButton(i)
    local b = footButtons[i]
    if not b then
        b = W.Button(win, 140, 32, "", function(self) Commit(self.opt, self.info) end)
        b.tipTitle = function() return b.opt and tostring(Eval(b.opt.name, b.info) or "") end
        b.tipText = function() return b.opt and Eval(b.opt.desc, b.info) end
        footButtons[i] = b
    end
    b:Show()
    return b
end

local function UpdateHeader(m)
    win.title:SetText(m.title or "")
    win.intro:SetText(m.intro or "")
end

local function UpdateFooter(m)
    local x = SIDE_W + PAD
    for i, e in ipairs(m.buttons) do
        local b = FootButton(i)
        b.opt, b.info = e.opt, e.info
        b:SetText(tostring(Eval(e.opt.name, e.info) or ""))
        b:SetWidth(math.max(120, Num(b.label:GetStringWidth(), 80) + 40))
        b:SetEnabled(not Eval(e.opt.disabled, e.info))
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", x, 13)
        x = x + Num(b:GetWidth(), 120) + 12
    end
    for i = #m.buttons + 1, #footButtons do footButtons[i]:Hide() end
end

local function Render(m, tabs, tab)
    UpdateHeader(m)
    -- Where the tabs go depends on how long the description is.
    local titleH = Num(win.title:GetStringHeight(), 30)
    local introH = (m.intro and m.intro ~= "") and Num(win.intro:GetStringHeight(), 16) or 0
    local tabsTop = 24 + titleH + 10 + introH + 16
    local x = SIDE_W + PAD
    for i, name in ipairs(tabs) do
        local b = TabButton(i)
        b.tab = name
        b.selected = name == tab
        b.text:SetText(#tabs == 1 and (m.name or name) or name)
        b.text:SetTextColor(b.selected and 1 or 0.6, b.selected and 1 or 0.62, b.selected and 1 or 0.66)
        b.line:SetShown(b.selected)
        b:SetWidth(Num(b.text:GetStringWidth(), 80) + 28)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -tabsTop)
        x = x + Num(b:GetWidth(), 100) + 6
    end
    for i = #tabs + 1, #tabButtons do tabButtons[i]:Hide() end
    win.tabRule:ClearAllPoints()
    win.tabRule:SetPoint("TOPLEFT", win, "TOPLEFT", SIDE_W + PAD, -(tabsTop + 34))
    win.tabRule:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -(tabsTop + 34))
    local body = win.body
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", win, "TOPLEFT", SIDE_W + PAD, -(tabsTop + 35))
    body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD + 12, FOOT_H + 1)

    -- The sections, each a title over its cells in two columns.
    ReleaseAll()
    for i = 1, headsUsed do heads[i]:Hide() end
    headsUsed = 0
    local child = body.child
    child:SetWidth(BODY_W)
    local y = -18
    for _, s in ipairs(m.sections) do
        if s.tab == tab then
            if s.title and s.title ~= "" then
                local h = Head(child)
                h:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
                h:SetText(tostring(s.title):upper())
                y = y - 22
            end
            local col, row = 0, 0
            local function NextRow()
                if col > 0 then y = y - ROW_H; row = row + 1; col = 0 end
            end
            for _, e in ipairs(s.items) do
                local kind = CELL_KIND[e.opt.type]
                if not kind then
                    -- an option type the window doesn't draw
                elseif kind == "text" or kind == "subhead" then
                    NextRow()
                    local text = tostring(Eval(e.opt.name, e.info) or "")
                    if text:find("%S") then
                        local c = Acquire(kind, child)
                        c.opt, c.info, c.group = e.opt, e.info, s.group
                        c:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
                        c:SetWidth(BODY_W)
                        c:SetHeight(kind == "subhead" and 30 or ROW_H)
                        c:Update()
                        y = y - Num(c:GetHeight(), ROW_H)
                        row = row + 1
                    end
                else
                    local c = Acquire(kind, child)
                    c.opt, c.info, c.group = e.opt, e.info, s.group
                    c:SetPoint("TOPLEFT", child, "TOPLEFT", col * COL_W, y)
                    c:SetSize(COL_W, ROW_H)
                    c.bg:SetColorTexture(1, 1, 1, row % 2 == 0 and 0.035 or 0.018)
                    c.divider:SetShown(col == 0)
                    c:Update()
                    col = col + 1
                    if col == 2 then NextRow() end
                end
            end
            NextRow()
            y = y - 24
        end
    end
    child:SetHeight(-y)
    body:Update()
    UpdateFooter(m)
end

Refresh = function()
    if not win or not win:IsShown() then return end
    local m = PageModel(current)
    local tabs, tab = Tabs(m)
    local sig = Signature(m, tab)
    if sig ~= lastSig then
        lastSig = sig
        local scroll = tonumber(win.body:GetVerticalScroll())
        Render(m, tabs, tab)
        win.body:ScrollTo(scroll or 0)
    else
        UpdateHeader(m)
        EachCell(function(c) if c.opt then c:Update() end end)
        UpdateFooter(m)
    end
    RefreshSidebar()
end

-- Edit mode follows the page: opening a ring's page puts that ring in edit mode, and
-- leaving the page (or closing the window) ends it. Only rings it started itself.
local autoKey
local function FollowPage(path)
    local key = path and path:match("%.([^.]+)$")
    local def = key and ns.FindRing(key)
    if def and def.key ~= key then def = nil end
    if autoKey and autoKey ~= (def and key) then
        ns.SetRingEditing(autoKey, false, true)
        autoKey = nil
    end
    if def and db.optionsAutoEdit and not def.edit.get() then
        ns.SetRingEditing(key, true, true)
        autoKey = key
    end
end

SelectPage = function(path)
    if not PageAt(path) then path = "general" end
    current = path
    lastSig = nil
    W.CloseList()
    if win.body then win.body:SetVerticalScroll(0) end
    Refresh()
    FollowPage(path)
end

---------------------------------------------------------------- building the window
local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = get and get(ADDON_NAME, "Version") or nil
    -- A copy straight from the repository, not a packaged release.
    if version and version:find("@project%-version@") then version = "dev" end
    return version
end

local function CloseX(parent)
    local b = W.Button(parent, 30, 30, "", function() win:Hide() end)
    for _, sign in ipairs({ 1, -1 }) do
        local l = b:CreateLine(nil, "OVERLAY")
        l:SetThickness(1.5)
        l:SetColorTexture(0.8, 0.8, 0.82, 1)
        l:SetStartPoint("CENTER", b, -6, 6 * sign)
        l:SetEndPoint("CENTER", b, 6, -6 * sign)
    end
    b.tipTitle = "Close"
    return b
end

local function BuildWindow()
    win = CreateFrame("Frame", "CircletConfigFrame", UIParent)
    win:Hide()
    win:SetSize(WIN_W, WIN_H)
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
    if win.SetToplevel then win:SetToplevel(true) end
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    table.insert(UISpecialFrames, "CircletConfigFrame") -- Esc closes it

    -- Background: dark slate, the sidebar darker, a faint blue glow behind the title.
    for i, a in ipairs({ 0.35, 0.22, 0.12, 0.05 }) do ns.SkinEdges(win, "BACKGROUND", -8, 2, i * 2, 0, 0, 0, a) end
    win.bg = W.Solid(win, "BACKGROUND", W.BG[1], W.BG[2], W.BG[3], W.BG[4], -7)
    win.bg:SetAllPoints()
    win.glow = win:CreateTexture(nil, "BACKGROUND", nil, -6)
    win.glow:SetPoint("TOPLEFT", win, "TOPLEFT", SIDE_W, 0)
    win.glow:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    win.glow:SetHeight(170)
    ns.SkinGradient(win.glow, "VERTICAL", A.r, A.g, A.b, 0, A.r, A.g, A.b, 0.07)
    win.side = W.Solid(win, "BACKGROUND", 0.04, 0.03, 0.038, 1, -5)
    win.side:SetPoint("TOPLEFT"); win.side:SetPoint("BOTTOMLEFT")
    win.side:SetWidth(SIDE_W)
    win.sideEdge = W.Solid(win, "BORDER", 1, 1, 1, 0.07)
    win.sideEdge:SetPoint("TOPLEFT", win, "TOPLEFT", SIDE_W, 0)
    win.sideEdge:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", SIDE_W, 0)
    win.sideEdge:SetWidth(1)
    win.border = W.Border(win, GOLD.r, GOLD.g, GOLD.b, 0.55)
    win.footRule = W.Solid(win, "BORDER", 1, 1, 1, 0.08)
    win.footRule:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", SIDE_W + 1, FOOT_H)
    win.footRule:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, FOOT_H)
    win.footRule:SetHeight(1)
    win.footBg = W.Solid(win, "BACKGROUND", 0, 0, 0, 0.25, -4)
    win.footBg:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", SIDE_W + 1, 1)
    win.footBg:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, 1)
    win.footBg:SetHeight(FOOT_H - 1)

    -- Sidebar: the logo and name.
    win.logo = ns.SkinLogo(win, 46)
    win.logo:SetPoint("TOPLEFT", win, "TOPLEFT", 20, -18)
    win.name = W.Text(win, 24, GOLD.r, GOLD.g, GOLD.b, "OVERLAY", W.TITLE_FONT)
    win.name:SetPoint("TOPLEFT", win.logo, "TOPRIGHT", 12, -4)
    win.name:SetText("Circlet")
    win.sub = W.Text(win, 11, 0.55, 0.57, 0.62)
    win.sub:SetPoint("TOPLEFT", win.name, "BOTTOMLEFT", 1, -3)
    win.sub:SetText("Progress rings")
    win.logoRule = ns.SkinRule(win, SIDE_W - 36, GOLD.r, GOLD.g, GOLD.b, 0.5)
    win.logoRule:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -80)

    -- Sidebar: the pages and actions at the top.
    win.nav = {}
    local y = -92
    for _, item in ipairs(NAV) do
        local b = SideRow(win, 34)
        b.item = item
        b.tip = item.tip
        b:SetPoint("TOPLEFT", win, "TOPLEFT", 1, y)
        b:SetPoint("TOPRIGHT", win, "TOPLEFT", SIDE_W, y)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(18, 18)
        b.icon:SetPoint("LEFT", b, "LEFT", 22, 0)
        b.icon:SetTexture(item.icon)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if b.icon.SetDesaturated then b.icon:SetDesaturated(true) end
        b.icon:SetAlpha(0.85)
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 14, 0)
        b.text:SetFont(W.TITLE_FONT, 13, "")
        b:SetScript("OnClick", function()
            if item.path then SelectPage(item.path) else item.func(); Refresh() end
        end)
        win.nav[#win.nav + 1] = b
        y = y - 34
    end

    -- Sidebar: search.
    win.search = W.EditBox(win, SIDE_W - 36, "LEFT", function() end)
    win.search:SetPoint("TOPLEFT", win, "TOPLEFT", 18, y - 12)
    win.search.hint = W.Text(win.search, 12, 0.45, 0.47, 0.52)
    win.search.hint:SetPoint("LEFT", 9, 0)
    win.search.hint:SetText("Search rings...")
    win.search:SetScript("OnTextChanged", function(self)
        search = self:GetText() or ""
        self.hint:SetShown(search == "")
        RefreshSidebar()
    end)
    win.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    -- Sidebar: the rings, under their folders.
    win.ringList = W.ScrollArea(win)
    win.ringList:SetPoint("TOPLEFT", win, "TOPLEFT", 1, y - 46)
    win.ringList:SetPoint("BOTTOMRIGHT", win, "BOTTOMLEFT", SIDE_W - 1, 46)
    win.version = W.Text(win, 11, 0.45, 0.47, 0.52)
    win.version:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 20, 16)
    local version = Version()
    win.version:SetText((version and ("v" .. version .. "   ·   ") or "") .. "/circ help for commands")

    -- Header: the page's title and description, and window scale / close at the top right.
    win.title = W.Text(win, 26, 1, 1, 1, "OVERLAY", W.TITLE_FONT)
    win.title:SetPoint("TOPLEFT", win, "TOPLEFT", SIDE_W + PAD, -24)
    win.title:SetWidth(CONTENT_W - PAD * 2 - 330)
    win.title:SetWordWrap(false)
    win.intro = W.Text(win, 13, 0.68, 0.7, 0.75)
    win.intro:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 1, -10)
    win.intro:SetWidth(CONTENT_W - PAD * 2)
    if win.intro.SetSpacing then win.intro:SetSpacing(2) end

    win.close = CloseX(win)
    win.close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -14, -14)
    win.scaleValue = W.Text(win, 12, 0.9, 0.9, 0.92)
    win.scaleValue:SetPoint("RIGHT", win.close, "LEFT", -14, 0)
    win.scaleValue:SetWidth(40)
    win.scaleValue:SetJustifyH("RIGHT")
    win.scale = W.Slider(win, 110, function(v) win.scaleValue:SetText(v .. "%") end, function(v)
        db.optionsScale = v
        win:SetScale(v / 100)
    end)
    win.scale:SetRange(70, 130, 5)
    win.scale:SetPoint("RIGHT", win.scaleValue, "LEFT", -12, 0)
    win.scaleLabel = W.Text(win, 12, 0.7, 0.72, 0.76)
    win.scaleLabel:SetPoint("RIGHT", win.scale, "LEFT", -12, 0)
    win.scaleLabel:SetText("Window scale")

    -- Tabs, the settings, and the footer's Close.
    win.tabRule = W.Solid(win, "BORDER", 1, 1, 1, 0.09)
    win.tabRule:SetHeight(1)
    win.body = W.ScrollArea(win)
    win.closeButton = W.Button(win, 150, 32, "Close", function() win:Hide() end)
    win.closeButton:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, 13)
    win.closeButton:SetAccent()

    win:SetScript("OnShow", function(self)
        local scale = tonumber(db.optionsScale) or 100
        self:SetScale(scale / 100)
        self.scale:SetValue(scale)
        self.scaleValue:SetText(scale .. "%")
        lastSig = nil
        SelectPage(current)
    end)
    win:SetScript("OnHide", function()
        W.CloseList()
        W.HideTip()
        FollowPage(nil)
    end)
end

local function SetupOptions()
    if not ns.W then error("UI/Widgets.lua didn't load") end
    root = BuildOptionsTable()
    ns.OptionsTable = root
    -- Still registered, for anything that reads Circlet's options the AceConfig way.
    local registry = LibStub and LibStub("AceConfigRegistry-3.0", true)
    if registry then registry:RegisterOptionsTable(APP, root) end
    BuildWindow()
    ns.RefreshOptions = function() Refresh() end

    -- Esc > Options > AddOns > Circlet: a short page that opens the window.
    if Settings and Settings.RegisterVerticalLayoutCategory then
        local category, layout = Settings.RegisterVerticalLayoutCategory("Circlet")
        layout:AddInitializer(CreateSettingsButtonInitializer("Circlet options", "Open options", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            if not win:IsShown() then win:Show() end
        end, "Open the Circlet options window. Also /circ.", true))
        Settings.RegisterAddOnCategory(category)
    end
end

-- Builds the window; if it fails on this client, the rest of the addon still works.
local function TrySetupOptions()
    local ok, err = pcall(SetupOptions)
    if not ok then
        if win then win:Hide() end
        win = nil
    end
    return ok, err
end

local function OpenOptions(page)
    if not win then
        Print("The options window failed to load; slash commands still work (/circ help).")
    elseif win:IsShown() and not page then
        win:Hide()
    else
        if page then current = page end
        if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 852) end
        if win:IsShown() then SelectPage(current) else win:Show() end
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
