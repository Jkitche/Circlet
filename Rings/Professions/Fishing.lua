-- Circlet: Fishing ring: the bobber's time, bobbing while you wait, flashing when a bite can come.
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing, SafeCall, SpellName =
    ns.db, ns.IsSecret, ns.CreateLiveRing, ns.SafeCall, ns.SpellName

---------------------------------------------------------------------------
-- Fishing ring
---------------------------------------------------------------------------
-- While your line is out the ring drains over the cast's time and bobs on the screen like
-- a float: a gentle swell with now and then a little tug, never the same twice. The game
-- doesn't tell addons when a fish bites (only the splash sound does), so the ring flashes
-- "Watch the bobber!" at the moments a splash can come instead: with about 17, 13, 7 and
-- 3 seconds left. When the line comes in it shows what you caught (with its icon, and a
-- burst), "Got away" if time ran out, or "Reeled in" if it ended with nothing.
--
-- Reel in with right-click (fishReel, off by default): while the line is out, and out of
-- combat, right-click anywhere in the world uses the game's Interact action on the bobber
-- (an override binding of BUTTON2 to INTERACTTARGET), with soft-interact targeting widened
-- so the bobber is the interact target. All of it is put back when the line comes in or a
-- fight starts; the CVars it changed are saved, so they're put back at the next login too
-- if the game closed mid-cast.
--
-- While this ring is on it handles fishing, and the gathering ring leaves fishing to it.

local ICON = "Interface\\Icons\\Trade_Fishing"
local FISHING_ID = 7620
local DEFAULT_TIME = 30 -- the cast's length if the game won't say
local WINDOWS = { 17, 13, 7, 3 } -- seconds left when a splash can come
local WINDOW_HALF = 0.7 -- each window: this long either side
local LOOT_WAIT = 1.5 -- how long the catch has to come in as loot after the line does

local fishName
local function IsFishing(name, spellID)
    if type(spellID) == "number" and not IsSecret(spellID) and spellID == FISHING_ID then return true end
    fishName = fishName or SpellName(FISHING_ID) or "Fishing"
    return type(name) == "string" and not IsSecret(name) and (name == fishName or name == "Fishing")
end

local f -- the line: { start, finish, seed, tugs, endedAt, how, loot, lootUntil, doneAt }

-- The bite window `left` seconds falls in, or nil.
local function Window(left)
    if not db.fishWindows then return nil end
    for _, w in ipairs(WINDOWS) do
        if math.abs(left - w) <= WINDOW_HALF then return w end
    end
end

local function State(left, total, loot, how, doneAt, waiting, finish)
    local c = db.fishColors
    local st = { title = "Fishing", icon = db.fishIcon and ICON or nil, color = c.fill }
    if how then
        st.hold = db.fishHold or 4
        if loot and loot.name then
            st.title, st.value = loot.name, loot.count > 1 and ("×" .. loot.count) or ""
            st.icon = db.fishIcon and (loot.icon or ICON) or nil
            st.label, st.labelColor, st.color, st.frac, st.doneAt = "Caught!", c.caught, c.caught, 1, doneAt
        elseif waiting then
            st.value, st.label, st.frac = "", "Reeling in", 1
        else
            st.value, st.frac = "", 0
            st.label = how == "timeout" and "Got away" or "Nothing caught"
        end
        return st
    end
    st.bob = true
    st.frac = total > 0 and math.max(0, math.min(1, left / total)) or 0
    st.value = tostring(math.max(0, math.ceil(left)))
    local w = Window(left)
    if w then
        st.watch = true
        st.label, st.labelColor, st.color = "Watch the bobber!", c.watch, c.watch
        -- The whole ring blinks, from the start of the window.
        if finish then
            st.flashFrom, st.flashTo, st.flashAt = 0, 1, finish - w - WINDOW_HALF
        end
    else
        st.label = db.fishReel and "Right-click to reel in" or "Waiting for a bite"
    end
    return st
end

---------------------------------------------------------------- the bob
-- A float on water: two slow swells, and a little tug down every few seconds; bigger in a
-- bite window. The same seed gives the same motion, so it doesn't jitter frame to frame.
local function Bob(t, seed, tugs, watch)
    local y = 2.2 * math.sin(t * 1.6 + seed) + 1.2 * math.sin(t * 2.9 + seed * 1.7)
    for _, at in ipairs(tugs) do
        local d = t - at
        if d >= 0 and d < 0.45 then y = y - 5 * math.sin(math.pi * d / 0.45) end
    end
    if watch then y = y + 3.5 * math.sin(t * 9) end
    return y
end

local function NewTugs(seed, length)
    local tugs, at = {}, 1.5 + (seed % 1) * 2
    local r = seed
    while at < length do
        table.insert(tugs, at)
        r = (r * 9301 + 49297) % 233280
        at = at + 2 + (r / 233280) * 3.5
    end
    return tugs
end

local sampleSeed, sampleTugs = 1.3, NewTugs(1.3, 40)

-- The fill's edge bobs about the countdown, like a float on the water (the ring stays put).
local BOB_SCALE = 0.005 -- of a turn per unit of Bob: about ±2% swells, 2.5% tugs
local BOB_MAX = 0.05 -- never more than 5% of the ring either way
local function Bobbed(st, t, seed, tugs)
    if st and st.bob then
        local d = math.max(-BOB_MAX, math.min(BOB_MAX, BOB_SCALE * Bob(t, seed, tugs, st.watch)))
        st.frac = math.max(0, math.min(1, st.frac + d))
    end
    return st
end

local fishRing = CreateLiveRing({
    key = "fish",
    read = function(now)
        if not f then return nil end
        if f.endedAt then
            local waiting = f.lootUntil and now < f.lootUntil and not f.loot
            if now - f.endedAt > 0.1 and not waiting then
                -- Handed to the ring once (it holds it); the result is set.
                f.resultAt = f.resultAt or now
                if now - f.resultAt > 0.1 then
                    f = nil
                    return nil
                end
            end
            return State(0, 0, db.fishLoot ~= false and f.loot or nil, f.how, f.doneAt, waiting)
        end
        local total = (f.finish - f.start)
        return Bobbed(
            State(math.max(0, f.finish - now), total, nil, nil, nil, nil, f.finish),
            now - f.start,
            f.seed,
            f.tugs
        )
    end,
    sample = function(t)
        -- 20 seconds of waiting (a bite window at 17, then 13), then a catch.
        local cycle = t % 16
        if cycle < 11 then
            local left = 20 - cycle
            return Bobbed(State(left, 30, nil, nil, nil, nil, GetTime() + left), t, sampleSeed, sampleTugs)
        end
        return State(
            0,
            0,
            { name = "Raw Brilliant Smallfish", count = 1, icon = "Interface\\Icons\\INV_Misc_Fish_02" },
            "done",
            GetTime() - (cycle - 11)
        )
    end,
})

---------------------------------------------------------------- reel in with right-click
local reelOwner = CreateFrame("Frame")
local reelOn = false
local REEL_CVARS = { SoftTargetInteract = "3", SoftTargetInteractArc = "2", SoftTargetInteractRange = "60" }

local function GetCV(name)
    return (C_CVar and C_CVar.GetCVar and SafeCall(C_CVar.GetCVar, name)) or (GetCVar and SafeCall(GetCVar, name))
end
local function SetCV(name, value)
    if C_CVar and C_CVar.SetCVar then return pcall(C_CVar.SetCVar, name, value) end
    if SetCVar then return pcall(SetCVar, name, value) end
end

-- Puts back the CVars the reel-in changed (saved, so this works after a reload too).
local function RestoreCVars()
    if not db.fishSavedCVars then return end
    for name, value in pairs(db.fishSavedCVars) do
        SetCV(name, value)
    end
    db.fishSavedCVars = nil
end

local function ReelOff()
    if InCombatLockdown and InCombatLockdown() then return end -- (PLAYER_REGEN_DISABLED already did it)
    if reelOn and ClearOverrideBindings then pcall(ClearOverrideBindings, reelOwner) end
    reelOn = false
    RestoreCVars()
end

local function ReelOn()
    if reelOn or not db.fishReel then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not (SetOverrideBinding and ClearOverrideBindings) then return end
    local saved = db.fishSavedCVars or {}
    for name, value in pairs(REEL_CVARS) do
        local old = GetCV(name)
        if old ~= nil and saved[name] == nil then
            saved[name] = old
            SetCV(name, value)
        end
    end
    db.fishSavedCVars = next(saved) and saved or nil
    SetOverrideBinding(reelOwner, true, "BUTTON2", "INTERACTTARGET")
    reelOn = true
end

---------------------------------------------------------------- the line out and in
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("%%%d%$", "%%")
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end
local LOOT_MULTI = ToPattern(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.")
local LOOT_ONE = ToPattern(LOOT_ITEM_SELF or "You receive loot: %s.")

local function Cast()
    local now = GetTime()
    local _, _, _, startMS, endMS = SafeCall(UnitChannelInfo, "player")
    local start, finish = now, now + DEFAULT_TIME
    if
        type(startMS) == "number"
        and type(endMS) == "number"
        and not IsSecret(startMS)
        and not IsSecret(endMS)
        and endMS > startMS
    then
        start, finish = startMS / 1000, endMS / 1000
    end
    local seed = math.random() * 10
    f = { start = start, finish = finish, seed = seed, tugs = NewTugs(seed, finish - start + 5) }
    fishRing.frame:Show()
    ReelOn()
end

local function LineIn()
    if not f or f.endedAt then return end
    local now = GetTime()
    f.endedAt = now
    f.how = (f.finish - now) < 1 and "timeout" or "done"
    f.lootUntil = now + LOOT_WAIT
    -- Leave right-click as Interact a moment longer, for the loot window.
    if C_Timer and C_Timer.After then
        C_Timer.After(1, ReelOff)
    else
        ReelOff()
    end
end

local function OnLoot(msg)
    if not (f and f.endedAt) or type(msg) ~= "string" or IsSecret(msg) then return end
    if GetTime() - f.endedAt > 3 then return end
    local link, count = msg:match(LOOT_MULTI or "^$")
    if not link then
        link = msg:match(LOOT_ONE or "^$")
        count = 1
    end
    if not link then return end
    local name = link:match("%[(.-)%]") or link
    local itemID = tonumber(link:match("item:(%d+)"))
    local icon = itemID and C_Item and C_Item.GetItemIconByID and SafeCall(C_Item.GetItemIconByID, itemID)
    if not f.loot then
        f.loot = { name = name, count = tonumber(count) or 1, icon = (not IsSecret(icon)) and icon or nil }
        f.doneAt, f.how = GetTime(), "done"
        if ns.SessionAdd then ns.SessionAdd("gathers", nil, 1) end
    elseif f.loot.name == name then
        f.loot.count = f.loot.count + (tonumber(count) or 1)
    end
end

ns.Listen({
    "UNIT_SPELLCAST_CHANNEL_START:player",
    "UNIT_SPELLCAST_CHANNEL_STOP:player",
    "CHAT_MSG_LOOT",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD",
}, function(event, a1, _, spellID)
    if not CircletDB then return end
    if event == "PLAYER_ENTERING_WORLD" then
        if not reelOn then RestoreCVars() end -- left over from a cast the game closed during
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- A fight: bindings can't change in combat, so give right-click back now.
        if reelOn and ClearOverrideBindings then pcall(ClearOverrideBindings, reelOwner) end
        reelOn = false
        RestoreCVars()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if f and not f.endedAt then ReelOn() end
    elseif not db.fishEnabled then
        return
    elseif event == "CHAT_MSG_LOOT" then
        OnLoot(a1)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local name = SafeCall(UnitChannelInfo, "player")
        if IsFishing(name, spellID) then Cast() end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        LineIn()
    end
end)

local function PreviewFishRing() fishRing.Preview(16) end

-- Shared with the files loaded after this one: the gathering and cast rings leave fishing
-- to this ring while it's on.
ns.fishRing = fishRing
ns.PreviewFishRing = PreviewFishRing
ns.FishingRingOn = function() return CircletDB ~= nil and db.fishEnabled and true or false end
ns.FishingActive = function() return f ~= nil and f.endedAt == nil end
ns.FishReelOff = ReelOff

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "fish",
    name = "Fishing",
    order = 13.5,
    since = "1.3.0",
    iconBg = true, -- "Icon as background": the fishing pole fills the ring's middle
    ring = fishRing,
    preview = PreviewFishRing,
    slash = { "fish", "fishing" },
    help = "preview the fishing ring",
    toggle = { "Fishing ring", "The bobber's time, bobbing while you wait and flashing when a bite can come." },
    defaults = {
        -- Fishing ring: the bobber's time. Where the gathering ring sits (they take turns).
        fishEnabled = true,
        fishIcon = true,
        fishWindows = true, -- flash at the moments a bite can come
        fishReel = false, -- right-click to reel in (changes a binding and soft-interact CVars while fishing)
        fishLoot = true, -- show what you caught
        fishSize = 110,
        fishThickness = 11,
        fishOpacity = 100,
        fishX = 0,
        fishFromTop = 260,
        fishHold = 4,
        fishStyle = "smooth",
        fishBorder = 2,
        fishColors = {
            fill = { r = 0.30, g = 0.65, b = 1.00 },
            watch = { r = 1.00, g = 0.85, b = 0.30 },
            caught = { r = 0.40, g = 0.90, b = 0.40 },
        },
    },
    page = {
        folder = "professions",
        order = 2.5,
        build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(
                12.5,
                "Fishing",
                "Fishing Ring",
                "While your line is out the ring drains over the cast's time and bobs like a float. The game doesn't "
                    .. "tell addons when a fish bites (only the splash sound does), so the ring flashes |cffffd100Watch the "
                    .. "bobber!|r at the moments a bite can come: with about 17, 13, 7 and 3 seconds left. When the line "
                    .. "comes in it shows what you caught. While this ring is on, it handles fishing instead of the "
                    .. "gathering ring.",
                MergeTop(
                    TopRow(
                        "fish",
                        "fishing ring",
                        ns.PreviewFishRing,
                        "Show a sample of waiting for a bite, then a catch. Also /circ fish."
                    ),
                    {
                        general = Box(2, "General", {
                            enabled = Toggle(
                                1,
                                "fishEnabled",
                                "Show fishing ring",
                                "Show the ring while your line is out."
                            ),
                            icon = Toggle(2, "fishIcon", "Show icon", "The fishing pole, then what you caught."),
                            windows = Toggle(
                                3,
                                "fishWindows",
                                "Flash when a bite can come",
                                'Flash "Watch the bobber!" with about 17, 13, 7 and 3 seconds left, when a splash can come.'
                            ),
                            loot = Toggle(
                                4,
                                "fishLoot",
                                "Show the catch",
                                "When the line comes in, show what you caught."
                            ),
                            reel = Toggle(
                                5,
                                "fishReel",
                                "Right-click to reel in",
                                "While your line is out (out of combat), right-click anywhere in the world reels in, using the "
                                    .. "game's Interact action on the bobber. Circlet widens the game's soft-interact targeting "
                                    .. "while you fish so the bobber is the one picked, and puts right-click and those settings back "
                                    .. "when the line comes in or a fight starts.",
                                function(v)
                                    if not v then ns.FishReelOff() end
                                end
                            ),
                        }),
                        colors = Box(3, "Colors", {
                            fill = Color(1, "fishColors", "fill", "Waiting", "Ring color while the line is out."),
                            watch = Color(2, "fishColors", "watch", "Watch!", "Color it flashes when a bite can come."),
                            caught = Color(3, "fishColors", "caught", "Caught", "Ring color when you catch something."),
                        }),
                        size = SizeBox(
                            4,
                            "fish",
                            "fishing ring",
                            "Offset from the center of the screen. By default it sits where the gathering ring does."
                        ),
                    }
                )
            )
            tab.args.size.args.hold.desc = "How long the catch stays after the line comes in."
            return tab
        end,
    },
})
