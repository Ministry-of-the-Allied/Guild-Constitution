-- Ministry of the Allied: the Settings page (Settings board, approved by Max 9 Nov).
-- A page of the add-on's own window, in place of the page you were on: the
-- gear knob, a right-click on the minimap seal and /mota settings open it; any
-- tab, or the gear again, goes back. The rows are grouped and the list scrolls.
-- Lit switches and choices wear the skin's accent. Reload UI sits at the foot,
-- with a soft gold glow behind it while a /reload is due.
--
-- The game's own options (Escape > Options > AddOns > Ministry of the Allied)
-- keep a small entry with an Open settings button.
--
-- The switches and choices are the Extras board's pictures (Media "swOn",
-- "segModestOn"...). Each sits centred on its control's box, and a choice's
-- halves keep their place in its box, so the pictures and the click areas
-- line up in a row of any width. (The board's measured boxes and its pictures
-- can be a row apart further down the old page, so a picture is never placed
-- by its own measured spot.)

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Page = {}
MOTA.SettingsPage = Page

local PAGE_ID = "settings"
local BLUE = "1B3570"                   -- the accent's ink (Kit follows the skin)

-- Each row: a switch (sw) or a choice (seg: the box's piece and slot, then
-- value, button slot, piece prefix).
local SW = { slot = "sw1", on = { "swOn", "sw1" }, off = { "swOff", "sw4" } }
local GROUPS = {
  { title = "Heralds", rows = {
    { key = "herald", label = "Herald pop-ups", small = "Announce votes, laws and defections live", sw = SW },
    { key = "fanfare", label = "Fanfare", small = "Play the game's own trumpet with each herald", sw = SW },
    { key = "heraldSize", label = "Herald size", small = "How grand the pop-ups appear",
      seg = { box = "segBox", slot = "seg",
              { "small", "seg-modest", "segModest" }, { "full", "seg-royal", "segRoyal" } } },
  } },
  { title = "The map", rows = {
    { key = "glow", label = "District glow", small = "Light your district on the world map", sw = SW,
      changed = function() MOTA:Fire("GLOW_CHANGED") end },
    -- The world map's dress (Batch D5f): Party (as the window), the Ministry's, or the game's own look.
    { key = "mapSkin", label = "World map skin", small = "How the world map is dressed",
      seg = { box = "segMapBox", slot = "segmap",
              { "party", "seg-mparty", "segMapParty" }, { "ministry", "seg-mministry", "segMapMinistry" },
              { "plain", "seg-mplain", "segMapPlain" } },
      changed = function() MOTA:Fire("MAP_SKIN_CHANGED") end,
      note = function() return MOTA.MapCompat and MOTA.MapCompat:Note() end },
  } },
  -- Window skins (ADDON_SPEC.md 9.1): the Crown ranks only, so this group is
  -- left out for everyone else. Party is the Crown's skin for them.
  { title = "The window", crownOnly = true, rows = {
    { key = "windowSkin", label = "Window skin", small = "The Crown's colours, or the Ministry's · the Crown's ranks only",
      seg = { box = "segSkinBox", slot = "segskin",
              { "party", "seg-party", "segParty" }, { "ministry", "seg-ministry", "segMinistry" } },
      changed = function() MOTA.Skin:Refresh(true) end },
  } },
  { title = "Coming later", rows = {
    { key = "cards", label = "Citizen cards", small = "Show the card when hovering guild members · later", sw = SW, later = true },
  } },
}

-- The page's place: the parchment, as the other pages.
local PARCH = M.slots.parch
local LEFT, TOP = PARCH.x + 34, PARCH.y + 20
local WIDTH, HEIGHT = PARCH.w - 60, PARCH.h - 42
local EYEBROW_Y = M.slots.eyebrow.y - TOP
local HEADING_Y = M.slots.heading.y - TOP
local LIST_Y = M.slots.divider.y + M.slots.divider.h - TOP + 4
local FOOT_H = 44
local LIST_H = HEIGHT - FOOT_H - 10 - LIST_Y
local BAR_W, BAR_GAP = 10, 14
local LIST_W = WIDTH - BAR_W - BAR_GAP
local ROW_H, GROUP_H, WHEEL = 55, 28, 40

local root, scroll, child, bar, thumb, foot
local groups = {}   -- built groups: { frame, rows = { { row, controls } } }
local controls = {} -- every switch and choice button, to Update
local notes = {}    -- rows whose small line can change: { row, fs }

local function isCrown()
  return MOTA.me ~= nil and MOTA:IsCrown(MOTA.me)
end

local function play(kit)
  if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

-- Puts piece name with its top-left at x, y in parent.
local function lay(t, name, parent, x, y)
  UI:SetPiece(t, name, 0, 0, parent, { x, y })
end

-- A piece centred on the box x, y, w, h in parent.
local function centred(parent, name, layer, x, y, w, h)
  local p = M.pieces[name]
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  lay(t, name, parent, x + (w - p.w) / 2, y + (h - p.h) / 2)
  return t
end

-- A piece that keeps its place beside another piece (bx, by: where that one is).
local function beside(parent, name, layer, ref, bx, by)
  local p, r = M.pieces[name], M.pieces[ref]
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  lay(t, name, parent, bx + p.x - r.x, by + p.y - r.y)
  return t
end

local function silver()
  return MOTA.skin and MOTA.skin.METAL == "silver"
end

-- A blue-and-gold picture follows the skin: its accent ("~cr", "~ex") and, for
-- Silverhand, its silver metal ("~sv": a silver rim and knob on the blue; Max, 9 Nov).
local function accent(t, name)
  MOTA.Kit:Track(function()
    local drawn = silver() and name .. "~sv" or name .. MOTA:Accent().SUFFIX
    MOTA.Kit:Look(t, M.pieces[drawn] and drawn or name)
  end)
end

-- A dotted rule along a row's foot: the board's dots, repeated to the row's width.
local function dots(parent, y, w)
  local p = M.pieces.rowLine
  local n = math.ceil(w / p.w)
  for i = 1, n do
    local t = parent:CreateTexture(nil, "BORDER")
    lay(t, "rowLine", parent, (i - 1) * p.w, y)
    local part = math.min(1, (w - (i - 1) * p.w) / p.w)
    if part < 1 then
      t:SetWidth(p.w * part)
      t:SetTexCoord(p.l, p.l + (p.r - p.l) * part, p.t, p.b)
    end
  end
end

-- A switch, its slot's top-left at x, y in parent.
local function buildSwitch(parent, row, x, y)
  local s = M.slots[SW.slot]
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(s.w, s.h)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  -- both pictures centred on the switch, so off sits where on did (Max, 9 Nov)
  b.on = centred(parent, SW.on[1], "ARTWORK", x, y, s.w, s.h)
  accent(b.on, SW.on[1])
  b.off = centred(parent, SW.off[1], "ARTWORK", x, y, s.w, s.h)
  function b:Update()
    local v = MOTA.db.settings[row.key] and true or false
    self.on:SetShown(v)
    self.off:SetShown(not v)
  end
  b:SetScript("OnClick", function(self)
    if row.later then return end
    MOTA.db.settings[row.key] = not MOTA.db.settings[row.key]
    play(MOTA.db.settings[row.key] and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
    self:Update()
    if row.changed then row.changed() end
  end)
  if row.later then
    b.on:SetAlpha(0.45)
    b.off:SetAlpha(0.45)
  end
  controls[#controls + 1] = b
  return s.w
end

-- A choice of two or three, its box's slot at x, y in parent.
local function buildChoice(parent, row, x, y)
  local seg = row.seg
  local box, pb = M.slots[seg.slot], M.pieces[seg.box]
  local bx, by = x + (box.w - pb.w) / 2, y + (box.h - pb.h) / 2
  centred(parent, seg.box, "BORDER", x, y, box.w, box.h)
  local buttons = {}
  for _, opt in ipairs(seg) do
    local value, slotName, prefix = opt[1], opt[2], opt[3]
    local s = M.slots[slotName]
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(s.w, s.h)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + s.x - box.x, -(y + s.y - box.y))
    b.on = beside(parent, prefix .. "On", "ARTWORK", seg.box, bx, by)
    accent(b.on, prefix .. "On")
    b.off = beside(parent, prefix .. "Off", "ARTWORK", seg.box, bx, by)
    function b:Update()
      local chosen = MOTA.db.settings[row.key] == value
      self.on:SetShown(chosen)
      self.off:SetShown(not chosen)
    end
    b:SetScript("OnClick", function()
      if row.crownOnly and not isCrown() then return end
      MOTA.db.settings[row.key] = value
      play("IG_MAINMENU_OPTION_CHECKBOX_ON")
      for _, other in ipairs(buttons) do other:Update() end
      if row.changed then row.changed() end
    end)
    buttons[#buttons + 1] = b
    controls[#controls + 1] = b
  end
  return box.w
end

-- One row: its label and small line on the left, its control on the right, dots along its foot.
local function buildRow(parent, row, y, last)
  local label = MOTA:Tracked(parent, "setLabel", "2A1F14", 0.08)
  label:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(y + 11))
  label:SetText(row.label:upper())
  local small = parent:CreateFontString(nil, "OVERLAY")
  small:SetFontObject(MOTA:Font("setSmall"))
  small:SetTextColor(MOTA:RGB("5E4B33"))
  small:SetJustifyH("LEFT")
  small:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(y + 29))
  small:SetText(row.small)
  if row.later then
    label:SetAlpha(0.5)
    small:SetAlpha(0.6)
  end
  if row.note then notes[#notes + 1] = { row = row, fs = small } end
  local slot = M.slots[row.sw and SW.slot or row.seg.slot]
  local cx, cy = LIST_W - slot.w, y + (ROW_H - slot.h) / 2
  if row.sw then buildSwitch(parent, row, cx, cy) else buildChoice(parent, row, cx, cy) end
  small:SetWidth(cx - 16)
  small:SetWordWrap(false)
  if not last then dots(parent, y + ROW_H - 1, LIST_W) end
end

local function buildGroup(g)
  local f = CreateFrame("Frame", nil, child)
  f:SetSize(LIST_W, GROUP_H + #g.rows * ROW_H)
  local head = MOTA.Kit:Label(f, "kitSection", BLUE, 0.22, g.title)
  head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -10)
  for i, row in ipairs(g.rows) do
    row.crownOnly = g.crownOnly
    buildRow(f, row, GROUP_H + (i - 1) * ROW_H, i == #g.rows)
  end
  return f
end

---------------------------------------------------------------------------
-- Scrolling: the wheel, a click on the bar, or dragging its gold thumb
---------------------------------------------------------------------------

local function range()
  return math.max(0, (child:GetHeight() or 0) - LIST_H)
end

local function placeThumb()
  local r = range()
  bar:SetShown(r > 0)
  if r <= 0 then return end
  local h = math.max(30, LIST_H * LIST_H / (LIST_H + r))
  thumb:SetHeight(h)
  local at = (scroll:GetVerticalScroll() or 0) / r
  thumb:ClearAllPoints()
  thumb:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -(2 + at * (LIST_H - 4 - h)))
end

local function scrollTo(v)
  scroll:SetVerticalScroll(math.max(0, math.min(range(), v)))
  placeThumb()
end

local function cursorY()
  local _, y = GetCursorPosition()
  return y / (bar:GetEffectiveScale() or 1)
end

local function buildBar()
  bar = CreateFrame("Button", nil, root)
  bar:SetSize(BAR_W, LIST_H)
  bar:SetPoint("TOPLEFT", root, "TOPLEFT", LIST_W + BAR_GAP, -LIST_Y)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  MOTA.Kit:Solid(track, "6E4F17", 0.18)
  track:SetAllPoints()
  MOTA.Kit:Outline(bar, "6E4F17", 0.4)
  thumb = CreateFrame("Button", nil, bar)
  thumb:SetWidth(BAR_W - 2)
  local left = thumb:CreateTexture(nil, "ARTWORK")
  left:SetPoint("TOPLEFT")
  left:SetPoint("BOTTOMRIGHT", thumb, "BOTTOM", 0, 0)
  local right = thumb:CreateTexture(nil, "ARTWORK")
  right:SetPoint("TOPLEFT", thumb, "TOP", 0, 0)
  right:SetPoint("BOTTOMRIGHT")
  MOTA.Kit:Outline(thumb, "4A330C", 0.7)
  MOTA.Kit:Track(function() -- the metal: gold, or Silverhand's silver
    local dark, light = "8A6420", "E9C979"
    if silver() then dark, light = "6B7483", "EEF2F6" end
    MOTA.Kit:Gradient(left, dark, light, 1, 1, true)
    MOTA.Kit:Gradient(right, light, dark, 1, 1, true)
  end)
  -- a click on the bar jumps a page towards it
  bar:SetScript("OnClick", function()
    local top = thumb:GetTop() or 0
    local step = cursorY() > top and -LIST_H or LIST_H
    scrollTo(scroll:GetVerticalScroll() + step)
  end)
  thumb:SetScript("OnMouseDown", function(self)
    self.from, self.start = cursorY(), scroll:GetVerticalScroll()
    self:SetScript("OnUpdate", function()
      local free = LIST_H - 4 - self:GetHeight()
      if free <= 0 then return end
      scrollTo(self.start + (self.from - cursorY()) / free * range())
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

-- Lays the groups one under another (the Crown's group only for the Crown).
function Page:Layout()
  if not root then return end
  local y = 0
  for i, g in ipairs(groups) do
    local shown = not GROUPS[i].crownOnly or isCrown()
    g:SetShown(shown)
    if shown then
      g:ClearAllPoints()
      g:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
      y = y + g:GetHeight()
    end
  end
  child:SetHeight(y + 6)
  scrollTo(scroll:GetVerticalScroll() or 0)
end

-- The small lines that can say why a choice is held back, and the reload's glow and words.
function Page:Notes()
  if not root then return end
  for _, n in ipairs(notes) do
    local text = n.row.note()
    n.fs:SetText(text or n.row.small)
    n.fs:SetTextColor(MOTA:RGB(text and "8E2B22" or "5E4B33"))
  end
  local due = MOTA.MapCompat and MOTA.MapCompat:NeedsReload() or false
  foot.glow:SetShown(due)
  foot.text:SetText(due and "A reload is due to finish a change: press Reload UI, or type /reload."
    or "Settings are kept for every character on this account.")
  foot.text:SetTextColor(MOTA:RGB(due and "8E2B22" or "5E4B33"))
end

-- Whether Reload UI glows (for the sim).
function Page:Glow()
  return foot ~= nil and foot.glow:IsShown()
end

function Page:Refresh()
  if not root then return end
  for _, c in ipairs(controls) do c:Update() end
  self:Layout()
  self:Notes()
end

local function buildFoot()
  foot = CreateFrame("Frame", nil, root)
  foot:SetSize(WIDTH, FOOT_H)
  foot:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
  local rule = foot:CreateTexture(nil, "BORDER")
  MOTA.Kit:Solid(rule, "6E4F17", 0.35)
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT")
  rule:SetPoint("TOPRIGHT")
  local rs = M.slots.sreload
  local bx, by = WIDTH - rs.w, FOOT_H - rs.h - 2
  -- the glow is drawn white and worn in the skin's accent, like the button (Max, 9 Nov)
  foot.glow = centred(foot, "sReloadGlow", "BACKGROUND", bx, by, rs.w, rs.h)
  MOTA.Kit:Track(function() foot.glow:SetVertexColor(MOTA:RGB(MOTA:Accent().TOP)) end)
  foot.glow:Hide()
  foot.reload = MOTA.Kit:Button(foot, rs.w, rs.h, "Reload UI", "blue", function() ReloadUI() end)
  foot.reload:SetPoint("TOPLEFT", foot, "TOPLEFT", bx, -by)
  foot.text = MOTA.Kit:Text(foot, "kitSmall", "5E4B33")
  foot.text:SetPoint("LEFT", foot, "TOPLEFT", 0, -(by + rs.h / 2))
  foot.text:SetWidth(bx - 20)
  foot.text:SetWordWrap(false)
end

local function build()
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
  root:SetFrameLevel(UI.window:GetFrameLevel() + 5)

  local eyebrow = MOTA:Tracked(root, "pageEyebrow", "7A5719", 0.32)
  eyebrow:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -EYEBROW_Y)
  eyebrow:SetText("OPTIONS · FOR THIS ACCOUNT")
  local heading = MOTA.Kit:Text(root, "heading", BLUE)
  heading:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -HEADING_Y)
  heading:SetText("Settings")
  local aside = MOTA.Kit:Text(root, "kitItalic", "5E4B33", "RIGHT")
  -- clear of the divider under it (Max, 9 Nov: it sat on the rule)
  aside:SetPoint("BOTTOMRIGHT", root, "TOPRIGHT", 0, -(M.slots.divider.y - TOP - 2))
  aside:SetText("Changes take effect at once,\nunless the page asks for a reload.")

  scroll = CreateFrame("ScrollFrame", nil, root)
  scroll:SetSize(LIST_W, LIST_H)
  scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -LIST_Y)
  child = CreateFrame("Frame", nil, scroll)
  child:SetSize(LIST_W, 1)
  scroll:SetScrollChild(child)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, delta) scrollTo(scroll:GetVerticalScroll() - delta * WHEEL) end)
  for i, g in ipairs(GROUPS) do groups[i] = buildGroup(g) end
  buildBar()
  buildFoot()
end

function Page:Show(show)
  if show and not root then build() end
  if not root then return end
  root:SetShown(show)
  if show then self:Refresh() end
end

Page.controls, Page.groups = controls, groups
MOTA:Listen("PAGE_SHOWN", function(_, id) Page:Show(id == PAGE_ID) end)
-- The guild rank arrives after login: show or leave out the Crown's group.
MOTA:Listen("GUILD_READY", function() if root and root:IsShown() then Page:Layout() end end)
MOTA:Listen("MAP_SKIN_CHANGED", function() Page:Notes() end)

---------------------------------------------------------------------------
-- Opening it, and the game's own options entry
---------------------------------------------------------------------------

-- The minimap seal's right-click and /mota settings.
function UI:OpenSettings()
  self:ShowSettings(true)
end

local panel
local function buildOptionsEntry()
  panel = CreateFrame("Frame", "MinistryOfTheAlliedOptions")
  panel.name = "Ministry of the Allied"
  local page = CreateFrame("Frame", nil, panel)
  local s = M.slots.settings
  page:SetSize(s.w, 200)
  page:SetPoint("TOP", panel, "TOP", 0, -12)
  -- the crest and the title from the old options page, on their parchment
  local p = M.pieces.settingsPage
  local bg = page:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
  local cut = 200 / p.h
  bg:SetTexCoord(p.l, p.r, p.t, p.t + (p.b - p.t) * cut)
  bg:SetSize(p.w, 200)
  bg:SetPoint("TOPLEFT", page, "TOPLEFT", p.x, -p.y)
  MOTA.LiveText:Set(bg, "settingsPage")
  local text = page:CreateFontString(nil, "OVERLAY")
  text:SetFontObject(MOTA:Font("setSmall"))
  text:SetTextColor(MOTA:RGB("5E4B33"))
  text:SetPoint("TOPLEFT", page, "TOPLEFT", 31, -92)
  text:SetWidth(s.w - 62)
  text:SetJustifyH("LEFT")
  text:SetText("The Ministry's settings live in its own window now, on the Settings page (the gear at the window's top right).")
  local open = MOTA.Kit:Button(page, 150, 30, "Open settings", "blue", function()
    if not InCombatLockdown() and SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then
      pcall(HideUIPanel, SettingsPanel)
    end
    UI:OpenSettings()
  end)
  open:SetPoint("TOPLEFT", page, "TOPLEFT", 31, -140)
  panel.open = open

  local function fit()
    local w = panel:GetWidth()
    if w and w > 50 then page:SetScale(math.min((w - 20) / s.w, 1.4)) end
  end
  panel:SetScript("OnShow", fit)
  panel:SetScript("OnSizeChanged", fit)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    UI.settingsCategory = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

MOTA:On("PLAYER_LOGIN", function()
  if not panel then buildOptionsEntry() end
end)
