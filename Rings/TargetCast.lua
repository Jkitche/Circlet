-- Circlet: Target cast ring: what your target is casting or channeling, and whether you can interrupt it.
local ADDON_NAME, ns = ...

local db, CreateLiveRing = ns.db, ns.CreateLiveRing
local SafeCall, Clean = ns.SafeCall, ns.Clean

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
local cast -- { castID, spellID, name, icon, channel, shielded, caster, start, finish, real, endedAt, how, lost }

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
-- The game's own timer, for when the times are hidden
---------------------------------------------------------------------------
-- The ring is drawn from numbers, which a hidden duration can't give. So the game's
-- cooldown sweep draws the fill instead: its swipe texture is a ring (Textures/RingNN.tga,
-- NN = the hollow's radius as % of the outer edge, the closest to this ring's band), laid
-- exactly over the ring's band and turned to start where the ring does. It fills in the
-- ring's color as the cast goes (unwinds for a channel), with the game's countdown in the
-- middle. Arcs (three-quarter, half) can't be swept this way: they get a disc in the
-- middle instead.
local CIRCLE   = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RING_TEX = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Ring%d"
local timer -- made on first use

local function Timer(frame)
    if timer then return timer end
    timer = CreateFrame("Frame", nil, frame)
    timer:SetPoint("CENTER")
    timer.cd = CreateFrame("Cooldown", nil, timer, "CooldownFrameTemplate")
    timer.cd:SetAllPoints()
    if timer.cd.SetDrawEdge then timer.cd:SetDrawEdge(false) end
    if timer.cd.SetDrawBling then timer.cd:SetDrawBling(false) end
    if timer.cd.SetHideCountdownNumbers then timer.cd:SetHideCountdownNumbers(false) end
    timer:Hide()
    return timer
end

local function HideTimer()
    if timer and timer:IsShown() then timer:Hide() end
end

-- The ring texture whose band best matches inner / outer radius (made in steps of 4%).
local function RingTexture(innerFrac)
    local pct = math.floor(innerFrac * 25 + 0.5) * 4
    return RING_TEX:format(math.max(40, math.min(96, pct)))
end

-- Lays the timer over the ring's band (or, for an arc, as a disc in its middle). Only
-- redone when the ring's geometry or the cast changes.
local function PlaceTimer(w, frame, geom, channel)
    local arc = (geom.sweep or 1) < 1
    local layout = table.concat({ geom.R, geom.T, tostring(geom.start), tostring(geom.reverse), tostring(arc),
                                  tostring(channel) }, ":")
    if w.layout == layout then return end
    w.layout = layout
    local cd = w.cd
    local outer = geom.R + geom.T / 2
    if arc then
        local d = math.max(8, (geom.R - geom.T / 2) * 2 * 0.8)
        w:SetSize(d, d)
        if cd.SetSwipeTexture then cd:SetSwipeTexture(CIRCLE) end
        if cd.SetRotation then pcall(cd.SetRotation, cd, 0) end
        if cd.SetTexCoordRange then pcall(cd.SetTexCoordRange, cd, { x = 0, y = 0 }, { x = 1, y = 1 }) end
    else
        w:SetSize(outer * 2, outer * 2)
        if cd.SetSwipeTexture then cd:SetSwipeTexture(RingTexture((geom.R - geom.T / 2) / outer)) end
        -- The sweep starts at the top and runs clockwise; the ring starts at geom.start
        -- (a fraction of a turn clockwise from the top) and may run counter-clockwise.
        if cd.SetTexCoordRange then
            if geom.reverse then
                pcall(cd.SetTexCoordRange, cd, { x = 1, y = 0 }, { x = 0, y = 1 }) -- mirrored: counter-clockwise
            else
                pcall(cd.SetTexCoordRange, cd, { x = 0, y = 0 }, { x = 1, y = 1 })
            end
        end
        local turn = -2 * math.pi * (geom.start or 0) -- negative: clockwise
        if geom.reverse then turn = -turn end
        if cd.SetRotation then pcall(cd.SetRotation, cd, turn) end
    end
    -- The game's countdown, sized like the ring's own time text.
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if fs and fs.SetFont then
        local inner = math.max(8, (geom.R - geom.T / 2) * 2)
        fs:SetFont(STANDARD_TEXT_FONT, math.max(9, math.floor(inner * 0.25)), "OUTLINE")
    end
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
    PlaceTimer(w, frame, geom, c.channel)
    w:SetFrameLevel(frame:GetFrameLevel() + 2)
    if w.cd.SetSwipeColor then
        w.cd:SetSwipeColor(color.r, color.g, color.b, (geom.sweep or 1) < 1 and 0.55 or 1)
    end
    -- Feed it once per cast (and after a delay), not every frame, which would restart it.
    if w.fedWith ~= c or c.durStale then
        w.fedWith, c.durStale = c, false
        if w.cd.SetReverse then w.cd:SetReverse(not c.channel) end -- a cast fills, a channel unwinds
        w.cd:SetCooldownFromDurationObject(c.durObj)
    end
    w:Show()
    return true
end

-- What the game says the target is casting (or channeling): name, icon, start, finish
-- (seconds, nil when hidden), can't-be-interrupted, spellID. nil when it's casting nothing.
local function Info(channel)
    local name, icon, startMS, endMS, shielded, spellID
    if channel then
        local n, _, tex, s, e, _, ni, id = SafeCall(UnitChannelInfo, UNIT)
        name, icon, startMS, endMS, shielded, spellID = n, tex, s, e, ni, id
    else
        local n, _, tex, s, e, _, _, ni, id = SafeCall(UnitCastingInfo, UNIT)
        name, icon, startMS, endMS, shielded, spellID = n, tex, s, e, ni, id
    end
    if not name then return nil end -- not casting (a secret name still counts as casting)
    startMS, endMS = Clean(startMS), Clean(endMS)
    local s, f
    if type(startMS) == "number" and type(endMS) == "number" and endMS > startMS then
        s, f = startMS / 1000, endMS / 1000
    end
    shielded = Clean(shielded)
    return Clean(name), Clean(icon), s, f, shielded, Clean(spellID)
end

local function Progress(now)
    if not (cast and cast.start and cast.finish) then return nil end
    local span = cast.finish - cast.start
    if span <= 0 then return nil end
    return math.max(0, math.min(1, (now - cast.start) / span)), math.max(0, cast.finish - now)
end

-- Unit checks that never throw (false when the client lacks the call or hides the answer).
local function Yes(fn, ...) return Clean(SafeCall(fn, ...)) and true or false end
local function TargetIsYou() return Yes(UnitIsUnit, UNIT, "player") end

-- Should the ring follow this target at all?
local function Watching()
    if not db.targetCastEnabled then return false end
    if not Yes(UnitExists, UNIT) then return false end
    if TargetIsYou() and not db.targetCastSelf then return false end
    if db.targetCastHostileOnly and not Yes(UnitCanAttack, "player", UNIT) then return false end
    return true
end

local function CasterName()
    local n = SafeCall(UnitName, UNIT)
    return Clean(n)
end

-- Starts following the target's current cast or channel (from an event, or a new target).
-- castID / spellID come from the event when there is one.
local function Begin(channel, castID, spellID)
    if not Watching() then cast = nil return end
    local name, icon, s, f, shielded, infoID = Info(channel)
    if not name and not s and not Clean(spellID) then
        -- Nothing readable at all: maybe it's casting nothing (a new target).
        if not SafeCall(channel and UnitChannelInfo or UnitCastingInfo, UNIT) then cast = nil return end
    end
    spellID = Clean(spellID) or infoID
    local now = GetTime()
    cast = { castID = Clean(castID), spellID = spellID, channel = channel, shielded = shielded and true or false,
             name = name or (spellID and ns.SpellName(spellID)) or "Casting",
             icon = icon or (spellID and ns.SpellIcon(spellID)), caster = CasterName() }
    if s then
        cast.start, cast.finish, cast.real = s, f, true
        Learn(cast)
        return
    end
    -- Times hidden: what this spell took before, or its listed cast time.
    local dur = LearnedTime(cast) or (not channel and spellID and ListedCastTime(spellID))
    if dur and dur > 0 then cast.start, cast.finish = now, now + dur end
end

-- A new target: show what it's casting now, if anything (no end animation for the old one).
local function Retarget()
    cast = nil
    if not Watching() then return end
    if SafeCall(UnitChannelInfo, UNIT) then
        Begin(true)
    elseif SafeCall(UnitCastingInfo, UNIT) then
        Begin(false)
    end
end

local function Finish(how)
    local c = cast
    if not c or c.endedAt then return end
    local now = GetTime()
    if how ~= "done" then c.lost = Progress(now) end
    c.how, c.endedAt = how, now
end

-- An event about the cast we're following?
local function Ours(castID, spellID)
    if not cast or cast.endedAt then return false end
    castID, spellID = Clean(castID), Clean(spellID)
    if castID and cast.castID then return castID == cast.castID end
    if spellID and cast.spellID then return spellID == cast.spellID end
    return true
end

local function State(st)
    local c = db.targetCastColors
    local out = { title = st.name or "Casting", icon = db.targetCastIcon and st.icon or nil,
                  hold = db.targetCastHold or 1, noBurst = true }
    if st.ended then
        if st.how == "done" then
            out.frac, out.color, out.labelColor = 1, c.done, c.done
            out.label, out.value = st.channel and "Done" or "Cast", ""
            out.doneAt = st.endedAt
        else
            out.frac = st.channel and (st.frac or 0) or 0
            out.color, out.labelColor = c.interrupted, c.interrupted
            out.label, out.value = st.how == "failed" and "Failed" or "Interrupted", ""
            if not st.channel and st.lost and st.lost > 0 then
                out.flashFrom, out.flashTo, out.flashAt = 0, st.lost, st.endedAt
            end
        end
        return out
    end
    -- Still going: if it vanishes without an end (a new target), don't linger on it.
    out.hold = 0.2
    out.color = st.shielded and c.shielded or (st.channel and c.channel or c.cast)
    out.iconColor = out.color
    local who = st.caster and db.targetCastName and st.caster or nil
    if st.shielded then
        out.label, out.labelColor = "Can't interrupt", c.shielded
    else
        out.label = who or (st.channel and "Channeling" or "Casting")
    end
    if not st.frac then
        out.frac, out.value = 1, "" -- no timing at all: just the spell, ring full
        return out
    end
    out.frac = st.channel and (1 - st.frac) or st.frac
    out.value = string.format(st.left >= 10 and "%.0f" or "%.1f", st.left)
    if st.guessed then out.label = out.label .. "*" end
    return out
end

-- Edit mode's sample: an enemy's Fireball that goes off, a Frostbolt that's interrupted,
-- then a channel you can't interrupt.
local SAMPLE_FIRE  = "Interface\\Icons\\Spell_Fire_FlameBolt"
local SAMPLE_FROST = "Interface\\Icons\\Spell_Frost_FrostBolt02"
local SAMPLE_DRAIN = "Interface\\Icons\\Spell_Shadow_LifeDrain02"

local targetCastRing = CreateLiveRing({
    key = "targetCast",
    read = function(now)
        local c = cast
        if not c then return nil end
        if c.endedAt then
            if now - c.endedAt > 0.1 then cast = nil return nil end -- shown once; the ring holds it
            return State({ name = c.name, icon = c.icon, channel = c.channel, ended = true, how = c.how,
                           endedAt = c.endedAt, lost = c.lost, frac = c.lost or 1 })
        end
        if not Watching() then cast = nil return nil end
        -- Keep up with the game's timing (pushback, channel updates) while it's readable.
        local name, _, s, f, shielded = Info(c.channel)
        if s then
            local wasReal = c.real
            c.start, c.finish, c.real = s, f, true
            if not wasReal then Learn(c) end
        end
        if shielded ~= nil then c.shielded = shielded and true or false end
        -- Ran out with no event (say the target went out of range): it went off.
        -- (A hidden name still means it's casting, so ask the game directly.)
        if c.finish and now > c.finish + 0.3 and not name
            and not SafeCall(c.channel and UnitChannelInfo or UnitCastingInfo, UNIT) then
            Finish("done")
            return nil
        end
        local frac, left = Progress(now)
        local st = State({ name = c.name, icon = c.icon, channel = c.channel, shielded = c.shielded, caster = c.caster,
                           frac = frac, left = left or 0, guessed = frac and not c.real })
        if not frac then
            -- No timing we can read: the game's own timer in the middle (decorate shows it).
            if not (c.durObj or c.durTried) then
                c.durTried = true
                c.durObj = DurationObject(c.channel)
            end
            if c.durObj then st.timerCast, st.frac = c, 0 end
        end
        return st
    end,
    sample = function(t)
        local cycle = t % 10
        local who = "Defias Conjurer"
        if cycle < 2.5 then
            return State({ name = "Fireball", icon = SAMPLE_FIRE, caster = who, frac = cycle / 2.5, left = 2.5 - cycle })
        end
        if cycle < 3.2 then
            return State({ name = "Fireball", icon = SAMPLE_FIRE, ended = true, how = "done", endedAt = GetTime() - (cycle - 2.5) })
        end
        if cycle < 4.6 then
            local f = (cycle - 3.2) / 2.5
            return State({ name = "Frostbolt", icon = SAMPLE_FROST, caster = who, frac = f, left = 2.5 - (cycle - 3.2) })
        end
        if cycle < 5.4 then
            return State({ name = "Frostbolt", icon = SAMPLE_FROST, ended = true, how = "interrupted",
                           endedAt = GetTime() - (cycle - 4.6), lost = 0.56 })
        end
        if cycle < 9.4 then
            local f = (cycle - 5.4) / 4
            return State({ name = "Drain Life", icon = SAMPLE_DRAIN, caster = who, channel = true, shielded = true,
                           frac = f, left = 4 - (cycle - 5.4) })
        end
        return State({ name = "Drain Life", icon = SAMPLE_DRAIN, channel = true, ended = true, how = "done",
                       endedAt = GetTime() - (cycle - 9.4) })
    end,
    decorate = function(st, frame, geom)
        if st and st.timerCast and geom.R > 0 and ShowTimer(st.timerCast, frame, geom, st.color) then return end
        HideTimer()
    end,
})

-- The same cast start arriving twice (as "target" and as "player" when you target
-- yourself): keep following the first.
local function AlreadyFollowing(castID)
    castID = Clean(castID)
    return cast and not cast.endedAt and castID and cast.castID == castID
end

local SPELLCAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }

local function OnEvent(event, unit, castID, spellID)
    if not CircletDB then return end
    -- Your own cast events count only while you're targeting yourself.
    if unit == "player" and not TargetIsYou() then return end
    if event == "PLAYER_TARGET_CHANGED" then
        Retarget()
    elseif event == "UNIT_SPELLCAST_START" then
        if not AlreadyFollowing(castID) then Begin(false, castID, spellID) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        if not AlreadyFollowing(castID) then Begin(true, castID, spellID) end
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        if cast and not cast.endedAt then cast.shielded = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" end
    elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        if cast and not cast.endedAt then
            local _, _, s, f = Info(cast.channel)
            if s then cast.start, cast.finish, cast.real = s, f, true end
            -- The game's timer (if it's showing) needs the updated duration.
            if cast.durObj then
                cast.durObj = DurationObject(cast.channel) or cast.durObj
                cast.durStale = true
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if Ours(castID, spellID) and not cast.channel then Finish("done") end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if Ours(castID, spellID) then Finish(cast.channel and "done" or "interrupted") end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        if Ours(castID, spellID) and not cast.channel then Finish("failed") end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if cast and cast.channel and not cast.endedAt then
            -- Channels end early when interrupted; otherwise they run out.
            local frac = Progress(GetTime())
            Finish((frac and frac < 0.95) and "interrupted" or "done")
        end
    elseif event == "UNIT_SPELLCAST_STOP" then
        -- Interrupts and failures arrive first as their own events, so reaching this
        -- still running means it went off (same as the game's cast bar).
        if Ours(castID, spellID) and not cast.channel then Finish("done") end
    end
end

-- One registration per unit: a frame can only watch each event for one set of units,
-- so the target's and your own (for when you target yourself) go on separate frames.
local targetEvents, playerEvents = { "PLAYER_TARGET_CHANGED" }, {}
for _, e in ipairs(SPELLCAST_EVENTS) do
    table.insert(targetEvents, e .. ":target")
    table.insert(playerEvents, e .. ":player")
end
ns.Listen(targetEvents, OnEvent)
ns.Listen(playerEvents, OnEvent)

-- /circ targetdebug: what the game tells (and hides) about your target's cast right now,
-- and what the ring is doing with it. Use it while the target is casting.
local function Show(v)
    if ns.IsSecret(v) then return "SECRET" end
    return tostring(v)
end

local function TargetCastDebug()
    ns.Print("Target cast debug" .. (InCombatLockdown() and " (in combat)" or " (out of combat)")
        .. ": target " .. (Yes(UnitExists, UNIT) and Show(SafeCall(UnitName, UNIT)) or "none"))
    for _, which in ipairs({ { "Casting", UnitCastingInfo, { 1, 4, 5, 8, 9 } }, { "Channel", UnitChannelInfo, { 1, 4, 5, 7, 8 } } }) do
        local r = { SafeCall(which[2], UNIT) }
        local labels = { "name", "start", "end", "notInterruptible", "spellID" }
        local parts = {}
        for i, idx in ipairs(which[3]) do table.insert(parts, labels[i] .. "=" .. Show(r[idx])) end
        ns.Print(which[1] .. ": " .. table.concat(parts, "  "))
    end
    ns.Print("UnitCastingDuration " .. (_G.UnitCastingDuration and "available" or "missing")
        .. ", UnitChannelDuration " .. (_G.UnitChannelDuration and "available" or "missing"))
    local c = cast
    if not c then
        ns.Print("Ring: no cast followed" .. (Watching() and "" or " (not watching this target)"))
        return
    end
    local how = c.endedAt and ("ended: " .. tostring(c.how))
        or (c.real and "game's times") or (c.start and "own time (learned or listed)")
        or (c.durObj and "game's timer display") or "no timing (ring full)"
    ns.Print("Ring: " .. tostring(c.name) .. " (spellID " .. tostring(c.spellID) .. ", "
        .. (c.channel and "channel" or "cast") .. ") - " .. how)
end
ns.RegisterCommand({ "targetdebug" }, TargetCastDebug) -- what the game hides about your target's cast

-- Shared with the files loaded after this one.
ns.targetCastRing = targetCastRing
ns.PreviewTargetCastRing = function() targetCastRing.Preview(10) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "targetCast", name = "Target Cast", order = 14.5, since = "1.2.0",
    iconBg = true, -- the icon can be the ring's background (Core/Settings.lua, UI/OptionsKit.lua)
    ring = targetCastRing,
    preview = ns.PreviewTargetCastRing, slash = { "target", "targetcast" }, help = "preview the target cast ring",
    toggle = { "Target cast ring", "What your target is casting, and whether you can interrupt it." },
    gameBar = "the game's target cast bar",
    alwaysInCombat = true, -- mostly for combat: no "Show in combat" option, never faded out in a fight
    defaults = {
        -- Target cast ring: your target's casts and channels. Below the cast ring.
        targetCastEnabled     = true,
        targetCastIcon        = true,
        targetCastName        = true,  -- the caster's name under the time
        targetCastHostileOnly = false, -- only targets you can attack
        targetCastSelf        = true,  -- targeting yourself: show your own casts too
        targetCastSize        = 100,
        targetCastThickness   = 10,
        targetCastOpacity     = 100,
        targetCastX           = 0,
        targetCastFromTop     = 385,
        targetCastHold        = 1,
        targetCastStyle       = "smooth",
        targetCastBorder      = 2,
        targetCastColors = {
            cast        = { r = 1.00, g = 0.55, b = 0.20 },
            channel     = { r = 0.40, g = 0.80, b = 1.00 },
            shielded    = { r = 0.62, g = 0.62, b = 0.68 },
            done        = { r = 0.40, g = 0.90, b = 0.40 },
            interrupted = { r = 1.00, g = 0.30, b = 0.30 },
        },
    },
    page = { folder = "professions", order = 4, build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(13.5, "Target casting", "Target Cast Ring",
                "Fills while your target casts and drains while it channels, with the spell's icon, the time left "
                .. "and who's casting. A cast you can't interrupt turns the ring gray. When it ends the ring turns "
                .. "green (it went off) or red (interrupted), and an interrupted cast flashes the part it lost. If "
                .. "the game hides the target's cast timing, the ring keeps its own from the spell's cast time, and a * "
                .. "after the label means the time is the ring's own.",
                MergeTop(TopRow("targetCast", "target cast ring", ns.PreviewTargetCastRing,
                    "Show a sample cast that goes off, one that's interrupted, then a channel you can't interrupt. "
                    .. "Also /circ target."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "targetCastEnabled", "Show target cast ring",
                            "Show the ring while your target casts or channels."),
                        icon = Toggle(2, "targetCastIcon", "Show spell icon", "The spell's icon on the ring."),
                        name = Toggle(3, "targetCastName", "Show caster's name",
                            "Your target's name under the time (the label says \"Can't interrupt\" instead when it can't be)."),
                        hostile = Toggle(4, "targetCastHostileOnly", "Enemies only",
                            "Only for targets you can attack, not friendly players or NPCs."),
                        self = Toggle(5, "targetCastSelf", "Include yourself",
                            "When you target yourself, show your own casts here too (the cast ring shows them as well).",
                            nil),
                    }),
                    colors = Box(3, "Colors", {
                        cast = Color(1, "targetCastColors", "cast", "Casting", "Ring color while your target casts."),
                        channel = Color(2, "targetCastColors", "channel", "Channeling", "Ring color while it channels."),
                        shielded = Color(3, "targetCastColors", "shielded", "Can't interrupt",
                            "Ring color for a cast or channel you can't interrupt."),
                        done = Color(4, "targetCastColors", "done", "Done", "Ring color when the cast goes off."),
                        interrupted = Color(5, "targetCastColors", "interrupted", "Interrupted",
                            "Ring color when it's interrupted or fails."),
                    }),
                    size = SizeBox(4, "targetCast", "target cast ring",
                        "Offset from the center of the screen. By default it sits below the cast ring."),
                }))
            tab.args.size.args.hold.desc = "How long the ring stays after the cast ends."
            tab.args.size.args.hold.min = 0.5
            tab.args.size.args.hold.step = 0.5
            return tab
        end },
})
