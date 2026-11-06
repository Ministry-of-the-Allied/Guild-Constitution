-- Ministry of the Allied: The Parties tab, following the Parties board
-- (design/canvas-source/Parties.dc.html; ADDON_SPEC.md, section 10.16).
-- The look only, for now: membership, leaders and the chamber's contents come
-- with the party data. Until then nothing here writes a record, the party
-- buttons are greyed out, and the chamber's As member view is a design preview
-- using the board's example text.

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

local root, tabs, public, member, outsider, toggle
local view, lastParty, preview = "sh", "sh", "outsider"

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

  for i, row in ipairs({ { "Whips", "None yet" }, { "Members", "None yet" }, { "Strongholds", party.home } }) do
    local rowY = 72 + (i - 1) * 22
    Kit:Label(plate, "kitTiny", "7A5719", 0.2, row[1]):SetPoint("TOPLEFT", plate, "TOPLEFT", 18, -rowY - 2)
    local value = Kit:Text(plate, "kitSmall")
    value:SetPoint("TOPLEFT", plate, "TOPLEFT", 118, -rowY)
    value:SetWidth(plateW - 130)
    value:SetMaxLines(1)
    value:SetText(row[2])
  end
  Kit:Rule(plate, plateW - 36):SetPoint("TOPLEFT", plate, "TOPLEFT", 18, -142)
  local join = Kit:Text(plate, "kitItalic", "5E4B33")
  join:SetPoint("TOPLEFT", plate, "TOPLEFT", 18, -152)
  join:SetWidth(plateW - 36)
  join:SetText("Joining costs 5 gold. Leaving another party starts a 14-day wait.")
  local ask = waiting(plate, 200, "Ask to join")
  ask:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT", 18, 18)
  v.ask = ask
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
  seal(v, "hseal_silverhand", 54):SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
  Kit:Label(v, "kitTiny", "7A5719", 0.22, "Design preview · example text"):SetPoint("TOPLEFT", v, "TOPLEFT", 66, -8)
  local title = Kit:Text(v, "kitChamber", "1B3570")
  title:SetPoint("TOPLEFT", v, "TOPLEFT", 66, -24)
  title:SetText("The Silverhand Chamber")

  notice(v, 66, leftW, 88, true, "Three-line whip · Elinor Ashby",
    "Polls close at 9:40 tonight. Seal your ballot and bring a friend to the Ballot Hall.")
  notice(v, 164, leftW, 88, false, "Campaign plan · Lady Vale",
    "When the polls close, gather on the Cathedral steps for the Crown's proclamation, win or lose.")
  notice(v, 262, leftW, 88, false, "Intelligence · Osric Hale",
    "Thorne plans to run Tomas Wren in the Cathedral Ward. Back Elinor Ashby there.")
  local post = waiting(v, 200, "Post to the chamber", "quiet")
  post:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -364)

  local x = leftW + 18
  local w = WIDTH - x
  local asking = panel(v, "plain", x, 0, w, 164)
  Kit:Label(asking, "kitSection", "1B3570", 0.22, "Asking to join"):SetPoint("TOPLEFT", asking, "TOPLEFT", 16, -14)
  local portrait = seal(asking, "portrait", 36)
  portrait:SetPoint("TOPLEFT", asking, "TOPLEFT", 16, -36)
  local initials = Kit:Text(asking, "initials", "F3D98A", "CENTER")
  initials:SetPoint("CENTER", portrait, "CENTER", 0, 0)
  initials:SetText("HB")
  local who = Kit:Text(asking, "kitName")
  who:SetPoint("TOPLEFT", asking, "TOPLEFT", 62, -36)
  who:SetText("Hal Brennick")
  local when = Kit:Text(asking, "kitSmallest", "5E4B33")
  when:SetPoint("TOPLEFT", asking, "TOPLEFT", 62, -54)
  when:SetText("Iron District · asked 2 h ago")
  waiting(asking, 100, "Admit"):SetPoint("TOPLEFT", asking, "TOPLEFT", 16, -80)
  waiting(asking, 100, "Decline", "quiet"):SetPoint("TOPLEFT", asking, "TOPLEFT", 124, -80)
  local only = Kit:Text(asking, "kitItalic", "5E4B33")
  only:SetPoint("TOPLEFT", asking, "TOPLEFT", 16, -126)
  only:SetWidth(w - 32)
  only:SetText("Only the Leader and Whips see this.")

  local floor = panel(v, "sunk", x, 176, w, 128)
  Kit:Label(floor, "kitSection", "1B3570", 0.22, "Roll of the floor"):SetPoint("TOPLEFT", floor, "TOPLEFT", 16, -14)
  local crossed = Kit:Text(floor, "kitSmall")
  crossed:SetPoint("TOPLEFT", floor, "TOPLEFT", 16, -36)
  crossed:SetWidth(w - 32)
  crossed:SetText("Elowen Marsh crossed the floor to the Exchange. Chamber access ended at once.")
  local waitLine = Kit:Text(floor, "kitSmallest", "5E4B33")
  waitLine:SetPoint("TOPLEFT", crossed, "BOTTOMLEFT", 0, -5)
  waitLine:SetWidth(w - 32)
  waitLine:SetText("No party may admit her until 17 November.")
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
  v.ask = waiting(v, 260, "Ask to join", "quiet")
  v.ask:SetPoint("TOP", v, "TOP", 0, -366)
  return v
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function toggleButton(parent, x, label, name)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(80, 30)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -3)
  b.bg = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  b.bg:SetAllPoints()
  b.label = Kit:Label(b, "kitTiny", "5E4B33", 0.06, label)
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:SetScript("OnClick", function() Page:Preview(name) end)
  return b
end

function Page:Refresh()
  if not root then return end
  for key, t in pairs(tabs) do t:SetOn(key == view) end
  public.sh:SetShown(view == "sh")
  public.ex:SetShown(view == "ex")
  local chamber = view == "ch"
  toggle:SetShown(chamber)
  member:SetShown(chamber and preview == "member")
  outsider:SetShown(chamber and preview == "outsider")
  for name, b in pairs(toggle.buttons) do
    local on = name == preview
    Kit:Gradient(b.bg, "2E58AA", "1B3570", on and 1 or 0, on and 1 or 0)
    b.label:SetColor(on and "F3D98A" or "5E4B33")
  end
  local party = PARTIES[lastParty]
  for key, s in pairs(outsider.seals) do s:SetShown(key == lastParty) end
  outsider.title:SetText(("The %s Chamber is sealed"):format(lastParty == "sh" and "Silverhand" or "Exchange"))
  outsider.ask:SetLabel("Ask to join " .. party.short)
end

function Page:Select(name)
  view = name
  if PARTIES[name] then lastParty = name end
  self:Refresh()
end

function Page:Preview(name)
  preview = name
  self:Refresh()
end

local function build()
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
  public = { sh = buildPublic("sh"), ex = buildPublic("ex") }
  member, outsider = buildMember(), buildOutsider()

  tabs = {}
  local x = 0
  for _, t in ipairs({ { "sh", 5 }, { "ex", 6 }, { "ch", 7 } }) do
    local b = Kit:Ribbon(root, t[2], function() Page:Select(t[1]) end)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", x, 0)
    x = x + b:GetWidth() + 2
    tabs[t[1]] = b
  end

  -- The board's preview switch; the real view will follow membership.
  toggle = panel(root, nil, WIDTH - 166, 0, 166, 36)
  Kit:Fill(toggle, "6E4F17", "6E4F17", 0.12)
  Kit:Outline(toggle, "6E4F17", 0.45)
  toggle.buttons = {
    member = toggleButton(toggle, 3, "As member", "member"),
    outsider = toggleButton(toggle, 83, "As outsider", "outsider"),
  }
end

function Page:Show(show)
  if show and not root then build() end
  if not root then return end
  root:SetShown(show)
  if show then self:Refresh() end
end

MOTA:Listen("PAGE_SHOWN", function(_, id) Page:Show(id == PAGE_ID) end)
