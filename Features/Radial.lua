-- Circlet: Radial menus: hold a key, point at a slice, let go to use it.
local ADDON_NAME, ns = ...

local db, Print, SafeCall, Clean = ns.db, ns.Print, ns.SafeCall, ns.Clean

---------------------------------------------------------------------------
-- Radial menus
---------------------------------------------------------------------------
-- Each menu is a ring of slices (spells, items, emotes, macros or macro text) with a
-- key of its own. Holding the key opens the ring around the cursor (or at the centre of
-- the screen); pointing at a slice lights it, and letting go of the key uses it. Letting
-- go with the cursor still in the middle does nothing.
--
-- Spells, items and macros can only be used from a protected (secure) button, so each
-- menu has one: CircletRadial<N>. Its key is an override binding that clicks it, down on
-- press and up on release. On release, a secure snippet (allowed in combat) works out
-- which slice the cursor points at from where it was on press, and copies that slice's
-- action onto the button just before the button runs it. The ring you see is an ordinary
-- frame that does the same sum to light the slice, so the two always agree.
--
-- Each slice's action is stored on the button as slice-<n>-<attribute>. (Not "spell1": the
-- button reads "spell1" as the spell for mouse button 1, which is how a key clicks it, so
-- that would always cast slice 1.)
--
-- The secure button's settings can't change in combat, so changes made during a fight
-- (and new menus) take effect when it ends.

local MAX_MENUS, MAX_SLICES = 8, 12

ns.DEFAULTS.radialMenus    = {}   -- { { name, key, slices = { { kind, value }, ... } }, ... }
ns.DEFAULTS.radialSize     = 240  -- the ring's diameter
ns.DEFAULTS.radialAtCursor = true -- open around the cursor (false: at the centre of the screen)
ns.KEEP_ON_RESET.radialMenus = true -- "Reset to defaults" leaves your menus alone

local KIND_NAMES = { spell = "Spell", item = "Item", emote = "Emote", macro = "Macro", text = "Macro text" }
local KIND_ORDER = { "spell", "item", "emote", "macro", "text" }

-- The emote list for emote slices (any other emote works as macro text: /wink).
local EMOTES = { "wave", "hello", "bye", "thank", "cheer", "applaud", "bow", "salute", "dance", "laugh",
                 "roar", "flex", "kiss", "hug", "cry", "sigh", "shrug", "nod", "no", "point", "followme",
                 "charge", "incoming", "attacktarget", "healme", "oom", "train", "chicken", "flirt", "joke",
                 "silly", "rude", "sit", "sleep", "kneel", "pray", "beg", "violin", "lol", "welcome" }
local EMOTE_NAMES = {}
for _, e in ipairs(EMOTES) do EMOTE_NAMES[e] = e:sub(1, 1):upper() .. e:sub(2) end
EMOTE_NAMES.followme, EMOTE_NAMES.attacktarget = "Follow me", "Attack target"
EMOTE_NAMES.healme, EMOTE_NAMES.oom, EMOTE_NAMES.lol = "Heal me", "Out of mana", "LOL"

local ICON_EMOTE = "Interface\\Icons\\Spell_Holy_Heal"
local ICON_TEXT = "Interface\\Icons\\INV_Misc_Note_01"
local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

local function Menus() return db.radialMenus end

---------------------------------------------------------------- what a slice is
local function ItemArg(value)
    local id = tonumber(value)
    return id and ("item:" .. id) or value
end

-- The secure button's type and its action attribute for a slice, or nil if it's empty.
local function SliceAction(s)
    local v = s and s.value
    if type(v) ~= "string" and type(v) ~= "number" then return nil end
    if v == "" then return nil end
    if s.kind == "spell" then return "spell", "spell", v end
    if s.kind == "item" then return "item", "item", ItemArg(v) end
    if s.kind == "macro" then return "macro", "macro", v end
    if s.kind == "emote" then return "macro", "macrotext", "/" .. v end
    if s.kind == "text" then return "macro", "macrotext", v end
end

-- Name and icon to show for a slice.
local function SliceLook(s)
    local v = s and s.value
    if not v or v == "" then return "(empty)", ICON_UNKNOWN end
    if s.kind == "spell" then
        local info = C_Spell and C_Spell.GetSpellInfo and SafeCall(C_Spell.GetSpellInfo, v)
        local name = type(info) == "table" and Clean(info.name) or (GetSpellInfo and SafeCall(GetSpellInfo, v))
        return name or tostring(v), ns.SpellIcon(v) or ICON_UNKNOWN
    elseif s.kind == "item" then
        local icon = C_Item and C_Item.GetItemInfoInstant and select(5, SafeCall(C_Item.GetItemInfoInstant, ItemArg(v)))
        local id = tonumber(v)
        local name = id and C_Item and C_Item.GetItemNameByID and SafeCall(C_Item.GetItemNameByID, id)
        return Clean(name) or tostring(v), Clean(icon) or ICON_UNKNOWN
    elseif s.kind == "macro" then
        local name, icon = nil, nil
        if GetMacroInfo then name, icon = SafeCall(GetMacroInfo, v) end
        return Clean(name) or tostring(v), Clean(icon) or ICON_UNKNOWN
    elseif s.kind == "emote" then
        return EMOTE_NAMES[v] or ("/" .. v), ICON_EMOTE
    end
    return (tostring(v):match("^[^\n]*")), ICON_TEXT
end

---------------------------------------------------------------- picking a slice
-- Slice i (of n) points at angle 2*pi*(i-1)/n, clockwise from 12 o'clock: slice 1 is
-- at the top. The slice picked is the one whose direction is closest to the cursor's,
-- i.e. the largest dot product, which the secure snippet can work out without trig.
local function SliceDir(i, n)
    local a = 2 * math.pi * (i - 1) / n
    return math.sin(a), math.cos(a)
end

local function DeadZone() return db.radialSize * 0.16 end

-- The slice under offset (dx, dy) from the ring's centre, or nil inside the dead zone.
local function PickSlice(dx, dy, n)
    if n < 1 or dx * dx + dy * dy < DeadZone() ^ 2 then return nil end
    local best, pick
    for i = 1, n do
        local sx, sy = SliceDir(i, n)
        local d = dx * sx + dy * sy
        if not best or d > best then best, pick = d, i end
    end
    return pick
end

-- Runs in the secure environment, before the button's own click: on press it remembers
-- where the cursor is (the ring's centre) and does nothing else; on release it picks the
-- slice and copies its action onto the button, which then uses it.
local SNIPPET = [[
    local tracker = owner:GetFrameRef("tracker")
    if down then
        local x, y = 0.5, 0.5
        if self:GetAttribute("atcursor") then x, y = tracker:GetMousePosition() end
        self:SetAttribute("cx", x)
        self:SetAttribute("cy", y)
        return false
    end
    local n = self:GetAttribute("n") or 0
    local cx, cy = self:GetAttribute("cx"), self:GetAttribute("cy")
    local x, y = tracker:GetMousePosition()
    local pick
    if cx and cy and x and y and n > 0 then
        local dx = (x - cx) * tracker:GetWidth()
        local dy = (y - cy) * tracker:GetHeight()
        local dz = self:GetAttribute("dz") or 0
        if dx * dx + dy * dy >= dz * dz then
            local best
            for i = 1, n do
                local d = dx * self:GetAttribute("slice-" .. i .. "-x") + dy * self:GetAttribute("slice-" .. i .. "-y")
                if not best or d > best then best, pick = d, i end
            end
        end
    end
    local t = pick and self:GetAttribute("slice-" .. pick .. "-type")
    self:SetAttribute("type", t)
    self:SetAttribute("typerelease", t)
    self:SetAttribute("spell", pick and self:GetAttribute("slice-" .. pick .. "-spell"))
    self:SetAttribute("item", pick and self:GetAttribute("slice-" .. pick .. "-item"))
    self:SetAttribute("macro", pick and self:GetAttribute("slice-" .. pick .. "-macro"))
    self:SetAttribute("macrotext", pick and self:GetAttribute("slice-" .. pick .. "-macrotext"))
    if not t then return false end
]]

---------------------------------------------------------------- the ring you see
local view, viewMenu, viewHover, viewX, viewY
local LINES = 96 -- enough segments for any slice count's notches

local function NewText(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    return fs
end

local function BuildView()
    view = CreateFrame("Frame", "CircletRadialView", UIParent)
    view:SetFrameStrata("FULLSCREEN_DIALOG")
    view:Hide()
    view.track = ns.NewRingLayer("BACKGROUND", 0, ns.TRACK, 0.85, view, LINES)
    view.outline = ns.NewRingLayer("BACKGROUND", -1, { r = 0, g = 0, b = 0 }, 0.9, view, LINES)
    view.hl = ns.NewRingLayer("ARTWORK", 0, { r = 1, g = 0.78, b = 0.25 }, 0.95, view, LINES)
    view.icons, view.cds = {}, {}
    for i = 1, MAX_SLICES do
        local icon = view:CreateTexture(nil, "OVERLAY")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        view.icons[i] = icon
        -- A plain Cooldown (not CooldownFrameTemplate, whose scripts restyle it): the dark
        -- sweep and the game's countdown numbers over the icon.
        local cd = CreateFrame("Cooldown", nil, view)
        cd:SetAllPoints(icon)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetDrawBling then cd:SetDrawBling(false) end
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.75) end
        cd:Hide()
        view.cds[i] = cd
    end
    view.title = NewText(view, 12)
    view.title:SetTextColor(0.75, 0.75, 0.75)
    view.name = NewText(view, 15)
    view.name:SetTextColor(1, 0.82, 0)
    view.hint = NewText(view, 11)
    view.hint:SetTextColor(0.6, 0.6, 0.6)
end

---------------------------------------------------------------- cooldowns
-- In combat this client hides cooldown numbers from addons, but a Cooldown frame still
-- takes the game's own duration object (see the target cast ring), so that's tried first;
-- plain numbers are the fallback where they're readable.
local function SpellCooldown(spell)
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local dur = SafeCall(C_Spell.GetSpellCooldownDuration, spell)
        if dur then return dur end
    end
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = SafeCall(C_Spell.GetSpellCooldown, spell)
        if type(info) == "table" then return nil, info.startTime, info.duration end
    end
    if GetSpellCooldown then return nil, SafeCall(GetSpellCooldown, spell) end
end

local function ItemCooldown(item)
    local id = tonumber(item)
        or (C_Item and C_Item.GetItemInfoInstant and SafeCall(C_Item.GetItemInfoInstant, item))
    if not id then return nil end
    local fn = (C_Item and C_Item.GetItemCooldown) or (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if fn then return nil, SafeCall(fn, id) end
end

-- A slice's cooldown: a duration object, or nil, start, duration. Emotes and macro text
-- have none; a saved macro has its spell's or item's (what its icon shows).
local function SliceCooldown(s)
    local v = s and s.value
    if not v or v == "" then return nil end
    if s.kind == "spell" then return SpellCooldown(v) end
    if s.kind == "item" then return ItemCooldown(v) end
    if s.kind == "macro" then
        local spell = GetMacroSpell and SafeCall(GetMacroSpell, v)
        if spell then return SpellCooldown(spell) end
        local _, link = nil, nil
        if GetMacroItem then _, link = SafeCall(GetMacroItem, v) end
        if link then return ItemCooldown(link) end
    end
end

local function ShowCooldown(cd, s)
    local dur, start, total = SliceCooldown(s)
    if dur and cd.SetCooldownFromDurationObject and pcall(cd.SetCooldownFromDurationObject, cd, dur) then
        cd:Show()
        return
    end
    start, total = ns.CleanNumber(start), ns.CleanNumber(total)
    if start and total and start > 0 and total > 0 then
        cd:SetCooldown(start, total)
        cd:Show()
        return
    end
    if cd.Clear then cd:Clear() end
    cd:Hide()
end

local function UpdateCooldowns()
    local slices = viewMenu and viewMenu.slices or {}
    for i, cd in ipairs(view.cds) do
        if slices[i] then ShowCooldown(cd, slices[i]) else cd:Hide() end
    end
end

local function Geom(n)
    local size = db.radialSize
    local T = math.floor(size * 0.2)
    return { R = size / 2 - T / 2, T = T, style = "segmented", notches = n, start = -0.5 / n, sweep = 1 }
end

local function DrawView(menu)
    local slices = menu.slices or {}
    local n = math.max(#slices, 1)
    local size = db.radialSize
    view:SetSize(size, size)
    local geom = Geom(n)
    local outline = {}
    for k, v in pairs(geom) do outline[k] = v end
    outline.T, outline.gapPx = geom.T + 4, math.max(0, math.max(1.5, geom.T * 0.3) - 4)
    ns.DrawArc(view.outline, 0, 1, view, outline)
    ns.DrawArc(view.track, 0, 1, view, geom)
    local iconSize = geom.T * 0.72
    for i = 1, MAX_SLICES do
        local icon = view.icons[i]
        if slices[i] then
            local sx, sy = SliceDir(i, n)
            local _, tex = SliceLook(slices[i])
            icon:SetTexture(tex)
            icon:SetSize(iconSize, iconSize)
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", view, "CENTER", sx * geom.R, sy * geom.R)
            icon:Show()
        else
            icon:Hide()
        end
    end
    view.title:ClearAllPoints()
    view.title:SetPoint("BOTTOM", view, "CENTER", 0, 10)
    view.title:SetText(menu.name or "")
    view.name:ClearAllPoints()
    view.name:SetPoint("TOP", view, "CENTER", 0, 4)
    view.name:SetWidth(geom.R * 1.4)
    view.hint:ClearAllPoints()
    view.hint:SetPoint("TOP", view.name, "BOTTOM", 0, -2)
end

local function SetHover(i)
    if i == viewHover then return end
    viewHover = i
    local menu = viewMenu
    local n = math.max(#(menu.slices or {}), 1)
    if i then
        -- DrawArc measures from the ring's start (geom.start), the first slice's left edge.
        ns.DrawArc(view.hl, (i - 1) / n, i / n, view, Geom(n))
        view.name:SetText((SliceLook(menu.slices[i])))
        view.hint:SetText("")
        for j, icon in ipairs(view.icons) do icon:SetAlpha(j == i and 1 or 0.55) end
    else
        for _, line in ipairs(view.hl) do line:Hide() end
        view.name:SetText("")
        view.hint:SetText(#(menu.slices or {}) > 0 and "Point at a slice, then let go" or "No slices yet")
        for _, icon in ipairs(view.icons) do icon:SetAlpha(1) end
    end
end

local function CursorXY()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

-- The slice the cursor is on now (nil in the middle).
local function HoveredSlice()
    if not viewMenu then return nil end
    local x, y = CursorXY()
    return PickSlice(x - viewX, y - viewY, #(viewMenu.slices or {}))
end

local function OpenView(index)
    local menu = Menus()[index]
    if not menu then return end
    if not view then BuildView() end
    viewMenu, viewHover = menu, false
    if db.radialAtCursor then
        viewX, viewY = CursorXY()
    else
        viewX, viewY = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    end
    view:ClearAllPoints()
    view:SetPoint("CENTER", UIParent, "BOTTOMLEFT", viewX, viewY)
    DrawView(menu)
    SetHover(nil)
    UpdateCooldowns()
    local since = 0
    view:SetScript("OnUpdate", function(_, elapsed)
        SetHover(HoveredSlice())
        since = since + (elapsed or 0)
        if since >= 0.2 then since = 0; UpdateCooldowns() end -- one starts while the ring is open
    end)
    view:Show()
end

local function CloseView()
    if view then
        view:SetScript("OnUpdate", nil)
        view:Hide()
    end
    viewMenu = nil
end

---------------------------------------------------------------- secure buttons and keys
local header, tracker, bindOwner
local buttons = {}
local pending = false -- a change waiting for combat to end

local function SetupSecure()
    if header then return true end
    tracker = CreateFrame("Frame", "CircletRadialTracker", UIParent, "SecureFrameTemplate")
    tracker:SetAllPoints(UIParent)
    tracker:EnableMouse(false)
    tracker:Show()
    header = CreateFrame("Frame", "CircletRadialHeader", UIParent, "SecureHandlerBaseTemplate")
    header:SetFrameRef("tracker", tracker)
    bindOwner = CreateFrame("Frame", "CircletRadialBindings", UIParent)
    return true
end

local function Button(i)
    if buttons[i] then return buttons[i] end
    local b = CreateFrame("Button", "CircletRadial" .. i, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("pressAndHoldAction", true) -- release runs "typerelease"
    b.menuIndex = i
    -- The ring you see (not secure: it works the same in combat).
    b:SetScript("PreClick", function(self, _, down)
        if down then
            OpenView(self.menuIndex)
        else
            CloseView()
        end
    end)
    header:WrapScript(b, "OnClick", SNIPPET)
    buttons[i] = b
    return b
end

local ATTRS = { "spell", "item", "macro", "macrotext" }

-- Copies every menu's slices onto its button and binds its key. Out of combat only.
local function Apply()
    if InCombatLockdown and InCombatLockdown() then
        pending = true
        return false
    end
    pending = false
    if not SetupSecure() then return false end
    if ClearOverrideBindings then ClearOverrideBindings(bindOwner) end
    for i, menu in ipairs(Menus()) do
        local b = Button(i)
        local slices = menu.slices or {}
        local n = math.min(#slices, MAX_SLICES)
        b:SetAttribute("n", n)
        b:SetAttribute("dz", DeadZone())
        b:SetAttribute("atcursor", db.radialAtCursor and true or nil)
        for j = 1, MAX_SLICES do
            local sx, sy
            if j <= n then sx, sy = SliceDir(j, n) end
            b:SetAttribute("slice-" .. j .. "-x", sx)
            b:SetAttribute("slice-" .. j .. "-y", sy)
            local t, attr, value = SliceAction(j <= n and slices[j] or nil)
            b:SetAttribute("slice-" .. j .. "-type", t)
            for _, a in ipairs(ATTRS) do b:SetAttribute("slice-" .. j .. "-" .. a, a == attr and value or nil) end
        end
        if menu.key and menu.key ~= "" and SetOverrideBindingClick then
            SetOverrideBindingClick(bindOwner, true, menu.key, b:GetName(), "LeftButton")
        end
    end
    -- Buttons for deleted menus: nothing to do (no slices, no key).
    for i = #Menus() + 1, #buttons do buttons[i]:SetAttribute("n", 0) end
    return true
end

local function Changed()
    if not Apply() then Print("Radial menu changes take effect when combat ends.") end
    if ns.RefreshRadialOptions then ns.RefreshRadialOptions() end
end

ns.Listen({ "PLAYER_REGEN_ENABLED" }, function()
    if pending then Apply() end
end)
-- Combat starts with a menu open (the key held): close it cleanly when released anyway.
ns.OnLoaded(function() Apply() end)

---------------------------------------------------------------- editing menus
local function CleanName(s)
    s = type(s) == "string" and s:gsub("^%s+", ""):gsub("%s+$", "") or ""
    return s ~= "" and s or nil
end

local function NewMenu(name)
    local menus = Menus()
    if #menus >= MAX_MENUS then Print("You can have up to " .. MAX_MENUS .. " radial menus.") return end
    table.insert(menus, { name = CleanName(name) or ("Menu " .. (#menus + 1)), key = nil, slices = {} })
    Changed()
    return #menus
end

local function DeleteMenu(i)
    table.remove(Menus(), i)
    Changed()
end

local function KeyUsedBy(key, except)
    for i, menu in ipairs(Menus()) do
        if i ~= except and menu.key == key then return menu end
    end
end

local function SetKey(i, key)
    local menu = Menus()[i]
    key = CleanName(key)
    local other = key and KeyUsedBy(key, i)
    if other then other.key = nil; Print(key .. " moved from " .. other.name .. " to " .. menu.name .. ".") end
    menu.key = key
    Changed()
end

local function AddSlice(i)
    local slices = Menus()[i].slices
    if #slices >= MAX_SLICES then Print("A radial menu can have up to " .. MAX_SLICES .. " slices.") return end
    table.insert(slices, { kind = "spell", value = "" })
    Changed()
end

local function MoveSlice(i, j, by)
    local slices = Menus()[i].slices
    local k = j + by
    if k < 1 or k > #slices then return end
    slices[j], slices[k] = slices[k], slices[j]
    Changed()
end

local function RemoveSlice(i, j)
    table.remove(Menus()[i].slices, j)
    Changed()
end

---------------------------------------------------------------- options
local optionsGroup

local function MacroValues()
    local values, order = {}, {}
    if not (GetNumMacros and GetMacroInfo) then return values, order end
    local global, char = GetNumMacros()
    local function Add(index)
        local name = GetMacroInfo(index)
        if name and not values[name] then values[name] = name; table.insert(order, name) end
    end
    for i = 1, global or 0 do Add(i) end
    for i = 1, char or 0 do Add((MAX_ACCOUNT_MACROS or 120) + i) end
    return values, order
end

local function SliceRow(O, i, j, base)
    local function S() return Menus()[i] and Menus()[i].slices[j] end
    local function Is(kind) return function() local s = S(); return not (s and s.kind == kind) end end
    local args = {}
    args["kind" .. j] = {
        type = "select", order = base, width = 0.75, name = "Slice " .. j,
        desc = "What this slice does. Spell, Item: type its name (or ID). Emote: pick one. Macro: one of "
            .. "your macros. Macro text: any macro lines, like /wink or /cast Hearthstone.",
        values = KIND_NAMES, sorting = KIND_ORDER,
        get = function() return S() and S().kind end,
        set = function(_, v) local s = S(); s.kind = v; s.value = v == "emote" and "wave" or ""; Changed() end,
    }
    local function Get() local s = S(); return s and s.value and tostring(s.value) or "" end
    local function Set(_, v) S().value = v; Changed() end
    args["value" .. j] = {
        type = "input", order = base + 0.1, width = 1.4, name = function()
            local s = S()
            if not s then return "" end
            local label, icon = SliceLook(s)
            return "|T" .. icon .. ":16|t " .. label
        end,
        desc = "Spell: its name, like Frostbolt (the highest rank you know), or Frostbolt(Rank 1). "
            .. "Item: its name or item ID.",
        get = Get, set = Set, hidden = function() local s = S(); return s and (s.kind == "emote" or s.kind == "macro" or s.kind == "text") end,
    }
    args["emote" .. j] = {
        type = "select", order = base + 0.11, width = 1.4, name = "Emote",
        values = EMOTE_NAMES, sorting = EMOTES, get = Get, set = Set, hidden = Is("emote"),
    }
    args["macro" .. j] = {
        type = "select", order = base + 0.12, width = 1.4, name = "Macro",
        desc = "One of your macros (Esc > Macros). It uses the macro as it is when you let go.",
        values = function() return (MacroValues()) end,
        sorting = function() return select(2, MacroValues()) end,
        get = Get, set = Set, hidden = Is("macro"),
    }
    args["text" .. j] = {
        type = "input", order = base + 0.13, width = 1.4, multiline = 2, name = "Macro text",
        desc = "Any macro lines, as in a macro: /wink, /cast Hearthstone, /use 13. Up to 255 characters.",
        get = Get, set = Set, hidden = Is("text"),
    }
    args["up" .. j] = {
        type = "execute", order = base + 0.2, width = 0.3, name = "Up",
        desc = "Move this slice one place earlier (anticlockwise).",
        func = function() MoveSlice(i, j, -1) end, disabled = function() return j == 1 end,
    }
    args["down" .. j] = {
        type = "execute", order = base + 0.3, width = 0.35, name = "Down",
        desc = "Move this slice one place later (clockwise).",
        func = function() MoveSlice(i, j, 1) end,
        disabled = function() return j == #(Menus()[i] and Menus()[i].slices or {}) end,
    }
    args["remove" .. j] = {
        type = "execute", order = base + 0.4, width = 0.45, name = "Remove",
        func = function() RemoveSlice(i, j) end,
    }
    return args
end

local function MenuPage(O, i)
    local menu = Menus()[i]
    local slices = {}
    for j = 1, #menu.slices do
        for k, v in pairs(SliceRow(O, i, j, j)) do slices[k] = v end
    end
    slices.add = {
        type = "execute", order = 99, width = 1.1, name = "Add a slice",
        desc = "Add a slice to the end of the ring (up to " .. MAX_SLICES .. "). Slice 1 sits at the top, "
            .. "and the rest follow clockwise.",
        func = function() AddSlice(i) end,
        disabled = function() return #(Menus()[i] and Menus()[i].slices or {}) >= MAX_SLICES end,
    }
    return {
        type = "group", order = i, name = function() return Menus()[i] and Menus()[i].name or "" end,
        args = {
            header = { type = "header", order = 0, name = function() return Menus()[i] and Menus()[i].name or "" end },
            intro = O.Intro(0.5, "Hold the key to open this ring, point at a slice, and let go to use it. "
                .. "Letting go with the cursor still in the middle closes it without doing anything."),
            menu = O.Box(1, "Menu", {
                name = {
                    type = "input", order = 1, width = 1.4, name = "Name",
                    desc = "Shown in the middle of the ring and in this list.",
                    get = function() return Menus()[i].name end,
                    set = function(_, v) Menus()[i].name = CleanName(v) or Menus()[i].name; Changed() end,
                },
                key = {
                    type = "keybinding", order = 2, width = 1.4, name = "Key",
                    desc = "Hold this key to open the ring. It takes over whatever the key normally does "
                        .. "(only while Circlet is loaded). Right-click the box to clear it.",
                    get = function() return Menus()[i].key end,
                    set = function(_, v) SetKey(i, v) end,
                },
                delete = {
                    type = "execute", order = 3, width = 1.1, name = "Delete this menu",
                    confirm = true, confirmText = "Delete the radial menu " .. (menu.name or "") .. "?",
                    func = function() DeleteMenu(i) end,
                },
            }),
            slices = O.Box(2, "Slices", slices),
        },
    }
end

local function TopArgs(O)
    local args = {
        header = { type = "header", order = 0, name = "Radial menus" },
        intro = O.Intro(0.5, "A radial menu is a ring of spells, items, emotes and macros on a key of your own. "
            .. "Hold the key and the ring opens around your cursor; point at a slice and let go of the key to "
            .. "use it. It works in combat too. Each menu has its own page below, where you set its key and "
            .. "slices; changes made during a fight take effect when it ends."),
        manage = O.Box(1, "Menus", {
            new = {
                type = "input", order = 1, width = 1.4, name = "New menu",
                desc = "Type a name and press Enter to make a new radial menu (up to " .. MAX_MENUS .. ").",
                get = function() return "" end,
                set = function(_, v)
                    local i = NewMenu(v)
                    if i and ns.SelectOptionsPage then ns.SelectOptionsPage("radial", "menu" .. i) end
                end,
                disabled = function() return #Menus() >= MAX_MENUS end,
            },
        }),
        look = O.Box(2, "Look", {
            size = O.Range(1, "radialSize", "Ring size", 160, 400, 10, "Diameter of the radial menus.",
                { set = function(_, v) db.radialSize = v; Changed() end }),
            atCursor = O.Toggle(2, "radialAtCursor", "Open at the cursor",
                "Open the ring centred on the cursor. Off: in the middle of the screen.", function() Changed() end),
        }),
    }
    for i = 1, #Menus() do args["menu" .. i] = MenuPage(O, i) end
    return args
end

local function RadialOptions(O)
    optionsGroup = { type = "group", order = 5, name = "Radial menus", childGroups = "tree", args = TopArgs(O) }
    ns.RefreshRadialOptions = function()
        if not optionsGroup then return end
        local args = TopArgs(O)
        wipe(optionsGroup.args)
        for k, v in pairs(args) do optionsGroup.args[k] = v end
        if ns.RefreshOptions then ns.RefreshOptions() end
    end
    return optionsGroup
end

---------------------------------------------------------------- slash command
ns.RegisterCommand({ "radial", "menus" }, function()
    if ns.OpenOptions then ns.OpenOptions("radial") end
end, "set up radial menus (hold a key, point, let go)")

-- For the tests: where the highlight is lit, in slice widths from slice 1's left edge
-- ("1.02-1.98" is all of slice 2), or "none".
local function LitArc()
    if not (view and viewMenu) then return "none" end
    local n = math.max(#(viewMenu.slices or {}), 1)
    local lo, hi
    for _, line in ipairs(view.hl) do
        if line:IsShown() and line.arcMid then
            local v = line.arcMid * n
            lo, hi = math.min(lo or v, v), math.max(hi or v, v)
        end
    end
    return lo and string.format("%.2f-%.2f", lo, hi) or "none"
end

-- Shared with the files loaded after this one.
ns.RadialOptions = RadialOptions
ns.ApplyRadial = Apply
ns.Radial = { -- for the tests
    PickSlice = PickSlice, SliceDir = SliceDir, SliceAction = SliceAction, SliceLook = SliceLook,
    NewMenu = NewMenu, DeleteMenu = DeleteMenu, SetKey = SetKey, AddSlice = AddSlice,
    MoveSlice = MoveSlice, RemoveSlice = RemoveSlice, SNIPPET = SNIPPET, Buttons = buttons,
    HoveredSlice = HoveredSlice, OpenView = OpenView, CloseView = CloseView, LitArc = LitArc,
    Cooldowns = function() return view and view.cds end,
}
