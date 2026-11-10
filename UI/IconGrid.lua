-- Circlet: /circ icons: every game icon the rings use, found or missing.
local ADDON_NAME, ns = ...

local FACTION_ICONS, IconPath, SKILL_ICONS = ns.FACTION_ICONS, ns.IconPath, ns.SKILL_ICONS

-- /circ icons: every skill icon this addon would use, marked found or missing ------

local iconGrid
local SKILL_ICON_NAMES = {
    { 164, "Blacksmithing" }, { 165, "Leatherworking" }, { 171, "Alchemy" }, { 182, "Herbalism" },
    { 186, "Mining" }, { 197, "Tailoring" }, { 202, "Engineering" }, { 333, "Enchanting" },
    { 393, "Skinning" }, { 129, "First Aid" }, { 185, "Cooking" }, { 356, "Fishing" }, { 762, "Riding" },
    { 43, "Swords" }, { 55, "2H Swords" }, { 44, "Axes" }, { 172, "2H Axes" }, { 54, "Maces" },
    { 160, "2H Maces" }, { 173, "Daggers" }, { 136, "Staves" }, { 229, "Polearms" }, { 45, "Bows" },
    { 226, "Crossbows" }, { 46, "Guns" }, { 176, "Thrown" }, { 228, "Wands" }, { 473, "Fist Weapons" },
    { 162, "Unarmed" }, { 95, "Defense" },
}
local FACTION_ICON_NAMES = {
    { 72, "Stormwind" }, { 47, "Ironforge" }, { 69, "Darnassus" }, { 54, "Gnomeregan" },
    { 76, "Orgrimmar" }, { 81, "Thunder Bluff" }, { 68, "Undercity" }, { 530, "Darkspear" },
    { 21, "Steamwheedle" }, { 529, "Argent Dawn" }, { 59, "Thorium Bro." }, { 576, "Timbermaw" },
    { 609, "Cenarion Circle" }, { 270, "Zandalar" }, { 749, "Hydraxian" }, { 910, "Nozdormu" },
    { 87, "Bloodsail" }, { 349, "Ravenholdt" }, { 589, "Wintersaber" }, { 809, "Shen'dralar" },
    { 890, "Alliance PvP" }, { 889, "Horde PvP" },
}

local function ToggleIconGrid()
    if iconGrid and iconGrid:IsShown() then iconGrid:Hide() return end
    if not iconGrid then
        -- Skills first, then factions, in one list.
        local entries = {}
        for _, e in ipairs(SKILL_ICON_NAMES) do table.insert(entries, { SKILL_ICONS[e[1]], e[2] }) end
        for _, e in ipairs(FACTION_ICON_NAMES) do table.insert(entries, { FACTION_ICONS[e[1]], e[2] }) end
        local cols, cell = 8, 74
        local rows = math.ceil(#entries / cols)
        local ok, f = pcall(CreateFrame, "Frame", "CircletIconGrid", UIParent, "BasicFrameTemplateWithInset")
        if not ok then f = CreateFrame("Frame", "CircletIconGrid", UIParent) end
        f:SetSize(cols * cell + 24, rows * cell + 50)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        table.insert(UISpecialFrames, "CircletIconGrid")
        f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        f.bg:SetAllPoints()
        f.bg:SetColorTexture(0, 0, 0, 0.6)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("TOP", 0, -6)
        f.title:SetText("Circlet: ring icons in this client")

        local found = 0
        for i, entry in ipairs(entries) do
            local iconName, label = entry[1], entry[2]
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local x, y = 12 + col * cell + cell / 2, -32 - row * cell
            local path = IconPath(iconName)
            local tex = f:CreateTexture(nil, "ARTWORK")
            tex:SetSize(40, 40)
            tex:SetPoint("TOP", f, "TOPLEFT", x, y)
            local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("TOP", tex, "BOTTOM", 0, -2)
            text:SetWidth(cell - 4)
            if path then
                found = found + 1
                tex:SetTexture(path)
                text:SetText(label)
            else
                tex:SetColorTexture(0.25, 0.05, 0.05, 0.8)
                text:SetText("|cffff5050" .. label .. "\nmissing|r")
            end
        end
        f.title:SetText(string.format("Circlet: ring icons in this client (%d / %d found)", found, #entries))
        iconGrid = f
    end
    iconGrid:Show()
end

ns.RegisterCommand({ "icons" }, ToggleIconGrid, "list the game icons the rings use (found / missing)")

-- Shared with the files loaded after this one.
ns.ToggleIconGrid = ToggleIconGrid
