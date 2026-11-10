-- Circlet: Ammo ring: arrows, bullets, thrown weapons and a warlock's soul shards.
local ADDON_NAME, ns = ...

local CreateProgressRing, IsSecret, SafeCall, db = ns.CreateProgressRing, ns.IsSecret, ns.SafeCall, ns.db

---------------------------------------------------------------------------
-- Ammo ring: arrows, bullets and thrown weapons (and a warlock's soul shards)
---------------------------------------------------------------------------
-- Quiet while you have plenty. At or below the warning level it pops up each time
-- the count drops another quarter of that level, and again when you run out. Buying
-- more shows the restock. The ring fills against the most you've carried since your
-- last restock.
--
-- ammoAlways: it shows on every shot instead, counting down (ammo only, not shards).
-- ammoFlash: at or below this % of that most-carried amount the ring flashes (0 = never).
-- When the game hides the count (a secret value), nothing shows and the last count is
-- kept, so the next one that can be read carries on from it.

local SOUL_SHARD = 6265
local ammoState = { ammo = {}, shards = {} }

local function ItemName(itemID)
    local name = (C_Item and C_Item.GetItemNameByID and SafeCall(C_Item.GetItemNameByID, itemID))
        or (GetItemInfo and SafeCall(GetItemInfo, itemID))
    return type(name) == "string" and not IsSecret(name) and name or nil
end

local function ItemCount(itemID)
    local count = (C_Item and C_Item.GetItemCount and SafeCall(C_Item.GetItemCount, itemID))
        or (GetItemCount and SafeCall(GetItemCount, itemID))
    return type(count) == "number" and not IsSecret(count) and count or nil
end

-- What's in the ammo slot (or a thrown weapon in the ranged slot): count, name, icon.
local function ReadAmmo()
    local ammoSlot = INVSLOT_AMMO or 0
    local id = SafeCall(GetInventoryItemID, "player", ammoSlot)
    local slot = id and ammoSlot
    if not id then
        local ranged = INVSLOT_RANGED or 18
        local rid = SafeCall(GetInventoryItemID, "player", ranged)
        local equipLoc = rid and C_Item and C_Item.GetItemInfoInstant
            and select(4, SafeCall(C_Item.GetItemInfoInstant, rid))
        if equipLoc == "INVTYPE_THROWN" then id, slot = rid, ranged end
    end
    if not id then return nil end
    if IsSecret(id) then return nil, nil, nil, nil, true end
    local count = SafeCall(GetInventoryItemCount, "player", slot)
    if IsSecret(count) then return nil, nil, nil, nil, true end
    if type(count) ~= "number" then return nil end
    local icon = SafeCall(GetInventoryItemTexture, "player", slot)
        or (C_Item and C_Item.GetItemIconByID and SafeCall(C_Item.GetItemIconByID, id))
    return count, ItemName(id) or "Ammo", icon, id
end

local ammoRing -- created below; CheckAmmoKind queues into it

-- kind: "ammo" or "shards". warn: the level at or below which the ring shows.
-- hidden: the game is keeping the count secret right now; keep what we had.
-- always: show every change, not just the warnings.
local function CheckAmmoKind(kind, count, name, icon, itemID, warn, hidden, always)
    local st = ammoState[kind]
    if hidden then return end
    if not count then st.count = nil return end
    if st.count == nil or st.itemID ~= itemID then -- first read, or switched ammo: baseline
        st.count, st.itemID, st.peak, st.step, st.alertFrom = count, itemID, count, nil, nil
        return
    end
    local prev = st.count
    st.count = count
    if count == prev then return end
    local step = math.max(1, math.floor(warn / 4))

    if count > prev then
        local wasLow = prev <= warn
        if count > st.peak or wasLow then st.peak = math.max(count, warn) end
        st.step, st.alertFrom = nil, nil
        -- A real restock (not just picking a few back up), or anything that gets you out of the red.
        if wasLow or count - prev >= math.max(5, step) then
            ammoRing.Queue({ id = kind, kind = kind, name = name, icon = icon, change = "restock",
                             from = prev, to = count, max = math.max(st.peak, count), warn = warn })
        end
        return
    end

    local bucket = (count == 0) and -1 or math.floor(count / step)
    if always then
        -- Every shot: one ring that keeps counting down while you fire.
        if count <= warn then st.step = bucket end
        ammoRing.Queue({ id = kind, kind = kind, name = name, icon = icon, change = (count == 0) and "out" or "shot",
                         from = prev, to = count, max = math.max(st.peak, 1), warn = warn })
        return
    end
    if count > warn then return end
    if bucket == st.step then return end
    st.step = bucket
    local from = st.alertFrom or prev
    st.alertFrom = count
    ammoRing.Queue({ id = kind, kind = kind, name = name, icon = icon, change = (count == 0) and "out" or "low",
                     from = from, to = count, max = math.max(st.peak, warn, 1), warn = warn })
end

local function CheckAmmo()
    local count, name, icon, itemID, hidden = ReadAmmo()
    CheckAmmoKind("ammo", count, name, icon, itemID, db.ammoWarn, hidden, db.ammoAlways)
    local _, class = UnitClass("player")
    if db.ammoShards and class == "WARLOCK" then
        local shards = ItemCount(SOUL_SHARD)
        local tex = C_Item and C_Item.GetItemIconByID and SafeCall(C_Item.GetItemIconByID, SOUL_SHARD)
        CheckAmmoKind("shards", shards, ItemName(SOUL_SHARD) or "Soul Shard", tex, SOUL_SHARD, db.ammoShardWarn)
    end
end

-- At or below the flash level (a % of the ring's full amount)?
local function Flashing(e)
    local pct = tonumber(db.ammoFlash) or 0
    if pct <= 0 or e.change == "restock" or not e.max or e.max <= 0 then return false end
    return e.to / e.max * 100 <= pct
end

local function AmmoFill(e)
    local c = db.ammoColors
    if e.change == "restock" then return c.restock end
    if e.to <= 0 then return c.out end
    if e.to <= (e.warn or db.ammoWarn) then return c.low end
    return c.normal
end

ammoRing = CreateProgressRing({
    key = "ammo",
    samples = function()
        return {
            { id = "edit-a0", kind = "ammo", name = "Sharp Arrow", change = "shot", from = 640, to = 628, max = 1000, warn = 200 },
            { id = "edit-a1", kind = "ammo", name = "Sharp Arrow", change = "low", from = 200, to = 150, max = 1000, warn = 200 },
            { id = "edit-a2", kind = "ammo", name = "Sharp Arrow", change = "out", from = 50, to = 0, max = 1000, warn = 200,
              editTime = 4 },
            { id = "edit-a3", kind = "ammo", name = "Sharp Arrow", change = "restock", from = 0, to = 1000, max = 1000, warn = 200 },
            { id = "edit-a4", kind = "shards", name = "Soul Shard", change = "low", from = 5, to = 3, max = 12, warn = 5 },
        }
    end,
    icon = function(e)
        if not db.ammoIcon then return nil end
        -- The icon of the ammo you have equipped (or your soul shards). Previews use
        -- yours too when there's any; otherwise a stand-in arrow or shard.
        local texture = e.icon
        if not texture and e.kind == "shards" then
            texture = C_Item and C_Item.GetItemIconByID and SafeCall(C_Item.GetItemIconByID, SOUL_SHARD)
        elseif not texture then
            texture = select(3, ReadAmmo())
        end
        texture = texture or (e.kind == "shards" and "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"
            or "Interface\\Icons\\INV_Ammo_Arrow_02")
        return { texture = texture, color = AmmoFill(e), celebrate = e.change == "out" }
    end,
    style = function(e, finished)
        local fill = AmmoFill(e)
        local shards = e.kind == "shards"
        local label
        if e.change == "restock" then
            label = "Restocked"
        elseif e.to <= 0 then
            label = shards and "Out of shards!" or "Out of ammo!"
        elseif e.to > (e.warn or db.ammoWarn) then
            label = "Ammo left" -- every shot, above the warning level
        else
            label = shards and "Low on shards" or "Low ammo"
        end
        return { fill = fill, rank = fill, label = label, labelColor = fill, flash = Flashing(e) }
    end,
})

local ammoQueued = false
local function QueueCheckAmmo()
    if ammoQueued then return end
    ammoQueued = true
    C_Timer.After(0.3, function()
        ammoQueued = false
        CheckAmmo()
    end)
end

local function PreviewAmmoRing()
    ammoRing.Preview({
        { id = "p-a0", kind = "ammo", name = "Sharp Arrow", change = "shot", from = 640, to = 628, max = 1000, warn = 200 },
        { id = "p-a1", kind = "ammo", name = "Sharp Arrow", change = "low", from = 200, to = 150, max = 1000, warn = 200 },
        { id = "p-a2", kind = "ammo", name = "Sharp Arrow", change = "out", from = 50, to = 0, max = 1000, warn = 200 },
        { id = "p-a3", kind = "ammo", name = "Sharp Arrow", change = "restock", from = 0, to = 1000, max = 1000, warn = 200 },
    })
end

-- Ammo used, bought or swapped, and a first read on login.
ns.Listen({ "UNIT_INVENTORY_CHANGED:player", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }, function() QueueCheckAmmo() end)

-- Shared with the files loaded after this one.
ns.PreviewAmmoRing = PreviewAmmoRing
ns.QueueCheckAmmo = QueueCheckAmmo
ns.ammoRing = ammoRing

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "ammo", name = "Ammo", order = 7,
    iconBg = true, -- the icon can be the ring's background (Core/Settings.lua, UI/OptionsKit.lua)
    ring = ammoRing,
    preview = PreviewAmmoRing, slash = { "ammo" }, help = "preview the ammo ring",
    toggle = { "Ammo ring", "Pops up when you're running low on ammo or soul shards." },
    class = { HUNTER = true, ROGUE = true, WARRIOR = true, WARLOCK = true }, -- ammo, thrown, soul shards
    defaults = {
        -- Ammo ring: arrows, bullets and thrown weapons, plus a warlock's soul shards.
        ammoEnabled     = true,
        ammoAfterCombat = false, -- running low mid-fight is exactly when it matters
        ammoShowDelta   = false,
        ammoWarn        = 200, -- show the ring at or below this much ammo
        ammoAlways      = false, -- show on every shot, counting down
        ammoFlash       = 15,  -- flash at or below this % of a full supply (0 = never)
        ammoShards      = true,
        ammoShardWarn   = 5,   -- ...and at or below this many soul shards
        ammoSize        = 110,
        ammoThickness   = 11,
        ammoOpacity     = 100,
        ammoX           = 510,
        ammoFromTop     = 55,
        ammoHold        = 3,
        ammoStyle       = "segmented",
        ammoBorder      = 2, -- black border width (0 = none)
        ammoIcon        = true, -- the ammo's (or soul shard's) icon as a badge on the ring
        ammoColors = {
            normal  = { r = 0.86, g = 0.74, b = 0.46 },
            low     = { r = 1.00, g = 0.55, b = 0.10 },
            out     = { r = 0.95, g = 0.15, b = 0.15 },
            restock = { r = 0.30, g = 0.85, b = 0.30 },
        },
    },
    page = { folder = "status", order = 5, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(7, "Ammo", "Ammo Ring",
                "Stays out of the way while you have plenty. At or below the warning level it pops up each time "
                .. "you're another quarter of the way down (not on every shot), again when you run out, and when "
                .. "you restock. Turn on Always show to watch it count down with every shot instead.",
                MergeTop(TopRow("ammo", "ammo ring", PreviewAmmoRing, "Show examples: running low, running out, "
                    .. "and restocking. Also /circ ammo."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "ammoEnabled", "Show ammo ring",
                            "Arrows, bullets and thrown weapons in your ammo or ranged slot."),
                        always = Toggle(1.5, "ammoAlways", "Always show",
                            "Show the ring every time you shoot, counting down what's left, instead of only at the "
                            .. "warnings. Nothing shows while the game keeps your ammo count hidden."),
                        warn = Range(2, "ammoWarn", "Warn at or below", 20, 1000, 10,
                            "How much ammo is left when the ring starts showing up (every quarter of this, "
                            .. "not every shot). With Always show it's where the ring turns the Low color."),
                        flash = Range(2.5, "ammoFlash", "Flash at or below (%)", 0, 50, 5,
                            "The ring flashes when what's left is at or below this share of a full supply "
                            .. "(the most you've carried since your last restock). 0 turns it off."),
                        afterCombat = Toggle(3, "ammoAfterCombat", "Wait until combat ends",
                            "Hold the warnings until the fight is over. Off by default: running low mid-fight is when it matters."),
                        delta = Toggle(4, "ammoShowDelta", "Show change as %",
                            "Add a line under the change showing it as a share of a full supply."),
                        icon = Toggle(5, "ammoIcon", "Show ammo icon",
                            "The icon of the ammo you have equipped (or your soul shards) as a round badge on the "
                            .. "ring's top edge. Border in the ring color."),
                    }),
                    shards = Box(3, "Soul shards (warlocks)", {
                        enabled = Toggle(1, "ammoShards", "Track soul shards", "Use the same ring for your soul shards."),
                        warn = Range(2, "ammoShardWarn", "Warn at or below", 1, 20, 1,
                            "How many shards are left when the ring starts showing up.",
                            { disabled = function() return not db.ammoShards end }),
                    }),
                    colors = Box(4, "Colors", {
                        normal = Color(1, "ammoColors", "normal", "Plenty", "Ring color above the warning level."),
                        low = Color(2, "ammoColors", "low", "Low", "Ring color at or below the warning level."),
                        out = Color(3, "ammoColors", "out", "Out", "Ring color when you've run out."),
                        restock = Color(4, "ammoColors", "restock", "Restocked", "Ring color when you buy or loot more."),
                    }),
                    size = SizeBox(5, "ammo", "ammo ring",
                        "Offset from the center of the screen. The default sits at the right end of the row."),
                }))
            return tab
        end },
})
