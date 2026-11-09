-- Circlet: Cast ring: your own casts and channels, timed even when combat hides them.
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing = ns.db, ns.IsSecret, ns.CreateLiveRing

---------------------------------------------------------------------------
-- Cast ring
---------------------------------------------------------------------------
-- Fills while you cast (drains while you channel), with the spell's icon and the time
-- left. In combat the client hides cast timing from addons, but still says which spell
-- started and when it ends, so, like the totem rings, the ring keeps its own time:
--   1. the real start/end times when they're readable (out of combat, and they also
--      teach the ring how long each spell takes);
--   2. the spell's cast time from its spell data (it includes your haste);
--   3. what the ring learned for that spell (channels have no listed cast time).
-- The ring snaps to the real end (done / interrupted) when the game reports it. What
-- it can't see in combat is pushback, so a pushed-back cast runs a little long.
-- Crafts and gathers are left to their own rings.

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e, f, g, h, i = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i end
end

local function Clean(v) return (v ~= nil and not IsSecret(v)) and v or nil end

local function Learned()
    db.castTimes = db.castTimes or {}
    return db.castTimes
end

local cast -- { spellID, guid, name, icon, channel, start, finish, real, endedAt, how, lost }

-- The game's own timing for the current cast, if it isn't hidden: start, finish (seconds).
local function RealTimes(channel)
    local fn = channel and UnitChannelInfo or UnitCastingInfo
    local name, _, _, startMS, endMS = SafeCall(fn, "player")
    startMS, endMS = Clean(startMS), Clean(endMS)
    if name and type(startMS) == "number" and type(endMS) == "number" and endMS > startMS then
        return startMS / 1000, endMS / 1000
    end
end

local function ListedCastTime(spellID)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local info = SafeCall(C_Spell.GetSpellInfo, spellID)
    local ms = type(info) == "table" and Clean(info.castTime) or nil
    if type(ms) == "number" and ms > 0 then return ms / 1000 end
end

local function Progress(now)
    if not (cast and cast.start and cast.finish) then return nil end
    local span = cast.finish - cast.start
    if span <= 0 then return nil end
    return math.max(0, math.min(1, (now - cast.start) / span)), math.max(0, cast.finish - now)
end

local function State(name, icon, channel, frac, left, ended, how, lost, endedAt, guessed)
    local c = db.castColors
    local st = { title = name or "Casting", color = channel and c.channel or c.cast,
                 icon = db.castIcon and icon or nil, hold = db.castHold or 1 }
    if ended then
        if how == "done" then
            st.frac, st.color, st.labelColor, st.label, st.value = 1, c.done, c.done, channel and "Done" or "Cast", ""
        else
            st.frac = channel and (frac or 0) or 0
            st.color, st.labelColor = c.interrupted, c.interrupted
            st.label, st.value = how == "failed" and "Failed" or "Interrupted", ""
            if not channel and lost and lost > 0 then
                st.flashFrom, st.flashTo, st.flashAt = 0, lost, endedAt
            end
        end
        return st
    end
    if not frac then
        -- No timing at all (a new channel in combat): just the spell, ring full.
        st.frac, st.value, st.label = 1, "", channel and "Channeling" or "Casting"
        return st
    end
    st.frac = channel and (1 - frac) or frac
    st.value = string.format(left >= 10 and "%.0f" or "%.1f", left)
    st.label = channel and "Channeling" or "Casting"
    if guessed then st.label = st.label .. "*" end
    return st
end

local castRing = CreateLiveRing({
    key = "cast",
    read = function(now)
        local c = cast
        if not c then return nil end
        -- A craft or gather that started with this cast belongs to its own ring.
        if (ns.CraftActive and ns.CraftActive()) or (ns.GatherActive and ns.GatherActive()) then
            cast = nil
            return nil
        end
        if c.endedAt then
            if now - c.endedAt > 0.1 then return nil end -- the end state shows once; the ring holds it
            return State(c.name, c.icon, c.channel, c.lost or 1, 0, true, c.how, c.lost, c.endedAt)
        end
        -- Out of combat the real times are readable, pushback included.
        local s, f = RealTimes(c.channel)
        if s then
            c.start, c.finish, c.real = s, f, true
            if c.spellID then Learned()[c.spellID] = f - s end
        end
        local frac, left = Progress(now)
        return State(c.name, c.icon, c.channel, frac, left or 0, false, nil, nil, nil, frac and not c.real)
    end,
    sample = function(t)
        local cycle = t % 6
        local icon = "Interface\\Icons\\Spell_Fire_FlameBolt"
        if cycle < 2.5 then return State("Fireball", icon, false, cycle / 2.5, 2.5 - cycle) end
        if cycle < 3.2 then return State("Fireball", icon, false, 1, 0, true, "done") end
        if cycle < 4.6 then return State("Fireball", icon, false, (cycle - 3.2) / 2.5, 2.5 - (cycle - 3.2)) end
        return State("Fireball", icon, false, 0.56, 0, true, "interrupted", 0.56, GetTime() - (cycle - 4.6))
    end,
})

local function Begin(spellID, guid, channel)
    if not db.castEnabled then return end
    -- Crafts and gathers have their own rings.
    if (ns.CraftActive and ns.CraftActive()) or (ns.GatherActive and ns.GatherActive()) then return end
    spellID = Clean(spellID)
    local name = spellID and C_Spell and C_Spell.GetSpellName and Clean(SafeCall(C_Spell.GetSpellName, spellID))
    local icon = spellID and C_Spell and C_Spell.GetSpellTexture and Clean(SafeCall(C_Spell.GetSpellTexture, spellID))
    if not name then
        local n, _, tex = SafeCall(channel and UnitChannelInfo or UnitCastingInfo, "player")
        name, icon = Clean(n), icon or Clean(tex)
    end
    local now = GetTime()
    cast = { spellID = spellID, guid = Clean(guid), name = name, icon = icon, channel = channel }
    local s, f = RealTimes(channel)
    if s then
        cast.start, cast.finish, cast.real = s, f, true
        if spellID then Learned()[spellID] = f - s end
        return
    end
    local dur = (not channel and spellID and ListedCastTime(spellID)) or (spellID and Learned()[spellID])
    if dur and dur > 0 then cast.start, cast.finish = now, now + dur end
end

local function Finish(how)
    local c = cast
    if not c or c.endedAt then return end
    local now = GetTime()
    if how ~= "done" then c.lost = Progress(now) end
    c.how, c.endedAt = how, now
end

-- An event about our current cast? (Instant spells fire SUCCEEDED with no START.)
local function Ours(guid, spellID)
    if not cast or cast.endedAt then return false end
    guid, spellID = Clean(guid), Clean(spellID)
    if guid and cast.guid then return guid == cast.guid end
    if spellID and cast.spellID then return spellID == cast.spellID end
    return true
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
                     "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_CHANNEL_START",
                     "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    pcall(events.RegisterUnitEvent, events, e, "player")
end
events:SetScript("OnEvent", function(_, event, _, guid, spellID)
    if not CircletDB then return end
    if event == "UNIT_SPELLCAST_START" then
        Begin(spellID, guid, false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        Begin(spellID, guid, true)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if Ours(guid, spellID) and not cast.channel then Finish("done") end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if Ours(guid, spellID) then Finish(cast.channel and "done" or "interrupted") end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        if Ours(guid, spellID) and not cast.channel then Finish("failed") end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if cast and cast.channel and not cast.endedAt then
            -- Channels end early when interrupted or moved; otherwise they run out.
            local frac = Progress(GetTime())
            Finish((frac and frac < 0.95) and "interrupted" or "done")
        end
    elseif event == "UNIT_SPELLCAST_STOP" then
        -- The cast is over. Interrupts and failures arrive first as their own events, so
        -- reaching this still running means it went off (same as the game's cast bar).
        if Ours(guid, spellID) and not cast.channel then Finish("done") end
    end
end)

-- Shared with the files loaded after this one.
ns.castRing = castRing
ns.CastActive = function() return cast ~= nil and cast.endedAt == nil end
ns.PreviewCastRing = function() castRing.Preview(12) end
