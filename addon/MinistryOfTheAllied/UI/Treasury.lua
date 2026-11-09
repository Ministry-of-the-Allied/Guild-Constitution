-- Ministry of the Allied: the Treasury tab, following the Treasury board
-- (design/canvas-source/Treasury.dc.html; ADDON_SPEC.md, section 10.7).
-- Taxes & budget and the Minister's name aren't built yet.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Kit = MOTA.Kit
local Page = {}
MOTA.TreasuryPage = Page

local PAGE_ID = "treasury"
local PARCH = M.slots.parch
local LEFT, TOP = PARCH.x + 34, PARCH.y + 20
local WIDTH, HEIGHT = PARCH.w - 60, PARCH.h - 42
local ASIDE_W, GAP = 236, 20 -- the Treasury board's column (the Ring's is narrower)
local MAIN_X = ASIDE_W + GAP
local MAIN_W = WIDTH - MAIN_X
local ROW_H = 30
local CHECK_H = 118 -- the checks under the ledger
local PAGER_H = 34
local HEAD_H = 36 + 12 -- the same height as a page's ribbons
local ROWS = math.floor((HEIGHT - HEAD_H - CHECK_H - PAGER_H - 12 - ROW_H) / ROW_H)
local CHECK_ROWS = 2

local root, coffer, notCounted, counted, accounts, term, openBtn
local rows, pager, prev, nextB, emptyLine
local checkTitle, checkLine, checkRows
local first = 1

local function panel(parent, kind, x, y, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  if kind then Kit:Plate(f, kind) end
  return f
end

local function lineText(line)
  local reason = line.note or (MOTA.BankPrompt and MOTA.BankPrompt:LabelFor(line.io, line.r)) or tostring(line.r)
  return reason .. " |cff5E4B33· " .. MOTA:Short(line.who) .. (line.entered and " (entered by the Crown)" or "") .. "|r"
end

local function amountRow(parent, y, label, w)
  local name = Kit:Text(parent, "kitSmall")
  name:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -y)
  name:SetText(label)
  local value = Kit:Amount(parent, "kitAmount")
  value:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, -y)
  return value
end

-- .bar: a short track with a coloured fill (top and bottom colours), as on the board.
local BAR_W = ASIDE_W - 34 - 102 -- between the label and the amount
local function bar(parent, top, bottom)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(BAR_W, 12)
  local track = f:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  Kit:Solid(track, "6E4F17", 0.16)
  Kit:Outline(f, "6E4F17", 0.55)
  local fill = f:CreateTexture(nil, "ARTWORK")
  fill:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
  Kit:Gradient(fill, top, bottom)
  local shine = f:CreateTexture(nil, "OVERLAY")
  shine:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
  shine:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
  shine:SetHeight(1)
  Kit:Solid(shine, "FFFFFF", 0.3)
  -- frac is 0 to 1 of the track
  function f:SetFraction(frac)
    local w = (BAR_W - 2) * math.max(0, math.min(1, frac or 0))
    fill:SetWidth(math.max(0.001, w))
    fill:SetShown(w >= 1)
    shine:SetShown(w >= 1)
  end
  return f
end

-- One row of the "This term" block: a label, a bar and the amount.
local function termRow(parent, y, label, top, bottom)
  Kit:Label(parent, "kitTiny", "7A5719", 0.2, label):SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(y + 1))
  local amount = Kit:Amount(parent, "kitSmall", "1B3570")
  amount:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
  local b = bar(parent, top, bottom)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", 34, -(y + 1))
  return { bar = b, amount = amount }
end

local COFFER_H = 202 -- the board's coffer plate, with a larger seal (74; the board's icon is 46)

local function buildAside()
  local plate = panel(root, nil, 0, 0, ASIDE_W, COFFER_H)
  Kit:PlateArt(plate, "kitBlue", "BACKGROUND")
  local seal = UI:Piece(plate, "hseal_treasury", "ARTWORK", nil, nil, nil, plate) -- the Seal of the State, Treasury form (crossed keys)
  seal:ClearAllPoints()
  seal:SetSize(74, 74)
  seal:SetPoint("TOP", plate, "TOP", 0, -14)
  Kit:Label(plate, "kitTiny", "C9D6F5", 0.28, "The Guild Coffers"):SetPoint("TOP", plate, "TOP", 0, -96)
  coffer = Kit:Coffer(plate, ASIDE_W - 32)
  coffer:SetPoint("TOP", plate, "TOP", 0, -116)
  notCounted = Kit:Text(plate, "kitStage", "F3D98A", "CENTER")
  notCounted:SetPoint("TOP", plate, "TOP", 0, -129)
  notCounted:SetWidth(ASIDE_W - 32)
  counted = Kit:Text(plate, "kitSmallest", "C9D5F0", "CENTER")
  counted:SetPoint("TOP", plate, "TOP", 0, -165)
  counted:SetWidth(ASIDE_W - 32)

  local acc = panel(root, "plain", 0, COFFER_H + 14, ASIDE_W, 118)
  Kit:Label(acc, "kitSection", "1B3570", 0.22, "The accounts"):SetPoint("TOPLEFT", acc, "TOPLEFT", 14, -12)
  Kit:Rule(acc, ASIDE_W - 28):SetPoint("TOPLEFT", acc, "TOPLEFT", 14, -30)
  accounts = {
    treasury = amountRow(acc, 38, "Guild Treasury"),
    sh = amountRow(acc, 62, "Silverhand"),
    ex = amountRow(acc, 86, "Exchange"),
  }

  -- "This term": money in and out, as bars against the larger of the two,
  -- from the start of the government's term (Ledger:ThisTerm).
  local block = panel(root, nil, 0, COFFER_H + 14 + 118 + 14, ASIDE_W, 70)
  Kit:Label(block, "kitSection", "1B3570", 0.22, "This term"):SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
  term = {
    moneyIn = termRow(block, 24, "In", "3E9A6E", "1F6B4A"),
    moneyOut = termRow(block, 46, "Out", "C2413C", "8A161C"),
  }

  local foot = panel(root, nil, 0, HEIGHT - 58, ASIDE_W, 58)
  local line = foot:CreateTexture(nil, "ARTWORK")
  Kit:Solid(line, "6E4F17", 0.35)
  line:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, 0)
  line:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, 0)
  line:SetHeight(1)
  Kit:Label(foot, "kitTiny", "7A5719", 0.02, "Minister of the Treasury"):SetPoint("TOPLEFT", foot, "TOPLEFT", 46, -7)
  -- the initials circle wears the window skin's colour (Exchange red, Crown plum...)
  local portrait = UI:SkinPiece(foot, "portrait", "metal", "ARTWORK", nil, nil, nil, nil, foot)
  portrait:ClearAllPoints()
  portrait:SetSize(36, 36)
  portrait:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, -14)
  local initials = Kit:Text(foot, "initials", "F3D98A", "CENTER")
  initials:SetPoint("CENTER", portrait, "CENTER", 0, 0)
  initials:SetText("—")
  root.ministerInitials = initials
  local name = Kit:Text(foot, "kitNameSmall")
  name:SetPoint("TOPLEFT", foot, "TOPLEFT", 46, -20)
  name:SetWidth(ASIDE_W - 46)
  name:SetText("None appointed")
  local awaiting = Kit:Text(foot, "kitSmallest", "5E4B33")
  awaiting:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
  awaiting:SetText("Appointed by the PM")
  root.ministerName, root.ministerLine = name, awaiting
end

local function column(row, font, hex, justify, x, w)
  local t = Kit:Text(row, font, hex, justify)
  t:SetPoint("LEFT", row, "LEFT", x, 0)
  t:SetWidth(w)
  t:SetMaxLines(1)
  return t
end

local DATE_W, MONEY_W = 58, 88
local function buildLedger()
  local heading = Kit:Text(root, "kitChamber", "1B3570")
  heading:SetPoint("TOPLEFT", root, "TOPLEFT", MAIN_X, -8)
  heading:SetText("The Ledger")
  Kit:Label(root, "kitTiny", "7A5719", 0.2, "Every line is public"):SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -16)
  local sheet = panel(root, nil, MAIN_X, HEAD_H, MAIN_W, ROW_H * (ROWS + 1))
  Kit:Fill(sheet, "F7EED5", "F7EED5")
  Kit:Outline(sheet, "6E4F17", 0.5)
  local margin = sheet:CreateTexture(nil, "BORDER")
  Kit:Solid(margin, "9E1B22", 0.55)
  margin:SetPoint("TOPLEFT", sheet, "TOPLEFT", DATE_W, 0)
  margin:SetPoint("BOTTOMLEFT", sheet, "BOTTOMLEFT", DATE_W, 0)
  margin:SetWidth(1)

  local entryW = MAIN_W - DATE_W - MONEY_W * 2 - 24
  local head = panel(sheet, nil, 0, 0, MAIN_W, ROW_H)
  Kit:Label(head, "kitTiny", "7A5719", 0.2, "Date"):SetPoint("LEFT", head, "LEFT", 10, 0)
  Kit:Label(head, "kitTiny", "7A5719", 0.2, "Entry"):SetPoint("LEFT", head, "LEFT", DATE_W + 10, 0)
  Kit:Label(head, "kitTiny", "7A5719", 0.2, "In"):SetPoint("RIGHT", head, "RIGHT", -MONEY_W - 14, 0)
  Kit:Label(head, "kitTiny", "7A5719", 0.2, "Out"):SetPoint("RIGHT", head, "RIGHT", -10, 0)

  rows = {}
  for i = 1, ROWS + 1 do
    local rule = sheet:CreateTexture(nil, "BORDER")
    Kit:Solid(rule, "3A63B8", i == 1 and 0.45 or 0.28)
    rule:SetPoint("TOPLEFT", sheet, "TOPLEFT", 0, -i * ROW_H)
    rule:SetPoint("TOPRIGHT", sheet, "TOPRIGHT", 0, -i * ROW_H)
    rule:SetHeight(1)
  end
  for i = 1, ROWS do
    local r = panel(sheet, nil, 0, i * ROW_H, MAIN_W, ROW_H)
    r.date = column(r, "kitTiny", "5E4B33", "LEFT", 8, DATE_W - 10)
    r.entry = column(r, "kitSmall", "2A1F14", "LEFT", DATE_W + 10, entryW)
    r.moneyIn = Kit:Amount(r, "kitSmall", "1F6B4A")
    r.moneyIn:SetPoint("RIGHT", r, "LEFT", MAIN_W - MONEY_W - 12, 0)
    r.moneyOut = Kit:Amount(r, "kitSmall", "8E1B1B")
    r.moneyOut:SetPoint("RIGHT", r, "LEFT", MAIN_W - 8, 0)
    rows[i] = r
  end
  emptyLine = Kit:Text(sheet, "kitItalic", "5E4B33", "CENTER")
  emptyLine:SetPoint("TOP", sheet, "TOP", 0, -ROW_H - 8)
  emptyLine:SetWidth(MAIN_W - 40)

  local y = HEAD_H + ROW_H * (ROWS + 1) + 5
  prev = Kit:Button(root, 90, 26, "Newer", "quiet", function()
    first = math.max(1, first - ROWS)
    Page:Refresh()
  end)
  prev:SetPoint("TOPLEFT", root, "TOPLEFT", MAIN_X, -y)
  nextB = Kit:Button(root, 90, 26, "Older", "quiet", function()
    first = first + ROWS
    Page:Refresh()
  end)
  nextB:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -y)
  pager = Kit:Text(root, "kitSmallest", "5E4B33", "CENTER")
  pager:SetPoint("TOP", root, "TOPLEFT", MAIN_X + MAIN_W / 2, -(y + 6))
  pager:SetWidth(MAIN_W - 200)
end

local function buildChecks()
  local c = panel(root, "sunk", MAIN_X, HEIGHT - CHECK_H, MAIN_W, CHECK_H)
  checkTitle = Kit:Label(c, "kitTiny", "7A5719", 0.2, "The balance check")
  checkTitle:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -11)
  checkLine = Kit:Text(c, "kitSmall")
  checkLine:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -27)
  checkLine:SetWidth(MAIN_W - 28)
  openBtn = Kit:Button(c, 200, 36, "Open the books", "gold", function()
    local rec, err = MOTA.Ledger:OpenBooks()
    if not rec then MOTA:Print(err) end
  end)
  openBtn:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -14, 14)
  checkRows = {}
  for i = 1, CHECK_ROWS do
    local r = panel(c, nil, 14, 52 + (i - 1) * 31, MAIN_W - 28, 28)
    r.text = column(r, "kitSmallest", "5E4B33", "LEFT", 0, MAIN_W - 180)
    r.button = Kit:Button(r, 136, 26, "Add a reason", "quiet", function()
      if r.entry then MOTA.Bank:AskFor(r.entry) end
    end)
    r.button:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    checkRows[i] = r
  end
end

function Page:Refresh()
  if not root then return end
  local L = MOTA.Ledger
  local data = L:Get()
  local isCrown = MOTA.me ~= nil and MOTA:IsCrown(MOTA.me)
  local opened = data.open ~= nil

  local function setAmount(box, copper)
    box:SetShown(opened)
    box:SetCopper(copper or 0, 2)
  end
  coffer:SetShown(opened)
  if opened then coffer:SetCopper(data.balance) end
  notCounted:SetShown(not opened)
  notCounted:SetText("Not yet counted")
  counted:SetText(opened and ("Counted · " .. date("%d %b", data.balanceAt)) or "The books aren't open")
  setAmount(accounts.treasury, data.treasury)
  setAmount(accounts.sh, MOTA.Party:Funds("sh"))
  setAmount(accounts.ex, MOTA.Party:Funds("ex"))
  local termIn, termOut = L:ThisTerm()
  local sums = { moneyIn = termIn, moneyOut = termOut }
  local biggest = math.max(termIn, termOut)
  for key, row in pairs(term) do
    setAmount(row.amount, sums[key])
    row.bar:SetShown(opened)
    row.bar:SetFraction(biggest > 0 and sums[key] / biggest or 0)
  end

  local canOpen = isCrown and not opened
  openBtn:SetShown(canOpen)
  openBtn:SetEnabled(MOTA.Bank.seenBalance ~= nil)
  openBtn:SetAlpha(MOTA.Bank.seenBalance ~= nil and 1 or 0.45)

  local lines, total = L:Page(first, ROWS)
  if first > total and total > 0 then
    first = 1
    lines, total = L:Page(first, ROWS)
  end
  for i, r in ipairs(rows) do
    local line = lines[i]
    r:SetShown(line ~= nil)
    if line then
      r.date:SetText(date("%d %b", line.t):upper())
      r.entry:SetText(lineText(line))
      r.moneyIn:SetShown(line.io ~= "w")
      r.moneyOut:SetShown(line.io == "w")
      r.moneyIn:SetCopper(line.amt, 2)
      r.moneyOut:SetCopper(line.amt, 2)
    end
  end
  emptyLine:SetShown(total == 0)
  emptyLine:SetText(opened and "Nothing has moved since the books opened." or "The books are closed: nothing at the bank is logged until a King opens them.")
  prev:SetShown(first > 1)
  nextB:SetShown(first + ROWS <= total)
  pager:SetText(total > 0 and ("%d to %d of %d"):format(first, math.min(first + ROWS - 1, total), total) or "")

  local minister = L:Minister()
  root.ministerName:SetText(minister and MOTA:Short(minister) or "None appointed")
  root.ministerInitials:SetText(MOTA:Initials(minister, "—"))
  root.ministerLine:SetText(minister and "In the Cabinet" or "Appointed by the PM")

  local unmatched = L:Unmatched()
  if not opened then
    checkLine:SetText(not isCrown and "The check starts once a King opens the books."
      or (MOTA.Bank.seenBalance and ("Opening starts the ledger at " .. MOTA:Money(MOTA.Bank.seenBalance) .. ".")
      or "Open the guild bank to count the balance, then open the books."))
  elseif data.unexplained == 0 then
    checkLine:SetText("The books balance. Every coin is accounted for.")
  else
    checkLine:SetText(("|cff8E1B1B%s %s|r than the ledger says. Unexplained, or not yet synced."):format(
      MOTA:Money(math.abs(data.unexplained)), data.unexplained > 0 and "more in the bank" or "less in the bank"))
  end
  for i, r in ipairs(checkRows) do
    local e = unmatched[i]
    r:SetShown(e ~= nil)
    if e then
      r.entry = e
      r.text:SetText(("%s %s %s, no reason given"):format(MOTA:Short(e.name),
        e.kind == "repair" and "repaired for" or (e.kind == "withdraw" and "withdrew" or "deposited"), MOTA:Money(e.amount)))
      r.button:SetShown(isCrown or (MOTA.me ~= nil and L:Minister() == MOTA.me)) -- the Minister of the Treasury too (not for party money)
    end
  end
end

local function build()
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
  buildAside()
  buildLedger()
  buildChecks()
end

function Page:Show(show)
  if show and not root then build() end
  if not root then return end
  root:SetShown(show)
  if show then self:Refresh() end
end

MOTA:Listen("PAGE_SHOWN", function(_, id) Page:Show(id == PAGE_ID) end)
MOTA:Listen("LEDGER_CHANGED", function() Page:Refresh() end)
