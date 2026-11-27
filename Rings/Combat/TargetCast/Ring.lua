-- Circlet: Target cast ring: following your target's cast, the ring itself, its events and /circ targetdebug.
local _, ns = ...

local db, CreateLiveRing = ns.db, ns.CreateLiveRing
local SafeCall, Clean, IsSecret = ns.SafeCall, ns.Clean, ns.IsSecret
local TC = ns.TargetCastRing
local UNIT = TC.UNIT
local Learn = TC.Learn
local LearnedTime = TC.LearnedTime
local ListedCastTime = TC.ListedCastTime
local DurationObject = TC.DurationObject
local ReadablePercent = TC.ReadablePercent
local Gate = TC.Gate
local NoteMode = TC.NoteMode
local HideTimer = TC.HideTimer
local RingTexture = TC.RingTexture
local ShowTimer = TC.ShowTimer
local ShowNumbers = TC.ShowNumbers

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
    if not (TC.cast and TC.cast.start and TC.cast.finish) then return nil end
    local span = TC.cast.finish - TC.cast.start
    if span <= 0 then return nil end
    return math.max(0, math.min(1, (now - TC.cast.start) / span)), math.max(0, TC.cast.finish - now)
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
    if not Watching() then TC.cast = nil return end
    local name, icon, s, f, shielded, infoID = Info(channel)
    if not name and not s and not Clean(spellID) then
        -- Nothing readable at all: maybe it's casting nothing (a new target).
        if not SafeCall(channel and UnitChannelInfo or UnitCastingInfo, UNIT) then TC.cast = nil return end
    end
    spellID = Clean(spellID) or infoID
    local now = GetTime()
    TC.cast = { castID = Clean(castID), spellID = spellID, channel = channel, shielded = shielded and true or false,
             name = name or (spellID and ns.SpellName(spellID)) or "Casting",
             icon = icon or (spellID and ns.SpellIcon(spellID)), caster = CasterName() }
    if s then
        TC.cast.start, TC.cast.finish, TC.cast.real = s, f, true
        Learn(TC.cast)
        return
    end
    -- Times hidden: what this spell took before, or its listed cast time.
    local dur = LearnedTime(TC.cast) or (not channel and spellID and ListedCastTime(spellID))
    if dur and dur > 0 then TC.cast.start, TC.cast.finish = now, now + dur end
end

-- A new target: show what it's casting now, if anything (no end animation for the old one).
local function Retarget()
    TC.cast = nil
    if not Watching() then return end
    if SafeCall(UnitChannelInfo, UNIT) then
        Begin(true)
    elseif SafeCall(UnitCastingInfo, UNIT) then
        Begin(false)
    end
end

local function Finish(how)
    local c = TC.cast
    if not c or c.endedAt then return end
    local now = GetTime()
    if how ~= "done" then c.lost = Progress(now) end
    c.how, c.endedAt = how, now
end

-- An event about the cast we're following?
local function Ours(castID, spellID)
    if not TC.cast or TC.cast.endedAt then return false end
    castID, spellID = Clean(castID), Clean(spellID)
    if castID and TC.cast.castID then return castID == TC.cast.castID end
    if spellID and TC.cast.spellID then return spellID == TC.cast.spellID end
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
        local c = TC.cast
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
            -- No timing we can read: the cast's duration object, in order of preference:
            -- its progress as a plain number; the ring's segments gated by curves (decorate
            -- adds the game's countdown in the middle); the game's own sweep.
            if not (c.durObj or c.durTried) then
                c.durTried = true
                c.durObj = DurationObject(c.channel)
            end
            if c.durObj then
                local pct = ReadablePercent(c)
                if pct then
                    st.frac = pct -- (a channel's is already what's left)
                    local okR, left = pcall(c.durObj.GetRemainingDuration, c.durObj)
                    if okR and type(left) == "number" and not IsSecret(left) then
                        st.value = string.format(left >= 10 and "%.0f" or "%.1f", left)
                    end
                    NoteMode(c, "readable percent")
                else
                    if c.gate == nil then
                        local gate, why = Gate(c)
                        c.gate, c.gateWhy = gate or false, why
                    end
                    if c.gate then
                        st.frac, st.fillGate, st.timerNumbers = 1, c.gate, c
                        NoteMode(c, "segments gated by curve")
                    else
                        st.timerCast, st.frac = c, 0
                        NoteMode(c, "game's sweep", c.gateWhy)
                    end
                end
            end
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
        if st and st.timerNumbers and geom.R > 0 and ShowNumbers(st.timerNumbers, frame, geom) then return end
        if st and st.timerCast and geom.R > 0 and ShowTimer(st.timerCast, frame, geom, st.color) then return end
        HideTimer()
    end,
})

-- The same cast start arriving twice (as "target" and as "player" when you target
-- yourself): keep following the first.
local function AlreadyFollowing(castID)
    castID = Clean(castID)
    return TC.cast and not TC.cast.endedAt and castID and TC.cast.castID == castID
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
        if TC.cast and not TC.cast.endedAt then TC.cast.shielded = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" end
    elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        if TC.cast and not TC.cast.endedAt then
            local _, _, s, f = Info(TC.cast.channel)
            if s then TC.cast.start, TC.cast.finish, TC.cast.real = s, f, true end
            -- The game's timer (if it's showing) needs the updated duration.
            if TC.cast.durObj then
                TC.cast.durObj = DurationObject(TC.cast.channel) or TC.cast.durObj
                TC.cast.durStale = true
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if Ours(castID, spellID) and not TC.cast.channel then Finish("done") end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if Ours(castID, spellID) then Finish(TC.cast.channel and "done" or "interrupted") end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        if Ours(castID, spellID) and not TC.cast.channel then Finish("failed") end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if TC.cast and TC.cast.channel and not TC.cast.endedAt then
            -- Channels end early when interrupted; otherwise they run out.
            local frac = Progress(GetTime())
            Finish((frac and frac < 0.95) and "interrupted" or "done")
        end
    elseif event == "UNIT_SPELLCAST_STOP" then
        -- Interrupts and failures arrive first as their own events, so reaching this
        -- still running means it went off (same as the game's cast bar).
        if Ours(castID, spellID) and not TC.cast.channel then Finish("done") end
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

local probeTexture -- for checking the ring texture loads (made on first use)

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
    -- The game's timer, used when the times are hidden: how it's drawn, and whether the game
    -- can load the ring texture it sweeps with (if not, it falls back to a plain pie).
    local probe = RingTexture(0.8)
    probeTexture = probeTexture or UIParent:CreateTexture()
    local test = probeTexture
    local loaded = test:SetTexture(probe)
    local fileID = test.GetTextureFileID and test:GetTextureFileID()
    test:SetTexture(nil)
    local cdProbe = TC.timer and TC.timer.cd
    ns.Print("Timer: " .. (TC.timer and ((TC.timer:IsShown() and "showing" or "hidden") .. ", " .. tostring(TC.timer.mode)
            .. ", texture " .. tostring(TC.timer.texPath)) or "not made yet (no hidden-time cast seen)")
        .. "  |  Ring80 loads: " .. tostring(loaded) .. " (file ID " .. tostring(fileID) .. ")"
        .. "  |  SetSwipeTexture " .. ((cdProbe and cdProbe.SetSwipeTexture) and "yes" or (cdProbe and "no" or "?"))
        .. ", SetCooldownFromDurationObject " .. ((cdProbe and cdProbe.SetCooldownFromDurationObject) and "yes"
            or (cdProbe and "no" or "?")))
    local d = db.targetCastDiag
    if d then
        ns.Print("Last timer (" .. tostring(d.at) .. "): " .. tostring(d.mode) .. ", started: " .. tostring(d.fed)
            .. ", texture loads: " .. tostring(d.textureLoads))
        ns.Print("  tried: " .. tostring(d.attempts))
        ns.Print("  duration: " .. tostring(d.durationMethods))
        ns.Print("  C_DurationUtil: " .. tostring(d.durationUtil) .. "  |  cooldown: " .. tostring(d.cooldownMethods))
    end
    local c = TC.cast
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

-- For the files loaded after this one.
TC.targetCastRing = targetCastRing
