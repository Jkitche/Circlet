-- Circlet: a welcome animation when you log in.
local ADDON_NAME, ns = ...

local db, IsSecret, NewRingLayer, DrawArc, XP_SEGMENTS = ns.db, ns.IsSecret, ns.NewRingLayer, ns.DrawArc, ns.XP_SEGMENTS

---------------------------------------------------------------------------
-- Welcome animation
---------------------------------------------------------------------------
-- On login (not /reload): five rings in the addon's colors spin open like a portal,
-- your name types itself out in your class color, then your level, class and zone,
-- how rested you are and when you last played fade in underneath. After a few
-- seconds the rings fling outward in a burst of sparks and everything fades.
-- Turned on and off on the General tab (db.loginFx).

local SIZE = 300
local RINGS = {
    -- radius, thickness, arc length, spin (turns per second; negative = backwards), color
    { 58, 5, 0.55, 0.45, { r = 0.58, g = 0.42, b = 0.95 } }, -- XP purple
    { 76, 4, 0.40, -0.32, { r = 1.00, g = 0.82, b = 0.25 } }, -- quest gold
    { 92, 6, 0.65, 0.22, { r = 0.40, g = 0.70, b = 1.00 } }, -- flight blue
    { 110, 3, 0.30, -0.55, { r = 0.30, g = 0.85, b = 0.40 } }, -- reputation green
    { 126, 5, 0.50, 0.28, { r = 0.95, g = 0.55, b = 0.20 } }, -- crafting orange
}
local T = { ringsIn = 1.0, nameStart = 0.45, perLetter = 0.06, subStart = 1.5, hold = 4.2, out = 0.9 }
local TOTAL = T.hold + T.out

local fx = CreateFrame("Frame", nil, UIParent)
fx:SetFrameStrata("HIGH")
fx:SetSize(SIZE, SIZE)
fx:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
fx:Hide()

for i, spec in ipairs(RINGS) do
    -- Two layers per ring: an arc that wraps past 12 o'clock is drawn in two pieces.
    spec.a = NewRingLayer("ARTWORK", i - 6, spec[5], 1, fx)
    spec.b = NewRingLayer("ARTWORK", i - 6, spec[5], 1, fx)
    spec.geom = { R = spec[1], T = spec[2], step = 2 * math.pi / XP_SEGMENTS }
end

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SPARKS = 18
fx.sparks = {}
for i = 1, SPARKS do
    local s = fx:CreateTexture(nil, "OVERLAY")
    s:SetTexture(CIRCLE)
    s:SetBlendMode("ADD")
    local c = RINGS[(i - 1) % #RINGS + 1][5]
    s:SetVertexColor(c.r, c.g, c.b)
    s:Hide()
    fx.sparks[i] = s
end

local function Text(size, r, g, b)
    local fs = fx:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    fs:SetTextColor(r, g, b)
    fs:SetShadowOffset(1, -1)
    return fs
end
fx.hello = Text(13, 1, 0.82, 0.25)
fx.hello:SetPoint("BOTTOM", fx, "CENTER", 0, 18)
fx.name = Text(26, 1, 1, 1)
fx.name:SetPoint("CENTER", fx, "CENTER", 0, 0)
fx.line1 = Text(12, 0.9, 0.9, 0.9)
fx.line1:SetPoint("TOP", fx, "CENTER", 0, -20)
fx.line2 = Text(11, 0.6, 0.75, 1)
fx.line2:SetPoint("TOP", fx.line1, "BOTTOM", 0, -3)

local info, startedAt = nil, 0

local function Ease(t) return 1 - (1 - math.max(0, math.min(1, t))) ^ 3 end

local function SetColor(layer, c, a)
    for _, l in ipairs(layer) do l:SetColorTexture(c.r, c.g, c.b, a) end
end

-- An arc from `from` of length `len` (fractions of the circle), wrapping past the top.
local function DrawSpinArc(spec, from, len, alpha)
    from = from % 1
    SetColor(spec.a, spec[5], alpha)
    SetColor(spec.b, spec[5], alpha)
    DrawArc(spec.a, from, math.min(1, from + len), fx, spec.geom)
    if from + len > 1 then
        DrawArc(spec.b, 0, from + len - 1, fx, spec.geom)
    else
        for _, l in ipairs(spec.b) do l:Hide() end
    end
end

local function DrawFrame(t)
    local out = t > T.hold and Ease((t - T.hold) / T.out) or 0
    local alpha = 1 - out

    for i, spec in ipairs(RINGS) do
        -- Each ring opens a little after the one inside it, spinning its own way.
        local open = Ease((t - (i - 1) * 0.08) / T.ringsIn)
        spec.geom.R = spec[1] * (0.4 + 0.6 * open) * (1 + 0.9 * out)
        local len = spec[3] * open
        if len > 0.002 and alpha > 0 then
            DrawSpinArc(spec, t * spec[4] + i * 0.17, len, open * alpha)
        else
            for _, l in ipairs(spec.a) do l:Hide() end
            for _, l in ipairs(spec.b) do l:Hide() end
        end
    end

    -- Sparks fling outward as the rings leave.
    local sp = out
    for i, s in ipairs(fx.sparks) do
        if t > T.hold and sp < 1 then
            local ang = (i / SPARKS) * 2 * math.pi
            local dist = 60 + 140 * sp + (i % 3) * 12
            s:ClearAllPoints()
            s:SetPoint("CENTER", fx, "CENTER", math.sin(ang) * dist, math.cos(ang) * dist)
            local size = 8 * (1 - sp) + 2
            s:SetSize(size, size)
            s:SetAlpha(1 - sp)
            s:Show()
        else
            s:Hide()
        end
    end

    -- Text: "Welcome back," then the name typing itself out, then the details.
    fx.hello:SetAlpha(Ease(t / 0.5) * alpha)
    local letters = math.floor((t - T.nameStart) / T.perLetter)
    local name = info.name
    fx.name:SetText(letters > 0 and name:sub(1, math.min(#name, letters)) or "")
    fx.name:SetAlpha(alpha)
    local pop = Ease((t - T.nameStart - #name * T.perLetter) / 0.25)
    fx.name:SetScale(1 + 0.12 * (1 - pop) * (letters >= #name and 1 or 0))
    fx.line1:SetAlpha(Ease((t - T.subStart) / 0.5) * alpha)
    fx.line2:SetAlpha(Ease((t - T.subStart - 0.3) / 0.5) * alpha)
end

fx:SetScript("OnUpdate", function()
    local t = GetTime() - startedAt
    if t >= TOTAL then
        fx:Hide()
        return
    end
    DrawFrame(t)
end)

---------------------------------------------------------------------------
-- What it says
---------------------------------------------------------------------------
local function CharKey()
    local name, realm = UnitName("player"), GetRealmName and GetRealmName() or ""
    if IsSecret(name) then return nil end
    return (name or "?") .. "-" .. (realm or "")
end

local function Ago(seconds)
    if seconds < 3600 then return "Last seen " .. math.max(1, math.floor(seconds / 60)) .. " min ago" end
    if seconds < 86400 then
        local h = math.floor(seconds / 3600)
        return "Last seen " .. h .. (h == 1 and " hour ago" or " hours ago")
    end
    local d = math.floor(seconds / 86400)
    return "Last seen " .. d .. (d == 1 and " day ago" or " days ago")
end

local function Gather(sample)
    local name = UnitName("player")
    if IsSecret(name) then name = nil end
    local className, classFile = UnitClass("player")
    local level = UnitLevel("player")
    local zone = GetZoneText and GetZoneText() or ""
    local c = classFile and (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]) or nil

    local parts = {}
    if level and not IsSecret(level) then table.insert(parts, "Level " .. level) end
    if className and not IsSecret(className) then table.insert(parts, className) end
    local line1 = table.concat(parts, " ")
    if zone and zone ~= "" and not IsSecret(zone) then
        line1 = line1 ~= "" and (line1 .. "  ·  " .. zone) or zone
    end

    local bits = {}
    local rest, max = GetXPExhaustion and GetXPExhaustion(), UnitXPMax("player")
    if rest and max and not IsSecret(rest) and not IsSecret(max) and max > 0 and rest > 0 then
        table.insert(bits, string.format("Rested %d%%", math.floor(rest / max * 100 + 0.5)))
    end
    local key = CharKey()
    local last = key and db.lastSeen and db.lastSeen[key]
    if sample and not last then last = time() - 2 * 86400 end
    if last then table.insert(bits, Ago(time() - last)) end

    return { name = name or "Adventurer", color = c, line1 = line1, line2 = table.concat(bits, "  ·  ") }
end

local function Play(sample)
    info = Gather(sample)
    fx.hello:SetText("Welcome back,")
    local c = info.color or { r = 1, g = 1, b = 1 }
    fx.name:SetTextColor(c.r, c.g, c.b)
    fx.line1:SetText(info.line1)
    fx.line2:SetText(info.line2)
    startedAt = GetTime()
    fx:Show()
    DrawFrame(0)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, isInitialLogin)
    if not CircletDB then return end
    if event == "PLAYER_LOGOUT" then
        local key = CharKey()
        if key then
            db.lastSeen = db.lastSeen or {}
            db.lastSeen[key] = time()
        end
    elseif event == "PLAYER_ENTERING_WORLD" and isInitialLogin and db.loginFx then
        -- A moment after the loading screen, so it isn't missed.
        C_Timer.After(1.5, function() Play(false) end)
    end
end)

-- Shared with the files loaded after this one.
ns.PreviewWelcome = function() Play(true) end
