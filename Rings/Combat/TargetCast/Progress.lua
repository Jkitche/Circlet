-- Circlet: Target cast ring: what your target is casting or channeling, and whether you can interrupt it.
local ADDON_NAME, ns = ...

local db, CreateLiveRing = ns.db, ns.CreateLiveRing
local SafeCall, Clean, IsSecret = ns.SafeCall, ns.Clean, ns.IsSecret

-- Shared by Rings/Combat/TargetCast/*.lua, which load in this order: Progress, Sweep, Ring, Register.
ns.TargetCastRing = ns.TargetCastRing or {}
local TC = ns.TargetCastRing

---------------------------------------------------------------------------
-- Target cast ring
---------------------------------------------------------------------------
-- Fills while your target casts (drains while it channels), with the spell's icon, the
-- time left and who's casting. A cast you can't interrupt turns the ring gray and says
-- so. When the cast ends the ring turns green (it went off) or red (interrupted or
-- failed), and an interrupted cast flashes the part it lost. Switching targets
-- switches the ring to the new target's cast, or clears it.
-- Timing comes from the game's cast info for the target. In combat the client can hide
-- it (secret values), so the ring falls back, in order, to:
--   1. how long that spell took when it last could see (learned per spell ID and name
--      whenever the times are readable, kept in db.targetCastTimes);
--   2. the spell's listed cast time;
--   3. the game's own timer display: a sweep in the ring's middle with the game's
--      countdown, fed the cast's duration object, which addons may show but not read.
-- With 1 or 2 a * after the label says the time is the ring's own. Targeting yourself,
-- it shows your own casts too (unless targetCastSelf is off: the cast ring has them).
-- /circ targetdebug shows what's hidden.

local UNIT = "target"

local function Learned()
    db.targetCastTimes = db.targetCastTimes or {}
    return db.targetCastTimes
end

-- Remember how long a spell took (by ID and by name; either may be hidden).
local function Learn(c)
    if not (c.start and c.finish and c.real) then return end
    local dur = c.finish - c.start
    if dur <= 0 or dur > 600 then return end
    local t = Learned()
    if c.spellID then t[c.spellID] = dur end
    if c.name and c.name ~= "Casting" then t[c.name] = dur end
end

local function LearnedTime(c)
    local t = Learned()
    return (c.spellID and t[c.spellID]) or (c.name and t[c.name]) or nil
end

local function ListedCastTime(spellID)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local info = SafeCall(C_Spell.GetSpellInfo, spellID)
    local ms = type(info) == "table" and Clean(info.castTime) or nil
    if type(ms) == "number" and ms > 0 then return ms / 1000 end
end

-- The cast's duration object (display only), when the client has one to give.
local function DurationObject(channel)
    local fn = channel and _G.UnitChannelDuration or _G.UnitCastingDuration
    return fn and SafeCall(fn, UNIT) or nil
end

---------------------------------------------------------------------------
-- Progress from a hidden duration, segment by segment
---------------------------------------------------------------------------
-- With the times hidden, the cast's duration object can still say how far along it is,
-- through a curve: EvaluateElapsedPercent(curve) runs the (hidden) progress through a curve
-- of our own and hands back a (hidden) result, and a line's SetAlpha accepts hidden values
-- from addon code. So each segment of the ring gets a step curve that's 0 before its place
-- along the ring and 1 from there on: the segments the cast has reached show, the rest
-- don't. That's the ring's own drawing, so every shape (ring, three-quarter, half),
-- style and direction fills as usual. (A channel uses the remaining time, so it drains.)
-- If the progress turns out to be a plain number after all, it's used as is.

local percentScale -- 1 if a duration's percentages run 0..1, 100 if 0..100
local function PercentScale()
    if percentScale then return percentScale end
    percentScale = 1
    -- Found from a duration of our own, halfway through (nothing hidden in it).
    local util = C_DurationUtil
    if util and type(util.CreateDuration) == "function" then
        local ok, d = pcall(util.CreateDuration)
        if ok and d and pcall(d.SetTimeFromStart, d, GetTime() - 5, 10) then
            local okP, p = pcall(d.GetElapsedPercent, d)
            if okP and type(p) == "number" and not IsSecret(p) and p > 2 then percentScale = 100 end
        end
    end
    return percentScale
end

-- How far along cast c is (0..1, a channel by what's left), if the game lets that be read.
local function ReadablePercent(c)
    local dur = c.durObj
    local method = c.channel and "GetRemainingPercent" or "GetElapsedPercent"
    local fn = dur and dur[method]
    if type(fn) ~= "function" then return nil end
    local ok, p = pcall(fn, dur)
    if ok and type(p) == "number" and not IsSecret(p) then return math.max(0, math.min(1, p / PercentScale())) end
end

local stepCurves = {} -- by threshold: curves that are 0 below it and 1 from it on
local function StepCurve(t)
    local key = math.max(1, math.floor(t * 400 + 0.5)) -- in 1/400ths of the ring
    local cv = stepCurves[key]
    if cv then return cv end
    cv = C_CurveUtil.CreateCurve()
    if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then pcall(cv.SetType, cv, Enum.LuaCurveType.Step) end
    cv:AddPoint(0, 0)
    cv:AddPoint(key / 400 * PercentScale(), 1)
    stepCurves[key] = cv
    return cv
end

-- The fill gate for cast c (each segment's alpha from where it sits), or nil plus why not.
local function Gate(c)
    local dur = c.durObj
    if not (C_CurveUtil and type(C_CurveUtil.CreateCurve) == "function") then return nil, "no C_CurveUtil" end
    local method = c.channel and "EvaluateRemainingPercent" or "EvaluateElapsedPercent"
    local fn = dur and dur[method]
    if type(fn) ~= "function" then return nil, method .. " missing" end
    local okC, cv = pcall(StepCurve, 0.5)
    if not okC then return nil, "curve: " .. tostring(cv) end
    local ok, err = pcall(fn, dur, cv)
    if not ok then return nil, method .. ": " .. tostring(err) end
    return function(pos)
        local okE, v = pcall(fn, dur, StepCurve(pos))
        if okE then return v end
        return 0
    end
end

-- Notes which way the ring shows a hidden cast's progress, once per cast.
local function NoteMode(c, mode, extra)
    if c.noted == mode then return end
    c.noted = mode
    db.targetCastDiag = {
        at = date and date("%Y-%m-%d %H:%M:%S") or "?",
        mode = mode,
        detail = extra,
        percentScale = percentScale,
    }
end

-- For the files loaded after this one.
TC.DurationObject = DurationObject
TC.UNIT = UNIT
TC.Learn = Learn
TC.LearnedTime = LearnedTime
TC.ListedCastTime = ListedCastTime
TC.ReadablePercent = ReadablePercent
TC.Gate = Gate
TC.NoteMode = NoteMode
