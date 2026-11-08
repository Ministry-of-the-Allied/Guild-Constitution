-- Ministry of the Allied: what the Throne Room shows (UI/ThroneRoom.lua draws it).
-- Everything here is read from the other systems; nothing is written.
--
--   Throne:Banner()   the state of the realm and the next date to count down to
--   Throne:Power()    the Crown, the government, the opposition, the Justices
--   Throne:Live()     a section for each thing on now, most urgent first
--   Throne:Duties()   my own to-do list, for any office I hold
--   Throne:Decrees()  recent public events from the book, newest first

local _, MOTA = ...
local Throne = {}
MOTA.Throne = Throne

local DAY, HOUR = 86400, 3600
local PAGES = { ballot = 2, statute = 3, parties = 4, treasury = 5, districts = 6, ring = 7 }
Throne.PAGES = PAGES
local ORDINALS = { "First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth", "Ninth", "Tenth",
  "Eleventh", "Twelfth" }
local NAMES = { sh = "Silverhand", ex = "Exchange" }

-- "3 days", "5 hours", "12 min"
function Throne:Left(seconds)
  seconds = math.max(0, seconds or 0)
  if seconds >= 2 * DAY then return math.floor(seconds / DAY + 0.5) .. " days" end
  if seconds >= 2 * HOUR then return math.floor(seconds / HOUR + 0.5) .. " hours" end
  if seconds >= HOUR then return "1 h " .. math.floor((seconds - HOUR) / 60) .. " min" end
  return math.max(1, math.floor(seconds / 60)) .. " min"
end

-- "2 h", "1 d", "18 d", as the board's decrees.
function Throne:Ago(t)
  local s = math.max(0, GetServerTime() - t)
  if s < HOUR then return math.max(1, math.floor(s / 60)) .. " m" end
  if s < DAY then return math.floor(s / HOUR) .. " h" end
  return math.floor(s / DAY) .. " d"
end

local cache = {}
local function forget() cache = {} end
MOTA:Listen("RECORD_ADDED", forget)
MOTA:Listen("GUILD_READY", forget)

local function governments()
  if cache.governments then return cache.governments end
  local n = 0
  for _, r in ipairs(MOTA.Book:Latest()) do
    local d = r.d or {}
    if r.k == "ballot.result" and d.w and (d.kind == "general" or d.kind == "snap" or d.kind == "runoff") then n = n + 1 end
  end
  cache.governments = n
  return n
end

---------------------------------------------------------------------------
-- The banner: { eyebrow, plateEyebrow, plateText }
---------------------------------------------------------------------------

function Throne:Banner()
  local El, Co = MOTA.Elect, MOTA.Contest
  local gov = El:Government()
  local now = GetServerTime()
  local out = {}
  if gov then
    local n = governments()
    local total = math.floor((gov.ends - gov.t) / DAY + 0.5)
    local day = math.min(total, math.floor((now - gov.t) / DAY) + 1)
    out.eyebrow = ("The %s Government · Day %d of %d"):format(ORDINALS[n] or (n .. "th"), day, total)
  elseif El:Begun() then
    out.eyebrow = "The first General Election"
  else
    out.eyebrow = "Recruiting · before the first election"
  end
  local cur = Co:Current()
  local ballot = MOTA.Ballot and MOTA.Ballot:Current()
  if ballot and MOTA.Ballot:Stage(ballot) == "open" then
    out.plateEyebrow, out.plateText = ballot.d.name, "Polls open"
  elseif El:Pending() and cur then
    local poll = Co:PollAt()
    out.plateEyebrow = Co:Kind()
    out.plateText = poll > now and ("In " .. self:Left(poll - now)) or "Polling day"
  elseif gov then
    out.plateEyebrow, out.plateText = "The next election", date("%d %b", gov.ends)
  else
    local g = El:Gates()
    out.plateEyebrow, out.plateText = "Recruiting", g.players .. " of " .. El.GATE_PLAYERS
  end
  return out
end

---------------------------------------------------------------------------
-- Who holds power
---------------------------------------------------------------------------

function Throne:Power()
  local El, Bench = MOTA.Elect, MOTA.Bench
  local out = { crown = MOTA:CrownMembers() }
  local gov = El:Government()
  if gov then
    out.pm = { name = gov.name, p = gov.p, since = gov.t }
    out.cabinet = {}
    for i = 2, #Bench.POSTS do
      local post = Bench.POSTS[i]
      out.cabinet[#out.cabinet + 1] = { title = Bench.TITLES[post], name = gov.p and Bench:Holder(gov.p, post) }
    end
    local opp = El:Opposition()
    local leader = opp and MOTA.Contest:Leader(opp)
    out.opposition = opp and { p = opp, name = leader and leader.name }
  else
    out.gates = El:Gates()
    out.leaders = {}
    for _, p in ipairs({ "sh", "ex" }) do
      local l = MOTA.Contest:Leader(p)
      out.leaders[p] = l and l.name
    end
  end
  out.justices = MOTA.Judiciary and MOTA.Judiciary:Line()
  return out
end

---------------------------------------------------------------------------
-- What's on: { key, title, line, live, button, page }
---------------------------------------------------------------------------

function Throne:Live()
  local out = {}
  local now = GetServerTime()
  local me = MOTA.me
  local crown = me and MOTA:IsCrown(me)
  local B, Co, NC, El = MOTA.Ballot, MOTA.Contest, MOTA.Confidence, MOTA.Elect

  local b = B and B:Current()
  if b and B:Stage(b) == "open" then
    local closes = B:CloseTime(b)
    local voted = B:MyState(b) ~= "none"
    out[#out + 1] = { key = "ballot", live = true, title = b.d.name, page = PAGES.ballot,
      line = "Polls close at " .. B:Clock(closes) .. " · " .. self:Left(closes - now) .. " left" .. (voted and " · you've voted" or ""),
      button = voted and "Open" or "Go to the ballot" }
  elseif b and B:Stage(b) == "closed" then
    out[#out + 1] = { key = "ballot", title = b.d.name, page = PAGES.ballot, button = "Open",
      line = "The polls have closed. The Crown is counting." }
  end

  if NC and NC:IsOpen() then
    local m = NC:Motion()
    local voted = NC:MyVote() ~= nil
    out[#out + 1] = { key = "nc", live = true, title = "A Vote of No Confidence", page = nil,
      line = ("%d of %d votes · %s left"):format(m.n, m.need, self:Left(m.ends - now)) .. (voted and " · you've voted" or (crown and "" or " · /mota noconfidence yes")) }
  end

  local mine = me and MOTA.Party:Of(me)
  for _, p in ipairs({ "sh", "ex" }) do
    local stage = Co:Stage(p)
    if stage == "standing" or stage == "voting" or stage == "counting" then
      local ends = Co:EndsAt(p)
      local line = Co:Banner(p)
      if stage == "voting" and mine == p and not Co:MyVote(p) and Co:Eligible(me, p) then line = line .. " · you haven't voted" end
      out[#out + 1] = { key = "contest_" .. p, live = stage == "voting", title = (Co:IsEmergency(p) and "Emergency contest · " or "Leadership contest · ") .. NAMES[p],
        line = line, page = PAGES.parties, button = "Open", ends = ends }
    end
  end

  local cur = Co:Current()
  if El:Underway() and cur and not (b and B:Stage(b) ~= "declared") then
    local poll = Co:PollAt()
    local campaign = poll - 14 * DAY
    local line
    if cur.kind ~= "snap" and now < campaign then line = "The leadership contests come first. Polling day is " .. date("%d %b", poll) .. "."
    elseif now < poll then line = "The campaign · polling day " .. date("%d %b", poll) .. ", in " .. self:Left(poll - now) .. "."
    else line = "Polling day. The Crown opens the polls in the Ballot Hall." end
    out[#out + 1] = { key = "election", title = Co:Kind(), line = line, page = PAGES.ballot, button = "Open" }
  end

  local gov = El:Government()
  if gov and gov.p and now < gov.t + El.NAME_WINDOW then
    local opp = El:Opposition()
    local open = #El:Vacant(gov.p) + (opp and #El:Vacant(opp) or 0)
    if open > 0 then
      out[#out + 1] = { key = "bench", title = "The 48 hours", page = PAGES.parties, button = "Open",
        line = "The Cabinet and shadow cabinet are being named · " .. self:Left(gov.t + El.NAME_WINDOW - now) .. " left." }
    end
  end

  local ring = MOTA.Ring and MOTA.Ring:Current()
  if ring then
    if ring.stage == "signup" then
      out[#out + 1] = { key = "ring", title = "The Ring · " .. tostring(ring.season or "a tournament"), page = PAGES.ring, button = "Open",
        line = now < (ring.closes or 0) and ("Sign-ups open · close in " .. self:Left(ring.closes - now)) or "Sign-ups closed · the draw is next" }
    elseif ring.stage == "bouts" and ring.next then
      out[#out + 1] = { key = "ring", title = "The Ring · next bout", page = PAGES.ring, button = "Open",
        line = MOTA:Short(ring.next.a) .. " v " .. MOTA:Short(ring.next.b) .. ", Old Town" }
    elseif ring.stage == "done" and ring.champion and now - (ring.lastT or 0) < 7 * DAY then
      out[#out + 1] = { key = "ring", title = "The Ring · champion", page = PAGES.ring, button = "Open",
        line = MOTA:Short(ring.champion) .. ", Gladiator of Stormwind" }
    end
  end

  if crown and MOTA.Ledger and not MOTA.Ledger:Get().open then
    out[#out + 1] = { key = "books", title = "The books are closed", page = PAGES.treasury, button = "Open",
      line = "Nothing at the bank is logged until a King opens them." }
  end
  return out
end

---------------------------------------------------------------------------
-- My duties: { text, page }
---------------------------------------------------------------------------

function Throne:Duties()
  local out = {}
  local me = MOTA.me
  if not me or not MOTA.guild then return out end
  local Co, El, Bench, Party = MOTA.Contest, MOTA.Elect, MOTA.Bench, MOTA.Party
  local function add(text, page) out[#out + 1] = { text = text, page = page } end

  if MOTA:IsCrown(me) then
    for _, p in ipairs({ "sh", "ex" }) do
      if Co:Stage(p) == "counting" and #Co:Candidates(p) > 0 then add("Ratify the " .. NAMES[p] .. " count", PAGES.parties) end
    end
    local b = MOTA.Ballot and MOTA.Ballot:Current()
    if b and MOTA.Ballot:Stage(b) == "closed" then add("Declare the result of " .. b.d.name, PAGES.ballot) end
    local n = #Party:Requests()
    if n > 0 then add(n .. (n == 1 and " citizen asks" or " citizens ask") .. " to join a party", PAGES.parties) end
    if MOTA.Ledger and not MOTA.Ledger:Get().open then add("Open the Treasury books", PAGES.treasury) end
    local cur = Co:Current()
    if cur and cur.kind ~= "snap" and not cur.openedAt and El:Underway() and Co:Stage("sh") == "none" then add("Open the leadership contests", PAGES.parties) end
    if not El:Begun() and El:Gates().ok then add("Begin the first General Election", PAGES.parties) end
    local open = b and MOTA.Ballot:Stage(b) ~= "declared"
    if El:Pending() and cur and GetServerTime() >= Co:PollAt() and not open then
      add("Polling day: open the polls for the " .. Co:Kind(), PAGES.ballot)
    end
    if MOTA.Judiciary and #MOTA.Judiciary:Justices() < MOTA.Judiciary.SEATS then
      add((MOTA.Judiciary.SEATS - #MOTA.Judiciary:Justices()) .. " seat(s) on the High Judiciary to fill (/mota justice)", PAGES.statute)
    end
  end

  local gov = El:Government()
  local mine = Party:Of(me)
  if mine and Bench:IsLeader(me, mine) then
    local vacant = El:Vacant(mine)
    if #vacant > 0 then
      local what = (gov and gov.p == mine) and "the Cabinet" or "the shadow cabinet"
      add("Name " .. what .. ": " .. table.concat(vacant, ", "), PAGES.parties)
    end
  end
  if mine and Co:Stage(mine) == "voting" and not Co:MyVote(mine) and Co:Eligible(me, mine) then
    add("Vote in your party's leadership contest", PAGES.parties)
  end
  local b = MOTA.Ballot and MOTA.Ballot:Current()
  if b and MOTA.Ballot:Stage(b) == "open" and MOTA.Ballot:MyState(b) == "none" and not MOTA:IsCrown(me) then
    add("Cast your vote in " .. b.d.name, PAGES.ballot)
  end
  if MOTA.Bank and #MOTA.Bank:Pending() > 0 then add("Give a reason for your guild bank deposit", PAGES.treasury) end
  if gov and gov.p and Bench:Holder(gov.p, "treasury") == me and MOTA.Ledger and #MOTA.Ledger:Unmatched() > 0 then
    add(#MOTA.Ledger:Unmatched() .. " bank entries without a reason", PAGES.treasury)
  end
  return out
end

---------------------------------------------------------------------------
-- Recent decrees: { text, t, hex, page }
---------------------------------------------------------------------------

local GEM = { crown = "1B3570", floor = "9E1B22", fail = "6E1712", party = "1F4290", ring = "7A5719" }

function Throne:Decrees(limit)
  limit = limit or 4
  local key = "decrees" .. limit
  if cache[key] then return cache[key] end
  local out = {}
  cache[key] = out
  for _, r in ipairs(MOTA.Book:Latest(300)) do
    local d = r.d or {}
    local e
    if r.k == "ballot.result" and d.w and type(d.cands) == "table" and d.cands[d.w] then
      e = { text = "|cff2A1F14" .. MOTA:Short(d.cands[d.w].n) .. "|r wins " .. tostring(d.name), hex = GEM.crown, page = PAGES.ballot }
    elseif r.k == "contest.result" and d.w then
      e = { text = "|cff2A1F14" .. MOTA:Short(d.w) .. "|r leads the " .. (NAMES[d.p] or "party"), hex = GEM.party, page = PAGES.parties }
    elseif r.k == "party.leave" or r.k == "party.remove" then
      local who = r.k == "party.leave" and r.a or d.v
      e = { text = "|cff2A1F14" .. MOTA:Short(who) .. "|r crossed the floor", hex = GEM.floor, page = PAGES.parties }
    elseif r.k == "nc.result" then
      e = { text = "Vote of No Confidence |cff2A1F14" .. (d.passed and "passed" or "failed") .. "|r", hex = GEM.fail }
    elseif r.k == "election.date" then
      e = { text = (d.kind == "snap" and "A |cff2A1F14Snap Election|r is called" or "A |cff2A1F14General Election|r is set for ") .. (d.kind == "snap" and "" or date("%d %b", d.at)), hex = GEM.crown, page = PAGES.parties }
    elseif r.k == "judiciary.appoint" and d.v then
      e = { text = "|cff2A1F14" .. MOTA:Short(d.v) .. "|r appointed a Justice", hex = GEM.crown, page = PAGES.statute }
    elseif r.k == "contest.emergency" then
      e = { text = "An |cff2A1F14emergency contest|r moves polling day back", hex = GEM.fail, page = PAGES.parties }
    elseif r.k == "ring.result" and d.s == 7 and d.w then
      e = { text = "|cff2A1F14" .. MOTA:Short(d.w) .. "|r is champion of the Ring", hex = GEM.ring, page = PAGES.ring }
    end
    if e then
      e.t = r.t
      out[#out + 1] = e
      if #out >= limit then break end
    end
  end
  return out
end

-- "Synced with 34 citizens · moments ago"
function Throne:Synced()
  local n = 0
  for name, p in pairs(MOTA.guild and MOTA.guild.peers or {}) do
    if MOTA.roster[name] and (p.seen or 0) >= GetServerTime() - 30 * DAY then n = n + 1 end
  end
  local last = MOTA.stats and MOTA.stats.lastReceived
  local when = (not last or GetServerTime() - last < 120) and "moments ago" or (self:Ago(last) .. " ago")
  return ("Synced with %d citizen%s · %s"):format(n, n == 1 and "" or "s", when)
end
