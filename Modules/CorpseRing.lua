-- Circlet: Corpse ring: how far your body is while you're a ghost, and which way.
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing, FormatTime = ns.db, ns.IsSecret, ns.CreateLiveRing, ns.FormatTime

---------------------------------------------------------------------------
-- Corpse ring
---------------------------------------------------------------------------
-- After you release, the ring shows the distance to your corpse in yards and fills
-- as you close in. A dot on the ring points toward the corpse (straight up = ahead).
-- It says when you can resurrect: the wait if there is one, then "In range" once
-- you're close enough.

local RES_RANGE = 39 -- yards; the game's corpse-resurrect range is about 40
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local startDist -- distance when this corpse run began, for the fill

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function XY(v)
    if type(v) == "table" and v.GetXY then return v:GetXY() end
    if type(v) == "table" then return v.x, v.y end
end

-- Distance in yards to the corpse and its bearing (radians, 0 = north, counter-
-- clockwise like GetPlayerFacing), or nil when the corpse isn't on this map.
local function CorpseVector()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = SafeCall(C_Map.GetBestMapForUnit, "player")
    if not mapID or IsSecret(mapID) then return nil end
    local px, py = XY(SafeCall(C_Map.GetPlayerMapPosition, mapID, "player"))
    local cx, cy
    if C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
        cx, cy = XY(SafeCall(C_DeathInfo.GetCorpseMapPosition, mapID))
    elseif GetCorpseMapPosition then
        cx, cy = SafeCall(GetCorpseMapPosition)
    end
    local w, h = SafeCall(C_Map.GetMapWorldSize, mapID)
    for _, v in ipairs({ px or false, py or false, cx or false, cy or false, w or false, h or false }) do
        if not v or IsSecret(v) then return nil end
    end
    if (cx == 0 and cy == 0) or w <= 0 then return nil end
    local east, north = (cx - px) * w, (py - cy) * h -- map y grows southward
    return math.sqrt(east * east + north * north), atan2(-east, north)
end

local function State(dist, bearing, facing, delay)
    local c = db.corpseColors
    local st = { title = "Your corpse", color = c.fill, markerColor = c.marker }
    if not dist then
        st.value, st.frac, st.label = "?", 0, "Not on this map"
        return st
    end
    startDist = math.max(startDist or 0, dist, 1)
    st.frac = math.max(0, math.min(1, 1 - dist / startDist))
    st.value = math.floor(dist + 0.5) .. " yd"
    if delay and delay > 0 then
        st.label = "Resurrect in " .. FormatTime(delay)
    elseif dist <= RES_RANGE then
        st.label, st.labelColor, st.color = "In range: resurrect!", c.ready, c.ready
        st.frac = 1
    else
        st.label = "to your corpse"
    end
    if bearing and facing then
        st.marker = -(bearing - facing) -- clockwise from straight ahead
    end
    return st
end

local corpseRing = CreateLiveRing({
    key = "corpse",
    read = function()
        if not UnitIsGhost("player") then
            startDist = nil
            return nil
        end
        local dist, bearing = CorpseVector()
        local facing = GetPlayerFacing and SafeCall(GetPlayerFacing)
        if IsSecret(facing) then facing = nil end
        local delay = GetCorpseRecoveryDelay and SafeCall(GetCorpseRecoveryDelay)
        if IsSecret(delay) then delay = nil end
        return State(dist, bearing, facing, delay)
    end,
    sample = function(t)
        -- Walking back: 420 yards down to in range, the corpse drifting to the right.
        local cycle = t % 12
        local dist = math.max(20, 420 - cycle * 40)
        startDist = 420
        return State(dist, -0.6 - cycle * 0.05, 0, cycle < 2 and (2 - cycle) * 8 or 0)
    end,
})

local function PreviewCorpseRing() corpseRing.Preview(12) end

-- Shared with the files loaded after this one.
ns.corpseRing = corpseRing
ns.PreviewCorpseRing = PreviewCorpseRing
