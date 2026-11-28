-- Circlet: Health ring effects on your own ring: durability, low mana, group leader, PvP flag, and a resurrect or summon waiting.
local _, ns = ...

local SafeCall, Clean, CleanNumber, IsSecret = ns.SafeCall, ns.Clean, ns.CleanNumber, ns.IsSecret
local FX = ns.HealthFx
local DISC = FX.DISC
local GLOW = FX.GLOW
local STAR = FX.STAR
local BadgeAngle = FX.BadgeAngle
local Tex = FX.Tex
local Text = FX.Text
local TextSize = FX.TextSize
local At = FX.At
local Polar = FX.Polar
local GlowOn = FX.GlowOn
local Curve = FX.Curve
local RoundIcon = FX.RoundIcon
local DrawThreshold = FX.DrawThreshold

---------------------------------------------------------------------------
-- Durability
---------------------------------------------------------------------------
-- The worst of your equipped gear, checked once a second: 2 broken (red, pulsing), 1 badly
-- damaged (yellow), 0 fine. The game's own alert status per slot (what lights the armor figure
-- under the minimap) when it has one, else broken at 0 and damaged at 20% or less.
local ANVIL = "Interface\\Icons\\Trade_BlackSmithing"
local SLOTS = 19
local duraAt, duraState = -math.huge, 0

local function SlotState(slot)
    if GetInventoryAlertStatus then
        local s = CleanNumber(SafeCall(GetInventoryAlertStatus, slot))
        if s then return s >= 2 and 2 or s end
    end
    local cur, max = SafeCall(GetInventoryItemDurability, slot)
    cur, max = CleanNumber(cur), CleanNumber(max)
    if not (cur and max and max > 0) then return 0 end
    if cur <= 0 then return 2 end
    return cur / max <= 0.2 and 1 or 0
end

local function GearState()
    local worst = 0
    for slot = 1, SLOTS do
        local s = SlotState(slot)
        if s > worst then worst = s end
        if worst >= 2 then break end
    end
    return worst
end

local function DrawDurability(key, fx, st, frame, geom, d, now)
    local state
    if not st.unit then
        state = 1 -- previews: damaged
    else
        if now - duraAt >= 1 then
            duraAt = now
            duraState = GearState()
        end
        state = duraState
    end
    if state <= 0 then return end
    local x, y = Polar(BadgeAngle(key, "Durability"), geom.R)
    local rim = Tex(fx, "duraRim", DISC, "OVERLAY", 2)
    At(rim, frame, x, y, d * 1.3)
    if state >= 2 then
        rim:SetVertexColor(1, 0.12, 0.08)
        rim:SetAlpha(0.6 + 0.4 * math.abs(math.sin(now * 4)))
    else
        rim:SetVertexColor(1, 0.82, 0.1)
        rim:SetAlpha(1)
    end
    local t = RoundIcon(fx, "dura", ANVIL)
    At(t, frame, x, y, d * 1.05)
    t:SetAlpha(1)
end
ns.VitalsFxGear = GearState -- tests
ns.Listen({ "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" }, function() duraAt = -math.huge end)

---------------------------------------------------------------------------
-- Low mana
---------------------------------------------------------------------------
-- A blue heartbeat on the mana band below 20%: the readable fraction when there is one, else
-- the hidden one through a step curve (like low health).
local function DrawLowMana(key, fx, st, frame, g2, now)
    local p = st.power
    if not (p and p.token == "MANA") or not st.unit then return end
    local gate
    if type(p.real) == "number" and not IsSecret(p.real) then
        gate = p.real < 0.2
    elseif type(UnitPowerPercent) == "function" and ns.VitalsCurves.Work() then
        local ok, v = pcall(UnitPowerPercent, st.unit, 0, false, Curve(0.2, 1, 0))
        if ok then gate = v end
    end
    local ph = now % 1.2
    local beat = math.max(math.exp(-((ph - 0.0) / 0.09) ^ 2), 0.6 * math.exp(-((ph - 0.26) / 0.09) ^ 2))
    DrawThreshold(fx, "lowMana", frame, g2.R, gate, { 0.25, 0.5, 1 }, 0.25 + 0.6 * beat)
end

---------------------------------------------------------------------------
-- Group leader
---------------------------------------------------------------------------
-- The crown while you lead your group (the assistant's icon if you assist a raid), the master
-- looter's bag beside it while you are one (or on its own, if you're neither). Previews show
-- both.
local CROWN = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local ASSIST = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
local LOOTER = "Interface\\GroupFrame\\UI-Group-MasterLooter"

local function MasterLooter()
    local get = (C_PartyInfo and C_PartyInfo.GetLootMethod) or GetLootMethod
    local method, partyId, raidId = SafeCall(get)
    method, partyId, raidId = Clean(method), CleanNumber(partyId), CleanNumber(raidId)
    if method ~= "master" and method ~= 2 then return false end
    if partyId == 0 then return true end
    if raidId then return Clean(SafeCall(UnitIsUnit, "raid" .. raidId, "player")) and true or false end
    return false
end

local function Roles()
    if not Clean(SafeCall(IsInGroup)) then return nil end
    local lead = Clean(SafeCall(UnitIsGroupLeader, "player")) and CROWN
        or (Clean(SafeCall(IsInRaid)) and Clean(SafeCall(UnitIsGroupAssistant, "player")) and ASSIST)
    return lead or nil, MasterLooter()
end

local function DrawLeader(key, fx, st, frame, geom, d, now)
    local lead, looter
    if not st.unit then
        lead, looter = CROWN, true
    else
        lead, looter = Roles()
    end
    if not lead and not looter then return end
    local deg = BadgeAngle(key, "Leader")
    local size = d * 1.15
    if lead then
        local x, y = Polar(deg, geom.R + geom.T * 0.2)
        local t = Tex(fx, "lead", lead, "OVERLAY", 3)
        if t.file ~= lead then
            t.file = lead
            t:SetTexture(lead)
        end
        At(t, frame, x, y, size)
        t:SetAlpha(1)
    end
    if looter then
        -- Beside the crown, a step clockwise round the ring; at the spot itself if alone.
        local step = lead and math.deg(size / math.max(1, geom.R)) or 0
        local x, y = Polar(deg - step, geom.R + geom.T * 0.2)
        local t = Tex(fx, "looter", LOOTER, "OVERLAY", 3)
        At(t, frame, x, y, size * 0.9)
        t:SetAlpha(1)
    end
end
ns.VitalsFxRoles = Roles -- tests

---------------------------------------------------------------------------
-- PvP flag
---------------------------------------------------------------------------
-- Your faction's crest (the same as the enemy faction badge) while you're flagged, and once
-- the flag is wearing off (IsPVPTimerRunning) the time left under it. The game may hide these
-- in combat; the last read stays. Previews show it wearing off.
local pvpOn, pvpEnds = false, nil

local function ReadPvP(now)
    local on = Clean(SafeCall(UnitIsPVP, "player"))
    local ffa = Clean(SafeCall(UnitIsPVPFreeForAll, "player"))
    if on ~= nil or ffa ~= nil then pvpOn = (on or ffa) and true or false end
    pvpEnds = nil
    if pvpOn and Clean(SafeCall(IsPVPTimerRunning)) then
        local ms = CleanNumber(SafeCall(GetPVPTimer))
        if ms and ms > 0 and ms < 600000 then pvpEnds = now + ms / 1000 end
    end
end

local function DrawPvP(key, fx, st, frame, geom, d, now)
    local mine = Clean(SafeCall(UnitFactionGroup, "player"))
    local f = FX.FACTIONS[mine]
    if not f then return end
    local left
    if not st.unit then
        left = 272 - (now % 60)
    else
        ReadPvP(now)
        if not pvpOn then return end
        left = pvpEnds and math.max(0, pvpEnds - now)
    end
    local x, y = Polar(BadgeAngle(key, "PvP"), geom.R)
    local t = Tex(fx, "pvp", f.icon, "OVERLAY", 3)
    if t.faction ~= mine then
        t.faction = mine
        t:SetTexture(f.icon)
        t:SetTexCoord(unpack(f.crop))
    end
    At(t, frame, x, y, d * 1.4)
    t:SetAlpha(1)
    if left then
        local fs = Text(fx, "pvp")
        TextSize(fs, math.max(8, math.floor(d * 0.55 + 0.5)))
        fs:SetText(ns.FormatTime(math.ceil(left)))
        fs:SetTextColor(1, 0.85, 0.2)
        fs:ClearAllPoints()
        fs:SetPoint("TOP", t, "BOTTOM", 0, 2)
        fs:Show()
    end
end

---------------------------------------------------------------------------
-- A resurrect or summon waiting
---------------------------------------------------------------------------
-- A resurrect: being cast on you (UnitHasIncomingResurrection) or offered (its popup is up).
-- A summon: C_SummonInfo's time left, or its popup. A soft glow round the ring breathing in and
-- out, gold for a resurrect, purple for a summon, glints circling it, and the summon's time
-- left under the ring.
local RES_POPUPS = { "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }

local function PopupUp(name) return StaticPopup_Visible and Clean(SafeCall(StaticPopup_Visible, name)) and true or false end

local function Waiting()
    local left = C_SummonInfo and CleanNumber(SafeCall(C_SummonInfo.GetSummonConfirmTimeLeft))
    if (left and left > 0) or PopupUp("CONFIRM_SUMMON") then return "summon", left end
    if Clean(SafeCall(UnitHasIncomingResurrection, "player")) then return "res" end
    for _, name in ipairs(RES_POPUPS) do
        if PopupUp(name) then return "res" end
    end
    return nil
end

local PENDING_COLOR = { res = { 1, 0.85, 0.45 }, summon = { 0.7, 0.4, 1 } }

local function DrawPending(key, fx, st, frame, geom, d, now)
    if not st.unit then return end
    local what, left = Waiting()
    if not what then return end
    local c = PENDING_COLOR[what]
    local breath = 0.5 + 0.5 * math.sin(now * 2.5)
    local glow = Tex(fx, "pendingGlow", GLOW, "OVERLAY", 3, true)
    GlowOn(glow, frame, geom.R + geom.T * (0.4 + 0.2 * breath))
    glow:SetVertexColor(c[1], c[2], c[3])
    glow:SetAlpha(0.45 + 0.35 * breath)
    for i = 1, 4 do
        local g = Tex(fx, "pendingGlint" .. i, STAR, "OVERLAY", 5, true)
        local x, y = Polar(now * 60 + i * 90, geom.R + geom.T * 0.6)
        At(g, frame, x, y, geom.T * 2)
        g:SetVertexColor(c[1], c[2], c[3])
        g:SetAlpha(0.8)
        if g.SetRotation then g:SetRotation(now * 3 + i) end
    end
    if what == "summon" and left and left > 0 then
        local fs = Text(fx, "pending")
        TextSize(fs, math.max(8, math.floor(d * 0.55 + 0.5)))
        fs:SetText("Summon " .. ns.FormatTime(math.ceil(left)))
        fs:SetTextColor(c[1], c[2], c[3])
        fs:ClearAllPoints()
        fs:SetPoint("TOP", frame, "CENTER", 0, -(geom.R + geom.T + 2))
        fs:Show()
    end
end
ns.VitalsFxWaiting = Waiting -- tests

-- For the files loaded after this one.
FX.DrawDurability = DrawDurability
FX.DrawLowMana = DrawLowMana
FX.DrawLeader = DrawLeader
FX.DrawPvP = DrawPvP
FX.DrawPending = DrawPending
