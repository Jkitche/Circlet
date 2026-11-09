from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
L='/mnt/user-data/uploads/AddOns/SideQuest/Libs/'
load = lua.eval('function(s, n) local f, e = load(s, "@"..n); if not f then error(e) end; return f end')
for f in ['LibStub/LibStub.lua','CallbackHandler-1.0/CallbackHandler-1.0.lua','AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua']:
    load(open(L+f).read(), f)()
lua.execute('''
OUT = {}
-- stub AceGUI / AceConfigDialog (real ones need the full frame API)
local gui = LibStub:NewLibrary("AceGUI-3.0", 1)
function gui:Create() local w = { shown = false }
  function w:Hide() self.shown = false end; function w:Show() self.shown = true end; function w:IsShown() return self.shown end
  function w:SetTitle(t) self.title = t end; function w:SetStatusText(t) self.status = t end; function w:SetLayout() end; function w:SetWidth() end; function w:SetHeight() end
  return w end
local dlg = LibStub:NewLibrary("AceConfigDialog-3.0", 1)
STATUS = {}; function dlg:GetStatusTable() return STATUS end; function dlg:SetDefaultSize() end; function dlg:Open(app) OPENED = (OPENED or 0) + 1 end
C_AddOns = C_AddOns or {}; C_AddOns.GetAddOnMetadata = function() return "0.24.0" end
PlaySound = function() end
''')
chunk = lua.eval('function(s) return load(s, "@SideQuest.lua") end')((__import__('subprocess').run(['python3','make_bundle.py']), open('bundle.lua').read())[1])
NSX = lua.table()
chunk("Circlet", NSX)
lua.globals().NSX = NSX
lua.execute('function RING_EDITORS_GET(k) return NSX.FindRing(k).edit.get() end')
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); XP = 300; XPMAX = 1000; Fire("PLAYER_ENTERING_WORLD"); Advance(1)
local reg = LibStub("AceConfigRegistry-3.0")
local opts = reg:GetOptionsTable("Circlet", "dialog", "test-1.0")
table.insert(OUT, "registered: " .. tostring(opts ~= nil))
local ok, err = pcall(reg.ValidateOptionsTable, reg, opts, "Circlet")
table.insert(OUT, "validate: " .. tostring(ok) .. " " .. tostring(err))
-- walk every option: call name/get/set/func/disabled
local count = { toggle=0, range=0, select=0, color=0, execute=0 }
local function walk(t, path)
  for k, o in pairs(t.args or {}) do
    local p = path .. "." .. k
    local info = { p }
    if type(o.name) == "function" then o.name(info) end
    if type(o.disabled) == "function" then o.disabled(info) end
    if count[o.type] then count[o.type] = count[o.type] + 1 end
    if o.type == "toggle" then local v = o.get(info); o.set(info, not v); o.set(info, v)
    elseif o.type == "range" then local v = o.get(info); assert(type(v)=="number", p); o.set(info, v)
    elseif o.type == "select" then local v = o.get(info); local vals = type(o.values) == "function" and o.values(info) or o.values; assert(v == nil or vals[v], p .. " value " .. tostring(v)); o.set(info, v)
    elseif o.type == "input" then o.get(info)
    elseif o.type == "color" then local r,g,b = o.get(info); o.set(info, 0.1, 0.2, 0.3); o.set(info, r, g, b)
    elseif o.type == "execute" and not k:match("^defaults$") then GUARD = GUARD; local ok2, e2 = pcall(o.func, info); if not ok2 then table.insert(OUT, "EXEC FAIL " .. p .. ": " .. tostring(e2)) end
    end
    if o.type == "group" then walk(o, p) end
  end
end
walk(opts, "root")
local parts = {} for k, v in pairs(count) do table.insert(parts, k .. "=" .. v) end
table.sort(parts); table.insert(OUT, "counts: " .. table.concat(parts, " "))
Advance(2)

local function tree(t, ind)
  local items = {}
  for k, g in pairs(t.args) do if g.type == "group" and not g.inline then table.insert(items, {g.order or 100, k, g}) end end
  table.sort(items, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
  for _, it in ipairs(items) do
    local hid = type(it[3].hidden) == "function" and it[3].hidden() and " [hidden]" or ""
    table.insert(OUT, ind .. it[2] .. " (" .. it[3].name .. ")" .. hid)
    tree(it[3], ind .. "  ")
  end
end
tree(opts, "")
local xpArgs = opts.args.progress.args.xp.args
table.insert(OUT, "xp boxes: size=" .. xpArgs.size.name .. " position=" .. tostring(xpArgs.position and xpArgs.position.name) .. " _position leftover=" .. tostring(xpArgs.size._position))
-- rotation range + normalize
local rot = xpArgs.size.args.rotation
CircletDB.xpRotation = -90
table.insert(OUT, "rotation min/max " .. rot.min .. "/" .. rot.max .. " get(-90)=" .. rot.get({}))
-- apply look to all
CircletDB.questShape = "arc"; CircletDB.questRotation = 45; CircletDB.questBorder = 4; CircletDB.questSize = 150; CircletDB.totemSize = 50
opts.args.progress.args.quest.args.size.args.applyAll.func({})
table.insert(OUT, "after apply: gatherShape=" .. CircletDB.gatherShape .. " totemRotation=" .. CircletDB.totemRotation .. " pinBorder=" .. CircletDB.pinBorder .. " totemSize kept=" .. CircletDB.totemSize)
-- reset ring
CircletDB.questColors.progress.r = 0; CircletDB.questX = 999; CircletDB.repSize = 222
opts.args.progress.args.quest.args.resetRing.func({})
table.insert(OUT, "after quest reset: shape=" .. CircletDB.questShape .. " rot=" .. CircletDB.questRotation .. " size=" .. CircletDB.questSize .. " r=" .. CircletDB.questColors.progress.r .. " X=" .. CircletDB.questX .. " rep untouched=" .. CircletDB.repSize)
CircletDB.pin2X = 5; CircletDB.pinSize = 33
opts.args.pin.args.resetRing.func({})
table.insert(OUT, "after pin reset: pin2X=" .. tostring(rawget(CircletDB, "pin2X")) .. " pinSize=" .. CircletDB.pinSize .. " pinned kept=" .. tostring(CircletDB.pinned ~= nil))
-- auto edit
for _, d in ipairs(NSX.RINGS) do NSX.SetRingEditing(d.key, false, true) end
Slash(""); Advance(0.5)
STATUS.groups.selected = "progress\001skill"; Advance(0.5)
table.insert(OUT, "skill page: skill editing=" .. tostring(RING_EDITORS_GET("skill")))
STATUS.groups.selected = "professions\001gather"; Advance(0.5)
table.insert(OUT, "gather page: skill=" .. tostring(RING_EDITORS_GET("skill")) .. " gather=" .. tostring(RING_EDITORS_GET("gather")))
STATUS.groups.selected = "general"; Advance(0.5)
table.insert(OUT, "general page: gather=" .. tostring(RING_EDITORS_GET("gather")))
STATUS.groups.selected = "pin"; Advance(0.5); table.insert(OUT, "pin page: pin=" .. tostring(RING_EDITORS_GET("pin")))
Slash(""); Advance(0.5); table.insert(OUT, "window closed: pin=" .. tostring(RING_EDITORS_GET("pin")))
CircletDB.optionsAutoEdit = false; Slash(""); STATUS.groups.selected = "progress\001xp"; Advance(0.5)
table.insert(OUT, "auto off: xp=" .. tostring(RING_EDITORS_GET("xp"))); Slash("")
table.insert(OUT, "tree expanded: " .. tostring(STATUS.groups.groups.progress) .. " width=" .. tostring(STATUS.groups.treewidth))
Circlet_OnAddonCompartmentClick(); table.insert(OUT, "compartment opens: " .. tostring(CircletConfigFrame:IsShown())); Circlet_OnAddonCompartmentClick()
''')
print("\n".join(lua.eval("OUT").values())); print("ERRORS:", dict(lua.eval("ERRORS")))
