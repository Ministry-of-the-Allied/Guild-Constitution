-- Ministry of the Allied: the window.
-- One window with seven pages (ADDON_SPEC.md, section 10), drawn from the
-- design canvas: every piece comes from Media.lua, which
-- tools/textures/build.py writes from the canvas's own stylesheet.
-- Milestone 2: the frame, the tabs and empty pages. Page contents come later.

local _, MOTA = ...
local UI = {}
MOTA.UI = UI

local M = MOTA.Media
local W, H = M.window.w, M.window.h

-- Colours from the canvas (design/canvas-source/ministry.css).
local TAB_COLORS = {
  rest = { label = "E5CF92", small = "EBC3B2" },
  hover = { label = "FBEFC4", small = "EBC3B2" },
  on = { label = "0E1F45", small = "3A2A0A" },
}

local DEFAULT_SCALE = 0.85

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function texturePath(name)
  return M.dir .. M.textures[name]
end

-- Draws a piece from Media.lua. Positions are canvas units from the top-left
-- corner of the piece's root (the window unless another frame is given as
-- anchor); dx, dy shift a piece that is reused somewhere else.
function UI:Piece(parent, name, layer, sublevel, dx, dy, anchor)
  local p = M.pieces[name]
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
  t:SetTexture(texturePath(p.tex), "CLAMP", "CLAMP", "TRILINEAR")
  t:SetTexCoord(p.l, p.r, p.t, p.b)
  t:SetSize(p.w, p.h)
  t:SetPoint("TOPLEFT", anchor or self.window, "TOPLEFT", p.x + (dx or 0), -(p.y + (dy or 0)))
  return t
end

-- Places a region at a slot from the layout (where live text or a button goes).
function UI:AtSlot(region, slot, dx, dy, anchor)
  local s = M.slots[slot]
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", anchor or self.window, "TOPLEFT", s.x + (dx or 0), -(s.y + (dy or 0)))
  return s
end

local function tint(texture, hex)
  texture:SetVertexColor(MOTA:RGB(hex))
end

local function text(parent, font, hex, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFontObject(MOTA:Font(font))
  fs:SetTextColor(MOTA:RGB(hex))
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  return fs
end

local function play(kit)
  if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

---------------------------------------------------------------------------
-- The soft drop shadow, as a nine-slice (corners stay sharp, edges stretch)
---------------------------------------------------------------------------

local function buildShadow(f)
  local s = M.shadow
  local c = s.corner / s.size -- texture coordinate where a corner ends
  local k, out = s.corner, s.inset
  local left, top = -out, out - 24                   -- shifted down, like the canvas's shadow
  local right, bottom = W + out, -(H + out + 24)
  local midW, midH = (right - left) - 2 * k, (top - bottom) - 2 * k
  local parts = {
    { 0, c, 0, c, left, top, k, k },
    { c, 1 - c, 0, c, left + k, top, midW, k },
    { 1 - c, 1, 0, c, right - k, top, k, k },
    { 0, c, c, 1 - c, left, top - k, k, midH },
    { c, 1 - c, c, 1 - c, left + k, top - k, midW, midH },
    { 1 - c, 1, c, 1 - c, right - k, top - k, k, midH },
    { 0, c, 1 - c, 1, left, bottom + k, k, k },
    { c, 1 - c, 1 - c, 1, left + k, bottom + k, midW, k },
    { 1 - c, 1, 1 - c, 1, right - k, bottom + k, k, k },
  }
  for _, p in ipairs(parts) do
    local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetTexture(texturePath("shadow"))
    t:SetTexCoord(p[1], p[2], p[3], p[4])
    t:SetSize(p[7], p[8])
    t:SetPoint("TOPLEFT", f, "TOPLEFT", p[5], p[6])
  end
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function setTabLook(tab, look)
  local colors = TAB_COLORS[look]
  tab.bgRest:SetShown(look == "rest")
  tab.bgHover:SetShown(look == "hover")
  tab.bgOn:SetShown(look == "on")
  tint(tab.icon, colors.label)
  tint(tab.label, colors.label)
  tint(tab.small, colors.small)
end

local function buildTab(f, i)
  local slot = "tab" .. i
  local tab = CreateFrame("Button", nil, f)
  local s = UI:AtSlot(tab, slot)
  local rest = M.slots.tab2 -- tab 2 is drawn resting in the layout
  tab:SetSize(rest.w, rest.h)
  tab.index = i

  local dyRest = s.y - M.slots.tab2.y
  local dyOn = s.y - M.slots.tab1.y
  tab.bgRest = UI:Piece(tab, "tabRest", "BACKGROUND", 0, 0, dyRest)
  tab.bgHover = UI:Piece(tab, "tabHover", "BACKGROUND", 0, 0, dyRest)
  tab.bgOn = UI:Piece(tab, "tabOn", "BACKGROUND", 0, 0, dyOn)
  tab.icon = UI:Piece(tab, "icon" .. i, "ARTWORK")
  tab.label = UI:Piece(tab, "label" .. i, "ARTWORK")
  tab.small = UI:Piece(tab, "small" .. i, "ARTWORK")

  tab:SetScript("OnClick", function()
    if UI.page ~= i then
      play("IG_CHARACTER_INFO_TAB")
      UI:SelectPage(i)
    end
  end)
  tab:SetScript("OnEnter", function()
    if UI.page ~= i then setTabLook(tab, "hover") end
  end)
  tab:SetScript("OnLeave", function()
    if UI.page ~= i then setTabLook(tab, "rest") end
  end)
  setTabLook(tab, "rest")
  return tab
end

-- The moving shine across the active tab (.tab.on::before on the canvas):
-- it waits, then sweeps across once every five seconds.
local function buildSheen(f)
  local on = M.slots.tab1
  local clip = CreateFrame("Frame", nil, f)
  clip:SetSize(on.w, on.h)
  clip:SetClipsChildren(true)
  clip:SetFrameLevel(f:GetFrameLevel() + 12)

  local p = M.pieces.sheen
  local sheen = clip:CreateTexture(nil, "OVERLAY")
  sheen:SetTexture(texturePath(p.tex), "CLAMP", "CLAMP", "TRILINEAR")
  sheen:SetTexCoord(p.l, p.r, p.t, p.b)
  sheen:SetSize(p.w, p.h)
  sheen:SetPoint("TOPLEFT", clip, "TOPLEFT", -60 - (p.w - M.slots.sheen.w) / 2, 0)

  local group = sheen:CreateAnimationGroup()
  group:SetLooping("REPEAT")
  local move = group:CreateAnimation("Translation")
  move:SetOffset(300, 0)
  move:SetDuration(1.9)
  move:SetStartDelay(3.1)
  move:SetSmoothing("IN_OUT")
  group:Play()

  UI.sheenClip = clip
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

local function buildKnob(f, piece, slot, tooltip, onClick)
  local b = CreateFrame("Button", nil, f)
  local s = UI:AtSlot(b, slot)
  b:SetSize(s.w, s.h)
  b:SetFrameLevel(f:GetFrameLevel() + 15)
  UI:Piece(b, piece, "ARTWORK")
  local glow = UI:Piece(b, piece, "HIGHLIGHT")
  glow:SetBlendMode("ADD")
  glow:SetAlpha(0.3)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(tooltip, 1, 0.95, 0.77)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

function UI:Build()
  if self.window then return self.window end
  local f = CreateFrame("Frame", "MinistryOfTheAlliedFrame", UIParent)
  self.window = f
  f:SetSize(W, H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetClampRectInsets(-60, 12, 70, -12) -- keep the crest on screen too
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(frame)
    frame:StopMovingOrSizing()
    UI:SavePosition()
  end)
  f:Hide()
  tinsert(UISpecialFrames, "MinistryOfTheAlliedFrame") -- Escape closes it

  buildShadow(f)
  self:Piece(f, "chrome", "BACKGROUND", 0)

  -- Header: the page's name under the title (the title is part of the chrome).
  self.subtitles, self.eyebrows = {}, {}
  for i = 1, #M.pages do
    self.subtitles[i] = self:Piece(f, "subtitle" .. i, "ARTWORK")
    self.eyebrows[i] = self:Piece(f, "eyebrow" .. i, "ARTWORK")
  end
  buildKnob(f, "knobSettings", "knob-settings", "Settings", function() UI:OpenSettings() end)
  buildKnob(f, "knobClose", "knob-close", "Close", function() f:Hide() end)

  -- The tab rail.
  self.tabs = {}
  for i = 1, #M.pages do self.tabs[i] = buildTab(f, i) end
  buildSheen(f)

  -- The rail's foot: who you are.
  self:Piece(f, "railLine", "ARTWORK")
  self:Piece(f, "portrait", "ARTWORK")
  self.initials = text(f, "initials", "F3D98A")
  local ps = M.slots.portrait
  self.initials:SetPoint("CENTER", f, "TOPLEFT", ps.x + ps.w / 2, -(ps.y + ps.h / 2))
  self.who = text(f, "who", "FBEFC4")
  self:AtSlot(self.who, "who")
  self.whoSmall = text(f, "whoSmall", "AFC0E6")
  self.whoSmall:SetPoint("TOPLEFT", self.who, "BOTTOMLEFT", 0, -2)

  -- The page: heading, divider and a note about what the page will hold.
  self.divider = self:Piece(f, "divider", "ARTWORK")
  local note = M.slots.note
  self.heading = text(f, "heading", "1B3570")
  self:AtSlot(self.heading, "heading")
  self.heading:SetWidth(M.slots.heading.w)
  self.note = text(f, "body", "2A1F14")
  self:AtSlot(self.note, "note")
  self.note:SetWidth(note.w)
  self.note:SetSpacing(5)
  self.note2 = text(f, "bodyItalic", "5E4B33")
  self.note2:SetPoint("TOPLEFT", self.note, "BOTTOMLEFT", 0, -14)
  self.note2:SetWidth(note.w)
  self.note2:SetText("This page is built in a later milestone.")

  -- The status strip along the bottom.
  self:Piece(f, "pip", "ARTWORK")
  self.footLeft = text(f, "foot", "AFC0E6")
  self:AtSlot(self.footLeft, "foot-left", 16, 5)
  self.footRight = text(f, "foot", "AFC0E6")
  local fr = M.slots["foot-right"]
  self.footRight:SetPoint("TOPRIGHT", f, "TOPLEFT", fr.x + fr.w, -(fr.y + 5))
  self.footRight:SetJustifyH("RIGHT")

  -- The crest goes on top of everything, breaking out over the frame.
  local top = CreateFrame("Frame", nil, f)
  top:SetAllPoints()
  top:SetFrameLevel(f:GetFrameLevel() + 30)
  self.crest = self:Piece(top, "crest", "ARTWORK")
  self:ApplyCrest()

  f:SetScript("OnShow", function()
    play("IG_CHARACTER_INFO_OPEN")
    UI:Refresh()
    UI.ticker = C_Timer.NewTicker(30, function() UI:Refresh() end)
  end)
  f:SetScript("OnHide", function()
    play("IG_CHARACTER_INFO_CLOSE")
    if UI.ticker then UI.ticker:Cancel() UI.ticker = nil end
  end)

  self:RestorePosition()
  self:SelectPage(MOTA.db.window.page or 1)
  return f
end

---------------------------------------------------------------------------
-- Pages, live text, position and size
---------------------------------------------------------------------------

function UI:SelectPage(i)
  if i < 1 or i > #M.pages then i = 1 end
  self.page = i
  MOTA.db.window.page = i
  for n, tab in ipairs(self.tabs) do
    setTabLook(tab, n == i and "on" or "rest")
    self.subtitles[n]:SetShown(n == i)
    self.eyebrows[n]:SetShown(n == i)
  end
  local slot = M.slots["tab" .. i]
  self.sheenClip:ClearAllPoints()
  self.sheenClip:SetPoint("TOPLEFT", self.window, "TOPLEFT", slot.x, -slot.y)
  local page = M.pages[i]
  self.heading:SetText(page.heading)
  self.note:SetText(page.note)
  -- A page with its own contents replaces the note about what it will hold.
  local built = page.id == "statute" or page.id == "ring"
  self.note:SetShown(not built)
  self.note2:SetShown(not built)
  -- The built pages run from the parchment's top, as their boards do.
  self.heading:SetShown(not built)
  self.divider:SetShown(not built)
  self.eyebrows[i]:SetShown(not built)
  MOTA:Fire("PAGE_SHOWN", page.id)
end

local function weekday()
  local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
  if now and CALENDAR_WEEKDAY_NAMES and CALENDAR_WEEKDAY_NAMES[now.weekday] then
    return CALENDAR_WEEKDAY_NAMES[now.weekday]
  end
  return date("%A")
end

function UI:Refresh()
  if not self.window then return end
  local name = UnitName("player") or "?"
  self.who:SetText(name)
  self.initials:SetText(name:match("^[%z\1-\127\194-\244][\128-\191]*") or "?")
  -- The canvas shows your district here; until the Citizens module, your guild rank.
  local rank = MOTA.guild and select(2, GetGuildInfo("player"))
  self.whoSmall:SetText(rank or "No guild yet")

  local left
  if MOTA.guild then
    local n = MOTA.Hello:OnlineCount()
    local last = MOTA.stats.lastReceived
    left = ("Synced with %d %s · %s"):format(n, n == 1 and "citizen" or "citizens", last and MOTA:Ago(last) or "no records yet")
  else
    left = IsInGuild() and "Waiting for the guild roster" or "Not in a guild yet"
  end
  self.footLeft:SetText(left:upper())
  local place = GetSubZoneText()
  if not place or place == "" then place = GetZoneText() or "" end
  self.footRight:SetText((place .. " · " .. weekday()):upper())
end

function UI:SavePosition()
  local point, _, relPoint, x, y = self.window:GetPoint(1)
  local w = MOTA.db.window
  w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
end

function UI:RestorePosition()
  local w = MOTA.db.window
  self.window:ClearAllPoints()
  if w.point then
    self.window:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
  else
    self.window:SetPoint("CENTER", UIParent, "CENTER", 0, -20)
  end
  self:SetScale(w.scale)
end

-- nil means the default: as large as the canvas intends, but always fitting the screen.
function UI:SetScale(scale)
  local fit = (UIParent:GetHeight() * 0.95) / (H + 90)
  local s = math.min(scale or DEFAULT_SCALE, fit)
  self.window:SetScale(math.max(0.4, s))
  return s
end

function UI:Toggle()
  local f = self:Build()
  f:SetShown(not f:IsShown())
end

---------------------------------------------------------------------------
-- The crest: our own picture, or one of the game's (see UI/Crests.lua)
---------------------------------------------------------------------------

function UI:ApplyCrest()
  if not self.crest then return end
  local p = M.pieces.crest
  local choice = MOTA.db.crest
  local t = self.crest
  t:ClearAllPoints()
  if choice and choice.atlas and C_Texture.GetAtlasInfo(choice.atlas) then
    t:SetAtlas(choice.atlas)
  elseif choice and choice.file then
    t:SetTexture(choice.file)
    t:SetTexCoord(0, 1, 0, 1)
  else
    t:SetTexture(texturePath(p.tex), "CLAMP", "CLAMP", "TRILINEAR")
    t:SetTexCoord(p.l, p.r, p.t, p.b)
    t:SetSize(p.w, p.h)
    t:SetPoint("TOPLEFT", self.window, "TOPLEFT", p.x, -p.y)
    return
  end
  -- A game texture goes in the crest's box, as a square.
  local s = M.slots.crest
  local size = math.min(s.w, s.h)
  t:SetSize(size, size)
  t:SetPoint("CENTER", self.window, "TOPLEFT", s.x + s.w / 2, -(s.y + s.h / 2))
end

-- Keep the window's live text up to date while it's open.
MOTA:Listen("RECORD_ADDED", function() if UI.window and UI.window:IsShown() then UI:Refresh() end end)
MOTA:Listen("GUILD_READY", function() if UI.window and UI.window:IsShown() then UI:Refresh() end end)
MOTA:On("ZONE_CHANGED", function() if UI.window and UI.window:IsShown() then UI:Refresh() end end)
MOTA:On("ZONE_CHANGED_NEW_AREA", function() if UI.window and UI.window:IsShown() then UI:Refresh() end end)

-- The game's add-on menu by the minimap (where the client has one).
function MinistryOfTheAllied_OnAddonCompartmentClick()
  UI:Toggle()
end
