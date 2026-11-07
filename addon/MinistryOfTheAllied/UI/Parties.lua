-- Ministry of the Allied: The Parties tab, following the Parties board
-- (design/canvas-source/Parties.dc.html; ADDON_SPEC.md, section 10.16).
-- The roll is real (Party.lua). Leaders, whips and chamber notices aren't built
-- yet, so those parts say so and their buttons are greyed out.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Kit = MOTA.Kit
local Page = {}
MOTA.PartiesPage = Page

local PAGE_ID = "parties"
-- The board's page padding: 20 top, 34 left, 26 right, 22 bottom.
local PARCH = M.slots.parch
local LEFT, TOP = PARCH.x + 34, PARCH.y + 20
local WIDTH, HEIGHT = PARCH.w - 60, PARCH.h - 42
local BODY_TOP = 36 + 14
local BODY_H = HEIGHT - BODY_TOP
local BANNER_H = 128

local PARTIES = {
  sh = {
    portrait = "kitPortraitSh", banner = "kitBannerSh", seal = "hseal_silverhand", color = "1F4290", ribbon = 5,
    name = "The Silverhand", short = "the Silverhand",
    motto = "“The strength of the light is not in the one who wields it, but in all those it protects.”",
    home = "Arcane Ward, Cathedral Ward",
    pillars = {
      { "A funded commons.", "The treasury serves every citizen." },
      { "Collective raiding.", "Loot by council, by need." },
      { "Progressive taxation.", "Those who earn more give more." },
      { "Support for new citizens.", "Bags, gold and guidance." },
      { "Transparent governance.", "Every coin on the record." },
    },
  },
  ex = {
    portrait = "kitPortraitEx", banner = "kitBannerEx", seal = "hseal_exchange", color = "9E1B22", ribbon = 6,
    name = "The Azeroth Exchange", short = "the Exchange",
    motto = "“Azeroth rewards those who are bold enough to take it.”",
    home = "Iron District, Harbour Quarter",
    pillars = {
      { "Low taxation, high output.", "Citizens keep what they earn." },
      { "A free guild market.", "Trade at market rates." },
      { "Merit-based raiding.", "Slots go to those who earn them." },
      { "Elite investment.", "Back the highest output." },
      { "Lean government.", "Fewer laws, not more." },
    },
  },
}

local root, tabs, public, member, outsider, crownView
local view, lastParty = "sh", "sh"
local confirmLeave = false

local function panel(parent, kind, x, y, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  if kind then Kit:Plate(f, kind) end
  return f
end

local function hex(s) return "|cff" .. s end

-- A greyed-out button: it waits for the party data.
local function waiting(parent, width, label, style)
  local b = Kit:Button(parent, width, 36, label, style)
  b:SetEnabled(false)
  b:SetAlpha(0.45)
  return b
end

-- The join button on a party's page, and on its sealed chamber.
local function pressJoin(key)
  local Party = MOTA.Party
  local _, _, action = Party:JoinState(key)
  local rec, err
  if action == "ask" then
    rec, err = Party:Ask(key)
  elseif action == "leave" then
    if not confirmLeave then
      confirmLeave = true
      return Page:Refresh()
    end
    confirmLeave = false
    rec, err = Party:Leave()
  end
  if err then MOTA:Print(err) end
  Page:Refresh()
end

local function gold(copper)
  return MOTA:Money(copper)
end

local function namesLine(names)
  if #names == 0 then return "None yet" end
  local short = {}
  for i, n in ipairs(names) do short[i] = MOTA:Short(n) end
  return table.concat(short, ", ")
end

local function seal(parent, name, size)
  local t = UI:Piece(parent, name, "ARTWORK", nil, nil, nil, parent)
  t:ClearAllPoints()
  t:SetSize(size, size)
  return t
end

---------------------------------------------------------------------------
-- A party's public face
---------------------------------------------------------------------------

local function buildPublic(key)
  local party = PARTIES[key]
  local v = panel(root, nil, 0, BODY_TOP, WIDTH, BODY_H)

  local banner = panel(v, nil, 0, 0, WIDTH, BANNER_H)
  Kit:Art(banner, party.banner, "BACKGROUND"):SetPoint("CENTER", banner, "CENTER", 0, 0)
  Kit:Label(banner, "kitTiny", "E3D3A6", 0.32, "Awaiting the election"):SetPoint("TOPLEFT", banner, "TOPLEFT", 150, -20)
  local name = Kit:Text(banner, "heading", "F3D98A")
  name:SetPoint("TOPLEFT", banner, "TOPLEFT", 150, -36)
  name:SetText(party.name)
  local motto = Kit:Text(banner, "kitMotto", "F2ECE0")
  motto:SetPoint("TOPLEFT", banner, "TOPLEFT", 150, -76)
  motto:SetWidth(WIDTH - 172)
  motto:SetText(party.motto)

  local y = BANNER_H + 14
  local leftW = 368
  Kit:Label(v, "kitSection", "1B3570", 0.22, "What we stand for"):SetPoint("TOPLEFT", v, "TOPLEFT", 0, -y)
  for i, p in ipairs(party.pillars) do
    local row = panel(v, nil, 0, y + 22 + (i - 1) * 34, leftW, 34)
    local dots = row:CreateTexture(nil, "BORDER")
    Kit:Solid(dots, "6E4F17", 0.3)
    dots:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    dots:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    dots:SetHeight(1)
    local gem = Kit:Gem(row, party.color)
    gem:SetPoint("LEFT", row, "LEFT", 0, 0)
    local text = Kit:Text(row, "kitSmall")
    text:SetPoint("LEFT", row, "LEFT", 17, 0)
    text:SetWidth(leftW - 17)
    text:SetText(hex("2A1F14") .. p[1] .. "|r " .. hex("5E4B33") .. p[2] .. "|r")
  end

  local plateX = leftW + 20
  local plateW = WIDTH - plateX
  local plate = panel(v, "plain", plateX, y, plateW, BODY_H - y)
  local portrait = Kit:Art(plate, party.portrait)
  portrait:SetSize(57, 57) -- the art has a soft shadow round it: this makes the circle itself 44
  portrait:SetPoint("CENTER", plate, "TOPLEFT", 40, -38)
  local initials = Kit:Text(plate, "initials", "F3D98A", "CENTER")
  initials:SetPoint("CENTER", portrait, "CENTER", 0, 0)
  initials:SetText("—")
  Kit:Label(plate, "kitTiny", "7A5719", 0.2, "Party Leader"):SetPoint("TOPLEFT", plate, "TOPLEFT", 74, -20)
  local leader = Kit:Text(plate, "kitName")
  leader:SetPoint("TOPLEFT", plate, "TOPLEFT", 74, -34)
  leader:SetWidth(plateW - 90)
  leader:SetText("Not yet chosen")

  v.values = {}
  for i, row in ipairs({ { "Funds", "0g" }, { "Members", "None yet" }, { "Strongholds", party.home } }) do
    local rowY = 72 + (i - 1) * 22
    Kit:Label(plate, "kitTiny", "7A5719", 0.2, row[1]):SetPoint("TOPLEFT", plate, "TOPLEFT", 18, -rowY - 2)
    local value = Kit:Text(plate, "kitSmall")
    value:SetPoint("TOPLEFT", plate, "TOPLEFT", 130, -rowY)
    value:SetWidth(plateW - 142)
    value:SetMaxLines(1)
    value:SetText(row[2])
    v.values[row[1]] = value
  end
  Kit:Rule(plate, plateW - 36):SetPoint("TOPLEFT", plate, "TOPLEFT", 18, -142)
  local join = Kit:Text(plate, "kitItalic", "5E4B33")
  join:SetPoint("TOPLEFT", plate, "TOPLEFT", 18, -152)
  join:SetWidth(plateW - 36)
  v.joinNote = join
  v.ask = Kit:Button(plate, 220, 36, "Ask to join", "blue", function() pressJoin(key) end)
  v.ask:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT", 18, 18)
  return v
end

---------------------------------------------------------------------------
-- The Party Chamber
---------------------------------------------------------------------------

local function notice(parent, y, w, h, whip, head, body)
  local n = panel(parent, nil, 0, y, w, h)
  Kit:Fill(n, "FFFAEB", "FFFAEB", 0.4)
  Kit:Outline(n, whip and "6E1712" or "6E4F17", whip and 0.6 or 0.45)
  if whip then
    local bar = n:CreateTexture(nil, "BORDER")
    Kit:Solid(bar, "6E1712")
    bar:SetPoint("TOPLEFT", n, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", n, "BOTTOMLEFT", 0, 0)
    bar:SetWidth(4)
  end
  Kit:Label(n, "kitTiny", whip and "6E1712" or "7A5719", 0.22, head):SetPoint("TOPLEFT", n, "TOPLEFT", 16, -11)
  local text = Kit:Text(n, "kitNotice")
  text:SetPoint("TOPLEFT", n, "TOPLEFT", 16, -27)
  text:SetWidth(w - 30)
  text:SetText(body)
  return n
end

local function buildMember()
  local v = panel(root, nil, 0, BODY_TOP, WIDTH, BODY_H)
  local leftW = 375
  v.seals = {}
  for key, party in pairs(PARTIES) do
    local s = seal(v, party.seal, 54)
    s:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
    v.seals[key] = s
  end
  Kit:Label(v, "kitTiny", "7A5719", 0.22, "Members only"):SetPoint("TOPLEFT", v, "TOPLEFT", 66, -8)
  v.title = Kit:Text(v, "kitChamber", "1B3570")
  v.title:SetPoint("TOPLEFT", v, "TOPLEFT", 66, -24)

  notice(v, 66, leftW, 88, false, "Chamber business",
    "Nothing has been posted yet. Notices and the leadership contest come next.")
  local post = waiting(v, 200, "Post to the chamber", "quiet")
  post:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -168)

  local x = leftW + 18
  local w = WIDTH - x
  local roll = panel(v, "plain", x, 0, w, 200)
  Kit:Label(roll, "kitSection", "1B3570", 0.22, "The members"):SetPoint("TOPLEFT", roll, "TOPLEFT", 16, -14)
  v.members = Kit:Text(roll, "kitSmall")
  v.members:SetPoint("TOPLEFT", roll, "TOPLEFT", 16, -36)
  v.members:SetWidth(w - 32)

  local floor = panel(v, "sunk", x, 212, w, 128)
  Kit:Label(floor, "kitSection", "1B3570", 0.22, "Roll of the floor"):SetPoint("TOPLEFT", floor, "TOPLEFT", 16, -14)
  v.floor = Kit:Text(floor, "kitSmall")
  v.floor:SetPoint("TOPLEFT", floor, "TOPLEFT", 16, -36)
  v.floor:SetWidth(w - 32)
  return v
end

-- The Crown belongs to no party: its chamber ribbon is the desk where
-- requests are decided.
local CROWN_ROWS = 6
local function buildCrown()
  local v = panel(root, nil, 0, BODY_TOP, WIDTH, BODY_H)
  Kit:Label(v, "kitTiny", "7A5719", 0.22, "The Crown's desk"):SetPoint("TOPLEFT", v, "TOPLEFT", 0, -8)
  local title = Kit:Text(v, "kitChamber", "1B3570")
  title:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -24)
  title:SetText("Asking to join")
  v.empty = Kit:Text(v, "kitItalic", "5E4B33")
  v.empty:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -62)
  v.empty:SetWidth(WIDTH)
  v.empty:SetText("Nobody is waiting. The Chambers stay sealed to the Crown, which belongs to no party.")
  v.rows = {}
  for i = 1, CROWN_ROWS do
    local r = panel(v, "plain", 0, 56 + (i - 1) * 62, WIDTH, 56)
    r.name = Kit:Text(r, "kitName")
    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 16, -10)
    r.name:SetWidth(WIDTH - 260)
    r.line = Kit:Text(r, "kitSmallest", "5E4B33")
    r.line:SetPoint("TOPLEFT", r, "TOPLEFT", 16, -30)
    r.line:SetWidth(WIDTH - 260)
    r.admit = Kit:Button(r, 100, 30, "Admit", "blue", function()
      local _, err = MOTA.Party:Admit(r.who)
      if err then MOTA:Print(err) end
    end)
    r.admit:SetPoint("RIGHT", r, "RIGHT", -120, 0)
    r.decline = Kit:Button(r, 100, 30, "Decline", "quiet", function()
      local _, err = MOTA.Party:Decline(r.who)
      if err then MOTA:Print(err) end
    end)
    r.decline:SetPoint("RIGHT", r, "RIGHT", -12, 0)
    v.rows[i] = r
  end
  return v
end

local function buildOutsider()
  local v = panel(root, nil, 0, BODY_TOP, WIDTH, BODY_H)
  local env = panel(v, nil, (WIDTH - 420) / 2, 8, 420, 250)
  Kit:Art(env, "kitEnvelope", "BACKGROUND"):SetAllPoints()
  v.seals = {}
  for key, party in pairs(PARTIES) do
    local s = seal(env, party.seal, 110)
    s:SetPoint("CENTER", env, "TOPLEFT", 210, -150)
    v.seals[key] = s
  end
  v.title = Kit:Text(v, "kitAwaiting", "1B3570", "CENTER")
  v.title:SetPoint("TOP", v, "TOP", 0, -276)
  v.title:SetWidth(WIDTH)
  v.line = Kit:Text(v, "kitProse", "2A1F14", "CENTER")
  v.line:SetPoint("TOP", v.title, "BOTTOM", 0, -8)
  v.line:SetWidth(470)
  v.line:SetText("Only admitted members may break this seal. Nothing written inside is ever sent to your add-on.")
  v.ask = Kit:Button(v, 260, 36, "Ask to join", "quiet", function() pressJoin(lastParty) end)
  v.ask:SetPoint("TOP", v, "TOP", 0, -366)
  return v
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function setJoin(button, key, note)
  local label, enabled, action, text = MOTA.Party:JoinState(key)
  if action == "leave" and confirmLeave then label = "Click again to leave" end
  button:SetLabel(label)
  button:SetEnabled(enabled and true or false)
  button:SetAlpha(enabled and 1 or 0.45)
  if note then note:SetText(text or "") end
end

local function floorLine(e)
  return ("%s left %s on %s."):format(MOTA:Short(e.name), MOTA.Party.NAMES[e.p] or "a party", date("%d %b", e.t))
end

local function refreshCrown()
  local requests = MOTA.Party:Requests()
  crownView.empty:SetShown(#requests == 0)
  for i, r in ipairs(crownView.rows) do
    local q = requests[i]
    r:SetShown(q ~= nil)
    if q then
      r.who = q.name
      r.name:SetText(MOTA:Short(q.name))
      local wait = MOTA.Party:WaitUntil(q.name, q.p)
      local paid = q.paid >= MOTA.Party.FEE
      local state = wait and ("waiting until " .. date("%d %b", wait))
        or not paid and "hasn't paid yet"
        or q.confirmed and (gold(q.paid) .. " paid, confirmed in the bank log")
        or (gold(q.paid) .. " paid, open the guild bank to confirm")
      r.line:SetText(MOTA.Party.NAMES[q.p] .. " · " .. state)
      local can = paid and not wait
      r.admit:SetEnabled(can)
      r.admit:SetAlpha(can and 1 or 0.45)
    end
  end
end

function Page:Refresh()
  if not root then return end
  local Party = MOTA.Party
  for key, t in pairs(tabs) do t:SetOn(key == view) end
  public.sh:SetShown(view == "sh")
  public.ex:SetShown(view == "ex")
  local chamber = view == "ch"
  local mine = Party:Of(MOTA.me)
  local isCrown = MOTA.me ~= nil and MOTA:IsCrown(MOTA.me)
  member:SetShown(chamber and mine ~= nil)
  crownView:SetShown(chamber and isCrown and not mine)
  outsider:SetShown(chamber and not mine and not isCrown)

  for key, v in pairs(public) do
    v.values.Funds:SetText(gold(Party:Funds(key)))
    v.values.Members:SetText(namesLine(Party:Members(key)))
    setJoin(v.ask, key, v.joinNote)
  end
  if mine then
    for key, s in pairs(member.seals) do s:SetShown(key == mine) end
    member.title:SetText(("The %s Chamber"):format(mine == "sh" and "Silverhand" or "Exchange"))
    member.members:SetText(namesLine(Party:Members(mine)))
    local lines = {}
    for _, e in ipairs(Party:Roll().floor) do
      if e.p == mine then lines[#lines + 1] = floorLine(e) end
    end
    member.floor:SetText(#lines > 0 and table.concat(lines, "\n") or "Nobody has left yet.")
  end
  if isCrown then refreshCrown() end
  for key, s in pairs(outsider.seals) do s:SetShown(key == lastParty) end
  outsider.title:SetText(("The %s Chamber is sealed"):format(lastParty == "sh" and "Silverhand" or "Exchange"))
  setJoin(outsider.ask, lastParty)
end

function Page:Select(name)
  view = name
  confirmLeave = false
  if PARTIES[name] then lastParty = name end
  self:Refresh()
end

local function build()
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
  -- Each party's page is drawn in its own colours (Silverhand blue, the Exchange
  -- crimson, the Crown plum), whatever skin is worn.
  public = {
    sh = Kit:With("sh", function() return buildPublic("sh") end),
    ex = Kit:With("ex", function() return buildPublic("ex") end),
  }
  member, outsider = buildMember(), buildOutsider()
  crownView = buildCrown()

  tabs = {}
  local x = 0
  for _, t in ipairs({ { "sh", 5, "sh" }, { "ex", 6, "ex" }, { "ch", 7 } }) do
    local b = Kit:With(t[3], function() return Kit:Ribbon(root, t[2], function() Page:Select(t[1]) end) end)
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
MOTA:Listen("PARTY_CHANGED", function() Page:Refresh() end)
