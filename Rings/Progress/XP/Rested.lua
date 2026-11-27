-- Circlet: XP ring: resting: the zZZ icon on the ring, and how long until rested XP is full.
local _, ns = ...

local db = ns.db
local XP = ns.XPRing
local xpRing = XP.xpRing
local xpState = XP.xpState
local anim = XP.anim

-- Resting "zZZ": the same animated icon as above your player portrait, on the ring's
-- top-right edge while you're resting. Built from the player frame's own animation
-- when it can be found (modern flipbook, or the classic state icon); otherwise three
-- drawn z's that drift up and fade.
local restIcon = CreateFrame("Frame", nil, xpRing)
restIcon:SetSize(1, 1)
restIcon:Hide()

local function FindFlipbook(region)
    if not region then return nil end
    local textures, groups = {}, {}
    if region.GetAtlas then table.insert(textures, region) end
    if region.GetRegions then
        for _, r in ipairs({ region:GetRegions() }) do
            if r.GetAtlas then table.insert(textures, r) end
        end
    end
    for _, tex in ipairs(textures) do
        local atlas = tex:GetAtlas()
        if atlas and tex.GetAnimationGroups then
            for _, g in ipairs({ tex:GetAnimationGroups() }) do table.insert(groups, { tex = tex, g = g }) end
        end
    end
    if region.GetAnimationGroups then
        for _, g in ipairs({ region:GetAnimationGroups() }) do table.insert(groups, { tex = textures[1], g = g }) end
    end
    for _, entry in ipairs(groups) do
        for _, a in ipairs({ entry.g:GetAnimations() }) do
            if a.GetFlipBookRows and entry.tex and entry.tex:GetAtlas() then
                return entry.tex:GetAtlas(), a:GetFlipBookRows(), a:GetFlipBookColumns(), a:GetFlipBookFrames(),
                    a:GetDuration()
            end
        end
    end
end

local function BuildRestIcon()
    if restIcon.built then return end
    restIcon.built = true
    -- Modern player frame: a flipbook animation.
    local content = PlayerFrame and PlayerFrame.PlayerFrameContent
    local contextual = content and content.PlayerFrameContentContextual
    local atlas, rows, cols, frames, duration = FindFlipbook(contextual and contextual.PlayerRestLoop)
    if not atlas then atlas, rows, cols, frames, duration = FindFlipbook(_G.PlayerRestLoop) end
    if atlas and rows and cols and frames and rows * cols > 0 then
        local tex = restIcon:CreateTexture(nil, "OVERLAY")
        tex:SetAtlas(atlas, false)
        tex:SetPoint("CENTER")
        local group = tex:CreateAnimationGroup()
        local anim = group:CreateAnimation("FlipBook")
        anim:SetFlipBookRows(rows)
        anim:SetFlipBookColumns(cols)
        anim:SetFlipBookFrames(frames)
        anim:SetDuration((duration and duration > 0) and duration or 1.5)
        group:SetLooping("REPEAT")
        restIcon.tex, restIcon.anim, restIcon.kind = tex, group, "flipbook"
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
        restIcon.aspect = (info and info.width and info.height and info.height > 0)
            and (info.width / cols) / (info.height / rows) or 1
        return
    end
    -- Classic player frame: a static "zzz" from the state icon sheet; it bobs gently.
    local classic = _G.PlayerRestIcon
    if classic and classic.GetTexture and classic:GetTexture() then
        local tex = restIcon:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(classic:GetTexture())
        tex:SetTexCoord(classic:GetTexCoord())
        tex:SetPoint("CENTER")
        restIcon.tex, restIcon.kind, restIcon.aspect = tex, "classic", 1
        return
    end
    -- Fallback: three z's.
    restIcon.zs = {}
    for i = 1, 3 do
        local z = restIcon:CreateFontString(nil, "OVERLAY")
        z:SetText(i == 1 and "z" or "Z")
        z:SetTextColor(0.75, 0.85, 1)
        restIcon.zs[i] = z
    end
    restIcon.kind, restIcon.aspect = "drawn", 1
end

-- Each frame while the ring is up: place it on the ring and animate the fallbacks.
local function UpdateRestIcon(show, radius, size)
    if not (show and db.xpRestIcon) then
        if restIcon:IsShown() then
            restIcon:Hide()
            if restIcon.anim then restIcon.anim:Stop() end
        end
        return
    end
    BuildRestIcon()
    local s = math.max(18, size * 0.24)
    restIcon:SetFrameLevel(xpRing:GetFrameLevel() + 4)
    restIcon:ClearAllPoints()
    -- On the ring's top-right edge, like the portrait's corner.
    restIcon:SetPoint("CENTER", xpRing, "CENTER", radius * 0.72, radius * 0.72 + s * 0.15)
    restIcon:SetSize(s, s)
    local t = GetTime()
    if restIcon.kind == "flipbook" then
        restIcon.tex:SetSize(s * restIcon.aspect, s)
    elseif restIcon.kind == "classic" then
        restIcon.tex:SetSize(s, s)
        restIcon.tex:SetPoint("CENTER", 0, math.sin(t * 2.2) * s * 0.06)
        restIcon.tex:SetAlpha(0.8 + 0.2 * math.sin(t * 2.2))
    else
        for i, z in ipairs(restIcon.zs) do
            local p = (t * 0.45 + (i - 1) / 3) % 1 -- each z rises and fades on its own cycle
            z:SetFont(STANDARD_TEXT_FONT, math.floor(s * (0.35 + 0.35 * p)), "OUTLINE")
            z:ClearAllPoints()
            z:SetPoint("CENTER", restIcon, "CENTER", (p - 0.5) * s * 0.5, (p - 0.4) * s * 0.9)
            z:SetAlpha(math.sin(p * math.pi))
        end
    end
    if not restIcon:IsShown() then
        restIcon:Show()
        if restIcon.anim then restIcon.anim:Play() end
    end
end

-- Resting (inn or city): the XP ring stays up showing your rested XP building.
local function RestingShow()
    if not (db.xpRestedRing and IsResting and IsResting()) or InCombatLockdown() then return false end
    return xpState.max ~= nil and xpState.max > 0
end

-- Rested XP grows 5% of a level per 8 hours of resting, up to 150% of a level.
local RESTED_CAP, RESTED_PER_HOUR = 1.5, 0.05 / 8

local function RestedFullIn(rested, max)
    local missing = RESTED_CAP * max - rested
    if missing <= max * 0.005 then return nil end
    local hours = missing / (max * RESTED_PER_HOUR)
    local h, m = math.floor(hours), math.floor((hours % 1) * 60)
    if h >= 48 then return string.format("full in ~%d days", math.floor(hours / 24 + 0.5)) end
    if h >= 1 then return string.format("full in ~%dh %02dm", h, m) end
    return string.format("full in ~%dm", math.max(1, m))
end

-- For the files loaded after this one.
XP.UpdateRestIcon = UpdateRestIcon
XP.RestingShow = RestingShow
XP.RestedFullIn = RestedFullIn
XP.restIcon = restIcon
