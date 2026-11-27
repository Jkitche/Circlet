-- Circlet: Crafting effects: an animation of its own for each crafting profession, on the
-- crafting ring.
local ADDON_NAME, ns = ...

local db, SafeCall, Clean = ns.db, ns.SafeCall, ns.Clean

-- Shared by Rings/Professions/*.lua, which load in this order: CraftFx, CraftFxProfessions.
ns.CraftFx = ns.CraftFx or {}
local CF = ns.CraftFx

---------------------------------------------------------------------------
-- Which profession
---------------------------------------------------------------------------
-- When a batch starts, the profession is the trade skill window that's open: its name
-- (English, or this client's own name for the profession, from the profession's spell).
-- These are the crafting professions WoW Forever has (its SkillLine table: no Jewelcrafting or
-- Inscription).
local PROFESSIONS = {
    -- kind           English names                        the profession's spell (for its local name)
    { kind = "alchemy", names = { "Alchemy" }, spell = 2259 },
    { kind = "blacksmithing", names = { "Blacksmithing" }, spell = 2018 },
    { kind = "enchanting", names = { "Enchanting" }, spell = 7411 },
    { kind = "engineering", names = { "Engineering" }, spell = 4036 },
    { kind = "leatherworking", names = { "Leatherworking" }, spell = 2108 },
    { kind = "tailoring", names = { "Tailoring" }, spell = 3908 },
    { kind = "cooking", names = { "Cooking" }, spell = 2550 },
    { kind = "firstaid", names = { "First Aid" }, spell = 3273 },
    { kind = "smelting", names = { "Mining", "Smelting" }, spell = 2656 },
    { kind = "poisons", names = { "Poisons" }, spell = 2842 },
}

local byName
local function KindOf(name)
    name = Clean(name)
    if type(name) ~= "string" then return nil end
    if not byName then
        byName = {}
        for _, p in ipairs(PROFESSIONS) do
            for _, n in ipairs(p.names) do
                byName[n] = p.kind
            end
            local own = ns.SpellName and ns.SpellName(p.spell)
            if own then byName[own] = byName[own] or p.kind end
        end
    end
    return byName[name]
end

-- The profession of the trade skill window that's open now (nil if it can't be told).
-- craft: the batch came from the older Craft window (Enchanting on old clients).
local function OpenProfession(craft)
    local name
    if craft then
        name = GetCraftDisplaySkillLine and SafeCall(GetCraftDisplaySkillLine)
        if not name and GetCraftName then name = SafeCall(GetCraftName) end
    else
        local info = C_TradeSkillUI
            and C_TradeSkillUI.GetBaseProfessionInfo
            and SafeCall(C_TradeSkillUI.GetBaseProfessionInfo)
        if type(info) == "table" then name = Clean(info.professionName) end
        if not name and GetTradeSkillLine then name = SafeCall(GetTradeSkillLine) end
    end
    return KindOf(name)
end

---------------------------------------------------------------------------
-- The effects
---------------------------------------------------------------------------
-- Worked out from the time alone, so edit mode's sample plays them too. The crafting
-- ring's state carries (Rings/Professions/Craft.lua):
--   st.craftFx: the profession (only while craftFx is on); st.fxStart: when the batch
--   started; st.fxMadeAt: when the last item was made (a pop at the end of the fill);
--   st.fxEndAt: when the batch ended, if it has; st.fxDone: it finished (a closing burst
--   in the profession's colors) rather than being stopped (the effect just fades).
--
--   alchemy:        bubbles rise through a potion glow that shifts from green to violet.
--   blacksmithing:  a hammer strikes the end of the fill, throwing sparks off hot metal.
--   engineering:    lightning crackles between the end of the fill and the middle.
--   enchanting:     runes orbit the middle, and a beam of arcane light plays on the fill.
--   tailoring:      a needle stitches along the fill, leaving neat stitches behind it.
--   leatherworking: the fill turns to tooled, studded leather, laced by a needle in wide waves.
--   cooking:        flames lick the bottom of the ring and steam rises from it.
--   firstaid:       a heartbeat glow in the middle, and crosses rising through it.
--   smelting:       molten metal glows in the hollow and embers rise off it.
--   poisons:        green drops gather and fall from the bottom of the ring.

local TAU = 2 * math.pi
local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR_TEX = "Interface\\Cooldown\\star4"
local DOT_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HAMMER_TEX = "Interface\\Cursor\\Crosshair\\Repair"
local HAMMER_FALLBACK = "Interface\\Cursor\\Repair"

local POP_TIME, BURST_TIME, FADE_TIME = 0.5, 1.2, 0.8

-- Each profession's colors: the main one and a second one for variety.
local PALETTE = {
    alchemy = { { r = 0.35, g = 1.00, b = 0.45 }, { r = 0.75, g = 0.40, b = 1.00 } },
    blacksmithing = { { r = 1.00, g = 0.60, b = 0.15 }, { r = 1.00, g = 0.90, b = 0.55 } },
    engineering = { { r = 0.55, g = 0.85, b = 1.00 }, { r = 1.00, g = 0.85, b = 0.30 } },
    enchanting = { { r = 0.75, g = 0.45, b = 1.00 }, { r = 1.00, g = 0.55, b = 0.95 } },
    tailoring = { { r = 1.00, g = 0.95, b = 0.80 }, { r = 0.55, g = 0.75, b = 1.00 } },
    leatherworking = { { r = 0.70, g = 0.45, b = 0.22 }, { r = 0.90, g = 0.72, b = 0.35 } },
    cooking = { { r = 1.00, g = 0.55, b = 0.15 }, { r = 1.00, g = 0.90, b = 0.40 } },
    firstaid = { { r = 0.45, g = 1.00, b = 0.55 }, { r = 1.00, g = 1.00, b = 1.00 } },
    smelting = { { r = 1.00, g = 0.45, b = 0.10 }, { r = 1.00, g = 0.85, b = 0.35 } },
    poisons = { { r = 0.45, g = 1.00, b = 0.20 }, { r = 0.75, g = 1.00, b = 0.40 } },
}

local function Hash(n)
    local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)
end
local function Mix(a, b, t) return a + (b - a) * t end
local function Clamp(x) return math.max(0, math.min(1, x)) end

-- Pools of textures and lines on the crafting ring's frame, made on first use. Each frame
-- takes what it needs from the front of each pool and hides the rest.
local POOL_SIZES = { glow = 20, star = 48, dot = 80, puff = 12, line = 640, spark = 128 }

local function Build(frame)
    CF.fx = { frame = frame }
    local function Tex(tex, blend, sub)
        local t = frame:CreateTexture(nil, "ARTWORK", nil, sub)
        if t:SetTexture(tex) == false then t:SetTexture(STAR_TEX) end -- a client without the glow art
        t:SetBlendMode(blend)
        t:Hide()
        return t
    end
    local function Line(add, sub)
        local l = frame:CreateLine(nil, "ARTWORK", nil, sub)
        if add and l.SetBlendMode then l:SetBlendMode("ADD") end
        if l.SetSnapToPixelGrid then
            l:SetSnapToPixelGrid(false)
            l:SetTexelSnappingBias(0)
        end
        l:Hide()
        return l
    end
    CF.fx.glow, CF.fx.star, CF.fx.dot, CF.fx.puff, CF.fx.line, CF.fx.spark = {}, {}, {}, {}, {}, {}
    for i = 1, POOL_SIZES.glow do
        CF.fx.glow[i] = Tex(GLOW_TEX, "ADD", 2)
    end
    for i = 1, POOL_SIZES.puff do
        CF.fx.puff[i] = Tex(GLOW_TEX, "BLEND", 3)
    end -- soft smoke and steam
    for i = 1, POOL_SIZES.star do
        CF.fx.star[i] = Tex(STAR_TEX, "ADD", 6)
    end
    for i = 1, POOL_SIZES.dot do
        CF.fx.dot[i] = Tex(DOT_TEX, "BLEND", 3)
    end
    for i = 1, POOL_SIZES.line do
        CF.fx.line[i] = Line(false, 4)
    end
    for i = 1, POOL_SIZES.spark do
        CF.fx.spark[i] = Line(true, 5)
    end
    CF.fx.tool = frame:CreateTexture(nil, "ARTWORK", nil, 7)
    if CF.fx.tool:SetTexture(HAMMER_TEX) == false then CF.fx.tool:SetTexture(HAMMER_FALLBACK) end
    CF.fx.tool:Hide()
end

local function Take(kind)
    local i = CF.used[kind] + 1
    local item = CF.fx[kind][i]
    if item then CF.used[kind] = i end
    return item
end

-- A soft glow (ADD), a star (ADD, turned by rot), or a round dot (normal blending).
local function Put(kind, x, y, size, r, g, b, a, rot)
    if a <= 0.01 or size <= 0.5 then return end
    local t = Take(kind)
    if not t then return end
    t:ClearAllPoints()
    t:SetPoint("CENTER", CF.fx.frame, "CENTER", x, y)
    t:SetSize(size, size)
    t:SetVertexColor(r, g, b)
    t:SetAlpha(Clamp(a))
    if t.SetRotation then t:SetRotation(rot or 0) end
    t:Show()
end
local function Glow(...) Put("glow", ...) end
local function Star(...) Put("star", ...) end
local function Dot(...) Put("dot", ...) end
local function Puff(...) Put("puff", ...) end

-- A line: "line" (normal) or "spark" (ADD, glowing).
local function Seg(kind, x1, y1, x2, y2, w, r, g, b, a)
    if a <= 0.01 then return end
    local l = Take(kind)
    if not l then return end
    l:SetStartPoint("CENTER", CF.fx.frame, x1, y1)
    l:SetEndPoint("CENTER", CF.fx.frame, x2, y2)
    l:SetThickness(math.max(1, w))
    l:SetColorTexture(r, g, b, Clamp(a))
    l:Show()
end

local function HideRest()
    for kind in pairs(POOL_SIZES) do
        local pool = CF.fx[kind]
        for i = CF.used[kind] + 1, #pool do
            pool[i]:Hide()
        end
    end
    if not CF.used.tool then CF.fx.tool:Hide() end
end

local function HideAll()
    if not CF.fx then return end
    CF.used = { glow = 0, star = 0, dot = 0, puff = 0, line = 0, spark = 0 }
    HideRest()
end

-- Everything a profession needs to draw one frame.
--   x, y: the end of the fill (on the ring's middle line); ox, oy: outward from the middle there
--   R, T, ri: ring radius, band width, inside radius; k: how strongly to draw (fades when it ends)
local function Context(st, geom, now)
    local frac = Clamp(st.frac or 0)
    local x, y = ns.RingPoint(geom, frac)
    local d = math.sqrt(x * x + y * y)
    return {
        now = now,
        t = now - (st.fxStart or now),
        frac = frac,
        x = x,
        y = y,
        ox = d > 0 and x / d or 0,
        oy = d > 0 and y / d or 1,
        R = geom.R,
        T = math.max(3, geom.T),
        ri = math.max(4, geom.R - geom.T / 2),
        geom = geom,
        k = 1,
        ended = st.fxEndAt ~= nil,
    }
end

-- For the files loaded after this one.
CF.KindOf = KindOf
CF.OpenProfession = OpenProfession
CF.TAU = TAU
CF.POP_TIME = POP_TIME
CF.BURST_TIME = BURST_TIME
CF.FADE_TIME = FADE_TIME
CF.PALETTE = PALETTE
CF.Hash = Hash
CF.Mix = Mix
CF.Clamp = Clamp
CF.Build = Build
CF.Glow = Glow
CF.Star = Star
CF.Dot = Dot
CF.Puff = Puff
CF.Seg = Seg
CF.HideRest = HideRest
CF.HideAll = HideAll
CF.Context = Context
