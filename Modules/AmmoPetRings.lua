-- Circlet: Ammo ring (arrows, bullets, thrown, soul shards) and pet XP ring.
local ADDON_NAME, ns = ...

local CreateProgressRing, IsSecret, db = ns.CreateProgressRing, ns.IsSecret, ns.db

---------------------------------------------------------------------------
-- Ammo ring: arrows, bullets and thrown weapons (and a warlock's soul shards)
---------------------------------------------------------------------------
-- Quiet while you have plenty. At or below the warning level it pops up each time
-- the count drops another quarter of that level, and again when you run out. Buying
-- more shows the restock. The ring fills against the most you've carried since your
-- last restock.

local SOUL_SHARD = 6265
local ammoState = { ammo = {}, shards = {} }

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

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
    if not id or IsSecret(id) then return nil end
    local count = SafeCall(GetInventoryItemCount, "player", slot)
    if type(count) ~= "number" or IsSecret(count) then return nil end
    local icon = SafeCall(GetInventoryItemTexture, "player", slot)
        or (C_Item and C_Item.GetItemIconByID and SafeCall(C_Item.GetItemIconByID, id))
    return count, ItemName(id) or "Ammo", icon, id
end

local ammoRing -- created below; CheckAmmoKind queues into it

-- kind: "ammo" or "shards". warn: the level at or below which the ring shows.
local function CheckAmmoKind(kind, count, name, icon, itemID, warn)
    local st = ammoState[kind]
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

    if count > warn then return end
    local bucket = (count == 0) and -1 or math.floor(count / step)
    if bucket == st.step then return end
    st.step = bucket
    local from = st.alertFrom or prev
    st.alertFrom = count
    ammoRing.Queue({ id = kind, kind = kind, name = name, icon = icon, change = (count == 0) and "out" or "low",
                     from = from, to = count, max = math.max(st.peak, warn, 1), warn = warn })
end

local function CheckAmmo()
    local count, name, icon, itemID = ReadAmmo()
    CheckAmmoKind("ammo", count, name, icon, itemID, db.ammoWarn)
    local _, class = UnitClass("player")
    if db.ammoShards and class == "WARLOCK" then
        local shards = ItemCount(SOUL_SHARD)
        local tex = C_Item and C_Item.GetItemIconByID and SafeCall(C_Item.GetItemIconByID, SOUL_SHARD)
        CheckAmmoKind("shards", shards, ItemName(SOUL_SHARD) or "Soul Shard", tex, SOUL_SHARD, db.ammoShardWarn)
    end
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
        else
            label = shards and "Low on shards" or "Low ammo"
        end
        return { fill = fill, rank = fill, label = label, labelColor = fill }
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
        { id = "p-a1", kind = "ammo", name = "Sharp Arrow", change = "low", from = 200, to = 150, max = 1000, warn = 200 },
        { id = "p-a2", kind = "ammo", name = "Sharp Arrow", change = "out", from = 50, to = 0, max = 1000, warn = 200 },
        { id = "p-a3", kind = "ammo", name = "Sharp Arrow", change = "restock", from = 0, to = 1000, max = 1000, warn = 200 },
    })
end

---------------------------------------------------------------------------
-- Pet ring: your pet's experience
---------------------------------------------------------------------------
-- GetPetExperience gives the pet's XP into its level. A gain fills the ring; a
-- level-up starts the new level's ring and says so. Pets without XP (or clients
-- without the API) simply never show it.

local petState = {}

local function ReadPet()
    if not (GetPetExperience and UnitExists("pet")) then return nil end
    local cur, max = SafeCall(GetPetExperience)
    if type(cur) ~= "number" or type(max) ~= "number" or IsSecret(cur) or IsSecret(max) or max <= 0 then
        return nil
    end
    local level = UnitLevel("pet")
    local name = UnitName("pet")
    local guid = UnitGUID and UnitGUID("pet") or name
    if IsSecret(level) or IsSecret(name) or IsSecret(guid) then return nil end
    return { cur = cur, max = max, level = level, name = name or "Pet", guid = guid,
             icon = GetPetIcon and SafeCall(GetPetIcon) or nil }
end

local petRing = CreateProgressRing({
    key = "pet",
    samples = function()
        return {
            { id = "edit-p1", name = "Wolf", level = 23, segment = 23, from = 4200, to = 5050, max = 9800 },
            { id = "edit-p2", name = "Wolf", level = 24, segment = 24, from = 0, to = 640, max = 10600,
              gainOffset = 380, change = "level", editTime = 4 },
        }
    end,
    icon = function(e)
        if not db.petPortrait then return nil end
        local c = e.change == "level" and db.petColors.level or db.petColors.xp
        local celebrate = e.change == "level"
        -- Your pet's portrait, like its unit frame; the family icon (or a stand-in for
        -- previews without a pet) when there's no pet to draw.
        if UnitExists("pet") then
            return { portrait = "pet", texture = e.icon, color = c, celebrate = celebrate }
        end
        local texture = e.icon or "Interface\\Icons\\Ability_Hunter_Pet_Wolf"
        return { texture = texture, color = c, celebrate = celebrate }
    end,
    style = function(e, finished)
        local c, lvl = db.petColors.xp, db.petColors.level
        if e.change == "level" and finished then
            return { fill = c, rank = c, label = "Now level " .. (e.level or "?") .. "!", labelColor = lvl }
        end
        return { fill = c, rank = c, label = "Level " .. (e.level or "?"), labelColor = { r = 0.8, g = 0.8, b = 0.8 } }
    end,
})

local function CheckPet()
    local pet = ReadPet()
    if not pet then return end
    local prev = petState
    petState = pet
    if prev.guid ~= pet.guid or not prev.level then return end -- new pet / first read: baseline

    if ns.SessionAdd then -- session summary
        if pet.level > prev.level then
            ns.SessionAdd("pet", nil, math.max(0, prev.max - prev.cur) + pet.cur)
        elseif pet.level == prev.level and pet.cur > prev.cur then
            ns.SessionAdd("pet", nil, pet.cur - prev.cur)
        end
    end
    if pet.level > prev.level then
        petRing.Queue({ id = "pet", segment = pet.level, name = pet.name, icon = pet.icon, level = pet.level,
                        change = "level", from = 0, to = pet.cur, max = pet.max,
                        gainOffset = math.max(0, prev.max - prev.cur) })
    elseif pet.level == prev.level and pet.cur > prev.cur then
        petRing.Queue({ id = "pet", segment = pet.level, name = pet.name, icon = pet.icon, level = pet.level,
                        from = prev.cur, to = pet.cur, max = pet.max })
    end
end

local petQueued = false
local function QueueCheckPet()
    if petQueued then return end
    petQueued = true
    C_Timer.After(0.2, function()
        petQueued = false
        CheckPet()
    end)
end

local function PreviewPetRing()
    petRing.Preview({
        { id = "p-p1", name = "Wolf", level = 23, segment = 23, from = 4200, to = 5050, max = 9800 },
        { id = "p-p2", name = "Wolf", level = 24, segment = 24, from = 0, to = 640, max = 10600,
          gainOffset = 380, change = "level" },
    })
end

-- Shared with the files loaded after this one.
ns.PreviewAmmoRing = PreviewAmmoRing
ns.PreviewPetRing = PreviewPetRing
ns.QueueCheckAmmo = QueueCheckAmmo
ns.QueueCheckPet = QueueCheckPet
ns.ammoRing = ammoRing
ns.petRing = petRing
