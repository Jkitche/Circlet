-- Circlet: Hide the game's own bars that a ring replaces.
local ADDON_NAME, ns = ...

local db = ns.db

---------------------------------------------------------------------------
-- Hide the default bars
---------------------------------------------------------------------------
-- Each ring that has a counterpart in the game's interface can hide it (<key>HideDefault;
-- the option's label is the ring's gameBar in its registration):
--   xp      the XP bar                 rep    the reputation bar
--   craft   the cast bar while crafting  gather the cast bar while gathering
--   breath  the breath / fatigue bars  timed  the quest timer
--   totem   the totem timers under your portrait
--   targetCast  the cast bar under the target frame
--   swing / shot  WoW Forever's own swing timer bars (melee / ranged)
--   playerHp / targetHp / totHp / petHp  the player / target / target of target / pet frames (health & power rings)
-- They're faded out (alpha 0, mouse off) rather than hidden, so the game's own layout and
-- show/hide logic carry on untouched; turning the option off brings them straight back.
-- Frame names cover both the modern and the classic interface; whichever exist are used.

local function G(name) local f = _G[name]; return type(f) == "table" and f.SetAlpha and f or nil end

local hidden = {} -- frame -> true while we're hiding it

local function SetMouse(frame, on)
    if not frame.EnableMouse then return end
    if InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return end
    pcall(frame.EnableMouse, frame, on)
end

local function Suppress(frame, on)
    if not frame then return end
    if on then
        if frame:GetAlpha() ~= 0 then frame:SetAlpha(0) end
        if not hidden[frame] then
            hidden[frame] = true
            frame.circletMouse = frame.IsMouseEnabled and frame:IsMouseEnabled()
            if frame.circletMouse then SetMouse(frame, false) end
        end
    elseif hidden[frame] then
        hidden[frame] = nil
        frame:SetAlpha(1)
        if frame.circletMouse then SetMouse(frame, true) end
    end
end

-- The XP and reputation bars. Classic: their own frames. Modern: the status-tracking
-- containers above the action bars, each showing one bar at a time; a container is
-- faded while the bar it shows is one we hide.
local function BarKind(container)
    local info = _G.StatusTrackingBarInfo
    local enum = info and info.BarsEnum
    local idx = container.shownBarIndex
    if enum and idx then
        if idx == enum.Experience then return "xp" end
        if idx == enum.Reputation then return "rep" end
        return nil
    end
    -- No index to go by: the XP bar is the one with the rested tick.
    for _, ch in ipairs({ container:GetChildren() }) do
        if ch:IsShown() and (ch.ExhaustionTick or ch.ExhaustionLevelFillBar) then return "xp" end
    end
end

local function UpdateTrackingBars()
    Suppress(G("MainMenuExpBar"), db.xpHideDefault)
    Suppress(G("ReputationWatchBar"), db.repHideDefault)
    for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
        local c = G(name)
        if c then
            local kind = BarKind(c)
            Suppress(c, (kind == "xp" and db.xpHideDefault) or (kind == "rep" and db.repHideDefault) or false)
        end
    end
end

-- The player's cast bar, only while a craft or gather is under way. Once that's over it
-- comes back when the bar next hides, so its own fade-out isn't cut short.
local castHiding = false
local function UpdateCastBar()
    local bar = G("PlayerCastingBarFrame") or G("CastingBarFrame")
    if not bar then return end
    -- The cast ring's switch hides it all the time; the crafting and gathering ones only
    -- while those are under way.
    local busy = db.castHideDefault
        or (db.craftHideDefault and ns.CraftActive and ns.CraftActive())
        or (db.gatherHideDefault and ns.GatherActive and ns.GatherActive())
    if busy then
        castHiding = true
        Suppress(bar, true)
    elseif castHiding and (not bar:IsShown() or not (db.craftHideDefault or db.gatherHideDefault)
            or not db.castHideDefault and not (ns.CraftActive and ns.CraftActive()) and not (ns.GatherActive and ns.GatherActive())) then
        castHiding = false
        Suppress(bar, false)
    end
end

local function UpdateOthers()
    local breath = db.breathHideDefault and true or false
    Suppress(G("MirrorTimerContainer"), breath)
    for i = 1, 3 do Suppress(G("MirrorTimer" .. i), breath) end
    Suppress(G("QuestTimerFrame"), db.timedHideDefault and true or false)
    Suppress(G("TotemFrame"), db.totemHideDefault and true or false)
    Suppress(G("TargetFrameSpellBar"), db.targetCastHideDefault and true or false)
    -- The health & power rings: the game's player and target frames.
    Suppress(G("PlayerFrame"), db.playerHpHideDefault and true or false)
    Suppress(G("TargetFrame"), db.targetHpHideDefault and true or false)
    Suppress(G("TargetFrameToT"), db.totHpHideDefault and true or false)
    Suppress(G("PetFrame"), db.petHpHideDefault and true or false)
end

-- WoW Forever's own swing timer bars (its showSwingTimer option). Their frames aren't
-- documented, so they're found by name: any named frame with "swing" in it (not ours),
-- ranged when the name also says ranged, range, shot or auto, melee otherwise. Looked for
-- again every few seconds while a hide option is on and none has turned up (the bars can be
-- made late). If none can be found, turning either option on switches the game's swing
-- timer off instead (both bars), and turning both off puts it back as it was.
local swingBars = { swing = {}, shot = {} }
local lastScan, scans = -100, 0
local CVAR = "showSwingTimer"

local function GetCVarValue(name)
    local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
    return get and select(2, pcall(get, name)) or nil
end
local function SetCVarValue(name, v)
    local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
    return set and pcall(set, name, v)
end

local function ScanSwingBars()
    if not EnumerateFrames then return end
    swingBars.swing, swingBars.shot = {}, {}
    local f = EnumerateFrames()
    while f do
        local ok, name = pcall(f.GetName, f)
        if ok and type(name) == "string" and not name:find("^Circlet") then
            local low = name:lower()
            if low:find("swing") then
                local kind = (low:find("ranged") or low:find("range") or low:find("shot") or low:find("auto"))
                    and "shot" or "swing"
                if f.SetAlpha then table.insert(swingBars[kind], f) end
            end
        end
        f = EnumerateFrames(f)
    end
end

local function UpdateSwingBars()
    local hideSwing, hideShot = db.swingHideDefault and true or false, db.shotHideDefault and true or false
    local now = GetTime()
    if (hideSwing or hideShot) and #swingBars.swing + #swingBars.shot == 0 and now - lastScan > 5 then
        lastScan, scans = now, scans + 1
        ScanSwingBars()
    end
    for _, f in ipairs(swingBars.swing) do Suppress(f, hideSwing) end
    for _, f in ipairs(swingBars.shot) do Suppress(f, hideShot) end
    -- No frames found: the game's own switch, put back when both options are off.
    if InCombatLockdown and InCombatLockdown() then return end
    local found = #swingBars.swing + #swingBars.shot > 0
    if (hideSwing or hideShot) and not found and scans >= 2 then
        local cur = GetCVarValue(CVAR)
        if cur ~= nil and cur ~= "0" then
            CircletDB.swingTimerCVarWas = cur
            SetCVarValue(CVAR, "0")
        end
    elseif not (hideSwing and not found or hideShot and not found) and CircletDB.swingTimerCVarWas then
        SetCVarValue(CVAR, CircletDB.swingTimerCVarWas)
        CircletDB.swingTimerCVarWas = nil
    end
end

-- /circ swingbars: what was found.
ns.RegisterCommand({ "swingbars" }, function()
    ScanSwingBars()
    local function Names(list)
        local t = {}
        for _, f in ipairs(list) do t[#t + 1] = select(2, pcall(f.GetName, f)) or "?" end
        return #t > 0 and table.concat(t, ", ") or "none"
    end
    ns.Print("Game swing timer bars: melee " .. Names(swingBars.swing) .. "; ranged " .. Names(swingBars.shot)
        .. "; " .. CVAR .. " = " .. tostring(GetCVarValue(CVAR))
        .. (CircletDB.swingTimerCVarWas and (" (Circlet turned it off; was " .. CircletDB.swingTimerCVarWas .. ")") or ""))
end)

local ticker = CreateFrame("Frame")
ticker.t = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.t < 0.1 or not CircletDB then return end
    self.t = 0
    UpdateTrackingBars()
    UpdateCastBar()
    UpdateOthers()
    UpdateSwingBars()
end)
