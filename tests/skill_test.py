import math, re
from lupa import LuaRuntime
from PIL import Image, ImageDraw, ImageFont
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
ERRORS = {}; SHOWN = {}
local function guard(where, fn, ...) local ok, err = pcall(fn, ...); if not ok then local k = where..": "..tostring(err); ERRORS[k] = (ERRORS[k] or 0) + 1 end end
function Fire(event, ...) for _, f in ipairs(allFrames) do if f._events and f._events[event] and f._scripts.OnEvent then guard("OnEvent "..event, f._scripts.OnEvent, f, event, ...) end end end
function Advance(seconds, fps) fps = fps or 30
  for _ = 1, math.floor(seconds * fps) do NOW = NOW + 1 / fps
    local due = {} for i = #pendingTimers, 1, -1 do if pendingTimers[i].at <= NOW then table.insert(due, table.remove(pendingTimers, i)) end end
    for _, t in ipairs(due) do guard("timer", t.fn) end
    for _, f in ipairs(allFrames) do if f._shown and f._scripts.OnUpdate then guard("OnUpdate", f._scripts.OnUpdate, f, 1 / fps) end end
  end end
''')
chunk = lua.eval('function(s) return load(s, "@SideQuest.lua") end')((__import__('subprocess').run(['python3','make_bundle.py']), open('bundle.lua').read())[1])
chunk("Circlet", lua.table())
lua.execute('Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD"); Advance(1)')
lua.execute('''
function SkillRingParts()
  local ringf
  for _, f in ipairs(ALL_FS) do
    if f._text and tostring(f._text):match("^%d+ / %d+$") then ringf = f._parent end
  end
  if not ringf or not ringf._shown then return nil end
  local lines, texts = {}, {}
  for _, l in ipairs(ALL_LINES) do if l._parent == ringf and l._shown and l._x1 then table.insert(lines, l) end end
  for _, f in ipairs(ALL_FS) do if f._parent == ringf and f._text then table.insert(texts, f) end end
  return lines, texts
end
''')

LAYER = {"BACKGROUND":0,"BORDER":1,"ARTWORK":2}
def find_skill_ring():
    # the frame whose fontstrings include a "/ " rank text
    for f in lua.eval('ALL_FS').values():
        t = f._text
        if t and re.match(r'^\d+ / \d+$', str(t)): return f._parent
    return None
def render(label):
    parts = lua.eval('{SkillRingParts()}')
    W=150; S=3
    im = Image.new("RGB",(W*S,W*S),(50,40,30))
    if parts[1] is None:
        ImageDraw.Draw(im).text((10,10), label + " (hidden)", fill=(230,230,230)); return im
    items=[]
    for l in parts[1].values():
        items.append((LAYER[l._layer], l._sub, l))
    items.sort(key=lambda t:(t[0],t[1]))
    for _,_,l in items:
        x1,y1,x2,y2,T = l._x1,l._y1,l._x2,l._y2,l._t; c = l._c
        dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy) or 1; nx,ny=-dy/L*T/2,dx/L*T/2
        pts=[((W/2+px)*S,(W/2-py)*S) for px,py in [(x1+nx,y1+ny),(x2+nx,y2+ny),(x2-nx,y2-ny),(x1-nx,y1-ny)]]
        ImageDraw.Draw(im).polygon(pts, fill=(int(c[1]*255),int(c[2]*255),int(c[3]*255)))
    d = ImageDraw.Draw(im)
    texts = [(f._text, f._tc) for f in parts[2].values()]
    big = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 24)
    y = im.height/2 - 62
    for t, c in texts:
        col = (int(c[1]*255),int(c[2]*255),int(c[3]*255)) if c else (255,255,255)
        w = d.textlength(str(t), font=big); d.text(((im.width-w)/2, y), str(t), fill=col, font=big); y += 32
    d.text((8,8), label, fill=(230,230,230), font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18))
    return im

imgs = []
# 1) Weapon skill-ups mid-fight -> nothing during combat, then ring after
lua.execute('''IN_COMBAT = true; Fire("PLAYER_REGEN_DISABLED")
SetSkill(43, 142); Fire("SKILL_LINES_CHANGED"); Advance(0.5)
SetSkill(43, 143); Fire("SKILL_LINES_CHANGED"); Advance(0.5)
SetSkill(95, 149); Fire("SKILL_LINES_CHANGED"); Advance(0.5)''')
imgs.append(render("during combat"))
lua.execute('IN_COMBAT = false; Fire("PLAYER_REGEN_ENABLED"); Advance(2.2)')
imgs.append(render("after: Swords +2"))
lua.execute('Advance(2.0)')   # queue moves on to Defense
imgs.append(render("then: Defense +1"))
lua.execute('Advance(6)')
# 2) Mining out of combat
lua.execute('SetSkill(186, 115); Fire("SKILL_LINES_CHANGED"); Advance(2.0)')
imgs.append(render("Mining +3"))
lua.execute('Advance(6)')
# 3) Fishing under a collapsed header
lua.execute('SetSkill(356, 41); Fire("SKILL_LINES_CHANGED"); Advance(2.0)')
imgs.append(render("Fishing (collapsed) +1"))
lua.execute('Advance(6)')
# 4) Cooking hits cap
lua.execute('SetSkill(185, 75); Fire("SKILL_LINES_CHANGED"); Advance(2.0)')
imgs.append(render("Cooking capped"))
lua.execute('Advance(6)')
# 5) Option off for weapons
lua.execute('CircletDB.skillWeapons = false; SetSkill(43, 144); Fire("SKILL_LINES_CHANGED"); Advance(2.0)')
imgs.append(render("weapons off"))
lua.execute('CircletDB.skillWeapons = true; Advance(6); SlashCmdList.CIRCLET("skill"); Advance(12)')

out = Image.new("RGB", (sum(i.width for i in imgs), max(i.height for i in imgs)))
x = 0
for i in imgs: out.paste(i, (x, 0)); x += i.width
out.save('/tmp/skill_rings.png')
errs = lua.eval('ERRORS')
print("ERRORS:", dict(errs) if list(errs.keys()) else "none")
