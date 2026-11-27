-- Circlet: Health rings: the pieces drawn on a ring: the inner band, badges, portrait and texts.
local ADDON_NAME, ns = ...

local db, SafeCall, Clean, CleanNumber = ns.db, ns.SafeCall, ns.Clean, ns.CleanNumber
local NewRingLayer, DrawArc, TRACK = ns.NewRingLayer, ns.DrawArc, ns.TRACK
local H = ns.HealthRings
local GLOW_TIME = H.GLOW_TIME
local FLASH_TIME = H.FLASH_TIME
local bigHitAt = H.bigHitAt
local NO_EVENTS = H.NO_EVENTS

---------------------------------------------------------------- drawing: the inner band and text
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a soft-edged white disc
-- The elite marker's wing (the left one; the right is it flipped): Textures/EliteWing.tga,
-- made by tools/make_wing_texture.py. Light grey, tinted gold or silver.
local WING = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\EliteWing"

local function Parts(frame)
    if frame.vit then return frame.vit end
    local v = {}
    v.border = NewRingLayer("BACKGROUND", -8, { r = 0, g = 0, b = 0 }, 0.9, frame)
    v.track = NewRingLayer("BACKGROUND", 0, TRACK, 1, frame)
    v.fill = NewRingLayer("ARTWORK", 0, { r = 1, g = 1, b = 1 }, 1, frame)
    -- Transition layers, for the health band (h) and the power band (p): the trail beside the
    -- fill and the soft glow over it.
    v.eh, v.ep = {}, {} -- eased bands' bars (health, power)
    local white = { r = 1, g = 1, b = 1 }
    for _, b in ipairs({ "h", "p" }) do
        v[b] = { trail = NewRingLayer("ARTWORK", -1, white, 1, frame), glow = NewRingLayer("ARTWORK", 2, white, 1, frame),
                 flash = NewRingLayer("ARTWORK", 3, white, 1, frame) }
    end
    local function Text(layer)
        local fs = frame:CreateFontString(nil, layer or "OVERLAY")
        fs:SetShadowOffset(1, -1)
        fs:SetJustifyH("CENTER")
        return fs
    end
    v.hp, v.hp2, v.pw, v.name = Text(), Text(), Text(), Text()
    v.g2 = {}
    -- The unit's portrait, clipped to a circle, filling the middle behind the text.
    v.portrait = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    v.portrait:SetPoint("CENTER")
    if frame.CreateMaskTexture then
        v.mask = frame:CreateMaskTexture()
        v.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        v.mask:SetPoint("CENTER")
        v.portrait:AddMaskTexture(v.mask)
    end
    v.portrait:Hide()
    -- Badges on the band: the level (bottom left) and the in-combat swords (top right). On a
    -- child frame, so they sit over the bands and the texts.
    local bf = CreateFrame("Frame", nil, frame)
    bf:SetAllPoints(frame)
    bf:SetFrameLevel(frame:GetFrameLevel() + 5)
    local function Badge()
        local bd = { parent = bf }
        bd.edge = bf:CreateTexture(nil, "BACKGROUND")
        bd.edge:SetTexture(DISC)
        bd.edge:SetVertexColor(0, 0, 0, 0.9)
        bd.fill = bf:CreateTexture(nil, "ARTWORK")
        bd.fill:SetTexture(DISC)
        bd.edge:Hide(); bd.fill:Hide()
        return bd
    end
    v.lvl = Badge()
    v.lvl.fill:SetVertexColor(0.11, 0.08, 0.10, 1)
    -- Its outline: a gold rim between the dark edge and the fill.
    v.lvl.rim = bf:CreateTexture(nil, "BORDER")
    v.lvl.rim:SetTexture(DISC)
    v.lvl.rim:SetVertexColor(0.85, 0.66, 0.28, 1)
    v.lvl.rim:Hide()
    v.lvl.text = bf:CreateFontString(nil, "OVERLAY")
    v.lvl.text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE") -- a font before any SetText (sized when drawn)
    v.lvl.text:SetShadowOffset(1, -1)
    v.lvl.text:SetJustifyH("CENTER")
    v.lvl.text:SetPoint("CENTER", v.lvl.fill, "CENTER", 0.5, 0)
    -- Elite marker: the game's own target-frame dragon behind the badge (or, if this client
    -- lacks that art, our wings).
    v.lvl.dragon = bf:CreateTexture(nil, "BACKGROUND", nil, -3)
    v.lvl.dragon:Hide()
    v.lvl.wingL = bf:CreateTexture(nil, "BACKGROUND", nil, -2)
    v.lvl.wingL:SetTexture(WING)
    v.lvl.wingR = bf:CreateTexture(nil, "BACKGROUND", nil, -2)
    v.lvl.wingR:SetTexture(WING)
    v.lvl.wingR:SetTexCoord(1, 0, 0, 1) -- flipped
    v.lvl.wingL:Hide(); v.lvl.wingR:Hide()
    v.cmb = Badge()
    v.cmb.fill:SetVertexColor(0.32, 0.05, 0.04, 1)
    v.cmb.icon = bf:CreateTexture(nil, "OVERLAY")
    v.cmb.icon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    v.cmb.icon:SetTexCoord(0.5, 1, 0, 0.5) -- the crossed swords
    v.cmb.icon:SetPoint("CENTER", v.cmb.fill, "CENTER")
    v.cmb.icon:Hide()
    frame.vit = v
    return v
end

-- A badge's disc, centered on the band at <deg> degrees (0 = right, counter-clockwise).
local function PlaceBadge(bd, R, deg, d)
    local k = R .. ":" .. deg .. ":" .. d
    if bd.k ~= k then
        bd.k = k
        local a = math.rad(deg)
        local x, y = R * math.cos(a), R * math.sin(a)
        bd.x, bd.y, bd.d = x, y, d
        bd.edge:ClearAllPoints(); bd.edge:SetPoint("CENTER", bd.parent, "CENTER", x, y); bd.edge:SetSize(d, d)
        local inset = 3
        if bd.rim then
            -- Outline: about a tenth of the disc, at least 2 px, inside a 1 px dark edge.
            local w = math.max(2, math.floor(d * 0.1 + 0.5))
            bd.rim:ClearAllPoints(); bd.rim:SetPoint("CENTER", bd.parent, "CENTER", x, y); bd.rim:SetSize(d - 2, d - 2)
            inset = 2 + 2 * w
        end
        bd.fill:ClearAllPoints(); bd.fill:SetPoint("CENTER", bd.parent, "CENTER", x, y); bd.fill:SetSize(d - inset, d - inset)
    end
    bd.edge:Show(); bd.fill:Show()
    if bd.rim then bd.rim:Show() end
end
local function HideBadge(bd)
    bd.edge:Hide(); bd.fill:Hide()
    if bd.rim then bd.rim:Hide() end
    if bd.wingL then bd.wingL:Hide(); bd.wingR:Hide() end
    if bd.dragon then bd.dragon:Hide() end
    if bd.text then bd.text:SetText("") end
    if bd.icon then bd.icon:Hide() end
end

-- Where each ring's level badge sits (degrees, 0 = right, counter-clockwise): bottom left on
-- yours, bottom right on the target's (the side away from yours).
-- Where the badges sit: each ring's choice (Rings/Health/Fx/Pieces.lua, ns.VitalsBadges).
local Badges = ns.VitalsBadges

-- The elite marker (<key>Elite) on the level badge: the game's own target-frame dragon
-- round it, the art TargetFrame uses for that classification: the gold dragon for elites
-- and world bosses, the silver one for rare elites, and the silver frame (no wings) for
-- rares. Previews show the gold one.
--
-- The art is TargetFrame's whole frame (256x128, drawn a pixel a texel); we cut out the
-- dragon round its portrait. From TargetFrame.xml: the 64 px portrait sits at TOPRIGHT
-- -24,-16 of the 232x100 frame, and the frame art at CENTER +18.5,-4, 230x99, texcoords
-- 0.1015625..1 x 0.0078125..0.78125. So the portrait's center is texel (182.5, 44.5). We
-- draw texels 142..256 x 0..100 (the dragon, not the bars to its left), scaled so the
-- portrait is the badge, its center on the badge's.
local ELITE = { elite = "gold", worldboss = "gold", rareelite = "silver", rare = "silver" }
local DRAGON_ART = {
    elite = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
    worldboss = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
    rareelite = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
    rare = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
}
local ART_W, ART_H = 256, 128
local PU, PV, PD = 182.5, 44.5, 64          -- the portrait's center and size, in texels
local U0, U1, V0, V1 = 142, 256, 0, 100     -- the piece we draw
local WING_COLORS = { gold = { 1, 0.80, 0.32 }, silver = { 0.85, 0.88, 0.95 } }
-- The badge's colors (rim, outline, inside): plain, or, with a dragon round it, taken from
-- the dragon's own art (its gold or steel, and the dark of its shading) so the two read as
-- one piece rather than a black-edged disc sat on the dragon.
local BADGE_LOOK = {
    plain  = { rim = { 0.85, 0.66, 0.28 }, edge = { 0, 0, 0, 0.9 },          fill = { 0.11, 0.08, 0.10 } },
    gold   = { rim = { 0.96, 0.72, 0.22 }, edge = { 0.24, 0.13, 0.03, 0.85 }, fill = { 0.17, 0.10, 0.04 } },
    silver = { rim = { 0.80, 0.83, 0.88 }, edge = { 0.13, 0.13, 0.16, 0.85 }, fill = { 0.11, 0.11, 0.14 } },
}

local function BadgeLook(bd, look)
    if bd.look == look then return end
    bd.look = look
    local c = BADGE_LOOK[look]
    bd.rim:SetVertexColor(c.rim[1], c.rim[2], c.rim[3], 1)
    bd.edge:SetVertexColor(c.edge[1], c.edge[2], c.edge[3], c.edge[4])
    bd.fill:SetVertexColor(c.fill[1], c.fill[2], c.fill[3], 1)
end

-- The game's dragon round the badge; false if this client hasn't the art.
local function DrawDragon(bd, class)
    local t = bd.dragon
    local file = DRAGON_ART[class]
    if bd.dragonFile ~= file then
        bd.dragonFile = file
        bd.dragonOK = t:SetTexture(file) ~= false
        t:SetTexCoord(U0 / ART_W, U1 / ART_W, V0 / ART_H, V1 / ART_H)
    end
    if not bd.dragonOK then t:Hide() return false end
    local k = bd.d / PD
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", bd.parent, "CENTER", bd.x - (PU - U0) * k, bd.y + (PV - V0) * k)
    t:SetSize((U1 - U0) * k, (V1 - V0) * k)
    t:Show()
    return true
end

local function DrawElite(key, bd, st)
    local class
    if db[key .. "Elite"] then
        if st.unit then
            class = Clean(SafeCall(UnitClassification, st.unit))
        elseif key ~= "playerHp" then
            class = "elite" -- the preview's sample
        end
    end
    local kind = ELITE[class or ""]
    BadgeLook(bd, kind or "plain")
    if not kind or not bd.x then bd.dragon:Hide(); bd.wingL:Hide(); bd.wingR:Hide() return end
    if DrawDragon(bd, class) then bd.wingL:Hide(); bd.wingR:Hide() return end
    -- No dragon art on this client: our wings (rares, like the game, get none).
    if class == "rare" then bd.wingL:Hide(); bd.wingR:Hide() return end
    local d, c = bd.d, WING_COLORS[kind]
    local w = d * 1.05
    -- Each wing's root (its inner bottom corner) tucked behind the disc's upper side.
    bd.wingL:ClearAllPoints()
    bd.wingL:SetPoint("BOTTOMRIGHT", bd.parent, "CENTER", bd.x - d * 0.18, bd.y - d * 0.02)
    bd.wingR:ClearAllPoints()
    bd.wingR:SetPoint("BOTTOMLEFT", bd.parent, "CENTER", bd.x + d * 0.18, bd.y - d * 0.02)
    for _, t in ipairs({ bd.wingL, bd.wingR }) do
        t:SetSize(w, w)
        t:SetVertexColor(c[1], c[2], c[3], 1)
        t:Show()
    end
end

-- The level badge (<key>Level): the unit's level on a disc at the bottom of the ring;
-- others' levels in the game's difficulty colors, "??" for ones too high to tell.
local function DrawLevel(key, v, st, geom, d)
    if not db[key .. "Level"] then HideBadge(v.lvl) return end
    local unit = st.unit or "player"
    local level = st.level or CleanNumber(SafeCall(UnitLevel, unit))
    if not st.unit and key ~= "playerHp" then level = st.level or 18 end
    if not level then HideBadge(v.lvl) return end
    d = math.floor(d * 1.4 + 0.5) -- bigger than the combat badge: it carries text
    PlaceBadge(v.lvl, geom.R, Badges.Angle(key, "Level"), d)
    local fk = d .. ":" .. ((tonumber(db[key .. "LevelTextSize"]) or 100))
    if v.lvl.fk ~= fk then
        v.lvl.fk = fk
        local size = math.max(6, math.floor(d * 0.5 * (tonumber(db[key .. "LevelTextSize"]) or 100) / 100 + 0.5))
        v.lvl.text:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    end
    local r, g, b = 1, 0.82, 0.25
    -- Colored the way the game's target frame and nameplates color it: the creature difficulty
    -- colors (the quest ones call anything within a few levels yellow), by its effective level.
    -- Friendly units: plain yellow (difficulty only matters for what you can fight).
    local Difficulty = GetCreatureDifficultyColor or GetQuestDifficultyColor
    local friend = st.unit and Clean(SafeCall(UnitIsFriend, "player", st.unit))
    if friend then
        r, g, b = 1, 0.82, 0
    elseif key ~= "playerHp" and st.unit and Difficulty then
        local eff = UnitEffectiveLevel and CleanNumber(SafeCall(UnitEffectiveLevel, st.unit)) or level
        local ok, c = pcall(Difficulty, (eff and eff > 0) and eff or 999)
        if ok and type(c) == "table" and c.r then r, g, b = c.r, c.g, c.b end
    end
    v.lvl.text:SetTextColor(r, g, b)
    v.lvl.text:SetText(level > 0 and tostring(level) or "??")
    DrawElite(key, v.lvl, st)
end

-- The in-combat badge (<key>Combat, your ring): crossed swords at the top right while you're
-- in combat, gently pulsing. Edit mode and previews show it so it can be placed.
local function DrawCombat(key, v, st, geom, d, now)
    local on = db[key .. "CombatIcon"]
    if on and st.unit then on = Clean(SafeCall(UnitAffectingCombat, st.unit)) and true or false end
    if not on then HideBadge(v.cmb) return end
    PlaceBadge(v.cmb, geom.R, Badges.Angle(key, "Combat"), d)
    v.cmb.icon:SetSize(d * 0.8, d * 0.8)
    v.cmb.icon:Show()
    local a = 0.8 + 0.2 * math.sin(now * 4)
    v.cmb.fill:SetAlpha(a)
    v.cmb.icon:SetAlpha(a)
end

-- Portraits to redraw (by ring key): when the target or a portrait changes.
local portraitDirty = {}

local function DrawPortrait(key, v, unit, room)
    if not db[key .. "Portrait"] or not SetPortraitTexture then v.portrait:Hide() return end
    local size = math.max(8, room - 2)
    v.portrait:SetSize(size, size)
    if v.mask then v.mask:SetSize(size, size) end
    if NO_EVENTS[unit] and GetTime() - (v.portraitAt or 0) > 1 then portraitDirty[key] = true end
    if portraitDirty[key] or v.portraitUnit ~= unit then
        v.portraitAt = GetTime()
        portraitDirty[key] = nil
        v.portraitUnit = unit
        pcall(SetPortraitTexture, v.portrait, unit)
    end
    v.portrait:SetAlpha((tonumber(db[key .. "PortraitAlpha"]) or 70) / 100)
    -- Grey for a mob someone else tagged (the Tapped effect).
    local grey = db[key .. "FxTapped"] and unit ~= "player" and Clean(SafeCall(UnitIsTapDenied, unit)) and true or false
    if v.portrait.grey ~= grey then v.portrait.grey = grey; pcall(v.portrait.SetDesaturated, v.portrait, grey) end
    v.portrait:Show()
end

-- Lays out the texts: the name on top, the health in the middle (with <key>SplitText and
-- "Value and percent", the number on one line and the percentage on a second, smaller one
-- under it), the power under those.
local function PlaceTexts(v, frame, room, split)
    v.hp:ClearAllPoints()
    v.hp2:ClearAllPoints()
    v.pw:ClearAllPoints()
    v.name:ClearAllPoints()
    if split then
        v.hp:SetPoint("CENTER", frame, "CENTER", 0, room * 0.09)
        v.hp2:SetPoint("TOP", v.hp, "BOTTOM", 0, -1)
        v.pw:SetPoint("TOP", v.hp2, "BOTTOM", 0, -1)
    else
        v.hp:SetPoint("CENTER", frame, "CENTER", 0, room * 0.02)
        v.pw:SetPoint("TOP", v.hp, "BOTTOM", 0, -1)
    end
    v.name:SetPoint("BOTTOM", v.hp, "TOP", 0, 1)
end

local function HideLayer(lines) for _, l in ipairs(lines) do l:Hide() end end

local function Whiten(c, k) return c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k end

-- One band's transitions (readable values only). L: its layers; tr: its track; c: its color;
-- trailColor: { r, g, b }.
local function Effects(key, L, tr, g, frame, c, now, trailColor)
    local readable = tr and not tr.hidden and tr.shown ~= nil
    -- The trail behind a loss: holds, then drains after the fill.
    if readable and db[key .. "Trail"] and tr.trailTop and tr.trailTop > tr.shown then
        for _, l in ipairs(L.trail) do l:SetColorTexture(trailColor.r, trailColor.g, trailColor.b, 0.85) end
        DrawArc(L.trail, tr.shown, tr.trailTop, frame, g)
    else
        HideLayer(L.trail)
    end
    -- A gain: the new part glows a little lighter as it fills in, fading out gently.
    if readable and db[key .. "Trail"] and tr.glowAt and now - tr.glowAt < GLOW_TIME then
        local k = 1 - (now - tr.glowAt) / GLOW_TIME
        local to = math.min(tr.glowTo, tr.shown)
        if to > tr.glowFrom + 0.002 then
            local r, gg, b = Whiten(c, 0.4)
            for _, l in ipairs(L.glow) do l:SetColorTexture(r, gg, b, 0.4 * k * k) end
            DrawArc(L.glow, tr.glowFrom, to, frame, g, true)
        else
            HideLayer(L.glow)
        end
    else
        HideLayer(L.glow)
    end
end

-- A big hit: the whole health band flashes red, fading out fast (FLASH_TIME).
local function BigHitFlash(key, L, g, frame, now)
    local at = bigHitAt[key]
    if db[key .. "BigHit"] and at and now - at < FLASH_TIME then
        local k = 1 - (now - at) / FLASH_TIME
        for _, l in ipairs(L.flash) do l:SetColorTexture(1, 0.3, 0.25, 0.55 * k * k) end
        DrawArc(L.flash, 0, 1, frame, g, true)
    else
        HideLayer(L.flash)
    end
end

local HEALTH_TRAIL = { r = 1, g = 0.32, b = 0.25 }

-- Puts text on a font string; hidden values go through SetText / SetFormattedText (which
-- accept them), and if even that's refused, nothing shows.
local function Put(fs, fmt, ...)
    if fmt then
        if not pcall(fs.SetFormattedText, fs, fmt, ...) then fs:SetText("") end
    else
        if not pcall(fs.SetText, fs, (...)) then fs:SetText("") end
    end
end

-- Health text on fs; split: the number on fs and the percentage on fs2 ("Value and
-- percent" only).
local function HealthText(key, st, fs, fs2, split)
    local mode = db[key .. "Text"]
    fs2:SetText("")
    if mode == "none" then fs:SetText("") return end
    if st.dead then fs:SetText(st.dead) return end
    if st.hpText then
        local t = st.hpText
        if mode == "value" then fs:SetText(t.value)
        elseif mode == "both" and split then fs:SetText(t.value); fs2:SetText(t.pct)
        elseif mode == "both" then fs:SetText(t.value .. "  |cffcccccc" .. t.pct .. "|r")
        else fs:SetText(t.pct) end
        return
    end
    local h = st.hpHidden or {}
    if mode == "value" or (mode == "both" and h.pct == nil) then
        if h.value ~= nil then Put(fs, nil, h.value) else fs:SetText("") end
    elseif mode == "both" and split then
        if h.value ~= nil then Put(fs, nil, h.value) else fs:SetText("") end
        Put(fs2, "%d%%", h.pct)
    elseif mode == "both" then
        Put(fs, "%s  |cffcccccc%d%%|r", h.value, h.pct)
    elseif h.pct ~= nil then
        Put(fs, "%d%%", h.pct)
    else
        fs:SetText("")
    end
end

local function PowerText(key, p, fs)
    if not (p and db[key .. "PowerText"]) then fs:SetText("") return end
    local c = p.color
    fs:SetTextColor(c.r + (1 - c.r) * 0.35, c.g + (1 - c.g) * 0.35, c.b + (1 - c.b) * 0.35)
    if p.text then fs:SetText(p.text) return end
    local h = p.hidden or {}
    if h.pct ~= nil then Put(fs, "%d%%", h.pct)
    elseif h.value ~= nil then Put(fs, nil, h.value)
    else fs:SetText("") end
end

-- For the files loaded after this one.
H.Parts = Parts
H.HideBadge = HideBadge
H.DrawLevel = DrawLevel
H.DrawCombat = DrawCombat
H.DrawPortrait = DrawPortrait
H.PlaceTexts = PlaceTexts
H.HideLayer = HideLayer
H.Whiten = Whiten
H.Effects = Effects
H.BigHitFlash = BigHitFlash
H.HEALTH_TRAIL = HEALTH_TRAIL
H.Put = Put
H.HealthText = HealthText
H.PowerText = PowerText
H.portraitDirty = portraitDirty
H.Badges = Badges
