-- Circlet: Health ring effects about an enemy target: your threat on it, and whether your crowd control works on it.
local _, ns = ...

local SafeCall, Clean, CleanNumber, IsSecret = ns.SafeCall, ns.Clean, ns.CleanNumber, ns.IsSecret
local FX = ns.HealthFx
local DISC = FX.DISC
local BadgeAngle = FX.BadgeAngle
local Tex = FX.Tex
local At = FX.At
local Polar = FX.Polar
local RoundIcon = FX.RoundIcon
local Knows = FX.Knows

local function Hostile(unit) return Clean(SafeCall(UnitCanAttack, "player", unit)) and true or false end

---------------------------------------------------------------------------
-- Threat
---------------------------------------------------------------------------
-- Your share of the target's threat (UnitDetailedThreatSituation's scaled percent: 100 is where
-- you'd pull it) as beads round the outside of the band, filling up both sides from the bottom
-- and meeting at the top at 100. Only while something else is tanking it and you have some:
-- when it's on you the aggro glare says so. Yellow, orange from 70%, red and pulsing from 90%.
-- Previews show 70%.
local THREAT_BEADS = 18 -- per side

local function ThreatShare(unit)
    local tanking, _, scaled = SafeCall(UnitDetailedThreatSituation, "player", unit)
    tanking, scaled = Clean(tanking), CleanNumber(scaled)
    if tanking or not scaled or scaled <= 0 then return nil end
    return math.min(1, scaled / 100)
end

local function DrawThreat(key, fx, st, frame, geom, d, now)
    local share
    if not st.unit then
        share = 0.7
    elseif not st.dead and Hostile(st.unit) then
        share = ThreatShare(st.unit)
    end
    if not share then return end
    local r1, g1, b1, pulse = 1, 0.85, 0.2, 1
    if share >= 0.9 then
        r1, g1, b1 = 1, 0.15, 0.1
        pulse = 0.6 + 0.4 * math.abs(math.sin(now * 5))
    elseif share >= 0.7 then
        r1, g1, b1 = 1, 0.5, 0.1
    end
    local bead = math.max(3, math.floor(geom.T * 0.45 + 0.5))
    local r = geom.R + geom.T / 2 + bead * 0.9
    local lit = math.floor(share * THREAT_BEADS + 0.5)
    for side = -1, 1, 2 do
        for i = 1, THREAT_BEADS do
            local x, y = Polar(270 + side * (i - 0.5) / THREAT_BEADS * 180, r)
            local t = Tex(fx, "threat" .. side .. "_" .. i, DISC, "ARTWORK", 1)
            At(t, frame, x, y, bead)
            if i <= lit then
                t:SetVertexColor(r1, g1, b1, 1)
                t:SetAlpha(pulse)
            else
                t:SetVertexColor(0, 0, 0, 1)
                t:SetAlpha(0.35)
            end
        end
    end
end
ns.VitalsFxThreat = ThreatShare -- tests

---------------------------------------------------------------------------
-- Crowd control
---------------------------------------------------------------------------
-- Your class's crowd control, when you know it and it works on the target's kind of creature
-- (UnitCreatureType, which names it in the game's language: these are the English names).
-- Sap only works on one that isn't in combat. Previews show Polymorph.
local CC = {
    MAGE = { 118, "Interface\\Icons\\Spell_Nature_Polymorph", { Humanoid = true, Beast = true, Critter = true } },
    PRIEST = { 9484, "Interface\\Icons\\Spell_Nature_Slow", { Undead = true } },
    WARLOCK = { 710, "Interface\\Icons\\Spell_Shadow_Cripple", { Demon = true, Elemental = true } },
    DRUID = { 2637, "Interface\\Icons\\Spell_Nature_Sleep", { Beast = true, Dragonkin = true } },
    ROGUE = { 6770, "Interface\\Icons\\Ability_Sap", { Humanoid = true }, calm = true },
    HUNTER = { 1513, "Interface\\Icons\\Ability_Druid_Cower", { Beast = true } },
    PALADIN = { 2878, "Interface\\Icons\\Spell_Holy_TurnUndead", { Undead = true } },
}
local PREVIEW_CC = "Interface\\Icons\\Spell_Nature_Polymorph"

-- The icon of the crowd control that works on unit, or nil.
local function CrowdControl(unit)
    local _, class = SafeCall(UnitClass, "player")
    local cc = CC[Clean(class) or ""]
    if not cc or not Hostile(unit) then return nil end
    local kind = Clean(SafeCall(UnitCreatureType, unit))
    if not (kind and cc[3][kind]) then return nil end
    if cc.calm and Clean(SafeCall(UnitAffectingCombat, unit)) ~= false then return nil end
    if not Knows(cc[1]) then return nil end
    return cc[2]
end

local function DrawCC(key, fx, st, frame, geom, d, now)
    local icon
    if not st.unit then
        icon = PREVIEW_CC
    elseif not st.dead then
        icon = CrowdControl(st.unit)
    end
    if not icon or IsSecret(icon) then return end
    local x, y = Polar(BadgeAngle(key, "CC"), geom.R)
    local back = Tex(fx, "ccBack", DISC, "OVERLAY", 2)
    At(back, frame, x, y, d * 1.25)
    back:SetVertexColor(0, 0, 0)
    back:SetAlpha(0.85)
    local t = RoundIcon(fx, "cc", icon)
    At(t, frame, x, y, d * 1.05)
    t:SetAlpha(1)
end
ns.VitalsFxCrowdControl = CrowdControl -- tests

-- For the files loaded after this one.
FX.DrawThreat = DrawThreat
FX.DrawCC = DrawCC
