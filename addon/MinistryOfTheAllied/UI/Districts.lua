-- Ministry of the Allied: the Districts tab, following the Districts board
-- (design/canvas-source/Districts.dc.html; ADDON_SPEC.md 10; Batch D3).
--   Map              the real Stormwind City map with the five districts outlined;
--                    the one picked lit (yours at first), its meeting place pinned,
--                    its facts on a plate, and "Set waypoint"
--   Regional Council one card per district with its Representative
--   Citizen Roll     every guild member: district, party, office, last seen;
--                    the Crown moves citizens from here (they place themselves on first use)
-- District colours are the districts' own (they don't follow the skin); the
-- ribbons, headings and the picked legend row follow the accent.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Kit = MOTA.Kit
local Page = {}
MOTA.DistrictsPage = Page

local PAGE_ID = "districts"
local PARCH = M.slots.parch
local LEFT, TOP = PARCH.x + 34, PARCH.y + 20
local WIDTH, HEIGHT = PARCH.w - 60, PARCH.h - 42
local HEAD_H = 50 -- the ribbons and the gap under them
local BODY_H = HEIGHT - HEAD_H
local ASIDE_W, GAP = 232, 18
local MAT = 6 -- the chart's cream mount
local CHART_W = WIDTH - ASIDE_W - GAP - 2 * MAT
local DZ = M.districts
local K = CHART_W / DZ.w -- chart units per screenshot pixel
local CHART_H = DZ.h * K
local LEGEND_H = 34
local ROW_H = 28
local ROWS = math.floor((BODY_H - 8 - ROW_H) / ROW_H)
local PARTY = { sh = { "Silverhand", "1F4290" }, ex = { "Exchange", "9E1B22" } }

local root, views, ribbons, count
local chart, looks, pin, ring, spots, legend, info
local cards, rollRows, rollEmpty, picker
local view, picked, hovered = "map", nil, nil
local first = 1

local function D() return MOTA.District end
local function districts() return MOTA.CONST.DISTRICTS end

local function frame(parent, x, y, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  return f
end

local function art(parent, name, layer, sub)
  local p = M.pieces[name]
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
  t:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
  t:SetTexCoord(p.l, p.r, p.t, p.b)
  t:SetSize(p.w * K, p.h * K)
  return t, p
end

-- Which district is at this point of the chart (screenshot pixels), if any.
-- The same test as the world map's (District.lua).
function Page:HitTest(x, y)
  return D():At(x, y)
end

local function mine()
  local d = MOTA.me and D():Of(MOTA.me)
  return d and d.code
end

---------------------------------------------------------------------------
-- The Map view
---------------------------------------------------------------------------

local function cursorOnChart()
  local clip = chart.clip
  local left, top = clip:GetLeft(), clip:GetTop()
  if not left or not top then return end
  local cx, cy = GetCursorPosition()
  local s = clip:GetEffectiveScale()
  return (cx / s - left) / K, (top - cy / s) / K
end

local function buildChart(v)
  local mount = frame(v, 0, 0, CHART_W + 2 * MAT, CHART_H + 2 * MAT)
  Kit:Fill(mount, "EADCB8", "EADCB8")
  Kit:Outline(mount, "6E4F17", 0.45, 0, 1)
  chart = frame(mount, MAT, MAT, CHART_W, CHART_H)
  local clip = CreateFrame("Button", nil, chart)
  clip:SetAllPoints()
  clip:SetClipsChildren(true)
  chart.clip = clip
  local map = clip:CreateTexture(nil, "BACKGROUND")
  local p = M.pieces.districts_map
  map:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
  map:SetTexCoord(p.l, p.r, p.t, p.b)
  map:SetAllPoints()
  Kit:Outline(chart, "6E4F17", 0.55, 0, 1)

  looks = {}
  for _, d in ipairs(districts()) do
    local l = {}
    for i, look in ipairs({ "fill", "rest", "lit" }) do
      local t, piece = art(clip, "dz_" .. d.code .. "_" .. look, "ARTWORK", i)
      t:SetPoint("TOPLEFT", clip, "TOPLEFT", piece.x * K, -piece.y * K)
      l[look] = t
    end
    looks[d.code] = l
  end
  spots = {}
  for _, d in ipairs(districts()) do
    local t, sp = art(clip, "dz_spot", "OVERLAY", 1)
    local s = DZ.spots[d.code]
    t:SetPoint("TOPLEFT", clip, "TOPLEFT", (s.x + sp.x) * K, -(s.y + sp.y) * K)
    spots[d.code] = t
  end
  ring = art(clip, "dz_ring", "OVERLAY", 2)
  local pulse = ring:CreateAnimationGroup()
  local grow = pulse:CreateAnimation("Scale")
  grow:SetScaleFrom(0.6, 0.6)
  grow:SetScaleTo(2.4, 2.4)
  grow:SetOrigin("CENTER", 0, 0)
  grow:SetDuration(2.2)
  grow:SetSmoothing("OUT")
  local fade = pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(0.9)
  fade:SetToAlpha(0)
  fade:SetDuration(2.2)
  pulse:SetLooping("REPEAT")
  ring.pulse = pulse
  pin = art(clip, "dz_pin", "OVERLAY", 3)

  clip:SetScript("OnClick", function()
    local x, y = cursorOnChart()
    local code = x and Page:HitTest(x, y)
    if code then Page:Pick(code) end
  end)
  clip:SetScript("OnUpdate", function(self)
    if not self:IsMouseOver() then
      if hovered then hovered = nil Page:PaintChart() end
      return
    end
    local x, y = cursorOnChart()
    local code = x and Page:HitTest(x, y)
    if code ~= hovered then
      hovered = code
      Page:PaintChart()
    end
  end)
  clip:SetScript("OnLeave", function()
    hovered = nil
    Page:PaintChart()
  end)
end

-- Lights the picked district, dims the rest and moves the pin to its meeting place.
function Page:PaintChart()
  if not chart then return end
  for code, l in pairs(looks) do
    local on = code == picked
    l.lit:SetShown(on)
    l.rest:SetShown(not on)
    l.rest:SetAlpha(code == hovered and 1 or 0.85)
    l.fill:SetShown(on or code == hovered)
    l.fill:SetAlpha(on and 0.1 or 0.08)
    spots[code]:SetShown(not on)
  end
  local s = picked and DZ.spots[picked]
  pin:SetShown(s ~= nil)
  ring:SetShown(s ~= nil)
  if s then
    local pp, rp = M.pieces.dz_pin, M.pieces.dz_ring
    pin:ClearAllPoints()
    pin:SetPoint("TOPLEFT", chart.clip, "TOPLEFT", (s.x + pp.x) * K, -(s.y + pp.y) * K)
    ring:ClearAllPoints()
    ring:SetPoint("TOPLEFT", chart.clip, "TOPLEFT", (s.x + rp.x) * K, -(s.y + rp.y) * K)
    ring.pulse:Play()
  else
    ring.pulse:Stop()
  end
end

-- A label and its value; the next row goes under the value (which may take two lines).
local VALUE_X = 72
local function infoRow(plate, anchor, label, first)
  local l = Kit:Label(plate, "kitTiny", "7A5719", 0.2, label)
  l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", first and 0 or -VALUE_X, -12)
  local v = Kit:Text(plate, "kitSmall", "2A1F14")
  v:SetPoint("TOPLEFT", l, "TOPLEFT", VALUE_X, 3.5)
  v:SetWidth(ASIDE_W - 32 - VALUE_X)
  v:SetMaxLines(2)
  return v
end

local function buildAside(v)
  local x = WIDTH - ASIDE_W
  legend = {}
  local list = {}
  for _, d in ipairs(districts()) do list[#list + 1] = d end
  for i = 1, #list do
    local row = CreateFrame("Button", nil, v)
    row:SetSize(ASIDE_W, LEGEND_H)
    row:SetPoint("TOPLEFT", v, "TOPLEFT", x, -(i - 1) * LEGEND_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    Kit:Gradient(row.bg, "C9A24A", "C9A24A", 0.3, 0, true)
    local line = row:CreateTexture(nil, "BORDER")
    Kit:Solid(line, "6E4F17", 0.3)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    row.gem = Kit:Gem(row, "5E4B33")
    row.gem:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name = Kit:Label(row, "bRecHead", "5E4B33", 0.12)
    row.name:SetPoint("LEFT", row, "LEFT", 28, 0)
    row.yours = Kit:Label(row, "kitTiny", "7A5719", 0.12, "Yours")
    row.yours:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    local glow = row:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 0.95, 0.7, 0.12)
    row:SetScript("OnClick", function() if row.code then Page:Pick(row.code) end end)
    legend[i] = row
  end

  local top = #list * LEGEND_H + 10
  local plate = frame(v, x, top, ASIDE_W, BODY_H - top)
  Kit:Plate(plate)
  info = { plate = plate }
  info.place = Kit:Label(plate, "kitTiny", "7A5719", 0.22)
  info.place:SetPoint("TOPLEFT", plate, "TOPLEFT", 16, -22)
  info.name = Kit:Text(plate, "kitChamber", "1B3570")
  info.name:SetPoint("TOPLEFT", plate, "TOPLEFT", 16, -40)
  info.name:SetWidth(ASIDE_W - 32)
  info.name:SetMaxLines(2) -- whole words wrap; the box is two lines tall on every card
  info.name:SetHeight(46)
  info.character = Kit:Text(plate, "kitItalic", "5E4B33")
  info.character:SetPoint("TOPLEFT", info.name, "BOTTOMLEFT", 0, -3)
  info.character:SetWidth(ASIDE_W - 32)
  info.character:SetHeight(34) -- two lines, so the rule and rows sit the same on every card
  local rule = Kit:Rule(plate, ASIDE_W - 32)
  rule:SetPoint("TOPLEFT", info.character, "BOTTOMLEFT", 0, -5)
  local anchor = CreateFrame("Frame", nil, plate)
  anchor:SetSize(1, 1)
  anchor:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, 0)
  info.meet = infoRow(plate, anchor, "Meets", true)
  info.rep = infoRow(plate, info.meet, "Rep.")
  info.count = infoRow(plate, info.rep, "Citizens")
  info.waypoint = Kit:Button(plate, ASIDE_W - 32, 28, "Set waypoint", "blue", function()
    if picked then Page:Waypoint(picked) end
  end)
  info.waypoint:SetPoint("BOTTOM", plate, "BOTTOM", 0, 14)
end

-- A map pin on the district's meeting place (the game's own user waypoint).
-- The screenshot is taken to cover the game's Stormwind City map edge to edge,
-- so its pixels turn into the map's 0 to 1 by the screenshot's size.
function Page:Waypoint(code)
  local d, s = D().byCode[code], DZ.spots[code]
  local x, y = (s.x + DZ.crop.x) / DZ.shot.w, (s.y + DZ.crop.y) / DZ.shot.h
  if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
    MOTA:Print("This game client can't place map pins.")
    return false
  end
  local ok = pcall(function()
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(MOTA.CONST.STORMWIND_MAP_ID, x, y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  end)
  if ok then
    MOTA:Print("Map pin set on " .. d.meet .. ".")
  else
    MOTA:Print("The game wouldn't place the map pin.")
  end
  self.lastWaypoint = { code = code, x = x, y = y, ok = ok }
  return ok
end

function Page:Pick(code)
  picked = code
  self:Refresh()
end

local function refreshMap()
  local you = mine()
  picked = picked or you or "CATH"
  -- the legend: yours first, then the rest in order
  local order = {}
  if you then order[1] = D().byCode[you] end
  for _, d in ipairs(districts()) do
    if d.code ~= you then order[#order + 1] = d end
  end
  local ink = MOTA:Accent().INK
  for i, row in ipairs(legend) do
    local d = order[i]
    row.code = d.code
    row.name:SetText(d.short)
    Kit:Tint(row.gem, d.color)
    local on = d.code == picked
    row.bg:SetShown(on)
    row.name:SetColor(on and ink or "5E4B33")
    row.yours:SetShown(d.code == you)
  end
  local d = D().byCode[picked]
  info.place:SetText(d.place .. (picked == you and " · your district" or ""))
  info.name:SetText(d.name)
  info.character:SetText(d.character .. ".")
  info.meet:SetText(d.meet)
  local rep = D():Rep(picked)
  info.rep:SetText(rep and MOTA:Short(rep) or "Vacant")
  local n = D():Size(picked)
  info.count:SetText(n .. (n == 1 and " citizen" or " citizens"))
  Page:PaintChart()
end

---------------------------------------------------------------------------
-- The Regional Council
---------------------------------------------------------------------------

local CARD_GAP = 12
local CARD_W = (WIDTH - 4 * CARD_GAP) / 5
local CARD_H = 158

local function chip(parent, w)
  local c = CreateFrame("Button", nil, parent)
  c:SetSize(w, 18)
  c.fill = c:CreateTexture(nil, "BACKGROUND")
  c.fill:SetAllPoints()
  Kit:Outline(c, "000000", 0.25)
  c.label = Kit:Label(c, "kitTiny", "F7EED5", 0.1)
  c.label:SetPoint("CENTER", c, "CENTER", 0, 0)
  -- Standing rule (Max, 8 Nov): a button whose words are cut short ("...") says
  -- in full what it does when hovered. hint is that full text.
  c:SetScript("OnEnter", function(self)
    if not self.hint then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.hint, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  function c:Set(text, hex, alpha, hint)
    self.hint = hint
    self.label:SetText(text)
    self.label:ClearAllPoints()
    self.label:SetPoint("CENTER", self, "CENTER", 0, 0)
    Kit:Solid(self.fill, hex, alpha or 1)
  end
  return c
end

local function buildCouncil(v)
  cards = {}
  for i, d in ipairs(districts()) do
    local c = frame(v, (i - 1) * (CARD_W + CARD_GAP), 0, CARD_W, CARD_H)
    Kit:Fill(c, "FFFAEB", "FFFAEB", 0.35)
    Kit:Outline(c, "6E4F17", 0.45)
    local band = c:CreateTexture(nil, "BORDER")
    band:SetPoint("TOPLEFT")
    band:SetPoint("TOPRIGHT")
    band:SetHeight(6)
    Kit:Solid(band, d.color)
    local portrait = UI:SkinPiece(c, "portrait", "metal", "ARTWORK", nil, nil, nil, nil, c)
    portrait:ClearAllPoints()
    portrait:SetSize(44, 44)
    portrait:SetPoint("TOP", c, "TOP", 0, -20)
    c.initials = Kit:Text(c, "initials", "F3D98A", "CENTER")
    c.initials:SetPoint("CENTER", portrait, "CENTER", 0, 0)
    c.name = Kit:Text(c, "bName13", "2A1F14", "CENTER")
    c.name:SetPoint("TOP", c, "TOP", 0, -72)
    c.name:SetWidth(CARD_W - 12)
    c.name:SetMaxLines(2)
    c.place = Kit:Label(c, "kitTiny", "7A5719", 0.2, d.short)
    c.place:SetPoint("TOP", c, "TOP", 0, -110)
    c.chip = chip(c, CARD_W - 30)
    c.chip:SetPoint("BOTTOM", c, "BOTTOM", 0, 14)
    c.code = d.code
    cards[i] = c
  end
  Page.cards = cards
  local y = CARD_H + 16
  local h = BODY_H - y
  local half = (WIDTH - 16) / 2
  local sitting = frame(v, 0, y, half, h)
  Kit:PlateArt(sitting, "kitBlue", "BACKGROUND") -- the drawn accent plate, as the Treasury coffer
  Kit:Label(sitting, "kitTiny", "C9D6F5", 0.22, "Next sitting"):SetPoint("TOPLEFT", sitting, "TOPLEFT", 16, -16)
  local when = Kit:Text(sitting, "kitName", "F3D98A")
  when:SetPoint("TOPLEFT", sitting, "TOPLEFT", 16, -34)
  when:SetText("Not yet called")
  local note = Kit:Text(sitting, "kitSmall", "C9D5F0")
  note:SetPoint("TOPLEFT", when, "BOTTOMLEFT", 0, -6)
  note:SetWidth(half - 32)
  note:SetText("The Crown calls the Council to Stormwind Keep. Sittings will be recorded here.")
  local powers = frame(v, half + 16, y, half, h)
  Kit:Plate(powers)
  Kit:Label(powers, "kitTiny", "7A5719", 0.22, "The Council's powers"):SetPoint("TOPLEFT", powers, "TOPLEFT", 16, -16)
  local text = Kit:Text(powers, "kitSmall", "2A1F14")
  text:SetPoint("TOPLEFT", powers, "TOPLEFT", 16, -34)
  text:SetWidth(half - 32)
  text:SetText("Must be consulted before a law that mainly affects one district. May petition the government, and may censure a minister by majority vote.")
end

local function initials(name) return MOTA:Initials(name) end

local function refreshCouncil()
  for _, c in ipairs(cards) do
    local rep = D():Rep(c.code)
    if rep then
      local short = MOTA:Short(rep)
      c.initials:SetText(initials(short))
      c.name:SetText(short)
      local party = PARTY[MOTA.Party:Of(rep) or ""]
      if party then c.chip:Set(party[1], party[2]) else c.chip:Set("No party", "5E4B33", 0.8) end
      c.chip:Show()
    else
      c.initials:SetText("?")
      c.name:SetText("Seat vacant")
      c.chip:Hide()
    end
  end
end

---------------------------------------------------------------------------
-- The Citizen Roll
---------------------------------------------------------------------------

local COLS = { name = 24, district = 180, party = 340, office = 450 }

local function seen(r)
  if r.online then return "Online" end
  local days = r.days
  if not days then return "—" end
  if days < 1 then return math.max(1, math.floor(days * 24 + 0.5)) .. " h" end
  if days < 2 then return "Yesterday" end
  return math.floor(days) .. " d"
end

local function buildPicker()
  picker = CreateFrame("Frame", nil, root)
  picker:SetSize(150, 5 * 22 + 8)
  picker:SetFrameLevel(root:GetFrameLevel() + 20)
  Kit:Fill(picker, "F7EED5", "EADCB8")
  Kit:Outline(picker, "6E4F17", 0.7)
  picker:EnableMouse(true)
  for i, d in ipairs(districts()) do
    local b = CreateFrame("Button", nil, picker)
    b:SetSize(142, 22)
    b:SetPoint("TOPLEFT", picker, "TOPLEFT", 4, -4 - (i - 1) * 22)
    Kit:Gem(b, d.color):SetPoint("LEFT", b, "LEFT", 4, 0)
    Kit:Label(b, "kitTiny", "2A1F14", 0.12, d.short):SetPoint("LEFT", b, "LEFT", 24, 0)
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(0.79, 0.64, 0.29, 0.3)
    b:SetScript("OnClick", function()
      local who = picker.who
      picker:Hide()
      if not who then return end
      local rec, err = D():Assign(who, d.code)
      if not rec and err then MOTA:Print(err) end
    end)
  end
  picker:Hide()
end

function Page:OpenPicker(row)
  if not picker then return end
  if picker:IsShown() and picker.who == row.who then picker:Hide() return end
  picker.who = row.who
  picker:ClearAllPoints()
  picker:SetPoint("TOPLEFT", row.district, "BOTTOMLEFT", 0, -2)
  picker:Show()
end

local function buildRoll(v)
  local sheet = frame(v, 0, 0, WIDTH, BODY_H)
  Kit:Plate(sheet, "sunk")
  local head = frame(sheet, 8, 4, WIDTH - 16, ROW_H)
  Kit:Label(head, "kitTiny", "7A5719", 0.2, "Citizen"):SetPoint("LEFT", head, "LEFT", COLS.name, 0)
  Kit:Label(head, "kitTiny", "7A5719", 0.2, "District"):SetPoint("LEFT", head, "LEFT", COLS.district, 0)
  Kit:Label(head, "kitTiny", "7A5719", 0.2, "Party"):SetPoint("LEFT", head, "LEFT", COLS.party, 0)
  Kit:Label(head, "kitTiny", "7A5719", 0.2, "Office"):SetPoint("LEFT", head, "LEFT", COLS.office, 0)
  Kit:Label(head, "kitTiny", "7A5719", 0.2, "Seen"):SetPoint("RIGHT", head, "RIGHT", -10, 0)
  local line = head:CreateTexture(nil, "BORDER")
  Kit:Solid(line, "6E4F17", 0.45)
  line:SetPoint("BOTTOMLEFT")
  line:SetPoint("BOTTOMRIGHT")
  line:SetHeight(1)
  rollRows = {}
  for i = 1, ROWS do
    local r = frame(sheet, 8, 4 + i * ROW_H, WIDTH - 16, ROW_H)
    local rule = r:CreateTexture(nil, "BORDER")
    Kit:Solid(rule, "6E4F17", 0.18)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    r.dot = r:CreateTexture(nil, "ARTWORK")
    r.dot:SetSize(8, 8)
    r.dot:SetPoint("LEFT", r, "LEFT", 8, 0)
    r.name = Kit:Text(r, "kitDuelistBold", "2A1F14")
    r.name:SetPoint("LEFT", r, "LEFT", COLS.name, 0)
    r.name:SetWidth(COLS.district - COLS.name - 8)
    r.name:SetMaxLines(1)
    r.district = chip(r, 146)
    r.district:SetPoint("LEFT", r, "LEFT", COLS.district, 0)
    r.district:SetScript("OnClick", function()
      if MOTA.me and MOTA:IsCrown(MOTA.me) and r.who then Page:OpenPicker(r) end
    end)
    r.party = Kit:Text(r, "bRow", "2A1F14")
    r.party:SetPoint("LEFT", r, "LEFT", COLS.party, 0)
    r.party:SetWidth(COLS.office - COLS.party - 8)
    r.party:SetMaxLines(1)
    r.office = Kit:Text(r, "bRow", "2A1F14")
    r.office:SetPoint("LEFT", r, "LEFT", COLS.office, 0)
    r.office:SetWidth(150)
    r.office:SetMaxLines(1)
    r.seen = Kit:Text(r, "bRow", "5E4B33", "RIGHT")
    r.seen:SetPoint("RIGHT", r, "RIGHT", -10, 0)
    r.seen:SetWidth(90)
    rollRows[i] = r
  end
  rollEmpty = Kit:Text(sheet, "kitItalic", "5E4B33", "CENTER")
  rollEmpty:SetPoint("TOP", sheet, "TOP", 0, -ROW_H - 18)
  rollEmpty:SetWidth(WIDTH - 40)
  rollEmpty:SetText("Reading the guild roll...")
  sheet:EnableMouseWheel(true)
  sheet:SetScript("OnMouseWheel", function(_, delta)
    first = math.max(1, first - delta * 3)
    if picker then picker:Hide() end
    Page:Refresh()
  end)
  buildPicker()
end

-- Everyone on the guild roster, online first, then by name.
function Page:RollList()
  local list = {}
  for name, r in pairs(MOTA.roster) do list[#list + 1] = { name = name, r = r } end
  table.sort(list, function(a, b)
    if a.r.online ~= b.r.online then return a.r.online end
    return a.name < b.name
  end)
  return list
end

local function refreshRoll()
  local list = Page:RollList()
  if first > math.max(1, #list - ROWS + 1) then first = math.max(1, #list - ROWS + 1) end
  local crown = MOTA.me and MOTA:IsCrown(MOTA.me)
  rollEmpty:SetShown(#list == 0)
  for i, row in ipairs(rollRows) do
    local e = list[first + i - 1]
    row:SetShown(e ~= nil)
    row.who = e and e.name
    if e then
      local r = e.r
      row.dot:SetColorTexture(MOTA:ClassColor(r.class))
      row.name:SetText(e.name)
      local d = D():Of(e.name)
      if d then
        row.district:Set(d.short, d.color, nil, crown and ("Move " .. e.name .. " to another district") or nil)
        row.district:Show()
      elseif crown and not MOTA:IsCrown(e.name) then
        row.district:Set("Place...", "6E4F17", 0.55, "Place " .. e.name .. " in a district")
        row.district:Show()
      else
        row.district:Hide()
      end
      local party = PARTY[MOTA.Party:Of(e.name) or ""]
      row.party:SetText(party and party[1] or (MOTA:IsCrown(e.name) and "The Crown" or "None"))
      row.party:SetTextColor(MOTA:RGB(party and "2A1F14" or "5E4B33"))
      local rank = r.rank or "Citizen"
      local rep
      for _, dd in ipairs(districts()) do
        if D():Rep(dd.code) == e.name then rep = dd.short .. " Rep." end
      end
      row.office:SetText(rep or rank)
      row.office:SetTextColor(MOTA:RGB((rep or rank ~= "Citizen") and "2A1F14" or "5E4B33"))
      row.seen:SetText(seen(r))
      row.seen:SetTextColor(MOTA:RGB(r.online and "1F6B4A" or "5E4B33"))
    end
  end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local VIEWS = { { "map", 11 }, { "council", 12 }, { "roll", 13 } }

function Page:Select(id)
  view = id
  if picker then picker:Hide() end
  self:Refresh()
end

function Page:View() return view end


function Page:Refresh()
  if not root then return end
  for _, t in ipairs(VIEWS) do
    ribbons[t[1]]:SetOn(view == t[1])
    views[t[1]]:SetShown(view == t[1])
  end
  local total = 0
  for _ in pairs(MOTA.roster) do total = total + 1 end
  count:SetText(total .. (total == 1 and " citizen" or " citizens") .. " · 5 districts")
  if view == "map" then refreshMap()
  elseif view == "council" then refreshCouncil()
  else refreshRoll() end
end

local function build()
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
  ribbons, views = {}, {}
  local x = 0
  for _, t in ipairs(VIEWS) do
    local b = Kit:Ribbon(root, t[2], function() Page:Select(t[1]) end)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", x, 0)
    x = x + b:GetWidth() + 2
    ribbons[t[1]] = b
    views[t[1]] = frame(root, 0, HEAD_H, WIDTH, BODY_H)
  end
  count = Kit:Label(root, "bEyebrow", "7A5719", 0.22)
  count:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -13)
  local mapView = views.map
  buildChart(frame(mapView, 0, 0, CHART_W + 2 * MAT, CHART_H + 2 * MAT))
  buildAside(mapView)
  buildCouncil(views.council)
  buildRoll(views.roll)
end

function Page:Show(show)
  if show and not root then build() end
  if not root then return end
  root:SetShown(show)
  if show then self:Refresh() end
end

local function refresh() if root and root:IsShown() then Page:Refresh() end end
MOTA:Listen("PAGE_SHOWN", function(_, id) Page:Show(id == PAGE_ID) end)
MOTA:Listen("DISTRICT_CHANGED", refresh)
MOTA:Listen("PARTY_CHANGED", refresh)
MOTA:Listen("SKIN_CHANGED", refresh)
