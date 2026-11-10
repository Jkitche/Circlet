-- Circlet: Quest rings: pin a quest from the quest log's right-click menu and it gets
-- its own ring, stacked by the quest list, until you turn it in.
local ADDON_NAME, ns = ...

local db, Print, IsSecret, CreateLiveRing = ns.db, ns.Print, ns.IsSecret, ns.CreateLiveRing

---------------------------------------------------------------------------
-- Quest rings
---------------------------------------------------------------------------
-- Each pinned quest shows on its own ring: the quest's name, objectives done ("1 / 3"),
-- and the next unfinished objective ("Screecher Feather 5/8"). With the segmented
-- style the ring has one notch per objective. When every objective is done it turns
-- the quest-complete color and says "Ready to turn in"; once the quest leaves your log
-- (turned in or abandoned) its ring goes away and the ones below move up.

local MAX_PINS = 5
local pinRings = {}
local missingSince = {} -- questID -> when it was first missing from the log

local function CharKey()
    local name, realm = UnitName("player"), GetRealmName and GetRealmName() or ""
    if IsSecret(name) then return nil end
    return (name or "?") .. "-" .. (realm or "")
end

local function PinList()
    local key = CharKey()
    if not key then return {} end
    db.pinned = db.pinned or {}
    db.pinned[key] = db.pinned[key] or {}
    return db.pinned[key]
end

local function IsPinned(questID)
    for _, id in ipairs(PinList()) do
        if id == questID then return true end
    end
    return false
end

-- The quest log, read at most twice a second for all the rings.
local snapshot, snapshotAt = nil, -1
local function QuestLog()
    local now = GetTime()
    if now - snapshotAt > 0.5 then
        snapshot, snapshotAt = ns.ReadQuestLog and ns.ReadQuestLog() or nil, now
    end
    return snapshot
end

local function TitleFor(questID)
    local q = QuestLog() and QuestLog()[questID]
    if q and q.title ~= "" then return q.title end
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    return (type(title) == "string" and not IsSecret(title)) and title or ("Quest " .. questID)
end

local function TogglePin(questID)
    if not questID or IsSecret(questID) then return end
    local list = PinList()
    for i, id in ipairs(list) do
        if id == questID then
            table.remove(list, i)
            Print("Removed the quest ring for " .. TitleFor(questID) .. ".")
            return
        end
    end
    if #list >= MAX_PINS then
        Print("You can have up to " .. MAX_PINS .. " quest rings; remove one first.")
        return
    end
    table.insert(list, questID)
    snapshotAt = -1 -- read the log fresh
    Print("Created a quest ring for " .. TitleFor(questID) .. ".")
end

-- One quest's ring state.
local function QuestState(title, objectives)
    local c = db.questColors
    local n, done, sum, next = 0, 0, 0, nil
    for _, o in ipairs(objectives) do
        n = n + 1
        local frac = o.done and 1 or (o.need > 0 and math.min(1, o.have / o.need) or 0)
        sum = sum + frac
        if o.done then done = done + 1 elseif not next then next = o end
    end
    local st = { title = title, notches = n >= 2 and n or nil }
    if n == 0 then
        st.value, st.frac, st.label, st.color = "", 0, "No objectives", c.progress
        return st
    end
    st.frac = sum / n
    if done == n then
        st.value, st.color, st.label, st.labelColor = done .. " / " .. n, c.complete, "Ready to turn in", c.complete
    else
        st.value, st.color = done .. " / " .. n, c.progress
        local name = ns.ObjectiveName and ns.ObjectiveName(next.text) or next.text
        st.label = next.bar and string.format("%s %d%%", name, next.have)
            or string.format("%s %d/%d", name, next.have, next.need)
    end
    return st
end

-- Right-click on a quest ring: a menu to remove it.
local function RingMenu(frame, i)
    local questID = PinList()[i]
    if not questID then return end
    local title = TitleFor(questID)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(frame, function(_, root)
            if root.CreateTitle then root:CreateTitle(title) end
            root:CreateButton("Remove Quest Ring", function() TogglePin(questID) end)
            if C_QuestLog and C_QuestLog.SetSelectedQuest and QuestMapFrame_OpenToQuestDetails then
                root:CreateButton("Show in Quest Log", function() QuestMapFrame_OpenToQuestDetails(questID) end)
            end
        end)
    else
        TogglePin(questID) -- no menu system: just remove it
    end
end

local SAMPLES = {
    { title = "The Defias Brotherhood", objectives = {
        { text = "Defias Thug slain: 9/12", have = 9, need = 12 },
        { text = "Red Leather Bandana: 4/4", have = 4, need = 4, done = true },
        { text = "Gold Pickup Schedule: 0/1", have = 0, need = 1 } } },
    { title = "Feathers for Grek", objectives = {
        { text = "Screecher Feather: 8/8", have = 8, need = 8, done = true } } },
}

for i = 1, MAX_PINS do
    pinRings[i] = CreateLiveRing({
        key = "pin" .. i,
        watchEvery = 0.5,
        onRightClick = function(frame) RingMenu(frame, i) end,
        -- (Settings aren't loaded yet when the rings are created; Events refreshes them.)
        menuEnabled = function() return not CircletDB or db.pinMenu end,
        locked = function() return CircletDB ~= nil and not db.pinMovable end,
        read = function()
            local list = PinList()
            local questID = list[i]
            if not questID then return nil end
            local log = QuestLog()
            if not log then return nil end
            local q = log[questID]
            if not q then
                -- Turned in or abandoned: drop it (once it's been gone a moment, and only
                -- when the log has loaded); the rings below move up.
                if next(log) then
                    local now = GetTime()
                    missingSince[questID] = missingSince[questID] or now
                    if now - missingSince[questID] > 1.5 then
                        missingSince[questID] = nil
                        table.remove(list, i)
                    end
                end
                return nil
            end
            missingSince[questID] = nil
            return QuestState(q.title, q.objectives)
        end,
        sample = function()
            local s = SAMPLES[i]
            return s and QuestState(s.title, s.objectives) or nil
        end,
    })
end

local function SetPinsEditing(on)
    for _, ring in ipairs(pinRings) do ring.SetEditing(on) end
end

local function PreviewPins()
    for _, ring in ipairs(pinRings) do ring.Preview(8) end
end

---------------------------------------------------------------------------
-- Quest log right-click menu
---------------------------------------------------------------------------
local function AddMenuEntry(owner, root, contextData)
    local questID = (type(contextData) == "table" and contextData.questID)
        or (owner and (owner.questID or (owner.GetQuestID and owner:GetQuestID())))
    if not questID or IsSecret(questID) or not root or not root.CreateButton then return end
    if root.CreateDivider then root:CreateDivider() end
    root:CreateButton(IsPinned(questID) and "Remove Quest Ring" or "Create Quest Ring", function()
        TogglePin(questID)
    end)
end

-- The world map's quest log and the objective tracker both use the modern menu system;
-- the exact menu names vary by client, so add to each that exists (others never fire).
if Menu and Menu.ModifyMenu then
    for _, tag in ipairs({ "MENU_QUEST_MAP_LOG_TITLE", "MENU_QUEST_LOG_TITLE", "MENU_QUEST_OBJECTIVE_TRACKER",
                           "MENU_OBJECTIVE_TRACKER_QUEST", "MENU_QUEST_TRACKER" }) do
        pcall(Menu.ModifyMenu, tag, AddMenuEntry)
    end
end

-- The classic-style quest log (QuestLogFrame) has no right-click menu: give it one.
if hooksecurefunc and QuestLogTitleButton_OnClick and MenuUtil and MenuUtil.CreateContextMenu then
    hooksecurefunc("QuestLogTitleButton_OnClick", function(self, button)
        if button ~= "RightButton" or not GetQuestLogTitle then return end
        local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(self:GetID())
        if isHeader or not questID then return end
        MenuUtil.CreateContextMenu(self, function(owner, root)
            if title and root.CreateTitle then root:CreateTitle(title) end
            AddMenuEntry(owner, root, { questID = questID })
        end)
    end)
end

-- /circ ring [name]: pin or unpin a quest whose name contains the text; /circ ring clear.
local function SlashRing(arg)
    arg = arg and arg:lower() or ""
    if arg == "clear" then
        wipe(PinList())
        Print("Removed all quest rings.")
        return
    end
    local log = QuestLog()
    snapshotAt = -1
    if arg == "" or not log then
        Print("Right-click a quest in your quest log and choose Create Quest Ring, or /circ ring <part of the quest name>.")
        return
    end
    for questID, q in pairs(log) do
        if q.title:lower():find(arg, 1, true) then
            TogglePin(questID)
            return
        end
    end
    Print("No quest in your log matches '" .. arg .. "'.")
end

ns.RegisterCommand({ "ring" }, SlashRing, "pin a quest to its own ring (or right-click it in the quest log); /circ ring clear", "ring <name>")

-- Shared with the files loaded after this one.
ns.SetPinsEditing = SetPinsEditing
ns.IsPinsEditing = function() return pinRings[1].IsEditing() end
ns.PreviewPins = PreviewPins
ns.SlashRing = SlashRing
ns.ClearPins = function() wipe(PinList()) end
ns.RefreshPinClicks = function()
    for _, ring in ipairs(pinRings) do ring.RefreshClicks() end
end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "pin", name = "Quest rings", order = 15,
    edit = { set = SetPinsEditing, get = ns.IsPinsEditing },
    preview = PreviewPins, slash = { "pins", "pin", "rings" }, help = "preview the quest rings",
    toggle = { "Quest rings", "Quests you've pinned from the quest log's right-click menu." },
    onReset = function() ns.RefreshPinClicks() end,
    onLoaded = function() ns.RefreshPinClicks() end,
    defaults = {
        -- Quest rings: quests you pin from the quest log's right-click menu, each tracked on
        -- its own ring, stacked down the right side by the quest list.
        pinEnabled   = true,
        pinSize      = 100,
        pinThickness = 10,
        pinOpacity   = 100,
        pinX         = 600,   -- set from your screen width the first time (see Events)
        pinFromTop   = 200,
        pinHold      = 3,
        pinStyle     = "segmented", -- with this, one notch per objective
        pinBorder    = 2,
        pinMenu      = true,  -- right-click a quest ring for its menu (remove it)
        pinMovable   = true,  -- quest rings can be dragged in edit mode
        pinned       = {},    -- per character: the pinned quest IDs, in order
    },
    page = { folder = nil, order = 5, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(5, "Quest rings", "Quest Rings",
                "Right-click a quest in your quest log and choose Create Quest Ring to give it its own ring, stacked "
                .. "by the quest list. Each shows objectives done, with one notch per objective (segmented style), and "
                .. "the next objective to do. It goes away once the quest leaves your log. Up to 5; also /circ ring <name>.",
                MergeTop(TopRow("pin", "quest rings", ns.PreviewPins, "Show two sample quest rings."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "pinEnabled", "Show quest rings", "Show the rings for pinned quests."),
                        menu = Toggle(1.2, "pinMenu", "Right-click menu",
                            "Right-click a quest ring for a menu to remove it. Turn off so the rings ignore the mouse "
                            .. "entirely (remove them from the quest log's menu or /circ ring instead).",
                            function() ns.RefreshPinClicks() end),
                        movable = Toggle(1.4, "pinMovable", "Movable",
                            "Let the quest rings be dragged (and reset with right-click) in edit mode. Turn off to lock "
                            .. "them in place; the position sliders below still work."),
                        clear = {
                            type = "execute", order = 2, width = 1.1, name = "Remove all quest rings",
                            confirm = true, confirmText = "Remove every quest ring on this character?",
                            func = function() ns.ClearPins() end,
                        },
                    }),
                    size = SizeBox(3, "pin", "quest rings",
                        "Offset from the center of the screen. The rings stack downward from here; by default they "
                        .. "start just left of the quest list."),
                }))
            tab.args.size.args.hold = nil
            tab.args.position.args.fromTop.desc = "Gap between the top of the screen and the top of the first ring."
            return tab
        end },
})
