-- Ministry of the Allied: the Statute Book page, following the Statute Book
-- board (design/canvas-source/StatuteBook.dc.html; ADDON_SPEC.md, sections 10.8, 10.10, 12.6).
-- Four views under the ribbons: In force, Awaiting, Court rulings, and the Charter
-- (UI/Constitution.lua draws that one). The laws, bills and rulings themselves are
-- not built yet, so each view shows its layout with an honest empty state. They
-- read from these hooks, which the lawmaking and the Court will provide:
--   MOTA.Laws:InForce()  { { title, area, text, author, assent, expires, due, used } }
--                        due is "Expires in 41 days", used is 0 to 1 of the three months gone
--   MOTA.Laws:Awaiting() { { kind = "Bill" or "Renewal", area, title, line, stage = 1 to 3, canAct } }
--                        stage: 1 Proposed, 2 Council, 3 Assent. A renewal has no stage.
--   MOTA.Laws:Renew(item), MOTA.Laws:Lapse(item)
--   MOTA.Court:Rulings() { { title, punishment, tone, line, note } } newest first
--   MOTA.Court:Ladder()  { censure, fine, embargo, suspension, exile } this term

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Kit = MOTA.Kit
local Page = {}
MOTA.StatutesPage = Page

local PAGE_ID = "statute"
local PARCH = M.slots.parch
local LEFT, TOP = PARCH.x + 34, PARCH.y + 20
local WIDTH, HEIGHT = PARCH.w - 60, PARCH.h - 44
local BOOK_TOP = 36 + 16
local BOOK_H = HEIGHT - BOOK_TOP

local VIEWS = {
  { id = "force", n = 8 }, { id = "wait", n = 9 }, { id = "court", n = 10 }, { id = "charter", n = 4 },
}

local root, ribbons, views, count
local view = "force"
local selected = 1

local function panel(parent, kind, x, y, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  if kind then Kit:Plate(f, kind) end
  return f
end

---------------------------------------------------------------------------
-- Where the data comes from (nothing yet: the views show their empty state)
---------------------------------------------------------------------------

local function laws() return MOTA.Laws and MOTA.Laws.InForce and MOTA.Laws:InForce() or {} end
local function awaiting() return MOTA.Laws and MOTA.Laws.Awaiting and MOTA.Laws:Awaiting() or {} end
local function rulings() return MOTA.Court and MOTA.Court.Rulings and MOTA.Court:Rulings() or {} end
local function ladder() return MOTA.Court and MOTA.Court.Ladder and MOTA.Court:Ladder() or { 0, 0, 0, 0, 0 } end

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

---------------------------------------------------------------------------
-- Small parts
---------------------------------------------------------------------------

-- .chip: a coloured tag with a gold diamond.
local function chip(parent)
  local c = CreateFrame("Frame", nil, parent)
  c:SetHeight(22)
  local fill = c:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints()
  Kit:Outline(c, "000000", 0.28)
  local gem = Kit:Gem(c, "F3D98A")
  gem:SetPoint("LEFT", c, "LEFT", 8, 0)
  c.label = Kit:Label(c, "kitTiny", "FFFFFF", 0.14)
  c.label:SetPoint("LEFT", c, "LEFT", 22, 0)
  function c:Set(text, hex)
    Kit:Solid(fill, hex or "5E4B33")
    self.label:SetText(text)
    self:SetWidth(30 + (self.label:GetWidth() or 60))
  end
  return c
end

-- .bar.gold: a short track with a gold fill.
local function goldBar(parent, width)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, 9)
  local track = f:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  Kit:Solid(track, "6E4F17", 0.16)
  Kit:Outline(f, "6E4F17", 0.55)
  local fill = f:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
  Kit:Gradient(fill, "FFF3C4", "C9A24A")
  function f:SetFraction(frac)
    local w = (width - 2) * math.max(0, math.min(1, frac or 0))
    fill:SetWidth(math.max(0.001, w))
    fill:SetShown(w >= 1)
  end
  return f
end

local function dottedLine(parent, y, width, x)
  local t = parent:CreateTexture(nil, "BORDER")
  Kit:Solid(t, "6E4F17", 0.3)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, -y)
  t:SetSize(width, 1)
  return t
end

---------------------------------------------------------------------------
-- In force: the index of statutes, and the page of the one chosen
---------------------------------------------------------------------------

local MAX_LAWS = 8
local ROW_H = 46
local GUTTER = math.floor(WIDTH * 0.465)
local R_X = GUTTER + 40            -- the right page's text, from the book's left edge
local R_W = WIDTH - R_X - 34

-- The ribbon mark hangs over the top right of the right page. Text that starts
-- beside it is set in two parts: the lines level with the ribbon stop just short
-- of it, and the rest runs the full width below (Max, 8 Nov).
local MARK_W, MARK_H, MARK_RIGHT, MARK_TOP = 23, 97, 42, 6
local MARK_NARROW = WIDTH - MARK_RIGHT - MARK_W - 8 - R_X -- text width beside the ribbon (8 clear of it)
local MARK_FOOT = MARK_H - MARK_TOP + 4                    -- how far down the book the ribbon reaches (+4)

local EMPTY_FORCE = "A law takes effect once the government has passed it and a King has given Royal Assent. It will be set down here, and lapses after three months unless the government renews it."

local function besideMark(book, font, hex, spacing)
  local s = { spacing = spacing or 0 }
  s.top = Kit:Text(book, font, hex)
  s.top:SetWidth(MARK_NARROW)
  s.rest = Kit:Text(book, font, hex)
  s.rest:SetWidth(R_W)
  s.rest:SetPoint("TOPLEFT", s.top, "BOTTOMLEFT", 0, -s.spacing)
  s.top:SetSpacing(s.spacing)
  s.rest:SetSpacing(s.spacing)
  s.probe = Kit:Text(book, font, hex)
  s.probe:SetWordWrap(false)
  s.probe:Hide()

  -- y: how far below the book's top edge the text starts
  function s:Set(text, y)
    self.top:ClearAllPoints()
    self.top:SetPoint("TOPLEFT", book, "TOPLEFT", R_X, -y)
    self.probe:SetText("Ag")
    local lineH = self.probe:GetStringHeight() + self.spacing
    local beside = math.max(0, math.ceil((MARK_FOOT - y) / lineH))
    -- only the first paragraph can reach the ribbon
    local first, after = (text or ""):match("^([^\n]*)\n?(.*)$")
    local words = {}
    for w in first:gmatch("%S+") do words[#words + 1] = w end
    local lines, i = {}, 1
    while i <= #words and #lines < beside do
      local line = words[i]
      i = i + 1
      while i <= #words do
        self.probe:SetText(line .. " " .. words[i])
        if self.probe:GetStringWidth() > MARK_NARROW then break end
        line = line .. " " .. words[i]
        i = i + 1
      end
      lines[#lines + 1] = line
    end
    self.top:SetText(table.concat(lines, "\n"))
    local rest = table.concat(words, " ", i)
    if after ~= "" then rest = rest ~= "" and (rest .. "\n" .. after) or after end
    self.rest:SetText(rest)
  end
  function s:SetShown(on)
    self.top:SetShown(on)
    self.rest:SetShown(on)
  end
  return s
end

local function buildForce(v)
  local book = panel(v, nil, 0, 0, WIDTH, BOOK_H)
  Kit:Fill(book, "F6ECD2", "F6ECD2")
  Kit:Outline(book, "6E4F17", 0.6)
  local gutter = book:CreateTexture(nil, "BORDER")
  Kit:Solid(gutter, "6E4F17", 0.3)
  gutter:SetSize(2, BOOK_H)
  gutter:SetPoint("TOPLEFT", book, "TOPLEFT", GUTTER, 0)

  -- the left page: the index
  local lw = GUTTER - 24 - 30
  local head = Kit:Label(book, "kitTiny", "7A5719", 0.3, "Index of statutes")
  head:SetPoint("TOP", book, "TOPLEFT", 24 + lw / 2, -22)
  Kit:Rule(book, lw):SetPoint("TOPLEFT", book, "TOPLEFT", 24, -44)
  v.rows = {}
  for i = 1, MAX_LAWS do
    local b = CreateFrame("Button", nil, book)
    b:SetSize(lw + 8, ROW_H)
    b:SetPoint("TOPLEFT", book, "TOPLEFT", 20, -(56 + (i - 1) * ROW_H))
    b.bg = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.bg:SetAllPoints()
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetColorTexture(0.79, 0.64, 0.29, 0.12)
    glow:SetAllPoints()
    dottedLine(b, ROW_H - 1, lw + 8)
    b.roman = Kit:Text(b, "kitRoman", "7A5719", "CENTER")
    b.roman:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.roman:SetWidth(30)
    b.title = Kit:Text(b, "kitName", "2A1F14")
    b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 40, -7)
    b.title:SetWidth(lw - 40)
    b.title:SetMaxLines(1)
    b.due = Kit:Text(b, "kitSmallest", "5E4B33")
    b.due:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -1)
    b:SetScript("OnClick", function() selected = i Page:Refresh() end)
    v.rows[i] = b
  end
  v.none = Kit:Text(book, "kitItalic", "5E4B33", "CENTER")
  v.none:SetPoint("TOP", book, "TOPLEFT", 24 + lw / 2, -78)
  v.none:SetWidth(lw - 10)
  v.none:SetText("No law is in force yet.")

  -- the right page: the statute
  local mark = Kit:AccentArt(book, "kitMark", "ARTWORK")
  mark:SetPoint("TOPRIGHT", book, "TOPRIGHT", -MARK_RIGHT, MARK_TOP)
  v.eyebrow = Kit:Label(book, "kitTiny", "7A5719", 0.3)
  v.eyebrow:SetPoint("TOPLEFT", book, "TOPLEFT", R_X, -26)
  v.title = Kit:Text(book, "kitLawTitle", "1B3570")
  v.title:SetPoint("TOPLEFT", book, "TOPLEFT", R_X, -46)
  v.title:SetWidth(R_W - 50)
  v.text = besideMark(book, "kitProse", "2A1F14", 3)
  v.facts = Kit:Text(book, "kitSmall", "2A1F14")
  v.factLabels = Kit:Text(book, "kitTiny", "7A5719")
  v.factLabels:SetPoint("TOPLEFT", v.text.rest, "BOTTOMLEFT", 0, -16)
  v.factLabels:SetSpacing(10)
  v.factLabels:SetText("AUTHOR\nROYAL ASSENT\nEXPIRES")
  v.facts:SetPoint("TOPLEFT", v.factLabels, "TOPRIGHT", 22, 3)
  v.facts:SetWidth(R_W - 120)
  v.facts:SetSpacing(5)
  v.bar = goldBar(book, R_W)
  v.bar:SetPoint("TOPLEFT", v.factLabels, "BOTTOMLEFT", 0, -22)
  v.barNote = Kit:Text(book, "kitItalic", "5E4B33")
  v.barNote:SetPoint("TOPLEFT", v.bar, "BOTTOMLEFT", 0, -6)
  v.barNote:SetWidth(R_W)
  v.barNote:SetText("All laws lapse after three months unless the government renews them.")
  v.empty = besideMark(book, "kitItalic", "5E4B33")
  v.empty:Set(EMPTY_FORCE, 60)
  -- Given under the seal of the Crown
  local seal = Kit:Art(book, "hseal_crown", "ARTWORK")
  seal:SetSize(58, 58)
  seal:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", R_X, 20)
  local l1 = Kit:Label(book, "kitTiny", "7A5719", 0.3, "Given under the seal")
  l1:SetPoint("LEFT", seal, "RIGHT", 12, 7)
  local l2 = Kit:Label(book, "kitTiny", "7A5719", 0.3, "of the Crown")
  l2:SetPoint("LEFT", seal, "RIGHT", 12, -7)
  return book
end

local function refreshForce(v)
  local list = laws()
  if selected > #list then selected = 1 end
  local law = list[selected]
  for i, b in ipairs(v.rows) do
    local l = list[i]
    b:SetShown(l ~= nil)
    if l then
      local on = i == selected
      local ink = MOTA:Accent().INK
      Kit:Gradient(b.bg, ink, ink, on and 0.13 or 0, 0, true)
      b.roman:SetText(ROMAN[i] or tostring(i))
      b.roman:SetTextColor(MOTA:RGB(on and ink or "7A5719"))
      b.title:SetText(l.title)
      b.due:SetText(l.due or "")
    end
  end
  v.none:SetShown(#list == 0)
  v.empty:SetShown(law == nil)
  if not law then v.empty:Set(EMPTY_FORCE, 60) end -- re-set, in case the text size changed
  for _, r in ipairs({ v.eyebrow, v.title, v.text, v.facts, v.factLabels, v.bar, v.barNote }) do r:SetShown(law ~= nil) end
  if law then
    v.eyebrow:SetText(("Statute %s · %s"):format(ROMAN[selected] or selected, law.area or ""))
    v.title:SetText(law.title)
    v.text:Set(law.text or "", 46 + v.title:GetStringHeight() + 12)
    v.facts:SetText(("%s\n%s\n%s"):format(law.author or "", law.assent or "", law.expires or ""))
    v.bar:SetFraction(law.used)
  end
  return #list
end

---------------------------------------------------------------------------
-- Awaiting: bills on their way, and laws up for renewal
---------------------------------------------------------------------------

local MAX_BILLS, BILL_H, BILL_GAP = 4, 76, 14
local STEPS = { "Proposed", "Council", "Assent" }

local function buildWait(v)
  v.plates = {}
  for i = 1, MAX_BILLS do
    local p = panel(v, "plain", 0, (i - 1) * (BILL_H + BILL_GAP), WIDTH, BILL_H)
    p.eyebrow = Kit:Label(p, "kitTiny", "7A5719", 0.2)
    p.eyebrow:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -14)
    p.name = Kit:Text(p, "kitName", "2A1F14")
    p.name:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -29)
    p.name:SetWidth(WIDTH - 400)
    p.name:SetMaxLines(1)
    p.line = Kit:Text(p, "kitSmall", "5E4B33")
    p.line:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -2)
    p.line:SetWidth(WIDTH - 400)
    p.line:SetMaxLines(1)
    -- the three steps
    p.steps = {}
    for s = 1, 3 do
      local cell = CreateFrame("Frame", nil, p)
      cell:SetSize(110, 52)
      cell:SetPoint("TOPRIGHT", p, "TOPRIGHT", -18 - (3 - s) * 110, -12)
      cell.mark = Kit:Art(cell, "kitStepTodo", "ARTWORK")
      cell.mark:SetPoint("TOP", cell, "TOP", 0, -4)
      cell.label = Kit:Label(cell, "kitTiny", "5E4B33", 0.14, STEPS[s])
      cell.label:SetPoint("TOP", cell, "TOP", 0, -34)
      p.steps[s] = cell
    end
    p.lapse = Kit:Button(p, 112, 30, "Let it lapse", "quiet", function()
      if p.item and MOTA.Laws and MOTA.Laws.Lapse then MOTA.Laws:Lapse(p.item) end
    end)
    p.lapse:SetPoint("RIGHT", p, "RIGHT", -18 - 82, 0)
    p.renew = Kit:Button(p, 74, 30, "Renew", "blue", function()
      if p.item and MOTA.Laws and MOTA.Laws.Renew then MOTA.Laws:Renew(p.item) end
    end)
    p.renew:SetPoint("RIGHT", p, "RIGHT", -18, 0)
    v.plates[i] = p
  end
  v.none = panel(v, "sunk", 0, 0, WIDTH, 74)
  v.none.title = Kit:Text(v.none, "kitName", "2A1F14")
  v.none.title:SetPoint("TOPLEFT", v.none, "TOPLEFT", 18, -17)
  v.none.title:SetText("Nothing is waiting")
  v.none.line = Kit:Text(v.none, "kitSmall", "5E4B33")
  v.none.line:SetPoint("TOPLEFT", v.none.title, "BOTTOMLEFT", 0, -3)
  v.none.line:SetText("A bill appears here once it is laid before the Crown, and a law once it is up for renewal.")
  v.note = Kit:Text(v, "kitItalic", "5E4B33", "CENTER")
  v.note:SetPoint("BOTTOM", v, "BOTTOM", 0, 12)
  v.note:SetWidth(WIDTH - 40)
  v.note:SetText("Only the Prime Minister and the Cabinet see the Renew controls. The Crown alone may give or refuse Assent.")
end

local function refreshWait(v)
  local list = awaiting()
  for i, p in ipairs(v.plates) do
    local it = list[i]
    p:SetShown(it ~= nil)
    if it then
      p.item = it
      p.eyebrow:SetText(("%s · %s"):format(it.kind or "Bill", it.area or ""))
      p.name:SetText(it.title)
      p.line:SetText(it.line or "")
      local renewal = it.kind == "Renewal"
      for s, cell in ipairs(p.steps) do
        cell:SetShown(not renewal)
        local look = it.stage and (s < it.stage and "kitStepDone" or (s == it.stage and "kitStepNow" or "kitStepTodo")) or "kitStepTodo"
        Kit:Look(cell.mark, look)
      end
      p.lapse:SetShown(renewal)
      p.renew:SetShown(renewal)
      for _, b in ipairs({ p.lapse, p.renew }) do
        b:SetEnabled(it.canAct and true or false)
        b:SetAlpha(it.canAct and 1 or 0.45)
      end
    end
  end
  v.none:SetShown(#list == 0)
  return #list
end

---------------------------------------------------------------------------
-- Court rulings, the Lay a charge plate and the ladder of punishments
---------------------------------------------------------------------------

local COURT_W = WIDTH - 200 - 20
local MAX_RULINGS = 3
local TONES = { censure = "5E4B33", fine = "B0621C", embargo = "6B44A8", suspension = "9E1B22", exile = "6E1712" }
local RUNGS = { "1 · Censure", "2 · Fine", "3 · Embargo", "4 · Suspension", "5 · Exile" }

local function buildCourt(v)
  v.rulings = {}
  for i = 1, MAX_RULINGS do
    local p = panel(v, "plain", 0, (i - 1) * 92, COURT_W, 80)
    p.seal = Kit:Art(p, "hseal_official", "ARTWORK")
    p.seal:SetSize(46, 46)
    p.seal:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -16)
    p.title = Kit:Text(p, "kitName", "2A1F14")
    p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 74, -14)
    p.title:SetWidth(COURT_W - 74 - 150)
    p.title:SetMaxLines(1)
    p.chip = chip(p)
    p.chip:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -12)
    p.line = Kit:Text(p, "kitSmall", "2A1F14")
    p.line:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -4)
    p.line:SetWidth(COURT_W - 74 - 20)
    p.line:SetMaxLines(1)
    p.note = Kit:Text(p, "kitItalic", "5E4B33")
    p.note:SetPoint("TOPLEFT", p.line, "BOTTOMLEFT", 0, -2)
    p.note:SetWidth(COURT_W - 74 - 20)
    p.note:SetMaxLines(1)
    v.rulings[i] = p
  end
  v.none = panel(v, "plain", 0, 0, COURT_W, 80)
  v.none.title = Kit:Text(v.none, "kitName", "2A1F14")
  v.none.title:SetPoint("TOPLEFT", v.none, "TOPLEFT", 74, -22)
  v.none.title:SetText("No rulings yet")
  v.none.line = Kit:Text(v.none, "kitSmall", "5E4B33")
  v.none.line:SetPoint("TOPLEFT", v.none.title, "BOTTOMLEFT", 0, -3)
  v.none.line:SetWidth(COURT_W - 90)
  v.none.line:SetText("The High Judiciary's rulings are published here.")
  local seal = Kit:Art(v.none, "hseal_official", "ARTWORK")
  seal:SetSize(46, 46)
  seal:SetPoint("TOPLEFT", v.none, "TOPLEFT", 16, -17)

  -- Bring an accusation
  local acc = panel(v, "sunk", 0, 3 * 92, COURT_W, 76)
  local gem = Kit:Gem(acc, "7A5719")
  gem:SetPoint("LEFT", acc, "LEFT", 26, 0)
  local t = Kit:Text(acc, "kitName", "2A1F14")
  t:SetPoint("TOPLEFT", acc, "TOPLEFT", 74, -16)
  t:SetText("Bring an accusation")
  local d = Kit:Text(acc, "kitSmall", "5E4B33")
  d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
  d:SetWidth(COURT_W - 74 - 176)
  d:SetText("Any citizen may lay a charge before the High Judiciary.")
  v.charge = Kit:Button(acc, 140, 36, "Lay a charge", "blue", function() end)
  v.charge:SetPoint("RIGHT", acc, "RIGHT", -16, 0)
  v.charge:SetEnabled(false)
  v.charge:SetAlpha(0.45) -- the Court opens in a later version

  -- the ladder
  local x = COURT_W + 20
  local head = Kit:Label(v, "kitSection", "1B3570", 0.22, "The ladder")
  head:SetPoint("TOPLEFT", v, "TOPLEFT", x, 0)
  v.rungs = {}
  for i = 1, 5 do
    local r = panel(v, nil, x, 24 + (i - 1) * 37, 200, 31)
    local exile = i == 5
    Kit:Outline(r, exile and "6E1712" or "6E4F17", exile and 0.6 or 0.4)
    r.name = Kit:Label(r, "kitTiny", exile and "6E1712" or "5E4B33", 0.12, RUNGS[i])
    r.name:SetPoint("LEFT", r, "LEFT", 10, 0)
    r.n = Kit:Text(r, "kitAmount", exile and "6E1712" or "1B3570", "RIGHT")
    r.n:SetPoint("RIGHT", r, "RIGHT", -10, 0)
    v.rungs[i] = r
  end
  local note = Kit:Text(v, "kitItalic", "5E4B33")
  note:SetPoint("TOPLEFT", v, "TOPLEFT", x, 24 + 5 * 37 + 4)
  note:SetWidth(200)
  note:SetText("Rulings this term. Exile needs the Crown's signature.")
end

local function refreshCourt(v)
  local list = rulings()
  for i, p in ipairs(v.rulings) do
    local r = list[i]
    p:SetShown(r ~= nil)
    if r then
      p.title:SetText(r.title)
      p.chip:Set(r.punishment or "", TONES[r.tone or "censure"] or TONES.censure)
      p.line:SetText(r.line or "")
      p.note:SetText(r.note or "")
    end
  end
  v.none:SetShown(#list == 0)
  local counts = ladder()
  for i, r in ipairs(v.rungs) do r.n:SetText(tostring(counts[i] or 0)) end
  return #list
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local BUILD = { force = buildForce, wait = buildWait, court = buildCourt }
local REFRESH = { force = refreshForce, wait = refreshWait, court = refreshCourt }

-- The root other files hang the Charter view on.
function Page:Root() return root end

function Page:Refresh()
  if not root or not root:IsShown() then return end
  local n
  if REFRESH[view] then n = REFRESH[view](views[view]) end
  if view == "force" then
    count:Set(("%d %s"):format(n, n == 1 and "law" or "laws"), "in force")
  elseif view == "wait" then
    count:Set(tostring(n), "awaiting")
  elseif view == "court" then
    count:Set(tostring(n), n == 1 and "ruling" or "rulings")
  else
    count:Set("Ten", "readings")
  end
end

function Page:Select(name)
  view = name
  if not root then return end
    for _, def in ipairs(VIEWS) do
    ribbons[def.id]:SetOn(def.id == name)
    if views[def.id] then views[def.id]:SetShown(def.id == name) end
  end
  if MOTA.ConstitutionPage then MOTA.ConstitutionPage:Show(name == "charter") end
  self:Refresh()
end

local function build()
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
  ribbons, views = {}, {}
  local x = 0
  for _, def in ipairs(VIEWS) do
    local id = def.id
    local b = Kit:Ribbon(root, def.n, function() Page:Select(id) end)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", x, 0)
    x = x + b:GetWidth() + 2
    ribbons[id] = b
    if BUILD[id] then
      local v = CreateFrame("Frame", nil, root)
      v:SetSize(WIDTH, BOOK_H)
      v:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -BOOK_TOP)
      BUILD[id](v)
      v:Hide()
      views[id] = v
    end
  end
  -- The count sits on two right-aligned lines ("0 laws" over "in force"),
  -- so it stays clear of the fourth ribbon.
  local line = MOTA:FontSize("kitTiny") * 1.25 + 2
  local top = Kit:Label(root, "kitTiny", "7A5719", 0.3)
  top:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -(18 - line))
  local bottom = Kit:Label(root, "kitTiny", "7A5719", 0.3)
  bottom:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -18)
  count = {}
  function count:Set(a, b)
    top:SetText(a)
    bottom:SetText(b)
  end
end

function Page:Show(show)
  if show and not root then build() end
  if not root then return end
  root:SetShown(show)
  if show then self:Select(view) end
end

MOTA:Listen("PAGE_SHOWN", function(_, id) Page:Show(id == PAGE_ID) end)
MOTA:Listen("SKIN_CHANGED", function() Page:Refresh() end)
