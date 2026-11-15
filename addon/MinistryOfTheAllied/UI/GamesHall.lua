-- Ministry of the Allied: the Games Hall tab, following the Games Hall board
-- (design/canvas-source/GamesHall.dc.html; Duncan, 2026-11-08).
-- The Royal Lottery (Lottery.lua), the Roll of Honour (Honours.lua), and the
-- treasure hunt, Hide and Seek (Hide.lua) and the District Cup (Cup.lua). The
-- games are picked from a drop-down; The Cup and Honours keep their ribbons. Everything blue follows the window
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
  aside.foot.initials:SetText(MOTA:Initials(minister, "—"))
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
  desk.draw = Kit:Button(desk, half, 28, "Draw", "blue", function() report(MOTA.Lottery:Draw()) end)
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

  local MEDAL_STEP = 62
  local medalsH = 32 + #H.MEDALS * MEDAL_STEP + 4
  local medals = panel(v, "plain", COL_W + 14, 0, COL_W, medalsH)
  Kit:Label(medals, "kitSection", BLUE, 0.22, "The medals"):SetPoint("TOPLEFT", medals, "TOPLEFT", 14, -12)
  v.medals = {}
  for i, m in ipairs(H.MEDALS) do
    local short = m.title:gsub("[^%u]", ""):sub(1, 2)
    local r = honourRow(medals, 32 + (i - 1) * MEDAL_STEP, "kitMedalS", short, COL_W)
    r.title:SetText(m.title)
    r.text:SetText(m.text)
    v.medals[m.key] = r
  end

  local latelyY = medalsH + 12
  local latelyH = HEIGHT - BODY_Y - latelyY
  local lately = panel(v, "sunk", COL_W + 14, latelyY, COL_W, latelyH)
  Kit:Label(lately, "kitSection", BLUE, 0.22, "Lately honoured"):SetPoint("TOPLEFT", lately, "TOPLEFT", 14, -10)
  lately.rows = {}
  for i = 1, math.max(1, math.min(5, math.floor((latelyH - 30) / 38))) do
    local t = line(lately, "kitSmallest", nil, 14, 30 + (i - 1) * 38, COL_W - 28)
    t:SetMaxLines(2)
    lately.rows[i] = t
  end
  v.lately = lately
  return v
end

-- The newest honours: orders conferred, medals won in the games, and The Ring.
local function latelyHonoured(limit)
  local found = {}
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
      found[#found + 1] = { t = r.t, text = text }
      if #found >= limit then break end
    end
  end
  for _, h in ipairs(MOTA.Ring and MOTA.Ring:Hall() or {}) do
    if h.champion then
      found[#found + 1] = { t = h.t or 0, text = "|cff2A1F14" .. MOTA:Short(h.champion) .. "|r, " .. H.MEDAL.ring.title .. " · " .. tostring(h.season) }
    end
  end
  table.sort(found, function(a, b) return a.t > b.t end)
  local out = {}
  for i = 1, math.min(limit, #found) do
    out[i] = "|cff5E4B33" .. date("%d %b", found[i].t) .. " ·|r " .. found[i].text
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
  line(how, "kitSmallest", nil, 14, 30, ASIDE_W - 28):SetText("Stand on the spot, write its riddle, and mark it. Hunters find it within 10 yards of where you stood.")
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
  line(note, "kitSmall", nil, 14, 30, MAIN_W - 28):SetText("The game gives no position inside dungeons and raids. Within 50 yards a gold glow grows round hunters' screens as they near the spot; they find it within 10. You can't play a hunt you set.")
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
    clue.hint:SetText(organiser and "You set this hunt, so you can't play it." or (Hu.warm and "Within 50 yards. Follow the glow to within 10."
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
-- The Cup: the districts' board this season, the top scorers, past champions
---------------------------------------------------------------------------

local CUP_ROWS, SCORER_ROWS, PAST_ROWS = 5, 8, 4

local function buildCup()
  local v = panel(root, nil, MAIN_X, BODY_Y, MAIN_W, HEIGHT - BODY_Y)

  local board = panel(v, "plain", 0, 0, COL_W, HEIGHT - BODY_Y)
  board.head = Kit:Label(board, "kitSection", BLUE, 0.22, "The District Cup")
  board.head:SetPoint("TOPLEFT", board, "TOPLEFT", 14, -12)
  board.season = line(board, "kitNameSmall", nil, 14, 30, COL_W - 28)
  board.note = line(board, "kitItalic", "5E4B33", 14, 48, COL_W - 28)
  board.note:SetMaxLines(2)
  board.rows = {}
  for i = 1, CUP_ROWS do
    local r = panel(board, nil, 10, 84 + (i - 1) * 46, COL_W - 20, 40)
    r.bar = r:CreateTexture(nil, "BACKGROUND")
    r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.bar:SetHeight(40)
    r.bar:SetColorTexture(1, 1, 1, 1)
    r.place = line(r, "kitNameSmall", nil, 8, 11, 24)
    r.name = line(r, "kitNameSmall", nil, 34, 4, COL_W - 120)
    r.name:SetMaxLines(1)
    r.sub = line(r, "kitSmallest", "5E4B33", 34, 22, COL_W - 120)
    r.sub:SetMaxLines(1)
    r.pts = line(r, "kitNameSmall", nil, COL_W - 90, 11, 64, "RIGHT")
    board.rows[i] = r
  end
  board.points = line(board, "kitSmallest", "5E4B33", 14, HEIGHT - BODY_Y - 40, COL_W - 28)
  board.points:SetMaxLines(2)
  board.points:SetText("1st 10 · 2nd 6 · 3rd 3, in every game but the lottery, and in The Ring (both losing semi-finalists 3).")
  v.board = board

  local scorers = panel(v, "plain", COL_W + 14, 0, COL_W, 34 + SCORER_ROWS * 22 + 12)
  Kit:Label(scorers, "kitSection", BLUE, 0.22, "Top scorers"):SetPoint("TOPLEFT", scorers, "TOPLEFT", 14, -12)
  scorers.rows = {}
  for i = 1, SCORER_ROWS do
    scorers.rows[i] = line(scorers, "kitSmallest", nil, 14, 34 + (i - 1) * 22, COL_W - 28)
    scorers.rows[i]:SetMaxLines(1)
  end
  v.scorers = scorers

  local y = 34 + SCORER_ROWS * 22 + 24
  local past = panel(v, "sunk", COL_W + 14, y, COL_W, HEIGHT - BODY_Y - y)
  Kit:Label(past, "kitSection", BLUE, 0.22, "Past champions"):SetPoint("TOPLEFT", past, "TOPLEFT", 14, -10)
  past.rows = {}
  for i = 1, PAST_ROWS do
    past.rows[i] = line(past, "kitSmallest", nil, 14, 30 + (i - 1) * 34, COL_W - 28)
    past.rows[i]:SetMaxLines(2)
  end
  v.past = past
  return v
end

local function districtName(code)
  local d = MOTA.District and MOTA.District.byCode[code]
  return d and d.name or code
end

local function refreshCup(v)
  local Cup = MOTA.Cup
  local s = Cup:Current()
  v.board.season:SetText("Season " .. s.n)
  local gov = MOTA.Elect and MOTA.Elect:Government()
  local nextAt = MOTA.Elect and MOTA.Elect:Pending() and gov and gov.ends
  v.board.note:SetText("The season ends when the next election is declared" .. (nextAt and (", due " .. date("%d %b", nextAt)) or "") .. ". The district with the most points wins the Cup.")
  local top = math.max(1, s.board[1].pts)
  local mine = MOTA.District and MOTA.District:Of(MOTA.me)
  for i, r in ipairs(v.board.rows) do
    local b = s.board[i]
    if b then
      local d = MOTA.District.byCode[b.code]
      local cr, cg, cb = MOTA:RGB(d and d.color or "8E2B22")
      r.bar:SetVertexColor(cr, cg, cb, 0.16)
      r.bar:SetWidth(math.max(4, (COL_W - 20) * b.pts / top))
      r.place:SetText(b.pts > 0 and (i .. ".") or "")
      r.name:SetText(b.name .. ((mine and mine.code == b.code) and " |cff5E4B33(yours)|r" or ""))
      local n = 0
      for _, m in ipairs(s.scorers) do if (m.by[b.code] or 0) > 0 then n = n + 1 end end
      r.sub:SetText(n == 0 and "No points yet" or (n .. (n == 1 and " scorer" or " scorers")))
      r.pts:SetText(b.pts .. " pts")
      r:Show()
    else
      r:Hide()
    end
  end
  for i, t in ipairs(v.scorers.rows) do
    local m = s.scorers[i]
    if m then
      local where = {}
      for code in pairs(m.by) do where[#where + 1] = MOTA.District.byCode[code].short end
      table.sort(where)
      t:SetText(i .. ". |cff2A1F14" .. MOTA:Short(m.name) .. "|r · " .. m.pts .. " pts" .. (#where > 0 and (" |cff5E4B33· " .. table.concat(where, ", ") .. "|r") or ""))
    else
      t:SetText(i == 1 and "|cff5E4B33Nobody has scored this season yet.|r" or "")
    end
  end
  local seasons, row = Cup:Seasons(), 0
  for n = #seasons, 1, -1 do
    local p = seasons[n]
    if p.done and row < #v.past.rows then
      row = row + 1
      local champs = {}
      for code in pairs(p.champions) do champs[#champs + 1] = districtName(code) end
      table.sort(champs)
      local tops = {}
      for _, name in ipairs(p.top) do tops[#tops + 1] = MOTA:Short(name) end
      v.past.rows[row]:SetText("|cff2A1F14Season " .. p.n .. "|r · " .. (#champs > 0 and table.concat(champs, " and ") or "no points scored")
        .. (#tops > 0 and ("\n|cff5E4B33Top scorer: " .. table.concat(tops, ", ") .. " (" .. (p.scorers[1] and p.scorers[1].pts or 0) .. " pts)|r") or ""))
    end
  end
  for i = row + 1, #v.past.rows do
    v.past.rows[i]:SetText(i == 1 and "|cff5E4B33The first season is still being played.|r" or "")
  end
end

---------------------------------------------------------------------------
-- Hide and Seek: the play area, the players, the organiser's form
---------------------------------------------------------------------------

local LOW_H = HEIGHT - BODY_Y - TOP_H - 12   -- the lower panel (playing)
local AREA = LOW_H - 44                      -- the play area's square while playing
local FORM_H = 172                           -- the organiser's form (setting up)
local SET_LOW_H = HEIGHT - BODY_Y - FORM_H - 12
local PREVIEW_YARDS = 180                    -- before a play area is set: the map round you
local AREA_GAP = 6                           -- pixels between the edge's dots

local function hideSetting()
  return MOTA.Games:CanRun(MOTA.me) and not MOTA.Hide:Live()
end

-- A small map of the play area: the zone's own map art behind it when the
-- game gives it (C_Map's art tiles, cut to the area), the edge, and you.
local function buildArea(parent, x, y, w, h)
  w, h = w or AREA, h or AREA
  local a = panel(parent, nil, x, y, w, h)
  a.w, a.h = w, h
  Kit:Fill(a, "EFE3C2", "E2D2A8")
  Kit:Outline(a, "6E4F17", 0.5)
  if a.SetClipsChildren then a:SetClipsChildren(true) end
  a.art = CreateFrame("Frame", nil, a)
  a.art:SetAllPoints()
  a.tiles, a.dots, a.over = {}, {}, {}
  a.you = a:CreateTexture(nil, "OVERLAY", nil, 7)
  a.you:SetSize(8, 8)
  a.you:SetColorTexture(MOTA:RGB("1B3570"))
  a.note = Kit:Text(parent, "kitSmallest", "5E4B33", "RIGHT")
  a.note:SetPoint("BOTTOMRIGHT", a, "TOPRIGHT", 0, 6)
  a.note:SetWidth(math.max(160, w - 160))
  return a
end

-- How world spots land on the square: through the zone map's pixels when the
-- map can be read (so the art lines up), else straight from yards.
local function projection(A)
  local Hi = MOTA.Hide
  local shape = Hi:Shape(A)
  local HMp = MOTA.HideMap
  local L = A.m and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(A.m)
  L = L and L[1]
  if L and HMp then
    local pts, ok = {}, true
    for i, q in ipairs(shape) do
      local px, py = HMp.ToMap(A.inst, q.x, q.y, A.m)
      if not px then ok = false break end
      pts[i] = { px * L.layerWidth, py * L.layerHeight }
    end
    if ok then
      return pts, function(x, y)
        local px, py = HMp.ToMap(A.inst, x, y, A.m)
        if px then return px * L.layerWidth, py * L.layerHeight end
      end, L
    end
  end
  -- Yards: x grows to the west, so it is turned round; y grows to the north.
  local pts = {}
  for i, q in ipairs(shape) do pts[i] = { -q.x, -q.y } end
  return pts, function(x, y) return -x, -y end
end

local function areaKey(A)
  local k = { A.inst, A.cx, A.cy, A.rad, A.m or 0, MOTA.HideMap and MOTA.HideMap.drawing and 1 or 0, A.preview and 1 or 0 }
  for _, q in ipairs(A.pts or {}) do k[#k + 1] = q.x .. ":" .. q.y end
  return table.concat(k, ",")
end

-- Draws the area (only when it changed) and puts your dot on it.
local function drawArea(a, A)
  local key = areaKey(A)
  if a.areaKey ~= key then
    a.areaKey = key
    local pts, proj, L = projection(A)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(pts) do
      x0, y0 = math.min(x0, p[1]), math.min(y0, p[2])
      x1, y1 = math.max(x1, p[1]), math.max(y1, p[2])
    end
    local span = math.max(x1 - x0, y1 - y0, 1) * 1.25
    local k = math.min(a.w, a.h) / span
    local halfX, halfY = a.w / 2 / k, a.h / 2 / k
    local ox, oy = (x0 + x1) / 2, (y0 + y1) / 2
    a.proj = function(x, y)
      local sx, sy = proj(x, y)
      if sx then return (sx - ox) * k, -(sy - oy) * k end
    end
    -- The map's art, the tiles that fall in the square.
    for _, t in ipairs(a.tiles) do t:Hide() end
    local files = L and C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(A.m, 1)
    if L and files then
      local cols = math.ceil(L.layerWidth / L.tileWidth)
      local half = span / 2
      local n = 0
      for i, file in ipairs(files) do
        local cx, cy = ((i - 1) % cols) * L.tileWidth, math.floor((i - 1) / cols) * L.tileHeight
        if cx < ox + halfX and cx + L.tileWidth > ox - halfX and cy < oy + halfY and cy + L.tileHeight > oy - halfY then
          n = n + 1
          local t = a.tiles[n] or a.art:CreateTexture(nil, "BACKGROUND", nil, 1)
          a.tiles[n] = t
          t:SetTexture(file)
          t:SetSize(L.tileWidth * k, L.tileHeight * k)
          t:ClearAllPoints()
          t:SetPoint("TOPLEFT", a, "CENTER", (cx - ox) * k, -(cy - oy) * k)
          t:SetAlpha(0.9)
          t:Show()
        end
      end
    end
    -- The explored pieces over the base map: the organiser's (in the game's
    -- record) and this player's own, drawn as the world map draws them.
    for _, t in ipairs(a.over) do t:Hide() end
    if L then
      local n, seen = 0, {}
      local function lay(list)
        for _, e in ipairs(list or {}) do
          local key = type(e.f) == "table" and tostring(e.f[1]) .. ":" .. tostring(e.x) .. ":" .. tostring(e.y)
          if key and not seen[key] and e.nw and e.nh then
            seen[key] = true
            for j = 1, e.nh do
              local ph, fh = 256, 256
              if j == e.nh then
                ph = e.h % 256
                if ph == 0 then ph = 256 end
                fh = 16
                while fh < ph do fh = fh * 2 end
              end
              for i = 1, e.nw do
                local pw, fw = 256, 256
                if i == e.nw then
                  pw = e.w % 256
                  if pw == 0 then pw = 256 end
                  fw = 16
                  while fw < pw do fw = fw * 2 end
                end
                local file = e.f[(j - 1) * e.nw + i]
                if file then
                  n = n + 1
                  local t = a.over[n] or a.art:CreateTexture(nil, "BACKGROUND", nil, 2)
                  a.over[n] = t
                  t:SetTexture(file)
                  t:SetTexCoord(0, pw / fw, 0, ph / fh)
                  t:SetSize(pw * k, ph * k)
                  t:ClearAllPoints()
                  t:SetPoint("TOPLEFT", a, "CENTER", (e.x + 256 * (i - 1) - ox) * k, -(e.y + 256 * (j - 1) - oy) * k)
                  t:SetAlpha(0.9)
                  t:Show()
                end
              end
            end
          end
        end
      end
      -- The whole map, fog lifted (MapReveal.lua, from Forever's own data);
      -- for a map that isn't there, the organiser's and your explored pieces.
      local reveal = MOTA.MapReveal and A.m and MOTA.MapReveal[A.m]
      if reveal then
        local list = {}
        for i, e in ipairs(reveal) do
          list[i] = { x = e[1], y = e[2], w = e[3], h = e[4], nw = e[5], nh = e[6], f = e[7] }
        end
        lay(list)
      else
        lay(A.ov)
        lay(MOTA.Hide:Explored(A))
      end
    end
    -- The edge.
    for _, t in ipairs(a.dots) do t:Hide() end
    local n = 0
    local closed = not (A == (MOTA.db and MOTA.db.hideDraft) and MOTA.HideMap and MOTA.HideMap.drawing)
    for i = 1, A.preview and 0 or #pts do
      local p, q = pts[i], pts[i % #pts + 1]
      if closed or i < #pts then
        local ax, ay = (p[1] - ox) * k, -(p[2] - oy) * k
        local bx, by = (q[1] - ox) * k, -(q[2] - oy) * k
        local steps = math.max(1, math.floor(math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) / AREA_GAP))
        for s = 0, steps - 1 do
          n = n + 1
          local t = a.dots[n] or a:CreateTexture(nil, "ARTWORK")
          a.dots[n] = t
          t:SetSize(3, 3)
          t:SetColorTexture(MOTA:RGB("8E2B22"))
          t:ClearAllPoints()
          t:SetPoint("CENTER", a, "CENTER", ax + (bx - ax) * s / steps, ay + (by - ay) * s / steps)
          t:Show()
        end
      end
    end
  end
  -- You.
  local Hi = MOTA.Hide
  local inst, x, y = Hi:Where()
  local edge = x and Hi:ToEdge(A, inst, x, y)
  local sx, sy
  if edge then sx, sy = a.proj(x, y) end
  if not sx then
    a.you:Hide()
    a.note:SetText(x and "You're in another part of the world" or "No position here")
    return
  end
  local limX, limY = a.w / 2 - 4, a.h / 2 - 4
  a.you:ClearAllPoints()
  a.you:SetPoint("CENTER", a, "CENTER", math.max(-limX, math.min(limX, sx)), math.max(-limY, math.min(limY, sy)))
  a.you:Show()
  if A.preview then
    a.note:SetText("You're here · set the play area to draw its edge")
    return
  end
  a.note:SetText(edge < 0 and "|cff8E1B1BOutside the play area|r" or ("You · " .. math.floor(edge) .. " yards from the edge"))
end

local function sureButton(parent, w, label, fn)
  return Kit:Button(parent, w, 26, label, "quiet", function(b)
    if not b.sure then
      b.sure = true
      b:SetLabel("Sure?")
      C_Timer.After(4, function() b.sure = nil; b:SetLabel(label) end)
      return
    end
    b.sure = nil
    b:SetLabel(label)
    fn()
  end)
end

-- A small "?" that explains on hover.
local function helpButton(parent, title, lines)
  local b = Kit:Button(parent, 22, 20, "?", "quiet", function() end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.95, 0.77)
    for _, l in ipairs(lines) do GameTooltip:AddLine(l, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b.lines = lines
  return b
end

local PLAYER_ROWS = 9

local function buildHide()
  local v = panel(root, nil, MAIN_X, BODY_Y, MAIN_W, HEIGHT - BODY_Y)
  local Hi = MOTA.Hide

  -- Playing.
  local play = panel(v, nil, 0, 0, MAIN_W, HEIGHT - BODY_Y)
  local game = panel(play, "plain", 0, 0, CLUE_W, TOP_H)
  game.head = Kit:Label(game, "kitSection", BLUE, 0.22, "")
  game.head:SetPoint("TOPLEFT", game, "TOPLEFT", 18, -14)
  game.zone = Kit:Label(game, "kitTiny", "7A5719", 0.2, "")
  game.zone:SetPoint("TOPLEFT", game, "TOPLEFT", 18, -32)
  Kit:Rule(game, CLUE_W - 36):SetPoint("TOPLEFT", game, "TOPLEFT", 18, -48)
  game.role = line(game, "kitNameSmall", nil, 18, 58, CLUE_W - 36)
  game.text = line(game, "kitSmall", nil, 18, 80, CLUE_W - 36)
  game.text:SetMaxLines(5)
  local warm = panel(game, nil, CLUE_W - 146, TOP_H - 42, 128, 24)
  Kit:Fill(warm, "B9503F", "8E2B22")
  Kit:Outline(warm, "3A0C08", 1)
  Kit:Label(warm, "kitTiny", "FBE9C8", 0.18, "A seeker is near"):SetPoint("CENTER", warm, "CENTER", 0, 0)
  game.warm = warm
  game.join = Kit:Button(game, 120, 28, "Join", "blue", function()
    local G = Hi:Current()
    if G and G.joined[MOTA.me] then report(Hi:Leave()) else report(Hi:Join()) end
  end)
  game.join:SetPoint("BOTTOMLEFT", game, "BOTTOMLEFT", 18, 16)
  v.game = game

  local players = panel(play, "plain", MAIN_W - SIDE_W, 0, SIDE_W, TOP_H)
  players.head = Kit:Label(players, "kitSection", BLUE, 0.22, "Players")
  players.head:SetPoint("TOPLEFT", players, "TOPLEFT", 14, -12)
  players.rows = {}
  for i = 1, PLAYER_ROWS do
    local n = line(players, "kitSmallest", nil, 14, 32 + (i - 1) * 15, SIDE_W - 28)
    n:SetMaxLines(1)
    players.rows[i] = n
  end
  players.start = Kit:Button(players, SIDE_W - 28, 26, "Start", "blue", function()
    report(Hi:Start(players.seeker))
  end)
  players.start:SetPoint("BOTTOMLEFT", players, "BOTTOMLEFT", 14, 44)
  players.pick = Kit:Button(players, SIDE_W - 28, 22, "Seeker: random", "quiet", function()
    -- Round the joined players, then back to random.
    local G = Hi:Current()
    if not G then return end
    local nextOne
    if not players.seeker then
      nextOne = G.players[1]
    else
      for i, p in ipairs(G.players) do if p == players.seeker then nextOne = G.players[i + 1] end end
    end
    players.seeker = nextOne
    Page:Refresh()
  end)
  players.pick:SetPoint("BOTTOMLEFT", players, "BOTTOMLEFT", 14, 74)
  players.stop = sureButton(players, SIDE_W - 28, "End the game", function() report(Hi:Close()) end)
  players.stop:SetPoint("BOTTOMLEFT", players, "BOTTOMLEFT", 14, 12)
  v.players = players

  -- Below: the play area, and past games beside it.
  local low = panel(play, "sunk", 0, TOP_H + 12, MAIN_W, LOW_H)
  low.head = Kit:Label(low, "kitSection", BLUE, 0.22, "The play area")
  low.head:SetPoint("TOPLEFT", low, "TOPLEFT", 14, -10)
  low.area = buildArea(low, 14, 26)
  local px = AREA + 40
  Kit:Label(low, "kitSection", BLUE, 0.22, "Past games"):SetPoint("TOPLEFT", low, "TOPLEFT", px, -10)
  low.rows = {}
  for i = 1, 6 do
    local t = line(low, "kitSmall", nil, px, 30 + (i - 1) * 21, MAIN_W - px - 14)
    t:SetMaxLines(1)
    low.rows[i] = t
  end
  v.low = low
  v.play = play

  -- Setting: the organiser's form, the whole width, and the map below it.
  local set = panel(v, nil, 0, 0, MAIN_W, HEIGHT - BODY_Y)
  local form = panel(set, "plain", 0, 0, MAIN_W, FORM_H)
  Kit:Label(form, "kitSection", BLUE, 0.22, "Open a game"):SetPoint("TOPLEFT", form, "TOPLEFT", 16, -14)
  local colW = (MAIN_W - 56) / 2
  local rx = 16 + colW + 24
  -- Left: the name and the play area.
  form.name = field(form, "Name", 16, 36, colW, "")
  form.name:SetScript("OnTextChanged", function(e) Hi:Draft().name = e:GetText() end)
  Kit:Label(form, "kitTiny", "7A5719", 0.2, "The play area"):SetPoint("TOPLEFT", form, "TOPLEFT", 16, -88)
  local third = (colW - 16) / 3
  form.here = Kit:Button(form, third, 26, "Here", "blue", function() report(Hi:SetCentre()) end)
  form.here:SetPoint("TOPLEFT", form, "TOPLEFT", 16, -104)
  form.circle = Kit:Button(form, third, 26, "Circle", "quiet", function()
    local HMp = MOTA.HideMap
    if not HMp then return end
    if HMp.circling then report(HMp:StopCircle()) else report(HMp:Circle()) end
  end)
  form.circle:SetPoint("TOPLEFT", form, "TOPLEFT", 16 + third + 8, -104)
  form.draw = Kit:Button(form, third, 26, "Shape", "quiet", function()
    local HMp = MOTA.HideMap
    if not HMp then return end
    if HMp.drawing then report(HMp:Finish()) else report(HMp:Draw()) end
  end)
  form.draw:SetPoint("TOPLEFT", form, "TOPLEFT", 16 + 2 * (third + 8), -104)
  form.status = line(form, "kitSmallest", "5E4B33", 16, 140, colW)
  form.status:SetMaxLines(2)
  -- Right: the size, the times, the options, and Open.
  local function stepper(y, get, put, steps)
    local l = Kit:Text(form, "kitSmall")
    l:SetPoint("TOPLEFT", form, "TOPLEFT", rx, -y)
    l:SetWidth(colW - 70)
    l:SetWordWrap(false)
    local function move(dir)
      local cur, at = get(), 1
      for i, s in ipairs(steps) do if s <= cur then at = i end end
      put(steps[math.max(1, math.min(#steps, at + dir))])
      Page:Refresh()
    end
    l.minus = Kit:Button(form, 26, 20, "-", "quiet", function() move(-1) end)
    l.minus:SetPoint("TOPLEFT", form, "TOPLEFT", rx + colW - 56, -(y - 3))
    l.plus = Kit:Button(form, 26, 20, "+", "quiet", function() move(1) end)
    l.plus:SetPoint("TOPLEFT", form, "TOPLEFT", rx + colW - 26, -(y - 3))
    return l
  end
  local D = function() return Hi:Draft() end
  form.radius = stepper(40, function() return D().rad end, function(r) Hi:SetRadius(r) end, Hi.RADII)
  form.undo = Kit:Button(form, 110, 20, "Undo corner", "quiet", function() report(Hi:UndoCorner()) end)
  form.undo:SetPoint("TOPLEFT", form, "TOPLEFT", rx + colW - 110, -37)
  form.hs = stepper(64, function() return D().hs end, function(s) D().hs = s end, { 30, 60, 120, 180, 300, 600 })
  form.ss = stepper(88, function() return D().ss end, function(s) D().ss = s end, { 300, 600, 900, 1200, 1800, 2700, 3600 })
  local half = (colW - 8) / 2
  local function toggle(label, key, x)
    local b = Kit:Button(form, half, 22, "", "quiet", function()
      D()[key] = not D()[key]
      Page:Refresh()
    end)
    b:SetPoint("TOPLEFT", form, "TOPLEFT", x, -110)
    b.base = label
    return b
  end
  form.nm = toggle("Names", "nm", rx)
  form.nmap = toggle("Map", "nmap", rx + half + 8)
  form.open = Kit:Button(form, colW, 26, "Open the game", "blue", function()
    report(Hi:Open(form.name:GetText()))
  end)
  form.open:SetPoint("TOPLEFT", form, "TOPLEFT", rx, -138)
  form.help = helpButton(form, "Before you open", {
    "Set the play area: Here makes a circle round where you stand (size it with - and +); Circle lets you click its middle and then its edge on the world map; Shape lets you click its corners.",
    "Names off: friendly names and nameplates are hidden for players until the game ends (they come back after, even after a crash).",
    "Map off: the world map stays shut for players; the play area shows on this page.",
  })
  form.help:SetPoint("TOPRIGHT", form, "TOPRIGHT", -12, -10)
  v.form = form

  -- Below: the map, the whole width.
  local note = panel(set, "sunk", 0, FORM_H + 12, MAIN_W, SET_LOW_H)
  Kit:Label(note, "kitSection", BLUE, 0.22, "The play area"):SetPoint("TOPLEFT", note, "TOPLEFT", 14, -10)
  note.area = buildArea(note, 14, 30, MAIN_W - 28, SET_LOW_H - 44)
  note.help = helpButton(note, "How it plays", {
    "Players join, then you start it. Everyone hides; then the seeker sets off.",
    "A seeker who stands within " .. Hi.FIND .. " yards of a hider for " .. Hi.DWELL .. " seconds finds them, and they seek too.",
    "10 seconds outside the play area and you're out.",
    "Everyone found: the best seeker wins. Time up: everyone still hidden shares first.",
  })
  note.help:SetPoint("TOPLEFT", note, "TOPLEFT", 150, -6)
  v.note = note
  v.set = set
  return v
end

local function refreshHide(v)
  local Hi = MOTA.Hide
  local isSetting = hideSetting()
  v.play:SetShown(not isSetting)
  v.set:SetShown(isSetting)

  if isSetting then
    local d = Hi:Draft()
    local f = v.form
    local drawing = MOTA.HideMap and MOTA.HideMap.drawing
    local circling = MOTA.HideMap and MOTA.HideMap.circling
    if not f.name:HasFocus() then f.name:SetText(d.name or "") end
    f.draw:SetLabel(drawing and "Finish" or "Shape")
    f.circle:SetLabel(circling and "Cancel" or "Circle")
    local shaped = d.pts ~= nil or drawing
    f.radius:SetText(shaped and ("Shape · " .. (d.pts and #d.pts or 0) .. " corners") or ("Circle · " .. d.rad .. " yd"))
    f.radius.minus:SetShown(not shaped)
    f.radius.plus:SetShown(not shaped)
    f.undo:SetShown(shaped and d.pts ~= nil)
    f.hs:SetText("Hiding " .. Hi.Clock(d.hs))
    f.ss:SetText("Seeking " .. Hi.Clock(d.ss))
    f.nm:SetLabel(d.nm and "Names off" or "Names on")
    f.nmap:SetLabel(d.nmap and "Map off" or "Map on")
    f.status:SetText((circling and "On the world map, click the middle, then click where the edge goes.")
      or (drawing and "On the world map, click the corners one by one, then press Finish.")
      or (d.cx and ("In |cff2A1F14" .. tostring(d.z) .. "|r: " .. (d.pts and (#d.pts .. " corners") or ("a circle, " .. d.rad .. " yards out")) .. "."))
      or "Not set yet.")
    local ready = d.cx ~= nil and (not d.pts or #d.pts >= Hi.MIN_PTS) and not drawing and not circling
    f.open:SetEnabled(ready)
    f.open:SetAlpha(ready and 1 or 0.45)
    -- The map: the play area, or until there is one, the map round where you stand.
    local area = v.note.area
    local A = d.cx and d
    if not A then
      local inst, x, y = Hi:Where()
      local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
      if x then A = { inst = inst, cx = math.floor(x / 20 + 0.5) * 20, cy = math.floor(y / 20 + 0.5) * 20, rad = PREVIEW_YARDS, m = m, preview = true } end
    end
    if A then
      area:Show()
      drawArea(area, A)
    else
      area.areaKey = nil
      area:Hide()
      area.note:SetText("No position here: go outdoors")
    end
    return
  end

  local G = Hi:Current()
  local stage = Hi:Stage(G)
  local game = v.game
  local role = G and Hi:Role(MOTA.me, G)
  local live = G ~= nil and Hi:Live(G)
  game.warm:SetShown(Hi.warm and role == "hider" and stage == "seeking")
  game.zone:SetText(live and (G.z .. " · " .. (G.pts and "drawn area" or (G.rad .. " yards out"))) or "")
  local opts = G and ((G.nm and "Names hidden. " or "") .. (G.nmap and "No map. " or "")) or ""
  if stage == "lobby" then
    game.head:SetText(G.name .. " · open to join")
    game.role:SetText(G.joined[MOTA.me] and "You've joined" or "Not joined yet")
    game.text:SetText("Hiding " .. Hi.Clock(G.hs) .. ", seeking " .. Hi.Clock(G.ss) .. ". " .. opts
      .. "Go to the play area: " .. MOTA:Short(G.by) .. " starts the game when everyone's ready.")
  elseif stage == "hiding" or stage == "seeking" then
    game.head:SetText(G.name .. " · " .. stage .. " " .. Hi.Clock(Hi:Left(G)))
    if role == "seeker" then
      game.role:SetText(stage == "hiding" and "You're seeking: wait" or "You're seeking")
      game.text:SetText(stage == "hiding" and "Stay where you are while everyone hides." or
        ("Stand within " .. G.fr .. " yards of a hider for " .. G.dw .. " seconds to find them. " .. #Hi:Hidden(G) .. " still hidden."))
    elseif role == "hider" then
      game.role:SetText(stage == "hiding" and "Hide!" or "Stay hidden")
      game.text:SetText("Keep inside the play area. Nobody is told where you are; a glow warns you when a seeker is within " .. Hi.WARM .. " yards.")
    elseif role == "out" then
      game.role:SetText("You're out")
      game.text:SetText("You left the play area.")
    else
      game.role:SetText("Watching")
      game.text:SetText(#Hi:Hidden(G) .. " still hidden. " .. opts)
    end
  elseif stage == "done" then
    local places = Hi:Places(G)
    game.head:SetText(G.name .. " · over")
    game.role:SetText(places[1] and ("Won by " .. MOTA:Short(places[1])) or "Over")
    game.text:SetText("The result is in the games log, and counts for the District Cup.")
  else
    game.head:SetText("No game on")
    game.role:SetText("")
    game.text:SetText(stage == "closed" and (G.name .. " was ended with no result.") or "When the Minister of Games opens a game of Hide and Seek, join it here.")
  end
  local area = v.low.area
  if live then
    area:Show()
    drawArea(area, G)
  else
    area.areaKey = nil
    area:Hide()
    area.note:SetText("Shown while a game is on")
  end
  local canJoin = stage == "lobby"
  game.join:SetShown(canJoin)
  if canJoin then game.join:SetLabel(G.joined[MOTA.me] and "Leave" or "Join") end

  -- The players.
  local list = {}
  if G then
    for _, p in ipairs(G.players) do
      local r = Hi:Role(p, G)
      local tag
      if stage == "lobby" then tag = ""
      elseif r == "out" then tag = "|cff8E1B1Bout|r"
      elseif r == "seeker" then
        tag = "seeking" .. ((G.finds[p] or 0) > 0 and (" · " .. G.finds[p] .. " found") or "")
      else tag = "|cff2A1F14hidden|r" end
      if G.flags[p] and G.flags[p].names then tag = tag .. " |cff8E1B1B(names on)|r" end
      list[#list + 1] = MOTA:Short(p) .. ((tag ~= "") and (" |cff5E4B33· " .. tag .. "|r") or "")
    end
  end
  for i, t in ipairs(v.players.rows) do
    t:SetText(list[i] or (i == 1 and "|cff5E4B33Nobody yet.|r" or ""))
  end
  v.players.head:SetText("Players" .. (live and (" (" .. #G.players .. ")") or ""))
  local organiser = G ~= nil and MOTA:IsMe(G.by)
  local lobbyOrg = stage == "lobby" and organiser
  v.players.start:SetShown(lobbyOrg)
  v.players.pick:SetShown(lobbyOrg)
  if lobbyOrg then
    if v.players.seeker and not G.joined[v.players.seeker] then v.players.seeker = nil end
    v.players.pick:SetLabel("Seeker: " .. (v.players.seeker and MOTA:Short(v.players.seeker) or "random"))
    local ok = #G.players >= Hi.MIN_PLAYERS
    v.players.start:SetEnabled(ok)
    v.players.start:SetAlpha(ok and 1 or 0.45)
  end
  v.players.stop:SetShown(live and (organiser or MOTA:IsCrown(MOTA.me)))

  -- Past games, from the games log.
  local done = {}
  for _, e in ipairs(MOTA.Games:Log()) do
    if e.g == "hide" and #done < #v.low.rows then done[#done + 1] = e end
  end
  for i, t in ipairs(v.low.rows) do
    local e = done[i]
    t:SetText(e and MOTA.Games:Line(e) or (i == 1 and "|cff5E4B33No games played yet.|r" or ""))
  end
end

-- For the simulator: the play area's square (the form's, or the game's).
function Page._hideArea(setting)
  return setting and views.hide.note.area or views.hide.low.area
end

local function buildHideAside()
  local h = panel(aside, nil, 0, 0, ASIDE_W, HEIGHT - 66)
  local plate = panel(h, nil, 0, 0, ASIDE_W, 178)
  Kit:PlateArt(plate, "kitBlue", "BACKGROUND")
  local seal = UI:Piece(plate, "hseal_official", "ARTWORK", nil, nil, nil, plate)
  seal:ClearAllPoints()
  seal:SetSize(50, 50)
  seal:SetPoint("TOP", plate, "TOP", 0, -10)
  Kit:Label(plate, "kitTiny", "C9D6F5", 0.28, "Hide and Seek"):SetPoint("TOP", plate, "TOP", 0, -66)
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
  local how = panel(h, "sunk", 0, 190, ASIDE_W, 170)
  Kit:Label(how, "kitTiny", "7A5719", 0.2, "Scoring"):SetPoint("TOPLEFT", how, "TOPLEFT", 14, -12)
  local t = line(how, "kitSmallest", nil, 14, 30, ASIDE_W - 28)
  t:SetMaxLines(9)
  t:SetText("Everyone found: 1st the seeker with most finds, 2nd the last found, 3rd the one before.\n\nTime up: everyone still hidden shares 1st, the best seeker 2nd, the last found 3rd.\n\nPoints count for the District Cup.")
  aside.hide = h
end

local function refreshHideAside()
  local Hi = MOTA.Hide
  local p = aside.hide.plate
  if hideSetting() then
    p.name:SetText("Opening a game")
    p.big:SetText(Hi:Draft().rad .. " yd")
    p.when:SetText("play area")
    return
  end
  local G = Hi:Current()
  local s = Hi:Stage(G)
  p.name:SetText(G and G.name or "No game yet")
  if s == "hiding" or s == "seeking" then
    p.big:SetText(Hi.Clock(Hi:Left(G)))
    p.when:SetText(s == "hiding" and "until the seekers set off" or (#Hi:Hidden(G) .. " still hidden"))
  elseif s == "lobby" then
    p.big:SetText(#G.players)
    p.when:SetText(#G.players == 1 and "player joined" or "players joined")
  else
    p.big:SetText("")
    p.when:SetText(G and Hi:Line(G) or "The Minister of Games opens one")
  end
end

---------------------------------------------------------------------------
-- The Pub Quiz: teams and the scoreboard for players; the quizmaster's desk
---------------------------------------------------------------------------

local QUIZ_TOP = 200                          -- the upper panels
local QUIZ_LOW = HEIGHT - BODY_Y - QUIZ_TOP - 12
local BOARD_ROWS = 8
local PLAN_ROWS = 12
local TEAM_ROWS = 8

local function quizSetting()
  return MOTA.Games:CanRun(MOTA.me) and not MOTA.Quiz:Live()
end

local function quizMaster()
  local Qz = MOTA.Quiz
  local Q = Qz:Current()
  return Q ~= nil and Qz:Live(Q) and MOTA:IsMe(Q.by)
end

-- The scoreboard: rank, team, each round, the total.
local function buildBoard(parent, x, y, w, h)
  local b = panel(parent, "plain", x, y, w, h)
  b.head = Kit:Label(b, "kitSection", BLUE, 0.22, "Scoreboard")
  b.head:SetPoint("TOPLEFT", b, "TOPLEFT", 14, -12)
  b.cols = line(b, "kitTiny", "7A5719", 14, 32, w - 28)
  b.rows = {}
  for i = 1, BOARD_ROWS do
    local t = line(b, "kitSmall", nil, 14, 50 + (i - 1) * 21, w - 28)
    t:SetMaxLines(1)
    b.rows[i] = t
  end
  return b
end

local function pad(s, n) s = tostring(s) return s .. string.rep(" ", math.max(1, n - #s)) end

local function refreshBoard(b, Q)
  local Qz = MOTA.Quiz
  local fmt = Qz.Fmt
  if not Q then
    b.cols:SetText("")
    for i, t in ipairs(b.rows) do t:SetText(i == 1 and "|cff5E4B33No quiz yet.|r" or "") end
    return
  end
  local head = {}
  for r = 1, Q.rounds do head[#head + 1] = "R" .. r end
  b.cols:SetText("Team · " .. table.concat(head, " · ") .. " · Total")
  local board = Qz:Board(Q)
  local mine = Qz:TeamOf(MOTA.me, Q)
  for i, t in ipairs(b.rows) do
    local row = board[i]
    if row then
      local by = {}
      for r = 1, Q.rounds do
        local p = row.rounds[r]
        by[#by + 1] = (p and fmt(p) or "-") .. (row.joker == r and "J" or "")
      end
      local you = mine and mine.cap == row.cap
      t:SetText(row.rank .. ". " .. (you and ("|cff1B3570" .. row.name .. "|r") or ("|cff2A1F14" .. row.name .. "|r"))
        .. " |cff5E4B33· " .. table.concat(by, " · ") .. " ·|r |cff2A1F14" .. fmt(row.total) .. "|r")
    else
      t:SetText(i == 1 and "|cff5E4B33No teams yet.|r" or "")
    end
  end
end

local function buildQuiz()
  local v = panel(root, nil, MAIN_X, BODY_Y, MAIN_W, HEIGHT - BODY_Y)
  local Qz = MOTA.Quiz
  local colW = (MAIN_W - 56) / 2
  local rx = 16 + colW + 24

  -------------------------------------------------------------------------
  -- Players
  -------------------------------------------------------------------------
  local play = panel(v, nil, 0, 0, MAIN_W, HEIGHT - BODY_Y)
  local team = panel(play, "plain", 0, 0, CLUE_W, QUIZ_TOP)
  team.head = Kit:Label(team, "kitSection", BLUE, 0.22, "Your team")
  team.head:SetPoint("TOPLEFT", team, "TOPLEFT", 16, -14)
  team.name = line(team, "kitNameSmall", nil, 16, 36, CLUE_W - 32)
  team.text = line(team, "kitSmall", nil, 16, 58, CLUE_W - 32)
  team.text:SetMaxLines(4)
  team.field = field(team, "Team name", 16, 104, CLUE_W - 160, "")
  team.make = Kit:Button(team, 120, 26, "Make team", "blue", function()
    local rec, err = Qz:MakeTeam(team.field:GetText())
    if rec then team.field:SetText("") end
    report(rec, err)
  end)
  team.make:SetPoint("TOPLEFT", team, "TOPLEFT", CLUE_W - 136, -119)
  team.leave = sureButton(team, 120, "Leave team", function() report(Qz:Leave()) end)
  team.leave:SetPoint("BOTTOMLEFT", team, "BOTTOMLEFT", 16, 14)
  team.joker = Kit:Button(team, 150, 26, "", "quiet", function()
    team.jokerRound = (team.jokerRound or 1) % (Qz:Current() and Qz:Current().rounds or 1) + 1
    Page:Refresh()
  end)
  team.joker:SetPoint("BOTTOMRIGHT", team, "BOTTOMRIGHT", -146, 14)
  team.play = Kit:Button(team, 120, 26, "Play joker", "blue", function()
    report(Qz:Joker(team.jokerRound or 1))
  end)
  team.play:SetPoint("BOTTOMRIGHT", team, "BOTTOMRIGHT", -16, 14)
  team.jokerRound = 1
  v.team = team

  local teams = panel(play, "plain", MAIN_W - SIDE_W, 0, SIDE_W, QUIZ_TOP)
  Kit:Label(teams, "kitSection", BLUE, 0.22, "Teams"):SetPoint("TOPLEFT", teams, "TOPLEFT", 14, -12)
  teams.rows = {}
  for i = 1, TEAM_ROWS do
    local r = panel(teams, nil, 14, 32 + (i - 1) * 20, SIDE_W - 28, 18)
    r.text = Kit:Text(r, "kitSmallest")
    r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.text:SetWidth(SIDE_W - 90)
    r.text:SetMaxLines(1)
    r.join = Kit:Button(r, 50, 18, "Join", "quiet", function() if r.cap then report(Qz:Join(r.cap)) end end)
    r.join:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    teams.rows[i] = r
  end
  v.teams = teams
  v.board = buildBoard(play, 0, QUIZ_TOP + 12, MAIN_W, QUIZ_LOW)
  v.play = play

  -------------------------------------------------------------------------
  -- The quizmaster: setting up (before a quiz is open)
  -------------------------------------------------------------------------
  local set = panel(v, nil, 0, 0, MAIN_W, HEIGHT - BODY_Y)
  local form = panel(set, "plain", 0, 0, MAIN_W, QUIZ_TOP)
  Kit:Label(form, "kitSection", BLUE, 0.22, "Set a quiz"):SetPoint("TOPLEFT", form, "TOPLEFT", 16, -14)
  form.name = field(form, "Name", 16, 36, colW, "")
  form.name:SetScript("OnTextChanged", function(e) Qz:Desk().name = e:GetText() end)
  local function stepper(y, get, put, lo, hi, step)
    local l = Kit:Text(form, "kitSmall")
    l:SetPoint("TOPLEFT", form, "TOPLEFT", 16, -y)
    l:SetWidth(colW - 70)
    l:SetWordWrap(false)
    l.minus = Kit:Button(form, 26, 20, "-", "quiet", function() put(math.max(lo, get() - step)) Page:Refresh() end)
    l.minus:SetPoint("TOPLEFT", form, "TOPLEFT", 16 + colW - 56, -(y - 3))
    l.plus = Kit:Button(form, 26, 20, "+", "quiet", function() put(math.min(hi, get() + step)) Page:Refresh() end)
    l.plus:SetPoint("TOPLEFT", form, "TOPLEFT", 16 + colW - 26, -(y - 3))
    return l
  end
  local D = function() return Qz:Desk() end
  form.rounds = stepper(92, function() return D().rounds end, function(n) D().rounds = n end, 1, Qz.MAX_ROUNDS, 1)
  form.per = stepper(116, function() return D().per end, function(n) D().per = n end, 1, Qz.MAX_PER, 1)
  form.secs = stepper(140, function() return D().secs end, function(n) D().secs = n end, 10, 300, 10)
  form.open = Kit:Button(form, colW, 26, "Open the quiz", "blue", function() report(Qz:Open(form.name:GetText())) end)
  form.open:SetPoint("TOPLEFT", form, "TOPLEFT", 16, -162)
  -- Right: the questions, round by round.
  Kit:Label(form, "kitTiny", "7A5719", 0.2, "Questions"):SetPoint("TOPLEFT", form, "TOPLEFT", rx, -36)
  local third = (colW - 16) / 3
  form.prev = Kit:Button(form, third, 24, "< Round", "quiet", function()
    form.round = math.max(1, (form.round or 1) - 1) Page:Refresh()
  end)
  form.prev:SetPoint("TOPLEFT", form, "TOPLEFT", rx, -52)
  form.roundLabel = Kit:Text(form, "kitNameSmall", nil, "CENTER")
  form.roundLabel:SetPoint("TOPLEFT", form, "TOPLEFT", rx + third + 8, -56)
  form.roundLabel:SetWidth(third)
  form.nextR = Kit:Button(form, third, 24, "Round >", "quiet", function()
    form.round = math.min(D().rounds, (form.round or 1) + 1) Page:Refresh()
  end)
  form.nextR:SetPoint("TOPLEFT", form, "TOPLEFT", rx + 2 * (third + 8), -52)
  local cats = { false }
  for _, c in ipairs(MOTA.QuizBank.CATEGORIES) do cats[#cats + 1] = c end
  form.cat = Kit:Button(form, (colW - 8) / 2, 24, "", "quiet", function()
    form.catAt = (form.catAt or 1) % #cats + 1 Page:Refresh()
  end)
  form.cat:SetPoint("TOPLEFT", form, "TOPLEFT", rx, -82)
  form.fill = Kit:Button(form, (colW - 8) / 2, 24, "Fill from bank", "blue", function()
    local c = cats[form.catAt or 1]
    report(Qz:FillRandom(form.round or 1, c and c.key or nil))
  end)
  form.fill:SetPoint("TOPLEFT", form, "TOPLEFT", rx + (colW - 8) / 2 + 8, -82)
  form.q = field(form, "Your own question", rx, 108, colW, "")
  form.q:SetMaxLetters(200)
  form.a = field(form, "", rx, 146, colW - 88, "")
  form.a:ClearAllPoints()
  form.a:SetPoint("TOPLEFT", form, "TOPLEFT", rx, -158)
  form.add = Kit:Button(form, 80, 26, "Add", "quiet", function()
    local n, err = Qz:AddOwn(form.round or 1, form.q:GetText(), form.a:GetText())
    if n then form.q:SetText("") form.a:SetText("") end
    report(n, err)
  end)
  form.add:SetPoint("TOPLEFT", form, "TOPLEFT", rx + colW - 80, -158)
  form.cats = cats
  form.round, form.catAt = 1, 1
  form.help = helpButton(form, "Setting a quiz", {
    "Pick each round's questions: fill it from the question bank (any category, or one), add your own, or both. Click a question below to take it out.",
    "Your own questions stay on your computer until you ask them. Type the answer in the second box.",
    "Then open the quiz: teams of up to " .. Qz.TEAM_MAX .. " join, each with a captain. A round with no questions picked is read out on Discord; captains still answer in the add-on.",
  })
  form.help:SetPoint("TOPRIGHT", form, "TOPRIGHT", -12, -10)
  v.form = form

  local plan = panel(set, "sunk", 0, QUIZ_TOP + 12, MAIN_W, QUIZ_LOW)
  plan.head = Kit:Label(plan, "kitSection", BLUE, 0.22, "")
  plan.head:SetPoint("TOPLEFT", plan, "TOPLEFT", 14, -10)
  plan.rows = {}
  for i = 1, PLAN_ROWS do
    local b = CreateFrame("Button", nil, plan)
    b:SetSize(MAIN_W - 28, 19)
    b:SetPoint("TOPLEFT", plan, "TOPLEFT", 14, -(30 + (i - 1) * 20))
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetColorTexture(0.8, 0.2, 0.1, 0.12)
    glow:SetAllPoints()
    b.text = Kit:Text(b, "kitSmallest")
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.text:SetWidth(MAIN_W - 28)
    b.text:SetMaxLines(1)
    b:SetScript("OnClick", function() if b.i then report(Qz:Remove(form.round or 1, b.i)) end end)
    plan.rows[i] = b
  end
  v.plan = plan
  v.set = set

  -------------------------------------------------------------------------
  -- The quizmaster: running it
  -------------------------------------------------------------------------
  local run = panel(v, nil, 0, 0, MAIN_W, HEIGHT - BODY_Y)
  local desk = panel(run, "plain", 0, 0, MAIN_W, QUIZ_TOP)
  desk.head = Kit:Label(desk, "kitSection", BLUE, 0.22, "")
  desk.head:SetPoint("TOPLEFT", desk, "TOPLEFT", 16, -14)
  desk.q = line(desk, "kitSmall", nil, 16, 36, colW)
  desk.q:SetMaxLines(3)
  desk.a = line(desk, "kitSmallest", "5E4B33", 16, 92, colW)
  desk.a:SetMaxLines(2)
  desk.who = line(desk, "kitSmallest", nil, 16, 122, colW)
  desk.who:SetMaxLines(3)
  local bw = (colW - 8) / 2
  local function deskButton(label, style, col, row, fn)
    local b = Kit:Button(desk, bw, 26, label, style, fn)
    b:SetPoint("TOPLEFT", desk, "TOPLEFT", rx + (col - 1) * (bw + 8), -(36 + (row - 1) * 32))
    return b
  end
  desk.start = deskButton("Start round", "blue", 1, 1, function() report(Qz:StartRound()) end)
  desk.ask = deskButton("Ask next", "blue", 2, 1, function() report(Qz:Ask()) end)
  desk.closeQ = deskButton("Close question", "quiet", 1, 2, function() report(Qz:CloseQuestion()) end)
  desk.publish = deskButton("Publish round", "blue", 2, 2, function() report(Qz:Publish()) end)
  desk.tie = deskButton("Ask tie-break", "quiet", 1, 3, function() report(Qz:AskTie()) end)
  desk.finish = Kit:Button(desk, bw, 26, "End quiz", "quiet", function(b)
    if not b.sure then
      b.sure = true
      b:SetLabel("Sure?")
      C_Timer.After(4, function() b.sure = nil; b:SetLabel("End quiz") end)
      return
    end
    b.sure = nil
    b:SetLabel("End quiz")
    report(Qz:Finish())
  end)
  desk.finish:SetPoint("TOPLEFT", desk, "TOPLEFT", rx + bw + 8, -100)
  desk.tieAns = field(desk, "", rx, 120, bw, "")
  desk.tieAns:ClearAllPoints()
  desk.tieAns:SetPoint("TOPLEFT", desk, "TOPLEFT", rx, -134)
  desk.settle = Kit:Button(desk, bw, 26, "Settle tie", "quiet", function() report(Qz:SettleTie(desk.tieAns:GetText())) end)
  desk.settle:SetPoint("TOPLEFT", desk, "TOPLEFT", rx + bw + 8, -134)
  desk.cancel = sureButton(desk, colW, "Cancel the quiz", function() report(Qz:Close()) end)
  desk.cancel:SetPoint("TOPLEFT", desk, "TOPLEFT", rx, -166)
  desk.help = helpButton(desk, "Running the quiz", {
    "Start round: teams are fixed once round 1 starts; a team's joker must be played before its round starts.",
    "Ask next: read the question on Discord as you press it. Captains get it with an answer box until they answer, or you close it (it closes itself when time is up).",
    "Marking: right answers are ticked for you. Click a team's answer to change it: right, half, wrong. Then Publish round.",
    "Tie-break: ask it, read the question on Discord, then type the right number and Settle tie. Closest guess wins.",
  })
  desk.help:SetPoint("TOPRIGHT", desk, "TOPRIGHT", -12, -10)
  v.desk = desk

  local mark = panel(run, "sunk", 0, QUIZ_TOP + 12, CLUE_W, QUIZ_LOW)
  mark.head = Kit:Label(mark, "kitSection", BLUE, 0.22, "")
  mark.head:SetPoint("TOPLEFT", mark, "TOPLEFT", 14, -10)
  mark.prev = Kit:Button(mark, 30, 20, "<", "quiet", function() mark.i = math.max(1, (mark.i or 1) - 1) Page:Refresh() end)
  mark.prev:SetPoint("TOPRIGHT", mark, "TOPRIGHT", -48, -8)
  mark.nextQ = Kit:Button(mark, 30, 20, ">", "quiet", function() mark.i = (mark.i or 1) + 1 Page:Refresh() end)
  mark.nextQ:SetPoint("TOPRIGHT", mark, "TOPRIGHT", -12, -8)
  mark.answer = line(mark, "kitSmallest", "5E4B33", 14, 32, CLUE_W - 28)
  mark.answer:SetMaxLines(1)
  mark.rows = {}
  for i = 1, TEAM_ROWS do
    local b = CreateFrame("Button", nil, mark)
    b:SetSize(CLUE_W - 28, 20)
    b:SetPoint("TOPLEFT", mark, "TOPLEFT", 14, -(52 + (i - 1) * 22))
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetColorTexture(1, 0.95, 0.7, 0.25)
    glow:SetAllPoints()
    b.text = Kit:Text(b, "kitSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.text:SetWidth(CLUE_W - 28)
    b.text:SetMaxLines(1)
    b:SetScript("OnClick", function() if b.key and b.cap then Qz:Mark(b.key, b.cap) end end)
    mark.rows[i] = b
  end
  mark.i = 1
  v.mark = mark
  v.deskBoard = buildBoard(run, MAIN_W - SIDE_W, QUIZ_TOP + 12, SIDE_W, QUIZ_LOW)
  v.run = run
  return v
end

local MARK = { [1] = "|cff2E7D32right|r", [0.5] = "|cffB07A10half|r", [0] = "|cff8E1B1Bwrong|r" }

local function refreshQuiz(v)
  local Qz = MOTA.Quiz
  local fmt = Qz.Fmt
  local Q = Qz:Current()
  local stage = Qz:Stage(Q)
  local setting, master = quizSetting(), quizMaster()
  v.set:SetShown(setting)
  v.run:SetShown(master)
  v.play:SetShown(not setting and not master)

  if setting then
    local d = Qz:Desk()
    local f = v.form
    if not f.name:HasFocus() then f.name:SetText(d.name or "") end
    f.rounds:SetText(d.rounds .. (d.rounds == 1 and " round" or " rounds"))
    f.per:SetText(d.per .. " questions a round")
    f.secs:SetText(d.secs .. " seconds to answer")
    f.round = math.min(f.round or 1, d.rounds)
    f.roundLabel:SetText("Round " .. f.round)
    local c = f.cats[f.catAt or 1]
    f.cat:SetLabel(c and c.name or "Any category")
    local plan = Qz:RoundPlan(f.round)
    v.plan.head:SetText("Round " .. f.round .. " · " .. #plan .. " of " .. d.per .. " picked · " .. #Qz:Unused() .. " left in the bank")
    for i, b in ipairs(v.plan.rows) do
      local q = plan[i]
      b.i = q and i or nil
      b:SetShown(q ~= nil or i == 1)
      b.text:SetText(q and (i .. ". " .. q.q .. " |cff5E4B33— " .. q.a .. (q.bank and "" or " (yours)") .. "|r")
        or "|cff5E4B33No questions picked: fill from the bank or add your own (or read them out on Discord).|r")
    end
    return
  end

  if master then
    local d = Qz:Desk()
    local desk = v.desk
    local o = d.open
    desk.head:SetText(Q.name .. " · " .. (Q.round == 0 and "teams joining" or ("round " .. Q.round .. " of " .. Q.rounds)))
    if o then
      local left = math.max(0, o.ends - GetServerTime())
      desk.q:SetText((o.key == "tie" and "Tie-break" or ("Q" .. o.i)) .. " · " .. string.format("%d:%02d", math.floor(left / 60), left % 60) .. " · " .. o.text)
      local q = o.key ~= "tie" and Qz:RoundPlan(o.r)[o.i]
      desk.a:SetText(q and ("Answer: " .. q.a) or "")
    else
      local i = Qz:NextQuestion()
      local q = i and Qz:RoundPlan(Q.round)[i]
      desk.q:SetText(Q.round == 0 and "Teams are joining. Start round 1 when everyone's in."
        or (i and ("Next: Q" .. i .. (q and (" · " .. q.q) or " (read it out on Discord)")) or "Every question this round has been asked: mark and publish."))
      desk.a:SetText(q and ("Answer: " .. q.a) or "")
    end
    local got, waiting = {}, {}
    local answered = Qz:Answered()
    for _, cap in ipairs(Q.order) do
      local T = Q.teams[cap]
      if T then
        if answered[cap] then got[#got + 1] = T.name else waiting[#waiting + 1] = T.name end
      end
    end
    desk.who:SetText(o and ("|cff2E7D32In:|r " .. (#got > 0 and table.concat(got, ", ") or "none yet")
      .. (#waiting > 0 and ("\n|cff8E1B1BWaiting:|r " .. table.concat(waiting, ", ")) or "")) or (#Q.order .. (#Q.order == 1 and " team" or " teams")))
    local canStart = not o and Q.round < Q.rounds and (Q.round == 0 or Q.scores[Q.round] ~= nil)
    desk.start:SetLabel("Start round " .. math.min(Q.round + 1, Q.rounds))
    desk.start:SetEnabled(canStart)
    desk.start:SetAlpha(canStart and 1 or 0.45)
    local canAsk = not o and Q.round > 0 and Qz:NextQuestion() ~= nil
    desk.ask:SetEnabled(canAsk)
    desk.ask:SetAlpha(canAsk and 1 or 0.45)
    desk.closeQ:SetEnabled(o ~= nil)
    desk.closeQ:SetAlpha(o and 1 or 0.45)
    desk.publish:SetEnabled(Q.round > 0)
    desk.publish:SetAlpha(Q.round > 0 and 1 or 0.45)

    -- Marking: the round under way, question by question.
    local mark = v.mark
    local r = math.max(1, Q.round)
    mark.i = math.max(1, math.min(mark.i or 1, Q.per))
    local k = Qz.Key(r, mark.i)
    local q = Qz:RoundPlan(r)[mark.i]
    mark.head:SetText("Marking · round " .. r .. " · Q" .. mark.i)
    mark.answer:SetText(q and ("Answer: " .. q.a) or (d.asked[k] and "Your own answer (read out)" or "Not asked yet"))
    local answers, marks = d.answers[k] or {}, d.marks[k] or {}
    local n = 0
    for _, cap in ipairs(Q.order) do
      local T = Q.teams[cap]
      if T then
        n = n + 1
        local b = mark.rows[n]
        if b then
          b.key, b.cap = k, cap
          local given = answers[cap]
          b.text:SetText("|cff2A1F14" .. T.name .. "|r · " .. (given and ('"' .. given .. '"') or "|cff5E4B33no answer|r")
            .. ((given or marks[cap]) and (" · " .. (MARK[marks[cap] or 0] or "")) or ""))
          b:Show()
        end
      end
    end
    for i = n + 1, #mark.rows do mark.rows[i]:Hide() mark.rows[i].key = nil end
    refreshBoard(v.deskBoard, Q)
    return
  end

  -- Players.
  local team = v.team
  local mine = Q and Qz:TeamOf(MOTA.me, Q)
  local lobby = stage == "lobby"
  team.field:SetShown(lobby and not mine)
  team.make:SetShown(lobby and not mine)
  team.leave:SetShown(lobby and mine ~= nil)
  local captain = mine and mine.cap == MOTA.me
  local canJoker = captain and Qz:Live(Q) and not Q.jokers[MOTA.me]
  team.joker:SetShown(canJoker)
  team.play:SetShown(canJoker)
  if canJoker then
    team.jokerRound = team.jokerRound or 1
    while team.jokerRound <= Q.rounds and Q.started[team.jokerRound] do team.jokerRound = team.jokerRound + 1 end
    if team.jokerRound > Q.rounds then team.jokerRound = 1 end
    team.joker:SetLabel("Joker: round " .. team.jokerRound)
  end
  if not Q or not Qz:Live(Q) then
    team.head:SetText("The Pub Quiz")
    team.name:SetText(stage == "done" and (Qz:Line(Q)) or "No quiz on")
    team.text:SetText(stage == "closed" and (Q.name .. " was ended with no result.")
      or "When the Minister of Games opens a pub quiz, make or join a team here. The questions are read out on Discord; your captain answers in the add-on.")
  elseif mine then
    team.head:SetText(Q.name .. " · " .. (lobby and "teams joining" or ("round " .. Q.round .. " of " .. Q.rounds)))
    local names = {}
    for _, m in ipairs(mine.members) do names[#names + 1] = MOTA:Short(m) .. (m == mine.cap and " (captain)" or "") end
    team.name:SetText(mine.name)
    local L = Qz.live
    local status
    if L and L.id == Q.id then
      if captain then
        status = Qz.sent[L.key] and ("You answered: " .. Qz.sent[L.key] .. (Qz.got[L.key] and " · received" or " · sending…")) or "A question is open: answer in the herald."
      else
        status = "Question open: " .. L.text .. "\nYour captain answers for the team."
      end
    end
    team.text:SetText(table.concat(names, ", ") .. (Q.jokers[mine.cap] and (" · joker on round " .. Q.jokers[mine.cap]) or "")
      .. (status and ("\n" .. status) or ""))
  else
    team.head:SetText(Q.name .. (lobby and " · teams joining" or (" · round " .. Q.round)))
    team.name:SetText(lobby and "Not on a team yet" or "Watching")
    team.text:SetText(lobby and ("Make a team (you'll be its captain) or join one, up to " .. Qz.TEAM_MAX .. " players. Quizmaster: " .. MOTA:Short(Q.by) .. ".") or "Teams were fixed when round 1 began.")
  end

  -- The teams.
  local list = Q and Qz:Live(Q) and Q.order or {}
  for i, r in ipairs(v.teams.rows) do
    local cap = list[i]
    local T = cap and Q.teams[cap]
    r.cap = T and cap or nil
    r:SetShown(T ~= nil or i == 1)
    if T then
      r.text:SetText(T.name .. " |cff5E4B33· " .. #T.members .. "/" .. Qz.TEAM_MAX .. " · " .. MOTA:Short(cap) .. "|r")
      r.join:SetShown(lobby and not mine and #T.members < Qz.TEAM_MAX)
    else
      r.text:SetText("|cff5E4B33No teams yet.|r")
      r.join:Hide()
    end
  end
  refreshBoard(v.board, Q)
end

local function buildQuizAside()
  local h = panel(aside, nil, 0, 0, ASIDE_W, HEIGHT - 66)
  local plate = panel(h, nil, 0, 0, ASIDE_W, 178)
  Kit:PlateArt(plate, "kitBlue", "BACKGROUND")
  local seal = UI:Piece(plate, "hseal_official", "ARTWORK", nil, nil, nil, plate)
  seal:ClearAllPoints()
  seal:SetSize(50, 50)
  seal:SetPoint("TOP", plate, "TOP", 0, -10)
  Kit:Label(plate, "kitTiny", "C9D6F5", 0.28, "The Pub Quiz"):SetPoint("TOP", plate, "TOP", 0, -66)
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
  local how = panel(h, "sunk", 0, 190, ASIDE_W, 190)
  Kit:Label(how, "kitTiny", "7A5719", 0.2, "How it works"):SetPoint("TOPLEFT", how, "TOPLEFT", 14, -12)
  local t = line(how, "kitSmallest", nil, 14, 30, ASIDE_W - 28)
  t:SetMaxLines(11)
  t:SetText("Questions are read out on Discord. Each team's captain answers in the add-on; answers go to the quizmaster alone.\n\nPlay your joker on one round, before it starts: double points.\n\nThe top three teams score for the District Cup, every member.")
  aside.quiz = h
end

local function refreshQuizAside()
  local Qz = MOTA.Quiz
  local p = aside.quiz.plate
  local Q = Qz:Current()
  if quizSetting() then
    local d = Qz:Desk()
    p.name:SetText("Setting a quiz")
    p.big:SetText(d.rounds .. " x " .. d.per)
    p.when:SetText("rounds x questions")
    return
  end
  local s = Qz:Stage(Q)
  p.name:SetText(Q and Q.name or "No quiz yet")
  if s == "running" then
    p.big:SetText(Q.round .. " / " .. Q.rounds)
    p.when:SetText("rounds")
  elseif s == "lobby" then
    local n = #Q.order
    p.big:SetText(n)
    p.when:SetText(n == 1 and "team so far" or "teams so far")
  else
    p.big:SetText("")
    p.when:SetText(Q and Qz:Line(Q) or "The Minister of Games opens one")
  end
end

---------------------------------------------------------------------------
-- The page: a game picker (a drop-down, as the games grow), then The Cup and
-- Honours, which cover every game, as ribbons
---------------------------------------------------------------------------

local GAMES = {
  { key = "lottery", label = "Royal Lottery" },
  { key = "hunt", label = "Treasure Hunt" },
  { key = "hide", label = "Hide and Seek" },
  { key = "quiz", label = "Pub Quiz" },
}
local RIBBONS = { { "cup", 16 }, { "honours", 17 } }
local PICKER_W, PICKER_H = 170, 37
local lastGame = "lottery"

local function isGame(name)
  for _, g in ipairs(GAMES) do if g.key == name then return g end end
end

-- What's on in each game, for the picker's list.
local function gameStatus(key)
  if key == "lottery" then
    local s = MOTA.Lottery and MOTA.Lottery.Stage and MOTA.Lottery:Stage()
    return s == "selling" and "tickets on sale" or nil
  elseif key == "hunt" then
    return MOTA.Hunt:Stage() == "running" and "running" or nil
  elseif key == "hide" then
    local s = MOTA.Hide:Stage()
    return (s == "lobby" and "open to join") or ((s == "hiding" or s == "seeking") and "playing") or nil
  elseif key == "quiz" then
    local s = MOTA.Quiz:Stage()
    return (s == "lobby" and "teams joining") or (s == "running" and "under way") or nil
  end
end
Page.GameStatus = gameStatus

-- The game to open on: one that's on now, or the last one looked at.
function Page:LiveGame()
  for _, k in ipairs({ "quiz", "hide", "hunt", "lottery" }) do
    if gameStatus(k) then return k end
  end
end

local picker, menu

local function buildPicker()
  picker = Kit:Button(root, PICKER_W, PICKER_H, "", "blue", function()
    menu:SetShown(not menu:IsShown())
  end)
  picker:SetPoint("TOPLEFT", root, "TOPLEFT", MAIN_X, 0)
  picker.arrow = picker:CreateTexture(nil, "OVERLAY")
  picker.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  picker.arrow:SetSize(12, 12)
  picker.arrow:SetRotation(-math.pi / 2)
  picker.arrow:SetPoint("RIGHT", picker, "RIGHT", -10, 0)

  menu = CreateFrame("Frame", nil, root)
  menu:SetSize(PICKER_W + 60, #GAMES * 30 + 12)
  menu:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 0, -2)
  menu:SetFrameLevel(root:GetFrameLevel() + 40)
  Kit:Fill(menu, "FBF4E1", "F0E2BE")
  Kit:Outline(menu, "6E4F17", 0.8)
  menu.items = {}
  for i, g in ipairs(GAMES) do
    local b = Kit:Button(menu, PICKER_W + 44, 26, g.label, "quiet", function()
      menu:Hide()
      Page:Select(g.key)
    end)
    b:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -(6 + (i - 1) * 30))
    b.key = g.key
    menu.items[i] = b
  end
  menu:Hide()
end

local function refreshPicker()
  local g = isGame(view) or isGame(lastGame)
  picker:SetLabel(g.label)
  picker:SetAlpha(isGame(view) and 1 or 0.75)
  for i, b in ipairs(menu.items) do
    local s = gameStatus(b.key)
    b:SetLabel(GAMES[i].label .. (s and (" · " .. s) or ""))
  end
end

function Page:Select(name)
  -- "picker" opens the last game (and the old ribbon names still work).
  if name == "picker" then name = lastGame end
  view = name
  if isGame(name) then lastGame = name end
  if menu then menu:Hide() end
  self:Refresh()
end

function Page:View() return view end

function Page:Refresh()
  if not root or not root:IsShown() then return end
  aside.lot:SetShown(view ~= "hunt" and view ~= "hide" and view ~= "quiz")
  aside.hunt:SetShown(view == "hunt")
  aside.hide:SetShown(view == "hide")
  aside.quiz:SetShown(view == "quiz")
  if view == "hunt" then refreshHuntAside()
  elseif view == "hide" then refreshHideAside()
  elseif view == "quiz" then refreshQuizAside()
  else refreshAside() end
  for name, v in pairs(views) do v:SetShown(name == view) end
  for name, t in pairs(tabs) do t:SetOn(name == view) end
  refreshPicker()
  if view == "lottery" then refreshLottery(views.lottery)
  elseif view == "honours" then refreshHonours(views.honours)
  elseif view == "cup" then refreshCup(views.cup)
  elseif view == "hunt" then refreshHunt(views.hunt)
  elseif view == "hide" then refreshHide(views.hide)
  elseif view == "quiz" then refreshQuiz(views.quiz) end
end

local function build()
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
  buildAside()
  buildHuntAside()
  buildHideAside()
  buildQuizAside()
  views = {
    lottery = buildLottery(),
    hunt = buildHunt(),
    hide = buildHide(),
    quiz = buildQuiz(),
    cup = buildCup(),
    honours = buildHonours(),
  }
  buildPicker()
  tabs = {}
  local x = MAIN_X + PICKER_W + 6
  for _, t in ipairs(RIBBONS) do
    local b = Kit:Ribbon(root, t[2], function() Page:Select(t[1]) end)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", x, 0)
    x = x + b:GetWidth() + 2
    tabs[t[1]] = b
  end
end

function Page:Show(show)
  local first = show and not root
  if first then build() end
  if not root then return end
  root:SetShown(show)
  if show then
    -- A game that's on now comes first.
    local live = self:LiveGame()
    if live and (first or isGame(view)) then view, lastGame = live, live end
    self:Refresh()
  end
end

MOTA:Listen("PAGE_SHOWN", function(_, id) Page:Show(id == PAGE_ID) end)
for _, signal in ipairs({ "LOTTERY_CHANGED", "HONOURS_CHANGED", "GAMES_CHANGED", "PARTY_CHANGED", "ACCOUNT_CHANGED", "HUNT_CHANGED", "CUP_CHANGED", "RING_CHANGED", "HIDE_CHANGED", "QUIZ_CHANGED" }) do
  MOTA:Listen(signal, function() Page:Refresh() end)
end
MOTA:On("ZONE_CHANGED_NEW_AREA", function() if view == "hunt" or view == "hide" then Page:Refresh() end end)
-- The clocks and your dot on the play area move each second.
C_Timer.NewTicker(1, function()
  if root and root:IsShown() and ((view == "hide" and MOTA.Hide:Live()) or (view == "quiz" and MOTA.Quiz:Live())) then Page:Refresh() end
end)
