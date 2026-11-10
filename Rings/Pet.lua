-- Circlet: Pet ring: your pet's experience.
local ADDON_NAME, ns = ...

local CreateProgressRing, IsSecret, SafeCall, db = ns.CreateProgressRing, ns.IsSecret, ns.SafeCall, ns.db

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

-- Pet XP, a new pet, a pet level, and a first read on login.
ns.Listen({ "UNIT_PET_EXPERIENCE:player", "UNIT_PET:player", "PET_UI_UPDATE", "UNIT_LEVEL:pet", "PLAYER_ENTERING_WORLD" }, function() QueueCheckPet() end)

-- Shared with the files loaded after this one.
ns.PreviewPetRing = PreviewPetRing
ns.QueueCheckPet = QueueCheckPet
ns.petRing = petRing

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "pet", name = "Pet", order = 6,
    iconBg = true, -- the icon can be the ring's background (Core/Settings.lua, UI/OptionsKit.lua)
    ring = petRing,
    preview = PreviewPetRing, slash = { "pet" }, help = "preview the pet ring",
    toggle = { "Pet ring", "Fills when your pet gains experience." },
    class = { HUNTER = true }, -- only hunter pets gain XP
    defaults = {
        -- Pet ring: your pet's experience.
        petEnabled     = true,
        petAfterCombat = true,
        petShowDelta   = false,
        petSize        = 110,
        petThickness   = 11,
        petOpacity     = 100,
        petX           = 340,
        petFromTop     = 55,
        petHold        = 3,
        petStyle       = "smooth",
        petBorder      = 2, -- black border width (0 = none)
        petPortrait    = true, -- your pet's portrait as a badge on the ring
        petColors = {
            xp    = { r = 0.40, g = 0.70, b = 1.00 },
            level = { r = 1.00, g = 0.82, b = 0.00 },
        },
    },
    page = { folder = "progress", order = 6, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(6, "Pet", "Pet Ring",
                "A donut that fills when your pet gains experience, and celebrates when it levels up.",
                MergeTop(TopRow("pet", "pet ring", PreviewPetRing, "Show example pet XP: a gain and a level-up. Also /circ pet."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "petEnabled", "Show pet ring", "Pop up and fill when your pet gains experience."),
                        afterCombat = Toggle(2, "petAfterCombat", "Wait until combat ends",
                            "Add up your pet's XP from a fight and show the total once combat ends."),
                        delta = Toggle(3, "petShowDelta", "Show gain as %",
                            "Add a line under the gain showing it as a share of the pet's level, e.g. +4.2%."),
                        portrait = Toggle(4, "petPortrait", "Show pet portrait",
                            "Your pet's portrait, as on its unit frame, as a round badge on the ring's top edge. "
                            .. "Border in the ring color, gold on a level-up."),
                    }),
                    colors = Box(3, "Colors", {
                        xp = Color(1, "petColors", "xp", "Experience", "Ring and count color."),
                        level = Color(2, "petColors", "level", "Level up", "Label and icon border color on a level-up."),
                    }),
                    size = SizeBox(4, "pet", "pet ring",
                        "Offset from the center of the screen. The default sits right of the skill ring."),
                }))
            return tab
        end },
})
