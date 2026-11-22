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
    { name = "Combat", keys = { "cast", "swing", "shot", "targetCast", "regen", "totem", "ammo" } },
    { name = "Group", keys = { "loot", "ready", "soulstone" } },
    { name = "Travel and survival", keys = { "flight", "hearth", "timed", "corpse", "breath" } },
    { name = "Professions", keys = { "craft", "gather", "fish" } },
    { name = "Comfort", keys = { "food", "camp", "clock", "timer" } },
}

-- Everything else in a release that isn't a ring of its own: with a setting, an on/off box
-- (and show: a ring to show it on); without one, just the news (fixes, changes, commands).
local NEW_FEATURES = {
    { id = "corpseReviveFx", since = "1.2.0", name = "Corpse ring: revive animation",
      desc = "Your soul drifts back into the ring when you revive in your own body.",
      setting = "corpseReviveFx", show = "corpse" },
    -- 1.4.0
    { id = "craftFx", since = "1.4.0", name = "Crafting animations",
      desc = "Each crafting profession gets its own animation on the crafting ring: bubbling potions, a hammer "
          .. "and sparks, lightning, runes, a stitching needle, flames and steam and more.",
      setting = "craftFx", show = "craft" },
    { id = "xpGainFx", since = "1.4.0", name = "XP ring: gain animation",
      desc = "A glowing comet rides the end of the fill as XP comes in, with a flare where it lands.",
      setting = "xpGainFx", show = "xp" },
    { id = "regenFx", since = "1.4.0", name = "Mana regen ring: animation",
      desc = "A spark charges while the five-second rule holds your regen back; mana spirals in when it starts again.",
      setting = "regenFx", show = "regen" },
    { id = "flightFx", since = "1.4.0", name = "Flight ring: animation",
      desc = "The arrow flies along the fill with a contrail through clouds and wind, then touches down in a puff of dust.",
      setting = "flightFx", show = "flight" },
    { id = "lootFx", since = "1.4.0", name = "Loot roll ring: dice",
      desc = "Two dice rattle while you decide, then tumble and land on their numbers when you roll.",
      setting = "lootFx", show = "loot" },
    { id = "timedFx", since = "1.4.0", name = "Timed quest ring: hourglass",
      desc = "Sand trickles from the end of the fill and piles up as time runs out.",
      setting = "timedFx", show = "timed" },
    { id = "skillFx", since = "1.4.0", name = "Profession skill ring: animation",
      desc = "A spark rides the fill shedding glitter, then bursts; a new tier or the cap sends a gold shimmer round.",
      setting = "skillFx", show = "skill" },
    { id = "weaponFx", since = "1.4.0", name = "Weapon skill ring: animation",
      desc = "A steel swoosh, a clang and a spray of sparks; capping a skill sends a blade glint round the ring.",
      setting = "weaponFx", show = "weapon" },
    { id = "swingHideDefault", since = "1.4.0", name = "Hide the game's swing timer bars",
      desc = "Let the swing timer ring replace WoW Forever's own melee swing timer bars.",
      setting = "swingHideDefault", show = "swing" },
    { id = "shotHideDefault", since = "1.4.0", name = "Hide the game's ranged swing timer bar",
      desc = "Let the shot timer ring replace WoW Forever's own ranged swing timer bar.",
      setting = "shotHideDefault", show = "shot" },
    { id = "flightTimesFixed", since = "1.4.0", name = "Flight times fixed",
      desc = "The flight ring counted down about 11% too fast; it now lands within a second of the real time.",
      show = "flight" },
    { id = "showxpCommand", since = "1.4.0", name = "/circ showxp",
      desc = "Brings the XP ring up for a few seconds at your current XP and prints your XP to chat." },
    { id = "optionsFolders", since = "1.4.0", name = "Tidier options window",
      desc = "Rings sorted into six folders, ring checkboxes grouped by folder, and checkboxes two to a row "
          .. "with their explanations in tooltips." },
    { id = "editAllSaved", since = "1.4.0", name = "Edit all rings: one message",
      desc = "Finishing Edit all rings says \"All ring positions saved.\" once, not a line for every ring." },
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
                                 setting = def.key .. "Enabled", onSet = def.toggle[3], show = def.key, rank = 1 })
        end
    end
    for i, f in ipairs(NEW_FEATURES) do
        local def = Def(f.show)
        if not def or Shown(def) then
            f.rank, f.order = f.setting and 2 or 3, i -- settings before plain news, as listed
            table.insert(list, f)
        end
    end
    if unseenOnly then
        local seen = db.seenNew or {}
        for i = #list, 1, -1 do if seen[list[i].id] then table.remove(list, i) end end
    end
    -- Newest release first; in each, new rings (by name), then new settings, then the news.
    table.sort(list, function(a, b)
        if a.since ~= b.since then return Newer(a.since, b.since) end
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.rank == 1 then return a.name < b.name end
        return a.order < b.order
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
--   { kind = "choice", id, text, selected, onClick, col }  (drawn as cards; Look's have pictures, ART)
--   { kind = "button", id, text, onClick, col }
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
    table.insert(items, { kind = "button", col = 2, id = "showall", text = anyShown and "Hide rings" or "Show all",
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
            since = item.since,
            info = not item.setting, -- just the news: no on/off box
            on = (not item.setting) or (db[item.setting] and true or false),
            onClick = item.setting and function() SetEnabled(item.setting, not db[item.setting], item.onSet) end or nil,
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
table.insert(UISpecialFrames, "CircletSetupFrame") -- Esc closes it

-- Circlet's window look (Features/PanelSkin.lua): header band with the turning logo,
-- gold border and accent line, a rule over the footer.
local HEADER, FOOTER = 58, 44
local GOLD = ns.SKIN_GOLD
local skin = ns.SkinPanel(frame, { header = HEADER, footer = FOOTER })
-- In the options window's colors and controls (UI/Widgets.lua).
local Wd = ns.W
Wd.ThemePanel(frame, skin, HEADER, FOOTER)

frame.title = Wd.Text(frame, 20, 1, 1, 1, "OVERLAY", Wd.TITLE_FONT)
frame.title:SetPoint("TOPLEFT", skin.logo, "TOPRIGHT", 12, -1)
frame.subtitle = Wd.Text(frame, 12, Wd.MUTED[1], Wd.MUTED[2], Wd.MUTED[3])
frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 1, -4)
frame.close = Wd.CloseButton(frame, function() frame:Hide() end)
frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -14)

-- The step ring, in the header's right corner: one notch per step, filled up to this one.
local STEP_R = 15
frame.steps = CreateFrame("Frame", nil, frame)
frame.steps:SetSize(STEP_R * 2, STEP_R * 2)
frame.steps:SetPoint("RIGHT", frame, "TOPRIGHT", -56, -HEADER / 2)
local stepGeom = { R = STEP_R - 2, T = 4, step = 2 * math.pi / ns.XP_SEGMENTS, style = "segmented", notches = STEPS, gapPx = 3 }
frame.steps.track = ns.NewRingLayer("BACKGROUND", 1, ns.TRACK, 1, frame.steps)
frame.steps.fill = ns.NewRingLayer("ARTWORK", 0, GOLD, 1, frame.steps)
frame.steps.text = frame.steps:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.steps.text:SetPoint("CENTER")
local function DrawSteps(n)
    ns.DrawArc(frame.steps.track, 0, 1, frame.steps, stepGeom, true)
    ns.DrawArc(frame.steps.fill, 0, n / STEPS, frame.steps, stepGeom)
    frame.steps.text:SetText(n .. "/" .. STEPS)
end

-- The page body scrolls (with the mouse wheel) when it's taller than the window: the New in
-- page can list a whole release. A slim bar on the right shows where you are.
local scroll = CreateFrame("ScrollFrame", nil, frame)
scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -(HEADER + 12))
scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, FOOTER + 6)
local body = CreateFrame("Frame", nil, scroll)
body:SetSize(W - 40, 10)
scroll:SetScrollChild(body)
local bar = scroll:CreateTexture(nil, "OVERLAY")
bar:SetColorTexture(0.5, 0.42, 0.36, 0.7)
bar:SetWidth(5)
bar:Hide()

local function Num(v) return type(v) == "number" and v or 0 end
local function MaxScroll() return math.max(0, Num(body:GetHeight()) - Num(scroll:GetHeight())) end
local function SetScroll(v)
    local max = MaxScroll()
    v = math.max(0, math.min(max, Num(v)))
    scroll:SetVerticalScroll(v)
    local view = Num(scroll:GetHeight())
    if max > 0 and view > 0 then
        local total = view + max
        local h = math.max(20, view * view / total)
        bar:SetHeight(h)
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 14, -(view - h) * v / max)
        bar:Show()
    else
        bar:Hide()
    end
end
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(_, delta) SetScroll(Num(scroll:GetVerticalScroll()) - delta * 40) end)
local scrolledFor -- the page the scroll position belongs to (a new page starts at the top)

local COL_X, COL_W, ROW_H = { 0, 340 }, 320, 23
local FULL_W = COL_X[2] + COL_W
local pool = { check = {}, header = {}, note = {}, card = {}, button = {}, footer = {} }
local used = {}

-- Pictures on the Look cards: mini rings { style, radius } drawn in that style / at that size.
local ART = {
    ["style:keep"] = { { "smooth", 11 }, { "segmented", 11 }, { "thin", 11 } },
    ["style:smooth"] = { { "smooth", 22 } }, ["style:segmented"] = { { "segmented", 22 } },
    ["style:thin"] = { { "thin", 22 } },
    ["size:keep"] = { { "smooth", 8 }, { "smooth", 11 }, { "smooth", 14 } },
    ["size:smaller"] = { { "smooth", 16 } }, ["size:default"] = { { "smooth", 20 } },
    ["size:larger"] = { { "smooth", 25 } },
}
local CARD_W, CARD_H, CARD_GAP = 155, 92, 10  -- picture cards (two to a column)
local TEXT_CARD_W, TEXT_CARD_H = 213, 48      -- placement cards (three across)

local function Tooltip(owner, title, text, hl)
    owner:SetScript("OnEnter", function(self)
        if hl then hl:Show() end
        if not (GameTooltip and text) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function()
        if hl then hl:Hide() end
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function SetEdges(e, r, g, b, a) for _, t in pairs(e) do t:SetColorTexture(r, g, b, a) end end

-- A mini ring on a card: style "smooth" / "segmented" / "thin", radius r, 70% filled in gold.
local function MiniRing(card, i)
    local m = card.minis[i]
    if m then return m end
    m = CreateFrame("Frame", nil, card)
    m.track = ns.NewRingLayer("BORDER", 0, ns.TRACK, 1, m)
    m.fill = ns.NewRingLayer("ARTWORK", 0, GOLD, 1, m)
    m.geom = { step = 2 * math.pi / ns.XP_SEGMENTS, notches = 12, gapPx = 2 }
    card.minis[i] = m
    return m
end

local function DrawMini(m, style, r, lit)
    m:SetSize(r * 2, r * 2)
    local g = m.geom
    g.T = style == "thin" and 2.5 or math.max(3, r * 0.3)
    g.R, g.style = r - g.T / 2, style
    for _, l in ipairs(m.fill) do l:SetColorTexture(lit and GOLD.r or 0.75, lit and GOLD.g or 0.75, lit and GOLD.b or 0.8, 1) end
    ns.DrawArc(m.track, 0, 1, m, g, true)
    ns.DrawArc(m.fill, 0, 0.7, m, g)
end

local makers = {
    -- Section title: small warm capitals over a faint line, like the options window's.
    header = function()
        local f = CreateFrame("Frame", nil, body)
        f:SetSize(COL_W, 20)
        f.text = Wd.Text(f, 11, Wd.HEADING[1], Wd.HEADING[2], Wd.HEADING[3])
        f.text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 5)
        f.line = f:CreateTexture(nil, "ARTWORK")
        f.line:SetPoint("BOTTOMLEFT"); f.line:SetPoint("BOTTOMRIGHT")
        f.line:SetHeight(1)
        ns.SkinGradient(f.line, "HORIZONTAL", 1, 1, 1, 0.12, 1, 1, 1, 0)
        f.SetLabel = function(self, t) self.text:SetText(tostring(t or ""):upper()) end
        return f
    end,
    -- A clickable card: a picture (mini rings) or just a label; gold border and tick when picked.
    card = function()
        local c = CreateFrame("Button", nil, body)
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints()
        c.glow = c:CreateTexture(nil, "BACKGROUND", nil, 1)
        c.glow:SetAllPoints()
        ns.SkinGradient(c.glow, "VERTICAL", GOLD.r, GOLD.g, GOLD.b, 0.02, GOLD.r, GOLD.g, GOLD.b, 0.16)
        c.edges = ns.SkinEdges(c, "BORDER", 0, 1, 0, 1, 1, 1, 0.10)
        c.label = Wd.Text(c, 12, 0.88, 0.88, 0.88)
        c.label:SetJustifyH("CENTER")
        c.tick = c:CreateTexture(nil, "OVERLAY")
        c.tick:SetTexture(Wd.DOT)
        c.tick:SetVertexColor(GOLD.r, GOLD.g, GOLD.b, 1)
        c.tick:SetSize(9, 9)
        c.tick:SetPoint("TOPRIGHT", c, "TOPRIGHT", -7, -7)
        c.minis = {}
        c:SetScript("OnEnter", function(self) if not self.picked then SetEdges(self.edges, 1, 1, 1, 0.3) end end)
        c:SetScript("OnLeave", function(self) if not self.picked then SetEdges(self.edges, 1, 1, 1, 0.10) end end)
        return c
    end,
    button = function()
        local b = Wd.Button(body, 150, 26, "")
        return b
    end,
    note = function()
        local f = Wd.Text(body, 12, Wd.BODY_TEXT[1], Wd.BODY_TEXT[2], Wd.BODY_TEXT[3])
        f:SetWordWrap(true)
        return f
    end,
    check = function()
        local w = CreateFrame("Frame", nil, body)
        -- Hover highlight; on the New in page also a panel, border and a NEW tag.
        w.hl = w:CreateTexture(nil, "BACKGROUND", nil, 2)
        w.hl:SetAllPoints()
        w.hl:SetColorTexture(1, 1, 1, 0.04)
        w.hl:Hide()
        w.panel = w:CreateTexture(nil, "BACKGROUND", nil, 1)
        w.panel:SetAllPoints()
        w.panel:SetColorTexture(1, 1, 1, 0.035)
        w.edges = ns.SkinEdges(w, "BORDER", 0, 1, 0, 1, 1, 1, 0.07)
        w.tag = Wd.Text(w, 10, GOLD.r, GOLD.g, GOLD.b)
        -- An on/off switch, as in the options window; clicking it clicks w.clickId.
        w.check = Wd.Switch(w, function() if w.onToggle then w.onToggle() end end)
        w.check.SetChecked = w.check.SetOn
        w.check.GetChecked = function(self) return self.on end
        w.text = Wd.Text(w, 13, 0.93, 0.93, 0.93)
        w.text:SetPoint("TOPLEFT", w.check, "TOPRIGHT", 10, -3)
        w.desc = Wd.Text(w, 11, 0.62, 0.6, 0.6)
        w.desc:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -3)
        w.show = Wd.Button(w, 58, 22, "")
        w.show:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)
        return w
    end,
    footer = function()
        local b = Wd.Button(frame, 110, 28, "")
        b.Disable = function(self) self:SetEnabled(false) end
        b.Enable = function(self) self:SetEnabled(true) end
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
    if mode == "wizard" then frame.steps:Show(); DrawSteps(step) else frame.steps:Hide() end
    local y = { 0, 0 }
    -- Cards flow left to right in rows; cardX / rowH track the row being filled per column.
    local cardX, rowH = { 0, 0 }, { 0, 0 }
    local function EndCardRow(c)
        if cardX[c] > 0 then y[c] = y[c] + rowH[c] + CARD_GAP; cardX[c], rowH[c] = 0, 0 end
    end
    for _, item in ipairs(items) do
        local c = item.col or 1
        local x, width = COL_X[c], (item.wide or item.kind == "note") and FULL_W or COL_W
        local isCard = item.kind == "choice"
        if not isCard then EndCardRow(c) end
        if item.kind == "header" then
            local f = Acquire("header")
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", body, "TOPLEFT", x, -(y[c] + 4))
            f:SetWidth(COL_W)
            f:SetLabel(item.text)
            y[c] = y[c] + 30
        elseif item.kind == "button" then
            local b = Acquire("button")
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", body, "TOPLEFT", x + 2, -(y[c] + 2))
            b:SetText(item.text)
            b.onClick = function() Click(item.id) end
            y[c] = y[c] + 32
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
            local panel = item.wide -- the New in page: each item on its own little panel
            local h = panel and 46 or ROW_H
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y[c])
            w:SetSize(width, h)
            w.panel:SetShown(panel)
            for _, e in pairs(w.edges) do e:SetShown(panel) end
            w.check:ClearAllPoints()
            w.check:SetPoint("TOPLEFT", w, "TOPLEFT", panel and 10 or 2, panel and -8 or -1)
            w.check:SetChecked(item.on)
            w.onToggle = function() Click(item.id) end
            w.check:SetShown(not item.info)
            w.text:SetText(item.text)
            w.text:SetTextColor(item.on and 1 or 0.6, item.on and 1 or 0.6, item.on and 1 or 0.62)
            w.desc:SetText(panel and item.desc or "")
            w.desc:SetWidth(width - 140)
            if panel then -- tall enough for a description that wraps
                local dh = w.desc.GetStringHeight and w.desc:GetStringHeight()
                if type(dh) == "number" and dh > 0 then h = math.max(h, 30 + dh) w:SetHeight(h) end
            end
            w.tag:ClearAllPoints()
            w.tag:SetPoint("RIGHT", w.show, "LEFT", -10, 0)
            w.tag:SetText(panel and item.since and ("NEW  " .. item.since) or "")
            if not item.info then Tooltip(w.check, item.text, item.desc, w.hl) end
            w.show:ClearAllPoints()
            w.show:SetPoint("RIGHT", w, "RIGHT", panel and -8 or 0, panel and 0 or 0)
            if item.showId then
                w.show:SetText(item.showOn and "Hide" or "Show")
                w.show.onClick = function() Click(item.showId) end
                Tooltip(w.show, item.text, item.showOn and "Take it off the screen again."
                    or "Put it on screen with sample content. You can drag it into place.", w.hl)
                w.show:Show()
            else
                w.show:Hide()
            end
            y[c] = y[c] + h + (panel and 6 or 0)
        elseif isCard then
            -- Picture cards (Look) two to a column; text cards (Placement) three across.
            local art = ART[item.id]
            local cw, ch = art and CARD_W or TEXT_CARD_W, art and CARD_H or TEXT_CARD_H
            local room = art and COL_W or FULL_W
            if cardX[c] > 0 and cardX[c] + cw > room then EndCardRow(c) end
            local card = Acquire("card")
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", body, "TOPLEFT", x + cardX[c], -y[c])
            card:SetSize(cw, ch)
            card.picked = item.selected
            card.bg:SetColorTexture(item.selected and 0.15 or 0.10, item.selected and 0.11 or 0.08,
                item.selected and 0.08 or 0.085, 0.95)
            card.glow:SetShown(item.selected)
            card.tick:SetShown(item.selected)
            SetEdges(card.edges, item.selected and GOLD.r or 1, item.selected and GOLD.g or 1,
                item.selected and GOLD.b or 1, item.selected and 0.95 or 0.10)
            card.label:ClearAllPoints()
            if art then card.label:SetPoint("BOTTOM", card, "BOTTOM", 0, 8) else card.label:SetPoint("CENTER") end
            card.label:SetWidth(cw - 12)
            card.label:SetText(item.text)
            card.label:SetTextColor(item.selected and 1 or 0.85, item.selected and 0.86 or 0.85, item.selected and 0.45 or 0.88)
            -- The mini rings, side by side above the label.
            local n = art and #art or 0
            local total = 0
            for i = 1, n do total = total + art[i][2] * 2 end
            total = total + math.max(0, n - 1) * 8
            local mx = -total / 2
            for i = 1, n do
                local m = MiniRing(card, i)
                local r = art[i][2]
                m:ClearAllPoints()
                m:SetPoint("CENTER", card, "TOP", mx + r, -36)
                DrawMini(m, art[i][1], r, item.selected)
                m:Show()
                mx = mx + r * 2 + 8
            end
            for i = n + 1, #card.minis do card.minis[i]:Hide() end
            card:SetScript("OnClick", function() Click(item.id) end)
            cardX[c] = cardX[c] + cw + CARD_GAP
            rowH[c] = math.max(rowH[c], ch)
        end
    end
    EndCardRow(1); EndCardRow(2)
    body:SetHeight(math.max(10, y[1], y[2]))
    local page = mode .. ":" .. tostring(step)
    if scrolledFor ~= page then scrolledFor = page; SetScroll(0) else SetScroll(scroll:GetVerticalScroll()) end
    local right = -12
    for i = #buttons, 1, -1 do
        local spec = buttons[i]
        local b = Acquire("footer")
        b:ClearAllPoints()
        if spec.side == "left" then
            b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 8)
        else
            b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right - 2, 8)
            right = right - 120
        end
        b:SetText(spec.text)
        if spec.enabled == false then b:Disable() else b:Enable() end
        -- The way forward (Next / Finish / Done) in gold, like the options window's Close.
        if spec.id == "next" or spec.id == "done" then
            b:SetAccent()
        else
            b.borderColor = { 0.33, 0.26, 0.24 }
            Wd.SetBorderColor(b.border, 0.33, 0.26, 0.24, 1)
            b.label:SetTextColor(0.92, 0.92, 0.92)
        end
        b.onClick = function() Click(spec.id) end
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
                table.insert(out, pre .. (item.info and " *  " or item.on and "[x] " or "[ ] ") .. item.text
                    .. (item.showId and (item.showOn and "  <Hide>" or "  <Show>") or ""))
            elseif item.kind == "choice" then table.insert(out, pre .. (item.selected and "(*) " or "( ) ") .. item.text)
            elseif item.kind == "button" then table.insert(out, pre .. "[" .. item.text .. "]") end
        end
        local b = {}
        for _, spec in ipairs(buttons) do table.insert(b, spec.enabled == false and ("{" .. spec.text .. "}") or ("[" .. spec.text .. "]")) end
        table.insert(out, "footer: " .. table.concat(b, " "))
        return out
    end,
}
