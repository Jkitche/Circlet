unpack = unpack or table.unpack
-- Minimal WoW API mock: frames/regions accept any method; specific APIs return controllable data.
local function Region(kind)
  local r = { _kind = kind, _shown = (kind ~= "Frame"), _scripts = {}, _alpha = 1, _w = 100, _h = 10 }
  return setmetatable(r, { __index = function(t, k)
    local m = rawget(_G, "RegionMethods")[k]
    if m then return m end
    if type(k) == "string" and k:sub(1, 1) == "_" then return nil end -- internal fields
    if type(k) == "string" and k:match("^%u") then
      return function(self, ...) return self end -- unknown Method(): no-op
    end
    return nil -- plain fields (e.g. plate.UnitFrame) are nil unless set
  end })
end
RegionMethods = {
  Show = function(s) s._shown = true; if s._scripts.OnShow then s._scripts.OnShow(s) end end,
  Hide = function(s) local was = s._shown; s._shown = false; if was and s._scripts.OnHide then s._scripts.OnHide(s) end end,
  IsShown = function(s) return s._shown end,
  SetShown = function(s, v) s._shown = v and true or false end,
  SetScript = function(s, n, f) s._scripts[n] = f end,
  GetScript = function(s, n) return s._scripts[n] end,
  HookScript = function(s, n, f) s._scripts[n] = f end,
  GetAlpha = function(s) return s._alpha end,
  SetAlpha = function(s, a) s._alpha = a end,
  GetWidth = function(s) return s._w end, GetHeight = function(s) return s._h end,
  GetFrameLevel = function(s) return s._level or 1 end, GetEffectiveScale = function() return 0.8 end,
  SetFrameLevel = function(s, l) s._level = l end,
  SetFrameStrata = function(s, st) s._strata = st end,
  GetFrameStrata = function(s) return s._strata or "MEDIUM" end,
  IsForbidden = function() return false end,
  CreateTexture = function() return Region("Texture") end,
  CreateFontString = function(self)
    local f = Region("FontString"); f._parent = self
    f.SetText = function(me, t) me._text = t end
    f.SetTextColor = function(me, r, g, b) me._tc = { r, g, b } end
    ALL_FS = ALL_FS or {}; table.insert(ALL_FS, f)
    return f
  end,
  CreateLine = function(self, name, layer, tmpl, sub)
    local l = Region("Line"); l._layer = layer; l._sub = sub or 0; l._parent = self
    l.SetStartPoint = function(me, p, rel, x, y) me._x1, me._y1 = x, y end
    l.SetEndPoint = function(me, p, rel, x, y) me._x2, me._y2 = x, y end
    l.SetThickness = function(me, t) me._t = t end
    l.SetColorTexture = function(me, r, g, b, a) me._c = { r, g, b, a or 1 } end
    ALL_LINES = ALL_LINES or {}; table.insert(ALL_LINES, l)
    return l
  end,
  CreateAnimationGroup = function()
    local ag = Region("AnimationGroup"); ag._playing = false
    ag.Play = function(self) self._playing = true end
    ag.Stop = function(self) self._playing = false end
    ag.IsPlaying = function(self) return self._playing end
    ag.CreateAnimation = function() return Region("Animation") end
    return ag
  end,
  GetChecked = function(s) return s._checked end,
  SetChecked = function(s, v) s._checked = v end,
  RegisterEvent = function(s, e) s._events = s._events or {}; s._events[e] = true end,
  RegisterUnitEvent = function(s, e) s._events = s._events or {}; s._events[e] = true end,
  UnregisterEvent = function(s, e) end,
  SetTextColor = function(s) end,
  StartMoving = function() end, StopMovingOrSizing = function() end,
}
allFrames = {}
function CreateFrame(kind, name, parent, template)
  local f = Region("Frame"); f._shown = true
  table.insert(allFrames, f)
  if name then _G[name] = f end
  return f
end
UIParent = CreateFrame("Frame")

-- Time & timers
NOW = 1000
function GetTime() return NOW end
pendingTimers = {}
C_Timer = { After = function(d, fn) table.insert(pendingTimers, { at = NOW + d, fn = fn }) end }
function Advance(seconds, fps)
  fps = fps or 30
  local steps = math.floor(seconds * fps)
  for _ = 1, steps do
    NOW = NOW + 1 / fps
    -- timers
    local due = {}
    for i = #pendingTimers, 1, -1 do
      if pendingTimers[i].at <= NOW then table.insert(due, table.remove(pendingTimers, i)) end
    end
    for _, t in ipairs(due) do t.fn() end
    -- OnUpdate scripts
    for _, f in ipairs(allFrames) do
      if f._shown and f._scripts.OnUpdate then f._scripts.OnUpdate(f, 1 / fps) end
    end
  end
end
function Fire(event, ...)
  for _, f in ipairs(allFrames) do
    if f._events and f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end

-- Globals used by the addon
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
SlashCmdList = {}; StaticPopupDialogs = {}; UISpecialFrames = {}
function StaticPopup_Show() end
YES, NO = "Yes", "No"
function print() end
function tostringall(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end return unpack(t) end
string.join = function(sep, ...) return table.concat({ ... }, sep) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s) local out = {} for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do out[#out + 1] = p end return unpack(out) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
function BreakUpLargeNumbers(n) local s = tostring(math.floor(n)); local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse(); return (r:gsub("^,", "")) end
function GetPhysicalScreenSize() return 2560, 1440 end
function InCombatLockdown() return IN_COMBAT end
IN_COMBAT = false
Enum = { TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 } }
C_Texture = { GetAtlasInfo = function() return {} end }
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }

-- Units
UNITS = {}
function UnitExists(u) return UNITS[u] ~= nil or u == "player" end
function UnitIsPlayer(u) return u == "player" end
function UnitName(u) return u == "player" and "Kaladin" or (UNITS[u] and UNITS[u].name) end
function UnitGUID(u) return UNITS[u] and UNITS[u].guid end
function UnitLevel(u) return PLAYER_LEVEL end
PLAYER_LEVEL = 16
XP, XPMAX = 300, 1000
function UnitXP() return XP end
function UnitXPMax() return XPMAX end
REST = nil
function GetXPExhaustion() return REST end

PLATES = {}
C_NamePlate = { GetNamePlateForUnit = function(u) return PLATES[u] end }
function MakePlate(unit, name, guid)
  UNITS[unit] = { name = name, guid = guid }
  local p = CreateFrame("Frame"); p.UnitFrame = { healthBar = Region("StatusBar") }
  p.UnitFrame.healthBar._shown = true
  PLATES[unit] = p
end

-- Tooltip data: Screecher shows a feather objective
OBJ_HAVE = 3
C_TooltipInfo = { GetUnit = function(u)
  if not UNITS[u] then return nil end
  return { lines = {
    { type = 2, leftText = UNITS[u].name },
    { type = 17, leftText = "Feathers for Grek" },
    { type = 8, leftText = OBJ_HAVE .. "/8 Screecher Feather", completed = OBJ_HAVE >= 8 },
  } }
end }

-- Quest log
C_QuestLog = {
  GetNumQuestLogEntries = function() return 1, 1 end,
  GetInfo = function(i) return { questID = 77, title = "Feathers for Grek", level = 15 } end,
  GetQuestObjectives = function(id) return { { text = OBJ_HAVE .. "/8 Screecher Feather", type = "item",
    numFulfilled = OBJ_HAVE, numRequired = 8, finished = OBJ_HAVE >= 8 } } end,
  IsComplete = function() return false end,
  GetMaxNumQuestsCanAccept = function() return 20 end,
}
function GetQuestLogRewardXP() return 450 end

-- Settings API (mock enough for SetupOptions)
Settings = {
  VarType = { Boolean = "boolean", Number = "number", String = "string" },
  RegisterVerticalLayoutCategory = function(name)
    PAGES = { { name = name, items = {} } }
    local cat = { GetID = function() return 1 end, page = PAGES[1] }
    local layout = { AddInitializer = function(self, init) table.insert(cat.page.items, init.label or "?") end, page = PAGES[1] }
    return cat, layout
  end,
  RegisterVerticalLayoutSubcategory = function(parent, name)
    local p = { name = "  > " .. name, items = {} }; table.insert(PAGES, p)
    local cat = { GetID = function() return #PAGES end, page = p }
    local layout = { AddInitializer = function(self, init) table.insert(p.items, init.label or "?") end }
    return cat, layout
  end,
  RegisterAddOnSetting = function(cat, var, key, tbl, typ, name, default)
    REGISTERED = REGISTERED or {}; REGISTERED[key] = (REGISTERED[key] or 0) + 1
    if cat.page then table.insert(cat.page.items, "[" .. key .. "]") end
    local s = { key = key, tbl = tbl }
    function s:SetValueChangedCallback(cb) self.cb = cb end
    function s:SetValue(v) self.tbl[self.key] = v; if self.cb then self.cb(self, v) end end
    return s
  end,
  CreateCheckbox = function() end,
  CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
  CreateSlider = function() end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function() end,
}
function CreateSettingsListSectionHeaderInitializer(t) return { label = "== " .. t } end
BUTTONS = {}
function CreateSettingsButtonInitializer(label, text, onClick) BUTTONS[label] = onClick; return { label = "(" .. text .. ")" } end

-- Skills (Forever C_SkillInfo)
SKILL_LINES = {
  { isHeader = true, name = "Weapon Skills" },
  { skillID = 43, name = "Swords", rank = 141, maxRank = 150, skillLineCategoryID = 6 },
  { skillID = 95, name = "Defense", rank = 148, maxRank = 150, skillLineCategoryID = 6 },
  { isHeader = true, name = "Professions" },
  { skillID = 186, name = "Mining", rank = 112, maxRank = 150, skillLineCategoryID = 11 },
  { isHeader = true, name = "Secondary Skills", isCollapsed = true },   -- children hidden
  { isHeader = true, name = "Armor Proficiencies" },
  { skillID = 413, name = "Mail", rank = 1, maxRank = 1, skillLineCategoryID = 8 },
}
HIDDEN = {   -- under the collapsed header: only reachable by ID
  [185] = { skillID = 185, name = "Cooking", rank = 74, maxRank = 75, skillLineCategoryID = 9 },
  [356] = { skillID = 356, name = "Fishing", rank = 40, maxRank = 150, skillLineCategoryID = 9 },
}
function SetSkill(id, rank)
  for _, l in ipairs(SKILL_LINES) do if l.skillID == id then l.rank = rank end end
  if HIDDEN[id] then HIDDEN[id].rank = rank end
end
C_SkillInfo = {
  GetNumSkillLines = function() return #SKILL_LINES end,
  GetSkillLineInfo = function(i) return SKILL_LINES[i] end,
  GetSkillLineInfoByID = function(id)
    for _, l in ipairs(SKILL_LINES) do if l.skillID == id then return l end end
    return HIDDEN[id]
  end,
}

ColorPickerFrame = {
  SetupColorPickerAndShow = function(self, info) PICKER = info end,
  GetColorRGB = function() return PICK_R, PICK_G, PICK_B end,
}

-- Reputation (Forever C_Reputation)
local TH = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000, 42999 }
local function Reaction(v) for r = 8, 1, -1 do if v >= TH[r] then return r end end return 1 end
FACTIONS = {
  { isHeader = true, name = "Alliance" },
  { factionID = 72, name = "Stormwind", standing = 3000 + 2150 },
  { factionID = 69, name = "Darnassus", standing = 3000 + 5500 },
  { isHeader = true, name = "Steamwheedle Cartel" },
  { factionID = 21, name = "Booty Bay", standing = 1800 },
  { isHeader = true, name = "Hidden group", isCollapsed = true },
}
HIDDEN_FACTIONS = { [47] = { factionID = 47, name = "Ironforge", standing = 3000 + 100 } }
local function Data(f)
  if not f then return nil end
  if f.isHeader then return { isHeader = true, name = f.name, isCollapsed = f.isCollapsed } end
  local r = Reaction(f.standing)
  return { factionID = f.factionID, name = f.name, reaction = r, currentStanding = f.standing,
           currentReactionThreshold = TH[r], nextReactionThreshold = TH[r + 1] }
end
function SetRep(id, v)
  for _, f in ipairs(FACTIONS) do if f.factionID == id then f.standing = v end end
  if HIDDEN_FACTIONS[id] then HIDDEN_FACTIONS[id].standing = v end
end
function ShowHidden(on) -- temporarily list Ironforge so it gets "seen"
  if on then table.insert(FACTIONS, HIDDEN_FACTIONS[47]) else table.remove(FACTIONS) end
end
C_Reputation = {
  GetNumFactions = function() return #FACTIONS end,
  GetFactionDataByIndex = function(i) return Data(FACTIONS[i]) end,
  GetFactionDataByID = function(id)
    for _, f in ipairs(FACTIONS) do if f.factionID == id then return Data(f) end end
    return Data(HIDDEN_FACTIONS[id])
  end,
}
function UnitSex() return 2 end

RegionMethods.SetPoint = function(s, p, rel, rp, x, y)
  if type(rp) == "number" then x, y = rp, x end
  s._pt = { x = x or 0, y = y or 0 }
end
RegionMethods.SetSize = function(s, w, h) s._w, s._h = w, h end
RegionMethods.SetVertexColor = function(s, r, g, b) s._vc = { r, g, b } end

RegionMethods.SetRotation = function(s, r) s._rot = r end
RegionMethods.SetAtlas = function(s, a) s._atlas = a end

MISSING_ICONS = {}
function GetFileIDFromPath(p) if MISSING_ICONS[p] then return nil end return 12345 end
RegionMethods.CreateMaskTexture = function(self) local m = Region("MaskTexture"); m._parent = self; return m end
RegionMethods.AddMaskTexture = function(s, m) s._mask = m end
RegionMethods.SetTexture = function(s, t) s._texpath = t end
RegionMethods.SetTexCoord = function(s, ...) s._tc4 = { ... } end
function UnitClass(u) return "Hunter", "HUNTER", 3 end
HP, HPMAX, PW, PWMAX, PTYPE, PTOKEN, DEAD = 1000, 1000, 800, 800, 0, "MANA", false
function UnitHealth() return HP end
function UnitHealthMax() return HPMAX end
function UnitPower() return PW end
function UnitPowerMax() return PWMAX end
function UnitPowerType() return PTYPE, PTOKEN end
function UnitIsDeadOrGhost() return DEAD end
function UnitAffectingCombat() return IN_COMBAT end
CURSOR_X, CURSOR_Y, SHIFT = 0, 0, false
function GetCursorPosition() return CURSOR_X, CURSOR_Y end
function IsShiftKeyDown() return SHIFT end
time = time or os.time
function UnitIsGhost() return false end
function IsResting() return false end
function GetMoney() return 0 end
function GetRealmName() return "Realm" end
