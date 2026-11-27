-- Circlet: The options window itself: building it, opening it, and the game's AddOns list and compartment.
local ADDON_NAME, ns = ...

local db, Print = ns.db, ns.Print
local UI = ns.OptionsUI
local APP = UI.APP
local BuildOptionsTable = UI.BuildOptionsTable
local W = UI.W
local A = UI.A
local GOLD = UI.GOLD
local WIN_W = UI.WIN_W
local WIN_H = UI.WIN_H
local SIDE_W = UI.SIDE_W
local FOOT_H = UI.FOOT_H
local PAD = UI.PAD
local CONTENT_W = UI.CONTENT_W
local NAV = UI.NAV
local SideRow = UI.SideRow
local RefreshSidebar = UI.RefreshSidebar
local FollowPage = UI.FollowPage

---------------------------------------------------------------- building the window
local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = get and get(ADDON_NAME, "Version") or nil
    -- A copy straight from the repository, not a packaged release.
    if version and version:find("@project%-version@") then version = "dev" end
    return version
end

local function CloseX(parent)
    local b = W.Button(parent, 30, 30, "", function() UI.win:Hide() end)
    for _, sign in ipairs({ 1, -1 }) do
        local l = b:CreateLine(nil, "OVERLAY")
        l:SetThickness(1.5)
        l:SetColorTexture(0.8, 0.8, 0.82, 1)
        l:SetStartPoint("CENTER", b, -6, 6 * sign)
        l:SetEndPoint("CENTER", b, 6, -6 * sign)
    end
    b.tipTitle = "Close"
    return b
end

local function BuildWindow()
    UI.win = CreateFrame("Frame", "CircletConfigFrame", UIParent)
    UI.win:Hide()
    UI.win:SetSize(WIN_W, WIN_H)
    UI.win:SetPoint("CENTER")
    UI.win:SetFrameStrata("HIGH")
    if UI.win.SetToplevel then UI.win:SetToplevel(true) end
    UI.win:SetClampedToScreen(true)
    UI.win:EnableMouse(true)
    UI.win:SetMovable(true)
    UI.win:RegisterForDrag("LeftButton")
    UI.win:SetScript("OnDragStart", UI.win.StartMoving)
    UI.win:SetScript("OnDragStop", UI.win.StopMovingOrSizing)
    table.insert(UISpecialFrames, "CircletConfigFrame") -- Esc closes it

    -- Background: dark slate, the sidebar darker, a faint blue glow behind the title.
    for i, a in ipairs({ 0.35, 0.22, 0.12, 0.05 }) do ns.SkinEdges(UI.win, "BACKGROUND", -8, 2, i * 2, 0, 0, 0, a) end
    UI.win.bg = W.Solid(UI.win, "BACKGROUND", W.BG[1], W.BG[2], W.BG[3], W.BG[4], -7)
    UI.win.bg:SetAllPoints()
    UI.win.glow = UI.win:CreateTexture(nil, "BACKGROUND", nil, -6)
    UI.win.glow:SetPoint("TOPLEFT", UI.win, "TOPLEFT", SIDE_W, 0)
    UI.win.glow:SetPoint("TOPRIGHT", UI.win, "TOPRIGHT", 0, 0)
    UI.win.glow:SetHeight(170)
    ns.SkinGradient(UI.win.glow, "VERTICAL", A.r, A.g, A.b, 0, A.r, A.g, A.b, 0.07)
    UI.win.side = W.Solid(UI.win, "BACKGROUND", 0.04, 0.03, 0.038, 1, -5)
    UI.win.side:SetPoint("TOPLEFT"); UI.win.side:SetPoint("BOTTOMLEFT")
    UI.win.side:SetWidth(SIDE_W)
    UI.win.sideEdge = W.Solid(UI.win, "BORDER", 1, 1, 1, 0.07)
    UI.win.sideEdge:SetPoint("TOPLEFT", UI.win, "TOPLEFT", SIDE_W, 0)
    UI.win.sideEdge:SetPoint("BOTTOMLEFT", UI.win, "BOTTOMLEFT", SIDE_W, 0)
    UI.win.sideEdge:SetWidth(1)
    UI.win.border = W.Border(UI.win, GOLD.r, GOLD.g, GOLD.b, 0.55)
    UI.win.footRule = W.Solid(UI.win, "BORDER", 1, 1, 1, 0.08)
    UI.win.footRule:SetPoint("BOTTOMLEFT", UI.win, "BOTTOMLEFT", SIDE_W + 1, FOOT_H)
    UI.win.footRule:SetPoint("BOTTOMRIGHT", UI.win, "BOTTOMRIGHT", -1, FOOT_H)
    UI.win.footRule:SetHeight(1)
    UI.win.footBg = W.Solid(UI.win, "BACKGROUND", 0, 0, 0, 0.25, -4)
    UI.win.footBg:SetPoint("BOTTOMLEFT", UI.win, "BOTTOMLEFT", SIDE_W + 1, 1)
    UI.win.footBg:SetPoint("BOTTOMRIGHT", UI.win, "BOTTOMRIGHT", -1, 1)
    UI.win.footBg:SetHeight(FOOT_H - 1)

    -- Sidebar: the logo and name.
    UI.win.logo = ns.SkinLogo(UI.win, 46)
    UI.win.logo:SetPoint("TOPLEFT", UI.win, "TOPLEFT", 20, -18)
    UI.win.name = W.Text(UI.win, 24, GOLD.r, GOLD.g, GOLD.b, "OVERLAY", W.TITLE_FONT)
    UI.win.name:SetPoint("TOPLEFT", UI.win.logo, "TOPRIGHT", 12, -4)
    UI.win.name:SetText("Circlet")
    UI.win.sub = W.Text(UI.win, 11, 0.55, 0.57, 0.62)
    UI.win.sub:SetPoint("TOPLEFT", UI.win.name, "BOTTOMLEFT", 1, -3)
    UI.win.sub:SetText("Progress rings")
    UI.win.logoRule = ns.SkinRule(UI.win, SIDE_W - 36, GOLD.r, GOLD.g, GOLD.b, 0.5)
    UI.win.logoRule:SetPoint("TOPLEFT", UI.win, "TOPLEFT", 18, -80)

    -- Sidebar: the pages and actions at the top.
    UI.win.nav = {}
    local y = -92
    for _, item in ipairs(NAV) do
        local b = SideRow(UI.win, 34)
        b.item = item
        b.tip = item.tip
        b:SetPoint("TOPLEFT", UI.win, "TOPLEFT", 1, y)
        b:SetPoint("TOPRIGHT", UI.win, "TOPLEFT", SIDE_W, y)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(18, 18)
        b.icon:SetPoint("LEFT", b, "LEFT", 22, 0)
        b.icon:SetTexture(item.icon)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if b.icon.SetDesaturated then b.icon:SetDesaturated(true) end
        b.icon:SetAlpha(0.85)
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 14, 0)
        b.text:SetFont(W.TITLE_FONT, 13, "")
        b:SetScript("OnClick", function()
            if item.path then UI.SelectPage(item.path) else item.func(); UI.Refresh() end
        end)
        UI.win.nav[#UI.win.nav + 1] = b
        y = y - 34
    end

    -- Sidebar: search.
    UI.win.search = W.EditBox(UI.win, SIDE_W - 36, "LEFT", function() end)
    UI.win.search:SetPoint("TOPLEFT", UI.win, "TOPLEFT", 18, y - 12)
    UI.win.search.hint = W.Text(UI.win.search, 12, 0.45, 0.47, 0.52)
    UI.win.search.hint:SetPoint("LEFT", 9, 0)
    UI.win.search.hint:SetText("Search rings...")
    UI.win.search:SetScript("OnTextChanged", function(self)
        UI.search = self:GetText() or ""
        self.hint:SetShown(UI.search == "")
        RefreshSidebar()
    end)
    UI.win.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    -- Sidebar: the rings, under their folders.
    UI.win.ringList = W.ScrollArea(UI.win)
    UI.win.ringList:SetPoint("TOPLEFT", UI.win, "TOPLEFT", 1, y - 46)
    UI.win.ringList:SetPoint("BOTTOMRIGHT", UI.win, "BOTTOMLEFT", SIDE_W - 1, 46)
    UI.win.version = W.Text(UI.win, 11, 0.45, 0.47, 0.52)
    UI.win.version:SetPoint("BOTTOMLEFT", UI.win, "BOTTOMLEFT", 20, 16)
    local version = Version()
    UI.win.version:SetText((version and ("v" .. version .. "   ·   ") or "") .. "/circ help for commands")

    -- Header: the page's title and description, and window scale / close at the top right.
    UI.win.title = W.Text(UI.win, 26, 1, 1, 1, "OVERLAY", W.TITLE_FONT)
    UI.win.title:SetPoint("TOPLEFT", UI.win, "TOPLEFT", SIDE_W + PAD, -24)
    UI.win.title:SetWidth(CONTENT_W - PAD * 2 - 330)
    UI.win.title:SetWordWrap(false)
    UI.win.intro = W.Text(UI.win, 13, 0.68, 0.7, 0.75)
    UI.win.intro:SetPoint("TOPLEFT", UI.win.title, "BOTTOMLEFT", 1, -10)
    UI.win.intro:SetWidth(CONTENT_W - PAD * 2)
    if UI.win.intro.SetSpacing then UI.win.intro:SetSpacing(2) end

    UI.win.close = CloseX(UI.win)
    UI.win.close:SetPoint("TOPRIGHT", UI.win, "TOPRIGHT", -14, -14)
    UI.win.scaleValue = W.Text(UI.win, 12, 0.9, 0.9, 0.92)
    UI.win.scaleValue:SetPoint("RIGHT", UI.win.close, "LEFT", -14, 0)
    UI.win.scaleValue:SetWidth(40)
    UI.win.scaleValue:SetJustifyH("RIGHT")
    UI.win.scale = W.Slider(UI.win, 110, function(v) UI.win.scaleValue:SetText(v .. "%") end, function(v)
        db.optionsScale = v
        UI.win:SetScale(v / 100)
    end)
    UI.win.scale:SetRange(70, 130, 5)
    UI.win.scale:SetPoint("RIGHT", UI.win.scaleValue, "LEFT", -12, 0)
    UI.win.scaleLabel = W.Text(UI.win, 12, 0.7, 0.72, 0.76)
    UI.win.scaleLabel:SetPoint("RIGHT", UI.win.scale, "LEFT", -12, 0)
    UI.win.scaleLabel:SetText("Window scale")

    -- Tabs, the settings, and the footer's Close.
    UI.win.tabRule = W.Solid(UI.win, "BORDER", 1, 1, 1, 0.09)
    UI.win.tabRule:SetHeight(1)
    UI.win.body = W.ScrollArea(UI.win)
    UI.win.closeButton = W.Button(UI.win, 150, 32, "Close", function() UI.win:Hide() end)
    UI.win.closeButton:SetPoint("BOTTOMRIGHT", UI.win, "BOTTOMRIGHT", -PAD, 13)
    UI.win.closeButton:SetAccent()

    UI.win:SetScript("OnShow", function(self)
        local scale = tonumber(db.optionsScale) or 100
        self:SetScale(scale / 100)
        self.scale:SetValue(scale)
        self.scaleValue:SetText(scale .. "%")
        UI.lastSig = nil
        UI.SelectPage(UI.current)
    end)
    UI.win:SetScript("OnHide", function()
        W.CloseList()
        W.HideTip()
        FollowPage(nil)
    end)
end

local function SetupOptions()
    if not ns.W then error("UI/Widgets.lua didn't load") end
    UI.root = BuildOptionsTable()
    ns.OptionsTable = UI.root
    -- Still registered, for anything that reads Circlet's options the AceConfig way.
    local registry = LibStub and LibStub("AceConfigRegistry-3.0", true)
    if registry then registry:RegisterOptionsTable(APP, UI.root) end
    BuildWindow()
    ns.RefreshOptions = function() UI.Refresh() end

    -- Esc > Options > AddOns > Circlet: a short page that opens the window.
    if Settings and Settings.RegisterVerticalLayoutCategory then
        local category, layout = Settings.RegisterVerticalLayoutCategory("Circlet")
        layout:AddInitializer(CreateSettingsButtonInitializer("Circlet options", "Open options", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            if not UI.win:IsShown() then UI.win:Show() end
        end, "Open the Circlet options window. Also /circ.", true))
        Settings.RegisterAddOnCategory(category)
    end
end

-- Builds the window; if it fails on this client, the rest of the addon still works.
local function TrySetupOptions()
    local ok, err = pcall(SetupOptions)
    if not ok then
        if UI.win then UI.win:Hide() end
        UI.win = nil
    end
    return ok, err
end

local function OpenOptions(page)
    if not UI.win then
        Print("The options window failed to load; slash commands still work (/circ help).")
    elseif UI.win:IsShown() and not page then
        UI.win:Hide()
    else
        if page then UI.current = page end
        if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 852) end
        if UI.win:IsShown() then UI.SelectPage(UI.current) else UI.win:Show() end
    end
end

-- The game's addon button by the minimap (set up in Circlet.toc).
function Circlet_OnAddonCompartmentClick()
    OpenOptions()
end

function Circlet_OnAddonCompartmentEnter(_, button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("Circlet")
    GameTooltip:AddLine("Click to open the options.", 1, 1, 1)
    GameTooltip:AddLine("/circ help for commands", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function Circlet_OnAddonCompartmentLeave()
    if GameTooltip then GameTooltip:Hide() end
end

-- Shared with the files loaded after this one.
ns.OpenOptions = OpenOptions
ns.TrySetupOptions = TrySetupOptions
