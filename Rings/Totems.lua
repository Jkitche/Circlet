-- Circlet: Totem rings: a small ring per active shaman totem.
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing, FormatTime = ns.db, ns.IsSecret, ns.CreateLiveRing, ns.FormatTime
local SafeCall = ns.SafeCall

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
--
-- That fallback draws none of the ring itself, only the game's icon and sweep, which show
-- just while a totem is really there: whenever Circlet can't be sure (a totem it hasn't
-- learned, or one that may have died), an empty slot shows nothing rather than a bare
-- ring. It also clears as soon as the game says a slot is empty (even with its times
-- hidden), and gives up once even the longest totem you've used would be over.
--
-- A totem dying mid-fight is seen through PLAYER_TOTEM_UPDATE. When the game hides which
-- slot changed, and you didn't just drop a learned totem, any slot might have lost its
-- totem: our own countdowns stop and every slot that had one switches to the game's
-- display, which shows only the totems still standing.

local ELEMENTS = {
    -- display order: GetTotemInfo slot, element
    { slot = 2, element = "earth" },
    { slot = 1, element = "fire" },
    { slot = 3, element = "water" },
    { slot = 4, element = "air" },
}
local WARN_AT = 10

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
local maybeActive = {} -- slot -> GetTime() a totem changed there while times were hidden
local FALLBACK_MAX = 300 -- seconds the game's display is kept without our own countdown, until a longer totem is learned

-- The longest totem you've used (from what's been learned), or FALLBACK_MAX.
local function LongestTotem()
    local longest = 0
    for _, t in pairs(db.totemSpells or {}) do
        if type(t.duration) == "number" and t.duration > longest then longest = t.duration end
    end
    return longest > 0 and longest or FALLBACK_MAX
end
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
            -- The game can say the slot is empty while still hiding its times: it's empty.
            if not IsSecret(have) and not have then
                HideSecret(i)
                maybeActive[e.slot], known[e.slot] = nil, nil
                return nil
            end
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
                if not maybeActive[e.slot] or GetTime() - maybeActive[e.slot] > LongestTotem() + 5 then
                    maybeActive[e.slot] = nil -- nothing there, or it's surely over by now
                    HideSecret(i)
                    return nil
                end
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
                        w.cd:SetCooldownFromDurationObject(dur, true) -- true: clears when there's no time left
                    end
                end
                w:Show()
                -- Only the game's icon and sweep, none of our ring: they show just while a
                -- totem is really there, so an empty slot shows nothing.
                return { value = "", frac = 0, color = c, noTrack = true }
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
            maybeActive[e.slot] = start
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

ns.Listen({ "PLAYER_TOTEM_UPDATE", "UNIT_SPELLCAST_SUCCEEDED:player" }, function(event, a1, a2, a3)
    if not CircletDB then return end
    local now = GetTime()
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        lastCast = now
        local spellID = a3
        if type(spellID) ~= "number" or IsSecret(spellID) then return end
        local t = db.totemSpells and db.totemSpells[spellID]
        if not t then return end
        local icon = t.icon or ns.SpellIcon(spellID)
        if IsSecret(icon) then icon = nil end
        known[t.slot] = { start = now, duration = t.duration, icon = icon }
        maybeActive[t.slot] = now
        lastPlaced[t.slot] = now
        return
    end
    local slot = a1
    if type(slot) == "number" and not IsSecret(slot) and slot >= 1 and slot <= 4 then
        for i, e in ipairs(ELEMENTS) do
            if e.slot == slot and secret[i] then secret[i].stale = true end
        end
        if now - (lastPlaced[slot] or -10) <= 0.5 then
            maybeActive[slot] = now -- the learned totem we just cast
        elseif now - lastCast <= 0.5 then
            -- You just cast something we haven't learned: probably a new totem here.
            -- Stop our countdown; if times are hidden, the game's display takes over.
            known[slot] = nil
            maybeActive[slot] = now
        else
            -- No cast: the totem there was killed or recalled (or expired).
            known[slot] = nil
            maybeActive[slot] = nil
        end
        return
    end
    -- The game hides which slot changed. A learned totem we just dropped explains it;
    -- otherwise any totem may have died, so stop trusting our own countdowns: every slot
    -- that had one switches to the game's display, which shows only what's still there.
    for _, at in pairs(lastPlaced) do
        if now - at <= 0.5 then return end
    end
    for s = 1, 4 do
        if known[s] or maybeActive[s] then
            known[s] = nil
            maybeActive[s] = now
        end
    end
    for _, w in pairs(secret) do w.stale = true end
end)

-- /circ totemdebug: which totem values the client is hiding right now.
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

ns.RegisterCommand({ "totemdebug" }, TotemDebug) -- what the game hides about your totems

-- Shared with the files loaded after this one.
ns.SetTotemsEditing = SetTotemsEditing
ns.IsTotemsEditing = function() return totemRings[1].IsEditing() end
ns.PreviewTotems = PreviewTotems
ns.TotemDebug = TotemDebug

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "totem", name = "Totem", order = 16,
    edit = { set = SetTotemsEditing, get = ns.IsTotemsEditing },
    preview = PreviewTotems, slash = { "totems", "totem" }, help = "preview the totem rings",
    toggle = { "Totem rings", "Shamans: a small ring for each totem you have down." },
    class = { SHAMAN = true },
    gameBar = "the game's totem timers",
    defaults = {
        -- Totem rings (shamans): one small ring per active totem, in a row.
        totemEnabled   = true,
        totemWarn      = true, -- pulse in the last 10 seconds
        totemSize      = 56,
        totemThickness = 6,
        totemOpacity   = 100,
        totemX         = -96,  -- the first (earth) ring; the rest go to its right
        totemFromTop   = 400,
        totemHold      = 0,
        totemStyle     = "smooth",
        totemBorder    = 2,
        totemSpells = {}, -- learned: totem spell ID -> { slot, duration, icon }
        totemColors = {
            earth = { r = 0.65, g = 0.50, b = 0.30 },
            fire  = { r = 1.00, g = 0.40, b = 0.15 },
            water = { r = 0.25, g = 0.60, b = 1.00 },
            air   = { r = 0.80, g = 0.90, b = 1.00 },
        },
    },
    page = { folder = nil, order = 6, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(6, "Totems", "Totem Rings",
                "Shamans: a small ring for each totem you have down, in the totem bar's order (earth, fire, water, "
                .. "air). The totem's icon sits in the middle with the time left, and the ring drains in the element's "
                .. "color.",
                MergeTop(TopRow("totem", "totem rings", ns.PreviewTotems, "Show four sample totems. Also /circ totems."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "totemEnabled", "Show totem rings", "Show a ring for each active totem."),
                        warn = Toggle(2, "totemWarn", "Pulse when ending", "Pulse a totem's ring in its last 10 seconds."),
                    }),
                    colors = Box(3, "Colors", {
                        earth = Color(1, "totemColors", "earth", "Earth", "Earth totem ring color."),
                        fire = Color(2, "totemColors", "fire", "Fire", "Fire totem ring color."),
                        water = Color(3, "totemColors", "water", "Water", "Water totem ring color."),
                        air = Color(4, "totemColors", "air", "Air", "Air totem ring color."),
                    }),
                    size = SizeBox(4, "totem", "totem rings",
                        "Offset from the center of the screen to the first (earth) ring; the others line up to its right."),
                }))
            tab.args.size.args.hold = nil
            tab.args.size.args.size.min = 30
            tab.args.size.args.size.max = 120
            tab.args.size.args.size.step = 2
            return tab
        end },
})
