-- Ministry of the Allied: the Throne Room, every citizen's home page, following
-- the Throne Room board (design/canvas-source/ThroneRoom.dc.html; ADDON_SPEC.md,
-- section 10). Planned with Duncan 2026-11-08: the board's "Open now" plate
-- shows each thing that's on, one at a time; "Your duties" lists my own to-do
-- items; letters wait for the Court. The data comes from Throne.lua.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Kit = MOTA.Kit
local Page = {}
MOTA.ThronePage = Page

local PAGE_ID = "throne"
local PARCH = M.slots.parch
local LEFT, TOP = PARCH.x + 34, PARCH.y + 20
local WIDTH, HEIGHT = PARCH.w - 60, PARCH.h - 42
local HEAD_H = 72
local GRID_Y = HEAD_H + 16
local GAP = 20
-- Below the banner the page scrolls (Max, 10 Nov): a body taller than the window, with a gold bar beside it.
local BAR_W, BAR_GAP, WHEEL = 10, 12, 40
local BODY_W = WIDTH - BAR_W - BAR_GAP
local LEFT_W = math.floor((BODY_W - GAP) * 1.12 / 2.12) -- the board's 1.12fr / 1fr
local RIGHT_X = LEFT_W + GAP
local RIGHT_W = BODY_W - RIGHT_X
local VIEW_H = HEIGHT - GRID_Y
local LIVE_H, DUTY_H, PLACE_H, VGAP = 130, 104, 78, 10
local DUTY_ROWS, DECREE_ROWS = 3, 5
local DECREE_ROW_H = 26
-- the right column's natural height: the four panels and the decrees under them
local BODY_H = math.max(VIEW_H, LIVE_H + DUTY_H + PLACE_H + 3 * VGAP + 18 + DECREE_ROWS * DECREE_ROW_H + 8)
local GRID_H = BODY_H

local PARTY = { sh = { name = "Silverhand", hex = "1F4290", portrait = "kitPortraitSh", seal = "hseal_silverhand" },
  ex = { name = "Exchange", hex = "9E1B22", portrait = "kitPortraitEx", seal = "hseal_exchange" } }
local SEAL_FOR = { ballot = "hseal_official", nc = "hseal_official", election = "hseal_crown", bench = "hseal_crown",
  ring = "hseal_ring", books = "hseal_treasury", contest_sh = "hseal_silverhand", contest_ex = "hseal_exchange" }

local root, head, power, recruit, live, duties, place, decrees, scroll, body, bar, thumb
local liveIndex = 1

local function panel(parent, kind, x, y, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  if kind == "blue" then
    Kit:PlateArt(f, "kitBlue", "BACKGROUND") -- the drawn accent plate, as the Treasury's coffer (follows the skin)
  elseif kind then
    Kit:Plate(f, kind)
  end
  return f
end

local function seal(parent, name, size)
  local t = UI:Piece(parent, name, "ARTWORK", nil, nil, nil, parent)
  t:ClearAllPoints()
  t:SetSize(size, size)
  return t
end

local function go(page)
  if not page then return end
  UI:SelectPage(page)
end

-- .chip, as on the other pages: a coloured lozenge with a gem and a label.
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

-- An initials circle in the window skin's colour.
local function portrait(parent, size)
  local t = UI:SkinPiece(parent, "portrait", "metal", "ARTWORK", nil, nil, nil, nil, parent)
  t:ClearAllPoints()
  t:SetSize(size, size)
  local initials = Kit:Text(parent, "initials", "F3D98A", "CENTER")
  initials:SetPoint("CENTER", t, "CENTER", 0, 0)
  t.initials = initials
  return t
end

local function initials(name) return MOTA:Initials(name, "—") end

-- A line of text that opens a page when clicked.
local function linkRow(parent, y, w)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 22)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -y)
  b.gem = Kit:Gem(b, "1B3570")
  b.gem:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.text = Kit:Text(b, "kitSmall")
  b.text:SetPoint("LEFT", b, "LEFT", 15, 0)
  b.text:SetWidth(w - 15)
  b.text:SetMaxLines(1)
  b:SetScript("OnClick", function(self) go(self.page) end)
  return b
end

---------------------------------------------------------------------------
-- The banner
---------------------------------------------------------------------------

local function buildHead()
  head = {}
  head.eyebrow = Kit:Label(root, "kitTiny", "7A5719", 0.22, "")
  head.eyebrow:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -6)
  local title = Kit:Text(root, "heading", "1B3570")
  title:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -22)
  title:SetText("The State of the Realm")
  local plate = panel(root, "blue", WIDTH - 236, 0, 236, 64)
  head.crest = seal(plate, "hseal_crown", 46)
  head.crest:SetPoint("LEFT", plate, "LEFT", 12, 0)
  head.plateEyebrow = Kit:Label(plate, "kitTiny", "C9D6F5", 0.2, "")
  head.plateEyebrow:SetPoint("TOPLEFT", plate, "TOPLEFT", 68, -16)
  head.plateText = Kit:Text(plate, "kitStage", "F3D98A")
  head.plateText:SetPoint("TOPLEFT", plate, "TOPLEFT", 68, -31)
  head.plateText:SetWidth(236 - 80)
  head.plateText:SetMaxLines(1)
  Kit:Rule(root, WIDTH):SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(HEAD_H + 4))
end

---------------------------------------------------------------------------
-- Who holds power (and, before the first election, how recruiting goes)
---------------------------------------------------------------------------

local function buildPower()
  local p = panel(body, "plain", 0, 0, LEFT_W, GRID_H)
  power = { frame = p }
  Kit:Label(p, "kitSection", "1B3570", 0.22, "Who holds power"):SetPoint("TOPLEFT", p, "TOPLEFT", 18, -16)

  -- The Crown
  power.k1 = portrait(p, 34)
  power.k1:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -40)
  power.k2 = portrait(p, 34)
  power.k2:SetPoint("TOPLEFT", p, "TOPLEFT", 44, -40)
  Kit:Label(p, "kitTiny", "7A5719", 0.2, "The Crown"):SetPoint("TOPLEFT", p, "TOPLEFT", 92, -42)
  power.crown = Kit:Text(p, "kitName")
  power.crown:SetPoint("TOPLEFT", p, "TOPLEFT", 92, -56)
  power.crown:SetWidth(LEFT_W - 92 - 60)
  power.crown:SetMaxLines(1)
  seal(p, "hseal_crown", 38):SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -38)
  Kit:Rule(p, LEFT_W - 36):SetPoint("TOPLEFT", p, "TOPLEFT", 18, -86)

  -- The government
  local gov = panel(p, nil, 0, 94, LEFT_W, GRID_H - 94)
  power.gov = gov
  power.pmArt = {}
  for key, party in pairs(PARTY) do
    local t = Kit:Art(gov, party.portrait)
    t:SetSize(57, 57)
    t:SetPoint("CENTER", gov, "TOPLEFT", 46, -30)
    power.pmArt[key] = t
  end
  power.pmPlain = portrait(gov, 46)
  power.pmPlain:SetPoint("CENTER", gov, "TOPLEFT", 46, -30)
  power.pmInitials = Kit:Text(gov, "initials", "F3D98A", "CENTER")
  power.pmInitials:SetPoint("CENTER", gov, "TOPLEFT", 46, -30)
  Kit:Label(gov, "kitTiny", "7A5719", 0.2, "Prime Minister"):SetPoint("TOPLEFT", gov, "TOPLEFT", 84, -6)
  power.pm = Kit:Text(gov, "kitStage")
  power.pm:SetPoint("TOPLEFT", gov, "TOPLEFT", 84, -20)
  power.pm:SetWidth(LEFT_W - 100)
  power.pm:SetMaxLines(1)
  power.pmChip = chip(gov)
  power.pmChip:SetPoint("TOPLEFT", gov, "TOPLEFT", 84, -44)
  power.since = Kit:Text(gov, "kitItalic", "5E4B33")
  power.since:SetPoint("LEFT", power.pmChip, "RIGHT", 8, 0)

  local cab = panel(gov, "sunk", 18, 74, LEFT_W - 36, 4 * 20 + 16) -- five posts, at 17 apart
  power.cab = {}
  for i = 1, 5 do
    local label = Kit:Label(cab, "kitTiny", "7A5719", 0.14, "")
    label:SetPoint("TOPLEFT", cab, "TOPLEFT", 12, -(10 + (i - 1) * 17))
    local name = Kit:Text(cab, "kitSmall")
    name:SetPoint("TOPLEFT", cab, "TOPLEFT", 110, -(7 + (i - 1) * 17))
    name:SetWidth(LEFT_W - 36 - 122)
    name:SetMaxLines(1)
    power.cab[i] = { label = label, name = name }
  end

  power.justices = Kit:Text(gov, "kitItalic", "5E4B33")
  power.justices:SetPoint("TOPLEFT", gov, "TOPLEFT", 18, -(74 + 96 + 10))
  power.justices:SetWidth(LEFT_W - 36)

  local opp = panel(gov, nil, 18, GRID_H - 94 - 54, LEFT_W - 36, 40)
  power.oppPortrait = portrait(opp, 34)
  power.oppPortrait:SetPoint("LEFT", opp, "LEFT", 0, 0)
  Kit:Label(opp, "kitTiny", "7A5719", 0.2, "Leader of the Opposition"):SetPoint("TOPLEFT", opp, "TOPLEFT", 46, -2)
  power.opp = Kit:Text(opp, "kitName")
  power.opp:SetPoint("TOPLEFT", opp, "TOPLEFT", 46, -16)
  power.opp:SetWidth(LEFT_W - 36 - 46 - 110)
  power.opp:SetMaxLines(1)
  power.oppChip = chip(opp)
  power.oppChip:SetPoint("RIGHT", opp, "RIGHT", 0, 0)

  -- Before the first election
  recruit = panel(p, nil, 0, 94, LEFT_W, GRID_H - 94)
  Kit:Label(recruit, "kitTiny", "7A5719", 0.2, "Before the first election"):SetPoint("TOPLEFT", recruit, "TOPLEFT", 18, -6)
  recruit.lines = {}
  for i = 1, 3 do
    local t = Kit:Text(recruit, "kitSmall")
    t:SetPoint("TOPLEFT", recruit, "TOPLEFT", 18, -(26 + (i - 1) * 24))
    t:SetWidth(LEFT_W - 36)
    recruit.lines[i] = t
  end
  recruit.note = Kit:Text(recruit, "kitItalic", "5E4B33")
  recruit.note:SetPoint("TOPLEFT", recruit, "TOPLEFT", 18, -110)
  recruit.note:SetWidth(LEFT_W - 36)
  recruit.justices = Kit:Text(recruit, "kitItalic", "5E4B33")
  recruit.justices:SetPoint("TOPLEFT", recruit, "TOPLEFT", 18, -170)
  recruit.justices:SetWidth(LEFT_W - 36)
end

---------------------------------------------------------------------------
-- The right column: what's on, my duties, my place, recent decrees
---------------------------------------------------------------------------

local function buildLive()
  local p = panel(body, "blue", RIGHT_X, 0, RIGHT_W, LIVE_H)
  live = { frame = p }
  Kit:Label(p, "kitSection", "F3D98A", 0.22, "What's on"):SetPoint("TOPLEFT", p, "TOPLEFT", 16, -14)
  -- LIVE, with its red dot
  local dot = p:CreateTexture(nil, "OVERLAY")
  Kit:Solid(dot, "E0705C")
  dot:SetSize(7, 7)
  live.dot = dot
  live.liveLabel = Kit:Label(p, "kitTiny", "FFD0C4", 0.2, "LIVE")
  live.liveLabel:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -15)
  dot:SetPoint("RIGHT", live.liveLabel, "LEFT", -6, 0)
  live.seals = {}
  for key, name in pairs(SEAL_FOR) do
    local s = seal(p, name, 48)
    s:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -38)
    live.seals[key] = s
  end
  live.title = Kit:Text(p, "kitName", "F3D98A")
  live.title:SetPoint("TOPLEFT", p, "TOPLEFT", 72, -42)
  live.title:SetWidth(RIGHT_W - 88)
  live.title:SetMaxLines(1)
  live.line = Kit:Text(p, "kitSmallest", "C9D5F0")
  live.line:SetPoint("TOPLEFT", p, "TOPLEFT", 72, -62)
  live.line:SetWidth(RIGHT_W - 88)
  live.line:SetMaxLines(2)
  live.button = Kit:Button(p, 150, 28, "Open", "gold", function() go(live.page) end)
  live.button:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 16, 12)
  live.count = Kit:Label(p, "kitTiny", "C9D6F5", 0.14, "")
  live.count:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -16, 20)
  live.more = CreateFrame("Button", nil, p)
  live.more:SetAllPoints(live.count)
  live.more:SetScript("OnClick", function()
    liveIndex = liveIndex + 1
    Page:Refresh()
  end)
  live.none = Kit:Text(p, "kitItalic", "C9D5F0")
  live.none:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -46)
  live.none:SetWidth(RIGHT_W - 32)
  live.none:SetText("Nothing is open just now. Elections, votes and tournaments appear here as they begin.")
end

local function buildDuties()
  local y = LIVE_H + VGAP
  local p = panel(body, "plain", RIGHT_X, y, RIGHT_W, DUTY_H)
  duties = { frame = p, rows = {} }
  Kit:Label(p, "kitSection", "1B3570", 0.22, "Your duties"):SetPoint("TOPLEFT", p, "TOPLEFT", 16, -12)
  for i = 1, DUTY_ROWS do duties.rows[i] = linkRow(p, 28 + (i - 1) * 22, RIGHT_W - 32) end
  duties.none = Kit:Text(p, "kitItalic", "5E4B33")
  duties.none:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -34)
  duties.none:SetWidth(RIGHT_W - 32)
  duties.none:SetText("Nothing waits for you.")
end

local function buildPlace()
  local y = LIVE_H + VGAP + DUTY_H + VGAP
  local p = panel(body, "plain", RIGHT_X, y, RIGHT_W, PLACE_H)
  place = { frame = p }
  Kit:Label(p, "kitSection", "1B3570", 0.22, "Your place"):SetPoint("TOPLEFT", p, "TOPLEFT", 16, -12)
  place.district = chip(p)
  place.district:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -30)
  place.party = chip(p)
  place.party:SetPoint("LEFT", place.district, "RIGHT", 8, 0)
  place.meet = Kit:Text(p, "kitSmallest", "2A1F14")
  place.meet:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -56)
  place.meet:SetWidth(RIGHT_W - 32)
  place.meet:SetMaxLines(1)
end

local function buildDecrees()
  local y = LIVE_H + VGAP + DUTY_H + VGAP + PLACE_H + VGAP
  local p = panel(body, nil, RIGHT_X, y, RIGHT_W, BODY_H - y)
  decrees = { frame = p, rows = {} }
  Kit:Label(p, "kitSection", "1B3570", 0.22, "Recent decrees"):SetPoint("TOPLEFT", p, "TOPLEFT", 2, 0)
  local rowH = DECREE_ROW_H
  for i = 1, DECREE_ROWS do
    local r = CreateFrame("Button", nil, p)
    r:SetSize(RIGHT_W, rowH)
    r:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -(18 + (i - 1) * rowH))
    r.gem = Kit:Gem(r, "1B3570")
    r.gem:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.text = Kit:Text(r, "kitSmall", "5E4B33")
    r.text:SetPoint("LEFT", r, "LEFT", 16, 0)
    r.text:SetWidth(RIGHT_W - 16 - 44)
    r.text:SetMaxLines(1)
    r.ago = Kit:Text(r, "kitItalic", "5E4B33", "RIGHT")
    r.ago:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    local dots = r:CreateTexture(nil, "BORDER")
    Kit:Solid(dots, "6E4F17", 0.3)
    dots:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    dots:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    dots:SetHeight(1)
    r:SetScript("OnClick", function(self) go(self.page) end)
    decrees.rows[i] = r
  end
  decrees.none = Kit:Text(p, "kitItalic", "5E4B33")
  decrees.none:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -24)
  decrees.none:SetWidth(RIGHT_W)
  decrees.none:SetText("Nothing has been decreed yet.")
end

---------------------------------------------------------------------------
-- Filling it in
---------------------------------------------------------------------------

local function refreshPower()
  local T = MOTA.Throne
  local data = T:Power()
  local kings = data.crown
  power.k1:SetShown(kings[1] ~= nil)
  power.k2:SetShown(kings[2] ~= nil)
  power.k1.initials:SetText(initials(kings[1]))
  power.k2.initials:SetText(initials(kings[2]))
  power.k1.initials:SetShown(kings[1] ~= nil)
  power.k2.initials:SetShown(kings[2] ~= nil)
  local names = {}
  for i, n in ipairs(kings) do if i <= 2 then names[#names + 1] = MOTA:Short(n) end end
  power.crown:SetText(#names > 0 and table.concat(names, " & ") or "The Crown")

  power.gov:SetShown(data.pm ~= nil)
  recruit:SetShown(data.pm == nil)
  if data.pm then
    local party = data.pm.p and PARTY[data.pm.p]
    for key, t in pairs(power.pmArt) do t:SetShown(key == data.pm.p) end
    power.pmPlain:SetShown(party == nil)
    power.pmPlain.initials:SetShown(false)
    power.pmInitials:SetText(initials(data.pm.name))
    power.pm:SetText(MOTA:Short(data.pm.name))
    power.pmChip:SetShown(party ~= nil)
    if party then power.pmChip:Set(party.name, party.hex) end
    power.since:SetText("In office since " .. date("%d %b", data.pm.since))
    for i, row in ipairs(power.cab) do
      local c = data.cabinet[i]
      row.label:SetText(c and c.title or "")
      row.name:SetText(c and (c.name and MOTA:Short(c.name) or "|cff8A7A5EVacant|r") or "")
    end
    power.justices:SetText(data.justices or "")
    local opp = data.opposition
    power.oppPortrait.initials:SetText(initials(opp and opp.name))
    power.opp:SetText(opp and opp.name and MOTA:Short(opp.name) or "No leader")
    power.oppChip:SetShown(opp ~= nil)
    if opp then power.oppChip:Set(PARTY[opp.p].name, PARTY[opp.p].hex) end
  else
    local g, El = data.gates, MOTA.Elect
    -- A gate that's met shows its count in green.
    local function count(n, need) return ("|cff%s%d of %d|r"):format(n >= need and "2E7D4F" or "1B3570", n, need) end
    recruit.lines[1]:SetText("Active players with the add-on: " .. count(g.players, El.GATE_PLAYERS))
    for i, key in ipairs({ "sh", "ex" }) do
      local leader = data.leaders[key]
      recruit.lines[i + 1]:SetText(("The %s: %s members%s"):format(PARTY[key].name, count(g[key], El.GATE_PARTY),
        leader and (" · led by " .. MOTA:Short(leader)) or ""))
    end
    recruit.note:SetText(El:Begun() and "The first General Election has been called. The leadership contests come first."
      or "When both are met, the Crown begins the first General Election: polling day 28 days on, with the leadership contests first.")
    recruit.justices:SetText(data.justices or "")
  end
end

local function refreshLive()
  local list = MOTA.Throne:Live()
  local n = #list
  if liveIndex > n then liveIndex = 1 end
  local e = list[liveIndex]
  live.none:SetShown(n == 0)
  live.title:SetShown(e ~= nil)
  live.line:SetShown(e ~= nil)
  live.button:SetShown(e ~= nil and e.page ~= nil)
  live.dot:SetShown(e ~= nil and e.live == true)
  live.liveLabel:SetShown(e ~= nil and e.live == true)
  for key, s in pairs(live.seals) do s:SetShown(e ~= nil and key == e.key) end
  live.count:SetText(n > 1 and (liveIndex .. " of " .. n .. "  ›") or "")
  live.more:SetShown(n > 1)
  if e then
    live.title:SetText(e.title)
    live.line:SetText(e.line or "")
    live.page = e.page
    live.button:SetLabel(e.button or "Open")
  end
end

local function refreshDuties()
  local list = MOTA.Throne:Duties()
  duties.none:SetShown(#list == 0)
  for i, r in ipairs(duties.rows) do
    local d = list[i]
    r:SetShown(d ~= nil)
    if d then
      r.page = d.page
      r.text:SetText(i == DUTY_ROWS and #list > DUTY_ROWS and (d.text .. " |cff5E4B33(+" .. (#list - DUTY_ROWS) .. " more)|r") or d.text)
    end
  end
end

local DISTRICT_HEX = "3D86C6"

local function refreshPlace()
  local me = MOTA.me
  local d = me and MOTA.DistrictOf and MOTA:DistrictOf(me)
  place.district:Set(d and (d.short or d.name) or "No district yet", d and (d.color or DISTRICT_HEX) or "8A7A5E")
  place.meet:SetText(d and d.meet and ("Council meets at the |cff1B3570" .. d.meet .. "|r") or "Your add-on places you in a district soon after you first log in.")
  local p = me and MOTA.Party:Of(me)
  if me and MOTA:IsCrown(me) then place.party:Set("The Crown", "6E2A8C")
  elseif p then place.party:Set(PARTY[p].name, PARTY[p].hex)
  else place.party:Set("No party", "8A7A5E") end
end

local function refreshDecrees()
  local list = MOTA.Throne:Decrees(DECREE_ROWS)
  decrees.none:SetShown(#list == 0)
  for i, r in ipairs(decrees.rows) do
    local e = list[i]
    r:SetShown(e ~= nil)
    if e then
      Kit:Tint(r.gem, e.hex)
      r.text:SetText(e.text)
      r.ago:SetText(MOTA.Throne:Ago(e.t))
      r.page = e.page
    end
  end
end

function Page:Refresh()
  if not root or not root:IsShown() or not MOTA.guild then return end
  local b = MOTA.Throne:Banner()
  head.eyebrow:SetText(b.eyebrow:upper())
  head.plateEyebrow:SetText((b.plateEyebrow or ""):upper())
  head.plateText:SetText(b.plateText or "")
  refreshPower()
  refreshLive()
  refreshDuties()
  refreshPlace()
  refreshDecrees()
end

---------------------------------------------------------------------------
-- Scrolling: the wheel, a click on the bar, or dragging its gold thumb
---------------------------------------------------------------------------

local function range() return math.max(0, BODY_H - VIEW_H) end

local function placeThumb()
  local r = range()
  bar:SetShown(r > 0)
  if r <= 0 then return end
  local h = math.max(30, VIEW_H * VIEW_H / (VIEW_H + r))
  thumb:SetHeight(h)
  local at = (scroll:GetVerticalScroll() or 0) / r
  thumb:ClearAllPoints()
  thumb:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -(2 + at * (VIEW_H - 4 - h)))
end

local function scrollTo(v)
  scroll:SetVerticalScroll(math.max(0, math.min(range(), v)))
  placeThumb()
end

local function cursorY()
  local _, y = GetCursorPosition()
  return y / (bar:GetEffectiveScale() or 1)
end

local function silver() return MOTA.skin and MOTA.skin.METAL == "silver" end

local function buildBar()
  bar = CreateFrame("Button", nil, root)
  bar:SetSize(BAR_W, VIEW_H)
  bar:SetPoint("TOPLEFT", root, "TOPLEFT", BODY_W + BAR_GAP, -GRID_Y)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  Kit:Solid(track, "6E4F17", 0.18)
  track:SetAllPoints()
  Kit:Outline(bar, "6E4F17", 0.4)
  thumb = CreateFrame("Button", nil, bar)
  thumb:SetWidth(BAR_W - 2)
  local left = thumb:CreateTexture(nil, "ARTWORK")
  left:SetPoint("TOPLEFT")
  left:SetPoint("BOTTOMRIGHT", thumb, "BOTTOM", 0, 0)
  local right = thumb:CreateTexture(nil, "ARTWORK")
  right:SetPoint("TOPLEFT", thumb, "TOP", 0, 0)
  right:SetPoint("BOTTOMRIGHT")
  Kit:Outline(thumb, "4A330C", 0.7)
  Kit:Track(function() -- the metal: gold, or Silverhand's silver
    local dark, light = "8A6420", "E9C979"
    if silver() then dark, light = "6B7483", "EEF2F6" end
    Kit:Gradient(left, dark, light, 1, 1, true)
    Kit:Gradient(right, light, dark, 1, 1, true)
  end)
  bar:SetScript("OnClick", function()
    local top = thumb:GetTop() or 0
    scrollTo(scroll:GetVerticalScroll() + (cursorY() > top and -VIEW_H or VIEW_H))
  end)
  thumb:SetScript("OnMouseDown", function(self)
    self.from, self.start = cursorY(), scroll:GetVerticalScroll()
    self:SetScript("OnUpdate", function()
      local free = VIEW_H - 4 - self:GetHeight()
      if free <= 0 then return end
      scrollTo(self.start + (self.from - cursorY()) / free * range())
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
  placeThumb()
end

local function build()
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
  buildHead()
  scroll = CreateFrame("ScrollFrame", nil, root)
  scroll:SetSize(BODY_W, VIEW_H)
  scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -GRID_Y)
  body = CreateFrame("Frame", nil, scroll)
  body:SetSize(BODY_W, BODY_H)
  scroll:SetScrollChild(body)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, delta) scrollTo(scroll:GetVerticalScroll() - delta * WHEEL) end)
  buildPower()
  buildLive()
  buildDuties()
  buildPlace()
  buildDecrees()
  buildBar()
  Page.root, Page.scroll, Page.head, Page.live = root, scroll, head, live -- for the pretend client's checks
end

function Page:Show(show)
  if show and not root then build() end
  if not root then return end
  root:SetShown(show)
  if show then self:Refresh() end
end

MOTA:Listen("PAGE_SHOWN", function(_, id) Page:Show(id == PAGE_ID) end)
for _, event in ipairs({ "RECORD_ADDED", "PARTY_CHANGED", "CONTEST_CHANGED", "CONFIDENCE_CHANGED", "LEDGER_CHANGED",
  "JUDICIARY_CHANGED", "ROSTER_UPDATED", "CAUGHT_UP", "BANK_PROMPT" }) do
  MOTA:Listen(event, function()
    -- Many records can arrive at once: one redraw for the lot.
    if Page.pending then return end
    Page.pending = true
    C_Timer.After(0.2, function()
      Page.pending = false
      Page:Refresh()
    end)
  end)
end
-- Countdowns move on while the page is open.
MOTA:Listen("GUILD_READY", function()
  if Page.ticking then return end
  Page.ticking = true
  C_Timer.NewTicker(30, function() Page:Refresh() end)
end)
