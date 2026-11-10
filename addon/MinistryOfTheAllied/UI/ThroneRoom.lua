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
-- Who holds power, in the board's numbers (the window is 1000 x 680 on the board and in the game, so 1 to 1)
local PAD_X, PAD_Y, FLOW = 18, 16, 12      -- .plate padding 16 18; the column's gap
local PW = LEFT_W - 2 * PAD_X              -- inside the plate
local PORTRAIT_SM = 42                     -- .portrait.sm: a 36px disc, plus its 2.5px ring and edge
local PM_DISC = 76                         -- .portrait.lg
local PM_ART = math.floor(67 * PM_DISC / 52 + 0.5)    -- the party portrait art (a 52px disc in a 67px piece), scaled up
local PM_PLAIN = math.floor(42 * PM_DISC / 36 + 0.5)  -- the skin's portrait (a 36px disc in a 42px piece)

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

-- The page object of each tab that has views, to switch to the right one after the tab opens.
local function pageObject(i)
  return ({ [3] = MOTA.StatutesPage, [4] = MOTA.PartiesPage, [6] = MOTA.DistrictsPage, [7] = MOTA.RingPage, [8] = MOTA.GamesPage })[i]
end

local function go(page, view)
  if not page then return end
  UI:SelectPage(page)
  local obj = view and pageObject(page)
  if obj and obj.Select then obj:Select(view) end
end

-- Every box that opens another page: click anywhere on it, a faint glow on hover, and a tooltip
-- saying where it goes. A box with no destination has no glow and no click (Kit:Hot).
local VIEW_LABEL = { map = "Map", council = "Council", roll = "Roll", sh = "Silverhand", ex = "Exchange", ch = "Chamber",
  force = "In force", wait = "Awaiting", court = "Court", charter = "Charter", lottery = "Lottery", hunt = "Treasure hunt",
  cup = "Cup", honours = "Honours", signup = "Sign-up", bracket = "Bracket", champions = "Champions" }

local function where(page, view)
  local p = M.pages[page]
  if not p then return "" end
  return "Opens " .. p.label .. (view and VIEW_LABEL[view] and (" · " .. VIEW_LABEL[view]) or "")
end

local hot = {}
Page.hot = hot -- for the pretend client's checks

local function link(box)
  local h = Kit:Hot(box, function(self) go(self.page, self.view) end)
  hot[#hot + 1] = h
  return h
end

local function aim(h, page, view, tip)
  page = page or nil -- a false from "x and page" counts as no page
  h:SetTarget(page, view, page and (tip or where(page, view)) or "")
end

-- An empty frame to lay a link over a part of a panel.
local function zone(parent, x, y, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  return f
end

-- .chip, as on the other pages: a coloured lozenge with a gem and a label.
local function chip(parent, font)
  local c = CreateFrame("Frame", nil, parent)
  c:SetHeight(22)
  local fill = c:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints()
  Kit:Outline(c, "000000", 0.28)
  local gem = Kit:Gem(c, "F3D98A")
  gem:SetPoint("LEFT", c, "LEFT", 8, 0)
  c.label = Kit:Label(c, font or "kitTiny", "FFFFFF", 0.14) -- .chip is 10px on the Throne Room board (bEyebrow)
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
  head.hot = link(plate)
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
  -- The board's plate (section.plate: padding 16 18, a column with a 12 gap). Everything below is put by
  -- layoutPower() each time it is filled in, from the board's numbers (measured in Edge, see ADDON_SPEC 19.1).
  local p = panel(body, "plain", 0, 0, LEFT_W, GRID_H)
  power = { frame = p, geo = {}, rows = { cab = {} } }
  power.title = Kit:Label(p, "bSec", "1B3570", 0.22, "Who holds power") -- .h-sec at 13
  power.previewTag = chip(p, "bEyebrow") -- /mota throne preview: drawn from a made-up government
  power.previewTag:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD_X, -14)
  power.previewTag:Set("Preview", "9E1B22")
  power.previewTag:Hide()

  -- The Crown: two overlapping 36px portraits (the ring makes the piece 42), the name, the crest at 38
  power.k1 = portrait(p, PORTRAIT_SM)
  power.k2 = portrait(p, PORTRAIT_SM)
  power.crownEyebrow = Kit:Label(p, "bEyebrow", "7A5719", 0.32, "The Crown")
  power.crown = Kit:Text(p, "tName15")
  power.crown:SetMaxLines(2)
  power.crownProbe = Kit:Text(p, "tName15") -- one line of the same font, to count the name's lines against
  power.crownProbe:SetText("Ag")
  power.crownProbe:Hide()
  power.crest = seal(p, "hseal_crown", 38)
  power.rule = Kit:Rule(p, PW)
  power.rows.crown = CreateFrame("Frame", nil, p)

  -- The government, from the Prime Minister down (gov starts at the Prime Minister's row)
  local gov = panel(p, nil, 0, 94, LEFT_W, GRID_H - 94)
  power.gov = gov
  power.pmArt = {}
  for key, party in pairs(PARTY) do
    local t = Kit:Art(gov, party.portrait)
    t:SetSize(PM_ART, PM_ART)
    t:SetPoint("CENTER", gov, "TOPLEFT", PAD_X + 38, -38)
    power.pmArt[key] = t
  end
  power.pmPlain = portrait(gov, PM_PLAIN)
  power.pmPlain:SetPoint("CENTER", gov, "TOPLEFT", PAD_X + 38, -38)
  power.pmInitials = Kit:Text(gov, "tInitialsLg", "F3D98A", "CENTER")
  power.pmInitials:SetPoint("CENTER", gov, "TOPLEFT", PAD_X + 38, -38)
  power.pmEyebrow = Kit:Label(gov, "bEyebrow", "7A5719", 0.32, "Prime Minister")
  power.pm = Kit:Text(gov, "tName19")
  power.pm:SetMaxLines(1)
  power.pm:SetWidth(PW - 90)
  power.pmChip = chip(gov, "bEyebrow")
  power.since = Kit:Text(gov, "kitSmall", "5E4B33") -- .small.muted
  power.rows.pm = CreateFrame("Frame", nil, gov) -- the rows below are in gov, so they go with it when it hides

  local cab = panel(gov, "sunk", PAD_X, 88, PW, 130) -- .plate.sunk: padding 10 12, five rows 18 high, 5 apart
  power.cab = {}
  power.cabFrame = cab
  for i = 1, 5 do
    local label = Kit:Label(cab, "eyebrow", "7A5719", 0.32, "") -- .eyebrow at 9.5
    local name = Kit:Text(cab, "kitSmall")
    name:SetMaxLines(1)
    power.cab[i] = { label = label, name = name }
    power.rows.cab[i] = CreateFrame("Frame", nil, gov)
  end

  -- Not on the board (Max, 10 Nov): the Justices, small and italic under the Cabinet
  power.justices = Kit:Text(gov, "bItalic", "5E4B33")
  power.justices:SetWidth(PW)
  power.rows.justices = CreateFrame("Frame", nil, gov)

  -- The Leader of the Opposition, pinned to the bottom of the plate
  local opp = panel(gov, nil, PAD_X, GRID_H - 94 - 54, PW, 49)
  power.oppFrame = opp
  power.rows.opp = opp
  power.oppPortrait = portrait(opp, PORTRAIT_SM)
  power.oppPortrait:SetPoint("CENTER", opp, "TOPLEFT", 18, -24.5)
  power.oppEyebrow = Kit:Label(opp, "bEyebrow", "7A5719", 0.32, "Leader of the Opposition")
  power.oppEyebrow2 = Kit:Label(opp, "bEyebrow", "7A5719", 0.32, "Opposition") -- the board's label wraps to two lines
  power.opp = Kit:Text(opp, "tName15")
  power.opp:SetMaxLines(1)
  power.oppChip = chip(opp, "bEyebrow")
  power.oppChip:SetPoint("RIGHT", opp, "TOPRIGHT", 0, -24.5)

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
  Page.power = power -- for the pretend client's checks (power.geo, power.rows)
end

-- The click targets of Who holds power: laid over the row frames layoutPower sizes (power.rows), so a
-- change to that layout moves them too. Aimed in refreshPowerLinks. The recruiting lines are text,
-- so a frame is stretched over each.
local function buildPowerLinks()
  local rows = power.rows
  power.links = { cab = {}, recruit = {} }
  local L = power.links
  L.crown = link(rows.crown)
  L.pm = link(rows.pm)
  for i = 1, #power.cab do L.cab[i] = link(rows.cab[i]) end
  L.justices = link(rows.justices)
  L.opp = link(rows.opp)
  local function over(text)
    local f = CreateFrame("Frame", nil, recruit)
    f:SetAllPoints(text)
    return link(f)
  end
  for i = 1, 3 do L.recruit[i] = over(recruit.lines[i]) end
  L.recruitJustices = over(recruit.justices)
end

---------------------------------------------------------------------------
-- The right column: what's on, my duties, my place, recent decrees
---------------------------------------------------------------------------

local function buildLive()
  local p = panel(body, "blue", RIGHT_X, 0, RIGHT_W, LIVE_H)
  live = { frame = p }
  live.hot = link(p) -- the whole plate opens what's on; the buttons below sit above it
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
  live.button = Kit:Button(p, 150, 28, "Open", "gold", function() go(live.page, live.view) end)
  live.hot:Above(live.button)
  live.button:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 16, 12)
  live.count = Kit:Label(p, "kitTiny", "C9D6F5", 0.14, "")
  live.count:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -16, 20)
  live.more = CreateFrame("Button", nil, p)
  live.more:SetAllPoints(live.count)
  live.hot:Above(live.more)
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
  for i = 1, DUTY_ROWS do
    local r = linkRow(p, 28 + (i - 1) * 22, RIGHT_W - 32)
    r.hot = link(r)
    duties.rows[i] = r
  end
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
  place.districtHot, place.partyHot = link(place.district), link(place.party)
  place.meet = Kit:Text(p, "kitSmallest", "2A1F14")
  place.meet:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -56)
  place.meet:SetWidth(RIGHT_W - 32)
  place.meet:SetMaxLines(1)
  place.meetHot = link(zone(p, 16, 54, RIGHT_W - 32, 16)) -- the council line belongs to the district
end

local function buildDecrees()
  local y = LIVE_H + VGAP + DUTY_H + VGAP + PLACE_H + VGAP
  local p = panel(body, nil, RIGHT_X, y, RIGHT_W, BODY_H - y)
  decrees = { frame = p, rows = {} }
  Kit:Label(p, "kitSection", "1B3570", 0.22, "Recent decrees"):SetPoint("TOPLEFT", p, "TOPLEFT", 2, 0)
  -- "See all" opens the Chronicle
  local seeAll = CreateFrame("Button", nil, p)
  seeAll:SetSize(70, 16)
  seeAll:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 2)
  local seeAllText = Kit:Label(seeAll, "kitTiny", "1B3570", 0.2, "See all  ›")
  seeAllText:SetPoint("RIGHT", seeAll, "RIGHT", -2, 0)
  seeAll:SetScript("OnClick", function() Page:Open("chronicle") end)
  decrees.seeAll = seeAll
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
    r.hot = link(r)
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

-- One line of text, the middle of its line lying at the middle of the board's line box (top, height h).
local function at(obj, parent, x, top, h)
  obj:ClearAllPoints()
  obj:SetPoint("LEFT", parent, "TOPLEFT", x, -(top + h / 2))
end

local function put(frame, parent, x, y, w, h)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  frame:SetSize(w, math.max(h, 1))
end

-- Who holds power, laid out as the board flows it (measured in Edge at the game's window size):
-- a column with a 12 gap inside the plate's 16 / 18 padding. Heights are the board's line boxes:
-- eyebrow 14 (10px) or 13 (9.5px), name 21 (15px) or 26 (19px), .small 18.
-- Run after the texts are set. power.geo keeps the numbers (plate coordinates) for the sim's checks;
-- power.rows are plain frames spanning each row, for the click overlays (Kit:Hot) to attach to.
local function layoutPower(data)
  local p, gov, g, rows = power.frame, power.gov, power.geo, power.rows
  at(power.title, p, PAD_X, PAD_Y, 18)

  -- The Crown
  local kings = data.crown
  local portraitsW = kings[2] and 64 or 36 -- two 36px portraits overlapping by 8, or one
  local textX = PAD_X + portraitsW + FLOW
  power.crown:SetWidth(PW - portraitsW - 2 * FLOW - 38)
  local one = math.max(1, power.crownProbe:GetStringHeight() or 1)
  local lines = math.max(1, math.min(2, math.floor((power.crown:GetStringHeight() or one) / one + 0.5)))
  local rowH = math.max(36, 14 + 21 * lines)
  local top = PAD_Y + 18 + FLOW
  local mid = top + rowH / 2
  power.k1:ClearAllPoints()
  power.k1:SetPoint("CENTER", p, "TOPLEFT", PAD_X + 18, -mid)
  power.k2:ClearAllPoints()
  power.k2:SetPoint("CENTER", p, "TOPLEFT", PAD_X + 46, -mid)
  local textTop = mid - (14 + 21 * lines) / 2
  at(power.crownEyebrow, p, textX, textTop, 14)
  if lines == 1 then
    at(power.crown, p, textX, textTop + 14, 21)
  else
    power.crown:ClearAllPoints()
    power.crown:SetPoint("TOPLEFT", p, "TOPLEFT", textX, -(textTop + 14))
  end
  power.crest:ClearAllPoints()
  power.crest:SetPoint("CENTER", p, "TOPRIGHT", -(PAD_X + 19), -mid)
  put(rows.crown, p, PAD_X, top, PW, rowH)
  local ruleY = top + rowH + FLOW
  power.rule:ClearAllPoints()
  power.rule:SetPoint("TOPLEFT", p, "TOPLEFT", PAD_X, -ruleY)
  local flow = ruleY + 1 + FLOW
  g.crownY, g.crownH, g.crownLines, g.ruleY, g.flowY = top, rowH, lines, ruleY, flow
  -- before the first election the recruiting lines take the place of the government (their first label sits 6 in)
  recruit:ClearAllPoints()
  recruit:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -(flow - 6))
  recruit:SetSize(LEFT_W, math.max(1, GRID_H - (flow - 6)))
  if not data.pm then return end

  -- The Prime Minister: a 76px portrait, the text 14 to its right, the column 70 high (14 + 4 + 26 + 4 + 22), centred
  local govH = math.max(1, GRID_H - flow)
  gov:ClearAllPoints()
  gov:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -flow)
  gov:SetSize(LEFT_W, govH)
  local tx = PAD_X + PM_DISC + 14
  at(power.pmEyebrow, gov, tx, 3, 14)
  at(power.pm, gov, tx, 21, 26)
  power.pmChip:ClearAllPoints()
  power.pmChip:SetPoint("LEFT", gov, "TOPLEFT", tx, -(51 + 11))
  power.since:ClearAllPoints()
  if power.pmChip:IsShown() then
    power.since:SetPoint("LEFT", power.pmChip, "RIGHT", 8, 0)
  else
    power.since:SetPoint("LEFT", gov, "TOPLEFT", tx, -(51 + 11))
  end
  put(rows.pm, gov, PAD_X, 0, PW, PM_DISC)

  -- The Cabinet: a sunk plate, padding 10 / 12, two columns (the labels as wide as the longest, a 14 gap), rows 18 high, 5 apart
  local cab = power.cabFrame
  local n = math.min(#data.cabinet, #power.cab)
  local cabH = 20 + 18 * n + 5 * math.max(0, n - 1)
  local cabY = PM_DISC + FLOW
  put(cab, gov, PAD_X, cabY, PW, cabH)
  local colW = 0
  for i = 1, n do colW = math.max(colW, power.cab[i].label:GetWidth() + 9.5 * 0.32) end -- CSS counts the last letter's spacing
  local nameX = 12 + colW + 14
  for i, row in ipairs(power.cab) do
    local rowTop = 10 + (i - 1) * 23
    at(row.label, cab, 12, rowTop + 5, 13) -- the labels sit on the names' baseline
    at(row.name, cab, nameX, rowTop, 18)
    row.name:SetWidth(math.max(20, PW - nameX - 12))
    local band = rows.cab[i]
    band:SetShown(i <= n)
    if i <= n then
      local from = i == 1 and 0 or rowTop - 2.5
      local to = i == n and cabH or rowTop + 18 + 2.5
      put(band, gov, PAD_X, cabY + from, PW, to - from)
    end
  end
  g.cabY, g.cabH, g.colW, g.nameX = flow + cabY, cabH, colW, nameX

  -- The Justices, small and italic under the Cabinet (not on the board; Max, 10 Nov)
  local jy = cabY + cabH + FLOW
  power.justices:ClearAllPoints()
  power.justices:SetPoint("TOPLEFT", gov, "TOPLEFT", PAD_X, -jy)
  local jh = (data.justices and data.justices ~= "") and math.max(18, power.justices:GetStringHeight() or 18) or 0
  put(rows.justices, gov, PAD_X, jy, PW, jh)
  rows.justices:SetShown(jh > 0)
  g.justicesY, g.justicesH = flow + jy, jh

  -- The Leader of the Opposition, pinned to the bottom of the plate: a 36px portrait, the label (it wraps to two
  -- lines on the board, so it does here), the name, and the chip at the right
  local opp = power.oppFrame
  local chipW = power.oppChip:IsShown() and power.oppChip:GetWidth() or 0
  local avail = PW - 36 - FLOW - (chipW > 0 and (FLOW + chipW) or 0)
  local x = 36 + FLOW
  power.oppEyebrow:SetText("Leader of the Opposition")
  local split = power.oppEyebrow:GetWidth() + 10 * 0.32 > avail
  if split then power.oppEyebrow:SetText("Leader of the") end
  power.oppEyebrow2:SetShown(split)
  local eyes = split and 2 or 1
  local oppH = math.max(36, 14 * eyes + 21)
  local natural = (jh > 0 and (jy + jh) or (cabY + cabH)) + FLOW
  local oppY = math.max(natural, govH - PAD_Y - oppH)
  put(opp, gov, PAD_X, oppY, PW, oppH)
  power.oppPortrait:ClearAllPoints()
  power.oppPortrait:SetPoint("CENTER", opp, "TOPLEFT", 18, -oppH / 2)
  local oTop = (oppH - (14 * eyes + 21)) / 2
  at(power.oppEyebrow, opp, x, oTop, 14)
  at(power.oppEyebrow2, opp, x, oTop + 14, 14)
  at(power.opp, opp, x, oTop + 14 * eyes, 21)
  power.opp:SetWidth(math.max(20, avail))
  power.oppChip:ClearAllPoints()
  power.oppChip:SetPoint("RIGHT", opp, "TOPRIGHT", 0, -oppH / 2)
  g.oppY, g.oppH, g.oppLines = flow + oppY, oppH, eyes
end

-- Keeps "In office since" inside the plate's inner right edge (PAD_X + PW from the gov column's left).
-- Needs the chip already set, so it runs after pmChip:Set in refreshPower.
local function fitSince(full)
  local start = PAD_X + PM_DISC + 14
  local shown = power.pmChip:IsShown()
  local function avail(textStart) return PAD_X + PW - textStart end
  local function startAt()
    return shown and (PAD_X + PM_DISC + 14 + (power.pmChip:GetWidth() or 0) + 8) or start
  end
  local room = avail(startAt())
  power.since:SetText(full)
  if power.since:GetStringWidth() > room then
    power.since:SetText((full:gsub("^In office since ", "Since ")))
  end
  if power.since:GetStringWidth() > room then
    power.since:SetMaxLines(1)
    power.since:SetWidth(math.max(20, room))
  else
    power.since:SetWidth(room)
  end
end

local function refreshPower()
  local T = MOTA.Throne
  local data = T:Power()
  power.previewTag:SetShown(data.preview == true)
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
    fitSince("In office since " .. date("%d %b", data.pm.since):gsub("^0", ""))
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
  layoutPower(data)
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
  aim(live.hot, e and e.page, e and e.view)
  live.dot:SetShown(e ~= nil and e.live == true)
  live.liveLabel:SetShown(e ~= nil and e.live == true)
  for key, s in pairs(live.seals) do s:SetShown(e ~= nil and key == e.key) end
  live.count:SetText(n > 1 and (liveIndex .. " of " .. n .. "  ›") or "")
  live.more:SetShown(n > 1)
  if e then
    live.title:SetText(e.title)
    live.line:SetText(e.line or "")
    live.page, live.view = e.page, e.view
    live.button:SetLabel(e.button or "Open")
  end
end

local function refreshDuties()
  local list = MOTA.Throne:Duties()
  duties.none:SetShown(#list == 0)
  for i, r in ipairs(duties.rows) do
    local d = list[i]
    r:SetShown(d ~= nil)
    aim(r.hot, d and d.page, d and d.view)
    if d then
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
  aim(place.districtHot, 6, "map")
  aim(place.meetHot, 6, "map")
  -- the party chip opens that party's page; the Crown's chip its chamber; with no party, the first party's page
  aim(place.partyHot, 4, (me and MOTA:IsCrown(me)) and "ch" or p or "sh")
end

local function refreshDecrees()
  local list = MOTA.Throne:Decrees(DECREE_ROWS)
  decrees.none:SetShown(#list == 0)
  for i, r in ipairs(decrees.rows) do
    local e = list[i]
    r:SetShown(e ~= nil)
    aim(r.hot, e and e.page, e and e.view)
    if e then
      Kit:Tint(r.gem, e.hex)
      r.text:SetText(e.text)
      r.ago:SetText(MOTA.Throne:Ago(e.t))
    end
  end
end

-- Where each part of Who holds power opens. The Crown's own chamber (Parties) is only open to a
-- Crown member, so anyone else is sent to the public Charter, the nearest page about the Crown.
local function refreshPowerLinks()
  local data = MOTA.Throne:Power()
  local L, PAGES = power.links, MOTA.Throne.PAGES
  local me = MOTA.me
  if me and MOTA:IsCrown(me) then aim(L.crown, PAGES.parties, "ch", "Opens The Parties · Crown chamber")
  else aim(L.crown, PAGES.statute, "charter", "Opens Statute Book · Charter (the Crown's powers)") end
  local pm = data.pm
  aim(L.pm, pm and PAGES.parties, pm and pm.p)
  for i, h in ipairs(L.cab) do aim(h, pm and data.cabinet[i] and PAGES.parties, pm and pm.p) end
  local jt = data.justices and data.justices ~= ""
  aim(L.justices, pm and jt and PAGES.statute, "court")
  aim(L.recruitJustices, not pm and jt and PAGES.statute, "court")
  -- the Leader of the Opposition: the other party's page
  aim(L.opp, pm and data.opposition and PAGES.parties, data.opposition and data.opposition.p)
  aim(L.recruit[1], not pm and PAGES.parties, nil)
  aim(L.recruit[2], not pm and PAGES.parties, "sh")
  aim(L.recruit[3], not pm and PAGES.parties, "ex")
end

function Page:Refresh()
  if not root or not root:IsShown() or not MOTA.guild then return end
  local b = MOTA.Throne:Banner()
  head.eyebrow:SetText(b.eyebrow:upper())
  head.plateEyebrow:SetText((b.plateEyebrow or ""):upper())
  head.plateText:SetText(b.plateText or "")
  aim(head.hot, b.page, b.view)
  refreshPower()
  refreshPowerLinks()
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
  buildPowerLinks()
  buildLive()
  buildDuties()
  buildPlace()
  buildDecrees()
  buildBar()
  Page.root, Page.scroll, Page.head, Page.live = root, scroll, head, live -- for the pretend client's checks
  Page.power, Page.recruit, Page.duties, Page.place, Page.decrees = power, recruit, duties, place, decrees
  Page.seeAll = decrees.seeAll
end

-- The Throne Room has a second view, the Chronicle (UI/ChroniclePage.lua): Page:Open("chronicle") and
-- Page:Open("state"). Choosing the tab itself always lands on the State of the Realm.
function Page:Show(show)
  if show and not self.opening then self.view = "state" end
  local chronicle = show and self.view == "chronicle"
  if self.ShowChronicle then self:ShowChronicle(chronicle) end
  if show and not chronicle and not root then build() end
  if not root then return end
  root:SetShown(show and not chronicle)
  if show and not chronicle then self:Refresh() end
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
