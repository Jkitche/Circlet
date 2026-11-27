-- Circlet: Target cast ring: the game's cooldown sweep, which draws the fill when the cast's times are hidden.
local ADDON_NAME, ns = ...

local db = ns.db
local TC = ns.TargetCastRing
local DurationObject = TC.DurationObject

---------------------------------------------------------------------------
-- The game's own timer, for when the times are hidden
---------------------------------------------------------------------------
-- The ring is drawn from numbers, which a hidden duration can't give. So the game's
-- cooldown sweep draws the fill instead: its swipe texture is a ring (Textures/RingNN.tga,
-- NN = the hollow's radius as % of the outer edge, the closest to this ring's band), laid
-- exactly over the ring's band and turned to start where the ring (or arc) does. It fills
-- in the ring's color as the cast goes (unwinds for a channel).
--
-- A sweep always goes all the way round in the cooldown's time, but an arc is only part of
-- a circle (half: 180 degrees, three quarters: 270). So for an arc the sweep runs slowed
-- down to the arc's share of a turn: it reaches the arc's end just as the cast does, and
-- never gets to the part of the circle outside the arc. That's done by giving the
-- cooldown a slower rate: through a copy of the cast's duration with a slower rate
-- (C_DurationUtil), or else SetCooldown with a rate. A slowed sweep's countdown would run
-- slow too, so the game's countdown numbers then come from a second, sweepless cooldown
-- fed the real duration. If neither way works in this client, the arc gets a disc in its
-- middle instead. What happened is kept in db.targetCastDiag (and /circ targetdebug).
local CIRCLE   = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RING_TEX = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Ring%d"

local function PlainCooldown(parent, swipe)
    local cd = CreateFrame("Cooldown", nil, parent)
    cd:SetAllPoints()
    if cd.SetDrawSwipe then cd:SetDrawSwipe(swipe) end
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
    return cd
end

-- Plain Cooldowns, not CooldownFrameTemplate: the template's scripts can put the default
-- (round) swipe back when a cooldown starts. cd sweeps; numbers only counts down (for a
-- slowed sweep, whose own numbers would be wrong).
local function Timer(frame)
    if TC.timer then return TC.timer end
    TC.timer = CreateFrame("Frame", nil, frame)
    TC.timer:SetPoint("CENTER")
    TC.timer.cd = PlainCooldown(TC.timer, true)
    TC.timer.numbers = PlainCooldown(TC.timer, false)
    TC.timer.numbers:Hide()
    TC.timer:Hide()
    return TC.timer
end

-- A texture-coordinate corner for SetTexCoordRange (a Vector2D where the client has them).
local function Corner(x, y)
    if CreateVector2D then return CreateVector2D(x, y) end
    return { x = x, y = y }
end

-- How the sweep looks: its texture, color, turn and direction (from PlaceTimer). Applied when
-- placed and again after every start, in case starting the cooldown reset any of it.
local function ApplyLook(w)
    local cd, look = w.cd, w.look
    if not look then return end
    if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, look.tex) end
    if look.color and cd.SetSwipeColor then
        local c = look.color
        cd:SetSwipeColor(c.r, c.g, c.b, look.alpha or 1)
    end
    if cd.SetRotation then pcall(cd.SetRotation, cd, look.turn or 0) end
    if look.mirror and cd.SetTexCoordRange then
        pcall(cd.SetTexCoordRange, cd, Corner(1, 0), Corner(0, 1)) -- mirrored: counter-clockwise
    elseif w.mirrored and cd.SetTexCoordRange then
        pcall(cd.SetTexCoordRange, cd, Corner(0, 0), Corner(1, 1))
    end
    w.mirrored = look.mirror
end

local function HideTimer()
    if TC.timer and TC.timer:IsShown() then TC.timer:Hide() end
end

-- The ring texture whose band best matches inner / outer radius (made in steps of 4%).
local function RingTexture(innerFrac)
    local pct = math.floor(innerFrac * 25 + 0.5) * 4
    return RING_TEX:format(math.max(40, math.min(96, pct)))
end

local function SizeNumbers(cd, geom)
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if fs and fs.SetFont then
        local inner = math.max(8, (geom.R - geom.T / 2) * 2)
        -- The game's countdown numbers stand in for the main text: they follow its size.
        fs:SetFont(STANDARD_TEXT_FONT, ns.FontSize("targetCast", "Value", inner * 0.25, 9), "OUTLINE")
    end
end

-- Lays the timer over the ring's band (or, for an arc this client can't slow the sweep
-- for, as a disc in its middle). Only redone when the ring's geometry or the cast changes.
local function PlaceTimer(w, frame, geom, channel)
    local sweep = geom.sweep or 1
    local disc = sweep < 1 and w.cantSlow
    local layout = table.concat({ geom.R, geom.T, tostring(geom.start), tostring(geom.reverse), sweep,
                                  tostring(disc), tostring(channel) }, ":")
    if w.layout == layout then return end
    w.layout = layout
    local outer = geom.R + geom.T / 2
    w.rate = disc and 1 or sweep
    w.mode = disc and "arc (disc in the middle: couldn't slow the sweep)"
        or (sweep < 1 and ("arc band, sweep slowed to " .. sweep) or "ring band")
    w.texPath = disc and CIRCLE or RingTexture((geom.R - geom.T / 2) / outer)
    local look = { tex = w.texPath, color = w.look and w.look.color, alpha = disc and 0.55 or 1 }
    if disc then
        local d = math.max(8, (geom.R - geom.T / 2) * 2 * 0.8)
        w:SetSize(d, d)
        look.turn, look.mirror = 0, false
    else
        w:SetSize(outer * 2, outer * 2)
        -- The sweep starts at the top and runs clockwise; the ring starts at geom.start (a
        -- fraction of a turn clockwise from the top), or for reverse at the arc's other end
        -- running counter-clockwise.
        local from = (geom.start or 0) + (geom.reverse and sweep or 0)
        local turn = -2 * math.pi * from -- negative: clockwise
        if geom.reverse then turn = -turn end
        look.turn, look.mirror = turn, geom.reverse and true or false
    end
    w.look = look
    ApplyLook(w)
    SizeNumbers(w.cd, geom)
    SizeNumbers(w.numbers, geom)
end

-- A method call that may refuse (secret values, a missing method): ok, then its results.
local function Try(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return false end
    return pcall(fn, obj, ...)
end

-- An error message, short and without the file and line.
local function Err(e)
    return (tostring(e or "?"):gsub("^.-:%d+: ", "")):sub(1, 120)
end

-- Calls fn, noting in w.attempts how it went (for the diagnostics). true if it worked.
local function Attempt(w, label, fn, ...)
    local ok, err = pcall(fn, ...)
    table.insert(w.attempts, label .. (ok and ": ok" or (": " .. Err(err))))
    return ok
end

-- Starts the sweep for cast c, slowed to w.rate for an arc. Returns how it was started, or
-- nil if this client wouldn't slow it. Every way tried is noted in w.attempts.
local function Feed(w, c)
    local cd, dur, rate = w.cd, c.durObj, w.rate or 1
    if cd.SetReverse then cd:SetReverse(not c.channel) end -- a cast fills, a channel unwinds
    if rate >= 1 then
        cd:SetCooldownFromDurationObject(dur)
        return "direct"
    end
    w.attempts = {}
    -- The cast's start, end and length, as the game gives them (possibly hidden).
    local function Get(m)
        local fn = dur[m]
        if type(fn) ~= "function" then table.insert(w.attempts, m .. ": missing") return nil end
        local ok, v = pcall(fn, dur)
        table.insert(w.attempts, m .. (ok and (type(v) == "nil" and ": nil" or ": ok") or (": " .. Err(v))))
        if ok then return v end
    end
    local start, total = Get("GetStartTime"), Get("GetTotalDuration")
    -- 1. A copy of the duration that runs at the arc's rate.
    local util = C_DurationUtil
    if util and type(util.CreateDuration) == "function" and start and total then
        local okC, copy = pcall(util.CreateDuration)
        if not (okC and copy) then
            table.insert(w.attempts, "CreateDuration: " .. Err(copy))
        elseif type(copy.SetTimeFromStart) ~= "function" then
            table.insert(w.attempts, "copy:SetTimeFromStart: missing")
        elseif Attempt(w, "copy:SetTimeFromStart(start, total, rate)", copy.SetTimeFromStart, copy, start, total, rate)
            and Attempt(w, "SetCooldownFromDurationObject(copy)", cd.SetCooldownFromDurationObject, cd, copy) then
            return "slowed copy of the duration"
        end
    end
    -- 2. The cooldown's own rate, from the cast's start.
    if type(cd.SetCooldown) == "function" and start and total
        and Attempt(w, "SetCooldown(start, total, rate)", cd.SetCooldown, cd, start, total, rate) then
        return "SetCooldown with a rate"
    end
    -- 3. From now (the cast has only just started), for its length, at the rate.
    if type(cd.SetCooldownDuration) == "function" and total
        and Attempt(w, "SetCooldownDuration(total, rate)", cd.SetCooldownDuration, cd, total, rate) then
        return "SetCooldownDuration with a rate"
    end
    -- 4. Started as it is, then slowed, if the cooldown can change its rate.
    for _, m in ipairs({ "SetCooldownModRate", "SetModRate" }) do
        if type(cd[m]) == "function" then
            if Attempt(w, "SetCooldownFromDurationObject(cast)", cd.SetCooldownFromDurationObject, cd, dur)
                and Attempt(w, m .. "(rate)", cd[m], cd, rate) then
                return m
            end
        end
    end
    return nil
end

-- The names of an object's methods (from its metatable, or its own functions), or of a
-- table's functions; only those matching `filter` if given.
local function Methods(obj, filter)
    local names = {}
    local ok, mt = pcall(getmetatable, obj)
    local idx = ok and type(mt) == "table" and mt.__index or nil
    local src = type(idx) == "table" and idx or (type(obj) == "table" and obj) or nil
    if src then
        for k, v in pairs(src) do
            if type(v) == "function" and (not filter or tostring(k):find(filter)) then table.insert(names, tostring(k)) end
        end
    end
    table.sort(names)
    return #names > 0 and table.concat(names, ",") or "(none found)"
end

-- What happened, for /circ targetdebug and db.targetCastDiag (read back from the saved
-- variables when something doesn't look right).
local diagProbe -- a hidden texture, to check the swipe texture loads
local function Diagnose(w, how, c)
    diagProbe = diagProbe or (UIParent and UIParent.CreateTexture and UIParent:CreateTexture())
    local probe = diagProbe
    local loads = probe and probe:SetTexture(w.texPath)
    if probe then probe:SetTexture(nil); probe:Hide() end
    db.targetCastDiag = {
        at = date and date("%Y-%m-%d %H:%M:%S") or "?", mode = w.mode, fed = how or "failed",
        texture = w.texPath, textureLoads = tostring(loads), rate = w.rate,
        attempts = w.attempts and table.concat(w.attempts, " | ") or "(none: not slowed)",
        durationMethods = c and c.durObj and Methods(c.durObj) or "?",
        durationUtil = C_DurationUtil and Methods(C_DurationUtil) or "(no C_DurationUtil)",
        cooldownMethods = Methods(w.cd, "[CR][oa][ot]"), -- the Cooldown... and Rate ones
    }
    w.diag = db.targetCastDiag
end

-- Shows the game's timer for cast c on the ring's frame; false if there's nothing to show.
local function ShowTimer(c, frame, geom, color)
    if not (c.durObj or c.durTried) then
        c.durTried = true
        c.durObj = DurationObject(c.channel)
    end
    if not c.durObj then return false end
    local w = Timer(frame)
    if not (w.cd.SetCooldownFromDurationObject) then return false end
    w.cd:Show()
    if w.numbersOnly then w.numbersOnly, w.fedWith, w.layout = nil, nil, nil end
    PlaceTimer(w, frame, geom, c.channel)
    w:SetFrameLevel(frame:GetFrameLevel() + 2)
    -- The ring's color, kept in the look (it changes: casting, channel, can't interrupt).
    local lc = w.look.color
    if not lc or lc.r ~= color.r or lc.g ~= color.g or lc.b ~= color.b then
        w.look.color = { r = color.r, g = color.g, b = color.b }
        if w.cd.SetSwipeColor then w.cd:SetSwipeColor(color.r, color.g, color.b, w.look.alpha or 1) end
    end
    -- Feed it once per cast (and after a delay), not every frame, which would restart it;
    -- then put the ring look back on, in case starting it reset the swipe.
    if w.fedWith ~= c or c.durStale then
        w.fedWith, c.durStale = c, false
        local how = Feed(w, c)
        if not how then
            -- Can't slow it here: the arc gets a disc in its middle from now on.
            local tried = w.attempts
            w.cantSlow = true
            PlaceTimer(w, frame, geom, c.channel)
            how = Feed(w, c)
            w.attempts = tried
            how = "disc (" .. how .. ")"
        end
        local slowed = how ~= nil and how ~= "direct" and how:sub(1, 4) ~= "disc"
        -- A slowed sweep's own countdown would run slow: the real one comes from `numbers`.
        if w.cd.SetHideCountdownNumbers then w.cd:SetHideCountdownNumbers(slowed) end
        if slowed then
            pcall(w.numbers.SetCooldownFromDurationObject, w.numbers, c.durObj)
            w.numbers:Show()
        else
            w.numbers:Hide()
        end
        ApplyLook(w)
        Diagnose(w, how, c)
    end
    w:Show()
    return true
end

-- Just the game's countdown in the ring's middle, for when the ring's own segments show
-- the progress (fillGate): no sweep.
local function ShowNumbers(c, frame, geom)
    local w = Timer(frame)
    if not (w.numbers and w.numbers.SetCooldownFromDurationObject) then return false end
    if not w.numbersOnly then w.numbersOnly, w.fedWith, w.layout = true, nil, nil end
    w.cd:Hide()
    local inner = math.max(8, (geom.R - geom.T / 2) * 2)
    w:SetSize(inner, inner)
    w:SetFrameLevel(frame:GetFrameLevel() + 2)
    SizeNumbers(w.numbers, geom)
    if w.fedWith ~= c or c.durStale then
        w.fedWith, c.durStale = c, false
        pcall(w.numbers.SetCooldownFromDurationObject, w.numbers, c.durObj)
    end
    w.numbers:Show()
    w:Show()
    return true
end

-- For the files loaded after this one.
TC.HideTimer = HideTimer
TC.RingTexture = RingTexture
TC.ShowTimer = ShowTimer
TC.ShowNumbers = ShowNumbers
