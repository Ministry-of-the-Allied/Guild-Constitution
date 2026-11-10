-- Ministry of the Allied: the Chronicle page (ADDON_SPEC.md, section 10.3), the Throne
-- Room's second view. It is not an eighth tab: the Throne Room's "Recent decrees" has a
-- "See all" that opens it, and a "Throne Room" button here goes back.
--
--   MOTA.ThronePage:Open("chronicle")   the Chronicle, whatever page is open
--   MOTA.ThronePage:Open("state")       back to the State of the Realm
--
-- Month by month, newest first, with a filter by kind. The data is Chronicle.lua's.
-- Board: design/canvas-source/Chronicle.dc.html. UI/ThroneRoom.lua's Page:Show hands the
-- Chronicle its show and hide.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Kit = MOTA.Kit
local Page = MOTA.ThronePage

local PARCH = M.slots.parch
local LEFT, TOP = PARCH.x + 34, PARCH.y + 20
local WIDTH, HEIGHT = PARCH.w - 60, PARCH.h - 42
local HEAD_H = 72
local GRID_Y = HEAD_H + 16
local BAR_H = 28 -- the row of the back button and the filter
local BODY_Y = GRID_Y + BAR_H + 10
local BODY_H = HEIGHT - BODY_Y
local MONTH_W, GAP = 190, 14
local MAIN_X = MONTH_W + GAP
local MAIN_W = WIDTH - MAIN_X
local MONTH_ROW_H = 24
local MONTH_ROWS = math.max(3, math.floor((BODY_H - 44) / MONTH_ROW_H))
local ROW_H, ROW_Y = 26, 54
local NAV_H = 40
local ROWS = math.max(3, math.floor((BODY_H - ROW_Y - NAV_H) / ROW_H))
local FILTER_GAP = 4
-- A button wide enough for its spaced capitals (about 9.5 px a letter, and 13 px of margin each side).
local function wide(label) return math.ceil(#label * 9.5) + 26 end
local BACK_W, NAV_W = wide("< Throne Room"), wide("< Newer month")
local SCROLL_W = 8

local root, head
local monthList, main, filters = {}, {}, {}
local filter, selKey = "all", nil
local monthTop, entryTop = 0, 0 -- how far each list is scrolled (rows)

-- Opening a page from a row. ThroneRoom.lua has a go(page, view) of its own for the same
-- job; this one only needs the page.
local function go(page)
  if page then UI:SelectPage(page) end
end

local function throneIndex()
  for i, p in ipairs(M.pages) do
    if p.id == "throne" then return i end
  end
  return 1
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

---------------------------------------------------------------------------
-- The data, as the page has it now
---------------------------------------------------------------------------

local function months() return MOTA.Chronicle:Months(filter) end

-- The month being read: the chosen one if this filter has it, else the newest.
local function current()
  local list = months()
  for i, g in ipairs(list) do
    if g.key == selKey then return g, i, list end
  end
  return list[1], 1, list
end

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------

local function buildHead()
  head = {}
  head.eyebrow = Kit:Label(root, "kitTiny", "7A5719", 0.22, "The record of the realm")
  head.eyebrow:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -6)
  local title = Kit:Text(root, "heading", "1B3570")
  title:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -22)
  title:SetText("The Chronicle")
  local plate = CreateFrame("Frame", nil, root)
  plate:SetSize(236, 64)
  plate:SetPoint("TOPLEFT", root, "TOPLEFT", WIDTH - 236, 0)
  Kit:PlateArt(plate, "kitBlue", "BACKGROUND")
  local crest = UI:Piece(plate, "hseal_crown", "ARTWORK", nil, nil, nil, plate)
  crest:ClearAllPoints()
  crest:SetSize(46, 46)
  crest:SetPoint("LEFT", plate, "LEFT", 12, 0)
  head.plateEyebrow = Kit:Label(plate, "kitTiny", "C9D6F5", 0.2, "")
  head.plateEyebrow:SetPoint("TOPLEFT", plate, "TOPLEFT", 68, -16)
  head.plateText = Kit:Text(plate, "kitStage", "F3D98A")
  head.plateText:SetPoint("TOPLEFT", plate, "TOPLEFT", 68, -31)
  head.plateText:SetWidth(236 - 80)
  head.plateText:SetMaxLines(1)
  Kit:Rule(root, WIDTH):SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(HEAD_H + 4))
end

-- The back button and the filter: each filter is a quiet button with a blue one laid over it when chosen.
local function buildBar()
  local back = Kit:Button(root, BACK_W, BAR_H, "< Throne Room", "gold", function() Page:Open("state") end)
  back:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -GRID_Y)
  root.back = back
  local x = BACK_W + 16
  for _, f in ipairs(MOTA.Chronicle.FILTERS) do
    local key, w = f.key, math.max(54, wide(f.label))
    local quiet = Kit:Button(root, w, BAR_H, f.label, "quiet", function() Page:Filter(key) end)
    quiet:SetPoint("TOPLEFT", root, "TOPLEFT", x, -GRID_Y)
    local lit = Kit:Button(root, w, BAR_H, f.label, "blue", function() Page:Filter(key) end)
    lit:SetPoint("TOPLEFT", root, "TOPLEFT", x, -GRID_Y)
    filters[key] = { quiet = quiet, lit = lit }
    x = x + w + FILTER_GAP
  end
end

local function buildMonths()
  local p = CreateFrame("Frame", nil, root)
  p:SetSize(MONTH_W, BODY_H)
  p:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -BODY_Y)
  Kit:Plate(p, "plain")
  monthList.frame = p
  Kit:Label(p, "kitSection", "1B3570", 0.22, "Months"):SetPoint("TOPLEFT", p, "TOPLEFT", 16, -14)
  monthList.rows = {}
  for i = 1, MONTH_ROWS do
    local r = CreateFrame("Button", nil, p)
    r:SetSize(MONTH_W - 20, MONTH_ROW_H)
    r:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -(36 + (i - 1) * MONTH_ROW_H))
    r.fill = r:CreateTexture(nil, "BACKGROUND")
    r.fill:SetAllPoints()
    Kit:Solid(r.fill, "6E4F17", 0.22)
    r.edge = Kit:Outline(r, "6E4F17", 0.6)
    local glow = r:CreateTexture(nil, "HIGHLIGHT")
    glow:SetColorTexture(1, 0.95, 0.7, 0.25)
    glow:SetAllPoints()
    r.name = Kit:Text(r, "kitSmall")
    r.name:SetPoint("LEFT", r, "LEFT", 8, 0)
    r.name:SetWidth(MONTH_W - 20 - 8 - 34)
    r.name:SetMaxLines(1)
    r.count = Kit:Text(r, "kitItalic", "5E4B33", "RIGHT")
    r.count:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r:SetScript("OnClick", function(self)
      selKey = self.key
      entryTop = 0
      Page:RefreshChronicle()
    end)
    monthList.rows[i] = r
  end
  monthList.more = Kit:Text(p, "kitItalic", "5E4B33", "CENTER")
  monthList.more:SetPoint("BOTTOM", p, "BOTTOM", 0, 8)
  monthList.more:SetWidth(MONTH_W - 20)
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta)
    local n = #months()
    monthTop = clamp(monthTop - delta, 0, math.max(0, n - MONTH_ROWS))
    Page:RefreshChronicle()
  end)
end

local function buildMain()
  local p = CreateFrame("Frame", nil, root)
  p:SetSize(MAIN_W, BODY_H)
  p:SetPoint("TOPLEFT", root, "TOPLEFT", MAIN_X, -BODY_Y)
  Kit:Plate(p, "plain")
  main.frame = p
  main.title = Kit:Text(p, "kitStage", "1B3570")
  main.title:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -12)
  main.title:SetWidth(MAIN_W - 150)
  main.title:SetMaxLines(1)
  main.count = Kit:Label(p, "kitTiny", "7A5719", 0.2, "")
  main.count:SetPoint("TOPRIGHT", p, "TOPRIGHT", -18, -18)
  Kit:Rule(p, MAIN_W - 36):SetPoint("TOPLEFT", p, "TOPLEFT", 18, -(ROW_Y - 8))
  main.rows = {}
  local textW = MAIN_W - 36 - 58 - 16 - SCROLL_W - 8
  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, p)
    r:SetSize(MAIN_W - 36 - SCROLL_W - 8, ROW_H)
    r:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -(ROW_Y + (i - 1) * ROW_H))
    r.glow = r:CreateTexture(nil, "HIGHLIGHT")
    r.glow:SetColorTexture(1, 0.95, 0.7, 0.22)
    r.glow:SetAllPoints()
    r.date = Kit:Text(r, "kitItalic", "5E4B33")
    r.date:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.gem = Kit:Gem(r, "1B3570")
    r.gem:SetPoint("LEFT", r, "LEFT", 58, 0)
    r.text = Kit:Text(r, "kitSmall", "5E4B33")
    r.text:SetPoint("LEFT", r, "LEFT", 74, 0)
    r.text:SetWidth(textW)
    r.text:SetMaxLines(1)
    local dots = r:CreateTexture(nil, "BORDER")
    Kit:Solid(dots, "6E4F17", 0.3)
    dots:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    dots:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    dots:SetHeight(1)
    r:SetScript("OnClick", function(self) go(self.page) end)
    main.rows[i] = r
  end
  main.none = Kit:Text(p, "kitItalic", "5E4B33")
  main.none:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -(ROW_Y + 6))
  main.none:SetWidth(MAIN_W - 36)

  -- a slim bar beside a month with more lines than fit: click it to page, or use the wheel
  local bar = CreateFrame("Button", nil, p)
  bar:SetSize(SCROLL_W, ROWS * ROW_H)
  bar:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -ROW_Y)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  Kit:Solid(track, "6E4F17", 0.18)
  track:SetAllPoints()
  Kit:Outline(bar, "6E4F17", 0.4)
  local thumb = bar:CreateTexture(nil, "ARTWORK")
  Kit:Track(function()
    local silver = MOTA.skin and MOTA.skin.METAL == "silver"
    Kit:Gradient(thumb, silver and "6B7483" or "8A6420", silver and "EEF2F6" or "E9C979", 1, 1, true)
  end)
  bar:SetScript("OnClick", function()
    local _, y = GetCursorPosition()
    local top = thumb:GetTop() or 0
    entryTop = entryTop + ((y / (bar:GetEffectiveScale() or 1)) > top and -ROWS or ROWS)
    Page:RefreshChronicle()
  end)
  main.bar, main.thumb = bar, thumb

  -- older and newer month
  main.newer = Kit:Button(p, NAV_W, 26, "< Newer month", "quiet", function() Page:Step(-1) end)
  main.newer:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 18, 10)
  main.older = Kit:Button(p, NAV_W, 26, "Older month >", "quiet", function() Page:Step(1) end)
  main.older:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -18, 10)
  main.range = Kit:Text(p, "kitItalic", "5E4B33", "CENTER")
  main.range:SetPoint("BOTTOM", p, "BOTTOM", 0, 16)
  main.range:SetWidth(MAIN_W - 2 * (NAV_W + 28))
  main.range:SetMaxLines(1)
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta)
    entryTop = entryTop - delta
    Page:RefreshChronicle()
  end)
end

local function build()
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
  buildHead()
  buildBar()
  buildMonths()
  buildMain()
  Page.chronicle, Page.chronicleHead, Page.chronicleMain = root, head, main -- for the pretend client's checks
end

---------------------------------------------------------------------------
-- Filling it in
---------------------------------------------------------------------------

function Page:RefreshChronicle()
  if not root or not root:IsShown() or not MOTA.guild then return end
  local C = MOTA.Chronicle
  local g, index, list = current()
  selKey = g and g.key or nil

  local total = C:Count(filter)
  local all = C:All(filter)
  local oldest = all[#all]
  head.plateEyebrow:SetText(oldest and ("Since " .. date("%d %b %Y", oldest.t)) or "Nothing yet")
  head.plateText:SetText(total .. (total == 1 and " entry" or " entries"))
  for key, f in pairs(filters) do
    f.lit:SetShown(key == filter)
    f.quiet:SetShown(key ~= filter)
  end

  -- the months
  monthTop = clamp(monthTop, 0, math.max(0, #list - MONTH_ROWS))
  if index <= monthTop then monthTop = index - 1 end
  if index > monthTop + MONTH_ROWS then monthTop = index - MONTH_ROWS end
  for i, r in ipairs(monthList.rows) do
    local m = list[monthTop + i]
    r:SetShown(m ~= nil)
    if m then
      r.key = m.key
      r.name:SetText(m.label)
      r.count:SetText(#m.lines)
      local on = m.key == selKey
      r.fill:SetShown(on)
      for _, t in ipairs(r.edge) do t:SetShown(on) end
    end
  end
  monthList.more:SetText(#list > MONTH_ROWS and "Scroll for more months" or (#list == 0 and "No months yet" or ""))

  -- the month's lines
  local lines = g and g.lines or {}
  entryTop = clamp(entryTop, 0, math.max(0, #lines - ROWS))
  main.title:SetText(g and g.label or "The Chronicle")
  main.count:SetText(#lines .. (#lines == 1 and " entry" or " entries"))
  main.none:SetShown(#lines == 0)
  main.none:SetText(filter == "all" and "Nothing has been decreed yet. Every election, result, party change, honour and game is kept here."
    or "Nothing of this kind has been recorded yet.")
  for i, r in ipairs(main.rows) do
    local e = lines[entryTop + i]
    r:SetShown(e ~= nil)
    if e then
      r.date:SetText(date("%d %b", e.t))
      Kit:Tint(r.gem, e.hex)
      r.text:SetText(e.text)
      r.page = e.page
      r.glow:SetShown(e.page ~= nil)
    end
  end
  local over = #lines > ROWS
  main.bar:SetShown(over)
  if over then
    local h = math.max(18, ROWS * ROW_H * ROWS / #lines)
    local at = entryTop / (#lines - ROWS)
    main.thumb:ClearAllPoints()
    main.thumb:SetPoint("TOPLEFT", main.bar, "TOPLEFT", 1, -(1 + at * (ROWS * ROW_H - 2 - h)))
    main.thumb:SetSize(SCROLL_W - 2, h)
  end
  main.range:SetText(#lines > 0 and ("Showing %d to %d of %d"):format(entryTop + 1, math.min(#lines, entryTop + ROWS), #lines) or "")
  main.newer:SetShown(index > 1)
  main.older:SetShown(index < #list)
end

-- one month newer (-1) or older (1)
function Page:Step(by)
  local _, index, list = current()
  local to = list[clamp(index + by, 1, math.max(1, #list))]
  if to then
    selKey = to.key
    entryTop = 0
    self:RefreshChronicle()
  end
end

function Page:Filter(key)
  filter = key
  monthTop, entryTop = 0, 0
  self:RefreshChronicle()
end

---------------------------------------------------------------------------
-- Opening it
---------------------------------------------------------------------------

-- Page:Open("chronicle") shows the Chronicle (newest month, or the month given as a second argument, "2026-11"),
-- Page:Open("state") the State of the Realm. Opens the window if it is closed.
function Page:Open(view, monthKey)
  local f = UI:Build()
  f:Show()
  self.view = view == "chronicle" and "chronicle" or "state"
  if self.view == "chronicle" then
    selKey, entryTop = monthKey, 0
    if filter ~= "all" and not monthKey then filter = "all" end
  end
  self.opening = true
  UI:SelectPage(throneIndex())
  self.opening = false
end

-- Called by Page:Show (UI/ThroneRoom.lua).
function Page:ShowChronicle(show)
  if show and not root and UI.window then build() end
  if not root then return end
  root:SetShown(show)
  if show then self:RefreshChronicle() end
end

local pending
for _, event in ipairs({ "RECORD_ADDED", "GUILD_READY", "SKIN_CHANGED" }) do
  MOTA:Listen(event, function()
    -- Many records can arrive at once: one redraw for the lot.
    if pending then return end
    pending = true
    C_Timer.After(0.2, function()
      pending = false
      Page:RefreshChronicle()
    end)
  end)
end
