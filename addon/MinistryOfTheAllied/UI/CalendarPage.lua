-- Ministry of the Allied: the Calendar, the Throne Room's third view (Duncan, 14 Nov 2026).
-- Like the Chronicle it is not a tab of its own: "Calendar" on the Throne Room's Recent
-- decrees opens it, and "< Throne Room" goes back.
--
--   MOTA.ThronePage:Open("calendar")   the Calendar, at this month
--
-- A month on the left, Monday first, with each day's dates as coloured lines; the chosen
-- day's dates on the right. The data is Calendar.lua's. The Crown has a button to post the
-- coming election dates to the game's guild calendar.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Kit = MOTA.Kit
local Page = MOTA.ThronePage

local PARCH = M.slots.parch
local LEFT, TOP = PARCH.x + 34, PARCH.y + 20
local WIDTH, HEIGHT = PARCH.w - 60, PARCH.h - 42
local HEAD_H = 72
local BAR_Y = HEAD_H + 16
local BAR_H = 28
local BODY_Y = BAR_Y + BAR_H + 10
local BODY_H = HEIGHT - BODY_Y
local SIDE_W, GAP = 252, 14
local GRID_W = WIDTH - SIDE_W - GAP
local WEEK_H = 18
local CELL_W = math.floor((GRID_W - 16) / 7)
local CELL_H = math.floor((BODY_H - 16 - WEEK_H) / 6)
local CELL_LINES = math.max(1, math.floor((CELL_H - 18) / 12))
local DAY_ROWS = 6
local DAY_ROW_H = math.floor((BODY_H - 56) / DAY_ROWS)
local WEEKDAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

local function wide(label) return math.ceil(#label * 9.5) + 26 end
local BACK_W = wide("< Throne Room")

local root, head, bar, grid, side
local year, month, selDay -- the month shown, and the chosen day (a timestamp at its midnight)

local function today() return MOTA.Calendar:DayStart(time()) end

local function monthStart(y, m) return time({ year = y, month = m, day = 1, hour = 0 }) end

-- Monday = 1 ... Sunday = 7
local function weekday(t) return (date("*t", t).wday + 5) % 7 + 1 end

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------

local function buildHead()
  head = {}
  Kit:Label(root, "kitTiny", "7A5719", 0.22, "The dates of the realm"):SetPoint("TOPLEFT", root, "TOPLEFT", 0, -6)
  local title = Kit:Text(root, "heading", "1B3570")
  title:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -22)
  title:SetText("The Calendar")
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

local function buildBar()
  bar = {}
  local back = Kit:Button(root, BACK_W, BAR_H, "< Throne Room", "gold", function() Page:Open("state") end)
  back:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -BAR_Y)
  local x = BACK_W + 16
  local prev = Kit:Button(root, 36, BAR_H, "<", "quiet", function() Page:StepMonth(-1) end)
  prev:SetPoint("TOPLEFT", root, "TOPLEFT", x, -BAR_Y)
  bar.month = Kit:Text(root, "kitStage", "1B3570", "CENTER")
  bar.month:SetPoint("LEFT", prev, "RIGHT", 6, 0)
  bar.month:SetWidth(150)
  bar.month:SetMaxLines(1)
  local nxt = Kit:Button(root, 36, BAR_H, ">", "quiet", function() Page:StepMonth(1) end)
  nxt:SetPoint("LEFT", prev, "RIGHT", 162, 0)
  local now = Kit:Button(root, wide("Today"), BAR_H, "Today", "quiet", function() Page:CalendarGoto() end)
  now:SetPoint("LEFT", nxt, "RIGHT", 8, 0)
  -- the Crown's: post the coming dates to the game's guild calendar
  bar.post = Kit:Button(root, wide("Post to guild calendar"), BAR_H, "Post to guild calendar", "blue", function()
    local n, why = MOTA.Calendar:PostAll()
    if not n then MOTA:Print(why) end
    Page:RefreshCalendar()
  end)
  bar.post:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -BAR_Y)
end

local function buildGrid()
  local p = CreateFrame("Frame", nil, root)
  p:SetSize(GRID_W, BODY_H)
  p:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -BODY_Y)
  Kit:Plate(p, "plain")
  grid = { frame = p, cells = {} }
  for i, name in ipairs(WEEKDAYS) do
    local l = Kit:Label(p, "kitTiny", "7A5719", 0.2, name:upper())
    l:SetPoint("TOP", p, "TOPLEFT", 8 + (i - 0.5) * CELL_W, -8)
  end
  for i = 1, 42 do
    local col, row = (i - 1) % 7, math.floor((i - 1) / 7)
    local c = CreateFrame("Button", nil, p)
    c:SetSize(CELL_W - 2, CELL_H - 2)
    c:SetPoint("TOPLEFT", p, "TOPLEFT", 8 + col * CELL_W + 1, -(8 + WEEK_H + row * CELL_H + 1))
    c.fill = c:CreateTexture(nil, "BACKGROUND")
    c.fill:SetAllPoints()
    Kit:Solid(c.fill, "6E4F17", 0.08)
    c.sel = c:CreateTexture(nil, "BORDER")
    c.sel:SetAllPoints()
    Kit:Solid(c.sel, "1B3570", 0.16)
    c.todayEdge = Kit:Outline(c, "8B2A1E", 0.9, 0, 2)
    local glow = c:CreateTexture(nil, "HIGHLIGHT")
    glow:SetColorTexture(1, 0.95, 0.7, 0.25)
    glow:SetAllPoints()
    c.num = Kit:Text(c, "kitSmall", "2A1F14")
    c.num:SetPoint("TOPLEFT", c, "TOPLEFT", 4, -3)
    c.lines = {}
    for j = 1, CELL_LINES do
      local stripe = c:CreateTexture(nil, "ARTWORK")
      stripe:SetSize(3, 10)
      stripe:SetPoint("TOPLEFT", c, "TOPLEFT", 3, -(18 + (j - 1) * 12))
      local t = Kit:Text(c, "kitSmallest", "2A1F14")
      t:SetPoint("TOPLEFT", c, "TOPLEFT", 9, -(17 + (j - 1) * 12))
      t:SetWidth(CELL_W - 14)
      t:SetMaxLines(1)
      c.lines[j] = { stripe = stripe, text = t }
    end
    c:SetScript("OnClick", function(self)
      if self.day then
        selDay = self.day
        local d = date("*t", self.day)
        if d.month ~= month then year, month = d.year, d.month; MOTA.Calendar:LoadMonth(year, month) end
        Page:RefreshCalendar()
      end
    end)
    grid.cells[i] = c
  end
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta) Page:StepMonth(delta > 0 and -1 or 1) end)
end

local function buildSide()
  local p = CreateFrame("Frame", nil, root)
  p:SetSize(SIDE_W, BODY_H)
  p:SetPoint("TOPLEFT", root, "TOPLEFT", GRID_W + GAP, -BODY_Y)
  Kit:Plate(p, "plain")
  side = { frame = p, rows = {} }
  side.title = Kit:Text(p, "kitStage", "1B3570")
  side.title:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -12)
  side.title:SetWidth(SIDE_W - 32)
  side.title:SetMaxLines(1)
  Kit:Rule(p, SIDE_W - 32):SetPoint("TOPLEFT", p, "TOPLEFT", 16, -40)
  for i = 1, DAY_ROWS do
    local r = CreateFrame("Frame", nil, p)
    r:SetSize(SIDE_W - 32, DAY_ROW_H)
    r:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -(48 + (i - 1) * DAY_ROW_H))
    r.gem = Kit:Gem(r, "1B3570")
    r.gem:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -3)
    r.head = Kit:Text(r, "kitSmall", "2A1F14")
    r.head:SetPoint("TOPLEFT", r, "TOPLEFT", 16, 0)
    r.head:SetWidth(SIDE_W - 48)
    r.head:SetMaxLines(1)
    r.text = Kit:Text(r, "kitItalic", "5E4B33")
    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 16, -15)
    r.text:SetWidth(SIDE_W - 48)
    r.text:SetMaxLines(math.max(1, math.floor((DAY_ROW_H - 18) / 12)))
    side.rows[i] = r
  end
  side.none = Kit:Text(p, "kitItalic", "5E4B33")
  side.none:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -52)
  side.none:SetWidth(SIDE_W - 32)
  side.more = Kit:Text(p, "kitItalic", "5E4B33", "CENTER")
  side.more:SetPoint("BOTTOM", p, "BOTTOM", 0, 8)
  side.more:SetWidth(SIDE_W - 32)
end

local function build()
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
  buildHead()
  buildBar()
  buildGrid()
  buildSide()
  Page.calendar, Page.calendarGrid, Page.calendarSide, Page.calendarBar = root, grid, side, bar -- for the pretend client's checks
end

---------------------------------------------------------------------------
-- Filling it in
---------------------------------------------------------------------------

local function timeOf(e)
  local c = date("*t", e.t)
  if c.hour == 0 and c.min == 0 then return "" end
  return ("%d:%02d "):format(c.hour, c.min)
end

local function until_(t)
  local d = math.floor((MOTA.Calendar:DayStart(t) - today()) / 86400 + 0.5)
  if d <= 0 then return "Today" end
  if d == 1 then return "Tomorrow" end
  return "In " .. d .. " days"
end

function Page:RefreshCalendar()
  if not root or not root:IsShown() then return end
  local Cal = MOTA.Calendar
  if not year then local n = date("*t"); year, month = n.year, n.month end
  selDay = selDay or today()

  -- the plate: what's next
  local nxt = Cal:Next()
  head.plateEyebrow:SetText(nxt and ("Next: " .. date("%d %b", nxt.t)) or "Nothing set")
  head.plateText:SetText(nxt and (until_(nxt.t) .. ": " .. nxt.title) or "No election called")

  bar.month:SetText(date("%B %Y", monthStart(year, month)))
  local can = Cal:CanPost()
  local left = can and #Cal:ToPost() or 0
  bar.post:SetShown(MOTA.me ~= nil and MOTA:IsCrown(MOTA.me) and Cal:HasGameCalendar())
  if bar.post.SetEnabled then bar.post:SetEnabled(can and left > 0 and not Cal:Posting()) end
  bar.post:SetAlpha((can and left > 0) and 1 or 0.5)

  -- the grid: six weeks from the Monday on or before the 1st
  local first = monthStart(year, month)
  local startDay = first - (weekday(first) - 1) * 86400
  local events = Cal:Events(startDay - 86400, startDay + 43 * 86400)
  local byDay = {}
  for _, e in ipairs(events) do
    local k = Cal:DayStart(e.t)
    byDay[k] = byDay[k] or {}
    table.insert(byDay[k], e)
  end
  local now = today()
  for i, c in ipairs(grid.cells) do
    local s = date("*t", startDay)
    local day = time({ year = s.year, month = s.month, day = s.day + i - 1, hour = 0 })
    c.day = day
    local d = date("*t", day)
    local inMonth = d.month == month
    c.num:SetText(d.day)
    c.num:SetAlpha(inMonth and 1 or 0.4)
    c.fill:SetShown(inMonth)
    c.sel:SetShown(day == selDay)
    for _, t in ipairs(c.todayEdge) do t:SetShown(day == now) end
    local list = byDay[day] or {}
    for j, l in ipairs(c.lines) do
      local e = list[j]
      local last = j == #c.lines and #list > #c.lines
      l.stripe:SetShown(e ~= nil)
      l.text:SetShown(e ~= nil)
      if e then
        Kit:Solid(l.stripe, e.hex, inMonth and 1 or 0.4)
        l.text:SetText(last and ("+" .. (#list - j + 1) .. " more") or e.title)
        l.text:SetAlpha(inMonth and 1 or 0.5)
      end
    end
  end

  -- the chosen day
  local list = byDay[selDay] or Cal:ForDay(selDay)
  side.title:SetText((date("%A %d %B", selDay):gsub(" 0", " ")))
  side.none:SetShown(#list == 0)
  side.none:SetText("Nothing on this day.")
  for i, r in ipairs(side.rows) do
    local e = list[i]
    r:SetShown(e ~= nil)
    if e then
      Kit:Tint(r.gem, e.hex)
      r.head:SetText(timeOf(e) .. e.title)
      r.text:SetText(e.text)
    end
  end
  side.more:SetText(#list > #side.rows and ("And " .. (#list - #side.rows) .. " more") or
    (Cal:Posting() and "Posting to the guild calendar..." or ""))
end

function Page:StepMonth(by)
  month = (month or date("*t").month) + by
  year = year or date("*t").year
  if month < 1 then month, year = 12, year - 1 elseif month > 12 then month, year = 1, year + 1 end
  local d = date("*t", selDay or today())
  local last = date("*t", time({ year = year, month = month + 1, day = 0, hour = 0 })).day
  selDay = time({ year = year, month = month, day = math.min(d.day, last), hour = 0 })
  MOTA.Calendar:LoadMonth(year, month)
  self:RefreshCalendar()
end

-- To this month and today, or to the day of a timestamp.
function Page:CalendarGoto(t)
  selDay = MOTA.Calendar:DayStart(t or time())
  local d = date("*t", selDay)
  year, month = d.year, d.month
  MOTA.Calendar:LoadMonth(year, month)
  self:RefreshCalendar()
end

-- Called by Page:Show (UI/ThroneRoom.lua).
function Page:ShowCalendar(show)
  if show and not root and UI.window then build() end
  if not root then return end
  root:SetShown(show)
  if show then self:CalendarGoto(selDay) end
end

local pending
for _, event in ipairs({ "RECORD_ADDED", "GUILD_READY", "SKIN_CHANGED", "CONTEST_CHANGED", "CALENDAR_CHANGED" }) do
  MOTA:Listen(event, function()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function()
      pending = false
      Page:RefreshCalendar()
    end)
  end)
end
