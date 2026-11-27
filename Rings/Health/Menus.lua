-- Circlet: Health rings: the right-click unit menu on each ring (secure buttons that follow the rings).
local _, ns = ...

local db = ns.db
local H = ns.HealthRings
local playerRing = H.playerRing
local targetRing = H.targetRing
local totRing = H.totRing
local petRing = H.petRing

---------------------------------------------------------------- right-click menus
-- The game's own unit menu on right-click, the way unit frames do it: a secure unit button
-- (right-click = togglemenu) over each ring, so the game opens the menu itself and its
-- protected entries (Set Focus...) keep working, with nothing tainted. Secure buttons can't be
-- moved, shown or hidden by addon code in combat, so they aren't the rings' children (a ring can
-- fade and slide freely): out of combat each button follows its ring where it actually is (auto-
-- arrange included) and shows exactly while the ring does; in combat the game shows and hides it
-- itself (a state driver: while the unit exists), where it was when combat started. Left clicks
-- pass through to the world, except on your own ring with <key>ClickTarget on, where a left
-- click targets you (type1 = target, as on the player frame); in edit mode the buttons step
-- aside so the rings can be dragged.
local MENU_RINGS = {
    { key = "playerHp", unit = "player", ring = playerRing, name = "CircletPlayerHpMenu" },
    { key = "targetHp", unit = "target", ring = targetRing, name = "CircletTargetHpMenu" },
    { key = "totHp", unit = "targettarget", ring = totRing, name = "CircletTotHpMenu" },
    { key = "petHp", unit = "pet", ring = petRing, name = "CircletPetHpMenu" },
}
local menuDebug = {}

local function MenuButton(m)
    if m.button then return m.button end
    local ok, b = pcall(CreateFrame, "Button", m.name, UIParent, "SecureUnitButtonTemplate")
    if not ok or not b then menuDebug[m.key] = "couldn't make the button: " .. tostring(b) return nil end
    b:SetAttribute("unit", m.unit)
    b:RegisterForClicks("AnyUp")
    b:SetFrameStrata(ns.RING_STRATA)
    b:SetFrameLevel(50)
    b:EnableMouse(true)
    b:Hide()
    m.button = b
    return b
end

local function Wants(m)
    return db[m.key .. "Enabled"] and (db[m.key .. "Menu"] or db[m.key .. "ClickTarget"]) and not m.ring.IsEditing()
end

-- What its clicks do (out of combat only): right = the menu, left = target the unit; a click
-- that does neither passes through to the world.
local function SetClicks(m, b)
    local menu = db[m.key .. "Menu"] and true or false
    local click = db[m.key .. "ClickTarget"] and true or false
    local k = tostring(menu) .. tostring(click)
    if m.clicks == k then return end
    m.clicks = k
    local menuType = menu and "togglemenu" or nil
    local targetType = click and "target" or nil
    b:SetAttribute("*type2", menuType); b:SetAttribute("type2", menuType)
    b:SetAttribute("*type1", targetType); b:SetAttribute("type1", targetType)
    if b.SetPassThroughButtons then
        if menu and click then pcall(b.SetPassThroughButtons, b)
        elseif click then pcall(b.SetPassThroughButtons, b, "RightButton")
        else pcall(b.SetPassThroughButtons, b, "LeftButton") end
    end
end

-- Where the ring is: its real center if it has one, else its saved spot.
local function RingSpot(m)
    local f = m.ring.frame
    local size = f:GetWidth()
    if not size or size <= 0 then size = tonumber(db[m.key .. "Size"]) or 110 end
    local x, y = f:GetCenter()
    if x and y then
        local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        return "BOTTOMLEFT", x * k, y * k, size * k
    end
    return "TOP", tonumber(db[m.key .. "X"]) or 0, -((tonumber(db[m.key .. "FromTop"]) or 0) + size / 2), size
end

local function PlaceMenu(m, b)
    local rel, x, y, size = RingSpot(m)
    local k = string.format("%s:%.1f:%.1f:%.1f", rel, x, y, size)
    if m.spot == k then return end
    m.spot = k
    b:ClearAllPoints()
    b:SetPoint("CENTER", UIParent, rel, x, y)
    b:SetSize(size, size)
end

-- Out of combat: follow the ring, shown while it is.
local function SyncMenus()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, m in ipairs(MENU_RINGS) do
        local want = Wants(m)
        local b = (want or m.button) and MenuButton(m)
        if b then
            if m.driver then pcall(UnregisterStateDriver, b, "visibility"); m.driver = nil end
            local f = m.ring.frame
            local up = want and f:IsVisible() and f:GetAlpha() > 0.05
            if up then
                SetClicks(m, b)
                PlaceMenu(m, b)
                if not b:IsShown() then b:Show() end
            elseif b:IsShown() then
                b:Hide()
            end
        end
    end
end

-- Combat starting (still allowed to set things up): the game takes over showing them.
local function HandOver()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, m in ipairs(MENU_RINGS) do
        local b = m.button
        if b and Wants(m) then
            SetClicks(m, b)
            PlaceMenu(m, b)
            if RegisterStateDriver then
                pcall(RegisterStateDriver, b, "visibility", "[@" .. m.unit .. ",exists] show; hide")
                m.driver = true
            end
        end
    end
end
ns.Listen({ "PLAYER_REGEN_DISABLED" }, HandOver)
ns.Listen({ "PLAYER_REGEN_ENABLED" }, SyncMenus)

local menuWatch = CreateFrame("Frame")
menuWatch.t = 0
menuWatch:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.t < 0.1 or not CircletDB then return end
    self.t = 0
    SyncMenus()
end)

-- /circ menudebug: where the menu buttons are and what they'd do.
ns.RegisterCommand({ "menudebug" }, function()
    for _, m in ipairs(MENU_RINGS) do
        local b = m.button
        if not b then
            ns.Print(m.key .. ": no button (" .. (menuDebug[m.key] or (Wants(m) and "not made yet" or "off")) .. ")")
        else
            local x, y = b:GetCenter()
            local rx, ry = m.ring.frame:GetCenter()
            ns.Print(string.format("%s: shown %s, mouse %s, over %s, at %s,%s (ring at %s,%s), size %d, unit %s, type2 %s, type1 %s, protected %s",
                m.key, tostring(b:IsVisible()), tostring(b:IsMouseEnabled()), tostring(b:IsMouseOver()),
                x and math.floor(x) or "?", y and math.floor(y) or "?", rx and math.floor(rx) or "?", ry and math.floor(ry) or "?",
                b:GetWidth() or 0, tostring(b:GetAttribute("unit")), tostring(b:GetAttribute("*type2")), tostring(b:GetAttribute("*type1")),
                tostring(b:IsProtected())))
        end
    end
    local focus = GetMouseFoci and GetMouseFoci() or (GetMouseFocus and { GetMouseFocus() }) or {}
    local names = {}
    for _, f in ipairs(focus) do names[#names + 1] = tostring(f.GetName and f:GetName() or f) end
    ns.Print("Under the mouse: " .. (#names > 0 and table.concat(names, ", ") or "nothing"))
end)
