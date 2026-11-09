-- Circlet: Auto-arrange: rings that are up at once slide apart instead of overlapping.
local ADDON_NAME, ns = ...

local db = ns.db

-- Auto-arrange: every ring frame, so rings that are up at the same time can keep
-- out of each other's way. The ring that appeared first keeps its spot; a ring that
-- pops up on top of it slides sideways just far enough to clear it, and slides back
-- home once the first one fades.
local RING_FRAMES = {}
local ARRANGE_GAP = 8

local function HomeCenter(key)
    local size = db[key .. "Size"]
    return db[key .. "X"], -(db[key .. "FromTop"] + size / 2), size / 2
end

-- Called from each ring's layout (every frame while it's up). Returns the sideways
-- offset to add to the ring's saved position.
local function ArrangeX(key, frame)
    local now = GetTime()
    -- Layout runs every frame while a ring is up; a gap means it was hidden in between.
    local fresh = now - (frame.arrangeSeen or 0) > 0.5
    if fresh then frame.shownAt = now end
    local dt = fresh and 1 or (now - frame.arrangeSeen)
    frame.arrangeSeen = now

    local target = 0
    if db.autoArrange and not frame.isEditing then
        local hx, hy, r = HomeCenter(key)
        for _ = 1, 4 do -- a few passes, in case clearing one ring lands on another
            local moved = false
            for otherKey, other in pairs(RING_FRAMES) do
                local older = other.shownAt and (other.shownAt < frame.shownAt
                    or (other.shownAt == frame.shownAt and otherKey < key))
                if other ~= frame and older and other:IsShown() and now - (other.arrangeSeen or 0) < 0.5 then
                    local ox, oy, orad = HomeCenter(otherKey)
                    ox = ox + (other.arrangeX or 0)
                    local need, dy = r + orad + ARRANGE_GAP, math.abs(hy - oy)
                    if dy < need then
                        local minDx = math.sqrt(need * need - dy * dy)
                        if math.abs(hx + target - ox) < minDx - 0.5 then
                            local dir = (hx >= ox) and 1 or -1 -- away from it, on our home side
                            target = ox + dir * minDx - hx
                            moved = true
                        end
                    end
                end
            end
            if not moved then break end
        end
    end

    local cur = frame.arrangeX or 0
    frame.arrangeX = fresh and target or cur + (target - cur) * math.min(1, dt * 10)
    return frame.arrangeX
end

-- Shared with the files loaded after this one.
ns.RING_FRAMES = RING_FRAMES
ns.ArrangeX = ArrangeX
