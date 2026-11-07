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
local ASIDE_W, GAP = 206, 20 -- the same column as the Ring
local MAIN_X = ASIDE_W + GAP
local MAIN_W = WIDTH - MAIN_X
local ROW_H = 30
local CHECK_H = 118 -- the checks under the ledger
local PAGER_H = 34
local HEAD_H = 36 + 12 -- the same height as a page's ribbons
local ROWS = math.floor((HEIGHT - HEAD_H - CHECK_H - PAGER_H - 12 - ROW_H) / ROW_H)
local CHECK_ROWS = 2

local root, coffer, counted, accounts, inOut, openBtn
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

local function buildAside()
  local plate = panel(root, nil, 0, 0, ASIDE_W, 158)
  Kit:Art(plate, "kitBlue", "BACKGROUND"):SetAllPoints()
  local seal = UI:Piece(plate, "hseal_official", "ARTWORK", nil, nil, nil, plate)
  seal:ClearAllPoints()
  seal:SetSize(44, 44)
  seal:SetPoint("TOP", plate, "TOP", 0, -14)
  Kit:Label(plate, "kitTiny", "C9D6F5", 0.28, "The Guild Coffers"):SetPoint("TOP", plate, "TOP", 0, -63)
  coffer = Kit:Text(plate, "kitStage", "F3D98A", "CENTER")
  coffer:SetPoint("TOP", plate, "TOP", 0, -80)
  coffer:SetWidth(ASIDE_W - 16)
  counted = Kit:Text(plate, "kitSmallest", "C9D5F0", "CENTER")
  counted:SetPoint("TOP", coffer, "BOTTOM", 0, -3)
  counted:SetWidth(ASIDE_W - 16)

  local acc = panel(root, "plain", 0, 170, ASIDE_W, 118)
  Kit:Label(acc, "kitSection", "1B3570", 0.22, "The accounts"):SetPoint("TOPLEFT", acc, "TOPLEFT", 14, -12)
  Kit:Rule(acc, ASIDE_W - 28):SetPoint("TOPLEFT", acc, "TOPLEFT", 14, -30)
  accounts = {
    treasury = amountRow(acc, 38, "Guild Treasury"),
    sh = amountRow(acc, 62, "Silverhand"),
    ex = amountRow(acc, 86, "Exchange"),
  }

  local since = panel(root, "sunk", 0, 300, ASIDE_W, 86)
  Kit:Label(since, "kitTiny", "7A5719", 0.2, "Since the books opened"):SetPoint("TOPLEFT", since, "TOPLEFT", 14, -12)
  inOut = { moneyIn = amountRow(since, 32, "In"), moneyOut = amountRow(since, 56, "Out") }

  local foot = panel(root, nil, 0, HEIGHT - 58, ASIDE_W, 58)
  local line = foot:CreateTexture(nil, "ARTWORK")
  Kit:Solid(line, "6E4F17", 0.35)
  line:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, 0)
  line:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, 0)
  line:SetHeight(1)
  Kit:Label(foot, "kitTiny", "7A5719", 0.02, "Minister of the Treasury"):SetPoint("TOPLEFT", foot, "TOPLEFT", 46, -7)
  local portrait = UI:Piece(foot, "portrait", "ARTWORK", nil, nil, nil, foot)
  portrait:ClearAllPoints()
  portrait:SetSize(36, 36)
  portrait:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, -14)
  local initials = Kit:Text(foot, "initials", "F3D98A", "CENTER")
  initials:SetPoint("CENTER", portrait, "CENTER", 0, 0)
  initials:SetText("—")
  local name = Kit:Text(foot, "kitNameSmall")
  name:SetPoint("TOPLEFT", foot, "TOPLEFT", 46, -20)
  name:SetWidth(ASIDE_W - 46)
  name:SetText("None appointed")
  local awaiting = Kit:Text(foot, "kitSmallest", "5E4B33")
  awaiting:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
  awaiting:SetText("Appointed by the PM")
end

local function column(row, font, hex, justify, x, w)
  local t = Kit:Text(row, font, hex, justify)
  t:SetPoint("LEFT", row, "LEFT", x, 0)
  t:SetWidth(w)
  t:SetMaxLines(1)
  return t
end

local DATE_W, MONEY_W = 58, 84
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
    r.moneyIn = column(r, "kitSmall", "1F6B4A", "RIGHT", MAIN_W - MONEY_W * 2 - 12, MONEY_W)
    r.moneyOut = column(r, "kitSmall", "8E1B1B", "RIGHT", MAIN_W - MONEY_W - 8, MONEY_W)
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
    box:SetGold((copper or 0) / 10000)
  end
  coffer:SetText(opened and MOTA:Money(data.balance) or "Not yet counted")
  counted:SetText(opened and ("Counted · " .. date("%d %b", data.balanceAt)) or "The books aren't open")
  setAmount(accounts.treasury, data.treasury)
  setAmount(accounts.sh, MOTA.Party:Funds("sh"))
  setAmount(accounts.ex, MOTA.Party:Funds("ex"))
  setAmount(inOut.moneyIn, data.moneyIn)
  setAmount(inOut.moneyOut, data.moneyOut)

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
      r.moneyIn:SetText(line.io ~= "w" and MOTA:Money(line.amt) or "")
      r.moneyOut:SetText(line.io == "w" and MOTA:Money(line.amt) or "")
    end
  end
  emptyLine:SetShown(total == 0)
  emptyLine:SetText(opened and "Nothing has moved since the books opened." or "A King opens the books, and the ledger starts from there.")
  prev:SetShown(first > 1)
  nextB:SetShown(first + ROWS <= total)
  pager:SetText(total > 0 and ("%d to %d of %d"):format(first, math.min(first + ROWS - 1, total), total) or "")

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
      r.button:SetShown(isCrown)
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
