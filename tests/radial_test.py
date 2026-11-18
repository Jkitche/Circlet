"""Radial menus: making menus and slices, the key bindings, the secure snippet's slice pick
(run here in a sandbox standing in for the game's secure environment), the ring you see
agreeing with it, changes in combat waiting for it to end, and the options pages."""
import os, subprocess, sys
from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open('mock.lua').read())
s = open('liveedit_test.py').read()
exec(s[s.index("lua.execute('''\nUIParent._w"):s.index("chunk = lua.eval")])
L = '../Libs/'
load = lua.eval('function(s, n) local f, e = load(s, "@"..n); if not f then error(e) end; return f end')
for f in ['LibStub/LibStub.lua', 'CallbackHandler-1.0/CallbackHandler-1.0.lua',
          'AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua']:
    load(open(L + f).read(), f)()
lua.execute('''
OUT = {}
local function out(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end table.insert(OUT, table.concat(t, " ")) end
_G.out = out
-- stub AceGUI / AceConfigDialog (the real ones need the full frame API)
local gui = LibStub:NewLibrary("AceGUI-3.0", 1)
function gui:Create() local w = { shown = false }
  function w:Hide() self.shown = false end; function w:Show() self.shown = true end; function w:IsShown() return self.shown end
  function w:SetTitle() end; function w:SetStatusText() end; function w:SetLayout() end; function w:SetWidth() end; function w:SetHeight() end
  return w end
local dlg = LibStub:NewLibrary("AceConfigDialog-3.0", 1)
STATUS = {}; function dlg:GetStatusTable() return STATUS end; function dlg:SetDefaultSize() end
function dlg:Open() end; function dlg:SelectGroup(app, ...) SELECTED = table.concat({ ... }, ".") end
C_AddOns = C_AddOns or {}; C_AddOns.GetAddOnMetadata = function() return "1.4.0" end
PlaySound = function() end

-- Secure frames: attributes, clicks, wrapped scripts and frame refs.
RegionMethods.SetAttribute = function(s, k, v) s._attr = s._attr or {}; s._attr[k] = v end
RegionMethods.GetAttribute = function(s, k) return s._attr and s._attr[k] end
RegionMethods.SetFrameRef = function(s, k, f) s._refs = s._refs or {}; s._refs[k] = f end
RegionMethods.WrapScript = function(s, frame, script, pre) frame._wrap = { header = s, pre = pre } end
RegionMethods.GetName = function(s) return s._name end
local CF = CreateFrame
function CreateFrame(kind, name, parent, template)
  local f = CF(kind, name, parent, template); f._name = name; f._template = template; return f end
BINDINGS = {}
function SetOverrideBindingClick(owner, prio, key, button, mouse) BINDINGS[key] = button end
function ClearOverrideBindings(owner) BINDINGS = {} end
SPELLS = { Frostbolt = 135846, Blink = 135736 }
C_Spell = { GetSpellInfo = function(v) if SPELLS[v] then return { name = v } end end,
            GetSpellTexture = function(v) return SPELLS[v] end }
C_Item = { GetItemInfoInstant = function(v) if v == "item:6948" then return 6948, "", "", "", 134414 end end,
           GetItemNameByID = function(id) if id == 6948 then return "Hearthstone" end end }
function GetNumMacros() return 1, 1 end
-- Cooldowns: numbers out of combat; with DURATIONS set, the game's duration objects.
SPELL_CD = { Frostbolt = { 995, 8 } }
function GetSpellCooldown(v) local c = SPELL_CD[v]; if c then return c[1], c[2], 1 end return 0, 0, 1 end
C_Container = { GetItemCooldown = function(id) if id == 6948 then return 400, 1800, 1 end return 0, 0, 1 end }
function GetMacroSpell(v) if v == "Taunt" then return "Blink" end end
RegionMethods.SetCooldown = function(s, st, d) s._cd = st .. "/" .. d end
RegionMethods.SetCooldownFromDurationObject = function(s, dur) s._cd = "duration " .. dur.name end
RegionMethods.Clear = function(s) s._cd = nil end
function CooldownState()
  local t = {}
  for i, cd in ipairs(NSX.Radial.Cooldowns()) do
    if i <= 5 then table.insert(t, i .. "=" .. (cd:IsShown() and tostring(cd._cd) or "-")) end
  end
  return table.concat(t, " ")
end
MAX_ACCOUNT_MACROS = 120
function GetMacroInfo(i) if i == 1 then return "Mount", 132261 elseif i == 121 or i == "Taunt" then return "Taunt", 132270 end end

-- The secure environment, in miniature: handles are the frames themselves, the mouse
-- position is normalized to the full-screen tracker, and the snippet runs sandboxed.
MOUSE = { 0.5, 0.5 }
function SecureClick(button, down)
  local w = button._wrap
  local owner = { GetFrameRef = function(_, k)
    local t = w.header._refs[k]
    return { GetMousePosition = function() return MOUSE[1], MOUSE[2] end,
             GetWidth = function() return UIParent._w end, GetHeight = function() return UIParent._h end }
  end }
  local env = { owner = owner, math = math }
  local fn = assert(load("local self, button, down = ...\\n" .. w.pre, "snippet", "t", env))
  if button._scripts.PreClick then button._scripts.PreClick(button, "LeftButton", down) end
  local r = fn(button, "LeftButton", down)
  if r == false then return nil end
  return button:GetAttribute("type")
end
-- What the button actually uses, read the way the game's secure button reads it: a key
-- clicks it as mouse button 1, and "spell1" (say) wins over "spell".
function Resolved(button, name)
  local v = button:GetAttribute(name .. "1")
  if v == nil then v = button:GetAttribute("*" .. name .. "1") end
  if v == nil then v = button:GetAttribute(name) end
  return v
end
-- Cursor at a normalized screen position, for the ring you see (UIParent scale 0.8 in the mock).
function Point(x, y)
  MOUSE = { x, y }
  CURSOR_X, CURSOR_Y = x * UIParent._w * 0.8, y * UIParent._h * 0.8
end
''')
chunk = lua.eval('function(s) return load(s, "@Circlet.lua") end')(
    (subprocess.run([sys.executable, 'make_bundle.py']), open('bundle.lua').read())[1])
NSX = lua.table()
chunk("Circlet", NSX)
lua.globals().NSX = NSX
lua.execute('''
Fire("ADDON_LOADED", "Circlet"); Fire("PLAYER_ENTERING_WORLD"); Advance(1)
local R = NSX.Radial
local db = CircletDB

-- A menu with five slices, one of each kind.
local i = R.NewMenu("  Fun  ")
out("menu", i, db.radialMenus[1].name, "slices", #db.radialMenus[1].slices)
for _ = 1, 5 do R.AddSlice(1) end
local sl = db.radialMenus[1].slices
sl[1].kind, sl[1].value = "spell", "Frostbolt"
sl[2].kind, sl[2].value = "item", "6948"
sl[3].kind, sl[3].value = "emote", "wave"
sl[4].kind, sl[4].value = "macro", "Taunt"
sl[5].kind, sl[5].value = "text", "/wink\\n/say hi"
R.SetKey(1, "CTRL-Q")
out("binding CTRL-Q ->", BINDINGS["CTRL-Q"])
for j = 1, 5 do out("look", j, R.SliceLook(sl[j])) end
for j = 1, 5 do out("action", j, R.SliceAction(sl[j])) end
local b = R.Buttons[1]
out("button", b:GetName(), "n", b:GetAttribute("n"), "dz", b:GetAttribute("dz"), "pressAndHold", b:GetAttribute("pressAndHoldAction"))
out("attrs 2", b:GetAttribute("slice-2-type"), b:GetAttribute("slice-2-item"), "3", b:GetAttribute("slice-3-type"), b:GetAttribute("slice-3-macrotext"))
out("no button-1 attributes:", tostring(b:GetAttribute("spell1")), tostring(b:GetAttribute("item1")), tostring(b:GetAttribute("type1")))

-- Press at the centre, let go in each direction: the secure pick and the ring's light agree.
local function Try(label, x, y)
  Point(0.5, 0.5)
  local downType = SecureClick(b, true)
  local shown = _G.CircletRadialView and CircletRadialView:IsShown()
  Point(x, y)
  Advance(0.05)
  local lit = R.HoveredSlice()
  local arc = R.LitArc()
  local t = SecureClick(b, false)
  out(label, "down:", tostring(downType), "shown:", tostring(shown), "lit:", tostring(lit), "arc:", arc,
      "-> type", tostring(t),
      "spell", tostring(Resolved(b, "spell")), "item", tostring(Resolved(b, "item")),
      "macro", tostring(Resolved(b, "macro")), "text", tostring(Resolved(b, "macrotext")),
      "hidden after:", tostring(not CircletRadialView:IsShown()))
end
Try("up", 0.5, 0.7)
Try("right-up", 0.58, 0.55)
Try("right-down", 0.56, 0.4)
Try("left-down", 0.44, 0.4)
Try("left-up", 0.42, 0.55)
Try("middle", 0.51, 0.505)

-- Cooldowns on the icons: a spell and an item on cooldown, an emote, a macro whose spell
-- isn't, and macro text (none). Then in combat, through the game's duration objects.
Point(0.5, 0.5)
SecureClick(b, true)
out("cooldowns", CooldownState())
SPELL_CD.Blink = { 1000, 15 }
Advance(0.3)
out("Blink starts while open", CooldownState())
C_Spell.GetSpellCooldownDuration = function(v) if v == "Frostbolt" then return { name = "Frostbolt" } end end
Advance(0.3)
out("duration objects", CooldownState())
C_Spell.GetSpellCooldownDuration = nil
SPELL_CD.Blink = nil
SecureClick(b, false)

-- Reorder and remove.
R.MoveSlice(1, 1, 1)
out("after move", sl[1].kind, sl[2].kind, "slice 1", b:GetAttribute("slice-1-type"), b:GetAttribute("slice-1-item"))
R.RemoveSlice(1, 5)
out("after remove", #sl, "n", b:GetAttribute("n"), "slice 5", tostring(b:GetAttribute("slice-5-type")))

-- In combat: changes wait for combat to end.
IN_COMBAT = true
R.AddSlice(1)
out("in combat: slices", #sl, "button n", b:GetAttribute("n"))
IN_COMBAT = false
Fire("PLAYER_REGEN_ENABLED")
out("after combat: button n", b:GetAttribute("n"))

-- A second menu taking the first one's key.
R.NewMenu("")
R.SetKey(2, "CTRL-Q")
out("menu 2", db.radialMenus[2].name, "key1", tostring(db.radialMenus[1].key), "binding", BINDINGS["CTRL-Q"])
R.DeleteMenu(2)
out("after delete: menus", #db.radialMenus, "binding", tostring(BINDINGS["CTRL-Q"]), "button 2 n", R.Buttons[2]:GetAttribute("n"))

-- Options pages.
local reg = LibStub("AceConfigRegistry-3.0")
local opts = reg:GetOptionsTable("Circlet", "dialog", "test-1.0")
local ok, err = pcall(reg.ValidateOptionsTable, reg, opts, "Circlet")
out("validate", ok, err)
local radial = opts.args.radial
out("radial page", radial.name, "menu page", radial.args.menu1 and radial.args.menu1.name())
local slices = radial.args.menu1.args.slices.args
out("slice 1 value name", slices.value1.name(), "hidden", tostring(slices.value1.hidden()))
slices.kind2.set({}, "emote")
out("slice 2 now", sl[2].kind, sl[2].value, "emote row shown", tostring(not slices.emote2.hidden()))
radial.args.manage.args.new.set({}, "Second")
out("new from options", #db.radialMenus, "selected", tostring(SELECTED), "page", radial.args.menu2 and radial.args.menu2.name())
NSX.OpenOptions("radial")
out("open radial", tostring(SELECTED))

-- Reset to defaults keeps menus.
NSX.ResetDefaults()
out("after reset: menus", #db.radialMenus)

local u = {} for k in pairs(UNDEF) do if not k:match("^Circlet") then table.insert(u, k) end end
table.sort(u)
for k, n in pairs(ERRORS) do out("ERROR", k, n) end
''')
for line in lua.globals().OUT.values():
    print(line)
