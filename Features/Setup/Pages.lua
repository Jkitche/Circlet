-- Circlet: Setup wizard and New in page: each page's title, subtitle and items.
local _, ns = ...

local db = ns.db
local SU = ns.SetupUI
local GROUPS = SU.GROUPS
local STYLES = SU.STYLES
local SIZES = SU.SIZES
local PLACES = SU.PLACES
local STEPS = SU.STEPS
local Def = SU.Def
local Shown = SU.Shown
local NewVersion = SU.NewVersion
local showing = SU.showing
local StopShowing = SU.StopShowing
local ToggleShow = SU.ToggleShow
local SetEnabled = SU.SetEnabled
local ApplyLook = SU.ApplyLook

---------------------------------------------------------------- pages
-- Each page: a title, a subtitle and a list of items:
--   { kind = "header", text, col }              { kind = "note", text, col }
--   { kind = "check", id, text, desc, on, onClick, showId, showOn, onShow, col }
--   { kind = "choice", id, text, selected, onClick, col }  (drawn as cards; Look's have pictures, ART)
--   { kind = "button", id, text, onClick, col }
local Page = {}

Page[1] = function()
    local items = {
        {
            kind = "note",
            col = 1,
            text = "Tick the rings you want. |cffffd100Show|r puts one on screen "
                .. "with sample content (you can drag it into place). Hover a name for what it does.",
        },
    }
    local placed, groups = {}, {}
    for _, g in ipairs(GROUPS) do
        local list = {}
        for _, key in ipairs(g.keys) do
            local def = Def(key)
            if def and Shown(def) then
                table.insert(list, def)
                placed[key] = true
            end
        end
        table.insert(groups, { name = g.name, defs = list })
    end
    local other = {}
    for _, def in ipairs(ns.RINGS) do
        if Shown(def) and not placed[def.key] then table.insert(other, def) end
    end
    table.insert(groups, { name = "Other", defs = other })
    -- Two columns: groups go in order, filling the first column to about half.
    local total = 0
    for _, g in ipairs(groups) do
        total = total + #g.defs + 1
    end
    local col, count = 1, 0
    for _, g in ipairs(groups) do
        if #g.defs > 0 then
            if col == 1 and count > 0 and count + #g.defs + 1 > total / 2 + 1 then col = 2 end
            table.insert(items, { kind = "header", text = g.name, col = col })
            for _, def in ipairs(g.defs) do
                local key, t = def.key, def.toggle
                table.insert(items, {
                    kind = "check",
                    col = col,
                    id = "ring:" .. key,
                    text = t[1],
                    desc = t[2],
                    on = db[key .. "Enabled"] and true or false,
                    onClick = function() SetEnabled(key .. "Enabled", not db[key .. "Enabled"], t[3]) end,
                    showId = "show:" .. key,
                    showOn = def.edit and def.edit.get(),
                    onShow = function() ToggleShow(key) end,
                })
            end
            count = count + #g.defs + 1
        end
    end
    return "Pick your rings", items
end

Page[2] = function()
    local items = {
        {
            kind = "note",
            col = 1,
            text = "Some rings show the same thing as a bar of the game's own. "
                .. "Tick one to hide that bar (untick it, here or on the ring's page, to bring it back).",
        },
    }
    for _, def in ipairs(ns.RINGS) do
        if def.gameBar and Shown(def) and db[def.key .. "Enabled"] then
            local key = def.key .. "HideDefault"
            table.insert(items, {
                kind = "check",
                col = 1,
                id = "bar:" .. def.key,
                text = "Hide " .. def.gameBar,
                desc = "Shown instead by the " .. def.toggle[1] .. ".",
                on = db[key] and true or false,
                onClick = function() db[key] = not db[key] end,
            })
        end
    end
    if #items == 1 then
        table.insert(items, { kind = "note", col = 1, text = "None of the rings you picked replace a game bar." })
    end
    return "Hide the game's bars", items
end

Page[3] = function()
    local items = {
        {
            kind = "note",
            col = 1,
            text = "One look for every ring. Each ring's page can still change its "
                .. "own afterwards. |cffffd100Show all|r puts your rings on screen to see it.",
        },
    }
    table.insert(items, { kind = "header", col = 1, text = "Style" })
    for _, s in ipairs(STYLES) do
        table.insert(items, {
            kind = "choice",
            col = 1,
            id = "style:" .. s[1],
            text = s[2],
            selected = SU.choice.style == s[1],
            onClick = function()
                SU.choice.style = s[1]
                ApplyLook()
            end,
        })
    end
    table.insert(items, { kind = "header", col = 2, text = "Size" })
    for _, s in ipairs(SIZES) do
        table.insert(items, {
            kind = "choice",
            col = 2,
            id = "size:" .. s[1],
            text = s[2],
            selected = SU.choice.size == s[1],
            onClick = function()
                SU.choice.size = s[1]
                ApplyLook()
            end,
        })
    end
    local anyShown = next(showing) ~= nil
    table.insert(items, {
        kind = "button",
        col = 2,
        id = "showall",
        text = anyShown and "Hide rings" or "Show all",
        onClick = function()
            if next(showing) then
                StopShowing()
                return
            end
            for _, def in ipairs(ns.RINGS) do
                if Shown(def) and db[def.key .. "Enabled"] and def.edit and not def.edit.get() then
                    ToggleShow(def.key)
                end
            end
        end,
    })
    return "Look", items
end

Page[4] = function()
    local items = {
        {
            kind = "note",
            col = 1,
            text = "Where the rings go. The default layout keeps them in a row "
                .. "across the top of the screen; rings that pop up together slide apart.",
        },
    }
    for _, p in ipairs(PLACES) do
        table.insert(items, {
            kind = "choice",
            col = 1,
            id = "place:" .. p[1],
            text = p[2],
            selected = SU.choice.place == p[1],
            onClick = function() SU.choice.place = p[1] end,
        })
    end
    table.insert(items, {
        kind = "note",
        col = 1,
        text = "You can come back any time: |cffffd100/circ setup|r, or Setup "
            .. "on the options window's General tab. Each ring's own page has many more options.",
    })
    return "Placement", items
end

local function NewPage()
    local items = {
        {
            kind = "note",
            col = 1,
            text = "Added since you last played. Tick what you want; " .. "|cffffd100Show|r puts it on screen.",
        },
    }
    for _, item in ipairs(SU.newItems) do
        table.insert(items, {
            kind = "check",
            col = 1,
            wide = true,
            id = "new:" .. item.id,
            text = item.name,
            desc = item.desc,
            since = item.since,
            info = not item.setting, -- just the news: no on/off box
            on = (not item.setting) or (db[item.setting] and true or false),
            onClick = item.setting and function() SetEnabled(item.setting, not db[item.setting], item.onSet) end or nil,
            showId = item.show and ("shownew:" .. item.id) or nil,
            showOn = item.show and Def(item.show) and Def(item.show).edit and Def(item.show).edit.get(),
            onShow = item.show and function() ToggleShow(item.show) end or nil,
        })
    end
    return "New in Circlet " .. NewVersion(SU.newItems), items
end

-- The current page: title, subtitle, items, and the footer buttons { id, text, enabled }.
local function Current()
    if SU.mode == "new" then
        local title, items = NewPage()
        local n = #SU.newItems
        return title,
            n == 1 and "1 new thing" or (n .. " new things"),
            items,
            { { id = "full", text = "Full setup", side = "left" }, { id = "done", text = "Done" } }
    end
    local name, items = Page[SU.step]()
    return "Welcome to Circlet",
        "Step " .. SU.step .. " of " .. STEPS .. ": " .. name,
        items,
        {
            { id = "skip", text = "Skip setup", side = "left" },
            { id = "back", text = "Back", enabled = SU.step > 1 },
            { id = "next", text = SU.step < STEPS and "Next" or "Finish" },
        }
end

-- For the files loaded after this one.
SU.Current = Current
