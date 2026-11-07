-- Ministry of the Allied: The Ring tab, following the Gladiator's Ring board
-- (design/canvas-source/GladiatorsRing.dc.html; ADDON_SPEC.md, section 11.3).

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Kit = MOTA.Kit
local Ring = MOTA.Ring
local Page = {}
MOTA.RingPage = Page

local PAGE_ID = "ring"
-- The board's page padding: 20 top, 34 left, 26 right, 24 bottom.
local PARCH = M.slots.parch
local LEFT, TOP = PARCH.x + 34, PARCH.y + 20
local WIDTH, HEIGHT = PARCH.w - 60, PARCH.h - 44
local ASIDE_W, GAP = 206, 20
local MAIN_W = WIDTH - ASIDE_W - GAP
local MAIN_X = ASIDE_W + GAP
local RIBBONS_H = 36 + 12
local BODY_TOP = RIBBONS_H + 26 + 12 -- ribbons, then the level-bracket row
local BODY_H = HEIGHT - BODY_TOP

local root, aside, views, tabs, bandRow
local view = "signup"

local function report(ok, why)
  if not ok and why then MOTA:Print("The Ring:", why) end
end

local function gold(amount)
  if amount == math.floor(amount) then return ("%d g"):format(amount) end
  return ("%d g %d s"):format(math.floor(amount), math.floor((amount % 1) * 100 + 0.5))
end

local function day(t) return t and date("%d %b", t) or "" end

local function panel(parent, kind, x, y, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  if kind then Kit:Plate(f, kind) end
  return f
end

---------------------------------------------------------------------------
-- The left-hand column: event plate, purse, next bout, Minister of War
---------------------------------------------------------------------------

local STAGES = { "Sign-ups", "The draw", "Quarter-finals", "Semi-finals", "The Final" }

local function stageIndex(cur)
  if not cur then return 0 end
  if cur.stage == "done" then return 6 end
  if cur.stage == "signup" then return 1 end
  local slot = cur.next and cur.next.slot or 1
  return slot <= 4 and 3 or (slot <= 6 and 4 or 5)
end

local function buildAside()
  aside = panel(root, nil, 0, 0, ASIDE_W, HEIGHT)

  local ev = panel(aside, nil, 0, 0, ASIDE_W, 178)
  Kit:PlateArt(ev, "kitBlue", "BACKGROUND")
  local seal = UI:Piece(ev, "hseal_ring", "ARTWORK", nil, nil, nil, ev) -- the Seal of the State, Ring page form (portcullis)
  seal:ClearAllPoints()
  seal:SetSize(68, 68)
  seal:SetPoint("TOP", ev, "TOP", 0, -10)
  ev.season = Kit:Label(ev, "kitTiny", "C9D6F5", 0.28)
  ev.stage = Kit:Text(ev, "kitStage", "F3D98A", "CENTER")
  ev.stage:SetPoint("TOP", ev, "TOP", 0, -100)
  ev.stage:SetWidth(ASIDE_W - 16)
  ev.when = Kit:Text(ev, "kitSmallest", "C9D5F0", "CENTER")
  ev.when:SetPoint("TOP", ev.stage, "BOTTOM", 0, -3)
  ev.when:SetWidth(ASIDE_W - 16)
  ev.steps = {}
  for i = 1, #STAGES do
    local step = Kit:Art(ev, "kitStepTodo", "OVERLAY")
    step:SetPoint("CENTER", ev, "BOTTOM", (i - 3) * 29, 29) -- centred, as the lit step's glow makes it larger
    ev.steps[i] = step
    step.piece = "kitStepTodo"
    Kit:Track(function() Kit:Look(step, Kit:AccentName(step.piece)) end) -- the diamonds follow the skin
  end
  aside.event = ev

  local purse = panel(aside, "plain", 0, 190, ASIDE_W, 128)
  Kit:Label(purse, "kitSection", "1B3570", 0.22, "The purse"):SetPoint("TOPLEFT", purse, "TOPLEFT", 14, -12)
  purse.rows = {}
  for i, y in ipairs({ 36, 70, 94 }) do
    local name = Kit:Text(purse, "kitSmall")
    name:SetPoint("TOPLEFT", purse, "TOPLEFT", 14, -y)
    local value = Kit:Amount(purse, "kitAmount")
    value:SetPoint("TOPRIGHT", purse, "TOPRIGHT", -14, -y)
    purse.rows[i] = { name = name, value = value }
  end
  Kit:Rule(purse, ASIDE_W - 28):SetPoint("TOPLEFT", purse, "TOPLEFT", 14, -61)
  aside.purse = purse

  local nb = panel(aside, nil, 0, 330, ASIDE_W, 112)
  Kit:Fill(nb, "8E2B22", "5A140F")
  Kit:Outline(nb, "3A0C08", 1, 0, 1)
  Kit:Outline(nb, "F3D98A", 0.35, 3, 1)
  nb.head = Kit:Label(nb, "kitTiny", "F3C9A8", 0.2)
  nb.head:SetPoint("TOPLEFT", nb, "TOPLEFT", 14, -10)
  nb.gemA = Kit:Gem(nb, "D2AE5C")
  nb.gemA:SetPoint("TOPLEFT", nb, "TOPLEFT", 14, -33)
  nb.a = Kit:Text(nb, "kitName", "FBE9C8")
  nb.a:SetPoint("TOPLEFT", nb, "TOPLEFT", 30, -30)
  nb.a:SetWidth(ASIDE_W - 44)
  nb.vs = Kit:Text(nb, "kitVersus", "F3D98A")
  nb.vs:SetPoint("TOPLEFT", nb, "TOPLEFT", 30, -49)
  nb.vs:SetText("versus")
  nb.gemB = Kit:Gem(nb, "D2AE5C")
  nb.gemB:SetPoint("TOPLEFT", nb, "TOPLEFT", 14, -70)
  nb.b = Kit:Text(nb, "kitName", "FBE9C8")
  nb.b:SetPoint("TOPLEFT", nb, "TOPLEFT", 30, -67)
  nb.b:SetWidth(ASIDE_W - 44)
  nb.where = Kit:Text(nb, "kitSmall", "F3C9A8")
  nb.where:SetPoint("BOTTOMLEFT", nb, "BOTTOMLEFT", 14, 9)
  nb.where:SetText("Old Town")
  aside.nextBout = nb

  local none = panel(aside, "sunk", 0, 330, ASIDE_W, 100)
  Kit:Label(none, "kitTiny", "7A5719", 0.2, "Next bout"):SetPoint("TOPLEFT", none, "TOPLEFT", 14, -12)
  none.title = Kit:Text(none, "kitName")
  none.title:SetPoint("TOPLEFT", none, "TOPLEFT", 14, -29)
  none.title:SetWidth(ASIDE_W - 28)
  none.line = Kit:Text(none, "kitItalic", "5E4B33")
  none.line:SetPoint("TOPLEFT", none.title, "BOTTOMLEFT", 0, -3)
  none.line:SetWidth(ASIDE_W - 28)
  aside.noBout = none

  local foot = panel(aside, nil, 0, HEIGHT - 58, ASIDE_W, 58)
  local line = foot:CreateTexture(nil, "ARTWORK")
  Kit:Solid(line, "6E4F17", 0.35)
  line:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, 0)
  line:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, 0)
  line:SetHeight(1)
  Kit:Label(foot, "kitTiny", "7A5719", 0.2, "Minister of War"):SetPoint("TOPLEFT", foot, "TOPLEFT", 46, -7)
  -- the initials circle wears the window skin's colour (Exchange red, Crown plum...)
  local portrait = UI:SkinPiece(foot, "portrait", "metal", "ARTWORK", nil, nil, nil, nil, foot)
  portrait:ClearAllPoints()
  portrait:SetSize(36, 36)
  portrait:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, -14)
  foot.initials = Kit:Text(foot, "initials", "F3D98A", "CENTER")
  foot.initials:SetPoint("CENTER", portrait, "CENTER", 0, 0)
  foot.name = Kit:Text(foot, "kitNameSmall")
  foot.name:SetPoint("TOPLEFT", foot, "TOPLEFT", 46, -20)
  foot.name:SetWidth(ASIDE_W - 46)
  foot.name:SetMaxLines(2)
  foot.line = Kit:Text(foot, "kitSmallest", "5E4B33")
  foot.line:SetPoint("TOPLEFT", foot.name, "BOTTOMLEFT", 0, -1)
  aside.foot = foot
end

local function refreshAside(cur)
  local ev = aside.event
  local at = stageIndex(cur)
  ev.season:SetText(cur and cur.season or "The Ring")
  ev.season:ClearAllPoints()
  ev.season:SetPoint("TOP", ev, "TOP", 0, -83)
  ev.stage:SetText(STAGES[at] or (at == 6 and "Crowned" or "Not yet called"))
  ev.when:SetText(not cur and "No tournament open"
    or (cur.stage == "signup" and ((cur.bracket or "Open") .. " · closes " .. day(cur.closes))
    or (cur.bracket or "Open")))
  for i, step in ipairs(ev.steps) do
    step.piece = i < at and "kitStepDone" or (i == at and "kitStepNow" or "kitStepTodo")
    Kit:Look(step, Kit:AccentName(step.piece))
  end

  local pot, champ, bank, paid = 0, 0, 0, 0
  if cur then pot, champ, bank, paid = Ring:Purse(cur) end
  local rows = aside.purse.rows
  rows[1].name:SetText(("%d × %s"):format(paid, gold(cur and cur.fee or 0)))
  rows[1].value:SetGold(pot)
  rows[2].name:SetText("Champion · 90%")
  rows[2].value:SetGold(champ)
  rows[3].name:SetText("Guild bank · 10%")
  rows[3].value:SetGold(bank)

  local n = cur and cur.next
  aside.nextBout:SetShown(n ~= nil)
  aside.noBout:SetShown(n == nil)
  if n then
    aside.nextBout.head:SetText("Next bout · " .. (n.slot == 7 and "The Final" or (n.slot >= 5 and "Semi-final" or "Quarter-final")))
    aside.nextBout.a:SetText(MOTA:Short(n.a))
    aside.nextBout.b:SetText(MOTA:Short(n.b))
  else
    aside.noBout.title:SetText(cur and cur.stage == "done" and "The Ring is over" or "Awaiting the draw")
    aside.noBout.line:SetText(cur and cur.stage == "done" and "Until the next tournament." or "Bouts are fought in Old Town.")
  end

  local minister = Ring:Minister()
  aside.foot.name:SetText(minister and MOTA:Short(minister) or "None appointed")
  aside.foot.line:SetText(minister and "Organises the Ring" or "Awaiting the rank")
  -- A name too long for one line takes two, in place of the line beneath it.
  local nameFS = aside.foot.name
  local wide = nameFS.GetUnboundedStringWidth and nameFS:GetUnboundedStringWidth() or nameFS:GetStringWidth()
  aside.foot.line:SetShown(wide <= nameFS:GetWidth())
  aside.foot.initials:SetText(minister and MOTA:Short(minister):sub(1, 2) or "—")
end

---------------------------------------------------------------------------
-- Sign-up: the entry plate, the terms form and the sheet
---------------------------------------------------------------------------

local SIGN_W = (MAIN_W - 18) / 2

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

local function kvRow(parent, y, name)
  local n = Kit:Text(parent, "kitSmall")
  n:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y)
  n:SetText(name)
  local v = Kit:Text(parent, "kitAmount", "1B3570", "RIGHT")
  v:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, -y - 1)
  return v
end

local function buildSignup()
  local v = panel(root, nil, MAIN_X, BODY_TOP, MAIN_W, BODY_H)

  -- The entry plate, once a tournament is open.
  local entry = panel(v, "plain", 0, 0, SIGN_W, BODY_H)
  Kit:Label(entry, "kitSection", "1B3570", 0.22, "Enter the Ring"):SetPoint("TOPLEFT", entry, "TOPLEFT", 16, -14)
  entry.body = Kit:Text(entry, "kitSmall")
  entry.body:SetPoint("TOPLEFT", entry, "TOPLEFT", 16, -36)
  entry.body:SetWidth(SIGN_W - 32)
  Kit:Rule(entry, SIGN_W - 32):SetPoint("TOPLEFT", entry, "TOPLEFT", 16, -112)
  entry.bracket = kvRow(entry, 122, "Bracket")
  entry.fee = kvRow(entry, 144, "Entry fee")
  entry.feeCoin = Kit:Amount(entry, "kitAmount")
  entry.feeCoin:SetPoint("TOPRIGHT", entry, "TOPRIGHT", -16, -144)
  entry.places = kvRow(entry, 166, "Places taken")
  entry.pay = kvRow(entry, 188, "Your fee")
  local function toggle()
    local cur = Ring:Current()
    if cur and Ring:IsEntered(cur) then report(Ring:Withdraw()) else report(Ring:Enter()) end
  end
  entry.enter = Kit:Button(entry, SIGN_W - 32, 36, "Enter the Ring", "gold", toggle)
  entry.enter:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 16, 46)
  entry.withdraw = Kit:Button(entry, SIGN_W - 32, 36, "Withdraw entry", "quiet", toggle)
  entry.withdraw:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 16, 46)
  entry.note = Kit:Text(entry, "kitItalic", "5E4B33", "CENTER")
  entry.note:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 16, 12)
  entry.note:SetWidth(SIGN_W - 32)
  v.entry = entry

  -- The sheet.
  local sheet = panel(v, nil, SIGN_W + 18, 0, SIGN_W, BODY_H)
  sheet.title = Kit:Label(sheet, "kitSection", "1B3570", 0.22)
  sheet.title:SetPoint("TOPLEFT", sheet, "TOPLEFT", 2, 0)
  sheet.status = Kit:Text(sheet, "kitItalic", "5E4B33")
  sheet.status:SetPoint("TOPLEFT", sheet, "TOPLEFT", 2, -18)
  sheet.status:SetWidth(SIGN_W - 4)
  local top = sheet:CreateTexture(nil, "ARTWORK")
  Kit:Solid(top, "6E4F17", 0.55)
  top:SetSize(SIGN_W, 1)
  top:SetPoint("TOPLEFT", sheet, "TOPLEFT", 0, -40)
  sheet.rows = {}
  for i = 1, Ring.MAX_ENTRANTS do
    local r = CreateFrame("Button", nil, sheet)
    r:SetSize(SIGN_W, 32)
    r:SetPoint("TOPLEFT", sheet, "TOPLEFT", 0, -(41 + (i - 1) * 32))
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    local dots = r:CreateTexture(nil, "BORDER")
    Kit:Solid(dots, "6E4F17", 0.3)
    dots:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    dots:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    dots:SetHeight(1)
    r.gem = Kit:Gem(r, "5E4B33")
    r.gem:SetPoint("LEFT", r, "LEFT", 7, 0)
    r.name = Kit:Text(r, "kitDuelist")
    r.name:SetPoint("LEFT", r, "LEFT", 23, 0)
    r.state = Kit:Label(r, "kitTiny", "1F6B4A", 0.16)
    r.state:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.you = Kit:Label(r, "kitTiny", "1B3570", 0.18, "You")
    r.you:SetPoint("RIGHT", r, "RIGHT", -62, 0)
    r:SetScript("OnClick", function()
      local cur = Ring:Current()
      if cur and r.entrant and Ring:CanOrganise() then Ring:SetPaid(r.entrant, not cur.paidAt[r.entrant]) end
    end)
    sheet.rows[i] = r
  end
  sheet.draw = Kit:Button(sheet, SIGN_W, 36, "Close & draw", "blue", function() report(Ring:Draw()) end)
  sheet.draw:SetPoint("BOTTOMLEFT", sheet, "BOTTOMLEFT", 0, 0)
  v.sheet = sheet

  -- The terms form takes the entry plate's place: greyed out until it can be used.
  local form = panel(v, "plain", 0, 0, SIGN_W, BODY_H)
  Kit:Label(form, "kitSection", "1B3570", 0.22, "Call the Ring"):SetPoint("TOPLEFT", form, "TOPLEFT", 16, -14)
  form.intro = Kit:Text(form, "kitSmall")
  form.intro:SetPoint("TOPLEFT", form, "TOPLEFT", 16, -36)
  form.intro:SetWidth(SIGN_W - 32)
  local w = SIGN_W - 32
  form.season = field(form, "Tournament name", 16, 104, w, "")
  form.bracket = field(form, "Level bracket", 16, 154, w, "Open")
  form.fee = field(form, "Entry fee (gold)", 16, 204, w, "1")
  form.days = field(form, "Open days", 16, 254, w, "7")
  form.create = Kit:Button(form, w, 36, "Open the Ring", "gold", function()
    local ok, why = Ring:Create(form.season:GetText(), form.bracket:GetText(), form.fee:GetText(), form.days:GetText())
    report(ok, why)
    if ok then form.season:SetText("") end
  end)
  form.create:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 16, 16)
  v.form = form
  return v
end

local function refreshForm(v, cur)
  local form, usable = v.form, Ring:CanSetTerms()
  form:SetAlpha(usable and 1 or 0.45)
  for _, control in ipairs({ form.season, form.bracket, form.fee, form.days, form.create }) do control:SetEnabled(usable) end
  form.intro:SetText(not Ring:Minister() and "No Minister of War has been appointed. Give someone that guild rank to open the Ring."
    or (not usable and "Only the Minister of War or the Crown can open the Ring.")
    or (cur and "The last tournament is over. Set the terms of the next:" or "Set the terms of the first tournament:"))
end

local function refreshSheet(s, cur, open)
  local count = cur and cur.stage ~= "done" and #cur.entrants or 0
  s.title:SetText(("Entered · %d of %d"):format(count, Ring.MAX_ENTRANTS))
  s.status:SetText(not cur and "No tournament is open yet."
    or (cur.stage == "done" and "The last Ring is over."
    or (open and ("Sign-ups open until %s."):format(day(cur.closes)) or "Closed. See the bracket for the draw.")))
  s.draw:SetShown((open and Ring:CanOrganise()) or false)
  for i, r in ipairs(s.rows) do
    local entrant = cur and cur.stage ~= "done" and (cur.sheet or cur.entrants)[i]
    r.entrant = entrant and entrant.name or nil
    local you = entrant and entrant.name == MOTA.me
    r.you:SetShown(you or false)
    if entrant then
      r.name:SetText(MOTA:Short(entrant.name))
      r.name:SetFontObject(MOTA:Font(you and "kitDuelistBold" or "kitDuelist"))
      r.name:SetTextColor(MOTA:RGB("2A1F14"))
      Kit:Gradient(r.bg, "C9A24A", "C9A24A", you and 0.3 or 0, you and 0.04 or 0, true)
      Kit:Tint(r.gem, "5E4B33")
      local paid = cur.paid[entrant.name]
      r.state:SetText(paid and "Paid" or (cur.paidAt[entrant.name] and "No place" or "Unpaid"))
      r.state:SetColor(paid and "1F6B4A" or "8E1B1B")
    else
      r.name:SetText("Place open")
      r.name:SetFontObject(MOTA:Font("kitItalic"))
      r.name:SetTextColor(MOTA:RGB("5E4B33"))
      Kit:Solid(r.bg, "FFFFFF", 0)
      Kit:Tint(r.gem, "5E4B33", true)
      r.state:SetText("")
    end
  end
end

local function refreshSignup(v, cur)
  local showForm = not cur or cur.stage == "done"
  local open = cur and cur.stage == "signup" or false
  v.form:SetShown(showForm)
  v.entry:SetShown(not showForm)
  refreshSheet(v.sheet, cur, open)
  if showForm then return refreshForm(v, cur) end

  local entered = Ring:IsEntered(cur)
  local e = v.entry
  e.body:SetText(("Pay the entry fee of %s into the guild bank. The bouts are fought in Old Town."):format(gold(cur.fee)))
  e.bracket:SetText(cur.bracket or "Open")
  e.fee:SetText("")
  e.feeCoin:SetGold(cur.fee)
  e.places:SetText(("%d of %d"):format(math.min(#cur.entrants, Ring.MAX_ENTRANTS), Ring.MAX_ENTRANTS))
  e.pay:SetText(not entered and "—" or (cur.paid[MOTA.me] and "Paid" or "Deposit the fee"))
  e.enter:SetShown(open and not entered)
  e.withdraw:SetShown(open and entered)
  e.note:SetText(open and ("Sign-ups close on %s."):format(day(cur.closes)) or "Sign-ups have closed.")
end

---------------------------------------------------------------------------
-- Bracket
---------------------------------------------------------------------------

local COLUMN_GAP = 24
local COLUMN_W = (MAIN_W - 2 * COLUMN_GAP) / 3
local DUELIST_H = 26
local BOUT_H = DUELIST_H * 2 + 1
local BRACKET_TOP = 20
local BRACKET_H = BODY_H - BRACKET_TOP

local function boutCentre(slot)
  local u = BRACKET_H / 8
  if slot <= 4 then return (2 * slot - 1) * u end
  if slot <= 6 then return (slot == 5 and 2 or 6) * u end
  return 4 * u
end

local function boutColumn(slot) return slot <= 4 and 0 or (slot <= 6 and 1 or 2) end

local function wire(parent, x, y, w, h)
  local t = parent:CreateTexture(nil, "BORDER")
  t:SetSize(w, h)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  Kit:Solid(t, "6E4F17", 0.5)
  return t
end

local function duelist(parent, slot, side)
  local d = CreateFrame("Button", nil, parent)
  d:SetSize(COLUMN_W, DUELIST_H)
  d:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, side == "a" and 0 or -(DUELIST_H + 1))
  d.bg = d:CreateTexture(nil, "BACKGROUND", nil, 1)
  d.bg:SetAllPoints()
  Kit:Gradient(d.bg, "C9A24A", "C9A24A", 0.34, 0.06, true)
  d.gem = Kit:Gem(d, "5E4B33")
  d.gem:SetPoint("LEFT", d, "LEFT", 8, 0)
  d.name = Kit:Text(d, "kitDuelist")
  d.name:SetPoint("LEFT", d, "LEFT", 23, 0)
  d.name:SetWidth(COLUMN_W - 30)
  d.name:SetMaxLines(1)
  local glow = d:CreateTexture(nil, "HIGHLIGHT")
  glow:SetColorTexture(1, 0.9, 0.6, 0.2)
  glow:SetAllPoints()
  d:SetScript("OnClick", function()
    local cur = Ring:Current()
    local b = cur and cur.bouts and cur.bouts[slot]
    if b and b[side] and Ring:CanOrganise() then Ring:Result(slot, b[side]) end
  end)
  return d
end

local function buildBracket()
  local v = panel(root, nil, MAIN_X, BODY_TOP, MAIN_W, BODY_H)
  v.field = panel(v, nil, 0, 0, MAIN_W, BODY_H)
  v.heads = {}
  for col, name in ipairs({ "Quarter-finals", "Semi-finals", "The Final" }) do
    local h = Kit:Label(v.field, "kitTiny", "7A5719", 0.2, name)
    h:SetPoint("TOPLEFT", v.field, "TOPLEFT", (col - 1) * (COLUMN_W + COLUMN_GAP), 0)
    v.heads[col] = h
  end
  local area = panel(v.field, nil, 0, BRACKET_TOP, MAIN_W, BRACKET_H)
  v.bouts = {}
  for s = 1, 7 do
    local x = boutColumn(s) * (COLUMN_W + COLUMN_GAP)
    local y = boutCentre(s)
    local half = COLUMN_GAP / 2
    if s < 7 then wire(area, x + COLUMN_W, y, half, 2) end
    if s == 1 or s == 3 or s == 5 then
      local below = s == 5 and boutCentre(6) or boutCentre(s + 1)
      wire(area, x + COLUMN_W + half, y, 2, below - y + 2)
      wire(area, x + COLUMN_W + half, (y + below) / 2, half, 2)
    end
    local b = panel(area, nil, x, y - BOUT_H / 2, COLUMN_W, BOUT_H)
    b.bg = Kit:Fill(b, "FBF4E1", "F0E2BE")
    if s == 7 then
      Kit:Outline(b, "C9A24A", 1, -2, 2) -- the Final's gold frame
      Kit:Outline(b, "5A3F10", 1, -3, 1)
    else
      Kit:Outline(b, "6E4F17", 0.6)
    end
    b.ring = Kit:Outline(b, "8E2B22", 1, s == 7 and -4 or -1, 1)
    local mid = b:CreateTexture(nil, "BORDER")
    Kit:Solid(mid, "6E4F17", 0.4)
    mid:SetPoint("LEFT", b, "LEFT", 0, 0)
    mid:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    mid:SetHeight(1)
    b.a = duelist(b, s, "a")
    b.b = duelist(b, s, "b")
    b.tag = Kit:Label(b, "kitTiny", "8E2B22", 0.2, "Next bout")
    b.tag:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, 6)
    v.bouts[s] = b
  end

  -- The laurels under The Final.
  local champ = panel(area, nil, 2 * (COLUMN_W + COLUMN_GAP), boutCentre(7) + BOUT_H / 2 + 12, COLUMN_W, 100)
  local seal = UI:Piece(champ, "seal", "ARTWORK", nil, nil, nil, champ)
  seal:ClearAllPoints()
  local sp = MOTA.Media.pieces.seal
  seal:SetSize(36 * sp.w / sp.h, 36) -- the Crown crest, taller than it is wide
  seal:SetPoint("TOP", champ, "TOP", 0, 0)
  local title = Kit:Text(champ, "kitLaurel", "7A5719", "CENTER")
  title:SetPoint("TOP", seal, "BOTTOM", 0, -3)
  title:SetWidth(COLUMN_W)
  title:SetText("Gladiator of Stormwind")
  champ.name = Kit:Text(champ, "kitName", "1B3570", "CENTER")
  champ.name:SetPoint("TOP", title, "BOTTOM", 0, -3)
  champ.name:SetWidth(COLUMN_W)
  v.champ = champ

  -- Awaiting the draw.
  local wait = panel(v, "plain", 0, 0, MAIN_W, BODY_H)
  wait.count = Kit:Label(wait, "kitTiny", "7A5719", 0.3)
  wait.count:SetPoint("CENTER", wait, "CENTER", 0, 58)
  wait.title = Kit:Text(wait, "kitAwaiting", "1B3570", "CENTER")
  wait.title:SetPoint("CENTER", wait, "CENTER", 0, 30)
  wait.title:SetText("Awaiting the draw")
  wait.line = Kit:Text(wait, "kitSmall", "2A1F14", "CENTER")
  wait.line:SetPoint("TOP", wait.title, "BOTTOM", 0, -8)
  wait.line:SetWidth(330)
  v.wait = wait
  return v
end

local function showDuelist(d, name, bout)
  d:SetEnabled(bout.a ~= nil and bout.b ~= nil and bout.w == nil and Ring:CanOrganise())
  if not name then
    d.name:SetText(bout.settled and "—" or "Awaiting")
    d.name:SetTextColor(MOTA:RGB("5E4B33"))
    d.bg:SetShown(false)
    Kit:Tint(d.gem, "5E4B33", true)
    return
  end
  d.name:SetText(MOTA:Short(name))
  local won, lost = bout.w == name, bout.w ~= nil and bout.w ~= name
  d.name:SetTextColor(MOTA:RGB(lost and "8C7A5E" or "2A1F14"))
  d.bg:SetShown(won and not bout.bye)
  Kit:Tint(d.gem, "5E4B33", false, lost and 0.4 or 1)
end

local function refreshBracket(v, cur)
  local drawn = cur and cur.drawn
  v.field:SetShown(drawn or false)
  v.wait:SetShown(not drawn)
  if not drawn then
    v.wait.count:SetText(cur and ("%s · %d places taken"):format(cur.bracket or "Open", #cur.entrants) or "No tournament open")
    v.wait.line:SetText(cur and ("Sign-ups close on %s. The bracket is drawn after that, and the bouts are fought in Old Town."):format(day(cur.closes))
      or "The bracket appears here once the Ring is called and drawn.")
    return
  end
  local round = cur.next and (cur.next.slot <= 4 and 1 or (cur.next.slot <= 6 and 2 or 3)) or 0
  for col, h in ipairs(v.heads) do h:SetColor(col == round and MOTA:Accent().INK or "7A5719") end
  for s, frame in ipairs(v.bouts) do
    local b = cur.bouts[s]
    showDuelist(frame.a, b.a, b)
    showDuelist(frame.b, b.b, b)
    local isNext = cur.next == b
    frame.tag:SetShown(isNext)
    for _, side in ipairs(frame.ring) do side:SetShown(isNext) end
  end
  v.champ.name:SetText(cur.champion and MOTA:Short(cur.champion) or "")
end

---------------------------------------------------------------------------
-- Champions
---------------------------------------------------------------------------

local COL_X = { 10, 180, 290, MAIN_W - 10 }

local function buildChampions()
  local v = panel(root, nil, MAIN_X, RIBBONS_H, MAIN_W, HEIGHT - RIBBONS_H)
  Kit:Label(v, "kitSection", "1B3570", 0.22, "The Hall of Champions"):SetPoint("TOPLEFT", v, "TOPLEFT", 2, 0)
  v.line = Kit:Text(v, "kitItalic", "5E4B33")
  v.line:SetPoint("TOPLEFT", v, "TOPLEFT", 2, -18)
  v.line:SetWidth(MAIN_W - 4)
  local tbl = panel(v, "sunk", 0, 42, MAIN_W, HEIGHT - RIBBONS_H - 42)
  for i, name in ipairs({ "The Ring", "Champion", "Runner-up", "Purse" }) do
    local h = Kit:Label(tbl, "kitTiny", "7A5719", 0.2, name)
    if i == 4 then
      h:SetPoint("TOPRIGHT", tbl, "TOPLEFT", COL_X[i], -9)
    else
      h:SetPoint("TOPLEFT", tbl, "TOPLEFT", COL_X[i], -9)
    end
  end
  local head = tbl:CreateTexture(nil, "ARTWORK")
  Kit:Solid(head, "6E4F17", 0.7)
  head:SetPoint("TOPLEFT", tbl, "TOPLEFT", 0, -26)
  head:SetPoint("TOPRIGHT", tbl, "TOPRIGHT", 0, -26)
  head:SetHeight(1)
  v.empty = Kit:Text(tbl, "kitItalic", "5E4B33", "CENTER")
  v.empty:SetPoint("TOP", tbl, "TOP", 0, -46)
  v.empty:SetText("No champion has been crowned yet.")
  v.rows = {}
  for i = 1, 8 do
    local r = panel(tbl, nil, 0, 27 + (i - 1) * 40, MAIN_W, 40)
    local dots = r:CreateTexture(nil, "BORDER")
    Kit:Solid(dots, "6E4F17", 0.3)
    dots:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    dots:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    dots:SetHeight(1)
    r.season = Kit:Text(r, "kitDuelist")
    r.season:SetPoint("TOPLEFT", r, "TOPLEFT", COL_X[1], -4)
    r.season:SetWidth(COL_X[2] - COL_X[1] - 8)
    r.season:SetMaxLines(1)
    r.band = Kit:Text(r, "kitItalic", "5E4B33")
    r.band:SetPoint("TOPLEFT", r.season, "BOTTOMLEFT", 0, 0)
    r.champion = Kit:Text(r, "kitDuelist")
    r.champion:SetPoint("LEFT", r, "LEFT", COL_X[2], 0)
    r.runner = Kit:Text(r, "kitDuelist", "5E4B33")
    r.runner:SetPoint("LEFT", r, "LEFT", COL_X[3], 0)
    r.purse = Kit:Text(r, "kitAmount", "1B3570", "RIGHT")
    r.purse:SetPoint("RIGHT", r, "LEFT", COL_X[4], 0)
    v.rows[i] = r
  end
  return v
end

local function refreshChampions(v)
  local hall = Ring:Hall()
  local newest = hall[#hall]
  v.line:SetText(newest and ("%s holds the title Gladiator of Stormwind."):format(MOTA:Short(newest.champion))
    or "Each month's champion holds the title Gladiator of Stormwind.")
  v.empty:SetShown(newest == nil)
  for i, r in ipairs(v.rows) do
    local h = hall[#hall - i + 1]
    r:SetShown(h ~= nil)
    if h then
      r.season:SetText(h.season)
      r.band:SetText((h.bracket or "Open") .. " · " .. day(h.t))
      r.champion:SetText(MOTA:Short(h.champion))
      r.runner:SetText(h.runnerUp and MOTA:Short(h.runnerUp) or "—")
      r.purse:SetText(gold(h.pot or 0))
    end
  end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

function Page:Form() return views and views.signup.form end

function Page:Select(name)
  view = name
  self:Refresh()
end

function Page:Refresh()
  if not root or not root:IsShown() then return end
  local cur = Ring:Current()
  refreshAside(cur)
  for name, v in pairs(views) do v:SetShown(name == view) end
  for name, t in pairs(tabs) do t:SetOn(name == view) end
  bandRow:SetShown(view ~= "champions")
  bandRow.band:SetText(cur and (cur.bracket or "Open") or "—")
  if view == "signup" then
    refreshSignup(views.signup, cur)
  elseif view == "bracket" then
    refreshBracket(views.bracket, cur)
  else
    refreshChampions(views.champions)
  end
end

local function build()
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
  buildAside()
  views = { signup = buildSignup(), bracket = buildBracket(), champions = buildChampions() }

  tabs = {}
  local x = MAIN_X
  for i, t in ipairs({ { "signup", 1 }, { "bracket", 2 }, { "champions", 3 } }) do
    local b = Kit:Ribbon(root, t[2], function() Page:Select(t[1]) end)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", x, 0)
    x = x + b:GetWidth() + 2
    tabs[t[1]] = b
  end

  bandRow = panel(root, nil, MAIN_X, 48, MAIN_W, 26)
  Kit:Label(bandRow, "kitTiny", "7A5719", 0.3, "Level bracket"):SetPoint("LEFT", bandRow, "LEFT", 0, 0)
  local chip = panel(bandRow, nil, 128, 0, 88, 26)
  Kit:Art(chip, "kitBand", "BACKGROUND"):SetAllPoints()
  bandRow.band = Kit:Text(chip, "kitAmount", "F3D98A", "CENTER")
  bandRow.band:SetPoint("CENTER", chip, "CENTER", 0, 0)
end

function Page:Show(show)
  if show and not root then build() end
  if not root then return end
  root:SetShown(show)
  if show then
    -- Once the bouts have begun, the bracket is what people come to see.
    local cur = Ring:Current()
    if view == "signup" and cur and cur.stage == "bouts" then view = "bracket" end
    self:Refresh()
  end
end

MOTA:Listen("PAGE_SHOWN", function(_, id) Page:Show(id == PAGE_ID) end)
MOTA:Listen("RING_CHANGED", function() Page:Refresh() end)
MOTA:On("GUILD_ROSTER_UPDATE", function() Page:Refresh() end) -- someone may have been given the rank
