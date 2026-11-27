-- Circlet: Setup wizard and New in page: opening, closing and clicking, and when they open on their own.
local _, ns = ...

local db, Print = ns.db, ns.Print
local SU = ns.SetupUI
local STEPS = SU.STEPS
local Shown = SU.Shown
local NewItems = SU.NewItems
local MarkAllSeen = SU.MarkAllSeen
local StopShowing = SU.StopShowing
local Current = SU.Current
local frame = SU.frame

---------------------------------------------------------------- opening, closing, clicking
local function OpenWizard()
    StopShowing()
    SU.mode, SU.step = "wizard", 1
    SU.orig = {}
    for _, def in ipairs(ns.RINGS) do
        SU.orig[def.key] = { style = db[def.key .. "Style"], size = db[def.key .. "Size"] }
    end
    SU.choice = { style = "keep", size = "keep", place = "keep" }
    frame:Show()
    SU.Render()
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
    SU.mode, SU.newItems = "new", items
    frame:Show()
    SU.Render()
    return true
end

frame:SetScript("OnHide", function()
    StopShowing()
    -- Closed one way or another: don't show it again on its own.
    if SU.mode == "wizard" then db.setupDone = true end
    MarkAllSeen()
end)

local function Finish()
    if SU.choice.place == "reset" and ns.ResetPositions then ns.ResetPositions() end
    frame:Hide() -- (closing also ends the Show previews; arranging starts edit mode afresh)
    if SU.choice.place == "arrange" then
        for _, def in ipairs(ns.RINGS) do
            if Shown(def) and db[def.key .. "Enabled"] and def.edit then ns.SetRingEditing(def.key, true, true) end
        end
    end
    Print("Setup done. /circ setup brings the wizard back; /circ options has every setting.")
end

-- Clicks an item or footer button by id (the window's buttons and the tests both use this).
SU.Click = function(id)
    if id == "next" then
        StopShowing()
        if SU.step < STEPS then SU.step = SU.step + 1 else return Finish() end
    elseif id == "back" then
        StopShowing()
        SU.step = math.max(1, SU.step - 1)
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
    SU.Render()
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
    frame = frame, Click = SU.Click, Open = OpenWizard, OpenNew = OpenNew,
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
