-- Circlet: One-time updates to saved settings, run on login before defaults fill in.
local ADDON_NAME, ns = ...

local DEFAULTS = ns.DEFAULTS

---------------------------------------------------------------------------
-- Migrations
---------------------------------------------------------------------------
-- Each runs once per settings (its flag is saved in CircletDB) when a release changes
-- what a setting means or where a ring sits. Newest last. They run on the character's
-- profile right after it's loaded, before missing defaults are filled in, so clearing a
-- setting (= nil) gives it its current default.

local MIGRATIONS = {
    -- The level-up effect used to be an on/off checkbox; keep "off" if it was off.
    { flag = nil, run = function(db)
        if db.xpLevelFx == false and db.xpLevelFxStyle == nil then db.xpLevelFxStyle = "none" end
    end },

    -- The corpse, flight and timed quest rings used to start on top of the crafting ring;
    -- move them to their new spots unless they've been placed by hand.
    { flag = "rowLayout2", run = function(db)
        for key, old in pairs({ corpse = { 0, 200 }, flight = { 0, 200 }, timed = { 640, 190 } }) do
            if db[key .. "X"] == old[1] and db[key .. "FromTop"] == old[2] then
                db[key .. "X"], db[key .. "FromTop"] = nil, nil
            end
        end
    end },

    -- Second row, spaced like the first (170 apart, centres level): the corpse ring left of
    -- the crafting ring, then flight and timed quest to its right, lined up on the crafting
    -- ring's current spot.
    { flag = "rowLayout3", run = function(db)
        local craftX = db.craftX or DEFAULTS.craftX
        local centre = (db.craftFromTop or DEFAULTS.craftFromTop) + (db.craftSize or DEFAULTS.craftSize) / 2
        for key, offset in pairs({ corpse = -170, flight = 170, timed = 340 }) do
            db[key .. "X"] = craftX + offset
            db[key .. "FromTop"] = math.floor(centre - (db[key .. "Size"] or DEFAULTS[key .. "Size"]) / 2 + 0.5)
        end
    end },

    -- Single crafts used to be off by default; they're on now.
    { flag = "craftSingleDefaultOn", run = function(db) db.craftSingle = true end },

    -- 0.48.2: rotation briefly defaulted to 0; it's 180 now. Rings left at 0 move to it.
    { flag = "rotationDefault180", run = function(db)
        for k, v in pairs(db) do
            if type(k) == "string" and k:match("Rotation$") and v == 0 then db[k] = nil end
        end
    end },

    -- 0.53.1 / 0.54.1: settings of features taken out again (icon in front / behind, the
    -- shaman shield and weapon rings).
    { flag = nil, run = function(db)
        for k in pairs(db) do
            if type(k) == "string" and (k:match("IconLayer$") or k:match("^shaman%u")) then db[k] = nil end
        end
    end },

    -- 0.57: the skill ring split in two. Weapon skills moved to their own ring, which starts
    -- with the skill ring's look and the weapon settings you had.
    { flag = "weaponSplit", run = function(db)
        if db.skillWeapons == false or db.skillEnabled == false then db.weaponEnabled = false end
        local sc = db.skillColors
        if type(sc) == "table" and type(sc.weapon) == "table" then
            db.weaponColors = { fill = CopyTable(sc.weapon), capped = type(sc.capped) == "table" and CopyTable(sc.capped) or nil }
            sc.weapon = nil
        end
        for _, f in ipairs({ "AfterCombat", "ShowDelta", "IconAlpha", "IconStyle", "Size", "Thickness", "Opacity",
                             "Hold", "Style", "Border", "Shape", "Rotation", "Fill", "Gradient", "Combat" }) do
            if db["skill" .. f] ~= nil and db["weapon" .. f] == nil then db["weapon" .. f] = db["skill" .. f] end
        end
        db.weaponAfterCombat = true
        db.skillWeapons = nil
    end },

    -- 0.58.1: "Hide text when idle" is on by default.
    { flag = "xpHideTextDefaultOn", run = function(db) db.xpHideText = nil end },

    -- Quest rings start just left of where the quest list sits on the right edge (depends
    -- on the screen, so it isn't a fixed default).
    { flag = nil, run = function(db)
        if db.pinX == nil and UIParent and UIParent.GetWidth then
            db.pinX = math.max(0, math.floor(UIParent:GetWidth() / 2 - 330))
        end
    end },
}

-- Runs every migration this CircletDB hasn't had yet (flag-less ones every time: they
-- only act when there's something to change).
local function RunMigrations()
    local db = CircletDB
    for _, m in ipairs(MIGRATIONS) do
        if not (m.flag and db[m.flag]) then
            m.run(db)
            if m.flag then db[m.flag] = true end
        end
    end
end

-- Shared with the files loaded after this one.
ns.RunMigrations = RunMigrations
