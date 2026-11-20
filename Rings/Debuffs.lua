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
-- Effects per type (debuffFx): layers of effect textures, each a dispel-type texture too,
-- style CustomAsset: its customDispelAssetMap gives its own art (Textures/DebuffFx<Art>.tga,
-- made by tools/make_debuff_fx.py) for its types and a blank texture for every other, so the
-- game shows only the layers for the debuff it picked, and tints them from the same color map.
-- Each layer has looping animations (turning, pulsing, rising, dripping), started once while
-- they're still ours and then handed to the button, which plays them when its aura shows
-- (AddAuraShownAnimation; after that they're the game's and can't even be asked about).
--   every type: a soft glow behind the ring, pulsing
--   magic:   two fields of sparkles turning opposite ways and twinkling, and a band of
--            arcane runes turning slowly outside the ring
--   poison:  bubbles round the ring, small bubbles rising off it, venom dripping
--   curse:   wisps swirling backwards, thin wisps the other way, shadow motes rising
--   disease: pulsing spores, a swarm of flies circling, bubbles rising
--   no type (bleeds, physical effects): blood running down at two speeds, and specks of
--            blood throbbing like a heartbeat
--
-- Edit mode and the preview draw sample rings of our own (plain textures), since a real one
-- needs a real debuff.

local STYLE_PRESERVE = 3 -- Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
local STYLE_CUSTOM = 4   -- Enum.CustomAuraButtonDispelTypeTextureStyle.CustomAsset
local TEXTURES = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\"
local RING_TEX = TEXTURES .. "Ring%d"
local BLANK = TEXTURES .. "Blank"
local FX_SCALE = 1.5 -- the effect textures are drawn 1.5x the ring, centered on it

-- The dispel types the color map names, and the color setting each one uses. The game's
-- names; "None" covers debuffs with no type (bleeds on clients that don't type them).
local TYPES = {
    { "Magic", "magic" }, { "Curse", "curse" }, { "Disease", "disease" }, { "Poison", "poison" },
    { "Bleed", "bleed" }, { "Enrage", "none" }, { "None", "none" },
}

-- The effect layers: which dispel types each is for, its art, and its looping animations.
--   turn   seconds per turn (negative: counter-clockwise)
--   pulse  { from alpha, to alpha, seconds } back and forth
--   grow   { from scale, to scale, seconds } back and forth
--   drip   { distance, seconds }: slides down and fades, over and over
--   rise   { distance, seconds }: slides up and fades, over and over
--   add    drawn additively (glows); back: drawn behind the ring
local NO_TYPE = { "Bleed", "Enrage", "None" }
local ALL_TYPES = { "Magic", "Curse", "Disease", "Poison", "Bleed", "Enrage", "None" }
local FX = {
    { kind = "glow", types = ALL_TYPES, art = "Glow", add = true, back = true, pulse = { 0.35, 0.9, 1.3 } },
    { kind = "magicRunes", types = { "Magic" }, art = "MagicRunes", add = true, turn = -30, pulse = { 0.4, 0.85, 2.2 } },
    { kind = "magicStars", types = { "Magic" }, art = "MagicStars", add = true, turn = 16, pulse = { 0.35, 1, 0.6 } },
    { kind = "magicStarsSmall", types = { "Magic" }, art = "MagicStarsSmall", add = true, turn = -11, pulse = { 0.2, 1, 0.45 } },
    { kind = "poisonBubbles", types = { "Poison" }, art = "PoisonBubbles", turn = 24, pulse = { 0.55, 1, 1.2 } },
    { kind = "poisonRise", types = { "Poison" }, art = "Rise", rise = { 16, 1.8 } },
    { kind = "poisonDrip", types = { "Poison" }, art = "Drip", drip = { 9, 2.2 } },
    { kind = "curseWisps", types = { "Curse" }, art = "CurseWisps", turn = -5, pulse = { 0.6, 1, 2 } },
    { kind = "curseThin", types = { "Curse" }, art = "CurseWispsThin", add = true, turn = 9, pulse = { 0.3, 0.9, 1.4 } },
    { kind = "curseMotes", types = { "Curse" }, art = "Motes", rise = { 18, 2.4 } },
    { kind = "diseaseSpores", types = { "Disease" }, art = "DiseaseSpores", turn = 40, grow = { 0.94, 1.06, 1.6 } },
    { kind = "diseaseFlies", types = { "Disease" }, art = "Flies", turn = 3.5 },
    { kind = "diseaseRise", types = { "Disease" }, art = "Rise", rise = { 12, 2.6 } },
    { kind = "bleedDrip", types = NO_TYPE, art = "Drip", drip = { 10, 1.5 } },
    { kind = "bleedDripB", types = NO_TYPE, art = "DripB", drip = { 13, 2.1 } },
    { kind = "bleedSpecks", types = NO_TYPE, art = "Splatter", pulse = { 0.3, 1, 0.38 } },
}
-- A sample's color name -> the dispel type whose layers it shows.
local SAMPLE_TYPE = { poison = "Poison", curse = "Curse", magic = "Magic", disease = "Disease", bleed = "Bleed", none = "None" }

local function ForType(fx, typeName)
    for _, t in ipairs(fx.types) do if t == typeName then return true end end
    return false
end

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

-- Looping animations for one effect texture; returns the groups.
local function Animate(tex, fx)
    local groups = {}
    local function Group(looping)
        local ok, ag = pcall(tex.CreateAnimationGroup, tex)
        if not ok or not ag then return nil end
        ag:SetLooping(looping)
        table.insert(groups, ag)
        return ag
    end
    if fx.turn then
        local ag = Group("REPEAT")
        if ag then
            local a = ag:CreateAnimation("Rotation")
            a:SetDegrees(fx.turn > 0 and -360 or 360) -- positive degrees turn counter-clockwise
            a:SetDuration(math.abs(fx.turn))
            if a.SetOrigin then pcall(a.SetOrigin, a, "CENTER", 0, 0) end
        end
    end
    if fx.pulse then
        local ag = Group("BOUNCE")
        if ag then
            local a = ag:CreateAnimation("Alpha")
            a:SetFromAlpha(fx.pulse[1]); a:SetToAlpha(fx.pulse[2]); a:SetDuration(fx.pulse[3])
            if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
        end
    end
    if fx.grow then
        local ag = Group("BOUNCE")
        if ag then
            local a = ag:CreateAnimation("Scale")
            local from, to = fx.grow[1], fx.grow[2]
            if a.SetScaleFrom then
                pcall(a.SetScaleFrom, a, from, from); pcall(a.SetScaleTo, a, to, to)
            else
                pcall(a.SetFromScale, a, from, from); pcall(a.SetToScale, a, to, to)
            end
            a:SetDuration(fx.grow[3])
            if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
        end
    end
    local slide = fx.drip and { -fx.drip[1], fx.drip[2] } or fx.rise and { fx.rise[1], fx.rise[2] }
    if slide then
        local ag = Group("REPEAT")
        if ag then
            local m = ag:CreateAnimation("Translation")
            m:SetOffset(0, slide[1]); m:SetDuration(slide[2])
            local f = ag:CreateAnimation("Alpha")
            f:SetFromAlpha(1); f:SetToAlpha(0); f:SetDuration(slide[2])
            if f.SetSmoothing then f:SetSmoothing("IN") end
        end
    end
    return groups
end

-- One effect texture per kind on a frame (the aura button or a sample), with its animations.
local function FxTextures(holder, owner)
    if holder.fx then return holder.fx end
    holder.fx = {}
    for i, fx in ipairs(FX) do
        local tex = owner:CreateTexture(nil, fx.back and "BACKGROUND" or "OVERLAY", nil, fx.back and 0 or math.min(7, i % 8))
        tex:SetPoint("CENTER", owner, "CENTER", 0, 0)
        if fx.add and tex.SetBlendMode then tex:SetBlendMode("ADD") end
        holder.fx[fx.kind] = { tex = tex, groups = Animate(tex, fx), def = fx }
    end
    return holder.fx
end

local function SizeFx(holder, outer)
    for _, f in pairs(holder.fx or {}) do f.tex:SetSize(outer * 2 * FX_SCALE, outer * 2 * FX_SCALE) end
end

-- Plays or stops a sample's effect. Only for the samples: once an animation is handed to an
-- aura button (AddAuraShownAnimation) the game owns it, and asking about it (IsPlaying) or
-- driving it from here is forbidden. So we remember what we started instead of asking.
local function PlayFx(f, on)
    if f.owned or f.playing == on then return end
    f.playing = on
    for _, ag in ipairs(f.groups) do
        if on then pcall(ag.Play, ag) else pcall(ag.Stop, ag) end
    end
end

-- The asset map for one effect: its art for its types, blank for every other.
local function AssetMap(fx, wrap)
    local mine = {}
    for _, t in ipairs(fx.types) do mine[t] = true end
    local map = {}
    for _, t in ipairs(TYPES) do
        local path = mine[t[1]] and (TEXTURES .. "DebuffFx" .. fx.art) or BLANK
        map[t[1]] = wrap and { asset = path } or path
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

    -- Effects: the game shows the one for the debuff's type.
    local fxs = FxTextures(r, b)
    SizeFx(r, outer)
    r.fxOk = 0
    for _, fx in ipairs(FX) do
        local f = fxs[fx.kind]
        if db.debuffFx then
            local o = { style = STYLE_CUSTOM, showWhenHarmful = true, showWithoutDispelType = true,
                        customDispelAssetMap = AssetMap(fx, true), customDispelColorMap = opts.customDispelColorMap }
            local ok = Try(b, "AddDispelTypeTexture", f.tex, o)
            if not ok then -- the map's entries as bare paths instead
                o.customDispelAssetMap = AssetMap(fx, false)
                ok = Try(b, "AddDispelTypeTexture", f.tex, o)
            end
            if ok then
                r.fxOk = r.fxOk + 1
                if not f.owned then
                    -- Start them once while they're still ours, then hand them over: the game
                    -- plays them whenever the debuff shows.
                    PlayFx(f, true)
                    for _, ag in ipairs(f.groups) do Try(b, "AddAuraShownAnimation", ag) end
                    f.owned = true
                end
            else
                f.tex:Hide()
            end
        else
            Try(b, "RemoveDispelTypeTexture", f.tex)
            f.tex:Hide()
        end
    end

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

-- Whether obj has a method (without noting it as missing).
local function Has(obj, method) return obj and type(obj[method]) == "function" end

local function IsFrame(v, c) return type(v) == "table" and v ~= c and type(v.GetObjectType) == "function" end

-- The aura button the container made for us, if there's one yet. A slot (AddAuraSlot) has
-- its button from the start; a group (AddAuraGroup, on clients without slots) may only make
-- it when a debuff first shows (initializeFrame then hands it to us).
local function FindButton(r)
    local c = r.container
    if r.kind == "slot" and Has(c, "GetAuraSlotFrame") then
        local ok, b = pcall(c.GetAuraSlotFrame, c, "debuff")
        if ok and IsFrame(b, c) then return b end
    elseif r.kind == "group" and Has(c, "GetAuraGroupFrame") then
        local ok, b = pcall(c.GetAuraGroupFrame, c, "debuff", 1)
        if ok and IsFrame(b, c) then return b end
    end
end

local function Container(unit)
    local r = live[unit]
    if r then return r end
    local _, unitFrame = Portrait(unit)
    if not unitFrame then return nil end
    -- The slot and group methods come from the container template (like the buttons'
    -- CustomAuraButtonTemplate); the bare frame type only knows its unit.
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, unitFrame, "CustomAuraContainerTemplate")
    if not ok or not c then
        Note("CustomAuraContainerTemplate: " .. tostring(c))
        ok, c = pcall(CreateFrame, "AuraContainer", nil, unitFrame)
    end
    if not ok or not c then Note("AuraContainer: " .. tostring(c)) return nil end
    NoMouse(c)
    Try(c, "SetUnit", unit)
    r = { container = c, unit = unit }
    live[unit] = r
    local opts = { initializeFrame = function(frame)
        -- A new button: dress it now if we may, else as soon as combat ends.
        if IsFrame(frame, c) and r.button ~= frame then
            r.button, r.dressed = frame, false
            applied[unit] = nil
        end
    end }
    if Has(c, "AddAuraSlot") then
        r.kind = "slot"
        local slotOk, b = Try(c, "AddAuraSlot", "debuff", FILTERS[unit].all, opts)
        if slotOk and IsFrame(b, c) then r.button = b end
    elseif Has(c, "AddAuraGroup") then
        r.kind = "group"
        local groupOk, b = Try(c, "AddAuraGroup", "debuff", FILTERS[unit].all, opts)
        if groupOk and IsFrame(b, c) then r.button = b end
        Try(c, "SetAuraGroupMaxFrameCount", "debuff", 1)
    else
        r.kind = "none"
        Note("container has neither AddAuraSlot nor AddAuraGroup")
    end
    r.button = r.button or FindButton(r)
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
        tostring(db.debuffOpacity), tostring(db.debuffPlayerFilter), tostring(db.debuffTargetFilter), tostring(db.debuffFx),
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
    local filter = FILTERS[unit][which] or "HARMFUL"
    local c = r.container
    if r.kind == "slot" then
        Try(c, "SetAuraSlotFilterString", "debuff", filter)
        if Has(c, "SetAuraSlotEnabled") then Try(c, "SetAuraSlotEnabled", "debuff", true) end
    elseif r.kind == "group" then
        if Has(c, "SetAuraGroupFilterString") then Try(c, "SetAuraGroupFilterString", "debuff", filter) end
        if Has(c, "SetAuraGroupEnabled") then Try(c, "SetAuraGroupEnabled", "debuff", true) end
        if Has(c, "SetAuraGroupMaxFrameCount") then Try(c, "SetAuraGroupMaxFrameCount", "debuff", 1) end
        -- One button the size of the ring, filling the container.
        if Has(c, "SetAuraGroupLayout") then
            Try(c, "SetAuraGroupLayout", "debuff", { elementWidth = outer * 2, elementHeight = outer * 2 })
        end
    end
    r.button = r.button or FindButton(r)
    Try(r.container, "SetEnabled", true)
    r.container:SetAlpha((db.debuffOpacity or 100) / 100)
    r.container:Show()
    if r.button then
        Try(r.button, "ClearAllPoints")
        Try(r.button, "SetAllPoints", r.container)
        DressButton(r, tex, outer)
        r.dressed = true
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
-- School layers: your own casts on the target (debuffSchoolFx)
---------------------------------------------------------------------------
-- The game's ring only knows a debuff's dispel type (Magic covers fire, frost, shadow...).
-- But the client does tell us what *you* cast, even in combat. So when you cast one of the
-- debuff spells below, the target's portrait gets a layer in that spell's school (flames,
-- ice, shadow, leaves, runes, light) for the spell's duration. It's a frame of our own over
-- the portrait (not part of the game's aura button), so we can time and animate it freely.
-- It can't see the debuff itself, so it's a best guess: a resisted spell still shows, one
-- dispelled early keeps showing until its time is up, and other players' spells don't show.
-- Kept per target (by GUID), so swapping back to a target brings its layer back.
-- Durations come from the spell's description ("... over 12 sec."), so every rank is right;
-- the numbers here are for when the description can't be read.
local SCHOOL_SPELLS = {
    fire   = { [8050] = 12, [348] = 15, [11366] = 12, [133] = 8 },        -- Flame Shock, Immolate, Pyroblast, Fireball
    frost  = { [8056] = 8, [116] = 7, [120] = 8, [122] = 8 },              -- Frost Shock, Frostbolt, Cone of Cold, Frost Nova
    shadow = { [589] = 18, [172] = 18, [18265] = 30, [5782] = 15, [689] = 5, [15286] = 60,
               [6789] = 3, [8122] = 8, [15407] = 3 },                      -- SW:Pain, Corruption, Siphon Life, Fear, Drain Life, VE, Death Coil, Scream, Mind Flay
    nature = { [8921] = 12, [5570] = 12, [339] = 15, [770] = 40 },         -- Moonfire, Insect Swarm, Entangling Roots, Faerie Fire
    arcane = { [118] = 20 },                                               -- Polymorph
    holy   = { [14914] = 10, [853] = 6 },                                  -- Holy Fire, Hammer of Justice
}
local SCHOOL_LAYERS = {
    fire   = { color = { 1.00, 0.45, 0.10 }, { art = "Glow", pulse = { 0.5, 1, 0.5 } },
               { art = "Flames", pulse = { 0.65, 1, 0.22 }, grow = { 0.97, 1.05, 0.35 } },
               { art = "Motes", rise = { 22, 1.2 } } },
    frost  = { color = { 0.55, 0.85, 1.00 }, { art = "Glow", pulse = { 0.4, 0.8, 1.6 } },
               { art = "Shards", turn = 45, pulse = { 0.6, 1, 1.3 } },
               { art = "Snow", drip = { 16, 2.6 } } },
    shadow = { color = { 0.60, 0.25, 0.90 }, { art = "Glow", pulse = { 0.3, 0.8, 1.4 } },
               { art = "CurseWisps", turn = -6, pulse = { 0.5, 1, 1.8 } },
               { art = "Motes", rise = { 14, 2.2 } } },
    nature = { color = { 0.35, 0.95, 0.35 }, { art = "Glow", pulse = { 0.4, 0.85, 1.5 } },
               { art = "Leaves", turn = 14, grow = { 0.97, 1.03, 1.8 } },
               { art = "Rise", rise = { 12, 2.4 } } },
    arcane = { color = { 0.85, 0.50, 1.00 }, { art = "Glow", pulse = { 0.4, 0.9, 1.0 } },
               { art = "MagicRunes", turn = -20, pulse = { 0.5, 1, 1.6 } },
               { art = "MagicStarsSmall", turn = 12, pulse = { 0.25, 1, 0.5 } } },
    holy   = { color = { 1.00, 0.90, 0.50 }, { art = "Glow", pulse = { 0.5, 1, 1.2 } },
               { art = "Rays", turn = 30, pulse = { 0.4, 1, 1.6 } },
               { art = "Motes", rise = { 16, 1.8 } } },
}
local SCHOOL_FADE = 0.6 -- seconds to fade out at the end

local schoolByID, schoolByName = {}, nil
for school, spells in pairs(SCHOOL_SPELLS) do
    for id, secs in pairs(spells) do schoolByID[id] = { school = school, secs = secs, id = id } end
end

-- The school and duration of one of your casts, or nil if it isn't one of these spells.
local function SchoolSpell(spellID)
    if not spellID then return nil end
    if schoolByID[spellID] then return schoolByID[spellID] end
    if not schoolByName then -- other ranks: by name
        local names, any = {}, false
        for _, info in pairs(schoolByID) do
            local n = ns.SpellName(info.id)
            if n then names[n], any = info, true end
        end
        if not any then return nil end
        schoolByName = names
    end
    local n = ns.SpellName(spellID)
    return n and schoolByName[n] or nil
end

local function SpellSeconds(spellID, fallback)
    local get = (C_Spell and C_Spell.GetSpellDescription) or _G.GetSpellDescription
    local text = ns.Clean(ns.SafeCall(get, spellID))
    if type(text) == "string" then
        local best
        for n in text:gmatch("(%d+%.?%d*) sec") do best = tonumber(n) end
        if best and best > 0 and best <= 120 then return best end
    end
    return fallback
end

local marks = {}   -- target GUID -> { school, until }
local schoolFx     -- the frame over the target portrait

local function SchoolFrame()
    if schoolFx then return schoolFx end
    local _, unitFrame = Portrait("target")
    if not unitFrame then return nil end
    -- On UIParent (not the target frame) so edit mode's sample shows without a target too;
    -- it's hidden whenever the target frame is.
    schoolFx = CreateFrame("Frame", nil, UIParent)
    schoolFx:SetFrameStrata(unitFrame:GetFrameStrata() or "MEDIUM")
    NoMouse(schoolFx)
    schoolFx.layers = {}
    for school, def in pairs(SCHOOL_LAYERS) do
        local list = {}
        for i, layer in ipairs(def) do
            local tex = schoolFx:CreateTexture(nil, "OVERLAY", nil, i)
            tex:SetPoint("CENTER")
            tex:SetTexture(TEXTURES .. "DebuffFx" .. layer.art)
            tex:SetVertexColor(def.color[1], def.color[2], def.color[3], 1)
            if tex.SetBlendMode then tex:SetBlendMode("ADD") end
            tex:Hide()
            table.insert(list, { tex = tex, groups = Animate(tex, layer) })
        end
        schoolFx.layers[school] = list
    end
    schoolFx:Hide()
    schoolFx.t = 0
    schoolFx:SetScript("OnUpdate", function(self, elapsed) -- the fade at the end, and running out
        self.t = self.t + elapsed
        if self.t < 0.05 then return end
        self.t = 0
        ns.UpdateDebuffSchool()
    end)
    return schoolFx
end

local function TargetGUID() return ns.Clean(ns.SafeCall(UnitGUID, "target")) end

-- Shows school's layers on the frame (nil: none), sized to the target ring.
local function ShowSchool(frame, school, alpha)
    if not frame then return end
    if not school then
        if frame.school then
            for _, l in ipairs(frame.layers[frame.school]) do l.tex:Hide(); PlayFx(l, false) end
            frame.school = nil
        end
        frame:Hide()
        return
    end
    if frame.school ~= school then
        ShowSchool(frame, nil)
        frame.school = school
        for _, l in ipairs(frame.layers[school]) do l.tex:Show(); PlayFx(l, true) end
    end
    local placed, _, outer = Place(frame, "target")
    if not placed then frame:Hide() return end
    frame:SetFrameLevel(frame:GetFrameLevel() + 2)
    for _, l in ipairs(frame.layers[school]) do l.tex:SetSize(outer * 2 * FX_SCALE, outer * 2 * FX_SCALE) end
    frame:SetAlpha(alpha * (db.debuffOpacity or 100) / 100)
    frame:Show()
end

local function SchoolOn()
    return db.debuffEnabled and db.debuffTarget ~= false and db.debuffSchoolFx
end

-- The current target's mark: its school and how much is left, or nil.
local function CurrentMark()
    local guid = TargetGUID()
    local m = guid and marks[guid]
    if not m then return nil end
    local left = m["until"] - GetTime()
    if left <= 0 then marks[guid] = nil return nil end
    return m.school, left
end

local sampleSchool -- edit mode / preview: the school the target's sample shows, or nil

local function UpdateSchool()
    if sampleSchool then
        ShowSchool(SchoolFrame(), sampleSchool, 1)
        return
    end
    local _, unitFrame = Portrait("target")
    if not SchoolOn() or not (unitFrame and unitFrame:IsVisible())
        or (UnitIsDead and ns.SafeCall(UnitIsDead, "target") == true) then
        if schoolFx then ShowSchool(schoolFx, nil) end
        return
    end
    local school, left = CurrentMark()
    if not school then
        if schoolFx then ShowSchool(schoolFx, nil) end
        return
    end
    ShowSchool(SchoolFrame(), school, math.min(1, left / SCHOOL_FADE))
end

ns.UpdateDebuffSchool = UpdateSchool

local function SetSampleSchool(school)
    if sampleSchool == school then return end
    sampleSchool = school
    UpdateSchool()
end

ns.Listen({ "UNIT_SPELLCAST_SUCCEEDED:player" }, function(_, _, _, spellID)
    if not SchoolOn() then return end
    local info = SchoolSpell(ns.CleanNumber(spellID))
    if not info then return end
    local guid = TargetGUID()
    if not guid then return end
    marks[guid] = { school = info.school, ["until"] = GetTime() + SpellSeconds(spellID, info.secs) }
    UpdateSchool()
end)
ns.Listen({ "PLAYER_TARGET_CHANGED", "UNIT_HEALTH:target" }, function() UpdateSchool() end)

-- Forget marks that have run out (or whose targets were left behind long ago).
local function SweepMarks()
    local now = GetTime()
    for guid, m in pairs(marks) do if m["until"] <= now then marks[guid] = nil end end
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
    FxTextures(s, s)
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
    SizeFx(s, outer)
    local typeName = SAMPLE_TYPE[kind] or "None"
    for _, f in pairs(s.fx) do
        local on = db.debuffFx and ForType(f.def, typeName)
        if on then
            f.tex:SetTexture(TEXTURES .. "DebuffFx" .. f.def.art)
            f.tex:SetVertexColor(c.r, c.g, c.b, 1)
            f.tex:Show()
        else
            f.tex:Hide()
        end
        PlayFx(f, on)
    end
    s.started, s.kind = GetTime(), kind
    s:Show()
    -- The target's magic sample also shows a school layer (fire), as your Flame Shock would.
    if unit == "target" then
        SetSampleSchool((db.debuffSchoolFx and kind == "magic") and "fire" or nil)
    end
end

local function HideSamples()
    for _, s in pairs(samples) do s:Hide() end
    SetSampleSchool(nil)
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
    SweepMarks()
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
            r and (r.button and (", " .. tostring(r.kind) .. " button") or (", no button yet (" .. tostring(r.kind) .. ")")) or "",
            r and r.button and ((r.colored and ", colored" or ", not colored") .. (r.drain and ", drains" or ", no drain")
                .. ", effects " .. tostring(r.fxOk or 0) .. "/" .. #FX) or ""))
    end
    -- Where things are: the container, its slot's button, the portrait. Calls on the button
    -- may throw (forbidden in combat) or answer with secrets; both are reported as such.
    local function Ask(obj, method, ...)
        if not (obj and obj[method]) then return "n/a" end
        local res = { pcall(obj[method], obj, ...) }
        if not res[1] then return "blocked" end
        local out = {}
        for i = 2, #res do
            local v = res[i]
            if ns.IsSecret(v) then out[#out + 1] = "secret"
            elseif type(v) == "number" then out[#out + 1] = string.format("%.0f", v)
            else out[#out + 1] = tostring(v) end
        end
        return table.concat(out, "x")
    end
    for _, unit in ipairs(UNITS) do
        local r = live[unit]
        local portrait, unitFrame = Portrait(unit)
        Print(string.format("  %s portrait: %s size %s, frame %s", unit, portrait and "found" or "MISSING",
            Ask(portrait, "GetSize"), unitFrame and (unitFrame:IsVisible() and "visible" or "hidden") or "MISSING"))
        if r then
            local c, b = r.container, r.button
            Print(string.format("    container: shown %s, visible %s, size %s, unit %s, level %s", Ask(c, "IsShown"),
                Ask(c, "IsVisible"), Ask(c, "GetSize"), Ask(c, "GetUnit"), Ask(c, "GetFrameLevel")))
            if b then
                Print(string.format("    slot button: shown %s, visible %s, size %s, points %s, parent is container %s",
                    Ask(b, "IsShown"), Ask(b, "IsVisible"), Ask(b, "GetSize"), Ask(b, "GetNumPoints"),
                    tostring(select(2, pcall(function() return b:GetParent() == c end)))))
            end
        end
    end
    local r = live.player or live.target
    if r then
        local names, seen, mt = {}, {}, getmetatable(r.container)
        local function Collect(t)
            for k, v in pairs(t) do
                if type(k) == "string" and type(v) == "function" and not seen[k]
                    and (k:find("Aura") or k:find("Unit") or k:find("Filter")) then
                    seen[k] = true; names[#names + 1] = k
                end
            end
        end
        pcall(Collect, r.container) -- methods mixed in by a template
        if mt and type(mt.__index) == "table" then pcall(Collect, mt.__index) end
        table.sort(names)
        Print("  container kind: " .. tostring(r.kind) .. "; its aura methods: " .. (#names > 0 and table.concat(names, ", ") or "(couldn't list)"))
    end
    if #diag == 0 then Print("  Nothing went wrong setting up.") end
    for _, m in ipairs(diag) do Print("  " .. m) end
end
ns.RegisterCommand({ "debuffdebug" }, DebuffDebug)

ns.PreviewDebuffRings = Preview
ns.DebuffRingsInfo = function() return live, samples, diag end -- tests
ns.DebuffSchoolFrame = function() return schoolFx, marks end -- tests
ns.DebuffAssetFor = function(kind, typeName) -- tests
    for _, fx in ipairs(FX) do if fx.kind == kind then return AssetMap(fx, false)[typeName] end end
end

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
        debuffFx        = true,  -- an animated effect per debuff type
        debuffSchoolFx  = false, -- your own spells' schools on the target (a best guess)
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
                        fx = Toggle(8, "debuffFx", "Effects per type",
                            "An animated effect for each type: bubbles round the ring for poison, swirling wisps for "
                            .. "curses, twinkling sparkles for magic, pulsing spores for disease, and blood running "
                            .. "down for bleeds and other debuffs with no type."),
                        school = Toggle(9, "debuffSchoolFx", "School effects from your casts",
                            "When you cast a debuff spell on your target, its portrait also gets that spell's school: "
                            .. "flames for Flame Shock or Immolate, ice for Frost Shock or Frostbolt, shadow for Shadow "
                            .. "Word: Pain or Corruption, leaves for Moonfire or Insect Swarm, runes for Polymorph, light "
                            .. "for Holy Fire, for as long as the spell lasts. A best guess: the game doesn't say which "
                            .. "debuff is which, so this goes by what you cast. A resisted spell still shows, one dispelled "
                            .. "early shows until its time would have run out, and other players' spells don't show."),
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
            for _, k in ipairs({ "player", "playerFilter", "target", "targetFilter", "drain", "time", "fx", "school" }) do
                tab.args.general.args[k].disabled = off
            end
            tab.args.general.args.playerFilter.disabled = function() return off() or db.debuffPlayer == false end
            tab.args.general.args.targetFilter.disabled = function() return off() or db.debuffTarget == false end
            tab.args.general.args.school.disabled = function() return off() or db.debuffTarget == false end
            return tab
        end },
})
