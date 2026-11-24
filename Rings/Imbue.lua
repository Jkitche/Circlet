-- Circlet: Weapon imbue ring (shamans): time left on your main-hand imbue, animated by kind.
local ADDON_NAME, ns = ...

local db, CreateLiveRing, SafeCall, Clean, CleanNumber = ns.db, ns.CreateLiveRing, ns.SafeCall, ns.Clean, ns.CleanNumber

---------------------------------------------------------------------------
-- Weapon imbue ring
---------------------------------------------------------------------------
-- While your main hand has a shaman weapon imbue, the ring drains over it with the imbue's
-- name and the time left, turning the warning color in the last 30 seconds and saying
-- Faded when it's gone. With imbueFx on, each imbue has its own animation:
--   Rockbiter    stones orbiting the ring, tumbling, with grit falling away (the stones are
--                Textures/Rock1-4.tga, made by tools/make_rock_textures.py)
--   Flametongue  lava pouring down both sides of the ring, crusting over as it cools
--                (Textures/Lava1-3.tga, tools/make_lava_textures.py) and dripping off the
--                bottom (Textures/Flame1-3.tga, tools/make_flame_textures.py); bubbles popping
--   Frostbrand   ice crystals twinkling and turning, snowflakes drifting down, a cold glow
--   Windfury     wind streaks whipping round the ring at different heights
--
-- The time comes from GetWeaponEnchantInfo (if it's hidden in combat, the last reading's
-- clock runs on). Which imbue it is: the weapon's tooltip line ("Flametongue 3 (5 min)"),
-- else the enchant's ID from the known ranks below, else one the tooltip named before; a
-- cast you just made is only a stand-in until one of those answers (see KindOf).

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

-- Enchants learned from casts by earlier versions: some were learned wrong (683 as
-- Frostbrand, 1667 as Windfury), and they outranked the known ranks. Dropped once loaded.
ns.Listen({ "PLAYER_LOGIN" }, function() if CircletDB then CircletDB.imbueLearned = nil end end)

-- Which kind a spell is (any rank, by name), or nil.
local function KindOfSpell(spellID)
    local n = ns.SpellName(CleanNumber(spellID))
    if not n then return nil end
    for kind, k in pairs(KINDS) do
        if n == k.spell or n == ns.SpellName(k.spellID) then return kind end
    end
end

-- Which kind the weapon's tooltip says, or nil. The temporary enchant's own line reads like
-- "Flametongue 3 (5 min)": a line with the name and a time in brackets is taken first; a
-- line with just the name only if there's no such line (the weapon's own name or effects
-- could mention one).
local function KindFromTooltip()
    local get = C_TooltipInfo and C_TooltipInfo.GetInventoryItem
    local data = get and SafeCall(get, "player", 16)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local loose
    for _, line in ipairs(data.lines) do
        local text = Clean(line.leftText)
        if type(text) == "string" then
            for kind, k in pairs(KINDS) do
                if text:find(k.name, 1, true) then
                    if text:find("%(%d+ ?%a+%)") then return kind end
                    loose = loose or kind
                end
            end
        end
    end
    return loose
end

local current        -- { kind, endsAt (GetTime()), total, enchant, sure }
local castKind, castAt
local faded          -- { kind, at }

-- Which imbue an enchant is, and whether that's certain: the weapon's tooltip (the game's
-- own words), then the known ranks above, then enchants learned from the tooltip before (for
-- ranks not listed). Learning from casts went wrong when a reading lagged the cast (in
-- combat, or the old imbue still showing), so casts are only a last guess, never stored.
local function KindOf(enchant)
    local fromTip = KindFromTooltip()
    if fromTip then
        if enchant and not byEnchant[enchant] then
            db.imbueTipLearned = db.imbueTipLearned or {}
            db.imbueTipLearned[enchant] = fromTip
        end
        return fromTip, true
    end
    if enchant and byEnchant[enchant] then return byEnchant[enchant], true end
    if enchant and db.imbueTipLearned and db.imbueTipLearned[enchant] then return db.imbueTipLearned[enchant], true end
    if castKind and GetTime() - (castAt or 0) < 5 then return castKind, false end
    return nil, false
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
        local kind, sure = KindOf(enchant)
        current = { kind = kind, sure = sure, enchant = enchant, total = math.max(DEFAULT_TOTAL, left), endsAt = now + left }
        faded = nil
    else
        current.endsAt = now + left
        -- Not certain yet (the tooltip can lag the enchant): look again.
        if not current.sure then
            local kind, sure = KindOf(enchant)
            if kind then current.kind, current.sure = kind, sure end
        end
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
local ROCK_TEX = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Rock"
-- Flame1-3.tga (tools/make_flame_textures.py): white tongues of flame standing on their base,
-- tinted here; the flame's foot is 7% up from the bottom of the image.
local FLAME_TEX = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Flame"
local FLAME_FOOT = 0.07
-- Lava1-3.tga (tools/make_lava_textures.py): lumps of dark crust with molten cracks, drawn in
-- their own colors.
local LAVA_TEX = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\Lava"
local FLOW = 32 -- blobs in Flametongue's lava stream (16 down each side)
local N = 16 -- pieces per effect

local fx

local function Tex(frame, layer, sub, tex, add)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    if t:SetTexture(tex) == false and tex == GLOW_TEX then t:SetTexture(STAR_TEX) end
    if add then t:SetBlendMode("ADD") end
    t:Hide()
    return t
end

-- A fixed pseudo-random number in [0, 1) for piece i and salt k: irregular, but the same every
-- frame (and every session), so pieces don't jump about.
local function Hash(i, k)
    local v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
    return v - math.floor(v)
end

local function Build(frame)
    fx = { pieces = {}, bits = {} }
    fx.glow = Tex(frame, "BACKGROUND", -5, GLOW_TEX, true)
    fx.glow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    for i = 1, N do
        -- Fixed per piece so they don't move in lockstep, and random rather than evenly
        -- spread so they don't look spaced out like clockwork. jit: how far a piece sits
        -- off its even slot around the ring (-1..1 of a slot).
        -- speed: 0.4..1.6, so some pieces drift at a quarter of the pace of others.
        fx.pieces[i] = { glow = Tex(frame, "ARTWORK", 2, GLOW_TEX, true), star = Tex(frame, "ARTWORK", 3, STAR_TEX, true),
                         flame = Tex(frame, "ARTWORK", 2, FLAME_TEX .. ((i - 1) % 3 + 1), true),
                         lava = Tex(frame, "ARTWORK", 3, LAVA_TEX .. ((i - 1) % 3 + 1), false),
                         core = Tex(frame, "ARTWORK", 3, FLAME_TEX .. ((i + 1) % 3 + 1), true),
                         block = Tex(frame, "ARTWORK", 2, ROCK_TEX .. ((i - 1) % 4 + 1), false),
                         grit = Tex(frame, "ARTWORK", 1, ROCK_TEX .. ((i + 1) % 4 + 1), false),
                         phase = Hash(i, 1), speed = 0.4 + Hash(i, 2) * 1.2, size = 0.6 + Hash(i, 3) * 0.7,
                         lane = Hash(i, 4) * 2 - 1, jit = Hash(i, 5) * 2 - 1,
                         -- dir: which way it goes round the ring (about 4 in 10 go backwards);
                         -- spin: which way it turns on its own axis (picked separately).
                         dir = Hash(i, 6) < 0.4 and -1 or 1, spin = Hash(i, 7) < 0.5 and -1 or 1 }
        fx.bits[i] = Tex(frame, "ARTWORK", 4, STAR_TEX, true)
    end
    -- Flametongue's lava stream: overlapping blobs, each a molten glow with a crust over it,
    -- half pouring down each side of the ring.
    fx.flow = {}
    for j = 1, FLOW do
        fx.flow[j] = { hot = Tex(frame, "ARTWORK", 1, GLOW_TEX, true),
                       crust = Tex(frame, "ARTWORK", 3, LAVA_TEX .. ((j - 1) % 3 + 1), false),
                       side = j % 2 == 0 and 1 or -1, off = (math.ceil(j / 2) - 1 + Hash(j, 8) * 0.7) / (FLOW / 2),
                       size = Hash(j, 9), speed = Hash(j, 10), turn = Hash(j, 11) * 6.28 }
    end
end

local function HideFlow()
    for _, b in ipairs(fx.flow) do b.hot:Hide(); b.crust:Hide() end
end

local function HideAll()
    if not fx then return end
    fx.glow:Hide()
    for i, p in ipairs(fx.pieces) do
        p.glow:Hide(); p.star:Hide(); p.flame:Hide(); p.lava:Hide(); p.core:Hide(); p.block:Hide(); p.grit:Hide(); fx.bits[i]:Hide()
    end
    HideFlow()
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

-- Rockbiter: stones orbiting slowly just outside the band, tumbling, bobbing in and out;
-- grit (tiny stones) falling away from them.
function DRAW.rock(frame, now, R, T, warn)
    for i, p in ipairs(fx.pieces) do
        p.flame:Hide(); p.lava:Hide(); p.core:Hide()
        if i <= 8 then
            -- Each stone orbits at its own pace and some the other way, so they drift
            -- together, pass each other and part.
            local a = now * (0.15 + 0.3 * p.speed) * p.dir + ((i + p.jit * 0.4) / 8) * math.pi * 2
            local r = R + T * (0.9 + 0.3 * p.lane) + math.sin(now * (1.0 + p.speed * 0.6) + i) * T * 0.35
            local x, y = At(a, r)
            local s = T * (1.3 + 0.8 * p.size)
            Put(p.block, frame, x, y, s)
            p.block:SetVertexColor(1, 0.97, 0.92, 1)
            if p.block.SetRotation then p.block:SetRotation(now * (0.25 + p.speed * 0.3) * p.spin + i) end
            p.block:SetAlpha(1)
            -- Grit: a tiny stone falling from each one, turning as it goes.
            local u = (now * p.speed * 0.7 + p.phase) % 1
            Put(p.grit, frame, x + p.lane * T * 0.4, y - s * 0.3 - u * T * 2.8, T * 0.55 * (1 - u * 0.4))
            if p.grit.SetRotation then p.grit:SetRotation(now * 3 * -p.spin + i) end
            p.grit:SetAlpha((1 - u) * 0.9)
        else
            p.block:Hide(); p.grit:Hide()
        end
        p.glow:Hide(); p.star:Hide(); fx.bits[i]:Hide()
    end
    Put(fx.glow, frame, 0, 0, R * 1.6)
    fx.glow:SetVertexColor(0.6, 0.45, 0.25)
    fx.glow:SetAlpha(0.25 + 0.05 * math.sin(now * 1.5))
end

-- Flametongue: flowing lava. Molten lava wells up at the top of the ring and pours down both
-- sides along the band, gathering speed as it goes, glowing yellow-orange where it's fresh
-- and growing a dark crust (Textures/Lava1-3) as it cools on the way down. At the bottom it
-- gathers and drips off: strands sag and stretch long and thin, then let go, and the drop
-- falls, rounding up and cooling from yellow to dark red (the drips are the flame shape the
-- right way up: thin neck above, round drop below). Bubbles swell and pop where the lava's
-- hottest, near the top; a deep red heat glows behind it all.
local FLOW_SPEED = 0.07 -- of a half ring per second, before gravity
function DRAW.flame(frame, now, R, T, warn)
    local cool = warn and 0.75 or 1 -- running out: the lava dims
    -- The stream: each blob's place down its side of the ring (0 at the top, 1 at the bottom),
    -- quickening as it falls (pos = f^1.6), so blobs spread out lower down like a real pour.
    for j, b in ipairs(fx.flow) do
        local f = (b.off + now * FLOW_SPEED * (0.85 + 0.3 * b.speed)) % 1
        local pos = f ^ 1.6
        local a = b.side * math.pi * (0.03 + 0.95 * pos)
        local wob = math.sin(now * 1.1 + j * 2.3) * T * 0.15
        local x, y = At(a, R + wob)
        -- Thick where it wells up, thinning as it runs, swelling again as it pools at the bottom.
        local thick = 1.15 - 0.45 * math.sin(pos * math.pi * 0.85) + 0.3 * math.max(0, pos - 0.8) / 0.2
        local s = T * (1.7 + 0.7 * b.size) * thick
        local fade = math.min(1, f * 10) * math.min(1, (1 - f) * 8)
        Put(b.hot, frame, x, y, s * 1.45)
        b.hot:SetVertexColor(1, 0.62 - 0.36 * pos, 0.16 - 0.13 * pos)
        b.hot:SetAlpha((0.5 + 0.35 * (1 - pos)) * fade * cool)
        Put(b.crust, frame, x, y, s)
        if b.crust.SetRotation then b.crust:SetRotation(b.turn - a * 0.6) end
        b.crust:SetVertexColor(cool, cool * (0.85 + 0.15 * pos), cool * (0.85 + 0.15 * pos))
        b.crust:SetAlpha((0.2 + 0.75 * pos) * fade)
    end
    for i, p in ipairs(fx.pieces) do
        p.star:Hide(); p.block:Hide(); p.grit:Hide(); p.flame:Hide(); p.lava:Hide()
        if i <= 10 then
            -- A drip off the bottom: hangs and stretches, lets go, falls.
            local u = (now * (0.1 + 0.1 * p.speed) + p.phase) % 1
            local da = math.pi + p.lane * 0.55
            local bx, by = At(da, R + T * 0.45)
            local hang = math.min(u / 0.72, 1)
            local fall = math.max(0, (u - 0.72) / 0.28)
            local reach = T * (0.9 + 3.6 * (0.5 + 0.5 * p.size)) -- how long the strand gets
            if fall == 0 then
                local len = T * 0.7 + (reach - T * 0.7) * hang ^ 1.8
                local w = T * (0.85 + 0.35 * p.size) * (1 - 0.3 * hang)
                Put(p.core, frame, bx, by - len * (0.5 - FLAME_FOOT), w, len)
                p.core:SetVertexColor(1, 0.66, 0.16)
                p.core:SetAlpha(cool)
            else
                -- The drop: rounder, falling faster and faster from where the strand ended.
                local dl = T * (1.3 + 0.5 * p.size)
                local dy = fall * fall * R * 1.6
                Put(p.core, frame, bx, by - reach + dl * (0.5 - FLAME_FOOT) - dy, T * (0.8 + 0.3 * p.size), dl)
                p.core:SetVertexColor(1, 0.66 - 0.5 * fall, 0.16 - 0.14 * fall)
                p.core:SetAlpha((1 - fall * fall) * cool)
            end
            if p.core.SetRotation then p.core:SetRotation(0) end
            -- Where it gathers: a glow at the strand's root, brightest as it lets go.
            Put(p.glow, frame, bx, by, T * (1.4 + 0.8 * hang))
            p.glow:SetVertexColor(1, 0.45, 0.08)
            p.glow:SetAlpha((0.25 + 0.3 * hang) * (1 - fall) * cool)
            fx.bits[i]:Hide()
        else
            p.core:Hide()
            -- A bubble near the top, where the lava's hottest: swells, then pops with a spark.
            local v = (now * (0.22 + 0.25 * p.speed) + p.phase * 0.7) % 1
            local ba = p.lane * 1.0
            local qx, qy = At(ba, R)
            if v < 0.85 then
                local g = v / 0.85
                Put(p.glow, frame, qx, qy, T * (0.4 + 1.2 * g))
                p.glow:SetVertexColor(1, 0.6 + 0.3 * g, 0.15 + 0.25 * g)
                p.glow:SetAlpha((0.35 + 0.45 * g) * cool)
                fx.bits[i]:Hide()
            else
                local k = (v - 0.85) / 0.15
                Put(p.glow, frame, qx, qy, T * (1.6 + 1.5 * k))
                p.glow:SetVertexColor(1, 0.82, 0.4)
                p.glow:SetAlpha((1 - k) * 0.8 * cool)
                Put(fx.bits[i], frame, qx, qy + T * 1.3 * k, T * 1.3 * (1 - k * 0.5))
                if fx.bits[i].SetRotation then fx.bits[i]:SetRotation(k * 2 * p.spin) end
                fx.bits[i]:SetVertexColor(1, 0.9, 0.5)
                fx.bits[i]:SetAlpha((1 - k) * cool)
            end
        end
    end
    -- Heat: a deep red glow behind the ring, slowly pulsing.
    local pulse = 0.5 + 0.3 * math.sin(now * 1.3) + 0.2 * math.sin(now * 2.9)
    Put(fx.glow, frame, 0, 0, R * 2.3 * (0.96 + 0.05 * pulse))
    fx.glow:SetVertexColor(0.9, 0.18, 0.03)
    fx.glow:SetAlpha((0.2 + 0.12 * pulse) * cool)
end

-- Frostbrand: ice crystals sitting round the band, turning slowly and twinkling; snowflakes
-- drifting down through the ring; a cold glow.
function DRAW.frost(frame, now, R, T, warn)
    for i, p in ipairs(fx.pieces) do
        -- Each crystal goes round the ring at its own pace, some the other way.
        local a = now * (0.06 + 0.14 * p.speed) * p.dir + ((i + p.jit * 0.45) / N) * math.pi * 2
        local x, y = At(a, R + T * (0.2 + 0.3 * p.lane))
        local tw = 0.5 + 0.5 * math.sin(now * (2 + p.speed * 3) + i * 2.1)
        local s = T * (0.9 + 0.9 * p.size) * (0.7 + 0.3 * tw)
        Put(p.star, frame, x, y, s)
        p.star:SetVertexColor(0.7, 0.9, 1)
        if p.star.SetRotation then p.star:SetRotation(now * (0.4 + 0.3 * p.speed) * p.spin + i) end
        p.star:SetAlpha(0.35 + 0.65 * tw)
        p.glow:Hide(); p.flame:Hide(); p.lava:Hide(); p.core:Hide(); p.block:Hide(); p.grit:Hide()
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
        -- Each streak's speed, starting point and height come from its head piece's random
        -- values, so the four don't sit at even quarters.
        local head = fx.pieces[streak * 4 + 1]
        local sp = 2.3 + streak * 0.6 + head.speed * 0.6
        local dir = streak % 2 == 0 and 1 or -1
        local a = now * sp * dir + head.phase * math.pi * 2 - seg * 0.16 * dir
        local r = R + T * (-0.6 + streak * 0.55 + head.lane * 0.2)
        local x, y = At(a, r)
        local s = T * (1.4 - seg * 0.28) * gust
        Put(p.glow, frame, x, y, s * 1.6, s * 0.8)
        if p.glow.SetRotation then p.glow:SetRotation(-a) end
        p.glow:SetVertexColor(0.75, 1, 0.95)
        p.glow:SetAlpha((0.7 - seg * 0.16) * gust)
        p.star:Hide(); p.flame:Hide(); p.lava:Hide(); p.core:Hide(); p.block:Hide(); p.grit:Hide(); fx.bits[i]:Hide()
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
    if st.imbue ~= "flame" then HideFlow() end
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
    key = "imbue", name = "Imbue", order = 14.15, since = "1.5.0",
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
                .. "animation: orbiting stones for Rockbiter, bubbling, dripping lava for Flametongue, ice crystals and snow "
                .. "for Frostbrand, and whipping wind for Windfury.",
                MergeTop(TopRow("imbue", "weapon imbue ring", ns.PreviewImbueRing,
                    "Show each imbue in turn. Also /circ imbue."), {
                    general = Box(2, "General", {
                        enabled = Toggle(1, "imbueEnabled", "Show weapon imbue ring",
                            "Show the ring while your weapon has an imbue."),
                        always = Toggle(2, "imbueAlways", "Show for the whole time",
                            "Off: only when you put it on, in its last 30 seconds, and when it fades."),
                        fx = Toggle(3, "imbueFx", "Animations",
                            "Orbiting stones, molten lava, ice and snow, or whipping wind, by imbue."),
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
