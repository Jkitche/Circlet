-- Circlet: XP ring: drawing it each frame, and playing a gain (held back during combat).
local _, ns = ...

local db = ns.db
local XP = ns.XPRing
local STATE_COLORS = XP.STATE_COLORS
local GOLD = XP.GOLD
local xpRing = XP.xpRing
local XP_TEXTS = XP.XP_TEXTS
local AlwaysOn = XP.AlwaysOn
local ring = XP.ring
local DrawArc = XP.DrawArc
local MinimapFrame = XP.MinimapFrame
local XPSize = XP.XPSize
local LayoutXPRing = XP.LayoutXPRing
local anim = XP.anim
local combatQueue = XP.combatQueue
local RestedNow = XP.RestedNow
local PlayLevelUpEffect = XP.PlayLevelUpEffect
local DrawGainFx = XP.DrawGainFx
local UpdateRestIcon = XP.UpdateRestIcon
local RestingShow = XP.RestingShow
local RestedFullIn = XP.RestedFullIn

local function DrawRing(value)
    LayoutXPRing() -- cheap unless a setting changed; keeps the toggle live while the ring is up
    local level = math.floor(value + 1e-9)
    local frac = value - level
    local rested, max = RestedNow()
    local isRested = rested > 0

    -- How much of this level's fill is blue (rested) vs purple (normal).
    local blueTo = 0
    if isRested then
        blueTo = frac -- still rested: the whole fill is blue, like Blizzard's bar
    elseif anim.restRunout then
        local ru = anim.restRunout
        if ru >= value then
            blueTo = frac
        elseif math.floor(ru + 1e-9) == level then
            blueTo = ru - level -- ran out partway through this level
        end -- ran out in an earlier level: all purple
    end
    -- Solid fill: reset the segments' color (a gradient colors each one).
    local shadeR, shadeN = ns.Shade("xp", STATE_COLORS.rested), ns.Shade("xp", STATE_COLORS.normal)
    if not shadeR then
        local c = STATE_COLORS.rested
        for _, l in ipairs(xpRing.fillRested) do l:SetColorTexture(c.r, c.g, c.b, 1) end
        c = STATE_COLORS.normal
        for _, l in ipairs(xpRing.fillNormal) do l:SetColorTexture(c.r, c.g, c.b, 1) end
    end
    DrawArc(xpRing.fillRested, 0, blueTo, nil, nil, nil, shadeR)
    DrawArc(xpRing.fillNormal, blueTo, frac, nil, nil, nil, shadeN)

    -- Rested band: from the fill to where rested runs out (fixed at the final XP
    -- position, so the fill grows into it). Only on the level you'll end on.
    local finalLevel = math.floor(anim.to + 1e-9)
    if isRested and max > 0 and level == finalLevel then
        local bandEnd = math.min(1, (anim.to - finalLevel) + rested / max)
        DrawArc(xpRing.restBand, frac, bandEnd)
    else
        DrawArc(xpRing.restBand, 0, 0)
    end

    local stateColor = isRested and STATE_COLORS.rested or STATE_COLORS.normal
    -- The color at the end of the fill (for the gain effect).
    xpRing.tipColor = (blueTo > 0 and frac <= blueTo + 1e-6) and STATE_COLORS.rested or STATE_COLORS.normal

    if GetTime() < anim.flashUntil then
        xpRing.levelText:SetText("LEVEL UP!")
        xpRing.levelText:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
    else
        xpRing.levelText:SetText("Level " .. level)
        xpRing.levelText:SetTextColor(0.85, 0.85, 0.85)
    end

    local idle = anim.session == 0 -- permanent ring with no recent gain
    local resting = idle and not anim.preview and RestingShow()
    local rg = anim.restGain
    if rg then
        -- Leaving a rest area: the rested XP gained there, counting up as the band grows.
        local rc = STATE_COLORS.rested
        xpRing.gainText:SetText("+" .. BreakUpLargeNumbers(math.floor(rg.shown - rg.from + 0.5)) .. " rested")
        xpRing.gainText:SetTextColor(rc.r, rc.g, rc.b)
        xpRing.deltaText:SetText(string.format("+%.0f%% of a level", (rg.shown - rg.from) / rg.max * 100))
        xpRing.deltaText:SetTextColor(0.8, 0.8, 0.8)
    elseif resting then
        -- At an inn: show rested XP building up instead of a gain.
        local rc = STATE_COLORS.rested
        xpRing.gainText:SetText("Resting")
        xpRing.gainText:SetTextColor(rc.r, rc.g, rc.b)
        xpRing.deltaText:SetText(max > 0 and (RestedFullIn(rested, max) or "Fully rested") or "")
        xpRing.deltaText:SetTextColor(0.8, 0.8, 0.8)
    else
        xpRing.gainText:SetText(idle and "" or ("+" .. BreakUpLargeNumbers(math.floor(anim.gainShown + 0.5)) .. " XP"))
        xpRing.gainText:SetTextColor(1, 1, 1)

        -- Share of a level gained since the ring appeared; exact across level-ups because
        -- it's measured in level units.
        local delta = (value - anim.sessionFrom) * 100
        xpRing.deltaText:SetText((db.xpShowDelta and not idle) and string.format("+%.1f%%", math.max(0, delta)) or "")
        xpRing.deltaText:SetTextColor(stateColor.r, stateColor.g, stateColor.b)
    end

    xpRing.pctText:SetText(string.format("%.1f%%", frac * 100))
    xpRing.pctText:SetTextColor(stateColor.r, stateColor.g, stateColor.b)

    if isRested then
        -- Rested pool as a share of a level (it caps at 150%).
        xpRing.stateText:SetText(string.format("Rested %d%%", math.floor(rested / max * 100 + 0.5)))
    else
        xpRing.stateText:SetText("Normal")
    end
    xpRing.stateText:SetTextColor(stateColor.r, stateColor.g, stateColor.b)
end

xpRing:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()

    local moving, landed = false, false
    if anim.t < anim.dur then
        moving = anim.to ~= anim.from
        anim.t = math.min(anim.dur, anim.t + elapsed)
        landed = moving and anim.t >= anim.dur
        local p = anim.t / anim.dur
        p = 1 - (1 - p) ^ 3 -- ease out
        local v = anim.from + (anim.to - anim.from) * p
        if math.floor(v + 1e-9) > math.floor(anim.shown + 1e-9) then
            anim.flashUntil = now + 1.5 -- crossed into a new level
            PlayLevelUpEffect()
        end
        anim.shown = v
        anim.gainShown = anim.gainFrom + (anim.session - anim.gainFrom) * p -- count up with the fill
    end
    local rg = anim.restGain
    if rg and rg.t < rg.dur then
        rg.t = math.min(rg.dur, rg.t + elapsed)
        local p = 1 - (1 - rg.t / rg.dur) ^ 3 -- ease out
        rg.shown = rg.from + (rg.to - rg.from) * p
    end
    DrawRing(anim.shown)
    DrawGainFx(now, moving and not landed, landed)
    UpdateRestIcon((IsResting and IsResting()) or (XP.xpEditing and XP.xpSampleRested == false), ring.R + ring.T / 2,
        XPSize())

    if XP.xpEditing then
        local a = self:GetAlpha()
        if a < 1 then self:SetAlpha(math.min(1, a + elapsed / 0.2)) end
        anim.idleSince = nil
        for _, t in ipairs(XP_TEXTS) do t:SetAlpha(1) end
        if now >= XP.xpSampleAt then XP.XPSample() end
        return
    end

    -- Around a minimap that's hidden (some UIs hide it), the ring hides too.
    local mmf = MinimapFrame()
    if mmf and not mmf:IsVisible() then
        self:SetAlpha(0)
        return
    end

    -- Always-on ring with "hide text": out in the world, once it's sat idle for the delay,
    -- the text fades out and the ring works as a plain XP bar. Any gain, or the mouse over
    -- the ring, brings the text back. While resting it stays (it shows your rested XP).
    local textTarget = 1
    if now >= anim.holdUntil and AlwaysOn() and db.xpHideText and db.xpEnabled and not RestingShow() then
        anim.idleSince = anim.idleSince or now
        if now - anim.idleSince >= (db.xpHideTextDelay or 3) and not (MouseIsOver and MouseIsOver(self)) then
            textTarget = 0
        end
    else
        anim.idleSince = nil
    end
    local ta = XP_TEXTS[1]:GetAlpha() or 1
    if ta ~= textTarget then
        ta = textTarget > ta and math.min(1, ta + elapsed / 0.25) or math.max(0, ta - elapsed / 0.6)
        for _, t in ipairs(XP_TEXTS) do t:SetAlpha(ta) end
    end

    local a = self:GetAlpha()
    if now < anim.holdUntil then
        if a < 1 then self:SetAlpha(math.min(1, a + elapsed / 0.2)) end
    elseif (AlwaysOn() or RestingShow()) and db.xpEnabled then
        -- Permanent ring (or resting at an inn): stay up, and once the gain has had its time, go back to idle.
        if a < 1 then self:SetAlpha(math.min(1, a + elapsed / 0.2)) end
        if anim.preview or anim.session ~= 0 or anim.restGain then
            XP.ShowXPIdle(true)
        end
    else
        a = a - elapsed / 0.6
        if a <= 0 then
            self:SetAlpha(0)
            self:Hide()
            anim.session = 0
            anim.preview = false
            anim.restGain = nil
            return
        end
        self:SetAlpha(a)
    end
end)

-- restBefore / maxBefore: rested pool and level size just before this gain, used to
-- find where rested ran out. They only matter at the start of a ring session.
local function PlayXPRing(fromValue, toValue, gain, restBefore, maxBefore, force)
    if not db.xpEnabled and not force then return end
    if not force then anim.preview = false end
    if anim.restGain then
        anim.restGain = nil
        anim.session = 0 -- a real gain replaces the rested-gain display
    end
    LayoutXPRing()

    local gainFrom = 0
    if xpRing:IsShown() and anim.session > 0 then
        fromValue = anim.shown     -- keep going from wherever the fill currently is
        gainFrom = anim.gainShown  -- ...and keep counting from the number on screen
    else
        anim.session = 0
        anim.sessionFrom = fromValue
        if restBefore and restBefore > 0 and maxBefore and maxBefore > 0 then
            anim.restRunout = fromValue + restBefore / maxBefore
        else
            anim.restRunout = nil
        end
    end

    anim.session = anim.session + gain
    anim.gainFrom, anim.gainShown = gainFrom, gainFrom
    anim.from, anim.to, anim.shown, anim.t = fromValue, toValue, fromValue, 0

    -- Bigger fills (a whole fight's worth, or a level-up) animate longer so the
    -- count-up is readable; small ones stay snappy.
    anim.dur = math.min(2.5, math.max(0.8, 0.6 + (toValue - fromValue) * 2.5))

    anim.holdUntil = GetTime() + anim.dur + db.xpHold
    xpRing:Show()
    DrawRing(fromValue)
end

local function QueueOrPlayXP(fromValue, toValue, gain, restBefore, maxBefore)
    if (XP.xpInCombat and db.xpAfterCombat) or XP.xpEditing then
        if combatQueue.from == nil then
            combatQueue.from, combatQueue.rest, combatQueue.max = fromValue, restBefore, maxBefore
        end
        combatQueue.to = toValue
        combatQueue.gain = combatQueue.gain + gain
    else
        PlayXPRing(fromValue, toValue, gain, restBefore, maxBefore)
    end
end

-- For the files loaded after this one.
XP.DrawRing = DrawRing
XP.PlayXPRing = PlayXPRing
XP.QueueOrPlayXP = QueueOrPlayXP
