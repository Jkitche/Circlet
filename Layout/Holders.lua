-- Circlet: Ring holders: one frame per ring for its opacity and combat fading.
local ADDON_NAME, ns = ...

local db = ns.db

-- Each ring and its extras (icons, effects, the "!") live in one holder frame per
-- ring; the holder's alpha is that ring's Opacity setting. Frame alpha multiplies
-- down to children, so it combines with the rings' own fades.
local ringHolders = {}
local function RingHolder(key)
    local holder = ringHolders[key]
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder:SetAllPoints(UIParent)
        ringHolders[key] = holder
    end
    return holder
end

-- Each ring's holder fades to its opacity setting, or out entirely while you're in
-- combat if the ring's "Show in combat" is off (it's hidden once faded, so it can't be
-- clicked, and comes back when combat ends).
local inCombat = false
local holderFader = CreateFrame("Frame")
holderFader:Hide()

local function TargetAlpha(key)
    if inCombat and db[key .. "Combat"] == false then return 0 end
    return math.max(0, math.min(100, db[key .. "Opacity"] or 100)) / 100
end

local function ApplyOpacity(key)
    local holder = RingHolder(key)
    holder.targetAlpha = TargetAlpha(key)
    if holder.targetAlpha > 0 then holder:Show() end
    holderFader:Show()
end

holderFader:SetScript("OnUpdate", function(self, elapsed)
    local busy = false
    for _, holder in pairs(ringHolders) do
        local target = holder.targetAlpha
        if target then
            local a = holder:GetAlpha()
            local step = elapsed / 0.3
            if math.abs(a - target) <= step then
                holder:SetAlpha(target)
                if target == 0 then holder:Hide() end
                holder.targetAlpha = nil
            else
                holder:SetAlpha(a + (target > a and step or -step))
                busy = true
            end
        end
    end
    if not busy then self:Hide() end
end)

holderFader:RegisterEvent("PLAYER_REGEN_DISABLED")
holderFader:RegisterEvent("PLAYER_REGEN_ENABLED")
holderFader:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    if not CircletDB then return end
    for key in pairs(ringHolders) do ApplyOpacity(key) end
end)

-- Shared with the files loaded after this one.
ns.RingHolder = RingHolder
ns.ApplyOpacity = ApplyOpacity
ns.ApplyAllOpacity = function() for key in pairs(ringHolders) do ApplyOpacity(key) end end
