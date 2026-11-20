-- Circlet: /circ swingprobe: what this client tells addons about melee swings (temporary).
local ADDON_NAME, ns = ...

local Print, IsSecret = ns.Print, ns.IsSecret

---------------------------------------------------------------------------
-- Swing probe
---------------------------------------------------------------------------
-- For working out a melee swing timer without the combat log. For 30 seconds, prints every
-- event that could mark a swing (or the start and end of auto-attack), with the time since
-- the probe started and which values are hidden ("secret"). Also your attack speed at the
-- start and whenever it changes.

local EVENTS = {
    "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "UNIT_ATTACK_SPEED", "UNIT_COMBAT", "UNIT_SPELLCAST_SUCCEEDED",
    "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_COMBAT_SELF_MISSES", "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS",
    "COMBAT_TEXT_UPDATE", "START_AUTOREPEAT_SPELL", -- not the combat log: registering it is blocked here
    "STOP_AUTOREPEAT_SPELL", "UNIT_TARGET",
}
local LIMIT = 80 -- lines, so a long fight doesn't flood chat

local probe = CreateFrame("Frame")
local started, lines, running = 0, 0, false

local function Show(v)
    if IsSecret(v) then return "<secret>" end
    if type(v) == "number" then return (string.format("%.3f", v):gsub("%.?0+$", "")) end
    if type(v) == "string" and #v > 40 then return v:sub(1, 40) .. "..." end
    return tostring(v)
end

local function Speed()
    local ok, main, off = pcall(UnitAttackSpeed, "player")
    if not ok then return "UnitAttackSpeed errors: " .. tostring(main) end
    return "attack speed " .. Show(main) .. (off and (" / off-hand " .. Show(off)) or "")
end

local function Line(text)
    if lines >= LIMIT then return end
    lines = lines + 1
    Print(string.format("%.2f %s", GetTime() - started, text))
    if lines == LIMIT then Print("(probe: line limit reached)") end
end

probe:SetScript("OnEvent", function(_, event, ...)
    if not running then return end
    local n = select("#", ...)
    local args = {}
    for i = 1, math.min(n, 6) do args[i] = Show((select(i, ...))) end
    -- Only the player's and target's unit events (others are noise).
    if event == "UNIT_COMBAT" or event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_ATTACK_SPEED" or event == "UNIT_TARGET" then
        local unit = select(1, ...)
        if unit ~= "player" and unit ~= "target" then return end
    end
    local extra = ""
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local id = select(3, ...)
        local name = not IsSecret(id) and ns.SpellName(id) or nil
        extra = name and (" (" .. name .. ")") or ""
    elseif event == "UNIT_ATTACK_SPEED" then
        extra = " -> " .. Speed()
    end
    Line(event .. " " .. table.concat(args, " ") .. extra)
end)

local function Stop()
    if not running then return end
    running = false
    probe:UnregisterAllEvents()
    Print("Swing probe finished.")
end

local function Start()
    if running then Stop() return end
    running, lines, started = true, 0, GetTime()
    local missing = {}
    for _, e in ipairs(EVENTS) do
        if not pcall(probe.RegisterEvent, probe, e) then table.insert(missing, e) end
    end
    Print("Swing probe: 30 seconds. Start auto-attacking something. " .. Speed())
    Print("Auto Attack current: " .. Show(ns.SafeCall(IsCurrentSpell, 6603))
        .. "; events this client refused: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
    C_Timer.After(30, Stop)
end

ns.RegisterCommand({ "swingprobe" }, Start)
