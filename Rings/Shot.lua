-- Circlet: Shot timer ring: time to your next Auto Shot (or wand shot, or throw).
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall, CleanNumber = ns.db, ns.CreateLiveRing, ns.SafeCall, ns.CleanNumber

---------------------------------------------------------------------------
-- Shot timer ring
---------------------------------------------------------------------------
-- While Auto Shot (or a wand's Shoot, or Throw) repeats, the ring fills over your ranged
-- weapon's speed and counts down to the next shot. Auto Shot's last half second is its aim:
-- moving then holds the shot back, so the ring turns its own color for it, and the label
-- says "Hold still" if you're moving in it.
--
-- Each shot comes as a cast of the shot spell (UNIT_SPELLCAST_SUCCEEDED), which this client
-- lets addons see in combat; auto-repeat starting and stopping as START/STOP_AUTOREPEAT_SPELL;
-- the speed from UnitRangedDamage (or, if that's hidden, the time between your last shots).
-- Casting something else (Aimed Shot, a spell) shows "Casting" until it's done.

local SHOTS = { 75, 5019, 2764 } -- Auto Shot, Shoot (wands), Throw (every rank by name)
local AIM = 0.5                  -- Auto Shot's aim: the last half second
local SAMPLE_SPEED = 2.8

local repeating = false
local last, lastWasAuto -- GetTime() of your last shot, and whether it was Auto Shot
local casting
local measured

local shotByID, shotByName = {}, nil
for _, id in ipairs(SHOTS) do shotByID[id] = true end

local function IsShot(spellID)
    if not spellID then return false end
    if shotByID[spellID] then return true end
    if not shotByName then
        local names, any = {}, false
        for id in pairs(shotByID) do
            local n = ns.SpellName(id)
            if n then names[n], any = true, true end
        end
        if not any then return false end
        shotByName = names
    end
    local n = ns.SpellName(spellID)
    return n and shotByName[n] or false
end

local function Speed()
    local s = CleanNumber(SafeCall(UnitRangedDamage, "player"))
    if s and s > 0 then return s end
    return measured or 2.5
end

local function Moving()
    local s = CleanNumber(SafeCall(GetUnitSpeed, "player"))
    return s ~= nil and s > 0
end

local function RangedIcon()
    return SafeCall(GetInventoryItemTexture, "player", 18) or "Interface\\Icons\\INV_Weapon_Bow_02"
end

-- auto: Auto Shot (has the aim at the end). moving: you're moving right now.
local function State(elapsed, speed, auto, moving, icon)
    local c = db.shotColors
    local left = speed - elapsed
    local st = { title = "Shot", icon = icon, hold = 0.4, label = "" }
    if left <= 0.05 then
        st.frac, st.value, st.color = 1, "Ready", c.ready
        if auto and moving and db.shotAim then st.label, st.labelColor = "Hold still", c.aim end
        return st
    end
    st.frac = math.min(1, elapsed / speed)
    st.value = string.format("%.1f", left)
    st.color = c.fill
    if auto and db.shotAim and left <= AIM then
        st.color = c.aim
        st.label = moving and "Hold still" or "Aiming"
        st.labelColor = c.aim
    end
    return st
end

local shotRing = CreateLiveRing({
    key = "shot",
    watchEvery = 0.1,
    read = function(now)
        if not repeating then return nil end
        if casting then
            return { title = "Shot", frac = 0, value = "", label = "Casting", color = db.shotColors.fill,
                     icon = RangedIcon(), hold = 0.4 }
        end
        local speed = Speed()
        if not last then return State(speed, speed, true, Moving(), RangedIcon()) end
        return State(now - last, speed, lastWasAuto, Moving(), RangedIcon())
    end,
    sample = function(t)
        local elapsed = t % SAMPLE_SPEED
        -- Every third shot, "moving" through the aim, to show Hold still.
        local moving = math.floor(t / SAMPLE_SPEED) % 3 == 2
        return State(elapsed, SAMPLE_SPEED, true, moving, "Interface\\Icons\\INV_Weapon_Bow_02")
    end,
})

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen({ "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL" }, function(event)
    repeating = event == "START_AUTOREPEAT_SPELL"
    if not repeating then casting = nil end
end)

ns.Listen({ "UNIT_SPELLCAST_START:player", "UNIT_SPELLCAST_STOP:player", "UNIT_SPELLCAST_SUCCEEDED:player",
            "UNIT_SPELLCAST_INTERRUPTED:player", "UNIT_SPELLCAST_FAILED:player" }, function(event, _, _, spellID)
    local id = CleanNumber(spellID)
    local shot = IsShot(id)
    if event == "UNIT_SPELLCAST_START" then
        if not shot then casting = GetTime() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if shot then
            local now = GetTime()
            if last then
                local gap = now - last
                if gap > 0.5 and gap < 6 then measured = gap end
            end
            last, lastWasAuto = now, (id == 75) or (ns.SpellName(id) == ns.SpellName(75))
        else
            casting = nil
        end
    elseif not shot then
        casting = nil
    end
end)

ns.shotRing = shotRing
ns.PreviewShotRing = function() shotRing.Preview(SAMPLE_SPEED * 3) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "shot", name = "Shot", order = 14.3, since = "1.5.0",
    iconBg = true,
    ring = shotRing,
    gameBar = "the game's ranged swing timer bar", -- WoW Forever's own (Features/DefaultUI.lua)
    alwaysInCombat = true,
    preview = ns.PreviewShotRing, slash = { "shot", "autoshot" }, help = "preview the shot timer ring",
    toggle = { "Shot timer ring", "Time to your next Auto Shot, wand shot or throw." },
    defaults = {
        -- Shot timer ring: left of the swing timer ring.
        shotEnabled   = true,
        shotAim       = true, -- Auto Shot's last half second (the aim) in its own color
        shotSize      = 80,
        shotThickness = 8,
        shotOpacity   = 100,
        shotX         = -255,
        shotFromTop   = 385,
        shotHold      = 0.4,
        shotStyle     = "smooth",
        shotBorder    = 2,
        shotColors = {
            fill  = { r = 0.45, g = 0.80, b = 0.40 },
            aim   = { r = 1.00, g = 0.40, b = 0.30 },
            ready = { r = 0.75, g = 1.00, b = 0.60 },
        },
    },
    page = { folder = "combat", order = 1.6, build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            return RingTab(13.3, "Shot timer", "Shot Timer Ring",
                "While Auto Shot repeats (or a wand's Shoot, or Throw), the ring fills over your ranged weapon's "
                .. "speed and counts down to the next shot. Auto Shot's last half second is its aim, when moving holds "
                .. "the shot back: the ring turns its own color for it, and the label says Hold still if you're moving.",
                MergeTop(TopRow("shot", "shot timer ring", ns.PreviewShotRing,
                    "Show a few sample shots. Also /circ shot."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "shotEnabled", "Show shot timer ring",
                            "Show the ring while Auto Shot, Shoot or Throw repeats."),
                        aim = Toggle(2, "shotAim", "Show Auto Shot's aim",
                            "Turn the ring the Aiming color for the last half second (when moving holds the shot back), and say "
                            .. "Hold still if you're moving."),
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "shotColors", "fill", "Reloading", "Ring color until the aim."),
                        aim = Color(2, "shotColors", "aim", "Aiming", "Ring color for Auto Shot's last half second."),
                        ready = Color(3, "shotColors", "ready", "Ready", "Ring color once the shot is ready."),
                    }),
                    size = SizeBox(4, "shot", "shot timer ring", "Offset from the center of the screen."),
                }))
        end },
})
