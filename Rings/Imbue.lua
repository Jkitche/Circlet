-- Circlet: Weapon imbue ring (shamans): time left on your main-hand imbue, animated by kind.
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall, Clean, CleanNumber = ns.db, ns.CreateLiveRing, ns.SafeCall, ns.Clean, ns.CleanNumber

---------------------------------------------------------------------------
-- Weapon imbue ring
---------------------------------------------------------------------------
-- While your main hand has a shaman weapon imbue, the ring drains over it with the imbue's
-- name and the time left, turning the warning color in the last 30 seconds and saying
-- Faded when it's gone. With imbueFx on, each imbue has its own animation:
--   Rockbiter    stone chunks orbiting the ring, tumbling, with grit falling away
--   Flametongue  tongues of flame licking outward all round, embers rising, a warm glow
--   Frostbrand   ice crystals twinkling and turning, snowflakes drifting down, a cold glow
--   Windfury     wind streaks whipping round the ring at different heights
--
-- The time comes from GetWeaponEnchantInfo (if it's hidden in combat, the last reading's
-- clock runs on). Which imbue it is: the enchant's ID, from the known ranks below, or
-- learned when you cast one (the next new enchant on the weapon is that imbue), or failing
-- both, read off the weapon's tooltip.

local KINDS = {
    rock  = { name = "Rockbiter",   spell = "Rockbiter Weapon",   spellID = 8017,
              ids = { 29, 6, 1, 503, 1663, 683, 1664 } },
    flame = { name = "Flametongue", spell = "Flametongue Weapon", spellID = 8024,
              ids = { 5, 4, 3, 523, 1665, 1666 } },
    frost = { name = "Frostbrand",  spell = "Frostbrand Weapon",  spellID = 8033,
              ids = { 2, 12, 524, 1667, 1668 } },
    wind  = { name = "Windfury",    spell = "Windfury Weapon",    spellID = 8232,
              ids = { 283, 284, 525, 1669 } },
}
local ORDER = { "rock", "flame", "frost", "wind" }
local DEFAULT_TOTAL = 300 -- imbues last 5 minutes
local WARN = 30
local FADED_SHOW = 4

local byEnchant = {}
for kind, k in pairs(KINDS) do for _, id in ipairs(k.ids) do byEnchant[id] = kind end end

-- Which kind a spell is (any rank, by name), or nil.
local function KindOfSpell(spellID)
    local n = ns.SpellName(CleanNumber(spellID))
    if not n then return nil end
    for kind, k in pairs(KINDS) do
        if n == k.spell or n == ns.SpellName(k.spellID) then return kind end
    end
end

-- Which kind the weapon's tooltip says (its "Flametongue 4 (5 min)" line), or nil.
local function KindFromTooltip()
    local get = C_TooltipInfo and C_TooltipInfo.GetInventoryItem
    local data = get and SafeCall(get, "player", 16)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        local text = Clean(line.leftText)
        if type(text) == "string" then
            for kind, k in pairs(KINDS) do
                if text:find(k.name, 1, true) then return kind end
            end
        end
    end
end

local current        -- { kind, endsAt (GetTime()), total, enchant }
local castKind, castAt
local faded          -- { kind, at }

local function KindOf(enchant)
    if enchant and db.imbueLearned and db.imbueLearned[enchant] then return db.imbueLearned[enchant] end
    if enchant and byEnchant[enchant] then return byEnchant[enchant] end
    return KindFromTooltip()
end

-- Reads the main hand's imbue; keeps the last reading if it's hidden.
local function Read()
    local has, expiresMS, _, enchant = SafeCall(GetWeaponEnchantInfo)
    if has == nil or ns.IsSecret(has) or ns.IsSecret(expiresMS) then return end
    enchant = CleanNumber(enchant)
    local now = GetTime()
    if not has then
        if current then faded = { kind = current.kind, at = now } end
        current = nil
        return
    end
    local left = (CleanNumber(expiresMS) or 0) / 1000
    if left <= 0 then return end
    local fresh = not current or enchant ~= current.enchant or left > (current.endsAt - now) + 2
    if fresh then
        -- Just cast one: this enchant is that imbue (learn it for next time).
        if castKind and now - castAt < 3 and enchant then
            db.imbueLearned = db.imbueLearned or {}
            db.imbueLearned[enchant] = castKind
        end
        local kind = (castKind and now - (castAt or 0) < 3 and castKind) or KindOf(enchant)
        current = { kind = kind, enchant = enchant, total = math.max(DEFAULT_TOTAL, left), endsAt = now + left }
        castKind, faded = nil, nil
    else
        current.endsAt = now + left
    end
end

---------------------------------------------------------------------------
-- The ring
---------------------------------------------------------------------------
local function Clock(secs)
    secs = math.max(0, secs)
    if secs >= 60 then return string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60)) end
    return string.format("%ds", math.ceil(secs))
end

local function State(kind, left, total)
    local c = db.imbueColors
    local k = KINDS[kind]
    local warn = left <= WARN
    local color = warn and c.warn or (kind and c[kind]) or c.rock
    return { title = k and k.name or "Imbue", icon = ns.SpellIcon(k and k.spellID or 8017),
             frac = math.max(0, math.min(1, left / total)), value = Clock(left), label = "",
             color = color, labelColor = warn and c.warn or nil, hold = 1, imbue = kind, imbueWarn = warn }
end

local imbueRing
imbueRing = CreateLiveRing({
    key = "imbue",
    watchEvery = 0.5,
    read = function(now)
        Read()
        if current then
            local left = current.endsAt - now
            if left <= 0 then faded = { kind = current.kind, at = now }; current = nil
            elseif db.imbueAlways or left <= WARN or current.total - left < 4 then
                return State(current.kind, left, current.total)
            else
                return nil
            end
        end
        if faded and now - faded.at < FADED_SHOW then
            local st = State(faded.kind, 0, 1)
            st.value, st.frac, st.color = "Faded", 0, db.imbueColors.warn
            st.imbue = nil -- gone: no animation
            return st
        end
        return nil
    end,
    sample = function(t)
        local i = math.floor(t / 4) % #ORDER + 1
        local u = (t % 4) / 4
        return State(ORDER[i], DEFAULT_TOTAL * (1 - u * 0.6), DEFAULT_TOTAL)
    end,
    decorate = function(st, frame, geom) ns.DrawImbueFx(st, frame, geom) end,
})

---------------------------------------------------------------------------
-- The animations
---------------------------------------------------------------------------
local GLOW_TEX = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local STAR_TEX = "Interface\\Cooldown\\star4"
local SQUARE_TEX = "Interface\\Buttons\\WHITE8X8"
local N = 16 -- pieces per effect

local fx

local function Tex(frame, layer, sub, tex, add)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    if t:SetTexture(tex) == false and tex == GLOW_TEX then t:SetTexture(STAR_TEX) end
    if add then t:SetBlendMode("ADD") end
    t:Hide()
    return t
end

local function Build(frame)
    fx = { pieces = {}, bits = {} }
    fx.glow = Tex(frame, "BACKGROUND", -5, GLOW_TEX, true)
    fx.glow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    for i = 1, N do
        -- Fixed per piece so they don't move in lockstep.
        fx.pieces[i] = { glow = Tex(frame, "ARTWORK", 2, GLOW_TEX, true), star = Tex(frame, "ARTWORK", 3, STAR_TEX, true),
                         block = Tex(frame, "ARTWORK", 2, SQUARE_TEX, false),
                         phase = (i * 0.618) % 1, speed = 0.7 + (i * 0.37) % 0.6, size = 0.6 + (i * 0.53) % 0.7,
                         lane = ((i * 0.437) % 1) * 2 - 1 }
        fx.bits[i] = Tex(frame, "ARTWORK", 4, STAR_TEX, true)
    end
end

local function HideAll()
    if not fx then return end
    fx.glow:Hide()
    for i, p in ipairs(fx.pieces) do p.glow:Hide(); p.star:Hide(); p.block:Hide(); fx.bits[i]:Hide() end
end

-- x, y of a point at angle a (radians, clockwise from the top) and radius r.
local function At(a, r) return math.sin(a) * r, math.cos(a) * r end

local function Put(t, frame, x, y, w, h)
    t:ClearAllPoints()
    t:SetPoint("CENTER", frame, "CENTER", x, y)
    t:SetSize(w, h or w)
    t:Show()
end

local DRAW = {}

-- Rockbiter: chunks of stone orbiting slowly just outside the band, tumbling, bobbing in
-- and out; grit falling away from them.
function DRAW.rock(frame, now, R, T, warn)
    local orbit = now * 0.35
    for i, p in ipairs(fx.pieces) do
        if i <= 9 then
            local a = orbit + (i / 9) * math.pi * 2 + p.lane * 0.2
            local r = R + T * 0.6 + math.sin(now * 1.3 + i) * T * 0.35
            local x, y = At(a, r)
            local s = T * (0.55 + 0.45 * p.size)
            Put(p.block, frame, x, y, s, s * (0.7 + 0.3 * p.size))
            p.block:SetVertexColor(0.45 + 0.15 * p.size, 0.36 + 0.1 * p.size, 0.24, 1)
            if p.block.SetRotation then p.block:SetRotation(now * (0.8 + p.speed) * (i % 2 == 0 and 1 or -1)) end
            p.block:SetAlpha(0.95)
            -- Grit: a speck falling from each chunk.
            local u = (now * p.speed * 0.7 + p.phase) % 1
            Put(fx.bits[i], frame, x + p.lane * T * 0.3, y - u * T * 2.5, T * 0.35)
            fx.bits[i]:SetVertexColor(0.75, 0.62, 0.42)
            fx.bits[i]:SetAlpha((1 - u) * 0.6)
        else
            p.block:Hide(); fx.bits[i]:Hide()
        end
        p.glow:Hide(); p.star:Hide()
    end
    Put(fx.glow, frame, 0, 0, R * 1.6)
    fx.glow:SetVertexColor(0.6, 0.45, 0.25)
    fx.glow:SetAlpha(0.25 + 0.05 * math.sin(now * 1.5))
end

-- Flametongue: flames licking outward all round the ring, flickering; embers rising off
-- the top; a warm glow breathing in the middle.
function DRAW.flame(frame, now, R, T, warn)
    for i, p in ipairs(fx.pieces) do
        local a = (i / N) * math.pi * 2 + math.sin(now * 0.7 + i) * 0.05
        local flick = 0.65 + 0.35 * math.abs(math.sin(now * (5 + p.speed * 4) + i * 1.7))
        local out = T * (0.5 + 1.1 * flick * p.size)
        local x, y = At(a, R + out * 0.5)
        y = y + out * 0.25 -- flames lean up
        Put(p.glow, frame, x, y, T * 1.3 * flick, T * 1.3 * flick + out)
        p.glow:SetVertexColor(1, 0.45 + 0.35 * flick, 0.1)
        p.glow:SetAlpha(0.55 * flick)
        p.star:Hide(); p.block:Hide()
        -- Embers: rising from the top half of the ring and drifting.
        local u = (now * p.speed * 0.6 + p.phase) % 1
        local ea = p.lane * 1.1
        local ex, ey = At(ea, R)
        Put(fx.bits[i], frame, ex + math.sin(now * 3 + i) * T * 0.6 * u, ey + u * R * 0.9, T * 0.45 * (1 - u * 0.5))
        fx.bits[i]:SetVertexColor(1, 0.85 - 0.6 * u, 0.3 - 0.25 * u)
        fx.bits[i]:SetAlpha(math.min(1, u * 5) * (1 - u))
    end
    Put(fx.glow, frame, 0, -R * 0.1, R * 1.9 * (0.95 + 0.05 * math.sin(now * 9)))
    fx.glow:SetVertexColor(1, 0.5, 0.15)
    fx.glow:SetAlpha(0.45 + 0.1 * math.sin(now * 11.3))
end

-- Frostbrand: ice crystals sitting round the band, turning slowly and twinkling; snowflakes
-- drifting down through the ring; a cold glow.
function DRAW.frost(frame, now, R, T, warn)
    local turn = now * 0.15
    for i, p in ipairs(fx.pieces) do
        local a = turn + (i / N) * math.pi * 2
        local x, y = At(a, R + T * (0.2 + 0.3 * p.lane))
        local tw = 0.5 + 0.5 * math.sin(now * (2 + p.speed * 3) + i * 2.1)
        local s = T * (0.9 + 0.9 * p.size) * (0.7 + 0.3 * tw)
        Put(p.star, frame, x, y, s)
        p.star:SetVertexColor(0.7, 0.9, 1)
        if p.star.SetRotation then p.star:SetRotation(now * 0.6 + i) end
        p.star:SetAlpha(0.35 + 0.65 * tw)
        p.glow:Hide(); p.block:Hide()
        -- Snow: falling across the whole ring, swaying.
        local u = (now * p.speed * 0.25 + p.phase) % 1
        local sx = p.lane * R * 0.9 + math.sin(now * 1.4 + i) * T * 0.8
        Put(fx.bits[i], frame, sx, R * 1.1 - u * R * 2.4, T * 0.5 * p.size)
        fx.bits[i]:SetVertexColor(0.85, 0.95, 1)
        fx.bits[i]:SetAlpha(math.min(1, u * 6) * math.min(1, (1 - u) * 6) * 0.8)
    end
    Put(fx.glow, frame, 0, 0, R * 1.8)
    fx.glow:SetVertexColor(0.45, 0.75, 1)
    fx.glow:SetAlpha(0.3 + 0.1 * math.sin(now * 2))
end

-- Windfury: streaks of wind whipping round the ring at different heights, each a head and
-- a fading tail; brief gusts flaring now and then.
function DRAW.wind(frame, now, R, T, warn)
    local gust = 0.75 + 0.25 * math.max(0, math.sin(now * 1.7)) ^ 4
    for i, p in ipairs(fx.pieces) do
        local streak = math.floor((i - 1) / 4) -- four streaks of four pieces (head and tail)
        local seg = (i - 1) % 4
        local sp = 2.6 + streak * 0.7
        local a = now * sp * (streak % 2 == 0 and 1 or -1) + streak * 1.6 - seg * 0.16 * (streak % 2 == 0 and 1 or -1)
        local r = R + T * (-0.6 + streak * 0.55)
        local x, y = At(a, r)
        local s = T * (1.4 - seg * 0.28) * gust
        Put(p.glow, frame, x, y, s * 1.6, s * 0.8)
        if p.glow.SetRotation then p.glow:SetRotation(-a) end
        p.glow:SetVertexColor(0.75, 1, 0.95)
        p.glow:SetAlpha((0.7 - seg * 0.16) * gust)
        p.star:Hide(); p.block:Hide(); fx.bits[i]:Hide()
    end
    Put(fx.glow, frame, 0, 0, R * 1.6)
    fx.glow:SetVertexColor(0.6, 0.95, 0.9)
    fx.glow:SetAlpha(0.18 * gust)
end

local function DrawImbueFx(st, frame, geom)
    if not (st and st.imbue and db.imbueFx) or not geom or geom.R <= 0 then return HideAll() end
    local draw = DRAW[st.imbue]
    if not draw then return HideAll() end
    if not fx then Build(frame) end
    draw(frame, GetTime(), geom.R, math.max(2, geom.T), st.imbueWarn)
end
ns.DrawImbueFx = DrawImbueFx

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen({ "UNIT_SPELLCAST_SUCCEEDED:player" }, function(_, _, _, spellID)
    local kind = KindOfSpell(spellID)
    if kind then castKind, castAt = kind, GetTime() end
end)

ns.imbueRing = imbueRing
ns.PreviewImbueRing = function() imbueRing.Preview(16) end

---------------------------------------------------------------------------
-- Registration (see Core/Registry.lua)
---------------------------------------------------------------------------
ns.RegisterRing({
    key = "imbue", name = "Imbue", order = 14.15, since = "1.4.0",
    class = { SHAMAN = true },
    iconBg = true,
    ring = imbueRing,
    preview = ns.PreviewImbueRing, slash = { "imbue" }, help = "preview the weapon imbue ring",
    toggle = { "Weapon imbue ring", "Time left on your weapon imbue, with an animation for each kind." },
    defaults = {
        -- Weapon imbue ring (shamans): right of the target cast ring, across from the shot ring.
        imbueEnabled   = true,
        imbueAlways    = true, -- the whole time; off: just the last 30 seconds, and when you put it on
        imbueFx        = true,
        imbueSize      = 80,
        imbueThickness = 8,
        imbueOpacity   = 100,
        imbueX         = 255,
        imbueFromTop   = 385,
        imbueHold      = 1,
        imbueStyle     = "smooth",
        imbueBorder    = 2,
        imbueColors = {
            rock  = { r = 0.72, g = 0.55, b = 0.35 },
            flame = { r = 1.00, g = 0.45, b = 0.10 },
            frost = { r = 0.50, g = 0.80, b = 1.00 },
            wind  = { r = 0.70, g = 0.95, b = 0.85 },
            warn  = { r = 1.00, g = 0.30, b = 0.25 },
        },
    },
    page = { folder = "combat", order = 3.6, build = function(O)
            local Toggle, Color, Box = O.Toggle, O.Color, O.Box
            local RingTab, MergeTop, TopRow, SizeBox = O.RingTab, O.MergeTop, O.TopRow, O.SizeBox
            return RingTab(13.55, "Weapon imbue", "Weapon Imbue Ring",
                "While your main hand has a weapon imbue, the ring drains over it with the imbue's name and the time "
                .. "left, turning red in the last 30 seconds, and says Faded when it's gone. Each imbue has its own "
                .. "animation: orbiting stones for Rockbiter, flames and embers for Flametongue, ice crystals and snow "
                .. "for Frostbrand, and whipping wind for Windfury.",
                MergeTop(TopRow("imbue", "weapon imbue ring", ns.PreviewImbueRing,
                    "Show each imbue in turn. Also /circ imbue."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "imbueEnabled", "Show weapon imbue ring",
                            "Show the ring while your weapon has an imbue."),
                        always = Toggle(2, "imbueAlways", "Show for the whole time",
                            "Off: only when you put it on, in its last 30 seconds, and when it fades."),
                        fx = Toggle(3, "imbueFx", "Animations",
                            "Orbiting stones, flames, ice and snow, or whipping wind, by imbue."),
                    }),
                    colors = Box(3, "Colors", {
                        rock = Color(1, "imbueColors", "rock", "Rockbiter", "Ring color for Rockbiter."),
                        flame = Color(2, "imbueColors", "flame", "Flametongue", "Ring color for Flametongue."),
                        frost = Color(3, "imbueColors", "frost", "Frostbrand", "Ring color for Frostbrand."),
                        wind = Color(4, "imbueColors", "wind", "Windfury", "Ring color for Windfury."),
                        warn = Color(5, "imbueColors", "warn", "Running out", "Ring color in the last 30 seconds."),
                    }),
                    size = SizeBox(4, "imbue", "weapon imbue ring", "Offset from the center of the screen."),
                }))
        end },
})
