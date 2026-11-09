import math
from lupa import LuaRuntime
from PIL import Image, ImageDraw, ImageFont
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('''
ERRORS = {}
local function guard(where, fn, ...) local ok, err = pcall(fn, ...); if not ok then local k = where..": "..tostring(err); ERRORS[k] = (ERRORS[k] or 0) + 1 end end
function Fire(event, ...) for _, f in ipairs(allFrames) do if f._events and f._events[event] and f._scripts.OnEvent then guard("OnEvent "..event, f._scripts.OnEvent, f, event, ...) end end end
function Advance(seconds, fps) fps = fps or 30
  for _ = 1, math.floor(seconds * fps) do NOW = NOW + 1 / fps
    local due = {} for i = #pendingTimers, 1, -1 do if pendingTimers[i].at <= NOW then table.insert(due, table.remove(pendingTimers, i)) end end
    for _, t in ipairs(due) do guard("timer", t.fn) end
    for _, f in ipairs(allFrames) do if f._shown and f._scripts.OnUpdate then guard("OnUpdate", f._scripts.OnUpdate, f, 1 / fps) end end
  end end
-- Every visible ring: its lines and its texts (in creation order).
function VisibleRings()
  local rings, seen = {}, {}
  for _, l in ipairs(ALL_LINES) do
    local p = l._parent
    if p and p._shown and not seen[p] then seen[p] = true; table.insert(rings, p) end
  end
  local out = {}
  for _, p in ipairs(rings) do
    local lines, texts = {}, {}
    for _, l in ipairs(ALL_LINES) do if l._parent == p and l._shown and l._x1 then table.insert(lines, l) end end
    for _, f in ipairs(ALL_FS) do if f._parent == p and f._text and f._text ~= "" then table.insert(texts, f) end end
    table.insert(out, { lines = lines, texts = texts })
  end
  return out
end
''')
chunk = lua.eval('function(s) return load(s, "@SideQuest.lua") end')((__import__('subprocess').run(['python3','make_bundle.py']), open('bundle.lua').read())[1])
chunk("Circlet", lua.table())
lua.execute('Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD"); Advance(1)')
LAYER = {"BACKGROUND":0,"BORDER":1,"ARTWORK":2}
big = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
def render_all(label):
    imgs = []
    for ring in lua.eval('VisibleRings()').values():
        W=150; S=3
        im = Image.new("RGB",(W*S,W*S),(50,40,30)); d = ImageDraw.Draw(im)
        items = sorted(((LAYER[l._layer], l._sub, l) for l in ring.lines.values()), key=lambda t:(t[0],t[1]))
        for _,_,l in items:
            x1,y1,x2,y2,T = l._x1,l._y1,l._x2,l._y2,l._t; c = l._c
            dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy) or 1; nx,ny=-dy/L*T/2,dx/L*T/2
            pts=[((W/2+px)*S,(W/2-py)*S) for px,py in [(x1+nx,y1+ny),(x2+nx,y2+ny),(x2-nx,y2-ny),(x1-nx,y1-ny)]]
            d.polygon(pts, fill=(int(c[1]*255),int(c[2]*255),int(c[3]*255)))
        texts = list(ring.texts.values())
        y = im.height/2 - 14*len(texts)
        for f in texts:
            c = f._tc; col = (int(c[1]*255),int(c[2]*255),int(c[3]*255)) if c else (255,255,255)
            t = str(f._text); w = d.textlength(t, font=big); d.text(((im.width-w)/2, y), t, fill=col, font=big); y += 28
        d.text((8,8), label, fill=(230,230,230), font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18))
        imgs.append(im)
    return imgs

shots = []
def shot(label): shots.extend(render_all(label))

# XP: 15 @ 90% -> level-up to 16 @ 13.6% (expect +23.6%)
lua.execute('XP = 900; XPMAX = 1000; Fire("PLAYER_XP_UPDATE", "player"); Advance(8)')
lua.execute('XP = 150; XPMAX = 1100; Fire("PLAYER_XP_UPDATE", "player"); Advance(2.8)'); shot("XP level-up: +23.6%")
lua.execute('Advance(8)')
# Quest 3->5/8 (expect +25.0%), percent objective (no delta)
lua.execute("""
QUEST = { objectives = { { text = "3/8 Screecher Feather", type = "item", numFulfilled = 3, numRequired = 8, finished = false },
                         { text = "Area explored (40%)", type = "progressbar", numFulfilled = 40, numRequired = 100, finished = false } } }
C_QuestLog.GetInfo = function(i) return { questID = 77, title = "Feathers for Grek", level = 15 } end
C_QuestLog.GetQuestObjectives = function(id) return QUEST.objectives end
Fire("QUEST_LOG_UPDATE"); Advance(1)
QUEST.objectives[1].numFulfilled = 5; QUEST.objectives[1].text = "5/8 Screecher Feather"; Fire("QUEST_LOG_UPDATE"); Advance(2.2)""")
shot("quest 3->5/8: +25.0%")
lua.execute('Advance(8); QUEST.objectives[2].numFulfilled = 65; Fire("QUEST_LOG_UPDATE"); Advance(2.2)'); shot("percent objective: no delta")
lua.execute('Advance(8)')
# Skill 141->143/150 (+1.3%)
lua.execute('SetSkill(43, 143); Fire("SKILL_LINES_CHANGED"); Advance(2.2)'); shot("skill: +1.3%")
lua.execute('Advance(8)')
# Rep: +250/6000 (+4.2%), loss -25/3000 (-0.8%), cross-standing +650 into 12000 (+5.4%)
lua.execute('SetRep(72, 3000 + 2400); Fire("UPDATE_FACTION"); Advance(2.2)'); shot("rep: +4.2%")
lua.execute('Advance(8); SetRep(21, 1775); Fire("UPDATE_FACTION"); Advance(2.2)'); shot("rep loss: -0.8%")
lua.execute('Advance(8); SetRep(69, 9000 + 150); Fire("UPDATE_FACTION"); Advance(2.4)'); shot("rep standing up: +5.4%")

out = Image.new("RGB", (sum(i.width for i in shots), max(i.height for i in shots)))
x = 0
for i in shots: out.paste(i, (x, 0)); x += i.width
out = out.resize((out.width * 2 // 3, out.height * 2 // 3))
out.save('/tmp/delta_rings.png')
errs = lua.eval('ERRORS'); print("ERRORS:", dict(errs) if list(errs.keys()) else "none")
