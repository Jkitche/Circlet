-- Circlet: Health ring effect: a glow in the debuff's type color while the unit has a debuff you can remove.
local _, ns = ...

local SafeCall, Clean, IsSecret = ns.SafeCall, ns.Clean, ns.IsSecret
local FX = ns.HealthFx
local GLOW = FX.GLOW
local Tex = FX.Tex
local GlowOn = FX.GlowOn

-- The game's "HARMFUL|RAID" filter is the debuffs you can remove yourself. In combat addons
-- can't read a debuff, not even its type, so the glow is one of the game's aura containers
-- (as for the buff and debuff arcs, Rings/Health/Auras.lua): a group of one, on that filter,
-- whose single button carries our glow texture, which the game tints in the debuff type's
-- color and shows only while there is one. The container's made out of combat. Where the
-- client has no containers, the glow is read out of combat only. Previews glow blue (magic).
local FILTER = "HARMFUL|RAID|INCLUDE_NAME_PLATE_ONLY" -- (see Rings/Health/Auras.lua)
local STYLE_PRESERVE = 3 -- Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
local PREVIEW = { 0.2, 0.6, 1 }
local UNIT = { playerHp = "player", targetHp = "target" }

local function InCombat() return InCombatLockdown and InCombatLockdown() end

local targetGen = 0 -- bumped on each target change
ns.Listen({ "PLAYER_TARGET_CHANGED" }, function() targetGen = targetGen + 1 end)

local function NoMouse(f)
    if f.EnableMouse then pcall(f.EnableMouse, f, false) end
    if f.SetMouseClickEnabled then pcall(f.SetMouseClickEnabled, f, false) end
    if f.SetMouseMotionEnabled then pcall(f.SetMouseMotionEnabled, f, false) end
end

-- The glow's own frame, under the ring (like the other halos) so it doesn't wash the band out.
local function Holder(fx, frame)
    local w = fx.cure
    if w then return w end
    local h = CreateFrame("Frame", nil, frame)
    h:SetAllPoints(frame)
    NoMouse(h)
    w = { holder = h, glows = {} }
    fx.cure = w
    return w
end

-- The container, made the first time it's needed out of combat; false if this client has none.
local function Container(w, frame, unit)
    if w.c ~= nil or InCombat() then return w.c end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, w.holder, "CustomAuraContainerTemplate")
    if not (ok and c and type(c.AddAuraGroup) == "function") then
        w.c = false
        return false
    end
    NoMouse(c)
    c:SetPoint("CENTER", frame, "CENTER")
    pcall(c.SetUnit, c, unit)
    local added = pcall(c.AddAuraGroup, c, "cure", FILTER, {
        maxFrameCount = 1,
        layout = { elementWidth = 1, elementHeight = 1, elementSpacing = 0 },
        candidateFilters = {}, -- every source (see Rings/Health/Auras.lua)
        initializeFrame = function(b)
            if not InCombat() then NoMouse(b) end
            local t = b:CreateTexture(nil, "BACKGROUND")
            t:SetTexture(GLOW)
            t:SetBlendMode("ADD")
            t:SetPoint("CENTER", frame, "CENTER")
            if w.size then t:SetSize(w.size, w.size) end
            if
                not (
                    b.AddDispelTypeTexture
                    and pcall(
                        b.AddDispelTypeTexture,
                        b,
                        t,
                        { style = STYLE_PRESERVE, showWhenHarmful = true, showWithoutDispelType = false }
                    )
                )
            then
                t:SetVertexColor(0.8, 0.1, 0.1)
            end
            w.glows[#w.glows + 1] = t
        end,
    })
    w.c = added and c or false
    if w.c then pcall(c.SetEnabled, c, true) end
    return w.c
end

-- Out of combat (or with no containers): the first removable debuff's type color, or nil.
local function ReadableColor(unit)
    if InCombat() then return nil end
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 40 do
        local a = get and SafeCall(get, unit, i, FILTER)
        if a == nil or IsSecret(a) then return nil end
        local kind = Clean(a.dispelName)
        local c = kind and DebuffTypeColor and DebuffTypeColor[kind]
        if c then return { c.r, c.g, c.b } end
    end
end

local function DrawCure(key, fx, st, frame, geom, d, now)
    local w = Holder(fx, frame)
    local unit = st.unit and UNIT[key]
    if st.unit and (st.dead or not unit) then
        w.holder:Hide()
        return
    end
    local level = math.max(0, frame:GetFrameLevel() - 1)
    if w.holder:GetFrameLevel() ~= level then w.holder:SetFrameLevel(level) end
    local r = geom.R + geom.T * 0.55
    local c = unit and Container(w, frame, unit)
    -- A new target: the container's pointed at it afresh (see Rings/Health/Auras.lua).
    if c and unit == "target" and w.gen ~= targetGen then
        w.gen = targetGen
        pcall(c.SetEnabled, c, false)
        pcall(c.SetUnit, c, unit)
        pcall(c.SetEnabled, c, true)
    end
    local plain = Tex(fx, "cureGlow", GLOW, "BACKGROUND", 0, true, w.holder)
    if c then
        plain:Hide()
        local size = math.floor(2 * r / 0.70 + 0.5) -- as GlowOn sizes it
        if w.size ~= size and not InCombat() then
            w.size = size
            for _, t in ipairs(w.glows) do
                t:SetSize(size, size)
            end
        end
    else
        local col = unit and ReadableColor(unit) or (not unit and PREVIEW)
        if not col then
            plain:Hide()
        else
            GlowOn(plain, frame, r)
            plain:SetVertexColor(col[1], col[2], col[3])
        end
    end
    w.holder:SetAlpha(0.45 + 0.3 * math.sin(now * 3))
    w.holder:Show()
end

local function HideCure(fx)
    if fx and fx.cure then fx.cure.holder:Hide() end
end

-- For the files loaded after this one.
FX.DrawCure = DrawCure
FX.HideCure = HideCure
