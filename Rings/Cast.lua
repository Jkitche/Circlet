-- Circlet: Cast ring: your own casts and channels, timed even when combat hides them.
local ADDON_NAME, ns = ...

local db, CreateLiveRing = ns.db, ns.CreateLiveRing
local SafeCall, Clean = ns.SafeCall, ns.Clean

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
-- Crafts and gathers are left to their own rings. Resurrect spells get an animation of
-- their own (below), and with castSchoolFx on other spells get an effect for their school
-- (Rings/CastSchools.lua). With castFollow on, a cast at something you're interacting with (a
-- chest, a quest object, a corpse...) puts the ring on it (Layout/Follow.lua).

local function Learned()
    db.castTimes = db.castTimes or {}
    return db.castTimes
end

local cast -- { spellID, guid, name, icon, channel, rez, start, finish, real, endedAt, how, lost }

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

---------------------------------------------------------------------------
-- Resurrection
---------------------------------------------------------------------------
-- While you cast a resurrect the ring fills in a soft holy gold, a halo breathes in its
-- middle and motes of light drift up through it, brighter as the cast nears its end.
-- When it goes off a pillar of light rises out of the ring, the ring flashes, a wave
-- rolls outward and the motes stream up and away. Interrupted, the light gutters out
-- and the motes sink. Everything is worked out from the time, so edit mode's sample
-- plays the same animation.

-- Spells that bring someone back. Any rank counts: these are matched by name as well.
local RESURRECT_SPELLS = {
    2006, 2010, 10880, 10881, 20770,     -- Resurrection (priest)
    7328, 10322, 10324, 20772, 20773,    -- Redemption (paladin)
    2008, 20609, 20610, 20776, 20777,    -- Ancestral Spirit (shaman)
    20484, 20739, 20742, 20747, 20748,   -- Rebirth (druid, in combat)
    50769,  -- Revive (druid)
    115178, -- Resuscitate (monk)
    361227, -- Return (evoker)
    61999,  -- Raise Ally (death knight)
    391054, -- Intercession (paladin)
    212036, -- Mass Resurrection (priest)
    212056, -- Absolution (paladin)
    212048, -- Ancestral Vision (shaman)
    212040, -- Revitalize (druid)
    212051, -- Reawaken (monk)
    361178, -- Mass Return (evoker)
    83968,  -- Mass Resurrection (guild perk)
}
local rezIDs = {}
for _, id in ipairs(RESURRECT_SPELLS) do rezIDs[id] = true end
local rezNames -- built on first use, once spell names can be read

local function IsResurrect(spellID, name)
    if spellID and rezIDs[spellID] then return true end
    if not name then return false end
    if not rezNames then
        local names, any = {}, false
        for _, id in ipairs(RESURRECT_SPELLS) do
            local n = ns.SpellName(id)
            if n then names[n], any = true, true end
        end
        if any then rezNames = names end -- try again later if nothing could be read yet
        return names[name] == true
    end
    return rezNames[name] == true
end

local REZ_MOTES   = 12
local REZ_BURST   = 1.6  -- seconds the burst runs after the cast goes off
local REZ_FADE    = 0.45 -- seconds the light takes to gutter out when it's cut short
local REZ_HOLD    = 2.0  -- the ring stays at least this long after a resurrect goes off
local GLOW_TEX    = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR_TEX    = "Interface\\Cooldown\\star4"
local WHITE       = { r = 1, g = 1, b = 1 }

local function EaseOut(t) return 1 - (1 - t) ^ 2 end

-- c mixed toward white by w (0..1).
local function Lighten(c, w)
    return c.r + (1 - c.r) * w, c.g + (1 - c.g) * w, c.b + (1 - c.b) * w
end

local fx -- the effect's textures and lines, made on the cast ring's frame on first use

local function SoftGlow(frame, layer, sub)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    if t:SetTexture(GLOW_TEX) == false then t:SetTexture(STAR_TEX) end
    t:SetBlendMode("ADD")
    t:Hide()
    return t
end

local function BuildFx(frame)
    fx = { motes = {}, glowGeom = {}, waveGeom = {} }
    fx.halo   = SoftGlow(frame, "BACKGROUND", -7) -- behind the track, in the ring's hollow
    fx.pillar = SoftGlow(frame, "BORDER", 0)
    fx.core   = SoftGlow(frame, "BORDER", 1)
    fx.glow   = ns.NewRingLayer("OVERLAY", 2, WHITE, 1, frame)
    fx.wave   = ns.NewRingLayer("OVERLAY", 3, WHITE, 1, frame)
    for i = 1, REZ_MOTES do
        local t = frame:CreateTexture(nil, "ARTWORK", nil, 2) -- under the ring's text
        t:SetTexture(STAR_TEX)
        t:SetBlendMode("ADD")
        t:Hide()
        -- Fixed per mote, so they don't move in lockstep: speed (rises per second),
        -- where in its rise it starts, which side it drifts up, how much it sways, size.
        fx.motes[i] = { tex = t, speed = 1 / (1.5 + (i * 0.37) % 0.9), phase = (i * 0.618) % 1,
                        side = ((i * 0.437) % 1) * 2 - 1, sway = 0.08 + (i * 0.29) % 0.12,
                        size = 0.7 + (i * 0.53) % 0.6 }
    end
end

local function HideFx()
    if not fx then return end
    fx.halo:Hide(); fx.pillar:Hide(); fx.core:Hide()
    for _, l in ipairs(fx.glow) do l:Hide() end
    for _, l in ipairs(fx.wave) do l:Hide() end
    for _, m in ipairs(fx.motes) do m.tex:Hide() end
end

-- A full ring (or the ring's arc) of radius R and band T, in color r, g, b at alpha a.
local function DrawBand(lines, g, geom, frame, R, T, r, gr, b, a)
    g.R, g.T, g.start, g.sweep, g.step, g.reverse = R, T, geom.start, geom.sweep, geom.step, geom.reverse
    for _, l in ipairs(lines) do l:SetColorTexture(r, gr, b, a) end
    ns.DrawArc(lines, 0, 1, frame, g, true)
end

local function DrawRezFx(st, frame, geom)
    if not (st and st.rez) or not geom or geom.R <= 0 then return HideFx() end
    if not fx then BuildFx(frame) end
    local now = GetTime()
    local c = db.castColors.rez or db.castColors.cast
    local ri = math.max(4, geom.R - geom.T / 2) -- the hollow's radius
    local phase = st.rez
    local age = st.rezAt and math.max(0, now - st.rezAt) or 0
    local breathe = math.sin(now * 2 * math.pi * 0.7)

    -- How lit the halo and motes are: building up while casting, then fading.
    local lit
    if phase == "cast" then
        lit = 0.45 + 0.55 * (st.rezFrac or 0.6)
    elseif phase == "done" then
        lit = math.max(0, 1 - age / REZ_BURST)
    else
        lit = math.max(0, 1 - age / REZ_FADE)
    end

    -- Halo: breathes while casting, swells when the cast goes off.
    local swell = phase == "done" and 0.6 * EaseOut(math.min(1, age / 0.5)) or 0
    local hs = ri * 2.3 * (1 + 0.06 * breathe + swell)
    fx.halo:SetSize(hs, hs)
    fx.halo:ClearAllPoints()
    fx.halo:SetPoint("CENTER", frame, "CENTER", 0, 0)
    fx.halo:SetVertexColor(Lighten(c, 0.2))
    fx.halo:SetAlpha(lit * (0.4 + 0.1 * breathe))
    fx.halo:SetShown(lit > 0)

    -- Motes: drift up through the hollow, swaying, fading in and out. Once the cast is
    -- over they stream up and away (it went off) or sink (it didn't).
    local mr, mg, mb = Lighten(c, 0.45)
    local endT = st.rezAt or now
    for i, m in ipairs(fx.motes) do
        local u = ((phase == "cast" and now or endT) * m.speed + m.phase) % 1
        local y = ri * (-0.75 + 1.5 * u)
        local across = math.sqrt(math.max(0, 1 - (y / ri) ^ 2))
        local x = (m.side * 0.65 + math.sin(u * 2 * math.pi * 1.3 + i) * m.sway) * ri * across
        local a = math.sin(math.pi * u) * lit
        local size = ri * 0.2 * m.size * (0.6 + 0.4 * math.sin(math.pi * u))
        if phase == "done" then
            local mt = math.min(1, age / 1.1)
            y = y + ri * 2.6 * EaseOut(mt) * (0.8 + 0.4 * m.speed)
            a = (1 - mt) * (0.5 + 0.5 * math.sin(math.pi * u))
            size = size * (1 + 0.5 * mt)
        elseif phase ~= "cast" then
            y = y - ri * 0.4 * math.min(1, age / REZ_FADE)
        end
        m.tex:ClearAllPoints()
        m.tex:SetPoint("CENTER", frame, "CENTER", x, y)
        m.tex:SetSize(size, size)
        m.tex:SetVertexColor(mr, mg, mb)
        m.tex:SetAlpha(a)
        m.tex:SetShown(a > 0.01)
    end

    if phase ~= "done" then
        fx.pillar:Hide(); fx.core:Hide()
        for _, l in ipairs(fx.glow) do l:Hide() end
        for _, l in ipairs(fx.wave) do l:Hide() end
        return
    end

    -- Pillar of light: shoots up out of the ring, thinning as it fades.
    local pt = age / 1.3
    if pt < 1 then
        local h = ri * (1.5 + 5 * EaseOut(math.min(1, pt * 1.6)))
        local w = ri * 1.5 * (1 - 0.55 * pt)
        local a = (pt < 0.12 and pt / 0.12 or 1 - (pt - 0.12) / 0.88) * 0.9
        local base = -ri * 0.7 -- the pillar's foot, low in the hollow
        fx.pillar:ClearAllPoints()
        fx.pillar:SetPoint("CENTER", frame, "CENTER", 0, base + h / 2)
        fx.pillar:SetSize(w, h)
        fx.pillar:SetVertexColor(Lighten(c, 0.3))
        fx.pillar:SetAlpha(a)
        fx.pillar:Show()
        fx.core:ClearAllPoints()
        fx.core:SetPoint("CENTER", frame, "CENTER", 0, base + h / 2)
        fx.core:SetSize(w * 0.35, h * 0.95)
        fx.core:SetVertexColor(1, 1, 1)
        fx.core:SetAlpha(a)
        fx.core:Show()
    else
        fx.pillar:Hide(); fx.core:Hide()
    end

    -- The ring flashes, up and back down.
    local gt = age / 0.6
    if gt < 1 then
        local r, g, b = Lighten(c, 0.5)
        DrawBand(fx.glow, fx.glowGeom, geom, frame, geom.R, geom.T + 4, r, g, b, math.sin(math.pi * gt) * 0.85)
    else
        for _, l in ipairs(fx.glow) do l:Hide() end
    end

    -- A wave rolls out from the ring, thinning as it goes.
    local wt = (age - 0.08) / 0.9
    if wt >= 0 and wt < 1 then
        local r, g, b = Lighten(c, 0.15)
        DrawBand(fx.wave, fx.waveGeom, geom, frame, geom.R * (1 + 0.65 * EaseOut(wt)),
            math.max(1.5, geom.T * 0.8 * (1 - wt)), r, g, b, 1 - wt)
    else
        for _, l in ipairs(fx.wave) do l:Hide() end
    end
end

-- interact: the cast was at something you're interacting with (a chest, a quest object):
-- its icon bursts when it goes off, like a gather. Spells don't burst.
local function State(name, icon, channel, frac, left, ended, how, lost, endedAt, guessed, rez, interact)
    local c = db.castColors
    rez = rez and db.castRezFx
    local st = { title = name or "Casting", color = channel and c.channel or c.cast,
                 icon = db.castIcon and icon or nil, hold = db.castHold or 1 }
    if ended then
        if how == "done" then
            st.frac, st.color, st.labelColor, st.label, st.value = 1, c.done, c.done, channel and "Done" or "Cast", ""
            st.doneAt, st.noBurst = endedAt, not interact
            if rez then
                st.rez, st.rezAt, st.hold = "done", endedAt, math.max(st.hold, REZ_HOLD)
            end
        else
            if rez then st.rez, st.rezAt = how, endedAt end
            st.frac = channel and (frac or 0) or 0
            st.color, st.labelColor = c.interrupted, c.interrupted
            st.label, st.value = how == "failed" and "Failed" or "Interrupted", ""
            if not channel and lost and lost > 0 then
                st.flashFrom, st.flashTo, st.flashAt = 0, lost, endedAt
            end
        end
        return st
    end
    local doing = rez and "Resurrecting" or channel and "Channeling" or "Casting"
    if rez then st.rez, st.rezFrac, st.color = "cast", frac, c.rez or c.cast end
    if not frac then
        -- No timing at all (a new channel in combat): just the spell, ring full.
        st.frac, st.value, st.label = 1, "", doing
        return st
    end
    st.frac = channel and (1 - frac) or frac
    st.value = string.format(left >= 10 and "%.0f" or "%.1f", left)
    st.label = doing
    if guessed then st.label = st.label .. "*" end
    return st
end

-- Adds the spell-school effect to a state (not for a resurrect, which has its own):
-- how far the cast is, or how and when it ended.
local function WithSchool(st, school, frac, how, endedAt)
    if st and school and db.castSchoolFx and not st.rez then
        st.school = school
        if how then st.schoolEnd, st.schoolAt = how, endedAt else st.schoolFrac = frac end
    end
    return st
end

-- Edit mode's sample spells, one per school, taken two at a time (one goes off, one is
-- interrupted) so every school comes round.
local SAMPLES = {
    { "Fireball", "Interface\\Icons\\Spell_Fire_FlameBolt", "fire" },
    { "Frostbolt", "Interface\\Icons\\Spell_Frost_FrostBolt02", "frost" },
    { "Arcane Missiles", "Interface\\Icons\\Spell_Nature_StarFall", "arcane" },
    { "Shadow Bolt", "Interface\\Icons\\Spell_Shadow_ShadowBolt", "shadow" },
    { "Wrath", "Interface\\Icons\\Spell_Nature_AbolishMagic", "nature" },
    { "Smite", "Interface\\Icons\\Spell_Holy_HolySmite", "holy" },
}

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
        if not c.school then c.school = ns.SpellSchool(c.spellID, c.name, c.icon) end -- the log may name it late
        if c.endedAt then
            if now - c.endedAt > 0.1 then return nil end -- the end state shows once; the ring holds it
            return WithSchool(State(c.name, c.icon, c.channel, c.lost or 1, 0, true, c.how, c.lost, c.endedAt, nil,
                c.rez, c.interact), c.school, nil, c.how, c.endedAt)
        end
        -- Out of combat the real times are readable, pushback included.
        local s, f = RealTimes(c.channel)
        if s then
            c.start, c.finish, c.real = s, f, true
            if c.spellID then Learned()[c.spellID] = f - s end
        end
        local frac, left = Progress(now)
        return WithSchool(State(c.name, c.icon, c.channel, frac, left or 0, false, nil, nil, nil, frac and not c.real, c.rez),
            c.school, frac)
    end,
    sample = function(t)
        -- A cast that goes off, one that's interrupted (each round, the next two schools:
        -- Fireball and Frostbolt first), then (with the resurrection animation on) a Resurrection.
        local period = db.castRezFx and 10.5 or 6
        local cycle, round = t % period, math.floor(t / period)
        local a, b = SAMPLES[(2 * round) % #SAMPLES + 1], SAMPLES[(2 * round + 1) % #SAMPLES + 1]
        if cycle < 2.5 then return WithSchool(State(a[1], a[2], false, cycle / 2.5, 2.5 - cycle), a[3], cycle / 2.5) end
        if cycle < 3.2 then
            local at = GetTime() - (cycle - 2.5)
            return WithSchool(State(a[1], a[2], false, 1, 0, true, "done", nil, at), a[3], nil, "done", at)
        end
        if cycle < 4.6 then
            local f = (cycle - 3.2) / 2.5
            return WithSchool(State(b[1], b[2], false, f, 2.5 - (cycle - 3.2)), b[3], f)
        end
        if cycle < 6 then
            local at = GetTime() - (cycle - 4.6)
            return WithSchool(State(b[1], b[2], false, 0.56, 0, true, "interrupted", 0.56, at), b[3], nil, "interrupted", at)
        end
        local rez = "Interface\\Icons\\Spell_Holy_Resurrection"
        if cycle < 9 then
            return State("Resurrection", rez, false, (cycle - 6) / 3, 3 - (cycle - 6), false, nil, nil, nil, nil, true)
        end
        return State("Resurrection", rez, false, 1, 0, true, "done", nil, GetTime() - (cycle - 9), nil, true)
    end,
    decorate = function(st, frame, geom)
        DrawRezFx(st, frame, geom)
        ns.DrawSchoolFx(st, frame, geom)
    end,
    follow = function(frame)
        if cast and db.castFollow then return ns.FollowPoint(cast.follow, frame) end -- (x, y: no and/or)
    end,
})

local function Begin(spellID, guid, channel)
    if not db.castEnabled then return end
    -- Crafts and gathers have their own rings.
    if (ns.CraftActive and ns.CraftActive()) or (ns.GatherActive and ns.GatherActive()) then return end
    spellID = Clean(spellID)
    local name = spellID and ns.SpellName(spellID)
    local icon = spellID and ns.SpellIcon(spellID)
    if not name then
        local n, _, tex = SafeCall(channel and UnitChannelInfo or UnitCastingInfo, "player")
        name, icon = Clean(n), icon or Clean(tex)
    end
    local now = GetTime()
    cast = { spellID = spellID, guid = Clean(guid), name = name, icon = icon, channel = channel,
             rez = IsResurrect(spellID, name) }
    -- At something you're interacting with? (It bursts when done, and the ring can follow it.)
    local target = ns.InteractTarget(guid, spellID)
    cast.interact = target ~= nil
    cast.follow = db.castFollow and target or nil
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

ns.Listen({ "UNIT_SPELLCAST_START:player", "UNIT_SPELLCAST_STOP:player", "UNIT_SPELLCAST_SUCCEEDED:player", "UNIT_SPELLCAST_INTERRUPTED:player", "UNIT_SPELLCAST_FAILED:player", "UNIT_SPELLCAST_CHANNEL_START:player", "UNIT_SPELLCAST_CHANNEL_STOP:player" }, function(event, _, guid, spellID)
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
ns.PreviewCastRing = function() castRing.Preview(db.castRezFx and 11 or 12) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "cast", name = "Cast", order = 14,
    iconBg = true, -- the icon can be the ring's background (Core/Settings.lua, UI/OptionsKit.lua)
    ring = castRing,
    preview = ns.PreviewCastRing, slash = { "cast", "casting" }, help = "preview the cast ring",
    toggle = { "Cast ring", "Your casts and channels, timed even in combat." },
    gameBar = "the game's cast bar",
    defaults = {
        -- Cast ring: your casts and channels, timed even in combat. Shares the crafting
        -- ring's spot (crafts and gathers are left to their own rings).
        castEnabled   = true,
        castIcon      = true,
        castSize      = 100,
        castThickness = 10,
        castOpacity   = 100,
        castX         = 0,
        castFromTop   = 265,
        castHold      = 1,
        castRezFx     = true, -- the resurrection animation (resurrect spells)
        castSchoolFx  = true, -- an effect for the spell's school (Rings/CastSchools.lua)
        castSchoolFxStrength = 100, -- % brightness of that effect
        castFollow    = false, -- a cast at what you're interacting with puts the ring on it (Layout/Follow.lua)
        castStyle     = "smooth",
        castBorder    = 2,
        castColors = {
            cast        = { r = 1.00, g = 0.75, b = 0.20 },
            channel     = { r = 0.40, g = 0.80, b = 1.00 },
            done        = { r = 0.40, g = 0.90, b = 0.40 },
            interrupted = { r = 1.00, g = 0.30, b = 0.30 },
            rez         = { r = 1.00, g = 0.90, b = 0.55 },
        },
    },
    page = { folder = "professions", order = 3, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(13, "Casting", "Cast Ring",
                "Fills while you cast and drains while you channel, with the spell's icon and the time left. In combat "
                .. "the game hides cast timing from addons, so the ring keeps its own time from the spell's cast time "
                .. "(or how long it took when it last could see), and snaps to the real end when the cast goes off or "
                .. "is interrupted. It can't see pushback in combat, so a pushed-back cast runs a little long. A * after "
                .. "\"Casting\" means the time is the ring's own. Spells get an effect for their school, and resurrects an "
                .. "animation of their own. Crafts and gathers use their own rings.",
                MergeTop(TopRow("cast", "cast ring", ns.PreviewCastRing,
                    "Show a sample cast that goes off, one that's interrupted, then a resurrect. Also /circ cast."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "castEnabled", "Show cast ring", "Show the ring while you cast or channel."),
                        icon = Toggle(2, "castIcon", "Show spell icon", "The spell's icon on the ring."),
                        schoolFx = Toggle(2.5, "castSchoolFx", "Spell school effects",
                            "An effect in the ring for the spell's school while you cast: embers for fire, "
                            .. "snowflakes for frost, orbiting motes for arcane, wisps for shadow, a swirl for nature "
                            .. "and turning rays for holy. Physical and unknown spells have none."),
                        schoolFxStrength = Range(2.6, "castSchoolFxStrength", "Effect strength", 25, 200, 5,
                            "How bright the spell school effects are. 100% is the default; lower is subtler.",
                            { disabled = function() return not db.castSchoolFx end }),
                        rezFx = Toggle(3, "castRezFx", "Resurrection animation",
                            "When you cast a resurrect, motes of light rise through the ring, and a pillar of "
                            .. "light shoots up when it goes off."),
                        follow = Toggle(4, "castFollow", "Follow what you're interacting with",
                            "When a cast is at something you're interacting with (opening a chest, using a quest "
                            .. "object, a corpse), the ring sits on it and moves with it as you turn the camera. Turns "
                            .. "on the game's nameplate for what you're facing (soft interact must be on); turning "
                            .. "this off sets it back. If it doesn't follow, /circ follow shows why.",
                            function() ns.ApplyFollowCVar() end),
                    }),
                    colors = Box(3, "Colors", {
                        cast = Color(1, "castColors", "cast", "Casting", "Ring color while casting."),
                        channel = Color(2, "castColors", "channel", "Channeling", "Ring color while channeling."),
                        done = Color(3, "castColors", "done", "Done", "Ring color when the cast goes off."),
                        interrupted = Color(4, "castColors", "interrupted", "Interrupted", "Ring color when it's interrupted or fails."),
                        rez = Color(5, "castColors", "rez", "Resurrecting",
                            "Ring and light color while you cast a resurrect (with the resurrection animation on)."),
                    }),
                    size = SizeBox(4, "cast", "cast ring",
                        "Offset from the center of the screen. By default it shares the crafting ring's spot."),
                }))
            tab.args.size.args.hold.desc = "How long the ring stays after the cast ends."
            tab.args.size.args.hold.min = 0.5
            tab.args.size.args.hold.step = 0.5
            return tab
        end },
})
