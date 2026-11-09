import math
exec(open('fx_test.py').read().split("# Level up: 85% -> next level 20%")[0])
from PIL import Image, ImageDraw, ImageFont
lua.execute('''
function SkillParts()
  local ring
  for _, f in ipairs(ALL_FS) do
    local t = tostring(f._text or "")
    if (t:match("^%d+ / %d+$")) and f._parent._shown then ring = f._parent end
  end
  if not ring then return nil end
  local ringLines, iconLines, texts, holder = {}, {}, {}, nil
  for _, f in ipairs(allFrames) do if f.glyphLines and f._shown then holder = f end end
  for _, l in ipairs(ALL_LINES) do
    if l._parent == ring and l._shown and l._x1 then table.insert(ringLines, l) end
    if holder and l._parent == holder and l._shown and l._x1 then table.insert(iconLines, l) end
  end
  for _, f in ipairs(ALL_FS) do if f._parent == ring and f._text and f._text ~= "" then table.insert(texts, f) end end
  return { ring = ringLines, icon = iconLines, texts = texts, holder = holder }
end
''')
small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20)
def poly(im, l, alpha, W, S):
    x1,y1,x2,y2,T = l._x1,l._y1,l._x2,l._y2,l._t; c = l._c
    dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy) or 1; nx,ny=-dy/L*T/2,dx/L*T/2
    pts=[((W/2+px)*S,(W/2-py)*S) for px,py in [(x1+nx,y1+ny),(x2+nx,y2+ny),(x2-nx,y2-ny),(x1-nx,y1-ny)]]
    ov = Image.new("RGBA", im.size, (0,0,0,0)); ImageDraw.Draw(ov).polygon(pts, fill=(int(c[1]*255),int(c[2]*255),int(c[3]*255),int(255*alpha)))
    return Image.alpha_composite(im, ov)
def render(label):
    W=150; S=2
    im = Image.new("RGBA",(W*S,W*S),(40,32,26,255))
    parts = lua.eval('SkillParts()')
    if parts is None:
        ImageDraw.Draw(im).text((8,8), label + " (hidden)", fill=(230,230,230)); return im.convert("RGB")
    h = parts.holder
    if h is not None:
        g = h.glow; ga = (g._alpha or 0) * (h._alpha or 1); gs = (g._w or 0)*S
        if ga > 0.01:
            vc = g._vc or [0,1,0.8,0.2]
            ov = Image.new("RGBA", im.size, (0,0,0,0)); od = ImageDraw.Draw(ov)
            cx = cy = W/2*S
            od.ellipse([cx-gs/2, cy-gs/2, cx+gs/2, cy+gs/2], fill=(int(vc[1]*255),int(vc[2]*255),int(vc[3]*255),int(120*min(1,ga))))
            im = Image.alpha_composite(im, ov)
        for l in parts.icon.values(): im = poly(im, l, h._alpha or 1, W, S)
    for l in parts.ring.values(): im = poly(im, l, 1, W, S)
    d = ImageDraw.Draw(im)
    texts = list(parts.texts.values())
    y = W/2*S - 13*len(texts)
    for f in texts:
        c = f._tc; col = (int(c[1]*255),int(c[2]*255),int(c[3]*255)) if c else (255,255,255)
        t = str(f._text); w = d.textlength(t, font=small); d.text(((im.width-w)/2, y), t, fill=col, font=small, stroke_width=2, stroke_fill=(0,0,0)); y += 25
    d.text((6,6), label, fill=(230,230,230), font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16))
    return im.convert("RGB")


shots = []
lua.execute('table.insert(SKILL_LINES, { skillID = 356, name = "Fishing", rank = 40, maxRank = 150, skillLineCategoryID = 9 }); Fire("SKILL_LINES_CHANGED"); Advance(1)')
lua.execute('SetSkill(43, 143); Fire("SKILL_LINES_CHANGED"); Advance(1.6)'); shots.append(render("Swords +2 (80%)"))
lua.execute('Advance(8); SetSkill(186, 115); Fire("SKILL_LINES_CHANGED"); Advance(1.6)'); shots.append(render("Mining +3 (80%)"))
lua.execute('Advance(8); SetSkill(356, 41); Fire("SKILL_LINES_CHANGED"); Advance(1.6)'); shots.append(render("Fishing +1 (80%)"))
lua.execute('Advance(8); CircletDB.skillIconAlpha = 30; SetSkill(43, 144); Fire("SKILL_LINES_CHANGED"); Advance(1.6)'); shots.append(render("Swords at 30%"))
lua.execute('Advance(8); CircletDB.skillIconAlpha = 80; SetSkill(185, 75); Fire("SKILL_LINES_CHANGED"); Advance(1.15+0.2+1.6)'); shots.append(render("capped, settled (80%)"))
out = Image.new("RGB",(sum(s.width for s in shots), shots[0].height)); x=0
for s in shots: out.paste(s,(x,0)); x+=s.width
out = out.resize((out.width*2//3, out.height*2//3)); out.save('/tmp/icon_opacity.png')
errs = lua.eval('ERRORS'); print("ERRORS:", dict(errs) if list(errs.keys()) else "none")
