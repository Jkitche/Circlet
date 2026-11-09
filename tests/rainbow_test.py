import math, sys
exec(open('fx_test.py').read().split("# Level up: 85% -> next level 20%")[0])
mode = sys.argv[1] if len(sys.argv) > 1 else "render"
if mode == "render":
    lua.execute('CircletDB.xpLevelFxStyle = "rainbow"')
    lua.execute('Slash("levelup")')
    frames = []
    for step in range(200):
        lua.execute('Advance(1/30)')
        if lua.eval('(function() for _, f in ipairs(allFrames) do if f.waves and f._shown then return true end end return false end)()'):
            break
    for t, label in [(0.15,"swirl 0.15s"),(0.3,"swirl 0.45s"),(0.35,"swirl 0.8s"),(0.3,"burst 1.1s"),(0.3,"burst 1.4s"),(0.4,"1.8s"),(0.6,"2.4s done")]:
        lua.execute(f'Advance({t})')
        frames.append(frame_img(label))
    out = Image.new("RGB",(sum(f.width for f in frames), frames[0].height))
    x=0
    for f in frames: out.paste(f,(x,0)); x+=f.width
    out = out.resize((out.width//2, out.height//2))
    out.save('/tmp/rainbow_fx.png')
    # style none -> no effect
    lua.execute('Advance(6); CircletDB.xpLevelFxStyle = "none"; Slash("levelup"); Advance(1.0)')
    print("style none, effect shown:", lua.eval('(function() for _, f in ipairs(allFrames) do if f.waves and f._shown then return true end end return false end)()'))
    lua.execute('Advance(6); CircletDB.xpLevelFxStyle = "gold"; Slash("levelup"); Advance(0.8)')
    print("style gold, effect shown:", lua.eval('(function() for _, f in ipairs(allFrames) do if f.waves and f._shown then return true end end return false end)()'))
errs = lua.eval('ERRORS'); print("ERRORS:", dict(errs) if list(errs.keys()) else "none")
