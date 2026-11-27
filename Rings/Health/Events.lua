-- Circlet: Health rings: the game events they follow, their previews, and the debug commands.
local _, ns = ...

local db, SafeCall, Clean, IsSecret = ns.db, ns.SafeCall, ns.Clean, ns.IsSecret
local H = ns.HealthRings
local CheckScale = H.CheckScale
local CurvesWork = H.CurvesWork
local InCombat = H.InCombat
local bigHitAt = H.bigHitAt
local tracks = H.tracks
local ResetTrack = H.ResetTrack
local Step = H.Step
local HALF_PLANE = H.HALF_PLANE
local easeNow = H.easeNow
local changes = H.changes
local UNIT_KEY = H.UNIT_KEY
local portraitDirty = H.portraitDirty
local floats = H.floats
local AddFloat = H.AddFloat
local playerRing = H.playerRing
local targetRing = H.targetRing
local totRing = H.totRing
local petRing = H.petRing

ns.Listen({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UNIT_MAXHEALTH:player" }, CheckScale)

-- Portraits: a new target, or a portrait that changed (gear, shapeshift, a model loading in).
-- Hidden changes: the game says a value changed (not how): the eased bars take the new value.
ns.Listen({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }, function(_, unit)
    local key = UNIT_KEY[unit]
    if key then changes[key .. ":hp"] = GetTime() end
end)
ns.Listen({ "UNIT_POWER_UPDATE" }, function(_, unit)
    local key = UNIT_KEY[unit]
    if key then changes[key .. ":pw"] = GetTime() end
end)
-- A new target: its bands start from its own values, not slide over from the last one's.
-- Critical and crushing hits taken (UNIT_COMBAT: the kind of hit can be read, its size can't):
-- with hidden values, the big hits.
ns.Listen({ "UNIT_COMBAT" }, function(_, unit, action, flag, amount)
    local key = UNIT_KEY[unit]
    if not key then return end
    action, flag = Clean(action), Clean(flag)
    AddFloat(key, action, flag, amount)
    if action == "WOUND" and (flag == "CRITICAL" or flag == "CRUSHING") then
        local tr = tracks[key .. ":hp"]
        if not tr or tr.hidden then bigHitAt[key] = GetTime() end -- readable: sized by the loss
    end
end)

local function FreshStart(key)
    floats[key] = nil -- the last target's numbers go with it
    ResetTrack(key .. ":hp")
    ResetTrack(key .. ":pw")
    easeNow[key .. ":hp"], easeNow[key .. ":pw"] = true, true
    portraitDirty[key] = true
end
ns.Listen({ "PLAYER_TARGET_CHANGED" }, function()
    FreshStart("targetHp")
    FreshStart("totHp")
end)
ns.Listen({ "UNIT_TARGET" }, function(_, unit)
    if unit == "target" then FreshStart("totHp") end
end)
-- A pet summoned, dismissed or swapped: its ring starts afresh.
ns.Listen({ "UNIT_PET" }, function(_, unit)
    if unit == "player" then FreshStart("petHp") end
end)

ns.Listen({ "PLAYER_TARGET_CHANGED", "UNIT_PORTRAIT_UPDATE", "PLAYER_ENTERING_WORLD" }, function(event, unit)
    if event == "UNIT_PORTRAIT_UPDATE" then
        if unit == "player" then
            portraitDirty.playerHp = true
        elseif unit == "target" then
            portraitDirty.targetHp = true
        elseif unit == "pet" then
            portraitDirty.petHp = true
        end
    else
        portraitDirty.targetHp = true
        if event == "PLAYER_ENTERING_WORLD" then
            portraitDirty.playerHp = true
            portraitDirty.petHp = true
        end
    end
end)

ns.PreviewPlayerHpRing = function() playerRing.Preview(12) end
ns.PreviewTotHpRing = function() totRing.Preview(12) end
ns.PreviewPetHpRing = function() petRing.Preview(12) end

-- /circ masktest: how this client applies masks (which way SetRotation turns them, what the
-- corner texture coordinates do), as white squares masked by Textures/HalfPlane, each labelled
-- with what it should show if the eased bands' assumptions hold. Click to close.
local maskTest
ns.RegisterCommand({ "masktest" }, function()
    if maskTest then
        maskTest:SetShown(not maskTest:IsShown())
        return
    end
    local W = 110
    local f = CreateFrame("Button", "CircletMaskTest", UIParent)
    f:SetSize(W * 4 + 40, W * 2 + 90)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.12, 0.95)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Circlet mask test (click to close). Expected result under each square.")
    f:SetScript("OnClick", function(self) self:Hide() end)
    local cases = {
        { "plain mask", "left half white", nil },
        { "SetRotation(+90)", "bottom half (if counter-clockwise)", function(m) m:SetRotation(math.pi / 2) end },
        { "SetRotation(-90)", "top half (if counter-clockwise)", function(m) m:SetRotation(-math.pi / 2) end },
        { "SetRotation(+45)", "lower-left half", function(m) m:SetRotation(math.pi / 4) end },
        { "texcoords mirrored", "right half white", function(m) m:SetTexCoord(1, 0, 1, 1, 0, 0, 0, 1) end },
        { "texcoords: u up", "bottom half white", function(m) m:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0) end },
        { "texcoords: half size", "left 3/4 white", function(m) m:SetTexCoord(0.25, 0, 0.25, 1, 0.75, 0, 0.75, 1) end },
        { "no mask", "all white", false },
    }
    for i, c in ipairs(cases) do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local x, y = 20 + col * W, -30 - row * (W + 30)
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetSize(W - 20, W - 20)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        t:SetColorTexture(1, 1, 1, 1)
        local edge = f:CreateTexture(nil, "BORDER")
        edge:SetPoint("TOPLEFT", t, "TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 1, -1)
        edge:SetColorTexture(0.5, 0.2, 0.2, 1)
        if c[3] ~= false then
            local m = f:CreateMaskTexture()
            m:SetTexture(HALF_PLANE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(t)
            if c[3] then
                local ok, err = pcall(c[3], m)
                if not ok then c[2] = "ERROR: " .. tostring(err) end
            end
            t:AddMaskTexture(m)
        end
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOP", t, "BOTTOM", 0, -3)
        label:SetWidth(W - 4)
        label:SetText(i .. ". " .. c[1] .. "\n|cffaaaaaa" .. c[2] .. "|r")
    end
    maskTest = f
end, "show how this client applies masks (for bug reports)")

-- /circ hpdebug: what the health rings can see right now (readable or hidden values, which
-- functions this client has, the animation's state), printed and kept in CircletDB.vitalsDebug.
local function Describe(v)
    if v == nil then return "nil" end
    if IsSecret(v) then return "HIDDEN" end
    return tostring(v)
end
ns.RegisterCommand({ "hpdebug" }, function()
    local out = {
        at = date and date("%Y-%m-%d %H:%M:%S") or "?",
        combat = InCombat() and true or false,
        hasHealthPercent = type(UnitHealthPercent) == "function",
        hasCurves = CurvesWork() and true or false,
        hasScaleTo100 = (CurveConstants and CurveConstants.ScaleTo100) and true or false,
        issecretvalue = issecretvalue ~= nil,
        percentScale = H.percentScale,
    }
    for unit, key in pairs({ player = "playerHp", target = "targetHp", targettarget = "totHp", pet = "petHp" }) do
        if Clean(SafeCall(UnitExists, unit)) then
            local tr = tracks[key .. ":hp"] or {}
            local u = {
                health = Describe(SafeCall(UnitHealth, unit)),
                max = Describe(SafeCall(UnitHealthMax, unit)),
                power = Describe(SafeCall(UnitPower, unit)),
                powerMax = Describe(SafeCall(UnitPowerMax, unit)),
                healthPercent = type(UnitHealthPercent) == "function" and Describe(SafeCall(UnitHealthPercent, unit))
                    or "-",
                smooth = tostring(db[key .. "Smooth"]),
                shown = tostring(tr.shown),
                target = tostring(tr.target),
                hiddenPath = tostring(tr.hidden),
                easing = tostring(tr.animAt ~= nil),
            }
            out[unit] = u
            ns.Print(
                string.format(
                    "%s: health %s / %s, power %s / %s, percent %s | smooth=%s shown=%s hidden path=%s",
                    unit,
                    u.health,
                    u.max,
                    u.power,
                    u.powerMax,
                    u.healthPercent,
                    u.smooth,
                    u.shown,
                    u.hiddenPath
                )
            )
        end
    end
    ns.Print(
        string.format(
            "in combat %s, UnitHealthPercent %s, curves %s, ScaleTo100 %s, issecretvalue %s",
            tostring(out.combat),
            tostring(out.hasHealthPercent),
            tostring(out.hasCurves),
            tostring(out.hasScaleTo100),
            tostring(out.issecretvalue)
        )
    )
    -- Can a status bar ease to a hidden value on its own (the game doing the in-betweens)?
    local interp = Enum and Enum.StatusBarInterpolation
    local bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetSize(10, 10)
    bar:Hide()
    local okRange = pcall(bar.SetMinMaxValues, bar, 0, 1)
    local hp = SafeCall(UnitHealthPercent, "player")
    local okPlain = pcall(bar.SetValue, bar, hp)
    local okEase, easeErr = false, "no Enum.StatusBarInterpolation"
    if interp then
        local mode = interp.ExponentialEaseOut or interp.Linear
        okEase, easeErr = pcall(bar.SetValue, bar, hp, mode)
    end
    out.statusBar = {
        interpolation = interp and table.concat(
            (function()
                local t = {}
                for k, v in pairs(interp) do
                    t[#t + 1] = k .. "=" .. tostring(v)
                end
                return t
            end)(),
            ","
        ) or "none",
        setRange = okRange,
        setHiddenValue = okPlain,
        easeHiddenValue = okEase,
        easeError = not okEase and tostring(easeErr) or nil,
        hasGetInterpolated = type(bar.GetInterpolatedValue) == "function",
        hasMask = type(bar.GetStatusBarTexture) == "function" and bar:GetStatusBarTexture() ~= nil,
    }
    ns.Print(
        string.format(
            "status bar: hidden value %s, eased hidden value %s (modes: %s)%s",
            tostring(okPlain),
            tostring(okEase),
            out.statusBar.interpolation,
            okEase and "" or (" - " .. tostring(easeErr))
        )
    )
    db.vitalsDebug = out
end, "what the health rings can see (for bug reports)")
ns.PreviewTargetHpRing = function() targetRing.Preview(12) end

-- /circ curvetest: shows on screen (hidden values can be shown, just not read) what your
-- health percentage comes out as raw, through the game's 0-100 curve, and through Circlet's
-- own step curves both ways round, so it's plain which way this client runs them.
ns.RegisterCommand({ "curvetest" }, function()
    local f = ns.curveTestFrame
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(420, 170)
        f:SetPoint("CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.8)
        f.lines = {}
        for i = 1, 7 do
            local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            fs:SetPoint("TOPLEFT", 12, -10 - (i - 1) * 21)
            fs:SetJustifyH("LEFT")
            f.lines[i] = fs
        end
        ns.curveTestFrame = f
    end
    local function Step(points)
        local cv = C_CurveUtil.CreateCurve()
        if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then pcall(cv.SetType, cv, Enum.LuaCurveType.Step) end
        for _, p in ipairs(points) do
            cv:AddPoint(p[1], p[2])
        end
        return cv
    end
    local tests = {
        { "raw (no curve)", function() return UnitHealthPercent("player") end },
        { "game 0-100 curve", function() return UnitHealthPercent("player", false, CurveConstants.ScaleTo100) end },
        {
            "up: 0 then 1 from 0.3",
            function() return UnitHealthPercent("player", false, Step({ { 0, 0 }, { 0.3, 1 } })) end,
        },
        {
            "down: 1 then 0 from 0.3",
            function() return UnitHealthPercent("player", false, Step({ { 0, 1 }, { 0.3, 0 } })) end,
        },
        {
            "up, 0-100: from 30",
            function() return UnitHealthPercent("player", false, Step({ { 0, 0 }, { 30, 1 } })) end,
        },
        { "curve as 2nd arg, down", function() return UnitHealthPercent("player", Step({ { 0, 1 }, { 0.3, 0 } })) end },
    }
    f.lines[1]:SetText("Circlet curve test (full health: you'd expect up = 1, down = 0)")
    for i, t in ipairs(tests) do
        local ok, v = pcall(t[2])
        local fs = f.lines[i + 1]
        if not ok then
            fs:SetText(t[1] .. ": error " .. tostring(v):sub(1, 60))
        elseif not pcall(fs.SetFormattedText, fs, "%s: %s", t[1], v) then
            fs:SetText(t[1] .. ": (can't show)")
        end
    end
    f:Show()
    C_Timer.After(30, function() f:Hide() end)
end, "show how this client runs health curves (for bug reports)")
