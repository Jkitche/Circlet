-- Circlet: Debuff rings: a ring round your portrait and your target's, colored by debuff type.
local ADDON_NAME, ns = ...

local db, Print = ns.db, ns.Print

---------------------------------------------------------------------------
-- Debuff rings
---------------------------------------------------------------------------
-- A ring round the player frame's portrait and the target frame's, in the color of the
-- unit's top debuff's type (magic, curse, disease, poison, or none: bleeds and the like),
-- draining as the debuff runs out. Hidden when there's no debuff.
--
-- Addons can't read auras in combat on this client (the 12.1 aura lockdown: index and
-- instance-ID lookups throw, UNIT_AURA's payload is secret). So these rings never look at a
-- debuff themselves. Each one is an aura container (CreateFrame("AuraContainer")) set to the
-- unit, with one slot filtered to its debuffs; the game picks the debuff, shows and hides the
-- slot's button, and does the rest:
--   * color: the ring texture (Textures/RingNN.tga) is the button's dispel-type texture,
--     style PreserveAsset (our ring, not the game's border), tinted by the game from
--     customDispelColorMap. We never learn which type it was.
--   * drain: a Cooldown with the ring as its swipe texture is the button's duration
--     cooldown; the game feeds it the debuff's (hidden) duration. Reversed, so the dark swipe
--     covers the time gone and the colored part left shrinks.
--   * time left (optional): a font string as the button's duration text.
-- The aura buttons are forbidden while auras are secret: any call on one from here throws
-- in combat, and scripts can't be hooked on them. So everything is set up out of combat (and
-- redone after combat if a setting changed during it), and every call is guarded: if this
-- client lacks a piece, that piece is skipped and noted (/circ debuffdebug).
--
-- Edit mode and the preview draw sample rings of our own (plain textures), since a real one
-- needs a real debuff.

local STYLE_PRESERVE = 3 -- Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
local RING_TEX = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Ring%d"

-- The dispel types the color map names, and the color setting each one uses. The game's
-- names; "None" covers debuffs with no type (bleeds on clients that don't type them).
local TYPES = {
    { "Magic", "magic" }, { "Curse", "curse" }, { "Disease", "disease" }, { "Poison", "poison" },
    { "Bleed", "bleed" }, { "Enrage", "none" }, { "None", "none" },
}

local FILTERS = {
    player = { all = "HARMFUL", dispel = "HARMFUL|RAID_PLAYER_DISPELLABLE" },
    target = { all = "HARMFUL", mine = "HARMFUL|PLAYER" },
}

local diag = {} -- what happened setting up, for /circ debuffdebug
local function Note(msg)
    for _, m in ipairs(diag) do if m == msg then return end end
    table.insert(diag, msg)
    if #diag > 30 then table.remove(diag, 1) end
end

-- Calls obj:method(...) if it has it; false (and a note) if it's missing or throws.
local function Try(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then Note(method .. ": not in this client") return false end
    local ok, err = pcall(fn, obj, ...)
    if not ok then Note(method .. ": " .. tostring(err)) return false end
    return true, err
end

---------------------------------------------------------------------------
-- Where the rings go
---------------------------------------------------------------------------
local UNITS = { "player", "target" }

-- The unit frame and its portrait (classic names first, then the modern frame's).
local function Portrait(unit)
    if unit == "player" then
        local f = _G.PlayerFrame
        local c = f and f.PlayerFrameContainer
        return _G.PlayerPortrait or (c and c.PlayerPortrait), f
    end
    local f = _G.TargetFrame
    local c = f and f.TargetFrameContainer
    return _G.TargetFramePortrait or (c and c.Portrait), f
end

-- The ring texture whose hollow best matches inner / outer (they come in steps of 4%).
local function RingPath(inner, outer)
    local pct = math.floor(inner / outer * 25 + 0.5) * 4
    return RING_TEX:format(math.max(40, math.min(96, pct)))
end

-- Size and texture for a ring round this portrait: outer radius and texture path.
local function Geometry(portrait)
    local w = portrait and portrait.GetWidth and portrait:GetWidth() or 64
    if type(w) ~= "number" or w <= 0 then w = 64 end
    local inner = w / 2 + (db.debuffGap or 0)
    local outer = inner + math.max(2, db.debuffThickness or 5)
    return outer, RingPath(inner, outer)
end

local function Place(frame, unit)
    local portrait, unitFrame = Portrait(unit)
    if not (portrait and unitFrame) then return false end
    local outer, tex = Geometry(portrait)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", portrait, "CENTER", 0, 0)
    frame:SetSize(outer * 2, outer * 2)
    frame:SetFrameLevel((unitFrame:GetFrameLevel() or 1) + 10)
    return true, tex, outer
end

-- Keeps clicks going to the unit frame underneath (its menu, targeting).
local function NoMouse(f)
    if f.EnableMouse then pcall(f.EnableMouse, f, false) end
    if f.SetMouseClickEnabled then pcall(f.SetMouseClickEnabled, f, false) end
    if f.SetMouseMotionEnabled then pcall(f.SetMouseMotionEnabled, f, false) end
end

local function ColorOf(name)
    local c = db.debuffColors and db.debuffColors[name] or { r = 0.8, g = 0, b = 0 }
    return c
end

-- The color map the game tints the ring from: dispel type name -> color.
local function ColorMap(plain)
    local map = {}
    for _, t in ipairs(TYPES) do
        local c = ColorOf(t[2])
        map[t[1]] = (not plain and CreateColor) and CreateColor(c.r, c.g, c.b) or { r = c.r, g = c.g, b = c.b }
    end
    return map
end

---------------------------------------------------------------------------
-- The real rings: one aura container per unit
---------------------------------------------------------------------------
local live = {} -- unit -> { container, button, ring, cd, text }
local applied = {} -- unit -> the settings signature last applied

local function TimeFont(text, outer)
    text:SetFont(STANDARD_TEXT_FONT, math.max(9, math.floor(outer * 0.3)), "OUTLINE")
end

-- Puts our ring, sweep and time text on the slot's aura button. Out of combat only.
local function DressButton(r, tex, outer)
    local b = r.button
    NoMouse(b)
    Try(b, "SetHideTooltipInCombat", true)
    if not r.ring then
        r.ring = b:CreateTexture(nil, "ARTWORK")
        r.ring:SetAllPoints(b)
        r.cd = CreateFrame("Cooldown", nil, b)
        r.cd:SetAllPoints(b)
        NoMouse(r.cd)
        r.text = b:CreateFontString(nil, "OVERLAY")
        r.text:SetPoint("BOTTOM", b, "BOTTOM", 0, -2)
    end
    r.ring:SetTexture(tex)
    TimeFont(r.text, outer)

    -- Color: our ring as the dispel-type texture, tinted by the game.
    Try(b, "ClearDispelTypeTextures")
    local opts = { style = STYLE_PRESERVE, showWhenHarmful = true, showWithoutDispelType = true,
                   customDispelColorMap = ColorMap(false) }
    local ok = Try(b, "AddDispelTypeTexture", r.ring, opts)
    if not ok then
        opts.customDispelColorMap = ColorMap(true)
        ok = Try(b, "AddDispelTypeTexture", r.ring, opts)
    end
    if not ok then
        opts.customDispelColorMap = nil -- the game's own colors
        ok = Try(b, "AddDispelTypeTexture", r.ring, opts) or Try(b, "SetAuraBorder", r.ring, opts)
    end
    r.colored = ok

    -- Drain: the game's duration on our ring-shaped sweep.
    local cd = r.cd
    Try(cd, "SetDrawEdge", false)
    Try(cd, "SetDrawBling", false)
    Try(cd, "SetHideCountdownNumbers", true)
    Try(cd, "SetSwipeTexture", tex)
    Try(cd, "SetSwipeColor", 0, 0, 0, 0.75)
    Try(cd, "SetReverse", true)
    if db.debuffDrain then
        r.drain = Try(b, "SetDurationCooldown", cd)
    else
        Try(b, "ClearDurationCooldown")
        cd:Hide()
    end

    if db.debuffTime then
        Try(b, "SetDurationText", r.text)
    else
        Try(b, "ClearDurationText")
        r.text:SetText("")
    end
end

local function Container(unit)
    local r = live[unit]
    if r then return r end
    local _, unitFrame = Portrait(unit)
    if not unitFrame then return nil end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, unitFrame)
    if not ok or not c then Note("AuraContainer: " .. tostring(c)) return nil end
    NoMouse(c)
    Try(c, "SetUnit", unit)
    local slotOk, button = Try(c, "AddAuraSlot", "debuff", FILTERS[unit].all, {})
    if not (slotOk and type(button) == "table") then
        local got, b2 = Try(c, "GetAuraSlotFrame", "debuff")
        button = got and b2 or nil
    end
    if type(button) ~= "table" or button == c then
        -- no slot frame to dress (a client without slots): leave the container empty
        if button == c then button = nil end
    end
    r = { container = c, button = button }
    live[unit] = r
    if not button then Note(unit .. ": no aura slot frame") end
    return r
end

local function Signature(unit)
    local cs = {}
    for _, t in ipairs(TYPES) do
        local c = ColorOf(t[2])
        table.insert(cs, string.format("%.2f,%.2f,%.2f", c.r, c.g, c.b))
    end
    return table.concat({ tostring(db.debuffEnabled), tostring(db["debuff" .. (unit == "player" and "Player" or "Target")]),
        tostring(db.debuffThickness), tostring(db.debuffGap), tostring(db.debuffDrain), tostring(db.debuffTime),
        tostring(db.debuffOpacity), tostring(db.debuffPlayerFilter), tostring(db.debuffTargetFilter),
        table.concat(cs, ";") }, "|")
end

local function UnitOn(unit)
    if not db.debuffEnabled then return false end
    if unit == "player" then return db.debuffPlayer ~= false end
    return db.debuffTarget ~= false
end

-- Sets one unit's ring up from the settings. Out of combat only (the buttons are forbidden
-- in it); returns false to be tried again later.
local function Apply(unit)
    if InCombatLockdown and InCombatLockdown() then return false end
    if not UnitOn(unit) then
        local r = live[unit]
        if r then
            Try(r.container, "SetEnabled", false)
            r.container:Hide()
        end
        return true
    end
    local r = Container(unit)
    if not r then return true end -- nothing to be done on this client
    local placed, tex, outer = Place(r.container, unit)
    if not placed then Note(unit .. ": no portrait to put the ring round") return true end
    local which = unit == "player" and (db.debuffPlayerFilter or "all") or (db.debuffTargetFilter or "all")
    Try(r.container, "SetAuraSlotFilterString", "debuff", FILTERS[unit][which] or "HARMFUL")
    Try(r.container, "SetAuraSlotEnabled", "debuff", true)
    Try(r.container, "SetEnabled", true)
    r.container:SetAlpha((db.debuffOpacity or 100) / 100)
    r.container:Show()
    if r.button then
        Try(r.button, "ClearAllPoints")
        Try(r.button, "SetAllPoints", r.container)
        DressButton(r, tex, outer)
    end
    Try(r.container, "UpdateAllAuras")
    return true
end

local function ApplyAll(force)
    for _, unit in ipairs(UNITS) do
        local sig = Signature(unit)
        if force or applied[unit] ~= sig then
            if Apply(unit) then applied[unit] = sig end
        end
    end
end

---------------------------------------------------------------------------
-- Samples: edit mode and the preview
---------------------------------------------------------------------------
local SAMPLE_ORDER = { "poison", "curse", "magic", "disease", "bleed", "none" }
local samples = {} -- unit -> frame with .ring, .cd
local editing, previewUntil = false, 0

local function Sample(unit)
    local s = samples[unit]
    if s then return s end
    local _, unitFrame = Portrait(unit)
    if not unitFrame then return nil end
    s = CreateFrame("Frame", nil, UIParent)
    NoMouse(s)
    s.ring = s:CreateTexture(nil, "ARTWORK")
    s.ring:SetAllPoints(s)
    s.cd = CreateFrame("Cooldown", nil, s)
    s.cd:SetAllPoints(s)
    NoMouse(s.cd)
    s.text = s:CreateFontString(nil, "OVERLAY")
    s.text:SetPoint("BOTTOM", s, "BOTTOM", 0, -2)
    s:Hide()
    samples[unit] = s
    return s
end

local function ShowSample(unit, i)
    local s = Sample(unit)
    if not s then return end
    local _, unitFrame = Portrait(unit)
    local placed, tex, outer = Place(s, unit)
    if not placed then s:Hide() return end
    s:SetFrameStrata(unitFrame:GetFrameStrata() or "MEDIUM")
    local kind = SAMPLE_ORDER[(i - 1) % #SAMPLE_ORDER + 1]
    local c = ColorOf(kind)
    s.ring:SetTexture(tex)
    s.ring:SetVertexColor(c.r, c.g, c.b, 1)
    s:SetAlpha((db.debuffOpacity or 100) / 100)
    local cd = s.cd
    if db.debuffDrain then
        Try(cd, "SetDrawEdge", false)
        Try(cd, "SetDrawBling", false)
        Try(cd, "SetHideCountdownNumbers", true)
        Try(cd, "SetSwipeTexture", tex)
        Try(cd, "SetSwipeColor", 0, 0, 0, 0.75)
        Try(cd, "SetReverse", true)
        Try(cd, "SetCooldown", GetTime(), 6)
        cd:Show()
    else
        cd:Hide()
    end
    TimeFont(s.text, outer)
    s.started, s.kind = GetTime(), kind
    s:Show()
end

local function HideSamples()
    for _, s in pairs(samples) do s:Hide() end
end

local sampleStep = 0
local function CycleSamples()
    sampleStep = sampleStep + 1
    for n, unit in ipairs(UNITS) do
        local key = unit == "player" and "debuffPlayer" or "debuffTarget"
        if db[key] ~= false then ShowSample(unit, sampleStep + (n - 1) * 2) else
            local s = samples[unit]
            if s then s:Hide() end
        end
    end
end

local function SampleActive() return editing or GetTime() < previewUntil end

local function SetEditing(on)
    editing = on and true or false
    if editing then
        sampleStep = 0
        CycleSamples()
    elseif GetTime() >= previewUntil then
        HideSamples()
    end
end

local function Preview()
    previewUntil = GetTime() + 12
    sampleStep = 0
    CycleSamples()
end

---------------------------------------------------------------------------
-- Upkeep
---------------------------------------------------------------------------
-- Every half second: apply changed settings (out of combat), and step the samples.
local ticker = CreateFrame("Frame")
ticker.t = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.t < 0.5 then return end
    self.t = 0
    if not ns.loaded then return end
    ApplyAll(false)
    if SampleActive() then
        local s = samples.player or samples.target
        if s and s.started and GetTime() - s.started >= 6 then CycleSamples() end
        for _, unit in ipairs(UNITS) do
            local sm = samples[unit]
            if sm and sm:IsShown() and db.debuffTime then
                sm.text:SetText(string.format("%d", math.max(0, math.ceil(6 - (GetTime() - sm.started) - 0.05))))
            elseif sm then
                sm.text:SetText("")
            end
        end
    elseif samples.player or samples.target then
        HideSamples()
    end
end)

-- The unit frames can be built after us (a load-on-demand UI), and a reload in combat
-- leaves the buttons forbidden: try again when combat ends and the world is entered.
ns.Listen({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }, function() ApplyAll(true) end)

local function DebuffDebug()
    Print("Debuff rings: " .. (db.debuffEnabled and "on" or "off"))
    for _, unit in ipairs(UNITS) do
        local r = live[unit]
        Print(string.format("  %s: %s%s%s", unit, r and "container" or "no container",
            r and (r.button and ", slot" or ", no slot") or "",
            r and r.button and ((r.colored and ", colored" or ", not colored") .. (r.drain and ", drains" or ", no drain")) or ""))
    end
    if #diag == 0 then Print("  Nothing went wrong setting up.") end
    for _, m in ipairs(diag) do Print("  " .. m) end
end
ns.RegisterCommand({ "debuffdebug" }, DebuffDebug)

ns.PreviewDebuffRings = Preview
ns.DebuffRingsInfo = function() return live, samples, diag end -- tests

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "debuff", name = "Debuff", order = 14.95, since = "1.5.0",
    edit = { set = SetEditing, get = function() return editing end },
    preview = Preview, slash = { "debuff", "debuffs" }, help = "preview the debuff rings",
    toggle = { "Debuff rings", "A ring round your portrait and your target's in the color of the debuff's type, draining as it runs out." },
    alwaysInCombat = true,
    defaults = {
        debuffEnabled   = false, -- sits on the game's unit frames: off until you want it
        debuffPlayer    = true,
        debuffTarget    = true,
        debuffPlayerFilter = "all",  -- "all" or "dispel" (ones you can dispel)
        debuffTargetFilter = "mine", -- "all" or "mine" (ones you put there)
        debuffThickness = 5,
        debuffGap       = 0,
        debuffOpacity   = 100,
        debuffDrain     = true,
        debuffTime      = false,
        debuffColors = { -- the game's own debuff colors
            magic   = { r = 0.20, g = 0.60, b = 1.00 },
            curse   = { r = 0.60, g = 0.00, b = 1.00 },
            disease = { r = 0.60, g = 0.40, b = 0.00 },
            poison  = { r = 0.00, g = 0.60, b = 0.00 },
            bleed   = { r = 0.85, g = 0.10, b = 0.10 },
            none    = { r = 0.80, g = 0.00, b = 0.00 },
        },
    },
    page = { folder = "combat", order = 3.7, build = function(O)
            local Toggle, Range, Select, Color, Box = O.Toggle, O.Range, O.Select, O.Color, O.Box
            local RingTab, MergeTop, TopRow = O.RingTab, O.MergeTop, O.TopRow
            local function off() return not db.debuffEnabled end
            local tab = RingTab(13.9, "Debuffs", "Debuff Rings",
                "A ring round your portrait and your target's, in the color of the debuff's type, that drains as it "
                .. "runs out. The game picks the debuff and colors the ring itself: addons can't read debuffs in "
                .. "combat any more, so the ring can't show which one it is. Changes made in combat apply when it ends.",
                MergeTop(TopRow("debuff", "debuff rings", Preview, "Show sample rings round both portraits. Also /circ debuff."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "debuffEnabled", "Show debuff rings", "Put the rings round the portraits."),
                        player = Toggle(2, "debuffPlayer", "On your portrait", "A ring for your own debuffs.",
                            nil),
                        playerFilter = Select(3, "debuffPlayerFilter", "Your debuffs",
                            { all = "All", dispel = "Ones you can dispel" }, { "all", "dispel" },
                            "Which of your debuffs the ring shows."),
                        target = Toggle(4, "debuffTarget", "On your target's portrait", "A ring for your target's debuffs."),
                        targetFilter = Select(5, "debuffTargetFilter", "Target's debuffs",
                            { all = "All", mine = "Only yours" }, { "all", "mine" },
                            "Which of your target's debuffs the ring shows. Only yours: your Rend, your poisons, your curses."),
                        drain = Toggle(6, "debuffDrain", "Drain as it runs out",
                            "The ring empties as the debuff wears off. Off: a full ring while it lasts."),
                        time = Toggle(7, "debuffTime", "Show time left", "The game's countdown under the portrait."),
                    }),
                    colors = Box(3, "Colors", {
                        magic = Color(1, "debuffColors", "magic", "Magic", "Magic debuffs."),
                        curse = Color(2, "debuffColors", "curse", "Curse", "Curses."),
                        disease = Color(3, "debuffColors", "disease", "Disease", "Diseases."),
                        poison = Color(4, "debuffColors", "poison", "Poison", "Poisons."),
                        bleed = Color(5, "debuffColors", "bleed", "Bleed",
                            "Bleeds, if the game gives them a type of their own. Otherwise they use No type."),
                        none = Color(6, "debuffColors", "none", "No type",
                            "Debuffs with no type: bleeds on most clients, and most physical effects."),
                    }),
                    look = Box(4, "Appearance", {
                        thickness = Range(1, "debuffThickness", "Thickness", 2, 16, 1, "How wide the ring is."),
                        gap = Range(2, "debuffGap", "Gap", -8, 12, 1,
                            "Space between the portrait and the ring. Negative: the ring overlaps the portrait's edge."),
                        opacity = Range(3, "debuffOpacity", "Opacity", 20, 100, 5, "How solid the ring is."),
                    }),
                }))
            for _, k in ipairs({ "player", "playerFilter", "target", "targetFilter", "drain", "time" }) do
                tab.args.general.args[k].disabled = off
            end
            tab.args.general.args.playerFilter.disabled = function() return off() or db.debuffPlayer == false end
            tab.args.general.args.targetFilter.disabled = function() return off() or db.debuffTarget == false end
            return tab
        end },
})
