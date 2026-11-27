-- Circlet: The options window's shared state and a page taken apart into sections, tabs and buttons.
local _, ns = ...

local UI = ns.OptionsUI
local NOT_AVAILABLE = UI.NOT_AVAILABLE

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
-- Laid out like EllesmereUI's options: a sidebar on the left (logo, General / Profiles and
-- a few actions, a search box, then every ring under its folder with an on/off dot), and
-- on the right the page's title and description, tabs, its settings in titled sections of
-- two columns (label on the left of each cell, control on the right), and a footer with
-- the page's buttons (Edit mode, Preview, Reset) and Close.
-- The pages are the same option tables as before (AceConfig format, built by each ring's
-- page.build with UI/Options/Kit.lua), drawn with UI/Widgets.lua.

local W = ns.W
local A = W.ACCENT
local GOLD = ns.SKIN_GOLD

local WIN_W, WIN_H = 1060, 700
local SIDE_W, FOOT_H, PAD = 240, 58, 28
local CONTENT_W = WIN_W - SIDE_W
local BODY_W = CONTENT_W - PAD * 2 - 12 -- the scrollbar sits in the last 12
local COL_W = BODY_W / 2
local ROW_H = 46

UI.current = "general" -- the page shown: "general", "profiles", "<folder>" or "<folder>.<ring>"
local tabOf = {}          -- page -> the tab picked on it

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
    local node = UI.root
    for part in path:gmatch("[^.]+") do node = node and node.args and node.args[part] end
    return node
end

-- The info table AceConfig passes to get/set/name/...: the path to the option, and the option.
local function Info(opt, ...)
    local info = { ... }
    info.option, info.type, info.arg, info.options = opt, opt.type, opt.arg, UI.root
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
    -- A whole page greyed out (another class's ring): the warning goes above its description.
    if Eval(page.disabled, pinfo) then
        m.disabled = true
        m.intro = NOT_AVAILABLE .. ((m.intro and m.intro ~= "") and ("\n\n" .. m.intro) or "")
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
        local t = TabOf(UI.current, s)
        s.tab = t
        if not seen[t] then seen[t] = true; tabs[#tabs + 1] = t end
    end
    table.sort(tabs, function(a, b) return (TAB_ORDER[a] or 9) < (TAB_ORDER[b] or 9) end)
    local pick = tabOf[UI.current]
    if not seen[pick] then pick = tabs[1] end
    return tabs, pick
end

local function Signature(m, tab)
    local parts = { UI.current, tostring(tab) }
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
        UI.Refresh()
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

-- For the files loaded after this one.
UI.W = W
UI.BODY_W = BODY_W
UI.COL_W = COL_W
UI.ROW_H = ROW_H
UI.Eval = Eval
UI.Num = Num
UI.Commit = Commit
UI.Fmt = Fmt
UI.A = A
UI.SIDE_W = SIDE_W
UI.Sorted = Sorted
UI.Info = Info
UI.FOOT_H = FOOT_H
UI.PAD = PAD
UI.tabOf = tabOf
UI.PageAt = PageAt
UI.PageModel = PageModel
UI.Tabs = Tabs
UI.Signature = Signature
UI.GOLD = GOLD
UI.WIN_W = WIN_W
UI.WIN_H = WIN_H
UI.CONTENT_W = CONTENT_W
