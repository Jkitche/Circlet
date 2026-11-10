-- Circlet: Telling whether a cast is at something you're interacting with (a chest, a quest
-- object...), so the cast ring can give it the finish burst.
local ADDON_NAME, ns = ...

local SafeCall, Clean = ns.SafeCall, ns.Clean

---------------------------------------------------------------------------
-- Interaction casts
---------------------------------------------------------------------------
-- What counts as an interaction: a cast whose target (UNIT_SPELLCAST_SENT names it) is
-- your soft-interact target, or was a moment ago (the game can drop the soft target as
-- the cast begins). So opening a chest or clicking a quest object counts; a Hearthstone
-- or a Fireball at a mob doesn't.

local SOFT = "softinteract"
local RECENT = 1.5 -- seconds a soft target that just went away still counts

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

local sent -- { castGUID, spellID, at }: the last cast sent at an interact target

local function OnSent(target, castGUID, spellID)
    target, castGUID, spellID = Clean(target), Clean(castGUID), Clean(spellID)
    local guid, name = SoftNow()
    local now = GetTime()
    if not guid and lastSoft and now - lastSoft.at < RECENT then guid, name = lastSoft.guid, lastSoft.name end
    -- The cast must be at the soft target (an empty target, e.g. fishing or an item, isn't).
    if not guid or type(target) ~= "string" or target == "" or (name and target ~= name) then
        sent = nil
        return
    end
    sent = { castGUID = castGUID, spellID = spellID, at = now }
end

-- At a cast's start: whether it's an interaction. castGUID/spellID tie it to the
-- UNIT_SPELLCAST_SENT that came first.
local function IsInteraction(castGUID, spellID)
    local s = sent
    if not s or GetTime() - s.at > 2 then return false end
    castGUID, spellID = Clean(castGUID), Clean(spellID)
    if castGUID and s.castGUID then return castGUID == s.castGUID end
    return not (spellID and s.spellID and spellID ~= s.spellID)
end

ns.Listen({ "UNIT_SPELLCAST_SENT:player", "PLAYER_SOFT_INTERACT_CHANGED" }, function(event, a1, a2, a3, a4)
    if event == "UNIT_SPELLCAST_SENT" then
        OnSent(a2, a3, a4) -- unit, target, castGUID, spellID
    else
        NoteSoft()
    end
end)

-- Shared with the files loaded after this one.
ns.IsInteraction = IsInteraction
