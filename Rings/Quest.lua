-- Circlet: Quest ring: objective progress, the "!" animation and the turn-in alert.
local ADDON_NAME, ns = ...

local CreateProgressRing, IsSecret, RingHolder, db = ns.CreateProgressRing, ns.IsSecret, ns.RingHolder, ns.db

---------------------------------------------------------------------------
-- Quest ring: the same donut when a kill or drop advances a quest objective
---------------------------------------------------------------------------
-- Driven by the quest log, which stays readable in combat. Each update is
-- diffed against the previous snapshot; only objectives that existed before
-- and went UP show a ring, so logging in, accepting a quest or abandoning
-- one never fires a false ring.

-- Objective complete: a quest-giver "!" pops up in the middle of the quest ring --
-- It sits in the ring's hollow centre, behind the ring's text: springs in with an
-- overshoot, wiggles, settles back to half strength so the text stays readable,
-- pulses gently with a glow, then swells slightly as it fades.

local EXCLAIM_LENGTH = 2.2

local exclaim = CreateFrame("Frame", nil, RingHolder("quest"))
exclaim:SetFrameStrata("HIGH")
exclaim:SetSize(1, 1)
exclaim:Hide()

exclaim.glow = exclaim:CreateTexture(nil, "BACKGROUND")
exclaim.glow:SetTexture("Interface\\Cooldown\\star4")
exclaim.glow:SetBlendMode("ADD")
exclaim.glow:SetVertexColor(1.0, 0.82, 0.2)
exclaim.glow:SetPoint("CENTER")

exclaim.icon = exclaim:CreateTexture(nil, "ARTWORK")
exclaim.icon:SetPoint("CENTER")
if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestNormal") then
    exclaim.icon:SetAtlas("QuestNormal") -- the yellow "!" over quest givers
else
    exclaim.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
end

-- The "!" for a finished objective, or the quest-giver "?" for a quest that's ready
-- to hand in.
local function SetExclaimIcon(turnIn)
    if exclaim.turnIn == turnIn then return end
    exclaim.turnIn = turnIn
    local atlas = turnIn and "QuestTurnin" or "QuestNormal"
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        exclaim.icon:SetAtlas(atlas)
    else
        exclaim.icon:SetTexture(turnIn and "Interface\\GossipFrame\\ActiveQuestIcon"
            or "Interface\\GossipFrame\\AvailableQuestIcon")
    end
end
exclaim.turnIn = false

local function PlayExclaim(ringFrame, geom, turnIn)
    SetExclaimIcon(turnIn and true or false)
    -- Fills the ring's hollow centre (inner diameter = 2R - T).
    local inner = 2 * geom.R - geom.T
    exclaim.base = math.max(20, inner * 0.8)
    exclaim.anchorY = 0
    exclaim.ring = ringFrame
    -- One level below the ring, so the ring's text draws on top of the "!".
    if ringFrame:GetFrameLevel() < 2 then ringFrame:SetFrameLevel(2) end
    exclaim:SetFrameStrata(ringFrame:GetFrameStrata())
    exclaim:SetFrameLevel(ringFrame:GetFrameLevel() - 1)
    exclaim.t = 0
    exclaim:Show()
end

exclaim:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    local t = self.t
    if t > EXCLAIM_LENGTH then self:Hide() return end

    -- Scale: spring in (0 -> 1.3), settle back to 1.
    local scale
    if t < 0.22 then
        scale = 1.3 * (1 - (1 - t / 0.22) ^ 2)
    elseif t < 0.4 then
        scale = 1.3 - 0.3 * ((t - 0.22) / 0.18)
    else
        scale = 1
    end

    -- Wiggle side to side, dying down over the first second.
    local wiggle = (t < 1.0) and math.sin(t * 2 * math.pi * 3) * 0.3 * (1 - t) or 0
    -- Small pulse once it has landed (kept small so it doesn't jitter behind the text).
    local bob = (t > 0.4) and math.sin((t - 0.4) * 2 * math.pi * 1.4) * 2 or 0
    -- Exit: swell a little and fade over the last half second.
    local exitT = math.max(0, (t - (EXCLAIM_LENGTH - 0.5)) / 0.5)
    scale = scale * (1 + 0.15 * exitT)
    -- Full strength while it pops in, then settles to ~55% so the text reads over it.
    local strength = (t < 0.4) and 1 or math.max(0.55, 1 - (t - 0.4) / 0.4 * 0.45)
    local alpha = strength * (1 - exitT)

    self:ClearAllPoints()
    self:SetPoint("CENTER", self.ring, "CENTER", 0, self.anchorY + bob)

    local size = self.base * scale
    self.icon:SetSize(size, size)
    self.icon:SetRotation(wiggle)
    self.icon:SetAlpha(alpha)

    local glowSize = self.base * 2.2 * (0.85 + 0.15 * math.sin(t * 2 * math.pi * 1.4))
    self.glow:SetSize(glowSize, glowSize)
    self.glow:SetAlpha(alpha * math.min(1, t / 0.3) * 0.7)
end)

local questRing = CreateProgressRing({
    key = "quest",
    samples = function()
        return {
            { id = "edit-q1", name = "Screecher Feather", title = "Feathers for Grek", from = 3, to = 5, max = 8 },
            { id = "edit-q2", name = "Sunscale Screecher slain", title = "Raptor Thieves", from = 9, to = 10,
              max = 10, editTime = 4 },
            { id = "edit-q3", name = "Raptor Thieves", from = 2, to = 3, max = 3, turnIn = true,
              gainText = "Done!", editTime = 4 },
        }
    end,
    style = function(e, finished)
        local c, done = db.questColors.progress, db.questColors.complete
        local complete = e.to >= e.max
        if e.turnIn then
            return { fill = done, rank = done, label = "Ready to turn in", labelColor = done }
        end
        if complete and finished then
            return { fill = done, rank = done, label = "Complete!", labelColor = done }
        end
        return { fill = complete and done or c, rank = c, label = e.title, labelColor = { r = 0.8, g = 0.8, b = 0.8 } }
    end,
    onFinish = function(e, frame, geom)
        if db.questCompleteFx and e.to >= e.max then
            PlayExclaim(frame, geom, e.turnIn)
            return EXCLAIM_LENGTH + 0.3 -- keep the ring up while the "!" plays
        end
    end
})

local objectiveSnapshot -- [questID] = { title, objectives = { [index] = { have, need, done, text, bar } } }

local function ObjectiveName(text)
    local name = (text:gsub("%s*%d+%s*/%s*%d+%s*", " "))
    name = (name:gsub("%s*%(?%d+%%%)?", ""))
    name = strtrim(name)
    name = strtrim((name:gsub(":$", "")))
    name = (name:gsub("^%-%s*", "")) -- " - Kobold Vermin slain" list style
    return name ~= "" and name or text
end

local function ReadQuestLog()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestObjectives) then
        return nil
    end

    local snap = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local questID = info and not info.isHeader and info.questID
        if questID and not IsSecret(questID) then
            local objectives = C_QuestLog.GetQuestObjectives(questID)
            if objectives and not IsSecret(objectives) then
                local q = {}
                for index, o in ipairs(objectives) do
                    local have, need, done, text = o.numFulfilled, o.numRequired, o.finished, o.text
                    if not (IsSecret(have) or IsSecret(need) or IsSecret(done) or IsSecret(text)) then
                        q[index] = {
                            have = have or 0,
                            need = need or 0,
                            done = done == true,
                            text = text or "",
                            bar  = (o.type == "progressbar"),
                        }
                    end
                end
                local title = info.title
                if IsSecret(title) then title = nil end
                snap[questID] = { title = title or "", objectives = q }
            end
        end
    end
    return snap
end

local function AllObjectivesDone(quest)
    local any = false
    for _, o in pairs(quest.objectives) do
        if not o.done then return false end
        any = true
    end
    return any
end

local function CheckProgress()
    local snap = ReadQuestLog()
    if not snap then return end

    local prev = objectiveSnapshot
    objectiveSnapshot = snap
    if not prev then return end -- first read is just the baseline

    for questID, quest in pairs(snap) do
        local old = prev[questID]
        if old then
            for index, o in pairs(quest.objectives) do
                local was = old.objectives[index]
                if was and o.done and not was.done and ns.SessionAdd then
                    ns.SessionAdd("objectives", nil, 1) -- session summary
                end
                if was and o.have > was.have then
                    -- An objective the game marks finished counts as complete even if its
                    -- counter is odd (some report 1/1 only at the end).
                    local need = o.need
                    if o.done and o.have < need then need = o.have end
                    questRing.Queue({
                        id = questID .. ":" .. index,
                        name = ObjectiveName(o.text),
                        title = quest.title,
                        from = was.have,
                        to = o.have,
                        max = need,
                        percent = o.bar,
                    })
                end
            end
            -- Every objective done now, and not before: the quest is ready to hand in.
            if db.questTurnIn and AllObjectivesDone(quest) and not AllObjectivesDone(old) then
                local count = 0
                for _ in pairs(quest.objectives) do count = count + 1 end
                questRing.Queue({
                    id = questID .. ":turnin",
                    name = quest.title,
                    from = count - 1,
                    to = count,
                    max = count,
                    turnIn = true,
                    gainText = "Done!",
                })
            end
        end
    end
end

local progressQueued = false
local function QueueCheckProgress()
    if progressQueued then return end
    progressQueued = true
    C_Timer.After(0.1, function()
        progressQueued = false
        CheckProgress()
    end)
end

local function PreviewQuestComplete()
    questRing.Preview({
        { id = "p4", name = "Sunscale Screecher slain", title = "Raptor Thieves", from = 9, to = 10, max = 10 },
    })
end

local function PreviewQuestRing()
    questRing.Preview({
        { id = "p1", name = "Screecher Feather", title = "Feathers for Grek", from = 3, to = 5, max = 8 },
        { id = "p2", name = "Area explored", title = "Into the Barrens", from = 40, to = 65, max = 100, percent = true },
        { id = "p3", name = "Sunscale Screecher slain", title = "Raptor Thieves", from = 9, to = 10, max = 10 },
        { id = "p5", name = "Raptor Thieves", from = 2, to = 3, max = 3, turnIn = true, gainText = "Done!" },
    })
end

-- Quest log changes: check for objective progress.
ns.Listen({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED:player" }, function() QueueCheckProgress() end)

ns.RegisterCommand({ "complete" }, PreviewQuestComplete, "preview the objective-complete animation")

-- Shared with the files loaded after this one.
ns.PreviewQuestComplete = PreviewQuestComplete
ns.ReadQuestLog = ReadQuestLog
ns.ObjectiveName = ObjectiveName
ns.PreviewQuestRing = PreviewQuestRing
ns.QueueCheckProgress = QueueCheckProgress
ns.questRing = questRing

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "quest", name = "Quest", order = 2,
    ring = questRing,
    preview = PreviewQuestRing, slash = { "quest", "pop" }, help = "preview the quest ring",
    toggle = { "Quest ring", "Fills when a kill or drop advances a quest objective." },
    defaults = {
        questEnabled     = true,
        questAfterCombat = true,
        questShowDelta   = false,
        questCompleteFx  = true, -- "!" animation when an objective completes
        questSize        = 120,
        questThickness   = 12,
        questOpacity     = 100, -- percent
        questX           = -170,
        questFromTop     = 50,
        questHold        = 3,
        questStyle       = "smooth",
        questBorder      = 2, -- black border width (0 = none)
        questTurnIn      = true, -- "Ready to turn in" once every objective of a quest is done
        questColors = {
            progress = { r = 1.00, g = 0.82, b = 0.00 }, -- quest gold
            complete = { r = 0.25, g = 1.00, b = 0.25 },
        },
    },
    page = { folder = "progress", order = 3, build = function(O)
            local Toggle, Range, Select, Color, Execute, Box = O.Toggle, O.Range, O.Select, O.Color, O.Execute, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            local tab = RingTab(3, "Quest", "Quest Ring",
                "A donut that fills when a kill or drop advances a quest objective, e.g. Screecher Feather 5 / 8.",
                MergeTop(TopRow("quest", "quest ring", PreviewQuestRing, "Show example progress: a drop, a percentage "
                    .. "objective, and an objective finishing. Also /sq quest."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "questEnabled", "Show quest ring", "Pop up and fill when an objective advances."),
                        afterCombat = Toggle(2, "questAfterCombat", "Wait until combat ends",
                            "Hold objective progress made in a fight and show it once combat ends."),
                        delta = Toggle(3, "questShowDelta", "Show gain as %",
                            "Add a line under the gain showing it as a share of the objective, e.g. +4.2%."),
                        completeFx = Toggle(4, "questCompleteFx", "Complete animation",
                            "A quest-giver \"!\" pops up in the middle of the ring, behind the text, when an objective is finished."),
                        turnIn = Toggle(5, "questTurnIn", "Turn-in alert",
                            "Once every objective of a quest is done, the ring shows the quest as \"Ready to turn in\" "
                            .. "(with a \"?\" if the complete animation is on)."),
                    }),
                    colors = Box(3, "Colors", {
                        progress = Color(1, "questColors", "progress", "In progress", "Ring and count color while an objective is in progress."),
                        complete = Color(2, "questColors", "complete", "Complete", "Ring color when an objective is finished."),
                    }),
                    size = SizeBox(4, "quest", "quest ring",
                        "Offset from the center of the screen. The default sits just left of the XP ring."),
                }))
            return tab
        end },
})
