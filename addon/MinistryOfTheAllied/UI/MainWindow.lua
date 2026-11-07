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

-- Tab colours by look, from the skin's tokens (UI/Skin.lua, ADDON_SPEC.md 9.3).
local TAB_TOKENS = {
  rest = { label = "TAB_INK", small = "TAB_SMALL" },
  hover = { label = "TAB_INK_HOVER", small = "TAB_SMALL" },
  on = { label = "TAB_INK_ON", small = "TAB_SMALL_ON" },
}

local DEFAULT_SCALE = 0.85

-- Every texture that changes with the skin, so a new skin can be put on at once.
local skinned = {}
local setTabLook -- below, with the tabs

-- Pages that fill the whole parchment themselves: the heading, divider,
-- eyebrow and note are hidden there (the Ballot Hall, UI/BallotHall.lua).
UI.fullPages = { ballot = true }

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
  -- A frame piece the skins own (the portrait ring) follows the skin's metal.
  if not M.pieces[name] and MOTA.skin and M.pieces[self:SkinName(name, "metal")] then
    return self:SkinPiece(parent, name, "metal", layer, sublevel, dx, dy, nil, anchor or parent)
  end
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
  self:SetPiece(t, name, dx, dy, anchor)
  return t
end

-- Puts a piece on an existing texture. at = { x, y } places it there instead
-- of where the layout has it; flipH, flipV mirror it.
function UI:SetPiece(t, name, dx, dy, anchor, at, flipH, flipV)
  local p = M.pieces[name]
  t:SetTexture(texturePath(p.tex), "CLAMP", "CLAMP", "TRILINEAR")
  local l, r, tp, b = p.l, p.r, p.t, p.b
  if flipH then l, r = r, l end
  if flipV then tp, b = b, tp end
  t:SetTexCoord(l, r, tp, b)
  t:SetSize(p.w, p.h)
  t:ClearAllPoints()
  local x, y = p.x + (dx or 0), p.y + (dy or 0)
  if at then x, y = at[1], at[2] end
  t:SetPoint("TOPLEFT", anchor or self.window, "TOPLEFT", x, -y)
end

-- The piece's name in the current skin: per skin ("crown:leather") or per
-- metal ("gold:tabOn").
function UI:SkinName(base, kind)
  local s = MOTA.skin
  local name = (kind == "metal" and s.METAL or s.FILE) .. ":" .. base
  -- a blue part drawn again in the skin's accent (the initials bubble): "gold:portrait~cr"
  return M.pieces[name .. MOTA:Accent().SUFFIX] and (name .. MOTA:Accent().SUFFIX) or name
end

-- A piece that changes with the skin. place(t) may put it somewhere of its
-- own after the skin's piece is set (the corners, the subtitle's rules).
-- anchor: a page piece its page places itself; a new skin then changes only
-- its picture and leaves where it sits alone.
function UI:SkinPiece(parent, base, kind, layer, sublevel, dx, dy, place, anchor)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
  local entry = { t = t, base = base, kind = kind, dx = dx, dy = dy, place = place, anchor = anchor }
  skinned[#skinned + 1] = entry
  self:ApplySkinPiece(entry)
  return t
end

function UI:ApplySkinPiece(e)
  if e.base == "cornerGem" then
    local g = MOTA.skin.GEM
    e.t:SetVertexColor(g.r, g.g, g.b)
  end
  if e.anchor and e.applied then
    local p = M.pieces[self:SkinName(e.base, e.kind)]
    e.t:SetTexture(texturePath(p.tex), "CLAMP", "CLAMP", "TRILINEAR")
    e.t:SetTexCoord(p.l, p.r, p.t, p.b)
    return
  end
  e.applied = true
  self:SetPiece(e.t, self:SkinName(e.base, e.kind), e.dx, e.dy, e.anchor)
  if e.place then e.place(e.t, M.pieces[self:SkinName(e.base, e.kind)]) end
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

-- Colours a texture or text with one of the skin's tokens.
local function ink(region, token)
  local c = MOTA.skin[token]
  if region:GetObjectType() == "FontString" then
    region:SetTextColor(c.r, c.g, c.b)
  else
    region:SetVertexColor(c.r, c.g, c.b)
  end
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
-- The frame, in layers (ADDON_SPEC.md 9.7): the skin's leather, the shared
-- grain tiled over it, the metal's rim and rules, the parchment page with
-- its metal rim, and the filigree corners.
---------------------------------------------------------------------------

-- The filigree corner is drawn once (top right); the bottom two are mirror images.
local function placeCorner(corner, base)
  base = base or "corner"
  return function(t, p)
    local tr, s = M.slots["corner-tr"], M.slots["corner-" .. corner]
    local ox, oy = p.x - tr.x, p.y - tr.y
    if corner == "bl" then
      UI:SetPiece(t, UI:SkinName(base, "metal"), 0, 0, nil, { s.x + s.w - ox - p.w, s.y + s.h - oy - p.h }, true, true)
    else
      UI:SetPiece(t, UI:SkinName(base, "metal"), 0, 0, nil, { s.x + ox, s.y + s.h - oy - p.h }, false, true)
    end
  end
end

function UI:BuildFrame(f)
  self:SkinPiece(f, "leather", "skin", "BACKGROUND", -6)
  local lr = M.slots.leather
  local grain = f:CreateTexture(nil, "BACKGROUND", nil, -5)
  grain:SetTexture(texturePath("grain"), "REPEAT", "REPEAT", "TRILINEAR")
  grain:SetTexCoord(0, lr.w / M.grain.tile, 0, lr.h / M.grain.tile)
  grain:SetSize(lr.w, lr.h)
  grain:SetPoint("TOPLEFT", f, "TOPLEFT", lr.x, -lr.y)
  for _, part in ipairs(M.frameParts) do
    self:SkinPiece(f, part, "metal", "BACKGROUND", -4)
  end
  self:Piece(f, "parch", "BACKGROUND", -3)
  self:SkinPiece(f, "corner", "metal", "BORDER", 0)
  self:SkinPiece(f, "corner", "metal", "BORDER", 0, 0, 0, placeCorner("bl"))
  self:SkinPiece(f, "corner", "metal", "BORDER", 0, 0, 0, placeCorner("br"))
  -- The jewels sit on top of the corners, tinted for the skin (Skin.lua: GEM).
  self:SkinPiece(f, "cornerGem", "metal", "BORDER", 1)
  self:SkinPiece(f, "cornerGem", "metal", "BORDER", 1, 0, 0, placeCorner("bl", "cornerGem"))
  self:SkinPiece(f, "cornerGem", "metal", "BORDER", 1, 0, 0, placeCorner("br", "cornerGem"))
end

-- The two rules either side of the page's name, which is a different width on each page.
function UI:PlaceSubRule(t, right)
  local sub = M.pieces["subtitle" .. (self.page or 1)]
  local p = M.pieces[self:SkinName("subRule", "metal")]
  if right then
    self:SetPiece(t, self:SkinName("subRule", "metal"), 0, 0, nil, { sub.x + sub.w + M.subRule.gapR, p.y }, true, false)
  else
    self:SetPiece(t, self:SkinName("subRule", "metal"), 0, 0, nil, { sub.x - M.subRule.gapL - p.w, p.y }, false, false)
  end
end

-- Colours the window's labels and live text with the skin's tokens.
function UI:InkWindow()
  for i, tab in ipairs(self.tabs) do setTabLook(tab, tab.look or "rest") end
  for _, sub in ipairs(self.subtitles) do ink(sub, "SUBTITLE") end
  if self.heading then self.heading:SetTextColor(MOTA:RGB(MOTA:Accent().INK)) end
  ink(self.who, "NAME_INK")
  ink(self.whoSmall, "PALE_INK")
  ink(self.footLeft, "PALE_INK")
  ink(self.footRight, "PALE_INK")
end

-- A new skin: every skinned piece, the crest and the colours, at once.
function UI:ReSkin()
  if not self.window then return end
  for _, e in ipairs(skinned) do self:ApplySkinPiece(e) end
  self:ApplyCrest()
  self:InkWindow()
  self:WearDivider()
end

-- The divider under the page's name has a jewel in the skin's accent.
function UI:WearDivider()
  local t = self.divider
  if not t then return end
  local p = M.pieces["divider" .. MOTA:Accent().SUFFIX] or M.pieces.divider
  t:SetTexture(texturePath(p.tex), "CLAMP", "CLAMP", "TRILINEAR")
  t:SetTexCoord(p.l, p.r, p.t, p.b)
end

MOTA:Listen("SKIN_CHANGED", function() UI:ReSkin() end)

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

function setTabLook(tab, look)
  local tokens = TAB_TOKENS[look]
  tab.look = look
  tab.bgRest:SetShown(look == "rest")
  tab.bgHover:SetShown(look == "hover")
  tab.bgOn:SetShown(look == "on")
  ink(tab.icon, tokens.label)
  ink(tab.label, tokens.label)
  ink(tab.small, tokens.small)
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
  tab.bgRest = UI:SkinPiece(tab, "tabRest", "skin", "BACKGROUND", 0, 0, dyRest)
  tab.bgHover = UI:SkinPiece(tab, "tabHover", "skin", "BACKGROUND", 0, 0, dyRest)
  tab.bgOn = UI:SkinPiece(tab, "tabOn", "metal", "BACKGROUND", 0, 0, dyOn)
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
  UI:SkinPiece(b, piece, "skin", "ARTWORK")
  local glow = UI:SkinPiece(b, piece, "skin", "HIGHLIGHT")
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
  self:BuildFrame(f)

  -- Header: the title, and the page's name under it between two rules.
  self:SkinPiece(f, "title", "metal", "ARTWORK")
  self.subtitles, self.eyebrows = {}, {}
  for i = 1, #M.pages do
    self.subtitles[i] = self:Piece(f, "subtitle" .. i, "ARTWORK")
    self.eyebrows[i] = self:Piece(f, "eyebrow" .. i, "ARTWORK")
  end
  self.subRules = {
    self:SkinPiece(f, "subRule", "metal", "ARTWORK", 0, 0, 0, function(t) UI:PlaceSubRule(t, false) end),
    self:SkinPiece(f, "subRule", "metal", "ARTWORK", 0, 0, 0, function(t) UI:PlaceSubRule(t, true) end),
  }
  buildKnob(f, "knobSettings", "knob-settings", "Settings", function() UI:OpenSettings() end)
  buildKnob(f, "knobClose", "knob-close", "Close", function() f:Hide() end)

  -- The tab rail.
  self.tabs = {}
  for i = 1, #M.pages do self.tabs[i] = buildTab(f, i) end
  buildSheen(f)

  -- The rail's foot: who you are.
  self:SkinPiece(f, "railLine", "metal", "ARTWORK")
  self:SkinPiece(f, "portrait", "metal", "ARTWORK")
  self.initials = text(f, "initials", "F3D98A")
  local ps = M.slots.portrait
  self.initials:SetPoint("CENTER", f, "TOPLEFT", ps.x + ps.w / 2, -(ps.y + ps.h / 2))
  self.who = text(f, "who", "FBEFC4")
  self:AtSlot(self.who, "who")
  self.whoSmall = text(f, "whoSmall", "AFC0E6")
  self.whoSmall:SetPoint("TOPLEFT", self.who, "BOTTOMLEFT", 0, -2)

  -- The page: heading, divider and a note about what the page will hold.
  self.divider = self:Piece(f, "divider", "ARTWORK")
  self:WearDivider()
  local note = M.slots.note
  self.heading = text(f, "heading", "1B3570")
  self.heading:SetTextColor(MOTA:RGB(MOTA:Accent().INK))
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

  -- The status strip along the bottom (coloured by UI:InkWindow).
  self:SkinPiece(f, "pip", "metal", "ARTWORK")
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
  self.crest = top:CreateTexture(nil, "ARTWORK")
  self:ApplyCrest()
  self:InkWindow()

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
  local full = UI.fullPages[M.pages[i].id]
  for n, tab in ipairs(self.tabs) do
    setTabLook(tab, n == i and "on" or "rest")
    self.subtitles[n]:SetShown(n == i)
    self.eyebrows[n]:SetShown(n == i and not full)
  end
  self.heading:SetShown(not full)
  self.divider:SetShown(not full)
  self:PlaceSubRule(self.subRules[1], false)
  self:PlaceSubRule(self.subRules[2], true)
  local slot = M.slots["tab" .. i]
  self.sheenClip:ClearAllPoints()
  self.sheenClip:SetPoint("TOPLEFT", self.window, "TOPLEFT", slot.x, -slot.y)
  local page = M.pages[i]
  self.heading:SetText(page.heading)
  self.note:SetText(page.note)
  -- A page with its own contents replaces the note about what it will hold.
  local built = page.id == "statute" or page.id == "ring" or page.id == "parties" or page.id == "treasury" or full
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
  local p = M.pieces[self:SkinName("crest", "skin")] -- the skin's own emblem (9.2)
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
