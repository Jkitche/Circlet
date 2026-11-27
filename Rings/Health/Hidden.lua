-- Circlet: Health & power rings for you and your target: health round the band, power in a
-- thinner band inside it.
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall, Clean, CleanNumber, IsSecret =
    ns.db, ns.CreateLiveRing, ns.SafeCall, ns.Clean, ns.CleanNumber, ns.IsSecret
local NewRingLayer, DrawArc, TRACK = ns.NewRingLayer, ns.DrawArc, ns.TRACK

-- Shared by the health rings' files (Rings/Health/*.lua after Fx.lua and Auras.lua), which load
-- in this order: Hidden, Bands, Parts, Draw, Menus, Events, Register.
ns.HealthRings = ns.HealthRings or {}
local H = ns.HealthRings

---------------------------------------------------------------------------
-- Health & power rings (playerHp: you; targetHp: your target; totHp: its target, smaller;
-- petHp: your pet, smaller, for any class with one out)
---------------------------------------------------------------------------
-- The outer band is health, the thinner band inside it power (mana, rage, energy, focus),
-- with the health (and power) as text in the middle and, optionally, the unit's name.
--
-- Hidden values: in combat the game can hide health and power from addons (secret values:
-- they can be passed on, never read, compared or added up). A ring's fill is drawn from
-- line segments, so it can't simply be given a hidden number to fill to. Instead every
-- segment gets a step curve of its own (0 below its place round the ring, 1 from there on),
-- and UnitHealthPercent / UnitPowerPercent run the hidden percentage through it: the hidden
-- 0 or 1 that comes back goes straight into the segment's SetAlpha, which accepts hidden
-- values from addon code. So the right segments show without Circlet ever knowing the
-- number (the same way the target cast ring shows hidden cast times; LiveRing fillGate).
-- The text goes the same way: the hidden number is handed to the font string, which
-- draws it. When the values can be read (often your own, or out of combat) they're used
-- as they are. What can't be done with hidden values: anything that compares them (a
-- "not full" check, colors by how low it is), so those treat hidden as "something to show".

local POWER_TOKENS = { [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY" }

---------------------------------------------------------------- hidden-value helpers
local function Readable(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) ~= "number" or IsSecret(v) then return false end
    end
    return true
end

-- The percent functions' scale: 1 if they run 0..1 (as they should), 100 if 0..100. Checked
-- against your own health whenever both can be read.
H.percentScale = 1
local function CheckScale()
    if type(UnitHealthPercent) ~= "function" then return end
    local hp, max = SafeCall(UnitHealth, "player"), SafeCall(UnitHealthMax, "player")
    local p = SafeCall(UnitHealthPercent, "player")
    if Readable(hp, max, p) and max > 0 and hp > 0 then H.percentScale = (p > 1.001) and 100 or 1 end
end

local stepCurves = {} -- by threshold (in 1/400ths): 0 below it, 1 from it on
local function StepCurve(t)
    local key = math.max(1, math.floor(t * 400 + 0.5))
    local cv = stepCurves[key]
    if cv then return cv end
    cv = C_CurveUtil.CreateCurve()
    if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then pcall(cv.SetType, cv, Enum.LuaCurveType.Step) end
    cv:AddPoint(0, 0)
    cv:AddPoint(key / 400 * H.percentScale, 1)
    stepCurves[key] = cv
    return cv
end

local function CurvesWork() return C_CurveUtil and type(C_CurveUtil.CreateCurve) == "function" end

-- A fill gate (each segment's alpha from where it sits round the ring) for a hidden value,
-- or nil if this client can't do it. pct(curve) runs the hidden percentage through a curve.
local function Gate(pct)
    if not CurvesWork() then return nil end
    local okC, cv = pcall(StepCurve, 0.5)
    if not okC or not pcall(pct, cv) then return nil end
    return function(pos)
        local ok, v = pcall(pct, StepCurve(pos))
        if ok then return v end
        return 0
    end
end

-- For the effects (Rings/Health/Fx/): the percent scale and whether curves work here.
ns.VitalsCurves = { Scale = function() return H.percentScale end, Work = CurvesWork, Readable = Readable }

-- The hidden percentage (0..100) for text, through the game's own scaling curve if it has one.
local function HiddenPercent100(pct)
    local scale = CurveConstants and CurveConstants.ScaleTo100
    if scale then
        local ok, v = pcall(pct, scale)
        if ok then return v end
    end
end

---------------------------------------------------------------- reading a unit
local function Short(n)
    if n >= 1e6 then return string.format("%.1fm", n / 1e6) end
    if n >= 1e4 then return string.format("%.1fk", n / 1e3) end
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- Health color: the ring's own, or the unit's class color (players) / reaction (NPCs).
local REACTION = {
    hostile = { r = 0.85, g = 0.2, b = 0.15 },
    neutral = { r = 0.95, g = 0.8, b = 0.2 },
    friendly = { r = 0.25, g = 0.8, b = 0.3 },
    tapped = { r = 0.5, g = 0.5, b = 0.5 },
}
local function HealthColor(key, unit)
    local c = db[key .. "Colors"]
    -- Tagged by someone else (the Tapped effect): grey, whatever the color mode.
    if db[key .. "FxTapped"] and Clean(SafeCall(UnitIsTapDenied, unit)) then return REACTION.tapped end
    if db[key .. "ColorMode"] ~= "class" then return c.health end
    if Clean(SafeCall(UnitIsPlayer, unit)) then
        local _, class = SafeCall(UnitClass, unit)
        class = Clean(class)
        local cc = class
            and (
                (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
                or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
            )
        if cc then return { r = cc.r, g = cc.g, b = cc.b } end
        return c.health
    end
    if Clean(SafeCall(UnitIsTapDenied, unit)) then return REACTION.tapped end
    local reaction = CleanNumber(SafeCall(UnitReaction, unit, "player"))
    if reaction then
        if reaction <= 3 then
            return REACTION.hostile
        elseif reaction == 4 then
            return REACTION.neutral
        end
        return REACTION.friendly
    end
    return c.health
end

local function PowerColor(key, token)
    local c = db[key .. "Colors"]
    if token == "MANA" then
        return c.mana
    elseif token == "RAGE" then
        return c.rage
    elseif token == "ENERGY" then
        return c.energy
    elseif token == "FOCUS" then
        return c.focus
    end
    local pc = PowerBarColor and token and PowerBarColor[token]
    if pc and pc.r then return { r = pc.r, g = pc.g, b = pc.b } end
    return c.mana
end

local function InCombat()
    return Clean(SafeCall(UnitAffectingCombat, "player")) or (InCombatLockdown and InCombatLockdown()) or false
end

-- For the files loaded after this one.
H.POWER_TOKENS = POWER_TOKENS
H.Readable = Readable
H.Gate = Gate
H.HiddenPercent100 = HiddenPercent100
H.Short = Short
H.HealthColor = HealthColor
H.PowerColor = PowerColor
H.InCombat = InCombat
H.REACTION = REACTION
H.CheckScale = CheckScale
H.CurvesWork = CurvesWork
