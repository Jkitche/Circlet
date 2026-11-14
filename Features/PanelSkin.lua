-- Circlet: The look shared by Circlet's own windows (the setup wizard, the session summary).
local ADDON_NAME, ns = ...

local NewRingLayer, DrawArc, XP_SEGMENTS, TRACK = ns.NewRingLayer, ns.DrawArc, ns.XP_SEGMENTS, ns.TRACK

---------------------------------------------------------------------------
-- Panel skin
---------------------------------------------------------------------------
-- ns.SkinPanel(frame, opts) dresses a plain frame as a Circlet window:
--   * a deep blue-black background shading lighter toward the top, a soft drop shadow
--     around it and a thin gold border (with a dark line just inside);
--   * a header band (opts.header px, default 52) with a gold accent line under it that
--     fades out toward both ends, and the Circlet logo on its left: four short arcs in the
--     addon's colors, slowly turning, drawn with the rings' own lines;
--   * a faint rule above the footer (opts.footer px from the bottom; none if nil);
--   * a quick fade-and-grow when it opens.
-- Returns the skin's parts ({ logo = frame, ... }) for anything that wants to sit on them.
-- Helpers for the windows' contents: ns.SkinGradient(texture, orientation, r,g,b,a, r2,g2,b2,a2)
-- and ns.SkinRule(parent, width, r,g,b,a) (a line fading out at both ends).

local GOLD = { r = 0.95, g = 0.78, b = 0.30 }
ns.SKIN_GOLD = GOLD
-- The logo's arcs: gold, sky blue, green, violet (the welcome animation's colors).
local LOGO = {
    { r = 1.00, g = 0.82, b = 0.25 }, { r = 0.45, g = 0.75, b = 1.00 },
    { r = 0.40, g = 0.90, b = 0.45 }, { r = 0.75, g = 0.50, b = 1.00 },
}

-- A gradient on a texture, whichever API this client has (no-op if neither).
local function Gradient(tex, orient, r, g, b, a, r2, g2, b2, a2)
    tex:SetColorTexture(1, 1, 1, 1)
    if CreateColor and tex.SetGradient then
        if pcall(tex.SetGradient, tex, orient, CreateColor(r, g, b, a), CreateColor(r2, g2, b2, a2)) then return end
    end
    if tex.SetGradientAlpha then pcall(tex.SetGradientAlpha, tex, orient, r, g, b, a, r2, g2, b2, a2) end
end
ns.SkinGradient = Gradient

local function Solid(parent, layer, sub, r, g, b, a)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetColorTexture(r, g, b, a)
    return t
end

-- A horizontal line `width` wide that fades out at both ends (two halves meeting in the middle).
local function Rule(parent, width, r, g, b, a, layer)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 1)
    f.left = f:CreateTexture(nil, layer or "ARTWORK")
    f.left:SetPoint("TOPLEFT"); f.left:SetPoint("BOTTOMRIGHT", f, "BOTTOM", 0, 0)
    Gradient(f.left, "HORIZONTAL", r, g, b, 0, r, g, b, a)
    f.right = f:CreateTexture(nil, layer or "ARTWORK")
    f.right:SetPoint("TOPLEFT", f, "TOP", 0, 0); f.right:SetPoint("BOTTOMRIGHT")
    Gradient(f.right, "HORIZONTAL", r, g, b, a, r, g, b, 0)
    return f
end
ns.SkinRule = Rule

-- The Circlet logo: four arcs with gaps between them, turning slowly while it's visible.
local function Logo(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local geom = { R = size / 2 - 3, T = 4, step = 2 * math.pi / XP_SEGMENTS, start = 0 }
    f.track = NewRingLayer("BACKGROUND", 1, TRACK, 0.9, f)
    f.arcs = {}
    for i, c in ipairs(LOGO) do f.arcs[i] = NewRingLayer("ARTWORK", 0, c, 1, f) end
    local function Draw(turn)
        geom.start = turn
        DrawArc(f.track, 0, 1, f, geom, true)
        for i, layer in ipairs(f.arcs) do
            local from = (i - 1) / 4 + 0.02
            DrawArc(layer, from, from + 0.19, f, geom)
        end
    end
    local t = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        t = t + (elapsed or 0)
        Draw((t * 0.06) % 1) -- one turn every ~17 seconds
    end)
    Draw(0)
    return f
end
ns.SkinLogo = Logo

-- Edge textures around a frame: thickness `w`, `out` px outside its edges (negative = inside).
local function Edges(frame, layer, sub, w, out, r, g, b, a)
    local e = {}
    e.top = Solid(frame, layer, sub, r, g, b, a)
    e.top:SetPoint("TOPLEFT", frame, "TOPLEFT", -out, out); e.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", out, out)
    e.top:SetHeight(w)
    e.bottom = Solid(frame, layer, sub, r, g, b, a)
    e.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -out, -out); e.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", out, -out)
    e.bottom:SetHeight(w)
    e.left = Solid(frame, layer, sub, r, g, b, a)
    e.left:SetPoint("TOPLEFT", frame, "TOPLEFT", -out, out); e.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -out, -out)
    e.left:SetWidth(w)
    e.right = Solid(frame, layer, sub, r, g, b, a)
    e.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", out, out); e.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", out, -out)
    e.right:SetWidth(w)
    return e
end

ns.SkinEdges = Edges

local function SkinPanel(frame, opts)
    opts = opts or {}
    local header = opts.header or 52
    local skin = {}
    if frame.SetBackdrop then frame:SetBackdrop(nil) end

    -- Drop shadow: a few soft dark bands just outside the edges.
    for i, a in ipairs({ 0.35, 0.22, 0.12, 0.05 }) do Edges(frame, "BACKGROUND", -8, 2, i * 2, 0, 0, 0, a) end
    -- Background: deep blue-black, lighter toward the top.
    skin.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    skin.bg:SetAllPoints()
    Gradient(skin.bg, "VERTICAL", 0.025, 0.025, 0.04, 0.97, 0.07, 0.07, 0.10, 0.97)
    -- Header band, darker and warmer, fading into the body.
    skin.header = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    skin.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    skin.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    skin.header:SetHeight(header)
    Gradient(skin.header, "VERTICAL", 0.10, 0.08, 0.03, 0.0, 0.16, 0.12, 0.04, 0.85)
    -- Borders: gold outside, a dark line inside it.
    skin.border = Edges(frame, "BORDER", 1, 1, 0, GOLD.r, GOLD.g, GOLD.b, 0.75)
    skin.inner = Edges(frame, "BORDER", 0, 1, -1, 0, 0, 0, 0.8)
    -- The accent line under the header, and the footer rule.
    skin.accent = Rule(frame, 10, GOLD.r, GOLD.g, GOLD.b, 0.9)
    skin.accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -header)
    skin.accent:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -header)
    if opts.footer then
        skin.footer = Rule(frame, 10, 1, 1, 1, 0.12)
        skin.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, opts.footer)
        skin.footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, opts.footer)
    end
    -- The logo, in the header's left corner.
    skin.logo = Logo(frame, header - 16)
    skin.logo:SetPoint("LEFT", frame, "TOPLEFT", 14, -header / 2)

    -- Opening: fade in while growing slightly from 96%.
    if frame.CreateAnimationGroup then
        local ok, ag = pcall(frame.CreateAnimationGroup, frame)
        if ok and ag and ag.CreateAnimation then
            local fade = ag:CreateAnimation("Alpha")
            pcall(fade.SetFromAlpha, fade, 0); pcall(fade.SetToAlpha, fade, 1); pcall(fade.SetDuration, fade, 0.18)
            local grow = ag:CreateAnimation("Scale")
            if not pcall(grow.SetScaleFrom, grow, 0.96, 0.96) then pcall(grow.SetFromScale, grow, 0.96, 0.96) end
            if not pcall(grow.SetScaleTo, grow, 1, 1) then pcall(grow.SetToScale, grow, 1, 1) end
            pcall(grow.SetDuration, grow, 0.18)
            if grow.SetSmoothing then pcall(grow.SetSmoothing, grow, "OUT") end
            frame:HookScript("OnShow", function() pcall(ag.Play, ag) end)
            skin.open = ag
        end
    end
    return skin
end
ns.SkinPanel = SkinPanel
