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
Page.showContest = {}

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
  v.bannerLabel = Kit:Label(banner, "kitTiny", "E3D3A6", 0.32, "Awaiting the election")
  v.bannerLabel:SetPoint("TOPLEFT", banner, "TOPLEFT", 150, -20)
  local name = Kit:Text(banner, "heading", "F3D98A")
  name:SetPoint("TOPLEFT", banner, "TOPLEFT", 150, -36)
  name:SetText(party.name)
  local motto = Kit:Text(banner, "kitMotto", "F2ECE0")
  motto:SetPoint("TOPLEFT", banner, "TOPLEFT", 150, -76)
  motto:SetWidth(WIDTH - 172)
  motto:SetText(party.motto)

  local y = BANNER_H + 14
  local leftW = 368
  v.standsFor = panel(v, nil, 0, y, leftW, 22 + #party.pillars * 34)
  Kit:Label(v.standsFor, "kitSection", "1B3570", 0.22, "What we stand for"):SetPoint("TOPLEFT", v.standsFor, "TOPLEFT", 0, 0)
  for i, p in ipairs(party.pillars) do
    local row = panel(v.standsFor, nil, 0, 22 + (i - 1) * 34, leftW, 34)
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

  -- The shadow cabinet, public, in two columns of three.
  local benchY = 22 + #party.pillars * 34 + 14
  Kit:Label(v.standsFor, "kitSection", "1B3570", 0.22, "Shadow cabinet"):SetPoint("TOPLEFT", v.standsFor, "TOPLEFT", 0, -benchY)
  v.bench = {}
  for i = 2, #MOTA.Bench.POSTS do
    local post = MOTA.Bench.POSTS[i]
    local col, line = (i - 2) % 2, math.floor((i - 2) / 2)
    local t = Kit:Text(v.standsFor, "kitSmall")
    t:SetPoint("TOPLEFT", v.standsFor, "TOPLEFT", col * (leftW / 2), -(benchY + 22 + line * 20))
    t:SetWidth(leftW / 2 - 8)
    t:SetMaxLines(1)
    v.bench[post] = t
  end

  -- The contest, public to the whole guild.
  v.contest = panel(v, nil, 0, y, leftW, BODY_H - y)
  v.contestTitle = Kit:Label(v.contest, "kitSection", "1B3570", 0.22, "The contest")
  v.contestTitle:SetPoint("TOPLEFT", v.contest, "TOPLEFT", 0, 0)
  v.names = {}
  for i = 1, 5 do
    local b = CreateFrame("Button", nil, v.contest)
    b:SetSize(leftW, 22)
    b:SetPoint("TOPLEFT", v.contest, "TOPLEFT", 0, -20 - (i - 1) * 22)
    b.text = Kit:Text(b, "kitSmall", "1B3570")
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b:SetScript("OnClick", function()
      Page.picked = b.name
      Page:Refresh()
    end)
    v.names[i] = b
  end
  v.detail = Kit:Text(v.contest, "kitSmall")
  v.detail:SetPoint("TOPLEFT", v.contest, "TOPLEFT", 0, -136)
  v.detail:SetWidth(leftW)
  v.switch = Kit:Button(v, 130, 22, "The contest", "quiet", function()
    Page.showContest[key] = not Page.showContest[key]
    Page:Refresh()
  end)
  v.switch:SetPoint("TOPRIGHT", v, "TOPLEFT", leftW, -(y - 3))

  local plateX = leftW + 20
  local plateW = WIDTH - plateX
  local plate = panel(v, "plain", plateX, y, plateW, BODY_H - y)
  local portrait = Kit:Art(plate, party.portrait)
  portrait:SetSize(57, 57) -- the art has a soft shadow round it: this makes the circle itself 44
  portrait:SetPoint("CENTER", plate, "TOPLEFT", 40, -38)
  local initials = Kit:Text(plate, "initials", "F3D98A", "CENTER")
  initials:SetPoint("CENTER", portrait, "CENTER", 0, 0)
  initials:SetText("—")
  v.initials = initials
  Kit:Label(plate, "kitTiny", "7A5719", 0.2, "Party Leader"):SetPoint("TOPLEFT", plate, "TOPLEFT", 74, -20)
  local leader = Kit:Text(plate, "kitName")
  leader:SetPoint("TOPLEFT", plate, "TOPLEFT", 74, -34)
  leader:SetWidth(plateW - 90)
  leader:SetText("Not yet chosen")
  v.leader = leader

  v.values = {}
  for i, row in ipairs({ { "Deputy", "Not yet named" }, { "Funds", "0g" }, { "Members", "None yet" }, { "Strongholds", party.home } }) do
    local rowY = 72 + (i - 1) * 22
    Kit:Label(plate, "kitTiny", "7A5719", 0.2, row[1]):SetPoint("TOPLEFT", plate, "TOPLEFT", 18, -rowY - 2)
    local value = Kit:Text(plate, "kitSmall")
    value:SetPoint("TOPLEFT", plate, "TOPLEFT", 130, -rowY)
    value:SetWidth(plateW - 142)
    value:SetMaxLines(1)
    value:SetText(row[2])
    v.values[row[1]] = value
  end
  Kit:Rule(plate, plateW - 36):SetPoint("TOPLEFT", plate, "TOPLEFT", 18, -164)
  local join = Kit:Text(plate, "kitItalic", "5E4B33")
  join:SetPoint("TOPLEFT", plate, "TOPLEFT", 18, -174)
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

  local stage = panel(v, "plain", 0, 66, leftW, 330)
  v.stage = stage
  v.stageHead = Kit:Label(stage, "kitSection", "1B3570", 0.22, "The contest")
  v.stageHead:SetPoint("TOPLEFT", stage, "TOPLEFT", 16, -14)
  v.stageLine = Kit:Text(stage, "kitSmall")
  v.stageLine:SetPoint("TOPLEFT", stage, "TOPLEFT", 16, -34)
  v.stageLine:SetWidth(leftW - 32)
  local function field(y, label)
    Kit:Label(stage, "kitTiny", "7A5719", 0.14, label):SetPoint("TOPLEFT", stage, "TOPLEFT", 16, -y)
    local e = CreateFrame("EditBox", nil, stage)
    e:SetSize(leftW - 32, 26)
    e:SetPoint("TOPLEFT", stage, "TOPLEFT", 16, -(y + 14))
    e:SetAutoFocus(false)
    e:SetMaxLetters(120)
    e:SetFontObject(MOTA:Font("kitSmall"))
    e:SetTextColor(MOTA:RGB("2A1F14"))
    e:SetTextInsets(7, 7, 0, 0)
    Kit:Fill(e, "FBF4E1", "F0E2BE")
    Kit:Outline(e, "6E4F17", 0.6)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
  end
  v.fields = { field(76, "Laws I campaign on"), field(124, "Laws I intend to remove"), field(172, "Proposals to the party") }
  v.standBtn = Kit:Button(stage, 200, 36, "Stand for leader", "gold", function()
    local Co = MOTA.Contest
    local standing = Co:Current() and Co:Current().parties[MOTA.Party:Of(MOTA.me)].cands[MOTA.me]
    local rec, err
    if standing then rec, err = Co:Unstand()
    else rec, err = Co:Stand(v.fields[1]:GetText(), v.fields[2]:GetText(), v.fields[3]:GetText()) end
    if err then MOTA:Print(err) end
  end)
  v.standBtn:SetPoint("BOTTOMLEFT", stage, "BOTTOMLEFT", 16, 16)
  v.votes = {}
  for i = 1, 5 do
    local r = panel(stage, nil, 16, 70 + (i - 1) * 38, leftW - 32, 34)
    r.name = Kit:Text(r, "kitName")
    r.name:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.button = Kit:Button(r, 90, 30, "Vote", "blue", function()
      local _, err = MOTA.Contest:Vote(r.who)
      if err then MOTA:Print(err) end
    end)
    r.button:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    v.votes[i] = r
  end

  local x = leftW + 18
  local w = WIDTH - x
  local roll = panel(v, "plain", x, 0, w, 112)
  Kit:Label(roll, "kitSection", "1B3570", 0.22, "The members"):SetPoint("TOPLEFT", roll, "TOPLEFT", 16, -14)
  v.members = Kit:Text(roll, "kitSmall")
  v.members:SetPoint("TOPLEFT", roll, "TOPLEFT", 16, -36)
  v.members:SetWidth(w - 32)

  -- The front bench: everyone sees it; the leader names people to it.
  local bench = panel(v, "plain", x, 122, w, 222)
  Kit:Label(bench, "kitSection", "1B3570", 0.22, "The front bench"):SetPoint("TOPLEFT", bench, "TOPLEFT", 16, -14)
  v.benchRows = {}
  for i, post in ipairs(MOTA.Bench.POSTS) do
    local r = panel(bench, nil, 16, 36 + (i - 1) * 30, w - 32, 28)
    Kit:Label(r, "kitTiny", "7A5719", 0.14, MOTA.Bench.TITLES[post]):SetPoint("LEFT", r, "LEFT", 0, 0)
    r.name = Kit:Text(r, "kitSmall")
    r.name:SetPoint("LEFT", r, "LEFT", 104, 0)
    r.name:SetWidth(w - 32 - 104 - 84)
    r.name:SetMaxLines(1)
    r.button = Kit:Button(r, 78, 24, "Name", "quiet", function() Page:Pick(post, r) end)
    r.button:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    v.benchRows[post] = r
  end

  local floor = panel(v, "sunk", x, 354, w, BODY_H - 354)
  Kit:Label(floor, "kitSection", "1B3570", 0.22, "Roll of the floor"):SetPoint("TOPLEFT", floor, "TOPLEFT", 16, -14)
  v.floor = Kit:Text(floor, "kitSmall")
  v.floor:SetPoint("TOPLEFT", floor, "TOPLEFT", 16, -36)
  v.floor:SetWidth(w - 32)
  return v
end

-- The Crown belongs to no party: its chamber ribbon is the desk where
-- requests are decided.
local CROWN_ROWS = 3
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

  local desk = panel(v, "plain", 0, 56 + CROWN_ROWS * 62 + 4, WIDTH, BODY_H - (56 + CROWN_ROWS * 62 + 4))
  Kit:Label(desk, "kitSection", "1B3570", 0.22, "The election and the contests"):SetPoint("TOPLEFT", desk, "TOPLEFT", 16, -14)
  v.electionLine = Kit:Text(desk, "kitSmall")
  v.electionLine:SetPoint("TOPLEFT", desk, "TOPLEFT", 16, -34)
  v.electionLine:SetWidth(WIDTH - 32)
  v.contestLine = Kit:Text(desk, "kitSmall")
  v.contestLine:SetPoint("TOPLEFT", desk, "TOPLEFT", 16, -56)
  v.contestLine:SetWidth(WIDTH - 32)
  local days = CreateFrame("EditBox", nil, desk)
  days:SetSize(60, 30)
  days:SetPoint("BOTTOMLEFT", desk, "BOTTOMLEFT", 16, 54)
  days:SetAutoFocus(false)
  days:SetFontObject(MOTA:Font("kitSmall"))
  days:SetTextColor(MOTA:RGB("2A1F14"))
  days:SetTextInsets(7, 7, 0, 0)
  days:SetText("28")
  Kit:Fill(days, "FBF4E1", "F0E2BE")
  Kit:Outline(days, "6E4F17", 0.6)
  days:SetScript("OnEscapePressed", days.ClearFocus)
  days:SetScript("OnEnterPressed", days.ClearFocus)
  -- Two rows, so each button has room for its label: the date and the
  -- contests on the left above, the two ratify buttons on the right below.
  local function act(point, x, y, w, label, style, fn)
    local b = Kit:Button(desk, w, 30, label, style, function()
      local _, err = fn()
      if err then MOTA:Print(err) end
    end)
    b:SetPoint(point, desk, point, x, y)
    return b
  end
  act("BOTTOMLEFT", 82, 54, 156, "Set: days away", "quiet", function() return MOTA.Contest:SetDate(days:GetText()) end)
  v.openBtn = act("BOTTOMLEFT", 244, 54, 156, "Open contests", "gold", function() return MOTA.Contest:Open() end)
  act("BOTTOMRIGHT", -16 - 194 - 8, 16, 200, "Ratify Silverhand", "blue", function() return MOTA.Contest:Ratify("sh") end)
  act("BOTTOMRIGHT", -16, 16, 194, "Ratify Exchange", "blue", function() return MOTA.Contest:Ratify("ex") end)
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

local function refreshContest(key, v)
  local Co = MOTA.Contest
  local stage = Co:Stage(key)
  v.bannerLabel:SetText(Co:Banner(key))
  local leader = Co:Leader(key)
  v.leader:SetText(leader and MOTA:Short(leader.name) or "Not yet chosen")
  v.initials:SetText(leader and MOTA:Short(leader.name):sub(1, 2) or "—")
  local cands = Co:Candidates(key)
  local active = stage ~= "none" or leader ~= nil
  v.switch:SetShown(active)
  Page.showContest = Page.showContest or {}
  local showing = active and Page.showContest[key]
  v.switch:SetLabel(showing and "What we stand for" or (leader and stage == "done" and "Current platform" or "The contest"))
  v.standsFor:SetShown(not showing)
  v.contest:SetShown(showing and true or false)
  if not showing then return end
  v.contestTitle:SetText(stage == "done" and "Current platform" or "The contest")
  for i, b in ipairs(v.names) do
    local c = stage ~= "done" and cands[i]
    b:SetShown(c and true or false)
    if c then
      b.name = c.name
      b.text:SetText((Page.picked == c.name and "> " or "") .. MOTA:Short(c.name))
    end
  end
  local picked
  for _, c in ipairs(cands) do if c.name == Page.picked then picked = c end end
  picked = picked or cands[1]
  local function platform(c)
    return ("|cff7A5719Campaigning on:|r %s\n|cff7A5719Will remove:|r %s\n|cff7A5719Proposals:|r %s"):format(
      c.on ~= "" and c.on or "—", c.off ~= "" and c.off or "—", c.prop ~= "" and c.prop or "—")
  end
  if stage == "done" and leader then
    local lines = { platform(leader), "" }
    local counts = {}
    for _, cand in pairs(leader.votes) do counts[cand] = (counts[cand] or 0) + 1 end
    for cand, n in pairs(counts) do lines[#lines + 1] = MOTA:Short(cand) .. ": " .. n end
    local voters = {}
    for voter, cand in pairs(leader.votes) do voters[#voters + 1] = MOTA:Short(voter) .. " for " .. MOTA:Short(cand) end
    table.sort(voters)
    lines[#lines + 1] = table.concat(voters, ", ")
    v.detail:ClearAllPoints()
    v.detail:SetPoint("TOPLEFT", v.contest, "TOPLEFT", 0, -22)
    v.detail:SetText(table.concat(lines, "\n"))
  else
    v.detail:ClearAllPoints()
    v.detail:SetPoint("TOPLEFT", v.contest, "TOPLEFT", 0, -136)
    v.detail:SetText(picked and platform(picked) or "Nobody has stood yet.")
  end
end

local function refreshStage(mine)
  local Co = MOTA.Contest
  local stage = Co:Stage(mine)
  local cur = Co:Current()
  local me = MOTA.me
  local standing = cur and cur.parties[mine].cands[me]
  local ok, why = Co:Eligible(me, mine)
  local standOpen = stage == "standing"
  for _, e in ipairs(member.fields) do e:SetShown(standOpen and not standing and ok) end
  member.standBtn:SetShown(standOpen and ok)
  member.standBtn:SetLabel(standing and "Drop out" or "Stand for leader")
  local voteOpen = stage == "voting"
  local cands = Co:Candidates(mine)
  local myVote = Co:MyVote(mine)
  for i, r in ipairs(member.votes) do
    local c = voteOpen and cands[i]
    r:SetShown(c and true or false)
    if c then
      r.who = c.name
      r.name:SetText(MOTA:Short(c.name) .. (myVote and myVote.cand == c.name and " (your vote)" or ""))
      r.button:SetShown(not myVote and ok)
    end
  end
  local line
  if not cur then line = "No election has been called yet."
  elseif stage == "none" then line = "The election is on " .. date("%d %b", cur.at) .. ". Contests open 28 days before it."
  elseif stage == "standing" then line = ok and (standing and "You are standing. Your platform is public on your party's page." or "Stand, and tell the guild where you stand. It's all public.") or why
  elseif stage == "voting" then line = not ok and why or (myVote and (myVote.delivered and "Your vote has reached the Crown." or "Your vote is held until a King comes online.") or "Choose your leader. Your vote can't be changed, and is published after the count.")
  elseif stage == "counting" then line = "The Crown is counting."
  else line = "The contest is over. The results are on your party's page." end
  member.stageLine:SetText(MOTA.Contest:Banner(mine) .. "\n" .. line)
end

local function refreshCrown()
  local Co = MOTA.Contest
  local cur = Co:Current()
  crownView.electionLine:SetText(cur and ("The election is on " .. date("%d %b %Y", cur.at) .. ".") or "No election has been called. Enter how many days away, at least 28.")
  local function state(p)
    local counts, _, total = Co:Count(p)
    local bits = {}
    for name, n in pairs(counts) do bits[#bits + 1] = MOTA:Short(name) .. " " .. n end
    table.sort(bits)
    return Co:Stage(p) .. (#bits > 0 and (": " .. table.concat(bits, ", ")) or "")
  end
  crownView.contestLine:SetText("Silverhand · " .. state("sh") .. "\nExchange · " .. state("ex"))
  crownView.openBtn:SetShown(cur ~= nil and not cur.openedAt)
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

-- The leader's list of members to name to a post.
local picker
function Page:Pick(post, row)
  local p = MOTA.Party:Of(MOTA.me)
  if not p then return end
  if not picker then
    picker = CreateFrame("Frame", nil, root)
    picker:SetFrameStrata("DIALOG")
    picker:SetSize(190, 40)
    Kit:Fill(picker, "FBF4E1", "F0E2BE")
    Kit:Outline(picker, "6E4F17", 0.7)
    picker:EnableMouse(true)
    picker.buttons = {}
  end
  if picker:IsShown() and picker.post == post then picker:Hide() return end
  picker.post = post
  local names = {}
  local Bench = MOTA.Bench
  for _, name in ipairs(MOTA.Party:Members(p)) do
    if not Bench:IsLeader(name, p) then names[#names + 1] = name end
  end
  local choices = {}
  for _, name in ipairs(names) do choices[#choices + 1] = { label = MOTA:Short(name), v = name } end
  if Bench:Holder(p, post) then choices[#choices + 1] = { label = "Leave it empty", v = false } end
  if #choices == 0 then
    MOTA:Print("Nobody else is in your party yet.")
    return
  end
  for i, c in ipairs(choices) do
    local b = picker.buttons[i]
    if not b then
      b = Kit:Button(picker, 174, 24, "", "quiet", function(self)
        picker:Hide()
        local _, err = MOTA.Bench:Name(picker.post, self.v or nil)
        if err then MOTA:Print(err) end
      end)
      picker.buttons[i] = b
    end
    b.v = c.v
    b:SetLabel(c.label)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", picker, "TOPLEFT", 8, -8 - (i - 1) * 28)
    b:Show()
  end
  for i = #choices + 1, #picker.buttons do picker.buttons[i]:Hide() end
  picker:SetHeight(16 + #choices * 28 - 4)
  picker:ClearAllPoints()
  picker:SetPoint("TOPRIGHT", row.button, "BOTTOMRIGHT", 0, -2)
  picker:Show()
end

local function refreshBench(p, v, rows)
  local Bench = MOTA.Bench
  local leads = MOTA.me and Bench:IsLeader(MOTA.me, p)
  for post, r in pairs(rows) do
    local who = Bench:Holder(p, post)
    if r.SetText then
      r:SetText(hex("7A5719") .. Bench.TITLES[post] .. "|r  " .. (who and MOTA:Short(who) or hex("8A7A5E") .. "vacant|r"))
    else
      r.name:SetText(who and MOTA:Short(who) or (hex("8A7A5E") .. "Vacant|r"))
      r.button:SetShown(leads and true or false)
      r.button:SetLabel(who and "Change" or "Name")
    end
  end
  if picker and not leads then picker:Hide() end
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
    local deputy = MOTA.Bench:Holder(key, "deputy")
    v.values.Deputy:SetText(deputy and MOTA:Short(deputy) or "Not yet named")
    refreshBench(key, v, v.bench)
    v.values.Funds:SetText(gold(Party:Funds(key)))
    v.values.Members:SetText(namesLine(Party:Members(key)))
    setJoin(v.ask, key, v.joinNote)
    refreshContest(key, v)
  end
  if mine then
    for key, s in pairs(member.seals) do s:SetShown(key == mine) end
    member.title:SetText(("The %s Chamber"):format(mine == "sh" and "Silverhand" or "Exchange"))
    member.members:SetText(namesLine(Party:Members(mine)))
    refreshStage(mine)
    refreshBench(mine, member, member.benchRows)
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
MOTA:Listen("CONTEST_CHANGED", function() Page:Refresh() end)
