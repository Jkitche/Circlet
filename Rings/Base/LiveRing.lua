-- Circlet: a ring that shows something live (a countdown, a distance) for as long
-- as it lasts, rather than popping up for a gain. Used by the timed quest and corpse rings.
local ADDON_NAME, ns = ...

local db, NewRingLayer, DrawArc = ns.db, ns.NewRingLayer, ns.DrawArc
local EDIT_STRATA = ns.EDIT_STRATA

-- Lost-progress flash: blinks between the track and white FLASH_BLINKS times over
-- FLASH_TIME seconds, each blink fainter than the last.
local FLASH_TIME, FLASH_BLINKS = 1.4, 3
-- Finish burst: the icon swells and settles (POP_TIME), a glow flashes behind it and
-- BURST_SPARKS sparks fly out from its edge, all gone by BURST_TIME. Each burst is turned
-- to a random angle, and each spark strays a little in direction, reach and size, so no
-- two look quite the same.
local POP_TIME, BURST_TIME, BURST_SPARKS = 0.35, 0.7, 8
local OPAQUE_TIME = 0.15 -- a dimmed background icon reaches full opacity this fast
local MAX_NOTCHES = 60  -- a state's notches beyond this fall back to the usual 24
local LINES = 2 * 72    -- enough segments for MAX_NOTCHES notches (2 per notch past 36)

-- cfg.key: settings prefix (<key>Size, <key>X, ...).
-- cfg.read(now): returns the state to draw, or nil when there's nothing to show.
--   state = { title, value, label, frac, color, labelColor, marker, icon, iconColor }
--   frac: 0..1 fill (nil = no fill); marker: angle in radians for a dot on the ring
--   (0 = top, clockwise), or nil. icon: a texture for a round badge on the ring's top
--   edge (bordered in iconColor, or the ring color).
--   notches: with the segmented style, split the ring into this many notches (one per
--   item being crafted, say) instead of the usual 24.
--   doneAt: GetTime() when the thing finished (a craft, gather, cast): from then on the
--   icon is fully opaque (even as a dimmed background), and it pops with a burst of glow
--   and sparks (unless noBurst: the cast ring's spells, which only turn opaque).
--   flashFrom / flashTo / flashAt: a stretch of the ring (fractions) that flashes white
--   and fades out, starting at GetTime() == flashAt: progress that was just lost.
--   noTrack: draw none of the ring itself (track, border, fill): for a ring whose content
--   is drawn by the game (the totem rings' fallback), so nothing of it shows on its own.
-- cfg.sample(t): the same for edit mode / previews (t = seconds since it started).
-- cfg.watchEvery: seconds between checks while hidden (default 0.25).
-- cfg.decorate(st, frame, geom): optional, called every frame once the ring is laid out (st is nil when there's
-- nothing to draw) so a ring can add effects of its own (the cast ring's resurrection).
-- cfg.centerIcon: draw the state's icon filling the middle of the ring (small rings).
-- <key>IconBg (rings registered with iconBg): the icon fills the ring's middle behind its
-- text, at <key>IconBgAlpha % opacity, instead of sitting on the top edge.
-- cfg.valueScale: size of the middle text relative to the ring's inside (default 0.25).
-- cfg.onRightClick(frame): if set, right-clicking the ring (outside edit mode) calls it;
-- left clicks still pass through to the game world. cfg.menuEnabled(): optional, turns
-- that off when it returns false. cfg.locked(): optional, when true the ring can't be
-- dragged or reset in edit mode.
local function CreateLiveRing(cfg)
    local key = cfg.key
    local function opt(name) return db[key .. name] end

    -- Extra segments so a ring can be split into up to MAX_NOTCHES notches.
    local frame = ns.NewRingFrame(key, LINES)
    local geom = frame.geom

    -- Right-click menu (outside edit mode, where right-click resets the position).
    local editMouseUp = frame:GetScript("OnMouseUp")
    local function SetClickMode(editingNow)
        if not cfg.onRightClick or (not editingNow and cfg.menuEnabled and not cfg.menuEnabled()) then
            frame:EnableMouse(editingNow)
            return
        end
        frame:EnableMouse(true)
        if frame.SetPassThroughButtons then
            if editingNow then frame:SetPassThroughButtons() else frame:SetPassThroughButtons("LeftButton") end
        end
    end
    if cfg.onRightClick then
        frame:SetScript("OnMouseUp", function(self, button)
            if self.isEditing then
                if editMouseUp then editMouseUp(self, button) end
            elseif button == "RightButton" then
                cfg.onRightClick(self)
            end
        end)
        SetClickMode(false)
    end
    frame.isLocked = cfg.locked

    frame.fill = NewRingLayer("ARTWORK", 0, { r = 1, g = 1, b = 1 }, 1, frame, LINES)
    frame.flash = NewRingLayer("ARTWORK", 1, { r = 1, g = 1, b = 1 }, 1, frame, LINES)

    local function Text()
        local fs = frame:CreateFontString(nil, "OVERLAY")
        fs:SetShadowOffset(1, -1)
        return fs
    end
    frame.title = Text()
    frame.value = Text()
    frame.label = Text()

    -- An arrow that rides the ring, pointing outward (the corpse ring's direction
    -- marker): the minimap's player arrow, or a plain dot if this client lacks it.
    frame.marker = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.markerIsArrow = frame.marker:SetTexture("Interface\\Minimap\\MinimapArrow") ~= false
    if not frame.markerIsArrow then frame.marker:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    frame.marker:Hide()
    -- A soft glow behind it in the same color, fading out from the middle, so it stands
    -- out against the ring.
    frame.markerGlow = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    if frame.markerGlow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64") == false then
        frame.markerGlow:SetTexture("Interface\\Cooldown\\star4")
    end
    frame.markerGlow:SetBlendMode("ADD")
    frame.markerGlow:SetAlpha(0.75)
    frame.markerGlow:Hide()

    -- Badge: an icon clipped to a circle on the ring's top edge, with a colored rim (a
    -- slightly larger disc behind it), like the reputation and skill rings' badges.
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    local badge = CreateFrame("Frame", nil, frame)
    badge:SetSize(1, 1)
    badge:Hide()
    badge.rim = badge:CreateTexture(nil, "BORDER")
    badge.rim:SetPoint("CENTER")
    badge.tex = badge:CreateTexture(nil, "ARTWORK")
    badge.tex:SetPoint("CENTER")
    badge.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's built-in border
    if badge.CreateMaskTexture then
        badge.mask = badge:CreateMaskTexture()
        badge.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        badge.mask:SetPoint("CENTER")
        badge.tex:AddMaskTexture(badge.mask)
        badge.rimMask = badge:CreateMaskTexture()
        badge.rimMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        badge.rimMask:SetPoint("CENTER")
        badge.rim:AddMaskTexture(badge.rimMask)
        -- A black outline round the badge, the ring's border width (behind the rim).
        badge.outline = badge:CreateTexture(nil, "BORDER", nil, -2)
        badge.outline:SetPoint("CENTER")
        badge.outline:SetColorTexture(0, 0, 0, 0.9)
        badge.outlineMask = badge:CreateMaskTexture()
        badge.outlineMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        badge.outlineMask:SetPoint("CENTER")
        badge.outline:AddMaskTexture(badge.outlineMask)
    end

    -- Finish burst: a glow behind the icon and sparks around it (made on first use).
    local function BurstParts()
        if badge.burstGlow then return end
        badge.burstGlow = badge:CreateTexture(nil, "BACKGROUND", nil, -8)
        if badge.burstGlow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64") == false then
            badge.burstGlow:SetTexture("Interface\\Cooldown\\star4")
        end
        badge.burstGlow:SetBlendMode("ADD")
        badge.burstGlow:SetPoint("CENTER")
        badge.sparks = {}
        for i = 1, BURST_SPARKS do
            local t = badge:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetTexture("Interface\\Cooldown\\star4")
            t:SetBlendMode("ADD")
            t:Hide()
            badge.sparks[i] = t
        end
    end

    local function HideBurst()
        if not badge.burstGlow then return end
        badge.burstGlow:Hide()
        for _, t in ipairs(badge.sparks) do t:Hide() end
    end

    -- A new burst's random turn and per-spark variation, picked once (stable while it plays).
    local function RollBurst(at)
        if badge.burstFor == at then return end
        badge.burstFor = at
        local spread = 2 * math.pi / BURST_SPARKS
        badge.burstTurn = math.random() * spread -- the whole ring of sparks
        badge.burstVary = badge.burstVary or {}
        for i = 1, BURST_SPARKS do
            badge.burstVary[i] = {
                angle = (math.random() - 0.5) * spread * 0.5, -- up to a quarter of the gap either way
                reach = 0.75 + math.random() * 0.5,
                size  = 0.8 + math.random() * 0.4,
            }
        end
    end

    -- The burst at `age` seconds after finishing, round an icon `size` across, in color c.
    local function DrawBurst(age, size, c, at)
        BurstParts()
        RollBurst(at)
        local t = age / BURST_TIME
        local gs = size * (1.3 + 0.9 * (1 - (1 - math.min(1, t * 2)) ^ 2))
        badge.burstGlow:SetSize(gs, gs)
        badge.burstGlow:SetVertexColor(c.r, c.g, c.b)
        badge.burstGlow:SetAlpha(0.9 * (1 - t))
        badge.burstGlow:Show()
        local r, g, b = c.r + (1 - c.r) * 0.5, c.g + (1 - c.g) * 0.5, c.b + (1 - c.b) * 0.5
        for i, s in ipairs(badge.sparks) do
            local v = badge.burstVary[i]
            local a = (i / BURST_SPARKS) * 2 * math.pi + badge.burstTurn + v.angle
            local d = size / 2 + size * 0.65 * v.reach * (1 - (1 - t) ^ 2)
            local ss = size * 0.32 * v.size * (1 - 0.6 * t)
            s:ClearAllPoints()
            s:SetPoint("CENTER", badge, "CENTER", math.sin(a) * d, math.cos(a) * d)
            s:SetSize(ss, ss)
            s:SetVertexColor(r, g, b)
            s:SetAlpha(1 - t)
            s:Show()
        end
    end

    local function DrawBadge(st)
        if not st.icon then
            badge:Hide()
            return
        end
        -- Finished: how long ago (nil while it's still going).
        local doneAge = st.doneAt and GetTime() - st.doneAt
        if doneAge and doneAge < 0 then doneAge = nil end
        badge:SetFrameLevel(frame:GetFrameLevel() + 3)
        local size = math.max(20, opt("Size") * 0.28)
        local rimT = math.max(2, size * 0.1)
        badge:ClearAllPoints()
        local bg = not cfg.centerIcon and opt("IconBg")
        if bg then
            -- Background: fills the hollow, one level below the ring so its text draws on top.
            size = math.max(8, (geom.R - geom.T / 2) * 2 - 2 - 2 * ns.BorderWidthOf(key))
            rimT = 0
            if frame:GetFrameLevel() < 2 then frame:SetFrameLevel(2) end
            badge:SetFrameLevel(frame:GetFrameLevel() - 1)
            badge:SetPoint("CENTER", frame, "CENTER", 0, 0)
        elseif cfg.centerIcon then
            -- Small rings: the icon fills the middle instead of sitting on the edge.
            size = math.max(8, (geom.R - geom.T / 2) * 2 - 2 - 2 * ns.BorderWidthOf(key))
            rimT = 0
            badge:SetFrameLevel(frame:GetFrameLevel())
            badge:SetPoint("CENTER", frame, "CENTER", 0, 0)
        else
            badge:SetPoint("CENTER", frame, "CENTER", 0, geom.R + geom.T / 2 + size * 0.2)
        end
        local iconSize = size
        if doneAge and doneAge < POP_TIME and not st.noBurst then
            size = size * (1 + 0.22 * math.sin(math.pi * doneAge / POP_TIME)) -- swell and settle
        end
        badge.tex:SetTexture(st.icon)
        badge.tex:SetSize(size, size)
        if badge.mask then badge.mask:SetSize(size, size) end
        local d = size + 2 * rimT
        badge.rim:SetSize(d, d)
        if badge.rimMask then badge.rimMask:SetSize(d, d) end
        local c = st.iconColor or st.color
        badge.rim:SetColorTexture(c.r, c.g, c.b, rimT > 0 and 1 or 0)
        if badge.outline then
            local b = ns.BorderWidthOf(key)
            local od = d + 2 * b
            badge.outline:SetSize(od, od)
            badge.outlineMask:SetSize(od, od)
            badge.outline:SetShown(b > 0 and not bg)
        end
        local alpha = st.iconAlpha or 1
        if bg then
            local dim = (opt("IconBgAlpha") or 40) / 100
            local lit = doneAge and math.min(1, doneAge / OPAQUE_TIME) or 0 -- finished: fully opaque
            alpha = alpha * (dim + (1 - dim) * lit)
        end
        badge.tex:SetAlpha(alpha)
        if doneAge and doneAge < BURST_TIME and not st.noBurst then
            DrawBurst(doneAge, iconSize, st.iconColor or st.color, st.doneAt)
        else
            HideBurst()
        end
        badge:Show()
    end

    local editing, previewUntil, sampleT, holdUntil = false, 0, 0, 0
    local last -- last real state, shown while fading out

    local function Layout(st)
        local notches = st and st.notches
        if notches and (notches < 1 or notches > MAX_NOTCHES) then notches = nil end
        local size = opt("Size")
        ns.PlaceRing(frame, key, size)
        if notches ~= geom.notches then frame.layoutKey = nil end -- the track's notches change too
        geom.notches = notches
        local inner = ns.UpdateGeometry(frame, key, size, notches)
        if not inner then return end
        frame.value:SetFont(STANDARD_TEXT_FONT, math.max(9, math.floor(inner * (cfg.valueScale or 0.25))), "OUTLINE")
        frame.title:SetFont(STANDARD_TEXT_FONT, math.max(7, math.floor(inner * 0.12)), "OUTLINE")
        frame.label:SetFont(STANDARD_TEXT_FONT, math.max(7, math.floor(inner * 0.115)), "OUTLINE")
        frame.title:SetWidth(inner * 0.9)
        frame.title:SetWordWrap(false)
        frame.label:SetWidth(inner * 0.95)
        frame.label:SetWordWrap(false)
        frame.value:ClearAllPoints()
        frame.value:SetPoint("CENTER", frame, "CENTER", 0, -math.floor(inner * 0.02))
        frame.title:ClearAllPoints()
        frame.title:SetPoint("BOTTOM", frame.value, "TOP", 0, 2)
        frame.label:ClearAllPoints()
        frame.label:SetPoint("TOP", frame.value, "BOTTOM", 0, -2)
        local m = frame.markerIsArrow and math.max(16, geom.T * 2.8) or math.max(6, geom.T * 1.6)
        frame.marker:SetSize(m, m)
        frame.markerGlow:SetSize(m * 2, m * 2)
    end

    local function Draw(st)
        Layout(st)
        if cfg.decorate then cfg.decorate(st, frame, geom) end
        if not st then return end
        -- No track: hide it and the border; when it comes back, the next layout redraws them.
        if st.noTrack then
            for _, l in ipairs(frame.bg) do l:Hide() end
            for _, l in ipairs(frame.sqBorder or {}) do l:Hide() end
            frame.trackHidden = true
        elseif frame.trackHidden then
            frame.trackHidden = nil
            frame.layoutKey = nil
        end
        local c = st.color
        for _, l in ipairs(frame.fill) do l:SetColorTexture(c.r, c.g, c.b, 1) end
        DrawArc(frame.fill, 0, st.frac or 0, frame, geom, nil, ns.Shade(key, c))

        -- Lost progress: blinks white a few times, fading out.
        local flashAlpha = 0
        if st.flashAt and st.flashTo and st.flashFrom and st.flashTo > st.flashFrom then
            local age = GetTime() - st.flashAt
            if age >= 0 and age < FLASH_TIME then
                local envelope = 1 - age / FLASH_TIME
                local blink = 0.5 + 0.5 * math.cos(2 * math.pi * FLASH_BLINKS * age / FLASH_TIME)
                flashAlpha = envelope * blink
            end
        end
        if flashAlpha > 0 then
            for _, l in ipairs(frame.flash) do l:SetColorTexture(1, 1, 1, flashAlpha) end
            DrawArc(frame.flash, st.flashFrom, st.flashTo, frame, geom, true)
        else
            for _, l in ipairs(frame.flash) do l:Hide() end
        end
        frame.title:SetText(st.title or "")
        frame.title:SetTextColor(1, 0.82, 0)
        frame.value:SetText(st.value or "")
        frame.value:SetTextColor(1, 1, 1)
        frame.label:SetText(st.label or "")
        local lc = st.labelColor or { r = 0.8, g = 0.8, b = 0.8 }
        frame.label:SetTextColor(lc.r, lc.g, lc.b)
        if st.marker then
            local x, y = math.sin(st.marker) * geom.R, math.cos(st.marker) * geom.R
            frame.marker:ClearAllPoints()
            frame.marker:SetPoint("CENTER", frame, "CENTER", x, y)
            local mc = st.markerColor or { r = 1, g = 1, b = 1 }
            frame.marker:SetVertexColor(mc.r, mc.g, mc.b)
            -- The arrow points up at rotation 0; SetRotation turns counter-clockwise.
            if frame.markerIsArrow and frame.marker.SetRotation then frame.marker:SetRotation(-st.marker) end
            frame.marker:Show()
            frame.markerGlow:ClearAllPoints()
            frame.markerGlow:SetPoint("CENTER", frame.marker, "CENTER")
            frame.markerGlow:SetVertexColor(mc.r, mc.g, mc.b)
            frame.markerGlow:Show()
        else
            frame.marker:Hide()
            frame.markerGlow:Hide()
        end
        DrawBadge(st)
    end

    local function Current(now)
        if editing or now < previewUntil then return cfg.sample(sampleT) end
        if not opt("Enabled") then return nil end
        return cfg.read(now)
    end

    frame:SetScript("OnUpdate", function(self, elapsed)
        local now = GetTime()
        if editing or now < previewUntil then sampleT = sampleT + elapsed end
        local st = Current(now)
        if st then
            last = st
            holdUntil = now + (st.hold or 0)
        end
        Draw(st or last)

        local a = self:GetAlpha()
        if st or now < holdUntil then
            if a < 1 then self:SetAlpha(math.min(1, a + elapsed / 0.25)) end
        else
            a = a - elapsed / 0.5
            if a <= 0 then
                self:SetAlpha(0)
                self:Hide()
                last = nil
                return
            end
            self:SetAlpha(a)
        end
    end)

    -- While hidden, check now and then whether there's something to show.
    local watcher = CreateFrame("Frame")
    watcher.t = 0
    local every = cfg.watchEvery or 0.25
    watcher:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        if self.t < every then return end
        self.t = 0
        if not CircletDB or frame:IsShown() then return end
        if opt("Enabled") and cfg.read(GetTime()) then
            frame:Show()
        end
    end)

    local ring = { frame = frame }
    function ring.SetEditing(on)
        editing = on and true or false
        frame.isEditing = editing
        SetClickMode(editing)
        if frame.editHint then
            frame.editHint:SetText((cfg.locked and cfg.locked()) and "Position locked"
                or "Drag to move  ·  Shift: no snap  ·  Right-click to reset")
        end
        frame.editHint:SetShown(editing)
        frame:SetFrameStrata(editing and EDIT_STRATA or ns.RING_STRATA)
        frame.layoutKey = nil
        if editing then
            sampleT = 0
            frame:Show()
        end
    end
    function ring.IsEditing() return editing end
    function ring.RefreshClicks() SetClickMode(editing) end -- after the menu option changes
    function ring.Preview(seconds)
        previewUntil = GetTime() + (seconds or 10)
        sampleT = 0
        frame:Show()
    end
    return ring
end

ns.CreateLiveRing = CreateLiveRing
