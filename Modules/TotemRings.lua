-- Circlet: Totem rings: a small ring per active shaman totem.
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing, FormatTime = ns.db, ns.IsSecret, ns.CreateLiveRing, ns.FormatTime

---------------------------------------------------------------------------
-- Totem rings
---------------------------------------------------------------------------
-- One small ring per totem element, in the totem bar's order (earth, fire, water,
-- air). Each shows the totem's icon in the middle with the time left, and the ring
-- drains in the element's color as it runs down. In the last 10 seconds it pulses.
-- An element with no totem down has no ring. Only for characters with totems.
--
-- In combat the client can hide totem times from addons (secret values). Then the
-- ring switches to the game's own cooldown display: the totem icon with a sweep and
-- countdown drawn by the game, fed GetTotemDuration's duration object, which addons
-- may display but not read. The ring itself stays as a plain track until the times
-- can be read again.
--
-- Usually it doesn't come to that: the ring keeps its own countdown going through
-- combat. A totem dropped before the fight was read in full, so its countdown just
-- continues. For one dropped mid-fight, the cast says which totem it was, and its
-- duration is known from earlier (learned per spell whenever times are readable,
-- kept in db.totemSpells). Only a totem never seen out of combat falls back to the
-- game's display.

local ELEMENTS = {
    -- display order: GetTotemInfo slot, element
    { slot = 2, element = "earth" },
    { slot = 1, element = "fire" },
    { slot = 3, element = "water" },
    { slot = 4, element = "air" },
}
local WARN_AT = 10

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g end
end

local function HasTotems()
    local _, class = UnitClass("player")
    return class == "SHAMAN"
end

local function State(element, left, duration, icon, name)
    local c = db.totemColors[element]
    local st = {
        title = nil, label = nil,
        value = left >= 60 and FormatTime(left) or tostring(math.max(0, math.ceil(left))),
        frac = duration > 0 and math.max(0, math.min(1, left / duration)) or 0,
        color = c, icon = icon, iconColor = c,
    }
    if db.totemWarn and left <= WARN_AT then
        -- Pulse: the ring and icon brighten and dim twice a second.
        local p = 0.5 + 0.5 * math.sin(GetTime() * 2 * math.pi * 2)
        st.color = { r = c.r + (1 - c.r) * p * 0.6, g = c.g + (1 - c.g) * p * 0.6, b = c.b + (1 - c.b) * p * 0.6 }
        st.iconAlpha = 0.6 + 0.4 * p
    end
    return st
end

local SAMPLE = { -- for edit mode / preview: { seconds left, duration, icon }
    { 95, 120, "Interface\\Icons\\Spell_Nature_StoneSkinTotem" },
    { 8, 20, "Interface\\Icons\\Spell_Fire_SearingTotem" },
    { 40, 60, "Interface\\Icons\\Spell_Nature_ManaRegenTotem" },
    { 110, 120, "Interface\\Icons\\Spell_Nature_Windfury" },
}

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Secret-mode widgets for ring i: an icon and a cooldown sweep in the middle.
local secret = {}
local maybeActive = {} -- slot -> a totem changed there while times were hidden
local known = {}       -- slot -> { start, duration, icon }: our own countdown for it

-- Remembers a totem spell's slot, duration and icon (whenever times are readable).
local function Learn(spellID, slot, duration, icon)
    if type(spellID) ~= "number" or IsSecret(spellID) or spellID <= 0 then return end
    db.totemSpells = db.totemSpells or {}
    db.totemSpells[spellID] = { slot = slot, duration = duration, icon = icon }
end

local function SecretWidgets(i, frame)
    local w = secret[i]
    if w then return w end
    w = CreateFrame("Frame", nil, frame)
    w:SetPoint("CENTER")
    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetAllPoints()
    w.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if w.CreateMaskTexture then
        w.mask = w:CreateMaskTexture()
        w.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        w.mask:SetAllPoints()
        w.icon:AddMaskTexture(w.mask)
    end
    w.cd = CreateFrame("Cooldown", nil, w, "CooldownFrameTemplate")
    w.cd:SetAllPoints()
    if w.cd.SetSwipeTexture then w.cd:SetSwipeTexture(CIRCLE) end
    if w.cd.SetDrawEdge then w.cd:SetDrawEdge(false) end
    if w.cd.SetDrawBling then w.cd:SetDrawBling(false) end
    if w.cd.SetHideCountdownNumbers then w.cd:SetHideCountdownNumbers(false) end
    w:Hide()
    secret[i] = w
    return w
end

local function HideSecret(i)
    if secret[i] and secret[i]:IsShown() then secret[i]:Hide() end
end

local totemRings = {}
for i, e in ipairs(ELEMENTS) do
    totemRings[i] = CreateLiveRing({
        key = "totem" .. i,
        centerIcon = true,
        valueScale = 0.42,
        watchEvery = 0.2,
        read = function()
            if not HasTotems() then HideSecret(i) return nil end
            local have, name, start, duration, icon, _, spellID = SafeCall(GetTotemInfo, e.slot)
            if IsSecret(have) or IsSecret(start) or IsSecret(duration) then
                -- Times hidden: keep our own countdown if we know this totem...
                local k = known[e.slot]
                if k then
                    local left = k.start + k.duration - GetTime()
                    if left > 0 then
                        HideSecret(i)
                        return State(e.element, left, k.duration, k.icon)
                    end
                    known[e.slot] = nil
                    maybeActive[e.slot] = nil
                end
                -- ...otherwise the game's own countdown, for a slot that may have one.
                if not maybeActive[e.slot] then HideSecret(i) return nil end
                local ring = totemRings[i]
                local w = SecretWidgets(i, ring.frame)
                local inner = math.max(8, db.totemSize - 2 * db.totemThickness - 2)
                w:SetSize(inner, inner)
                w:SetFrameLevel(ring.frame:GetFrameLevel() + 2)
                w.icon:SetTexture(icon) -- display only; the value is never read
                local c = db.totemColors[e.element]
                if w.cd.SetSwipeColor then w.cd:SetSwipeColor(c.r * 0.2, c.g * 0.2, c.b * 0.2, 0.75) end
                -- Feed the cooldown once when it appears and after each totem change
                -- (not every frame, which would restart its animation).
                if not w:IsShown() or w.stale then
                    w.stale = false
                    local dur = GetTotemDuration and SafeCall(GetTotemDuration, e.slot)
                    if dur and w.cd.SetCooldownFromDurationObject then
                        w.cd:SetCooldownFromDurationObject(dur)
                    end
                end
                w:Show()
                return { value = "", frac = 0, color = c }
            end
            HideSecret(i)
            if not have then
                maybeActive[e.slot], known[e.slot] = nil, nil
                return nil
            end
            if type(duration) ~= "number" or duration <= 0 or type(start) ~= "number" then return nil end
            local left = start + duration - GetTime()
            if left <= 0 then
                maybeActive[e.slot], known[e.slot] = nil, nil
                return nil
            end
            if IsSecret(icon) then icon = nil end
            maybeActive[e.slot] = true
            known[e.slot] = { start = start, duration = duration, icon = icon }
            Learn(spellID, e.slot, duration, icon)
            return State(e.element, left, duration, icon, name)
        end,
        sample = function(t)
            local s = SAMPLE[i]
            local left = (s[1] - t) % s[2]
            return State(e.element, left, s[2], s[3])
        end,
    })
end

-- A totem placed or removed while times are hidden: show that slot (the cooldown
-- display shows nothing once it's gone; the ring clears when times are readable).
-- Casting a totem we've learned starts our own countdown for its slot right away; a
-- slot changing without such a cast means its totem was destroyed or recalled.
local lastPlaced = {} -- slot -> GetTime() a learned totem was cast into it
local lastCast = -10  -- GetTime() of your last successful cast of anything

local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "PLAYER_TOTEM_UPDATE")
pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
events:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if not CircletDB then return end
    local now = GetTime()
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        lastCast = now
        local spellID = a3
        if type(spellID) ~= "number" or IsSecret(spellID) then return end
        local t = db.totemSpells and db.totemSpells[spellID]
        if not t then return end
        local icon = t.icon or (C_Spell and C_Spell.GetSpellTexture and SafeCall(C_Spell.GetSpellTexture, spellID))
        if IsSecret(icon) then icon = nil end
        known[t.slot] = { start = now, duration = t.duration, icon = icon }
        maybeActive[t.slot] = true
        lastPlaced[t.slot] = now
        return
    end
    local slot = a1
    if type(slot) == "number" and not IsSecret(slot) and slot >= 1 and slot <= 4 then
        for i, e in ipairs(ELEMENTS) do
            if e.slot == slot and secret[i] then secret[i].stale = true end
        end
        if now - (lastPlaced[slot] or -10) <= 0.5 then
            maybeActive[slot] = true -- the learned totem we just cast
        elseif now - lastCast <= 0.5 then
            -- You just cast something we haven't learned: probably a new totem here.
            -- Stop our countdown; if times are hidden, the game's display takes over.
            known[slot] = nil
            maybeActive[slot] = true
        else
            -- No cast: the totem there was killed or recalled (or expired).
            known[slot] = nil
            maybeActive[slot] = nil
        end
    end
end)

-- /sq totemdebug: which totem values the client is hiding right now.
local function TotemDebug()
    for _, e in ipairs(ELEMENTS) do
        local r = { SafeCall(GetTotemInfo, e.slot) }
        local parts = {}
        for k, label in ipairs({ "have", "name", "start", "duration", "icon" }) do
            table.insert(parts, label .. "=" .. (IsSecret(r[k]) and "SECRET" or tostring(r[k])))
        end
        ns.Print(e.element .. ": " .. table.concat(parts, "  "))
    end
    ns.Print("GetTotemDuration " .. (GetTotemDuration and "available" or "missing")
        .. (InCombatLockdown() and " (in combat)" or " (out of combat)"))
end

local function SetTotemsEditing(on)
    for _, ring in ipairs(totemRings) do ring.SetEditing(on) end
end

local function PreviewTotems()
    for _, ring in ipairs(totemRings) do ring.Preview(12) end
end

-- Shared with the files loaded after this one.
ns.SetTotemsEditing = SetTotemsEditing
ns.IsTotemsEditing = function() return totemRings[1].IsEditing() end
ns.PreviewTotems = PreviewTotems
ns.TotemDebug = TotemDebug
