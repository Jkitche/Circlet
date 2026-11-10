-- Circlet: Keeping a ring on what you're interacting with (a corpse, herb, ore vein,
-- chest...) as the camera moves.
local ADDON_NAME, ns = ...

local db, SafeCall, Clean = ns.db, ns.SafeCall, ns.Clean

---------------------------------------------------------------------------
-- Follow the interact target
---------------------------------------------------------------------------
-- Addons can't turn a spot in the world into a spot on screen, but the game can show a
-- nameplate over the thing you'd interact with (the "softinteract" unit), and that
-- plate moves with the camera. A ring that follows sits on that plate.
--
-- What counts as an interaction: a cast whose target (UNIT_SPELLCAST_SENT names it) is
-- your soft-interact target, or was a moment ago (the game can drop the soft target as
-- the cast begins). So skinning a corpse, mining a vein, opening a chest or clicking a
-- quest object all follow; a Hearthstone or a Fireball at a mob doesn't.
--
-- The target is pinned by GUID: its plate is found through the softinteract token or,
-- once that has moved on, among the visible nameplates. If the plate goes (the corpse is
-- skinned, the node is gone, it's out of view) the ring stays where it last was.
--
-- Needs the game's SoftTargetNameplateInteract setting, which the follow options turn on
-- (and put back as they were when they're all off).

local SOFT = "softinteract"
local PLATE_CVAR = "SoftTargetNameplateInteract"
local RECENT = 1.5 -- seconds a soft target that just went away still counts

local function FollowWanted() return db.gatherFollow or db.castFollow end

-- Diagnostics for /sq follow: the last few things that happened.
local log = {}
local function Log(fmt, ...)
    table.insert(log, string.format("%.1f  " .. fmt, GetTime() % 1000, ...))
    while #log > 12 do table.remove(log, 1) end
end

-- The game setting --------------------------------------------------------------

local cvarPending = false
local function ApplyFollowCVar()
    if not (CircletDB and GetCVar and SetCVar) then return end
    if InCombatLockdown and InCombatLockdown() then cvarPending = true return end
    cvarPending = false
    local current = SafeCall(GetCVar, PLATE_CVAR)
    if current == nil then return end -- this client doesn't have it
    if FollowWanted() then
        if current ~= "1" then
            db.gatherFollowCVar = db.gatherFollowCVar or current
            SafeCall(SetCVar, PLATE_CVAR, "1")
        end
    elseif db.gatherFollowCVar then
        SafeCall(SetCVar, PLATE_CVAR, db.gatherFollowCVar)
        db.gatherFollowCVar = nil
    end
end

-- The soft-interact target, now and just before -----------------------------------

local function SoftNow()
    local guid = Clean(SafeCall(UnitGUID, SOFT))
    if not guid then return nil end
    return guid, Clean(SafeCall(UnitName, SOFT))
end

local lastSoft -- { guid, name, at }: the latest soft target; at = when it was last current

local function NoteSoft()
    local guid, name = SoftNow()
    if guid then
        lastSoft = { guid = guid, name = name, at = GetTime() }
    elseif lastSoft then
        lastSoft.at = GetTime() -- it was current until just now
    end
end

-- A plate's center in screen pixels, if it's on screen.
local function PlateCenter(plate)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return nil end
    if not SafeCall(plate.IsVisible, plate) then return nil end
    local px, py = SafeCall(plate.GetCenter, plate)
    local ps = SafeCall(plate.GetEffectiveScale, plate)
    px, py, ps = Clean(px), Clean(py), Clean(ps)
    if type(px) == "number" and type(py) == "number" and type(ps) == "number" then
        return px * ps, py * ps
    end
end

-- The plate showing guid: the soft target's, else any visible nameplate's.
local function FindPlate(guid)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    if Clean(SafeCall(UnitGUID, SOFT)) == guid then
        local plate = SafeCall(C_NamePlate.GetNamePlateForUnit, SOFT)
        if plate then return plate, "soft" end
    end
    local plates = C_NamePlate.GetNamePlates and SafeCall(C_NamePlate.GetNamePlates)
    if type(plates) == "table" then
        for _, plate in ipairs(plates) do
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if unit and Clean(SafeCall(UnitGUID, unit)) == guid then return plate, unit end
        end
    end
end

-- Casts -------------------------------------------------------------------------------

local sent -- { castGUID, spellID, guid, name, x, y, at }: the last cast sent at an interact target

local function OnSent(target, castGUID, spellID)
    target, castGUID, spellID = Clean(target), Clean(castGUID), Clean(spellID)
    local guid, name = SoftNow()
    local now = GetTime()
    if not guid and lastSoft and now - lastSoft.at < RECENT then guid, name = lastSoft.guid, lastSoft.name end
    if not guid then
        sent = nil
        if FollowWanted() then Log("cast %s at %q: no soft-interact target", tostring(spellID), tostring(target)) end
        return
    end
    -- The cast must be at the soft target (an empty target, e.g. fishing or an item, isn't).
    if type(target) ~= "string" or target == "" or (name and target ~= name) then
        sent = nil
        if FollowWanted() then
            Log("cast %s at %q: soft target is %q, not following", tostring(spellID), tostring(target), tostring(name))
        end
        return
    end
    sent = { castGUID = castGUID, spellID = spellID, guid = guid, name = name or target, at = now }
    local plate = FindPlate(guid)
    sent.x, sent.y = PlateCenter(plate)
    if FollowWanted() then
        Log("cast %s at %q: target %s, plate %s", tostring(spellID), tostring(target), guid,
            sent.x and "found" or (plate and "hidden" or "none"))
    end
end

-- At a cast's start: what to follow (a new table each time), or nil if it isn't an
-- interaction. castGUID/spellID tie it to the UNIT_SPELLCAST_SENT that came first.
local function InteractTarget(castGUID, spellID)
    local s = sent
    if not s or GetTime() - s.at > 2 then return nil end
    castGUID, spellID = Clean(castGUID), Clean(spellID)
    if castGUID and s.castGUID then
        if castGUID ~= s.castGUID then return nil end
    elseif spellID and s.spellID and spellID ~= s.spellID then
        return nil
    end
    return { guid = s.guid, name = s.name, x = s.x, y = s.y }
end

-- Where a following ring's center goes (x, y from the screen's bottom-left, in frame's
-- units), or nil if its target has never been on screen.
local function FollowPoint(f, frame)
    if not f then return nil end
    local plate, via = FindPlate(f.guid)
    local x, y = PlateCenter(plate)
    if x then
        f.x, f.y = x, y
        if not f.seen then f.seen = true; Log("following %s via %s", f.name or f.guid, tostring(via)) end
    elseif f.seen and not f.lost then
        f.lost = true
        Log("lost the plate for %s; holding the last spot", f.name or f.guid)
    end
    if not f.x then return nil end
    local fs = frame:GetEffectiveScale()
    return f.x / fs, f.y / fs
end

ns.Listen({ "UNIT_SPELLCAST_SENT:player", "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" },
    function(event, a1, a2, a3, a4)
        if not CircletDB then return end
        if event == "UNIT_SPELLCAST_SENT" then
            OnSent(a2, a3, a4) -- unit, target, castGUID, spellID
        elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
            NoteSoft()
        elseif event == "PLAYER_ENTERING_WORLD" or cvarPending then
            ApplyFollowCVar()
        end
    end)

-- /sq follow: what the follow saw lately, and how things stand now.
ns.RegisterCommand({ "follow" }, function()
    local P = ns.Print
    P("follow: gathering " .. (db.gatherFollow and "on" or "off") .. ", interactions " .. (db.castFollow and "on" or "off")
        .. "; " .. PLATE_CVAR .. " = " .. tostring(GetCVar and SafeCall(GetCVar, PLATE_CVAR))
        .. ", SoftTargetInteract = " .. tostring(GetCVar and SafeCall(GetCVar, "SoftTargetInteract")))
    local guid, name = SoftNow()
    local plate = guid and FindPlate(guid)
    P("now facing: " .. (guid and (tostring(name) .. " (" .. guid .. "), plate "
        .. (PlateCenter(plate) and "on screen" or (plate and "hidden" or "none"))) or "nothing"))
    if #log == 0 then P("nothing logged yet: gather or interact with something, then /sq follow again.") end
    for _, line in ipairs(log) do P("  " .. line) end
end, "what following a corpse / node / object saw lately")

-- Shared with the files loaded after this one.
ns.ApplyFollowCVar = ApplyFollowCVar
ns.InteractTarget = InteractTarget
ns.FollowPoint = FollowPoint
