import math
exec(open('fx_test.py').read().split("# Level up: 85% -> next level 20%")[0])
from PIL import Image, ImageDraw, ImageFont
lua.execute('''
function ExclaimFrame() for _, f in ipairs(allFrames) do if f.icon and f.glow and f.ring ~= nil then return f end end
  for _, f in ipairs(allFrames) do if f.icon and f.glow and not f.waves then return f end end end
function QuestRingFrame() for _, f in ipairs(ALL_FS) do if f._text == "Complete!" or tostring(f._text or ""):match("^%d+ / %d+$") then return f._parent end end end
function QuestRingParts()
  local ring = QuestRingFrame(); local lines, texts = {}, {}
  if not ring then return lines, texts end
  for _, l in ipairs(ALL_LINES) do if l._parent == ring and l._shown and l._x1 then table.insert(lines, l) end end
  for _, f in ipairs(ALL_FS) do if f._parent == ring and f._text and f._text ~= "" then table.insert(texts, f) end end
  return lines, texts
end
function QuestRingUp() local f = QuestRingFrame(); return f and f._shown and f._alpha > 0.05 end
''')
bigfont = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 120)
small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
def render(label):
    W=200; S=2
    im = Image.new("RGBA",(W*S,W*S),(40,32,26,255))
    parts = lua.eval('{QuestRingParts()}')
    for l in parts[1].values():
        if True:
            x1,y1,x2,y2,T = l._x1,l._y1,l._x2,l._y2,l._t; c = l._c
            dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy) or 1; nx,ny=-dy/L*T/2,dx/L*T/2
            cy0 = W*0.5
            pts=[((W/2+px)*S,(cy0-py)*S) for px,py in [(x1+nx,y1+ny),(x2+nx,y2+ny),(x2-nx,y2-ny),(x1-nx,y1-ny)]]
            ImageDraw.Draw(im).polygon(pts, fill=(int(c[1]*255),int(c[2]*255),int(c[3]*255),255))
    ex = lua.eval('ExclaimFrame()')
    if ex._shown:
        px, py = ex._pt.x, ex._pt.y
        cx, cy = (W/2+px)*S, (W*0.5-py)*S
        g = ex.glow; gs = (g._w or 0)*S; ga = g._alpha or 0
        ov = Image.new("RGBA", im.size, (0,0,0,0)); od = ImageDraw.Draw(ov)
        od.ellipse([cx-gs/2, cy-gs/2, cx+gs/2, cy+gs/2], fill=(255,210,50,int(110*ga)))
        im = Image.alpha_composite(im, ov)
        ic = ex.icon; size = (ic._w or 0)*S; a = ic._alpha if ic._alpha is not None else 1
        if size > 2:
            glyph = Image.new("RGBA",(200,200),(0,0,0,0)); gd = ImageDraw.Draw(glyph)
            gd.text((100,100), "!", font=bigfont, fill=(255,215,40,int(255*a)), anchor="mm", stroke_width=4, stroke_fill=(90,50,0,int(255*a)))
            glyph = glyph.rotate(math.degrees(ic._rot or 0), resample=Image.BICUBIC).resize((max(1,int(size)),max(1,int(size))))
            im.alpha_composite(glyph, (int(cx-size/2), int(cy-size/2)))
    d = ImageDraw.Draw(im)
    texts = list(parts[2].values())
    y = W*0.5*S - 14*len(texts)
    for f in texts:
        c = f._tc; col = (int(c[1]*255),int(c[2]*255),int(c[3]*255)) if c else (255,255,255)
        t = str(f._text); w = d.textlength(t, font=small); d.text(((im.width-w)/2, y), t, fill=col, font=small); y += 26
    ImageDraw.Draw(im).text((8,8), label, fill=(230,230,230), font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18))
    return im.convert("RGB")

lua.execute('''
QUEST = { objectives = { { text = "8/10 Sunscale Screecher slain", type = "monster", numFulfilled = 8, numRequired = 10, finished = false } } }
C_QuestLog.GetInfo = function(i) return { questID = 88, title = "Raptor Thieves", level = 15 } end
C_QuestLog.GetQuestObjectives = function(id) return QUEST.objectives end
function SetObj(n) local o = QUEST.objectives[1]; o.numFulfilled = n; o.text = n .. "/10 Sunscale Screecher slain"; o.finished = n >= 10 end
Fire("QUEST_LOG_UPDATE"); Advance(1)
''')
# 1) ordinary progress: no "!"
lua.execute('SetObj(9); Fire("QUEST_LOG_UPDATE"); Advance(2.0)')
print("progress 8->9, '!' shown:", lua.eval('ExclaimFrame()._shown'))
lua.execute('Advance(8)')
# 2) completion: "!" plays; capture frames
lua.execute('SetObj(10); Fire("QUEST_LOG_UPDATE")')
frames = []
start = None
for i in range(1, 30*8):
    lua.execute('Advance(1/30)')
    if start is None and lua.eval('ExclaimFrame()._shown'): start = i/30
    if start is not None: break
for dt, label in [(0.1,"pop 0.1s"),(0.12,"overshoot 0.22s"),(0.25,"wiggle 0.47s"),(0.4,"bob 0.87s"),(0.6,"bob 1.5s"),(0.45,"exit 1.95s")]:
    lua.execute(f'Advance({dt})')
    frames.append(render(label))
ex_end = None; ring_down = None
t = start + sum([0.1,0.12,0.25,0.4,0.6,0.45])
for i in range(1, 30*8):
    lua.execute('Advance(1/30)'); t += 1/30
    if ex_end is None and not lua.eval('ExclaimFrame()._shown'): ex_end = t
    if ring_down is None and not lua.eval('QuestRingUp()'): ring_down = t
print(f"'!' ran {ex_end - start:.2f}s (fill landed after {start:.2f}s) | ring stayed up until after the '!': {ring_down is None or ring_down >= ex_end}")
# 3) option off
lua.execute('Advance(8); SetObj(5); Fire("QUEST_LOG_UPDATE"); Advance(6); CircletDB.questCompleteFx = false; SetObj(10); Fire("QUEST_LOG_UPDATE"); Advance(2.5)')
print("option off, '!' shown:", lua.eval('ExclaimFrame()._shown'))
lua.execute('CircletDB.questCompleteFx = true; Advance(8); Slash("complete"); Advance(2.0)')
print("/circ complete, '!' shown:", lua.eval('ExclaimFrame()._shown'))
print('frame levels: ring =', lua.eval('QuestRingFrame():GetFrameLevel()'), '| "!" =', lua.eval('ExclaimFrame():GetFrameLevel()'), '| same strata:', lua.eval('QuestRingFrame():GetFrameStrata() == ExclaimFrame():GetFrameStrata()'))
out = Image.new("RGB",(sum(f.width for f in frames), frames[0].height))
x=0
for f in frames: out.paste(f,(x,0)); x+=f.width
out = out.resize((out.width*3//5, out.height*3//5))
out.save('/tmp/exclaim.png')
errs = lua.eval('ERRORS'); print("ERRORS:", dict(errs) if list(errs.keys()) else "none")
