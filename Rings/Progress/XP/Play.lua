-- Circlet: XP ring: what brings it up: XP events, resting, combat, edit mode, previews and commands.
local _, ns = ...

local IsSecret = ns.IsSecret
local db = ns.db
local XP = ns.XPRing
local xpRing = XP.xpRing
local AlwaysOn = XP.AlwaysOn
local MinimapFrame = XP.MinimapFrame
local RingStrata = XP.RingStrata
local LayoutXPRing = XP.LayoutXPRing
local xpState = XP.xpState
local anim = XP.anim
local combatQueue = XP.combatQueue
local XPFraction = XP.XPFraction
local LiveRestedXP = XP.LiveRestedXP
local RestingShow = XP.RestingShow
local DrawRing = XP.DrawRing
local PlayXPRing = XP.PlayXPRing
local QueueOrPlayXP = XP.QueueOrPlayXP

local function OnXPCombatStart()
    XP.xpInCombat = true
    if db.xpAfterCombat and xpRing:IsShown() then
        -- Fade out whatever was showing (a permanent ring just goes back to idle);
        -- the fight's total comes later.
        anim.holdUntil = 0
    end
end

-- Shows the ring at your current XP with no gain on it: the resting state of the
-- permanent ring. force: reset even if a gain or preview is on screen.
XP.ShowXPIdle = function(force)
    if not ((AlwaysOn() or RestingShow()) and db.xpEnabled) then return end
    if not (xpState.level and xpState.max and xpState.max > 0) then return end -- max level / no data
    if not force and xpRing:IsShown() and (anim.session > 0 or anim.preview or anim.restGain) then return end

    local v = xpState.level + XPFraction(xpState.cur, xpState.max)
    LayoutXPRing()
    anim.preview = false
    anim.restGain = nil
    anim.session, anim.gainShown, anim.gainFrom = 0, 0, 0
    anim.from, anim.to, anim.shown, anim.t = v, v, v, anim.dur
    anim.sessionFrom, anim.restRunout, anim.holdUntil = v, nil, 0
    xpRing:Show()
    DrawRing(v)
end

-- Shows the rested XP gained while resting: the ring at your current XP with the
-- rested band growing from fromRest to toRest (XP, against a level of max).
local REST_GAIN_TIME = 1.8
local function PlayRestedGain(fromRest, toRest, max, preview)
    if not (db.xpEnabled or preview) then return end
    if not (xpState.level and xpState.max and xpState.max > 0) then return end
    local v = xpState.level + XPFraction(xpState.cur, xpState.max)
    LayoutXPRing()
    anim.preview = preview and true or false
    anim.session, anim.gainShown, anim.gainFrom = 0, 0, 0
    anim.from, anim.to, anim.shown, anim.t = v, v, v, anim.dur
    anim.sessionFrom, anim.restRunout = v, nil
    anim.restGain = { from = fromRest, to = toRest, max = max, shown = fromRest, t = 0, dur = REST_GAIN_TIME }
    anim.holdUntil = GetTime() + REST_GAIN_TIME + (db.xpHold or 3) + 1
    xpRing:SetAlpha(math.max(xpRing:GetAlpha(), 0.01))
    xpRing:Show()
    DrawRing(v)
end

-- Edit mode's sample: alternates a rested gain (blue fill, rested band) and a
-- normal one (purple), so both color states can be judged while settings change.
XP.XPSample = function()
    local level = xpState.level or UnitLevel("player")
    anim.preview, anim.previewMax = true, 1000
    anim.previewRested = XP.xpSampleRested and 250 or 0
    anim.session = 0 -- a fresh gain without hiding the ring
    PlayXPRing(level + 0.40, level + 0.62, 1240, XP.xpSampleRested and 600 or nil, 1000, true)
    XP.xpSampleAt = GetTime() + 3.5
    XP.xpSampleRested = not XP.xpSampleRested
end

local function SetXPEditing(on)
    XP.xpEditing = on and true or false
    xpRing.isEditing = XP.xpEditing
    xpRing:EnableMouse(XP.xpEditing)
    xpRing.editHint:SetShown(XP.xpEditing)
    xpRing:SetFrameStrata(RingStrata(MinimapFrame()))
    if XP.xpEditing then
        XP.xpSampleRested = true
        LayoutXPRing()
        XP.XPSample()
        return
    end
    anim.preview = false
    anim.holdUntil = 0
    anim.session = 0 -- don't add the sample's numbers onto real XP
    if combatQueue.gain > 0 and not XP.xpInCombat then
        -- XP that came in while editing.
        PlayXPRing(combatQueue.from, combatQueue.to, combatQueue.gain, combatQueue.rest, combatQueue.max)
        combatQueue.from, combatQueue.to, combatQueue.gain = nil, nil, 0
        combatQueue.rest, combatQueue.max = nil, nil
    else
        XP.ShowXPIdle(true) -- a permanent ring goes back to your real XP
    end
end

-- The "Always show" checkbox: show the ring now, or let an idle one fade away.
-- Entering or leaving an inn or city (PLAYER_UPDATE_RESTING), or the option changing.
-- Rested XP when this character entered the current rest area, kept in saved
-- variables so rested XP built up while logged out at an inn counts too.
local function RestKey()
    local name, realm = UnitName("player"), GetRealmName and GetRealmName() or ""
    if IsSecret(name) then return nil end
    return (name or "?") .. "-" .. (realm or "")
end

local function OnRestingChanged()
    local key = RestKey()
    local resting = IsResting and IsResting()
    if key and db.restBase then
        if resting then
            if not db.restBase[key] then db.restBase[key] = LiveRestedXP() end
        elseif db.restBase[key] then
            -- Left the rest area: show what was gained there.
            local base = db.restBase[key]
            db.restBase[key] = nil
            local now, max = LiveRestedXP(), xpState.max or 0
            if db.xpRestedGain and max > 0 and now - base >= max * 0.01 and not XP.xpEditing then
                PlayRestedGain(base, now, max)
                return
            end
        end
    end
    if RestingShow() then
        XP.ShowXPIdle()
    elseif not AlwaysOn() and xpRing:IsShown() and anim.session == 0 and not anim.restGain then
        anim.holdUntil = 0 -- fade out
    end
end

local function PreviewRestedGain()
    local max = xpState.max or 1000
    PlayRestedGain(max * 0.15, max * 0.6, max, true)
end
ns.PreviewRestedGain = PreviewRestedGain
ns.OnRestingChanged = OnRestingChanged

local function OnXPAlwaysChanged()
    if AlwaysOn() then
        XP.ShowXPIdle()
    elseif xpRing:IsShown() and anim.session == 0 then
        anim.holdUntil = 0 -- normal fade-out rules take over
    end
end

local function OnXPCombatEnd()
    -- XP for the final kill can land a moment after combat ends, so keep queueing
    -- briefly and then show the whole fight's total at once.
    C_Timer.After(0.4, function()
        if InCombatLockdown() then return end -- already in the next fight; keep queueing
        XP.xpInCombat = false
        if combatQueue.gain > 0 then
            PlayXPRing(combatQueue.from, combatQueue.to, combatQueue.gain, combatQueue.rest, combatQueue.max)
        else
            XP.ShowXPIdle() -- back to the resting / permanent ring
        end
        combatQueue.from, combatQueue.to, combatQueue.gain = nil, nil, 0
        combatQueue.rest, combatQueue.max = nil, nil
    end)
end

-- Rested XP grows while you sit in an inn; keep the "before" value fresh between gains.
-- Skipped during combat so a kill's rested use isn't counted before its XP arrives.
local function OnRestedChanged()
    if not XP.xpInCombat then
        xpState.rest = LiveRestedXP()
    end
end

local function OnXPUpdate()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local level = UnitLevel("player")
    if IsSecret(cur) or IsSecret(max) or IsSecret(level) then return end

    -- Never go backwards: UnitLevel can lag behind a level-up for a moment.
    level = math.max(level, xpState.pendingLevel or 0, xpState.level or 0)
    xpState.pendingLevel = nil

    if xpState.level == nil then -- first reading is just the baseline
        xpState.level, xpState.cur, xpState.max = level, cur, max
        xpState.rest = LiveRestedXP()
        return
    end

    -- XP went down on the same level: a level-up the API hasn't reported yet.
    if level == xpState.level and cur < xpState.cur then
        level = xpState.level + 1
    end

    local gain
    if level > xpState.level then
        gain = (xpState.max - xpState.cur) + cur
    else
        gain = cur - xpState.cur
    end

    local fromValue = xpState.level + XPFraction(xpState.cur, xpState.max)
    local toValue = level + XPFraction(cur, max)
    local restBefore, maxBefore = xpState.rest, xpState.max
    xpState.level, xpState.cur, xpState.max = level, cur, max
    xpState.rest = LiveRestedXP()

    if gain > 0 then
        QueueOrPlayXP(fromValue, toValue, gain, restBefore, maxBefore)
        if ns.SessionAdd then
            ns.SessionAdd("xp", nil, gain)
            ns.SessionAdd("levels", nil, math.floor(toValue + 1e-9) - math.floor(fromValue + 1e-9))
        end
    end
end

-- Just the level-up moment, with whichever effect style is selected ("Off" shows
-- the level-up with no effect, exactly as it would happen in game).
local function PreviewLevelUp()
    local level = xpState.level or UnitLevel("player")
    xpRing:Hide()
    anim.session = 0
    anim.preview, anim.previewMax, anim.previewRested = true, 1000, 0
    PlayXPRing(level + 0.80, level + 1.15, 3500, nil, nil, true)
end

-- Walks through every state: rested with a band ahead, rested running out partway
-- (blue then purple), then a level-up while normal.
local function PreviewXPRing()
    local level = xpState.level or UnitLevel("player")
    xpRing:Hide()
    anim.session = 0
    anim.preview, anim.previewMax = true, 1000

    anim.previewRested = 150 -- 15% of a level left after this gain
    PlayXPRing(level + 0.40, level + 0.55, 980, 300, 1000, true) -- rested runs out at .70

    C_Timer.After(1.6, function()
        anim.previewRested = 0
        PlayXPRing(level + 0.55, level + 0.85, 1960, nil, nil, true) -- crosses .70: blue, then purple
    end)
    C_Timer.After(3.4, function()
        PlayXPRing(level + 0.85, level + 1.12, 2650, nil, nil, true) -- level-up, all purple
    end)
end

-- Events: XP, levels, rest state and combat.
ns.Listen({ "PLAYER_XP_UPDATE:player", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING",
            "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }, function(event, arg1)
    if event == "PLAYER_XP_UPDATE" then
        OnXPUpdate()
    elseif event == "PLAYER_LEVEL_UP" then
        -- UnitLevel can lag a moment behind this event; remember the new level.
        xpState.pendingLevel = tonumber(arg1)
    elseif event == "UPDATE_EXHAUSTION" or event == "PLAYER_UPDATE_RESTING" then
        OnRestedChanged()
        if event == "PLAYER_UPDATE_RESTING" then OnRestingChanged() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnXPCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnXPCombatEnd()
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnXPUpdate() -- baseline (or catch up after a loading screen)
        XP.ShowXPIdle()  -- permanent XP ring, if turned on
        if IsResting and IsResting() then OnRestingChanged() end -- rested baseline if logging in at an inn
    end
end)

-- /circ showxp: brings the ring up for a few seconds at your current XP (with its text, even
-- on an always-on ring whose text has faded), whether or not it would show on its own, and
-- prints the numbers to chat.
local SHOW_NOW = 4 -- seconds it stays before fading (plus the hold setting)
local function ShowXPNow()
    if not (xpState.level and xpState.max and xpState.max > 0) then
        ns.Print("No XP to show (max level, or the game hasn't said yet).")
        return
    end
    local v = xpState.level + XPFraction(xpState.cur, xpState.max)
    LayoutXPRing()
    anim.preview = false
    anim.restGain = nil
    anim.session, anim.gainShown, anim.gainFrom = 0, 0, 0
    anim.from, anim.to, anim.shown, anim.t = v, v, v, anim.dur
    anim.sessionFrom, anim.restRunout = v, nil
    anim.holdUntil = GetTime() + SHOW_NOW + (db.xpHold or 0)
    anim.idleSince = nil -- an always-on ring's faded text comes back
    xpRing:SetAlpha(math.max(xpRing:GetAlpha(), 0.01))
    xpRing:Show()
    DrawRing(v)
    local rested = LiveRestedXP()
    ns.Print(string.format("Level %d: %s / %s XP (%.1f%%), %s to go%s.", xpState.level,
        BreakUpLargeNumbers(xpState.cur), BreakUpLargeNumbers(xpState.max), XPFraction(xpState.cur, xpState.max) * 100,
        BreakUpLargeNumbers(xpState.max - xpState.cur),
        rested > 0 and (", " .. BreakUpLargeNumbers(rested) .. " rested") or ""))
end

ns.RegisterCommand({ "showxp", "myxp" }, ShowXPNow, "show your current XP on the ring for a few seconds")
ns.RegisterCommand({ "levelup" }, PreviewLevelUp, "preview the level-up effect")
ns.RegisterCommand({ "rested" }, PreviewRestedGain, "preview the rested XP gained ring")

-- Shared with the files loaded after this one.
ns.OnRestedChanged = OnRestedChanged
ns.OnXPAlwaysChanged = OnXPAlwaysChanged
ns.OnXPCombatEnd = OnXPCombatEnd
ns.OnXPCombatStart = OnXPCombatStart
ns.OnXPUpdate = OnXPUpdate
ns.PreviewLevelUp = PreviewLevelUp
ns.PreviewXPRing = PreviewXPRing
ns.SetXPEditing = SetXPEditing
ns.ShowXPIdle = XP.ShowXPIdle
ns.IsXPEditing = function() return XP.xpEditing end -- live value, not a copy
ns.xpState = xpState

-- For the files loaded after this one.
XP.SetXPEditing = SetXPEditing
XP.OnXPAlwaysChanged = OnXPAlwaysChanged
XP.PreviewLevelUp = PreviewLevelUp
XP.PreviewXPRing = PreviewXPRing
