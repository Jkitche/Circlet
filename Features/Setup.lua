-- Circlet: The setup wizard (first run) and the "New in <version>" page (after an update).
local ADDON_NAME, ns = ...

local db, Print, SafeCall, DEFAULTS = ns.db, ns.Print, ns.SafeCall, ns.DEFAULTS

---------------------------------------------------------------------------
-- Setup wizard and New in page
---------------------------------------------------------------------------
-- The first time Circlet runs on an account, a short wizard opens a few seconds after the
-- welcome animation:
--   1. Pick your rings, by group, each with a Show button that puts it on screen with
--      sample content (in edit mode, so it can be dragged there and then).
--   2. Hide the game's own bars that the rings you kept replace.
--   3. Look: one style and one size for every ring at once (or keep each ring's own).
--   4. Placement: keep the layout, reset it, or arrange the rings yourself after Finish.
-- Players who had Circlet before get, after an update, a "New in <version>" page instead:
-- just the rings and features added since (registered with since = "x.y.z", plus
-- NEW_FEATURES below), each with an on/off box and Show. Either one is shown once
-- (db.setupDone, db.seenNew: learned data, shared by every profile); /circ setup and
-- /circ new, or the buttons on the General tab, bring them back.
--
-- Each page is built as a list of items (headers, check rows, choices, notes); the window
-- is drawn from that list, and the tests read and click it through ns.Setup.

-- The rings, by group, in the order they're listed. A ring that isn't here goes to "Other".
local GROUPS = {
    { name = "Progress", keys = { "xp", "quest", "pin", "rep", "skill", "weapon", "pet" } },
    { name = "Combat", keys = { "cast", "targetCast", "totem", "ammo" } },
    { name = "Group", keys = { "loot", "ready" } },
    { name = "Travel and survival", keys = { "flight", "timed", "corpse", "breath" } },
    { name = "Professions", keys = { "craft", "gather" } },
    { name = "Comfort", keys = { "food", "camp", "clock" } },
}

-- New features that aren't rings of their own: an on/off setting and a ring to show it on.
local NEW_FEATURES = {
    { id = "corpseReviveFx", since = "1.2.0", name = "Corpse ring: revive animation",
      desc = "Your soul drifts back into the ring when you revive in your own body.",
      setting = "corpseReviveFx", show = "corpse" },
}

local STYLES = { { "keep", "Keep each ring's own" }, { "smooth", "Smooth" }, { "segmented", "Segmented" }, { "thin", "Thin" } }
local SIZES = { { "keep", "Keep each ring's own" }, { "smaller", "Smaller" }, { "default", "Default" }, { "larger", "Larger" } }
local SIZE_FACTOR = { smaller = 0.85, default = 1, larger = 1.2 }
local PLACES = { { "keep", "Keep where they are" }, { "reset", "Reset to the default layout" },
                 { "arrange", "Arrange them myself after Finish" } }
local STEPS = 4

---------------------------------------------------------------- helpers
-- "1.2.0" -> comparable; anything not a version (a dev build's @project-version@) is nil.
local function VersionParts(v)
    if type(v) ~= "string" then return nil end
    local a, b, c = v:match("^v?(%d+)%.?(%d*)%.?(%d*)")
    if not a then return nil end
    return { tonumber(a), tonumber(b) or 0, tonumber(c) or 0 }
end
local function Newer(a, b) -- is version string a newer than b?
    local x, y = VersionParts(a), VersionParts(b)
    if not x then return false elseif not y then return true end
    for i = 1, 3 do if x[i] ~= y[i] then return x[i] > y[i] end end
    return false
end
local function AddonVersion()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = get and SafeCall(get, ADDON_NAME, "Version")
    return VersionParts(v) and (v:gsub("^v", "")) or nil
end

local function Def(key) local d = ns.FindRing(key) return d and d.key == key and d or nil end
local function Shown(def) return def.toggle and not ns.HiddenForClass(def) end

-- Everything that's new: rings with `since` and NEW_FEATURES, newest release first.
-- unseenOnly: only what this player hasn't been shown yet.
local function NewItems(unseenOnly)
    local list = {}
    for _, def in ipairs(ns.RINGS) do
        if def.since and Shown(def) then
            table.insert(list, { id = def.key, since = def.since, name = def.toggle[1], desc = def.toggle[2],
                                 setting = def.key .. "Enabled", onSet = def.toggle[3], show = def.key })
        end
    end
    for _, f in ipairs(NEW_FEATURES) do
        local def = Def(f.show)
        if not def or Shown(def) then table.insert(list, f) end
    end
    if unseenOnly then
        local seen = db.seenNew or {}
        for i = #list, 1, -1 do if seen[list[i].id] then table.remove(list, i) end end
    end
    table.sort(list, function(a, b)
        if a.since ~= b.since then return Newer(a.since, b.since) end
        return a.name < b.name
    end)
    return list
end

local function MarkAllSeen()
    db.seenNew = db.seenNew or {}
    for _, item in ipairs(NewItems(false)) do db.seenNew[item.id] = true end
end

-- The version the New in page names: this build's, or (a dev build) the newest item's.
local function NewVersion(items)
    local v = AddonVersion()
    if v then return v end
    return items[1] and items[1].since or "this version"
end

---------------------------------------------------------------- state
local mode            -- "wizard" or "new"
local step = 1
local choice = {}     -- the Look and Placement choices: style, size, place
local orig            -- each ring's style and size when the wizard opened (for "keep")
local showing = {}    -- rings the wizard put in edit mode to show them
local newItems = {}   -- what the New in page lists
local Render          -- forward

local function StopShowing()
    for key in pairs(showing) do
        if ns.SetRingEditing then ns.SetRingEditing(key, false, true) end
        showing[key] = nil
    end
end

local function ToggleShow(key)
    local def = Def(key)
    if not (def and def.edit) then return end
    local on = not def.edit.get()
    ns.SetRingEditing(key, on, true)
    showing[key] = on or nil
end

local function SetEnabled(key, value, onSet)
    db[key] = value
    if onSet then onSet(value) end
end

-- Look: one style / size for every ring, or each ring's own (as it was when the wizard opened).
local function ApplyLook()
    for _, def in ipairs(ns.RINGS) do
        local k = def.key
        if DEFAULTS[k .. "Style"] ~= nil then
            db[k .. "Style"] = choice.style == "keep" and orig[k].style or choice.style
        end
        if DEFAULTS[k .. "Size"] ~= nil then
            local f = SIZE_FACTOR[choice.size]
            db[k .. "Size"] = f and math.floor(DEFAULTS[k .. "Size"] * f + 0.5) or orig[k].size
        end
    end
end

---------------------------------------------------------------- pages
-- Each page: a title, a subtitle and a list of items:
--   { kind = "header", text, col }              { kind = "note", text, col }
--   { kind = "check", id, text, desc, on, onClick, showId, showOn, onShow, col }
--   { kind = "choice", id, text, selected, onClick, col }
local Page = {}

Page[1] = function()
    local items = { { kind = "note", col = 1, text = "Tick the rings you want. |cffffd100Show|r puts one on screen "
        .. "with sample content (you can drag it into place). Hover a name for what it does." } }
    local placed, groups = {}, {}
    for _, g in ipairs(GROUPS) do
        local list = {}
        for _, key in ipairs(g.keys) do
            local def = Def(key)
            if def and Shown(def) then table.insert(list, def) placed[key] = true end
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
    for _, g in ipairs(groups) do total = total + #g.defs + 1 end
    local col, count = 1, 0
    for _, g in ipairs(groups) do
        if #g.defs > 0 then
            if col == 1 and count > 0 and count + #g.defs + 1 > total / 2 + 1 then col = 2 end
            table.insert(items, { kind = "header", text = g.name, col = col })
            for _, def in ipairs(g.defs) do
                local key, t = def.key, def.toggle
                table.insert(items, {
                    kind = "check", col = col, id = "ring:" .. key, text = t[1], desc = t[2],
                    on = db[key .. "Enabled"] and true or false,
                    onClick = function() SetEnabled(key .. "Enabled", not db[key .. "Enabled"], t[3]) end,
                    showId = "show:" .. key, showOn = def.edit and def.edit.get(),
                    onShow = function() ToggleShow(key) end,
                })
            end
            count = count + #g.defs + 1
        end
    end
    return "Pick your rings", items
end

Page[2] = function()
    local items = { { kind = "note", col = 1, text = "Some rings show the same thing as a bar of the game's own. "
        .. "Tick one to hide that bar (untick it, here or on the ring's page, to bring it back)." } }
    for _, def in ipairs(ns.RINGS) do
        if def.gameBar and Shown(def) and db[def.key .. "Enabled"] then
            local key = def.key .. "HideDefault"
            table.insert(items, { kind = "check", col = 1, id = "bar:" .. def.key,
                text = "Hide " .. def.gameBar, desc = "Shown instead by the " .. def.toggle[1] .. ".",
                on = db[key] and true or false, onClick = function() db[key] = not db[key] end })
        end
    end
    if #items == 1 then
        table.insert(items, { kind = "note", col = 1, text = "None of the rings you picked replace a game bar." })
    end
    return "Hide the game's bars", items
end

Page[3] = function()
    local items = { { kind = "note", col = 1, text = "One look for every ring. Each ring's page can still change its "
        .. "own afterwards. |cffffd100Show all|r puts your rings on screen to see it." } }
    table.insert(items, { kind = "header", col = 1, text = "Style" })
    for _, s in ipairs(STYLES) do
        table.insert(items, { kind = "choice", col = 1, id = "style:" .. s[1], text = s[2], selected = choice.style == s[1],
            onClick = function() choice.style = s[1]; ApplyLook() end })
    end
    table.insert(items, { kind = "header", col = 2, text = "Size" })
    for _, s in ipairs(SIZES) do
        table.insert(items, { kind = "choice", col = 2, id = "size:" .. s[1], text = s[2], selected = choice.size == s[1],
            onClick = function() choice.size = s[1]; ApplyLook() end })
    end
    local anyShown = next(showing) ~= nil
    table.insert(items, { kind = "choice", col = 2, id = "showall", text = anyShown and "Hide rings" or "Show all",
        onClick = function()
            if next(showing) then StopShowing() return end
            for _, def in ipairs(ns.RINGS) do
                if Shown(def) and db[def.key .. "Enabled"] and def.edit and not def.edit.get() then ToggleShow(def.key) end
            end
        end })
    return "Look", items
end

Page[4] = function()
    local items = { { kind = "note", col = 1, text = "Where the rings go. The default layout keeps them in a row "
        .. "across the top of the screen; rings that pop up together slide apart." } }
    for _, p in ipairs(PLACES) do
        table.insert(items, { kind = "choice", col = 1, id = "place:" .. p[1], text = p[2], selected = choice.place == p[1],
            onClick = function() choice.place = p[1] end })
    end
    table.insert(items, { kind = "note", col = 1, text = "You can come back any time: |cffffd100/circ setup|r, or Setup "
        .. "on the options window's General tab. Each ring's own page has many more options." })
    return "Placement", items
end

local function NewPage()
    local items = { { kind = "note", col = 1, text = "Added since you last played. Tick what you want; "
        .. "|cffffd100Show|r puts it on screen." } }
    for _, item in ipairs(newItems) do
        table.insert(items, { kind = "check", col = 1, wide = true, id = "new:" .. item.id, text = item.name, desc = item.desc,
            on = db[item.setting] and true or false,
            onClick = function() SetEnabled(item.setting, not db[item.setting], item.onSet) end,
            showId = item.show and ("shownew:" .. item.id) or nil, showOn = item.show and Def(item.show)
                and Def(item.show).edit and Def(item.show).edit.get(),
            onShow = item.show and function() ToggleShow(item.show) end or nil })
    end
    return "New in Circlet " .. NewVersion(newItems), items
end

-- The current page: title, subtitle, items, and the footer buttons { id, text, enabled }.
local function Current()
    if mode == "new" then
        local title, items = NewPage()
        local n = #newItems
        return title, n == 1 and "1 new thing" or (n .. " new things"), items,
            { { id = "full", text = "Full setup", side = "left" }, { id = "done", text = "Done" } }
    end
    local name, items = Page[step]()
    return "Welcome to Circlet", "Step " .. step .. " of " .. STEPS .. ": " .. name, items, {
        { id = "skip", text = "Skip setup", side = "left" },
        { id = "back", text = "Back", enabled = step > 1 },
        { id = "next", text = step < STEPS and "Next" or "Finish" },
    }
end

---------------------------------------------------------------- window
local W, H = 700, 500
local frame = CreateFrame("Frame", "CircletSetupFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
frame:SetSize(W, H)
frame:SetFrameStrata("DIALOG")
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -40)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetClampedToScreen(true)
frame:Hide()
if frame.SetBackdrop then
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.65, 1)
else
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.95)
end
table.insert(UISpecialFrames, "CircletSetupFrame") -- Esc closes it

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.title:SetPoint("TOP", frame, "TOP", 0, -14)
frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.subtitle:SetPoint("TOP", frame.title, "BOTTOM", 0, -4)
frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

local body = CreateFrame("Frame", nil, frame)
body:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -58)
body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 44)

local COL_X, COL_W, ROW_H = { 0, 340 }, 320, 22
local pool = { check = {}, header = {}, note = {}, choice = {}, footer = {} }
local used = {}

local function Tooltip(owner, title, text)
    owner:SetScript("OnEnter", function(self)
        if not (GameTooltip and text) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local makers = {
    header = function()
        local f = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f:SetJustifyH("LEFT")
        return f
    end,
    note = function()
        local f = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f:SetJustifyH("LEFT")
        f:SetWordWrap(true)
        return f
    end,
    check = function()
        local w = CreateFrame("Frame", nil, body)
        w.check = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
        w.check:SetSize(24, 24)
        w.check:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 1)
        w.text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        w.text:SetPoint("TOPLEFT", w.check, "TOPRIGHT", 2, -5)
        w.text:SetJustifyH("LEFT")
        w.desc = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        w.desc:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -2)
        w.desc:SetJustifyH("LEFT")
        w.show = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        w.show:SetSize(58, 20)
        w.show:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)
        return w
    end,
    choice = function()
        local b = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
        b:SetSize(220, 22)
        return b
    end,
    footer = function()
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(110, 22)
        return b
    end,
}

local function Acquire(kind)
    used[kind] = (used[kind] or 0) + 1
    local w = pool[kind][used[kind]]
    if not w then w = makers[kind]() pool[kind][used[kind]] = w end
    w:Show()
    return w
end

local Click -- forward

-- Draws the current page.
Render = function()
    if not frame:IsShown() then return end
    for kind, list in pairs(pool) do
        for _, w in ipairs(list) do w:Hide() end
        used[kind] = 0
    end
    local title, subtitle, items, buttons = Current()
    frame.title:SetText(title)
    frame.subtitle:SetText(subtitle)
    local y = { 0, 0 }
    for _, item in ipairs(items) do
        local c = item.col or 1
        local x, width = COL_X[c], (item.wide or item.kind == "note") and (COL_X[2] + COL_W) or COL_W
        if item.kind == "header" then
            local f = Acquire("header")
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", body, "TOPLEFT", x, -(y[c] + 6))
            f:SetText(item.text)
            y[c] = y[c] + 24
        elseif item.kind == "note" then
            local f = Acquire("note")
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y[c])
            f:SetWidth(width)
            f:SetText(item.text)
            -- A note spans both columns: both continue below it.
            local sh = f.GetStringHeight and f:GetStringHeight()
            local h = math.max(14, type(sh) == "number" and sh or 14) + 8
            y[1], y[2] = math.max(y[1], y[c] + h), math.max(y[2], y[c] + h)
        elseif item.kind == "check" then
            local w = Acquire("check")
            local h = item.wide and 38 or ROW_H
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y[c])
            w:SetSize(width, h)
            w.check:SetChecked(item.on)
            w.check:SetScript("OnClick", function() Click(item.id) end)
            w.text:SetText(item.text)
            w.desc:SetText(item.wide and item.desc or "")
            w.desc:SetWidth(width - 100)
            Tooltip(w.check, item.text, item.desc)
            if item.showId then
                w.show:SetText(item.showOn and "Hide" or "Show")
                w.show:SetScript("OnClick", function() Click(item.showId) end)
                w.show:Show()
            else
                w.show:Hide()
            end
            y[c] = y[c] + h
        elseif item.kind == "choice" then
            local b = Acquire("choice")
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", body, "TOPLEFT", x + 4, -(y[c] + 2))
            b:SetText(item.selected and ("|cff33ff33" .. item.text .. "|r") or item.text)
            if item.selected then b:LockHighlight() else b:UnlockHighlight() end
            b:SetScript("OnClick", function() Click(item.id) end)
            y[c] = y[c] + 26
        end
    end
    local right = -12
    for i = #buttons, 1, -1 do
        local spec = buttons[i]
        local b = Acquire("footer")
        b:ClearAllPoints()
        if spec.side == "left" then
            b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
        else
            b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, 12)
            right = right - 116
        end
        b:SetText(spec.text)
        if spec.enabled == false then b:Disable() else b:Enable() end
        b:SetScript("OnClick", function() Click(spec.id) end)
    end
end

---------------------------------------------------------------- opening, closing, clicking
local function OpenWizard()
    StopShowing()
    mode, step = "wizard", 1
    orig = {}
    for _, def in ipairs(ns.RINGS) do
        orig[def.key] = { style = db[def.key .. "Style"], size = db[def.key .. "Size"] }
    end
    choice = { style = "keep", size = "keep", place = "keep" }
    frame:Show()
    Render()
end

-- The New in page. all: list everything from the newest release even if already seen.
local function OpenNew(all)
    local items = NewItems(true)
    if #items == 0 and all then
        local every = NewItems(false)
        local newest = every[1] and every[1].since
        for _, it in ipairs(every) do if it.since == newest then table.insert(items, it) end end
    end
    if #items == 0 then return false end
    StopShowing()
    mode, newItems = "new", items
    frame:Show()
    Render()
    return true
end

frame:SetScript("OnHide", function()
    StopShowing()
    -- Closed one way or another: don't show it again on its own.
    if mode == "wizard" then db.setupDone = true end
    MarkAllSeen()
end)

local function Finish()
    if choice.place == "reset" and ns.ResetPositions then ns.ResetPositions() end
    frame:Hide() -- (closing also ends the Show previews; arranging starts edit mode afresh)
    if choice.place == "arrange" then
        for _, def in ipairs(ns.RINGS) do
            if Shown(def) and db[def.key .. "Enabled"] and def.edit then ns.SetRingEditing(def.key, true, true) end
        end
    end
    Print("Setup done. /circ setup brings the wizard back; /circ options has every setting.")
end

-- Clicks an item or footer button by id (the window's buttons and the tests both use this).
Click = function(id)
    if id == "next" then
        StopShowing()
        if step < STEPS then step = step + 1 else return Finish() end
    elseif id == "back" then
        StopShowing()
        step = math.max(1, step - 1)
    elseif id == "skip" or id == "done" then
        frame:Hide()
        return
    elseif id == "full" then
        frame:Hide()
        OpenWizard()
        return
    else
        local _, _, items = Current()
        for _, item in ipairs(items) do
            if item.id == id and item.onClick then item.onClick() break end
            if item.showId == id and item.onShow then item.onShow() break end
        end
    end
    Render()
end

---------------------------------------------------------------- when it opens on its own
-- On login (or a /reload), a little after the welcome animation: the wizard on the very
-- first run, else the New in page if there's anything new. Not in combat: it waits.
local function Decide()
    if ns.firstRun and not db.setupDone then return "wizard" end
    db.setupDone = true -- had Circlet before: no full setup, just what's new
    if db.seenNew == nil then db.seenNew = {} end -- tracking starts: anything with `since` is new
    if #NewItems(true) > 0 then return "new" end
end

local pending
local function OpenPending()
    if not pending or frame:IsShown() then return end
    if InCombatLockdown and InCombatLockdown() then return end -- PLAYER_REGEN_ENABLED tries again
    local what = pending
    pending = nil
    if what == "wizard" then OpenWizard() else OpenNew(false) end
end

ns.Listen({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }, function(event, isLogin, isReload)
    if not CircletDB then return end
    if event == "PLAYER_REGEN_ENABLED" then OpenPending() return end
    if not (isLogin or isReload) then return end -- just changing zones
    pending = Decide()
    if pending and C_Timer then C_Timer.After(db.loginFx and 6 or 2, OpenPending) end
end)

ns.RegisterCommand({ "setup", "wizard" }, OpenWizard, "the setup wizard: pick your rings, their look and layout")
ns.RegisterCommand({ "new", "whatsnew" }, function()
    if not OpenNew(true) then Print("Nothing new to show.") end
end, "what's new in this version")

-- Shared with the files loaded after this one (and the tests).
ns.OpenSetup = OpenWizard
ns.OpenWhatsNew = function() return OpenNew(true) end
ns.Setup = {
    frame = frame, Click = Click, Open = OpenWizard, OpenNew = OpenNew,
    -- The current page as text: title, subtitle, then one line per item and the footer.
    Lines = function()
        local title, subtitle, items, buttons = Current()
        local out = { title, subtitle }
        for _, item in ipairs(items) do
            local pre = (item.col == 2) and "      | " or ""
            if item.kind == "header" then table.insert(out, pre .. "== " .. item.text)
            elseif item.kind == "note" then table.insert(out, pre .. "(" .. (item.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) .. ")")
            elseif item.kind == "check" then
                table.insert(out, pre .. (item.on and "[x] " or "[ ] ") .. item.text
                    .. (item.showId and (item.showOn and "  <Hide>" or "  <Show>") or ""))
            elseif item.kind == "choice" then table.insert(out, pre .. (item.selected and "(*) " or "( ) ") .. item.text) end
        end
        local b = {}
        for _, spec in ipairs(buttons) do table.insert(b, spec.enabled == false and ("{" .. spec.text .. "}") or ("[" .. spec.text .. "]")) end
        table.insert(out, "footer: " .. table.concat(b, " "))
        return out
    end,
}
