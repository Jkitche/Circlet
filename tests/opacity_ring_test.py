from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
lua.execute('local cf = CreateFrame; CreateFrame = function(k, n, p, t) local f = cf(k, n, p, t); f._parent = p; return f end')
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
chunk = lua.eval('function(s) return load(s, "@SideQuest.lua") end')((__import__('subprocess').run(['python3','make_bundle.py']), open('bundle.lua').read())[1])
chunk("Circlet", lua.table())
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); XP = 300; XPMAX = 1000; Fire("PLAYER_ENTERING_WORLD"); Advance(1)
OUT = {}
CircletDB.questOpacity = 40; CircletDB.xpOpacity = 70
Slash("edit"); Advance(1)
for _, f in ipairs(allFrames) do
  if f.editHint then
    local p = f._parent
    table.insert(OUT, string.format("ring a=%.2f holderAlpha=%s holder~=UIParent=%s", f._alpha, tostring(p and p._alpha), tostring(p ~= UIParent)))
  end
end
CircletDB.questOpacity = 100; Advance(0.1)
for _, f in ipairs(allFrames) do if f.editHint then table.insert(OUT, "after: " .. tostring(f._parent and f._parent._alpha)) end end
Slash("edit"); Slash("complete"); Advance(3)
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
