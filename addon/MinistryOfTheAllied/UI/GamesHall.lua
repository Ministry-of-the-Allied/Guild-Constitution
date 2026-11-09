-- Ministry of the Allied: the Games Hall tab, following the Games Hall board
-- (design/canvas-source/GamesHall.dc.html; Duncan, 2026-11-08).
-- The Royal Lottery (Lottery.lua), the Roll of Honour (Honours.lua), and the
-- treasure hunt and District Cup to come. Everything blue follows the window
-- skin (Kit's accent), as on the other pages.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Kit = MOTA.Kit
local Page = {}
MOTA.GamesPage = Page

local PAGE_ID = "games"
local PARCH = M.slots.parch
local LEFT, TOP = PARCH.x + 34, PARCH.y + 20
local WIDTH, HEIGHT = PARCH.w - 60, PARCH.h - 44
local ASIDE_W, GAP = 206, 20
local MAIN_W = WIDTH - ASIDE_W - GAP
local MAIN_X = ASIDE_W + GAP
local BODY_Y = 36 + 12
local SIDE_W = 196                      -- the lottery's right-hand column
local SHEET_W = MAIN_W - SIDE_W - 14
local ROW_H, ROWS = 30, 7
local BLUE = "1B3570"                   -- the accent's ink (Kit follows the skin)

local root, aside, views, tabs
local view = "lottery"

local function panel(parent, kind, x, y, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  if kind then Kit:Plate(f, kind) end
  return f
end

local function line(parent, font, hex, x, y, w, justify)
  local t = Kit:Text(parent, font, hex, justify)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  t:SetWidth(w)
  return t
end

local function report(rec, err)
  if err then MOTA:Print("The Games Hall:", err) end
  Page:Refresh()
end

local function left(seconds)
  if seconds <= 0 then return "now" end
  local d, h = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
  if d > 0 then return d .. (d == 1 and " day " or " days ") .. h .. " h" end
  local m = math.floor(seconds % 3600 / 60)
  return h > 0 and (h .. " h " .. m .. " min") or (m .. " min")
end

local function pct(n, total)
  if total == 0 then return "" end
  local p = n / total * 100
  return (p < 1 and "<1" or tostring(math.floor(p + 0.5))) .. "%"
end

---------------------------------------------------------------------------
-- The left-hand column: the lottery plate, the pot, your tickets, the Minister
---------------------------------------------------------------------------

local function buildAside()
  aside = panel(root, nil, 0, 0, ASIDE_W, HEIGHT)
  local lot = panel(aside, nil, 0, 0, ASIDE_W, HEIGHT - 66)
  aside.lot = lot

  local plate = panel(lot, nil, 0, 0, ASIDE_W, 178)
  Kit:PlateArt(plate, "kitBlue", "BACKGROUND")
  local seal = UI:Piece(plate, "hseal_treasury", "ARTWORK", nil, nil, nil, plate)
  seal:ClearAllPoints()
  seal:SetSize(50, 50)
  seal:SetPoint("TOP", plate, "TOP", 0, -10)
  plate.eyebrow = Kit:Label(plate, "kitTiny", "C9D6F5", 0.28, "The Royal Lottery")
  plate.eyebrow:SetPoint("TOP", plate, "TOP", 0, -66)
  plate.name = Kit:Text(plate, "kitStage", "F3D98A", "CENTER")
  plate.name:SetPoint("TOP", plate, "TOP", 0, -80)
  plate.name:SetWidth(ASIDE_W - 16)
  plate.name:SetMaxLines(1)
  plate.pot = Kit:Coffer(plate, ASIDE_W - 20)
  plate.pot:SetPoint("TOP", plate, "TOP", 0, -100)
  plate.when = Kit:Text(plate, "kitSmallest", "C9D5F0", "CENTER")
  plate.when:SetPoint("TOP", plate, "TOP", 0, -146)
  plate.when:SetWidth(ASIDE_W - 16)
  aside.plate = plate

  local pot = panel(lot, "plain", 0, 190, ASIDE_W, 104)
  Kit:Label(pot, "kitSection", BLUE, 0.22, "The pot"):SetPoint("TOPLEFT", pot, "TOPLEFT", 14, -12)
  pot.rows = {}
  for i, y in ipairs({ 34, 62, 82 }) do
    local name = Kit:Text(pot, "kitSmall")
    name:SetPoint("TOPLEFT", pot, "TOPLEFT", 14, -y)
    local value = Kit:Amount(pot, "kitAmount")
    value:SetPoint("TOPRIGHT", pot, "TOPRIGHT", -14, -y)
    pot.rows[i] = { name = name, value = value }
  end
  Kit:Rule(pot, ASIDE_W - 28):SetPoint("TOPLEFT", pot, "TOPLEFT", 14, -56)
  aside.pot = pot

  local mine = panel(lot, "sunk", 0, 306, ASIDE_W, 112)
  Kit:Label(mine, "kitTiny", "7A5719", 0.2, "Your tickets"):SetPoint("TOPLEFT", mine, "TOPLEFT", 14, -12)
  mine.n = Kit:Text(mine, "kitCofferBig", BLUE)
  mine.n:SetPoint("TOPLEFT", mine, "TOPLEFT", 14, -28)
  mine.odds = Kit:Text(mine, "kitSmall")
  mine.odds:SetPoint("BOTTOMLEFT", mine.n, "BOTTOMRIGHT", 8, 4)
  mine.how = line(mine, "kitItalic", "5E4B33", 14, 68, ASIDE_W - 28)
  aside.mine = mine

  local foot = panel(aside, nil, 0, HEIGHT - 58, ASIDE_W, 58)
  local rule = foot:CreateTexture(nil, "ARTWORK")
  Kit:Solid(rule, "6E4F17", 0.35)
  rule:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, 0)
  rule:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, 0)
  rule:SetHeight(1)
  Kit:Label(foot, "kitTiny", "7A5719", 0.2, "Minister of Games"):SetPoint("TOPLEFT", foot, "TOPLEFT", 46, -7)
  local portrait = UI:SkinPiece(foot, "portrait", "metal", "ARTWORK", nil, nil, nil, nil, foot)
  portrait:ClearAllPoints()
  portrait:SetSize(36, 36)
  portrait:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, -14)
  foot.initials = Kit:Text(foot, "initials", "F3D98A", "CENTER")
  foot.initials:SetPoint("CENTER", portrait, "CENTER", 0, 0)
  foot.name = Kit:Text(foot, "kitNameSmall")
  foot.name:SetPoint("TOPLEFT", foot, "TOPLEFT", 46, -20)
  foot.name:SetWidth(ASIDE_W - 46)
  foot.name:SetMaxLines(1)
  foot.line = Kit:Text(foot, "kitSmallest", "5E4B33")
  foot.line:SetPoint("TOPLEFT", foot.name, "BOTTOMLEFT", 0, -1)
  aside.foot = foot
end

local function refreshAside()
  local Lo = MOTA.Lottery
  local L = Lo:Current()
  local stage = Lo:Stage(L)
  local live = stage == "selling" or stage == "closed"
  local p = aside.plate
  p.name:SetText(L and L.name or "No lottery yet")
  p.pot:SetShown(L ~= nil)
  if L then p.pot:SetCopper(L.pot) end
  if stage == "selling" then
    p.when:SetText("in the pot · sales close in " .. left(L.closes - GetServerTime()))
  elseif stage == "closed" then
    p.when:SetText("in the pot · waiting for the draw")
  elseif stage == "cancelled" then
    p.when:SetText(Lo:Owed(L) > 0 and "cancelled · refunds being paid" or "cancelled · everyone refunded")
  elseif stage == "drawn" then
    p.when:SetText(L.winner and ("won by " .. MOTA:Short(L.winner)) or "drawn, with no tickets sold")
  else
    p.when:SetText("The Minister of Games opens one")
  end

  local rows = aside.pot.rows
  local share = math.floor(Lo.SHARE * 100 + 0.5)
  rows[1].name:SetText(L and (#L.tickets .. (#L.tickets == 1 and " ticket" or " tickets") .. " · " .. MOTA:Money(L.price) .. " each") or "No tickets yet")
  rows[1].value:SetCopper(L and L.pot or 0)
  rows[2].name:SetText("Winner · " .. share .. "%")
  rows[2].value:SetCopper(L and L.prize or 0)
  rows[3].name:SetText("Treasury · " .. (100 - share) .. "%")
  rows[3].value:SetCopper(L and L.treasury or 0)

  local mine = aside.mine
  local n = L and Lo:TicketsOf(MOTA.me, L) or 0
  mine.n:SetText(tostring(n))
  mine.odds:SetText(L and #L.tickets > 0 and ("of " .. #L.tickets .. " · a " .. pct(n, #L.tickets) .. " chance") or "")
  if stage == "selling" then
    mine.how:SetText(n > 0 and "Buy more at the guild bank: deposit gold and choose Lottery tickets."
      or "Buy at the guild bank: deposit gold and choose Lottery tickets.")
  elseif live then
    mine.how:SetText("Sales are closed. Good luck in the draw.")
  else
    mine.how:SetText("No tickets on sale just now.")
  end

  local minister = MOTA.Games:Minister()
  aside.foot.name:SetText(minister and MOTA:Short(minister) or "None appointed")
  aside.foot.line:SetText(minister and "Runs the Games" or "The Crown runs the Games")
  aside.foot.initials:SetText(minister and MOTA:Short(minister):sub(1, 2) or "—")
end

---------------------------------------------------------------------------
-- The Lottery view: ticket holders, the fair draw, the organiser's desk, past draws
---------------------------------------------------------------------------

local function field(parent, label, x, y, w, default)
  Kit:Label(parent, "kitTiny", "7A5719", 0.2, label):SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(w, 26)
  e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(y + 15))
  e:SetAutoFocus(false)
  e:SetFontObject(MOTA:Font("kitSmall"))
  e:SetTextColor(MOTA:RGB("2A1F14"))
  e:SetTextInsets(7, 7, 0, 0)
  e:SetText(default)
  Kit:Fill(e, "FBF4E1", "F0E2BE")
  Kit:Outline(e, "6E4F17", 0.6)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEnterPressed", e.ClearFocus)
  return e
end

local function buildLottery()
  local v = panel(root, nil, MAIN_X, BODY_Y, MAIN_W, HEIGHT - BODY_Y)

  -- The sheet of ticket holders, ruled like the Treasury's ledger.
  local sheet = panel(v, nil, 0, 0, SHEET_W, ROW_H * (ROWS + 1))
  Kit:Fill(sheet, "F7EED5", "F7EED5")
  Kit:Outline(sheet, "6E4F17", 0.5)
  local head = panel(sheet, nil, 0, 0, SHEET_W, ROW_H)
  Kit:Label(head, "kitTiny", "7A5719", 0.2, "Ticket holders"):SetPoint("LEFT", head, "LEFT", 12, 0)
  Kit:Label(head, "kitTiny", "7A5719", 0.2, "Tickets"):SetPoint("RIGHT", head, "RIGHT", -86, 0)
  v.chanceHead = Kit:Label(head, "kitTiny", "7A5719", 0.2, "Chance")
  v.chanceHead:SetPoint("RIGHT", head, "RIGHT", -12, 0)
  for i = 1, ROWS do
    local rule = sheet:CreateTexture(nil, "BORDER")
    Kit:Solid(rule, "3A63B8", i == 1 and 0.45 or 0.28)
    rule:SetPoint("TOPLEFT", sheet, "TOPLEFT", 0, -i * ROW_H)
    rule:SetPoint("TOPRIGHT", sheet, "TOPRIGHT", 0, -i * ROW_H)
    rule:SetHeight(1)
  end
  v.rows = {}
  for i = 1, ROWS - 1 do
    local r = panel(sheet, nil, 0, i * ROW_H, SHEET_W, ROW_H)
    r.mine = r:CreateTexture(nil, "BACKGROUND")
    Kit:Gradient(r.mine, "C9A24A", "C9A24A", 0.30, 0.04, true)
    r.mine:SetAllPoints()
    r.name = Kit:Text(r, "kitSmall")
    r.name:SetPoint("LEFT", r, "LEFT", 12, 0)
    r.name:SetWidth(SHEET_W - 170)
    r.name:SetMaxLines(1)
    r.n = Kit:Text(r, "kitAmount", BLUE, "RIGHT")
    r.n:SetPoint("RIGHT", r, "RIGHT", -100, 0)
    r.chance = Kit:Text(r, "kitSmall", nil, "RIGHT")
    r.chance:SetPoint("RIGHT", r, "RIGHT", -16, 0)
    v.rows[i] = r
  end
  v.more = Kit:Text(sheet, "kitItalic", "5E4B33", "CENTER")
  v.more:SetPoint("BOTTOM", sheet, "BOTTOM", 0, 8)
  v.more:SetWidth(SHEET_W - 20)
  v.empty = Kit:Text(sheet, "kitItalic", "5E4B33", "CENTER")
  v.empty:SetPoint("TOP", sheet, "TOP", 0, -ROW_H - 10)
  v.empty:SetWidth(SHEET_W - 30)
  v.sheet = sheet

  -- The form to open a lottery, over the sheet (the Crown and the Minister of Games).
  local form = panel(v, "plain", 0, 0, SHEET_W, ROW_H * (ROWS + 1))
  form:SetFrameLevel(sheet:GetFrameLevel() + 5)
  Kit:Label(form, "kitSection", BLUE, 0.22, "Open a lottery"):SetPoint("TOPLEFT", form, "TOPLEFT", 16, -14)
  form.name = field(form, "Name", 16, 40, SHEET_W - 32, "The Royal Lottery")
  form.price = field(form, "Gold per ticket", 16, 92, (SHEET_W - 44) / 2, "1")
  form.days = field(form, "Days of sales", 28 + (SHEET_W - 44) / 2, 92, (SHEET_W - 44) / 2, "3")
  local note = line(form, "kitItalic", "5E4B33", 16, 148, SHEET_W - 32)
  note:SetText("The winner takes 70% of the pot and the Treasury 30%. You can't buy tickets in your own draw.")
  local open = Kit:Button(form, 120, 28, "Open it", "blue", function()
    report(MOTA.Lottery:Open(form.name:GetText(), form.price:GetText(), form.days:GetText()))
    form:Hide()
    Page:Refresh()
  end)
  open:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 16, 14)
  local cancel = Kit:Button(form, 100, 28, "Cancel", "quiet", function() form:Hide() end)
  cancel:SetPoint("LEFT", open, "RIGHT", 10, 0)
  form:Hide()
  v.form = form

  -- The right-hand column.
  local sx = MAIN_W - SIDE_W
  local fair = panel(v, "plain", sx, 0, SIDE_W, 104)
  Kit:Label(fair, "kitSection", BLUE, 0.22, "A fair draw"):SetPoint("TOPLEFT", fair, "TOPLEFT", 14, -12)
  fair.text = line(fair, "kitSmallest", nil, 14, 32, SIDE_W - 28)
  fair.seal = line(fair, "kitTiny", "5E4B33", 14, 84, SIDE_W - 28)
  v.fair = fair

  local desk = panel(v, "plain", sx, 116, SIDE_W, 124)
  Kit:Label(desk, "kitSection", BLUE, 0.22, "Organiser's desk"):SetPoint("TOPLEFT", desk, "TOPLEFT", 14, -12)
  desk.line = line(desk, "kitSmallest", nil, 14, 30, SIDE_W - 28)
  local half = (SIDE_W - 28 - 8) / 2
  desk.draw = Kit:Button(desk, half, 28, "Draw now", "blue", function() report(MOTA.Lottery:Draw()) end)
  desk.draw:SetPoint("BOTTOMLEFT", desk, "BOTTOMLEFT", 14, 46)
  -- Cancelling asks once more: the first press says "Sure?", the second cancels.
  desk.cancel = Kit:Button(desk, half, 28, "Cancel", "quiet", function(b)
    if not b.sure then
      b.sure = true
      b:SetLabel("Sure?")
      C_Timer.After(4, function() b.sure = nil; b:SetLabel("Cancel") end)
      return
    end
    b.sure = nil
    b:SetLabel("Cancel")
    report(MOTA.Lottery:Cancel())
  end)
  desk.cancel:SetPoint("BOTTOMRIGHT", desk, "BOTTOMRIGHT", -14, 46)
  desk.open = Kit:Button(desk, SIDE_W - 28, 28, "Open a lottery", "quiet", function() form:Show() end)
  desk.open:SetPoint("BOTTOMLEFT", desk, "BOTTOMLEFT", 14, 12)
  v.desk = desk

  local buy = panel(v, "sunk", sx, 116, SIDE_W, 124)
  Kit:Label(buy, "kitTiny", "7A5719", 0.2, "How to buy"):SetPoint("TOPLEFT", buy, "TOPLEFT", 14, -12)
  local how = line(buy, "kitSmallest", nil, 14, 30, SIDE_W - 28)
  how:SetText("Deposit gold in the guild bank and choose Lottery tickets as the reason. Each whole ticket price buys a ticket.")
  v.buy = buy

  -- Past draws.
  local py = ROW_H * (ROWS + 1) + 12
  local past = panel(v, "sunk", 0, py, MAIN_W, HEIGHT - BODY_Y - py)
  Kit:Label(past, "kitSection", BLUE, 0.22, "Past draws"):SetPoint("TOPLEFT", past, "TOPLEFT", 14, -10)
  past.rows = {}
  for i = 1, 4 do
    local t = line(past, "kitSmall", nil, 14, 30 + (i - 1) * 21, MAIN_W - 140)
    t:SetMaxLines(1)
    local amt = Kit:Amount(past, "kitAmount")
    amt:SetPoint("TOPRIGHT", past, "TOPRIGHT", -14, -(30 + (i - 1) * 21))
    past.rows[i] = { text = t, amt = amt }
  end
  v.past = past
  return v
end

local function refreshLottery(v)
  local Lo = MOTA.Lottery
  local L = Lo:Current()
  local stage = Lo:Stage(L)
  local now = GetServerTime()

  -- Ticket holders, one row per player, most tickets first.
  local holders, total = {}, L and #L.tickets or 0
  if L and stage ~= "drawn" then
    local byKey = {}
    for _, t in ipairs(L.tickets) do
      local k = MOTA.Account:Key(t.who)
      if not byKey[k] then
        byKey[k] = { name = t.who, n = 0, me = MOTA.Account:Same(t.who, MOTA.me) }
        holders[#holders + 1] = byKey[k]
      end
      byKey[k].n = byKey[k].n + 1
    end
    table.sort(holders, function(a, b)
      if a.n ~= b.n then return a.n > b.n end
      return a.name < b.name
    end)
  end
  for i, r in ipairs(v.rows) do
    local h = holders[i]
    r:SetShown(h ~= nil)
    if h then
      r.mine:SetShown(h.me)
      r.name:SetText(MOTA:Short(h.name) .. (h.me and " |cff5E4B33(you)|r" or ""))
      r.n:SetText(tostring(h.n))
      r.chance:SetText(L.cancelled and MOTA:Money(h.n * L.price) or pct(h.n, total))
    end
  end
  v.chanceHead:SetText(L and L.cancelled and "Refund" or "Chance")
  v.more:SetText(#holders > #v.rows and ("and " .. (#holders - #v.rows) .. " more") or "")
  v.empty:SetShown(#holders == 0)
  v.empty:SetText(stage == "selling" and "No tickets sold yet. Be the first."
    or (stage == "cancelled" and "Cancelled, with no tickets sold." or nil)
    or (stage == "drawn" and "This lottery has been drawn. See Past draws below." or "No lottery is running."))

  -- The fair draw.
  if not L then
    v.fair.text:SetText("Each draw is sealed before the first ticket sells, and every add-on checks the winner for itself.")
    v.fair.seal:SetText("")
  elseif stage == "cancelled" then
    v.fair.text:SetText("Cancelled by " .. MOTA:Short(L.cancelled.by) .. " before the draw. Every ticket is refunded.")
    v.fair.seal:SetText("Seal never opened")
  elseif stage == "drawn" and L.winner then
    v.fair.text:SetText("Drawn by " .. MOTA:Short(L.drawn.by) .. ". Every add-on worked it out: ticket " .. L.win .. " of " .. #L.tickets .. ".")
    v.fair.seal:SetText(L.drawn.s and "Seal opened and checked" or "Drawn without the seal")
  else
    v.fair.text:SetText("The draw is sealed before the first ticket sells. Every add-on checks the winner for itself.")
    v.fair.seal:SetText("Seal " .. L.c:sub(1, 8) .. "…" .. L.c:sub(-5))
  end

  -- The organiser's desk, or how to buy.
  local runs = MOTA.Games:CanRun(MOTA.me) or (L ~= nil and Lo:CanCancel(MOTA.me, L))
  v.desk:SetShown(runs)
  v.buy:SetShown(not runs)
  if not runs then v.form:Hide() end
  local canDraw = stage == "closed" and (MOTA:IsMe(L.by) or now >= L.closes + Lo.LATE)
  local canOpen = stage ~= "selling" and stage ~= "closed"
  local owed = Lo:Owed(L)
  if stage == "selling" then
    v.desk.line:SetText("Sales close " .. date("%d %b, %H:%M", L.closes) .. ".")
  elseif stage == "closed" then
    v.desk.line:SetText(canDraw and "Sales are closed. Ready to draw." or (MOTA:Short(L.by) .. " draws it, or another from " .. date("%d %b", L.closes + Lo.LATE) .. "."))
  elseif owed > 0 and L.cancelled then
    v.desk.line:SetText("Refunds: " .. MOTA:Money(owed) .. " left. Withdraw it as Lottery payout.")
  elseif owed > 0 then
    v.desk.line:SetText("Pay " .. MOTA:Short(L.winner) .. " " .. MOTA:Money(owed) .. ": withdraw it as Lottery payout.")
  else
    v.desk.line:SetText("No lottery running.")
  end
  v.desk.draw:SetEnabled(canDraw)
  v.desk.draw:SetAlpha(canDraw and 1 or 0.45)
  local canCancel = L ~= nil and Lo:CanCancel(MOTA.me, L)
  v.desk.cancel:SetEnabled(canCancel)
  v.desk.cancel:SetAlpha(canCancel and 1 or 0.45)
  v.desk.open:SetEnabled(canOpen)
  v.desk.open:SetAlpha(canOpen and 1 or 0.45)

  -- Past draws, newest first.
  local drawn = {}
  local all = Lo:All()
  for i = #all, 1, -1 do
    if all[i].drawn or all[i].cancelled then drawn[#drawn + 1] = all[i] end
  end
  for i, r in ipairs(v.past.rows) do
    local d = drawn[i]
    r.text:SetShown(d ~= nil)
    r.amt:SetShown(d ~= nil and d.winner ~= nil)
    if d then
      local ended = d.drawn or d.cancelled
      r.text:SetText("|cff5E4B33" .. date("%d %b", ended.t) .. " ·|r " .. d.name .. " · "
        .. (d.cancelled and "cancelled, tickets refunded" or (d.winner and (MOTA:Short(d.winner) .. ", ticket " .. d.win .. " of " .. #d.tickets) or "no tickets sold")))
      if d.winner then r.amt:SetCopper(d.prize) end
    end
  end
  if #drawn == 0 then
    v.past.rows[1].text:Show()
    v.past.rows[1].text:SetText("|cff5E4B33No draws yet.|r")
  end
end

---------------------------------------------------------------------------
-- The Honours view: the orders, the medals, and who was lately honoured
---------------------------------------------------------------------------

local COL_W = (MAIN_W - 14) / 2

local function honourRow(parent, y, medalArt, letters, w)
  local r = panel(parent, nil, 0, y, w, 60)
  local medal = Kit:Art(r, medalArt, "ARTWORK")
  medal:SetSize(34, 34)
  medal:SetPoint("TOPLEFT", r, "TOPLEFT", 12, -6)
  local l = Kit:Text(r, "kitTiny", "3A2A10", "CENTER")
  l:SetPoint("CENTER", medal, "CENTER", 0, 0)
  l:SetText(letters)
  r.title = line(r, "kitNameSmall", nil, 56, 4, w - 64)
  r.title:SetMaxLines(1)
  r.text = line(r, "kitItalic", "5E4B33", 56, 20, w - 64)
  r.text:SetMaxLines(1)
  r.holders = line(r, "kitSmallest", nil, 56, 37, w - 64)
  r.holders:SetMaxLines(1)
  return r
end

local function buildHonours()
  local v = panel(root, nil, MAIN_X, BODY_Y, MAIN_W, HEIGHT - BODY_Y)
  local H = MOTA.Honours

  local orders = panel(v, "plain", 0, 0, COL_W, HEIGHT - BODY_Y)
  Kit:Label(orders, "kitSection", BLUE, 0.22, "The orders"):SetPoint("TOPLEFT", orders, "TOPLEFT", 14, -12)
  v.orders = {}
  for i, o in ipairs(H.ORDERS) do
    local r = honourRow(orders, 32 + (i - 1) * 64, "kitMedalG", o.letters, COL_W)
    r.title:SetText(o.title)
    r.text:SetText(o.text)
    v.orders[o.key] = r
  end

  local medals = panel(v, "plain", COL_W + 14, 0, COL_W, 172)
  Kit:Label(medals, "kitSection", BLUE, 0.22, "The medals"):SetPoint("TOPLEFT", medals, "TOPLEFT", 14, -12)
  v.medals = {}
  for i, m in ipairs(H.MEDALS) do
    local short = m.title:gsub("[^%u]", ""):sub(1, 2)
    local r = honourRow(medals, 32 + (i - 1) * 66, "kitMedalS", short, COL_W)
    r.title:SetText(m.title)
    r.text:SetText(m.text)
    v.medals[m.key] = r
  end

  local lately = panel(v, "sunk", COL_W + 14, 184, COL_W, HEIGHT - BODY_Y - 184)
  Kit:Label(lately, "kitSection", BLUE, 0.22, "Lately honoured"):SetPoint("TOPLEFT", lately, "TOPLEFT", 14, -10)
  lately.rows = {}
  for i = 1, 5 do
    local t = line(lately, "kitSmallest", nil, 14, 30 + (i - 1) * 38, COL_W - 28)
    t:SetMaxLines(2)
    lately.rows[i] = t
  end
  v.lately = lately
  return v
end

-- The newest honours: orders conferred, and medals won in the games.
local function latelyHonoured(limit)
  local out = {}
  local H = MOTA.Honours
  for _, r in ipairs(MOTA.Book:Latest(400)) do
    local d = r.d or {}
    local text
    if r.k == "honour.award" and H.ORDER[d.o] then
      text = "|cff2A1F14" .. MOTA:Short(d.v) .. "|r, " .. H.ORDER[d.o].title .. (d.why and (" · |cff5E4B33" .. d.why .. "|r") or "")
    elseif r.k == "game.result" and d.g ~= "lottery" and type(d.places) == "table" and d.places[1] then
      text = "|cff2A1F14" .. MOTA:Short(d.places[1]) .. "|r, " .. (H.MEDAL[d.g == "hunt" and "path" or "laurel"].title) .. " · " .. tostring(d.name)
    end
    if text then
      out[#out + 1] = "|cff5E4B33" .. date("%d %b", r.t) .. " ·|r " .. text
      if #out >= limit then break end
    end
  end
  return out
end

local function refreshHonours(v)
  -- Who holds each honour, one entry per player.
  local held = {}
  for _, e in ipairs(MOTA.Honours:Roll()) do
    for _, h in ipairs(e.list) do
      held[h.key] = held[h.key] or {}
      table.insert(held[h.key], MOTA:Short(e.name) .. (h.n > 1 and (" ×" .. h.n) or ""))
    end
  end
  for key, r in pairs(v.orders) do
    r.holders:SetText(held[key] and table.concat(held[key], ", ") or "|cff5E4B33Not yet conferred|r")
  end
  for key, r in pairs(v.medals) do
    r.holders:SetText(held[key] and table.concat(held[key], ", ") or "|cff5E4B33Not yet won|r")
  end
  local list = latelyHonoured(#v.lately.rows)
  for i, t in ipairs(v.lately.rows) do t:SetText(list[i] or (i == 1 and "|cff5E4B33Nobody has been honoured yet.|r" or "")) end
end


---------------------------------------------------------------------------
-- The Hunt: its own left-hand column, the clue, the hunters, past hunts,
-- and the organiser's form for setting one
---------------------------------------------------------------------------

local GOLD_GEM, NOW_GEM = "C9A24A", "8E2B22"

-- The organiser sets a hunt when none is running; everyone else plays.
local function setting()
  return MOTA.Games:CanRun(MOTA.me) and MOTA.Hunt:Stage() ~= "running"
end

local function buildHuntAside()
  local h = panel(aside, nil, 0, 0, ASIDE_W, HEIGHT - 66)
  local plate = panel(h, nil, 0, 0, ASIDE_W, 178)
  Kit:PlateArt(plate, "kitBlue", "BACKGROUND")
  local seal = UI:Piece(plate, "hseal_official", "ARTWORK", nil, nil, nil, plate)
  seal:ClearAllPoints()
  seal:SetSize(50, 50)
  seal:SetPoint("TOP", plate, "TOP", 0, -10)
  Kit:Label(plate, "kitTiny", "C9D6F5", 0.28, "The Treasure Hunt"):SetPoint("TOP", plate, "TOP", 0, -66)
  plate.name = Kit:Text(plate, "kitStage", "F3D98A", "CENTER")
  plate.name:SetPoint("TOP", plate, "TOP", 0, -80)
  plate.name:SetWidth(ASIDE_W - 16)
  plate.name:SetMaxLines(1)
  plate.big = Kit:Text(plate, "kitCofferBig", "F3D98A", "CENTER")
  plate.big:SetPoint("TOP", plate, "TOP", 0, -104)
  plate.when = Kit:Text(plate, "kitSmallest", "C9D5F0", "CENTER")
  plate.when:SetPoint("TOP", plate, "TOP", 0, -146)
  plate.when:SetWidth(ASIDE_W - 16)
  h.plate = plate

  local trail = panel(h, "plain", 0, 190, ASIDE_W, HEIGHT - 66 - 190)
  trail.head = Kit:Label(trail, "kitSection", BLUE, 0.22, "Your trail")
  trail.head:SetPoint("TOPLEFT", trail, "TOPLEFT", 14, -12)
  trail.rows = {}
  for i = 1, MOTA.Hunt.MAX_CLUES do
    local r = panel(trail, nil, 14, 32 + (i - 1) * 20, ASIDE_W - 28, 18)
    r.gem = Kit:Gem(r, GOLD_GEM)
    r.gem:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.text = Kit:Text(r, "kitSmall")
    r.text:SetPoint("LEFT", r, "LEFT", 18, 0)
    r.text:SetWidth(ASIDE_W - 46)
    r.text:SetMaxLines(1)
    trail.rows[i] = r
  end
  h.trail = trail

  local how = panel(h, "sunk", 0, 190, ASIDE_W, 120)
  Kit:Label(how, "kitTiny", "7A5719", 0.2, "How it works"):SetPoint("TOPLEFT", how, "TOPLEFT", 14, -12)
  line(how, "kitSmallest", nil, 14, 30, ASIDE_W - 28):SetText("Stand on the spot, write its riddle, and mark it. The spot is sealed: nobody can read where it is, only find it.")
  h.how = how
  aside.hunt = h
end

local function refreshHuntAside()
  local Hu = MOTA.Hunt
  local h = aside.hunt
  local p = h.plate
  if setting() then
    local d = Hu:Draft()
    p.name:SetText("Setting a hunt")
    p.big:SetText(#d.clues .. (#d.clues == 1 and " clue" or " clues"))
    p.when:SetText("marked so far · up to " .. Hu.MAX_CLUES)
    h.trail:Hide()
    h.how:Show()
    return
  end
  h.how:Hide()
  h.trail:Show()
  local H = Hu:Current()
  local stage = Hu:Stage(H)
  local n = H and Hu:Progress(MOTA.me, H) or 0
  p.name:SetText(H and H.name or "No hunt yet")
  if stage == "running" then
    p.big:SetText(n .. " of " .. #H.clues)
    p.when:SetText("clues found · first to finish wins")
  elseif stage == "won" then
    p.big:SetText(MOTA:Short(H.winner))
    p.when:SetText("found the treasure first")
  else
    p.big:SetText("")
    p.when:SetText(stage == "closed" and "ended with no winner" or "The Minister of Games sets one")
  end
  for i, r in ipairs(h.trail.rows) do
    local c = H and H.clues[i]
    r:SetShown(c ~= nil)
    if c then
      if i <= n then
        Kit:Tint(r.gem, GOLD_GEM)
        r.text:SetText(c.z)
        r.text:SetTextColor(MOTA:RGB("2A1F14"))
      elseif i == n + 1 and stage == "running" then
        Kit:Tint(r.gem, NOW_GEM)
        r.text:SetText("Clue " .. i .. " · " .. c.z)
        r.text:SetTextColor(MOTA:RGB("2A1F14"))
      else
        Kit:Tint(r.gem, "8A7A5E", true)
        r.text:SetText("Clue " .. i)
        r.text:SetTextColor(MOTA:RGB("8A7A5E"))
      end
    end
  end
end

local CLUE_W = MAIN_W - SIDE_W - 14
local TOP_H = 240

local function buildHunt()
  local v = panel(root, nil, MAIN_X, BODY_Y, MAIN_W, HEIGHT - BODY_Y)

  -- Playing: the clue.
  local play = panel(v, nil, 0, 0, MAIN_W, HEIGHT - BODY_Y)
  local clue = panel(play, "plain", 0, 0, CLUE_W, TOP_H)
  clue.head = Kit:Label(clue, "kitSection", BLUE, 0.22, "")
  clue.head:SetPoint("TOPLEFT", clue, "TOPLEFT", 18, -14)
  clue.zone = Kit:Label(clue, "kitTiny", "7A5719", 0.24, "")
  clue.zone:SetPoint("TOPRIGHT", clue, "TOPRIGHT", -18, -16)
  Kit:Rule(clue, CLUE_W - 36):SetPoint("TOPLEFT", clue, "TOPLEFT", 18, -34)
  clue.riddle = line(clue, "kitMotto", nil, 18, 46, CLUE_W - 36)
  clue.riddle:SetMaxLines(5)
  local warm = panel(clue, nil, 18, TOP_H - 64, 128, 24)
  Kit:Fill(warm, "B9503F", "8E2B22")
  Kit:Outline(warm, "3A0C08", 1)
  Kit:Label(warm, "kitTiny", "FBE9C8", 0.18, "Getting warmer"):SetPoint("CENTER", warm, "CENTER", 0, 0)
  clue.warm = warm
  clue.hint = line(clue, "kitItalic", "5E4B33", 18, TOP_H - 34, CLUE_W - 36)
  v.clue = clue

  local hunters = panel(play, "plain", MAIN_W - SIDE_W, 0, SIDE_W, TOP_H)
  Kit:Label(hunters, "kitSection", BLUE, 0.22, "The hunters"):SetPoint("TOPLEFT", hunters, "TOPLEFT", 14, -12)
  hunters.rows = {}
  for i = 1, 7 do
    local name = line(hunters, "kitSmall", nil, 14, 32 + (i - 1) * 21, SIDE_W - 80)
    name:SetMaxLines(1)
    local n = Kit:Text(hunters, "kitAmount", BLUE, "RIGHT")
    n:SetPoint("TOPRIGHT", hunters, "TOPRIGHT", -14, -(33 + (i - 1) * 21))
    hunters.rows[i] = { name = name, n = n }
  end
  hunters.empty = line(hunters, "kitItalic", "5E4B33", 14, 34, SIDE_W - 28)
  hunters.stop = Kit:Button(hunters, SIDE_W - 28, 26, "End the hunt", "quiet", function(b)
    if not b.sure then
      b.sure = true
      b:SetLabel("Sure?")
      C_Timer.After(4, function() b.sure = nil; b:SetLabel("End the hunt") end)
      return
    end
    b.sure = nil
    b:SetLabel("End the hunt")
    report(MOTA.Hunt:Close())
  end)
  hunters.stop:SetPoint("BOTTOMLEFT", hunters, "BOTTOMLEFT", 14, 12)
  v.hunters = hunters

  local past = panel(play, "sunk", 0, TOP_H + 12, MAIN_W, HEIGHT - BODY_Y - TOP_H - 12)
  Kit:Label(past, "kitSection", BLUE, 0.22, "Past hunts"):SetPoint("TOPLEFT", past, "TOPLEFT", 14, -10)
  past.rows = {}
  for i = 1, 4 do
    local t = line(past, "kitSmall", nil, 14, 30 + (i - 1) * 21, MAIN_W - 28)
    t:SetMaxLines(1)
    past.rows[i] = t
  end
  v.past = past
  v.play = play

  -- Setting: the form and the marked clues.
  local set = panel(v, nil, 0, 0, MAIN_W, HEIGHT - BODY_Y)
  local form = panel(set, "plain", 0, 0, CLUE_W, TOP_H)
  Kit:Label(form, "kitSection", BLUE, 0.22, "Set a hunt"):SetPoint("TOPLEFT", form, "TOPLEFT", 16, -14)
  form.name = field(form, "Name", 16, 36, CLUE_W - 32, "")
  form.name:SetScript("OnTextChanged", function(e) MOTA.Hunt:Draft().name = e:GetText() end)
  form.riddleLabel = Kit:Label(form, "kitTiny", "7A5719", 0.2, "")
  form.riddleLabel:SetPoint("TOPLEFT", form, "TOPLEFT", 16, -88)
  local riddle = CreateFrame("EditBox", nil, form)
  riddle:SetSize(CLUE_W - 32, 58)
  riddle:SetPoint("TOPLEFT", form, "TOPLEFT", 16, -103)
  riddle:SetMultiLine(true)
  riddle:SetMaxLetters(MOTA.Hunt.MAX_RIDDLE)
  riddle:SetAutoFocus(false)
  riddle:SetFontObject(MOTA:Font("kitItalic"))
  riddle:SetTextColor(MOTA:RGB("2A1F14"))
  riddle:SetTextInsets(7, 7, 5, 5)
  Kit:Fill(riddle, "FBF4E1", "F0E2BE")
  Kit:Outline(riddle, "6E4F17", 0.6)
  riddle:SetScript("OnEscapePressed", riddle.ClearFocus)
  form.riddle = riddle
  form.mark = Kit:Button(form, 150, 28, "Mark this spot", "blue", function()
    local rec, err = MOTA.Hunt:Mark(form.riddle:GetText())
    if rec then form.riddle:SetText("") end
    report(rec, err)
  end)
  form.mark:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 16, 16)
  form.where = Kit:Text(form, "kitSmallest")
  form.where:SetPoint("LEFT", form.mark, "RIGHT", 12, 0)
  form.where:SetWidth(CLUE_W - 32 - 162)
  v.form = form

  local marked = panel(set, "plain", MAIN_W - SIDE_W, 0, SIDE_W, TOP_H)
  Kit:Label(marked, "kitSection", BLUE, 0.22, "Marked clues"):SetPoint("TOPLEFT", marked, "TOPLEFT", 14, -12)
  marked.rows = {}
  for i = 1, MOTA.Hunt.MAX_CLUES do
    local r = panel(marked, nil, 14, 30 + (i - 1) * 13, SIDE_W - 28, 13)
    r.text = Kit:Text(r, "kitSmallest")
    r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.text:SetWidth(SIDE_W - 28)
    r.text:SetMaxLines(1)
    marked.rows[i] = r
  end
  marked.empty = line(marked, "kitItalic", "5E4B33", 14, 32, SIDE_W - 28)
  marked.publish = Kit:Button(marked, SIDE_W - 28, 26, "Publish", "blue", function()
    report(MOTA.Hunt:Publish(form.name:GetText()))
  end)
  marked.publish:SetPoint("BOTTOMLEFT", marked, "BOTTOMLEFT", 14, 44)
  marked.discard = Kit:Button(marked, SIDE_W - 28, 26, "Discard", "quiet", function(b)
    if not b.sure then
      b.sure = true
      b:SetLabel("Sure?")
      C_Timer.After(4, function() b.sure = nil; b:SetLabel("Discard") end)
      return
    end
    b.sure = nil
    b:SetLabel("Discard")
    report(MOTA.Hunt:Discard())
  end)
  marked.discard:SetPoint("BOTTOMLEFT", marked, "BOTTOMLEFT", 14, 12)
  v.marked = marked

  local note = panel(set, "sunk", 0, TOP_H + 12, MAIN_W, HEIGHT - BODY_Y - TOP_H - 12)
  Kit:Label(note, "kitSection", BLUE, 0.22, "Spots must be outdoors"):SetPoint("TOPLEFT", note, "TOPLEFT", 14, -10)
  line(note, "kitSmall", nil, 14, 30, MAIN_W - 28):SetText("The game gives no position inside dungeons and raids. Hunters are told they're getting warmer within about 50 yards, and find the spot within 10. You can't play a hunt you set.")
  v.set = set
  return v
end

local function refreshHunt(v)
  local Hu = MOTA.Hunt
  local isSetting = setting()
  v.play:SetShown(not isSetting)
  v.set:SetShown(isSetting)

  if isSetting then
    local d = Hu:Draft()
    if not v.form.name:HasFocus() then v.form.name:SetText(d.name or "") end
    v.form.riddleLabel:SetText("Clue " .. (#d.clues + 1) .. " · its riddle")
    local zone = GetZoneText and GetZoneText() or ""
    local inst, x = Hu:Where()
    v.form.where:SetText(x and ("You're in |cff2A1F14" .. (zone ~= "" and zone or "the world") .. "|r") or "|cff8E1B1BNo position here: go outdoors|r")
    for i, r in ipairs(v.marked.rows) do
      local c = d.clues[i]
      r:SetShown(c ~= nil)
      if c then r.text:SetText(i .. " · " .. c.z) end
    end
    v.marked.empty:SetShown(#d.clues == 0)
    v.marked.empty:SetText("Stand on the first spot, write its riddle, and press Mark this spot.")
    local ready = #d.clues >= Hu.MIN_CLUES
    v.marked.publish:SetEnabled(ready)
    v.marked.publish:SetAlpha(ready and 1 or 0.45)
    return
  end

  local H = Hu:Current()
  local stage = Hu:Stage(H)
  local clue = v.clue
  clue.warm:SetShown(stage == "running" and Hu.warm)
  if stage == "running" then
    local organiser = MOTA.Account:Same(MOTA.me, H.by)
    local i = organiser and 1 or Hu:Progress(MOTA.me, H) + 1
    local text, zone = Hu:Riddle(i, H)
    clue.head:SetText("Clue " .. i .. " of " .. #H.clues)
    clue.zone:SetText(zone or "")
    clue.riddle:SetText(text or "The riddle opens when you find the spot before it.")
    clue.hint:SetText(organiser and "You set this hunt, so you can't play it." or (Hu.warm and "Within about 50 yards. Stand on the spot itself to find it."
      or "Solve the riddle, then go and stand on the spot. Your add-on knows when you're there."))
  elseif stage == "won" then
    clue.head:SetText("The treasure is found")
    clue.zone:SetText("")
    clue.riddle:SetText(MOTA:Short(H.winner) .. " stood on all " .. #H.clues .. " spots first, and wins " .. H.name .. ".")
    clue.hint:SetText("A new hunt is set by the Minister of Games.")
  else
    clue.head:SetText("No hunt running")
    clue.zone:SetText("")
    clue.riddle:SetText(stage == "closed" and (H.name .. " was ended with no winner.") or "When the Minister of Games sets a hunt, its first riddle appears here.")
    clue.hint:SetText("")
  end

  local list = H and Hu:Hunters(H) or {}
  for i, r in ipairs(v.hunters.rows) do
    local e = list[i]
    r.name:SetShown(e ~= nil)
    r.n:SetShown(e ~= nil)
    if e then
      local me = MOTA.Account:Same(e.name, MOTA.me)
      r.name:SetText(me and ("|cff2A1F14" .. MOTA:Short(e.name) .. "|r |cff5E4B33(you)|r") or MOTA:Short(e.name))
      r.n:SetText(e.n .. " / " .. #H.clues)
    end
  end
  v.hunters.empty:SetShown(#list == 0)
  v.hunters.empty:SetText(stage == "running" and "Nobody has found a spot yet." or "")
  local canStop = stage == "running" and (MOTA:IsCrown(MOTA.me) or MOTA:IsMe(H.by))
  v.hunters.stop:SetShown(canStop)

  local all, done = Hu:All(), {}
  for i = #all, 1, -1 do
    if all[i].ended then done[#done + 1] = all[i] end
  end
  for i, t in ipairs(v.past.rows) do
    local h = done[i]
    t:SetShown(h ~= nil or i == 1)
    if h then
      local took = h.ended.t - h.t
      local dur = took >= 3600 and (math.floor(took / 3600) .. " h " .. math.floor(took % 3600 / 60) .. " min") or (math.floor(took / 60) .. " min")
      t:SetText("|cff5E4B33" .. date("%d %b", h.ended.t) .. " ·|r " .. h.name .. " · " .. #h.clues .. " clues · "
        .. (h.winner and ("won by |cff2A1F14" .. MOTA:Short(h.winner) .. "|r in " .. dur) or "no winner"))
    elseif i == 1 then
      t:SetText("|cff5E4B33No hunts finished yet.|r")
    end
  end
end

---------------------------------------------------------------------------
-- The Cup: to come
---------------------------------------------------------------------------

local function buildSoon(title, text)
  local v = panel(root, nil, MAIN_X, BODY_Y, MAIN_W, HEIGHT - BODY_Y)
  local p = panel(v, "sunk", 40, 70, MAIN_W - 80, 150)
  Kit:Label(p, "kitTiny", "7A5719", 0.24, "Coming soon"):SetPoint("TOP", p, "TOP", 0, -22)
  local t = Kit:Text(p, "kitAwaiting", BLUE, "CENTER")
  t:SetPoint("TOP", p, "TOP", 0, -42)
  t:SetText(title)
  local s = line(p, "kitItalic", "5E4B33", 30, 84, MAIN_W - 140, "CENTER")
  s:SetText(text)
  return v
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local VIEWS = {
  { "lottery", 14 }, { "hunt", 15 }, { "cup", 16 }, { "honours", 17 },
}

function Page:Select(name)
  view = name
  self:Refresh()
end

function Page:View() return view end

function Page:Refresh()
  if not root or not root:IsShown() then return end
  aside.lot:SetShown(view ~= "hunt")
  aside.hunt:SetShown(view == "hunt")
  if view == "hunt" then refreshHuntAside() else refreshAside() end
  for name, v in pairs(views) do v:SetShown(name == view) end
  for name, t in pairs(tabs) do t:SetOn(name == view) end
  if view == "lottery" then refreshLottery(views.lottery)
  elseif view == "honours" then refreshHonours(views.honours)
  elseif view == "hunt" then refreshHunt(views.hunt) end
end

local function build()
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
  buildAside()
  buildHuntAside()
  views = {
    lottery = buildLottery(),
    hunt = buildHunt(),
    cup = buildSoon("The District Cup", "Every game won earns points for your district. The champion district is crowned at each General Election."),
    honours = buildHonours(),
  }
  tabs = {}
  local x = MAIN_X
  for _, t in ipairs(VIEWS) do
    local b = Kit:Ribbon(root, t[2], function() Page:Select(t[1]) end)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", x, 0)
    x = x + b:GetWidth() + 2
    tabs[t[1]] = b
  end
end

function Page:Show(show)
  if show and not root then build() end
  if not root then return end
  root:SetShown(show)
  if show then self:Refresh() end
end

MOTA:Listen("PAGE_SHOWN", function(_, id) Page:Show(id == PAGE_ID) end)
for _, signal in ipairs({ "LOTTERY_CHANGED", "HONOURS_CHANGED", "GAMES_CHANGED", "PARTY_CHANGED", "ACCOUNT_CHANGED", "HUNT_CHANGED" }) do
  MOTA:Listen(signal, function() Page:Refresh() end)
end
MOTA:On("ZONE_CHANGED_NEW_AREA", function() if view == "hunt" then Page:Refresh() end end)
