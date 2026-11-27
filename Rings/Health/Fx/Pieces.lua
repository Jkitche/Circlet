-- Circlet: effects on the health & power rings (Rings/Health/Draw.lua draws them each frame).
local ADDON_NAME, ns = ...

local db, SafeCall, Clean, CleanNumber, IsSecret = ns.db, ns.SafeCall, ns.Clean, ns.CleanNumber, ns.IsSecret

-- Shared by the effects' files (Rings/Health/Fx/*.lua), which load in this order: Pieces,
-- Effects, Target, Draw.
ns.HealthFx = ns.HealthFx or {}
local FX = ns.HealthFx

---------------------------------------------------------------------------
-- Health ring effects
---------------------------------------------------------------------------
-- Each one has its own setting, <key>Fx<Name>, on the rings it suits (all on by default):
--
--   Combo      (target)   five pips over the ring for your combo points, popping as they
--                         light, the lot pulsing gold at five (rogues and druids)
--   Mark       (all)      the unit's raid marker (skull, cross, star...) at its top left
--   Aggro      (target)   a red glare round the ring while the target is targeting you
--   Execute    (target)   the ring throbs red-orange below 20% health
--   LowHealth  (yours)    a red heartbeat (lub-dub) below 30% health
--   Death      (all)      dead: the ring cracks and darkens, a faded skull in its middle; your ghost: a
--                         pale glow with wisps drifting up
--   Flare      (yours)    a gold ring bursting outward as combat starts
--   Heal       (yours, target) green sparkles racing up both sides when a heal lands
--   Jolt       (yours, target) the ring jolts on a critical or crushing hit
--   Avoid      (yours, target) a shield on a block, a whoosh round the ring on a dodge,
--                         crossed blades on a parry
--   EnergyTick (yours)    a spark running round the energy band, once per energy tick
--   Rage       (yours)    embers flying off the rage band as rage comes in
--   FullMana   (yours)    a soft shine on the mana band while it's full
--   Skin       (target)   a pelt badge at the top right when the target can be skinned (or
--                         gathered: herbs, ore, parts), from the corpse's tooltip; kinds of
--                         creature seen skinnable before get a faint one while alive
--   Range      (target)   the ring dims while the target's out of range of your main attacks
--   Tapped     (target)   a mob someone else tagged (no XP or loot for you) goes grey, whatever the
--                         color mode, its portrait too
--   Loot       (target)   gold glints round a corpse that still has loot for you, a coin at the right
--   Stance     (you)      your stance, form, aura or stealth as a badge at the bottom right
--   Quest      (target)   a yellow ! at the bottom left when the target is part of one of
--                         your active quests, with the objective's progress (3/10) under it
--
-- What the game hides from addons in combat shapes some of them. Health and power can be
-- hidden: thresholds (20%, 30%, full) are checked by running the hidden percentage through
-- a step curve, whose hidden 0 or 1 goes straight into a texture's SetAlpha (the way the
-- rings fill; see Rings/Health/Hidden.lua), with the pulse on its parent frame. The size of a rage
-- gain can't be read, so embers come with each gain, not by its size. Energy ticks every
-- two seconds; with energy hidden, a tick is any energy change that isn't one of your casts.

local TEX = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\"
local GLOW = TEX .. "GlowRing"       -- a soft band peaking at 0.70 of its half-width
local GLOW_AT = 0.70
local STAR = "Interface\\Cooldown\\star4"
local SOFT = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local SWORDS = "Interface\\CharacterFrame\\UI-StateIcon"

local ON = {
    Combo = { targetHp = true }, Mark = { playerHp = true, targetHp = true, totHp = true, petHp = true },
    Aggro = { targetHp = true }, Execute = { targetHp = true }, LowHealth = { playerHp = true },
    Death = { playerHp = true, targetHp = true, totHp = true, petHp = true }, Flare = { playerHp = true },
    Heal = { playerHp = true, targetHp = true, petHp = true }, Jolt = { playerHp = true, targetHp = true, petHp = true },
    Avoid = { playerHp = true, targetHp = true, petHp = true }, EnergyTick = { playerHp = true }, Rage = { playerHp = true },
    FullMana = { playerHp = true }, Skin = { targetHp = true },
    Quest = { targetHp = true }, Range = { targetHp = true }, Tapped = { targetHp = true },
    Loot = { targetHp = true }, Stance = { playerHp = true },
}
ns.VITALS_FX = ON

local function On(key, name) return ON[name][key] and db[key .. "Fx" .. name] end

-- Badge positions: where each badge sits on its ring, one of eight spots round it, chosen per
-- ring in its options (<key>Pos<Badge>; the defaults are where they've always been). Two badges
-- never share a spot: picking a taken one swaps them (ns.SetBadgeSpot). The top is also where
-- combo points go, and the aura arc sits on whichever side it's set to.
local BADGE_SPOTS = { top = 90, topright = 45, right = 0, bottomright = 315,
                      bottom = 270, bottomleft = 225, left = 180, topleft = 135 }
local BADGE_SPOT_ORDER = { "topleft", "top", "topright", "right", "bottomright", "bottom", "bottomleft", "left" }
local BADGE_SPOT_NAMES = { topleft = "Top left", top = "Top", topright = "Top right", right = "Right",
                           bottomright = "Bottom right", bottom = "Bottom", bottomleft = "Bottom left", left = "Left" }
-- Each badge: its label, what it is, and its default spot on each ring that has it.
local BADGES = {
    Level = { "Level badge", "The level disc (with the elite dragon on it for elites).",
              playerHp = "bottomleft", targetHp = "bottomright", totHp = "bottomright", petHp = "bottomleft" },
    Combat = { "In-combat indicator", "The crossed swords while you're in combat.", playerHp = "topright" },
    Mark = { "Raid marker", "The raid target icon (skull, cross...).",
             playerHp = "topleft", targetHp = "topleft", totHp = "topleft", petHp = "topleft" },
    Stance = { "Stance or form", "Your stance, form, aura or stealth.", playerHp = "bottomright" },
    Skin = { "Skinnable", "The skinning (or herb, ore, parts) badge.", targetHp = "topright" },
    Quest = { "Quest target", "The quest ! and its progress.", targetHp = "bottomleft" },
    Loot = { "Lootable", "The coin on a corpse with loot for you.", targetHp = "right" },
}
local BADGE_ORDER = { "Level", "Combat", "Mark", "Stance", "Skin", "Quest", "Loot" }

-- The spot a badge is at on a ring, and its angle (degrees, 0 = right, counter-clockwise).
local function BadgeSpot(key, badge)
    local b = BADGES[badge]
    local spot = db[key .. "Pos" .. badge]
    if not BADGE_SPOTS[spot] then spot = b and b[key] or "topleft" end
    return spot
end
local function BadgeAngle(key, badge) return BADGE_SPOTS[BadgeSpot(key, badge)] end

-- Moves a badge; whichever was at that spot takes its old one.
local function SetBadgeSpot(key, badge, spot)
    if not BADGE_SPOTS[spot] then return end
    local old = BadgeSpot(key, badge)
    for other, b in pairs(BADGES) do
        if other ~= badge and b[key] and BadgeSpot(key, other) == spot then
            db[key .. "Pos" .. other] = old
        end
    end
    db[key .. "Pos" .. badge] = spot
end

ns.VitalsBadges = { spots = BADGE_SPOTS, spotOrder = BADGE_SPOT_ORDER, spotNames = BADGE_SPOT_NAMES,
                    badges = BADGES, order = BADGE_ORDER, Spot = BadgeSpot, Angle = BadgeAngle, Set = SetBadgeSpot }

-- Event times, by ring key.
local hits = {}   -- key -> { heal = t, jolt = t, block = t, dodge = t, parry = t, flare = t }
local function Mark(key, what) hits[key] = hits[key] or {}; hits[key][what] = GetTime() end
local function Since(key, what) local h = hits[key] return h and h[what] and GetTime() - h[what] or math.huge end
ns.VitalsFxMark = Mark -- tests and previews

---------------------------------------------------------------------------
-- Pieces: textures on a frame over the ring, made when first needed
---------------------------------------------------------------------------
local function Pieces(v, frame)
    if v.fx then return v.fx end
    local fx = { t = {}, frames = {} }
    fx.root = CreateFrame("Frame", nil, frame)
    fx.root:SetAllPoints(frame)
    fx.root:SetFrameLevel(frame:GetFrameLevel() + 6)
    v.fx = fx
    return fx
end

-- A frame of its own (for effects whose alpha is gated by a hidden value: the gate on the
-- texture, the pulse on this frame).
local function Sub(fx, name)
    local f = fx.frames[name]
    if not f then
        f = CreateFrame("Frame", nil, fx.root)
        f:SetAllPoints(fx.root)
        fx.frames[name] = f
    end
    return f
end

local function Tex(fx, name, file, layer, sub, add, parent)
    local t = fx.t[name]
    if not t then
        t = (parent or fx.root):CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
        t:SetTexture(file)
        if add then t:SetBlendMode("ADD") end
        fx.t[name] = t
    end
    t.used = true
    return t
end

local function At(t, frame, x, y, w, h)
    t:ClearAllPoints()
    t:SetPoint("CENTER", frame, "CENTER", x, y)
    t:SetSize(w, h or w)
    t:Show()
end

-- x, y at <deg> degrees (0 = right, counter-clockwise) and radius r.
local function Polar(deg, r) local a = math.rad(deg) return r * math.cos(a), r * math.sin(a) end

-- A glow ring texture sized to sit on a ring of radius r.
local function GlowOn(t, frame, r, x, y) At(t, frame, x or 0, y or 0, 2 * r / GLOW_AT) end

---------------------------------------------------------------------------
-- Hidden thresholds
---------------------------------------------------------------------------
local curves = {}
-- A step curve: <below> under t (a fraction), <above> from t on.
local function Curve(t, below, above)
    local k = t .. ":" .. below .. ":" .. above
    if curves[k] then return curves[k] end
    local scale = ns.VitalsCurves and ns.VitalsCurves.Scale() or 1
    local cv = C_CurveUtil.CreateCurve()
    if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then pcall(cv.SetType, cv, Enum.LuaCurveType.Step) end
    cv:AddPoint(0, below)
    cv:AddPoint(t * scale, above)
    curves[k] = cv
    return cv
end

-- Whether the unit's health is under t: true / false when readable, or the hidden 0/1 (a
-- secret, for SetAlpha), or nil if this client can't tell.
local function HealthUnder(st, t)
    if st.dead then return false end
    if st.hpFrac then return st.hpFrac < t end
    if not (st.unit and type(UnitHealthPercent) == "function" and ns.VitalsCurves and ns.VitalsCurves.Work()) then return nil end
    local ok, v = pcall(UnitHealthPercent, st.unit, false, Curve(t, 1, 0))
    if ok then return v end
end

-- Puts a gate (true/false or a hidden 0/1) on a texture's alpha; false if it's plainly off.
-- A hidden value can't be compared or tested, so it's checked for first and passed on.
local function Gate(t, g)
    if IsSecret(g) then
        if not pcall(t.SetAlpha, t, g) then t:Hide() return false end
        t:Show()
        return true
    end
    if g == true or (type(g) == "number" and g > 0) then
        t:SetAlpha(type(g) == "number" and g or 1)
        t:Show()
        return true
    end
    t:Hide()
    return false
end

-- For the files loaded after this one.
FX.TEX = TEX
FX.GLOW = GLOW
FX.STAR = STAR
FX.SOFT = SOFT
FX.DISC = DISC
FX.SKULL = SKULL
FX.SWORDS = SWORDS
FX.BadgeAngle = BadgeAngle
FX.Since = Since
FX.Tex = Tex
FX.At = At
FX.Polar = Polar
FX.GlowOn = GlowOn
FX.Curve = Curve
FX.HealthUnder = HealthUnder
FX.Gate = Gate
FX.ON = ON
FX.On = On
FX.hits = hits
FX.Mark = Mark
FX.Pieces = Pieces
