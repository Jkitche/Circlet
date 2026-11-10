-- Circlet: Gathering ring: mining, herbalism, skinning and fishing.
local ADDON_NAME, ns = ...

local db, IsSecret, CreateLiveRing = ns.db, ns.IsSecret, ns.CreateLiveRing
local SafeCall, SpellName = ns.SafeCall, ns.SpellName

---------------------------------------------------------------------------
-- Gathering ring
---------------------------------------------------------------------------
-- While you mine, pick herbs or skin, the ring fills with the cast and shows the
-- profession's icon. When it finishes it shows what you got ("Copper Ore ×2", with
-- the item's icon) for a few seconds. Fishing counts down the bobber instead, then
-- shows your catch. Interrupting a gather flashes the lost progress white, like the
-- crafting ring. Optionally the ring sits on what you're gathering (below).

-- Spells counted as gathering, by name (so every rank and client version matches):
-- the names are looked up from known spell IDs at load.
local GATHER_SPELLS = {
    { id = 2575, kind = "mining" },  -- Mining
    { id = 2366, kind = "herb" },    -- Herb Gathering
    { id = 8613, kind = "skinning" }, -- Skinning
    { id = 7620, kind = "fishing" }, -- Fishing
    { id = 2656, kind = "mining" },  -- Smelting is crafting, not gathering: excluded below
}
local GATHER_ICONS = {
    mining = "Interface\\Icons\\Trade_Mining",
    herb = "Interface\\Icons\\Trade_Herbalism",
    skinning = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    fishing = "Interface\\Icons\\Trade_Fishing",
}
local LABELS = { mining = "Mining", herb = "Herb Gathering", skinning = "Skinning", fishing = "Fishing" }

local kindByName, kindByID = nil, {}
local function GatherKind(name, spellID)
    if type(spellID) == "number" and not IsSecret(spellID) and kindByID[spellID] then return kindByID[spellID] end
    if not kindByName then
        kindByName = {}
        for _, s in ipairs(GATHER_SPELLS) do
            kindByID[s.id] = s.id ~= 2656 and s.kind or nil
            local n = SpellName(s.id)
            if n and s.id ~= 2656 then kindByName[n] = s.kind end
        end
        -- English names as a fallback if the lookups fail.
        for kind, label in pairs(LABELS) do kindByName[label] = kindByName[label] or kind end
    end
    if type(name) == "string" and not IsSecret(name) then return kindByName[name] end
end

local g = nil -- the current gather: { kind, name, icon, start, finish, channel, ended, how, lost, loot, follow }

-- With gatherFollow on, the ring sits on what you're gathering (the corpse, vein or herb)
-- and moves with it as the camera turns: see Layout/Follow.lua.

local function Progress(now)
    if not (g and g.start and g.finish) then return 0 end
    local span = g.finish - g.start
    if span <= 0 then return 0 end
    return math.max(0, math.min(1, (now - g.start) / span))
end

-- doneAt: when the result came in (the icon bursts then).
local function State(kind, title, frac, channel, ended, how, lost, endedAt, loot, waiting, caught, left, doneAt)
    local c = db.gatherColors
    local fill = kind == "fishing" and c.fishing or c.fill
    local st = { title = title, color = fill, icon = db.gatherIcon and GATHER_ICONS[kind] or nil }
    if ended and how == "done" then
        st.frac, st.color, st.labelColor = 1, c.done, c.done
        st.doneAt = doneAt
        if loot and loot.name then
            st.title = loot.name
            st.value = loot.count > 1 and ("×" .. loot.count) or ""
            st.icon = db.gatherIcon and (loot.icon or st.icon) or nil
            st.label = kind == "fishing" and "Caught!" or "Gathered"
        elseif kind == "fishing" and not caught then
            -- The catch comes in as loot just after the bobber goes; nothing means it got away.
            st.value = ""
            st.label = waiting and "Reeling in" or "Got away"
            if not waiting then st.color, st.labelColor, st.frac = c.fishing, nil, 0 end
        else
            st.value, st.label = "", kind == "fishing" and "Caught!" or "Gathered"
        end
        st.hold = db.gatherHold or 3
        return st
    end
    if ended then
        st.frac = channel and frac or 0
        st.value, st.label = "", channel and "Stopped" or "Interrupted"
        st.hold = db.gatherHold or 3
        if not channel and lost and lost > 0 then
            st.flashFrom, st.flashTo, st.flashAt = 0, lost, endedAt
        end
        return st
    end
    if channel then
        -- Fishing: the bobber's time counts down.
        st.frac = 1 - frac
        st.label = "Bobber"
    else
        st.frac = frac
        st.label = LABELS[kind] or "Gathering"
    end
    st.value = string.format("%d%%", math.floor(frac * 100 + 0.5))
    if channel then st.value = left and string.format("%ds", math.ceil(left)) or "" end
    return st
end

local gatherRing = CreateLiveRing({
    key = "gather",
    read = function(now)
        if not g then return nil end
        if g.endedAt and now - g.endedAt > 0.1 and not (g.how == "done" and g.lootUntil and now < g.lootUntil) then
            return nil -- end state shown; the ring holds it
        end
        local waiting = g.lootUntil and now < g.lootUntil - 0.15
        return State(g.kind, LABELS[g.kind], Progress(now), g.channel, g.endedAt ~= nil, g.how, g.lost, g.endedAt,
            db.gatherLoot and g.loot or nil, waiting, g.loot ~= nil,
            g.finish and math.max(0, g.finish - now) or nil, g.doneAt)
    end,
    follow = function(frame)
        if g and db.gatherFollow then return ns.FollowPoint(g.follow, frame) end -- (x, y: no and/or)
    end,
    sample = function(t)
        local cycle = t % 7
        if cycle < 2.5 then return State("mining", "Mining", cycle / 2.5, false) end
        if cycle < 5 then
            return State("mining", "Mining", 1, false, true, "done", nil, nil,
                { name = "Copper Ore", count = 2, icon = "Interface\\Icons\\INV_Ore_Copper_01" },
                nil, nil, nil, GetTime() - (cycle - 2.5))
        end
        return State("herb", "Herb Gathering", (cycle - 5) / 1.5, false)
    end,
})

local function End(how)
    if not g or g.endedAt then return end
    local now = GetTime()
    if how ~= "done" then g.lost = Progress(now) end
    g.how, g.endedAt = how, now
    -- Give the loot message a moment to arrive before the ring settles.
    if how == "done" then g.lootUntil = now + 1.5 end
    -- The icon bursts when it's done (fishing: once something is caught, see OnLoot).
    if how == "done" and g.kind ~= "fishing" then g.doneAt = now end
    -- Fishing only counts once a catch comes in (see OnLoot).
    if how == "done" and g.kind ~= "fishing" and ns.SessionAdd then ns.SessionAdd("gathers", nil, 1) end
end

---------------------------------------------------------------------------
-- Loot: "You receive loot: [Copper Ore]x2."
---------------------------------------------------------------------------
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("%%%d%$", "%%")
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end
local LOOT_MULTI = ToPattern(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.")
local LOOT_ONE = ToPattern(LOOT_ITEM_SELF or "You receive loot: %s.")

local function OnLoot(msg)
    if not (g and g.endedAt and g.how == "done") or IsSecret(msg) or type(msg) ~= "string" then return end
    if GetTime() - g.endedAt > 3 then return end
    local link, count = msg:match(LOOT_MULTI or "^$")
    if not link then link = msg:match(LOOT_ONE or "^$") count = 1 end
    if not link then return end
    local name = link:match("%[(.-)%]") or link
    local itemID = tonumber(link:match("item:(%d+)"))
    local icon = itemID and C_Item and C_Item.GetItemIconByID and SafeCall(C_Item.GetItemIconByID, itemID)
    -- The first item is the main one (ore, herb, leather, fish); others are bonuses.
    if not g.loot then
        -- The result is in: burst now, unless the gather's own burst has only just started
        -- (the item's icon takes over mid-burst instead of bursting twice).
        local now = GetTime()
        if not g.doneAt or now - g.doneAt > 0.35 then g.doneAt = now end
        if g.kind == "fishing" and ns.SessionAdd then ns.SessionAdd("gathers", nil, 1) end
        g.loot = { name = name, count = tonumber(count) or 1, icon = (not IsSecret(icon)) and icon or nil }
    elseif g.loot.name == name then
        g.loot.count = g.loot.count + (tonumber(count) or 1)
    end
    g.lootUntil = math.min(g.lootUntil or 0, GetTime() + 0.3)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen({ "UNIT_SPELLCAST_START:player", "UNIT_SPELLCAST_SUCCEEDED:player", "UNIT_SPELLCAST_INTERRUPTED:player", "UNIT_SPELLCAST_FAILED:player", "UNIT_SPELLCAST_CHANNEL_START:player", "UNIT_SPELLCAST_CHANNEL_STOP:player", "CHAT_MSG_LOOT" }, function(event, unit, castGUID, spellID)
    if not CircletDB or not db.gatherEnabled then return end
    if event == "CHAT_MSG_LOOT" then
        OnLoot(unit)
        return
    end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        local channel = event == "UNIT_SPELLCAST_CHANNEL_START"
        local name, _, _, startMS, endMS = SafeCall(channel and UnitChannelInfo or UnitCastingInfo, "player")
        local kind = GatherKind(name, spellID)
        if not kind then return end
        g = { kind = kind, spellID = spellID, channel = channel, follow = db.gatherFollow and ns.InteractTarget(castGUID, spellID) or nil }
        if type(startMS) == "number" and type(endMS) == "number" and not IsSecret(startMS) and not IsSecret(endMS) then
            g.start, g.finish = startMS / 1000, endMS / 1000
        end
        return
    end
    if not g or g.endedAt then return end
    if spellID and g.spellID and spellID ~= g.spellID and not IsSecret(spellID) then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not g.channel then End("done") end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- Fishing ends when you click the bobber (a catch comes in as loot) or it times out.
        End("done")
    else
        End(g.channel and "stopped" or "interrupted")
    end
end)

-- Shared with the files loaded after this one.
ns.gatherRing = gatherRing
ns.GatherActive = function() return g ~= nil and g.endedAt == nil end
ns.PreviewGatherRing = function() gatherRing.Preview(14) end


---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "gather", name = "Gathering", order = 13,
    iconBg = true, -- the icon can be the ring's background (Core/Settings.lua, UI/OptionsKit.lua)
    ring = gatherRing,
    preview = ns.PreviewGatherRing, slash = { "gather", "gathering" }, help = "preview the gathering ring",
    toggle = { "Gathering ring", "Mining, herbalism, skinning and fishing, then what you got." },
    gameBar = "the game's cast bar while gathering",
    defaults = {
        -- Gathering ring: mining, herbalism, skinning and fishing casts, then what you got.
        -- Shares the crafting ring's spot (you never do both at once).
        gatherEnabled   = true,
        gatherIcon      = true,  -- profession / item icon in the middle
        gatherLoot      = true,  -- show what you gathered when it finishes
        gatherFollow    = false, -- the ring sits on what you're gathering (Layout/Follow.lua)
        gatherSize      = 110,
        gatherThickness = 11,
        gatherOpacity   = 100,
        gatherX         = 0,
        gatherFromTop   = 260,
        gatherHold      = 3,
        gatherStyle     = "smooth",
        gatherBorder    = 2,
        gatherColors = {
            fill    = { r = 0.45, g = 0.85, b = 0.35 },
            fishing = { r = 0.30, g = 0.65, b = 1.00 },
            done    = { r = 1.00, g = 0.82, b = 0.25 },
        },
    },
    page = { folder = "professions", order = 2, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(12, "Gathering", "Gathering Ring",
                "While you mine, pick herbs or skin, the ring fills with the cast and shows the profession's icon. "
                .. "Fishing drains as the bobber waits. When it finishes it shows what you got (Copper Ore ×2). "
                .. "Interrupting a gather flashes the progress you lost.",
                MergeTop(TopRow("gather", "gathering ring", ns.PreviewGatherRing,
                    "Show a sample mining and herb gather. Also /circ gather."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "gatherEnabled", "Show gathering ring", "Show the ring while gathering or fishing."),
                        icon = Toggle(2, "gatherIcon", "Show icon",
                            "The profession's icon while gathering, and the item's icon when it's done."),
                        loot = Toggle(3, "gatherLoot", "Show what you got",
                            "When the gather finishes, show the item and how many you got."),
                        follow = Toggle(4, "gatherFollow", "Follow what you're gathering",
                            "The ring sits on the corpse, vein or herb you're gathering and moves with it as you turn "
                            .. "the camera. Turns on the game's nameplate for what you're facing (soft interact must be "
                            .. "on), which also shows at other times; turning this off sets it back. If it doesn't "
                            .. "follow, /circ follow shows why.",
                            function() ns.ApplyFollowCVar() end),
                    }),
                    colors = Box(3, "Colors", {
                        fill = Color(1, "gatherColors", "fill", "Gathering", "Ring color while mining, picking or skinning."),
                        fishing = Color(2, "gatherColors", "fishing", "Fishing", "Ring color while fishing."),
                        done = Color(3, "gatherColors", "done", "Done", "Ring and label color when you get the goods."),
                    }),
                    size = SizeBox(4, "gather", "gathering ring",
                        "Offset from the center of the screen. By default it shares the crafting ring's spot."),
                }))
            tab.args.size.args.hold.desc = "How long the ring stays after the gather ends."
            return tab
        end },
})
