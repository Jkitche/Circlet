-- Circlet: The shared pop-up ring used by the quest, skill, reputation, pet and ammo rings.
local ADDON_NAME, ns = ...

local DrawArc, DrawGlyph, EDIT_STRATA = ns.DrawArc, ns.DrawGlyph, ns.EDIT_STRATA
local ICON_CELEBRATE, IconPose, NewRingLayer, RingHolder = ns.ICON_CELEBRATE, ns.IconPose, ns.NewRingLayer, ns.RingHolder
local XP_SEGMENTS, db = ns.XP_SEGMENTS, ns.db

---------------------------------------------------------------------------
-- Progress ring: one donut shared by the skill ring and the quest ring
---------------------------------------------------------------------------
-- Settings are read from db with a prefix (cfg.key):
--   <key>Enabled, <key>AfterCombat, <key>ShowDelta, <key>Size, <key>Thickness, <key>X, <key>FromTop, <key>Hold
-- Entries: { id, name, from, to, max, percent = bool, segment, gainOffset, ... }.
-- The ring fills (or drains, for a loss) from from/max to to/max while "+N" and
-- "x / max" count. Entries for the same id and segment merge (segment = e.g. a
-- reputation standing, so gains in different standings don't mix); different
-- ids queue and show one after another. gainOffset adds to the "+N" shown, for
-- gains that started in an earlier segment. With <key>AfterCombat
-- on, anything earned in a fight waits until combat ends.
-- cfg.icon(entry), optional, returns { glyph, texture, color, celebrate }. With a
-- texture, it shows as a round badge on the ring's top edge (the game's own icon);
-- otherwise the glyph is drawn in the ring's centre behind the text. Either way it
-- springs in with a glow once the fill lands when celebrate is true.
-- <key>IconBg (rings registered with iconBg): a texture icon fills the ring's middle
-- behind the text, at <key>IconBgAlpha % opacity, instead of the badge on the top edge.
-- Entries may set gainText to replace the "+N" line (and hide the delta line).
-- cfg.onFinish(entry, frame, geom), optional, runs once when an entry's fill lands;
-- it may return a number of seconds to keep the ring up (for an effect to finish).
-- cfg.style(entry, finished) returns { fill, rank, label, labelColor, flash } every frame,
-- so color changes in the options panel show up live. flash: the fill pulses toward white
-- (FLASH_HZ times a second) to grab attention.

local FLASH_HZ = 1.5

local function CreateProgressRing(cfg)
    local key = cfg.key
    local function opt(name) return db[key .. name] end

    local holder = RingHolder(key)
    local frame = ns.NewRingFrame(key)
    local geom = frame.geom
    frame.fill = NewRingLayer("ARTWORK", 0, { r = 1, g = 1, b = 1 }, 1, frame)

    frame.nameText  = frame:CreateFontString(nil, "OVERLAY")
    frame.gainText  = frame:CreateFontString(nil, "OVERLAY")
    frame.deltaText = frame:CreateFontString(nil, "OVERLAY") -- gain as a % of the bar
    frame.rankText  = frame:CreateFontString(nil, "OVERLAY")
    frame.labelText = frame:CreateFontString(nil, "OVERLAY")
    local texts = { frame.nameText, frame.gainText, frame.deltaText, frame.rankText, frame.labelText }
    for _, fs in ipairs(texts) do fs:SetShadowOffset(1, -1) end

    local queue = {}
    local inCombat = false
    local flashColor = {}
    local anim = { entry = nil, from = 0, to = 0, shown = 0, t = 1, dur = 0.8, holdUntil = 0, animEndAt = 0 }

    -- Edit mode: the ring stays up, cycling through cfg.samples() so every color
    -- state can be seen while settings change. Real progress waits in the queue.
    local editing = false
    local sampleIndex, sampleSwitchAt = 1, 0

    -- Centre icon: its own frame one level below the ring so the ring's text draws
    -- on top. It follows the ring's position and fade.
    local iconHolder = CreateFrame("Frame", nil, holder)
    iconHolder:SetSize(1, 1)
    iconHolder:SetPoint("CENTER", frame, "CENTER")
    iconHolder:Hide()
    iconHolder.glow = iconHolder:CreateTexture(nil, "BACKGROUND")
    iconHolder.glow:SetTexture("Interface\\Cooldown\\star4")
    iconHolder.glow:SetBlendMode("ADD")
    iconHolder.glow:SetPoint("CENTER")

    -- Badge: the game's icon clipped to a circle, with a thin colored border, sitting
    -- on the ring's top edge (above the ring, so it doesn't fight with the text).
    local badge = CreateFrame("Frame", nil, holder)
    badge:SetSize(1, 1)
    badge:Hide()
    badge.glow = badge:CreateTexture(nil, "BACKGROUND")
    badge.glow:SetTexture("Interface\\Cooldown\\star4")
    badge.glow:SetBlendMode("ADD")
    badge.glow:SetPoint("CENTER")
    badge.tex = badge:CreateTexture(nil, "ARTWORK")
    badge.tex:SetPoint("CENTER")
    if badge.CreateMaskTexture then
        badge.mask = badge:CreateMaskTexture()
        badge.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        badge.mask:SetPoint("CENTER")
        badge.tex:AddMaskTexture(badge.mask)
    end
    -- Border: a solid colored disc a little larger than the icon, behind it, so a rim
    -- shows around the edge whatever the icon is drawn with (unit portraits included).
    -- A dark disc under the icon keeps see-through parts of a portrait from showing
    -- the rim's color. Without mask support, falls back to a ring of line segments.
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    if badge.mask then
        badge.rim = badge:CreateTexture(nil, "BORDER")
        badge.rim:SetPoint("CENTER")
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
        badge.backing = badge:CreateTexture(nil, "ARTWORK", nil, -8)
        badge.backing:SetPoint("CENTER")
        badge.backing:SetColorTexture(0.05, 0.05, 0.06, 1)
        badge.backing:AddMaskTexture(badge.mask)
    else
        badge.geom = { R = 0, T = 0, step = 2 * math.pi / XP_SEGMENTS }
        badge.border = NewRingLayer("OVERLAY", 0, { r = 1, g = 1, b = 1 }, 1, badge)
    end

    local function DrawBadge(e, icon)
        badge:SetFrameStrata(frame:GetFrameStrata())
        local bg = opt("IconBg")

        local base, scale, rotation, strength, glow
        badge:ClearAllPoints()
        if bg then
            -- Background: fills the hollow, one level below the ring so its text draws on
            -- top, dimmed. A celebration only adds its glow (no pop or wiggle).
            if frame:GetFrameLevel() < 2 then frame:SetFrameLevel(2) end
            badge:SetFrameLevel(frame:GetFrameLevel() - 1)
            base = math.max(8, 2 * geom.R - geom.T - 2 - 2 * ns.BorderWidthOf(key))
            local resting = (opt("IconBgAlpha") or 40) / 100
            scale, rotation, strength, glow = 1, 0, resting, 0
            if icon.celebrate and e.iconStart then
                local _, _, s, gl = IconPose(GetTime() - e.iconStart, resting)
                strength, glow = math.max(resting, s), gl
            end
            badge:SetPoint("CENTER", frame, "CENTER", 0, 0)
        else
            badge:SetFrameLevel(frame:GetFrameLevel() + 3)
            base = math.max(20, opt("Size") * 0.28)
            scale, rotation, strength, glow = 1, 0, 1, 0
            if icon.celebrate and e.iconStart then
                scale, rotation, strength, glow = IconPose(GetTime() - e.iconStart, 1)
            end
            -- Mostly above the ring's outer edge, overlapping it a little.
            badge:SetPoint("CENTER", frame, "CENTER", 0, geom.R + geom.T / 2 + base * 0.2)
        end
        local size = base * scale

        if icon.portrait and SetPortraitTexture then
            -- A unit's portrait (the pet's, as on its unit frame). Re-rendered when the
            -- unit changes, and every couple of seconds in case it was still loading.
            local guid = UnitGUID(icon.portrait)
            local now = GetTime()
            if badge.portraitGUID ~= guid or now - (badge.portraitAt or 0) > 2 then
                SetPortraitTexture(badge.tex, icon.portrait)
                badge.portraitGUID, badge.portraitAt = guid, now
            end
            badge.tex:SetTexCoord(0, 1, 0, 1)
        else
            badge.portraitGUID = nil
            badge.tex:SetTexture(icon.texture)
            badge.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's built-in border
        end
        badge.tex:SetSize(size, size)
        badge.tex:SetRotation(rotation)
        if badge.mask then badge.mask:SetSize(size, size) end

        local rimT = math.max(2, base * 0.1)
        if bg then
            -- No rim, outline or dark backing: just the icon.
            if badge.rim then
                badge.rim:Hide(); badge.outline:Hide(); badge.backing:Hide()
            else
                for _, line in ipairs(badge.border) do line:Hide() end
            end
        elseif badge.rim then
            badge.rim:Show(); badge.backing:Show()
            local d = size + 2 * rimT
            badge.rim:SetSize(d, d)
            badge.rimMask:SetSize(d, d)
            badge.rim:SetColorTexture(icon.color.r, icon.color.g, icon.color.b, 1)
            badge.backing:SetSize(size, size)
            local b = ns.BorderWidthOf(key)
            badge.outline:SetSize(d + 2 * b, d + 2 * b)
            badge.outlineMask:SetSize(d + 2 * b, d + 2 * b)
            badge.outline:SetShown(b > 0)
        else
            badge.geom.T = rimT
            badge.geom.R = size / 2 + rimT / 2 - 1
            DrawArc(badge.border, 0, 1, badge, badge.geom)
            for _, line in ipairs(badge.border) do
                line:SetColorTexture(icon.color.r, icon.color.g, icon.color.b, 1)
            end
        end

        local glowSize = base * (bg and 1.4 or 2.4)
        badge.glow:SetSize(glowSize, glowSize)
        badge.glow:SetVertexColor(icon.color.r, icon.color.g, icon.color.b)
        badge.glow:SetAlpha(glow * 0.9)

        badge:SetAlpha(frame:GetAlpha() * strength)
        badge:Show()
    end

    local function DrawIcon(e)
        local icon = cfg.icon and cfg.icon(e)
        if not icon then iconHolder:Hide() badge:Hide() return end
        if icon.texture or icon.portrait then
            iconHolder:Hide()
            DrawBadge(e, icon)
            return
        end
        badge:Hide()
        if frame:GetFrameLevel() < 2 then frame:SetFrameLevel(2) end
        iconHolder:SetFrameStrata(frame:GetFrameStrata())
        iconHolder:SetFrameLevel(frame:GetFrameLevel() - 1)

        local inner = 2 * geom.R - geom.T
        -- Large enough to show around the text stack, not just behind it.
        local base = math.max(16, inner * 0.85)
        local resting = (opt("IconAlpha") or 80) / 100
        local scale, rotation, strength, glow = 1, 0, resting, 0
        if icon.celebrate and e.iconStart then
            scale, rotation, strength, glow = IconPose(GetTime() - e.iconStart, resting)
        end
        DrawGlyph(iconHolder, icon.glyph, base * scale, rotation, icon.color)
        iconHolder:SetAlpha(frame:GetAlpha() * strength)

        local glowSize = base * 2
        iconHolder.glow:SetSize(glowSize, glowSize)
        iconHolder.glow:SetVertexColor(icon.color.r, icon.color.g, icon.color.b)
        iconHolder.glow:SetAlpha(glow * 0.8 / math.max(strength, 0.01)) -- glow ignores the icon's dimming
        iconHolder:Show()
    end

    local function Layout()
        local size = opt("Size")
        ns.PlaceRing(frame, key, size)
        local showDelta = opt("ShowDelta") and true or false
        local inner = ns.UpdateGeometry(frame, key, size, showDelta)
        if not inner then return end
        frame.gainText:SetFont(STANDARD_TEXT_FONT, math.max(10, math.floor(inner * 0.22)), "OUTLINE")
        frame.deltaText:SetFont(STANDARD_TEXT_FONT, math.max(7, math.floor(inner * 0.11)), "OUTLINE")
        frame.nameText:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(inner * 0.12)), "OUTLINE")
        frame.rankText:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(inner * 0.13)), "OUTLINE")
        frame.labelText:SetFont(STANDARD_TEXT_FONT, math.max(7, math.floor(inner * 0.10)), "OUTLINE")
        -- Long names (objectives, quest titles) are cut off rather than spilling over the ring.
        for _, fs in ipairs({ frame.nameText, frame.labelText }) do
            fs:SetWidth(inner - 6)
            fs:SetWordWrap(false)
        end

        for _, fs in ipairs(texts) do fs:ClearAllPoints() end
        -- Stack: name / +gain / (+delta%) / rank / label. Without the delta line the
        -- rank sits right under the gain and everything moves back down.
        frame.gainText:SetPoint("CENTER", frame, "CENTER", 0, math.floor(inner * (showDelta and 0.10 or 0.04)))
        frame.nameText:SetPoint("BOTTOM", frame.gainText, "TOP", 0, 1)
        frame.deltaText:SetPoint("TOP", frame.gainText, "BOTTOM", 0, 0)
        if showDelta then
            frame.rankText:SetPoint("TOP", frame.deltaText, "BOTTOM", 0, -2)
        else
            frame.rankText:SetPoint("TOP", frame.gainText, "BOTTOM", 0, -2)
        end
        frame.labelText:SetPoint("TOP", frame.rankText, "BOTTOM", 0, -1)
    end

    local function Draw()
        local e = anim.entry
        if not e then return end
        Layout() -- cheap unless a setting changed; keeps the toggle live while a ring is up

        local span = anim.to - anim.from
        local p = (math.abs(span) > 1e-9) and (anim.shown - anim.from) / span or 1
        p = math.min(1, math.max(0, p))
        local value = math.floor(e.from + (e.to - e.from) * p + 0.5) -- counts with the fill
        local s = cfg.style(e, p >= 1)
        if p >= 1 and not e.finishFired and anim.t >= anim.dur then
            e.finishFired = true
            local icon = cfg.icon and cfg.icon(e)
            if icon and icon.celebrate then
                e.iconStart = GetTime()
                anim.holdUntil = math.max(anim.holdUntil, GetTime() + ICON_CELEBRATE + 0.3)
            end
            local extra = cfg.onFinish and cfg.onFinish(e, frame, geom)
            if extra then anim.holdUntil = math.max(anim.holdUntil, GetTime() + extra) end
        end

        local fill = s.fill
        if s.flash then
            local k = 0.7 * (0.5 - 0.5 * math.cos(GetTime() * 2 * math.pi * FLASH_HZ))
            flashColor.r = fill.r + (1 - fill.r) * k
            flashColor.g = fill.g + (1 - fill.g) * k
            flashColor.b = fill.b + (1 - fill.b) * k
            fill = flashColor
        end
        for _, line in ipairs(frame.fill) do
            line:SetColorTexture(fill.r, fill.g, fill.b, 1)
        end
        DrawArc(frame.fill, 0, anim.shown, frame, geom, nil, ns.Shade(key, fill))

        frame.nameText:SetText(e.name)
        frame.nameText:SetTextColor(0.9, 0.9, 0.9)
        local gain = (e.gainOffset or 0) + (value - e.from)
        frame.gainText:SetText(e.gainText
            or ((gain < 0 and "-" or "+") .. BreakUpLargeNumbers(math.abs(gain)) .. (e.percent and "%" or "")))
        frame.gainText:SetTextColor(1, 1, 1)
        -- The same gain as a share of this bar (redundant for objectives already in %).
        if e.percent or e.gainText or not opt("ShowDelta") then
            frame.deltaText:SetText("")
        else
            local pct = gain / e.max * 100
            frame.deltaText:SetText(string.format("%s%.1f%%", pct < 0 and "-" or "+", math.abs(pct)))
        end
        frame.deltaText:SetTextColor(s.rank.r, s.rank.g, s.rank.b)
        frame.rankText:SetText(e.percent and (value .. "%")
            or (BreakUpLargeNumbers(value) .. " / " .. BreakUpLargeNumbers(e.max)))
        frame.rankText:SetTextColor(s.rank.r, s.rank.g, s.rank.b)
        frame.labelText:SetText(s.label or "")
        frame.labelText:SetTextColor(s.labelColor.r, s.labelColor.g, s.labelColor.b)
        DrawIcon(e)
    end

    local ShowNext -- forward declaration

    local function Play(entry)
        Layout()
        local continuing = frame:IsShown() and anim.entry and anim.entry.id == entry.id
            and anim.entry.segment == entry.segment
        local fromFrac = continuing and anim.shown or (entry.from / entry.max)
        if continuing then -- keep counting the whole "+N"
            entry.from, entry.gainOffset = anim.entry.from, anim.entry.gainOffset
        end
        anim.entry = entry
        entry.finishFired, entry.iconStart = nil, nil
        anim.from, anim.to, anim.shown, anim.t = fromFrac, math.min(1, math.max(0, entry.to / entry.max)), fromFrac, 0
        anim.dur = math.min(1.8, math.max(0.7, 0.6 + math.abs(anim.to - anim.from) * 4))
        anim.animEndAt = GetTime() + anim.dur
        anim.holdUntil = anim.animEndAt + opt("Hold")
        frame:Show()
        Draw()
    end

    local function ShowSample()
        local samples = cfg.samples and cfg.samples() or {}
        local sample = samples[sampleIndex]
        if not sample then return end
        Play(sample)
        sampleSwitchAt = GetTime() + (sample.editTime or 3.5)
    end

    frame:SetScript("OnUpdate", function(self, elapsed)
        local now = GetTime()
        if anim.t < anim.dur then
            anim.t = math.min(anim.dur, anim.t + elapsed)
            local p = 1 - (1 - anim.t / anim.dur) ^ 3 -- ease out
            anim.shown = anim.from + (anim.to - anim.from) * p
        end
        Draw()

        if editing then
            local a = self:GetAlpha()
            if a < 1 then self:SetAlpha(math.min(1, a + elapsed / 0.2)) end
            if now >= sampleSwitchAt then
                local count = cfg.samples and #cfg.samples() or 1
                sampleIndex = sampleIndex % count + 1
                ShowSample()
            end
            return
        end

        -- With more entries waiting, hold only a second after the fill so the queue moves along.
        local holdUntil = anim.holdUntil
        if #queue > 0 then holdUntil = math.min(holdUntil, anim.animEndAt + 1.0) end

        local a = self:GetAlpha()
        if now < holdUntil then
            if a < 1 then self:SetAlpha(math.min(1, a + elapsed / 0.2)) end
        else
            a = a - elapsed / 0.4
            if a <= 0 then
                self:SetAlpha(0)
                self:Hide()
                iconHolder:Hide()
                badge:Hide()
                anim.entry = nil
                ShowNext()
                return
            end
            self:SetAlpha(a)
        end
    end)

    ShowNext = function(force)
        if editing then return end -- real progress waits until editing is done
        if frame:IsShown() then return end
        if inCombat and opt("AfterCombat") and not force then return end
        local entry = table.remove(queue, 1)
        if entry then Play(entry) end
    end

    local ring = {}

    function ring.Queue(entry, force)
        if not force and not opt("Enabled") then return end
        if not entry.max or entry.max <= 0 then return end

        if frame:IsShown() and anim.entry and anim.entry.id == entry.id
            and anim.entry.segment == entry.segment
            and not (inCombat and opt("AfterCombat")) then
            Play(entry) -- extend the ring that's already up
            return
        end
        for _, waiting in ipairs(queue) do
            if waiting.id == entry.id then
                -- Total shown so far by the waiting entry, before it's overwritten.
                local soFar = (waiting.gainOffset or 0) + (waiting.to - waiting.from)
                local sameSegment = waiting.segment == entry.segment
                local from, offset = waiting.from, waiting.gainOffset
                for k, v in pairs(entry) do waiting[k] = v end
                if sameSegment then
                    waiting.from, waiting.gainOffset = from, offset -- keep the earliest starting point
                else
                    -- Crossed into a new segment while waiting: the new entry's own offset
                    -- covers finishing the old segment, so add what was earned before that.
                    waiting.gainOffset = soFar + (entry.gainOffset or 0)
                end
                return
            end
        end
        table.insert(queue, entry)
        ShowNext(force)
    end

    function ring.CombatStart()
        inCombat = true
        if opt("AfterCombat") and frame:IsShown() then
            anim.holdUntil = 0 -- fade out; the fight's progress comes after
        end
    end

    function ring.CombatEnd()
        -- Credit for the last kill can land a moment after combat ends.
        C_Timer.After(0.4, function()
            if InCombatLockdown() then return end -- already in the next fight
            inCombat = false
            ShowNext()
        end)
    end

    function ring.SetEditing(on)
        editing = on and true or false
        frame.isEditing = editing
        frame:EnableMouse(editing)
        frame.editHint:SetShown(editing)
        frame:SetFrameStrata(editing and EDIT_STRATA or "HIGH")
        if editing then
            Layout()
            sampleIndex = 1
            ShowSample()
        else
            anim.holdUntil, anim.animEndAt = 0, 0 -- fade the sample out; queued progress follows
        end
    end

    function ring.IsEditing() return editing end

    function ring.Preview(entries)
        if editing then return end
        wipe(queue)
        frame:Hide()
        iconHolder:Hide()
        badge:Hide()
        anim.entry = nil
        for _, e in ipairs(entries) do ring.Queue(e, true) end
    end

    -- "Wait until combat ends": progress made in a fight is held back until it's over.
    ns.Listen({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }, function(event)
        if event == "PLAYER_REGEN_DISABLED" then ring.CombatStart() else ring.CombatEnd() end
    end)

    return ring
end

-- Shared with the files loaded after this one.
ns.CreateProgressRing = CreateProgressRing
