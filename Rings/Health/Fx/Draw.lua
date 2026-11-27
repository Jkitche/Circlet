-- Circlet: Health ring effects: drawing them each frame, and the events that start them.
local _, ns = ...

local db, Clean = ns.db, ns.Clean
local FX = ns.HealthFx
local ON = FX.ON
local On = FX.On
local hits = FX.hits
local Mark = FX.Mark
local Pieces = FX.Pieces
local DrawCombo = FX.DrawCombo
local DrawMark = FX.DrawMark
local DrawAggro = FX.DrawAggro
local DrawExecute = FX.DrawExecute
local DrawLowHealth = FX.DrawLowHealth
local DrawDeath = FX.DrawDeath
local DrawFlare = FX.DrawFlare
local DrawHeal = FX.DrawHeal
local Restore = FX.Restore
local DrawJolt = FX.DrawJolt
local DrawAvoid = FX.DrawAvoid
local DrawEnergyTick = FX.DrawEnergyTick
local DrawRage = FX.DrawRage
local DrawFullMana = FX.DrawFullMana
local DrawSkin = FX.DrawSkin
local DrawQuest = FX.DrawQuest
local DrawRange = FX.DrawRange
local DrawLoot = FX.DrawLoot
local DrawStance = FX.DrawStance
local DrawFaction = FX.DrawFaction

---------------------------------------------------------------------------
-- Each frame
---------------------------------------------------------------------------
function ns.DrawVitalsFx(key, v, st, frame, geom, d, now)
    local fx = Pieces(v, frame)
    for _, t in pairs(fx.t) do
        t.used = false
    end
    for _, f in pairs(fx.frames) do
        f.used = false
    end
    fx.root:Show()
    if On(key, "Death") then DrawDeath(key, fx, st, frame, geom, d, now) end
    if not st.dead then
        if On(key, "Combo") then DrawCombo(key, fx, st, frame, geom, d, now) end
        if On(key, "Aggro") then DrawAggro(key, fx, st, frame, geom, d, now) end
        if On(key, "Execute") then DrawExecute(key, fx, st, frame, geom, d, now) end
        if On(key, "LowHealth") then DrawLowHealth(key, fx, st, frame, geom, d, now) end
        if On(key, "Heal") then DrawHeal(key, fx, st, frame, geom, d, now) end
        if On(key, "Avoid") then DrawAvoid(key, fx, st, frame, geom, d, now) end
        if v.g2 and v.g2.R and st.power then
            if On(key, "EnergyTick") then DrawEnergyTick(key, fx, st, frame, v.g2, now) end
            if On(key, "Rage") then DrawRage(key, fx, st, frame, v.g2, now) end
            if On(key, "FullMana") then DrawFullMana(key, fx, st, frame, v.g2, now) end
        end
    end
    if On(key, "Mark") then DrawMark(key, fx, st, frame, geom, d) end
    if On(key, "Range") then
        DrawRange(key, fx, st, frame, geom, d, now)
    elseif ns.SetRingDim then
        ns.SetRingDim(key, 1)
    end
    if On(key, "Loot") then DrawLoot(key, fx, st, frame, geom, d, now) end
    if On(key, "Stance") then DrawStance(key, fx, st, frame, geom, d, now) end
    if On(key, "Faction") then DrawFaction(key, fx, st, frame, geom, d, now) end
    if On(key, "Skin") then DrawSkin(key, fx, st, frame, geom, d, now) end
    fx.questTextUsed = false
    if On(key, "Quest") then DrawQuest(key, fx, st, frame, geom, d, now) end
    if fx.questText and not fx.questTextUsed then fx.questText:Hide() end
    if On(key, "Flare") then DrawFlare(key, fx, st, frame, geom, d, now) end
    DrawJolt(key, fx, st, frame, geom, now) -- always called: it puts the ring back after a jolt
    -- Anything not drawn this frame goes.
    for name, t in pairs(fx.t) do
        if not t.used then t:Hide() end
    end
    for _, f in pairs(fx.frames) do
        local any = false
        for _, t in pairs(fx.t) do
            if t.used and t:GetParent() == f then
                any = true
                break
            end
        end
        if not any then f:Hide() end
    end
end

function ns.HideVitalsFx(v, frame)
    local fx = v.fx
    if not fx then return end
    fx.root:Hide()
    -- The halos live under the ring (on the ring frame or frames of their own), not on fx.root.
    for _, t in pairs(fx.t) do
        if t:GetParent() ~= fx.root then t:Hide() end
    end
    Restore(fx, frame)
end

-- Jolt only when the setting is on (DrawJolt runs regardless, to undo one).
local function JoltOn(key) return ON.Jolt[key] and db[key .. "FxJolt"] end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local UNIT_KEY = { player = "playerHp", target = "targetHp" }

ns.Listen({ "UNIT_COMBAT" }, function(_, unit, action, flag)
    local key = UNIT_KEY[unit]
    if not key then return end
    action, flag = Clean(action), Clean(flag)
    if action == "HEAL" then
        Mark(key, "heal")
    elseif action == "WOUND" and (flag == "CRITICAL" or flag == "CRUSHING") then
        if JoltOn(key) then Mark(key, "jolt") end
    elseif action == "BLOCK" then
        Mark(key, "block")
    elseif action == "DODGE" then
        Mark(key, "dodge")
    elseif action == "PARRY" then
        Mark(key, "parry")
    end
end)

ns.Listen({ "PLAYER_REGEN_DISABLED" }, function() Mark("playerHp", "flare") end)

ns.Listen({ "UNIT_SPELLCAST_SUCCEEDED:player" }, function() FX.lastCastAt = GetTime() end)
ns.Listen({ "UNIT_POWER_FREQUENT:player" }, function(_, _, token)
    token = Clean(token)
    local now = GetTime()
    local yours = now - FX.lastCastAt < 0.2 -- spent (or gained) by a cast of yours
    if token == "ENERGY" and not yours then FX.tickAt = now end
    if token == "RAGE" and not yours and On("playerHp", "Rage") then ns.VitalsFxRage() end
end)

ns.VitalsFxState = function() return hits, FX.tickAt end -- tests
