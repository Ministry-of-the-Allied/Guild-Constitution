-- Ministry of the Allied: the election date and party leadership contests
-- (ADDON_SPEC.md, section 10.16). Candidates and platforms are public records.
-- Votes go by hidden whisper to the Kings, and are published with the result.
--
--   election.date    Crown   { at }                  the latest stands
--   contest.open     Crown   { id }                  the ceremony; the system opens it anyway after 2 days
--   contest.advance  Crown   { id, stage, p? }       moves on early: "voting" or "counting"
--                                                    (with p, only that party's emergency contest)
--   contest.stand    member  { id, p, on, off, prop }  standing, with a platform
--   contest.unstand  member  { id, p }               dropping out
--   contest.runoff   Crown   { id, p, a, b }         a tie: 48 hours between those tied
--   contest.result   Crown   { id, p, w, votes }     the first for a party stands
--   contest.emergency Crown  { id, p }               Charter 3.6: polling day moves back 14
--                                                    days while that party holds a new contest
--
-- An emergency contest is called (by the Crown's add-on, or /mota contest
-- emergency) when a party's contest ends with no leader: nobody stood, or the
-- leader and Deputy have both left before polling day. Once per election
-- (decided 2026-11-08). It runs 4 days standing and 7 voting from the call.
--
--   LV <id> <round> <p> <candidate>   WHISPER  a vote, to each online King
--   LR <id> <round> <p>               WHISPER  a King's receipt
--   LF <id> <round> <p> <voter> <candidate>  WHISPER  a King passing a vote to the other

local _, MOTA = ...
local Contest = {}
MOTA.Contest = Contest

local DAY = 86400
Contest.MIN_DAYS = 28
local OPEN_BEFORE, AUTO_BEFORE = 28 * DAY, 26 * DAY
local STAND, VOTE, RUNOFF = 4 * DAY, 7 * DAY, 2 * DAY
Contest.DELAY = 14 * DAY
Contest.JOIN_WAIT = 14 * DAY
local KEYS = { "sh", "ex" }
local SEALS = { sh = "silverhand", ex = "exchange" }

local Comm, Book = MOTA.Comm, MOTA.Book
local rules = Book.rules
local function crown(author) return MOTA:IsCrown(author) end
for _, k in ipairs({ "election.date", "contest.open", "contest.advance", "contest.runoff", "contest.result", "contest.emergency" }) do
  rules[k] = crown
end
rules["contest.stand"] = function() return true end
rules["contest.unstand"] = function() return true end

local cache
local clock

local function newParty()
  return { cands = {}, round = 1 }
end

local function build()
  local out = { leaders = {}, past = 0 }
  local list = Book:Latest()
  local cur
  for i = #list, 1, -1 do
    local r = list[i]
    local d = r.d or {}
    if r.k == "election.date" and type(d.at) == "number" then
      cur = { id = r.a .. "#" .. r.n, at = d.at, parties = { sh = newParty(), ex = newParty() } }
      out.cur = cur
    elseif cur and d.id == cur.id then
      local p = d.p and cur.parties[d.p]
      if r.k == "contest.open" then
        cur.openedAt = cur.openedAt or r.t
      elseif r.k == "contest.advance" then
        local clk = (p and p.emOpen) and p or (not d.p and cur)
        if clk and d.stage == "voting" then clk.voteAt = clk.voteAt or r.t
        elseif clk and d.stage == "counting" then clk.countAt = clk.countAt or r.t end
      elseif p and r.k == "contest.emergency" and not cur.emergency then
        cur.emergency = { p = d.p, t = r.t }
        p.cands, p.round, p.among, p.runEnd, p.result = {}, 3, nil, nil, nil
        p.emOpen = r.t
      elseif p and r.k == "contest.stand" then
        if MOTA.Party:Of(r.a) == d.p and not p.cands[r.a] then
          p.cands[r.a] = { name = r.a, on = d.on, off = d.off, prop = d.prop, t = r.t }
        end
      elseif p and r.k == "contest.unstand" then
        p.cands[r.a] = nil
      elseif p and r.k == "contest.runoff" and not p.result then
        p.round, p.among, p.runEnd = p.round + 1, { [d.a] = true, [d.b] = true }, r.t + RUNOFF
      elseif p and r.k == "contest.result" and not p.result then
        p.result = { w = d.w, votes = d.votes or {}, t = r.t }
        local c = p.cands[d.w]
        out.leaders[d.p] = { name = d.w, on = c and c.on, off = c and c.off, prop = c and c.prop, t = r.t, votes = d.votes or {} }
        out.past = out.past + 1
      end
    end
  end
  return out
end

function Contest:Get()
  if not cache then cache = build() end
  return cache
end

function Contest:Current() return self:Get().cur end

-- The leader, while still a member of the party.
-- If they've left, the Deputy they named leads instead (Bench.lua).
function Contest:Leader(p)
  if MOTA.Bench then return MOTA.Bench:Leader(p) end
  local l = self:Get().leaders[p]
  if l and MOTA.Party:Of(l.name) == p then return l end
end

local function openAt(cur)
  return cur.openedAt or (cur.at - AUTO_BEFORE)
end

-- When a party's contest opens, voting starts and counting starts.
-- An emergency contest keeps its own clock, from when it was called.
function clock(cur, party)
  if party.emOpen then
    local voteAt = party.voteAt or (party.emOpen + STAND)
    return party.emOpen, voteAt, party.countAt or (voteAt + VOTE)
  end
  local open = openAt(cur)
  if cur.voteAt and cur.voteAt < open then open = cur.voteAt end
  local voteAt = cur.voteAt or (open + STAND)
  return open, voteAt, cur.countAt or (voteAt + VOTE)
end

-- none, standing, voting, counting or done, for one party.
function Contest:Stage(p)
  local cur = self:Current()
  if not cur then return "none" end
  local party = cur.parties[p]
  if party.result then return "done" end
  local now = GetServerTime()
  local open, voteAt, countAt = clock(cur, party)
  if now < open then return "none" end
  if now < voteAt then return "standing" end
  if party.runEnd then return now < party.runEnd and "voting" or "counting" end
  if now < countAt then return "voting" end
  return "counting"
end

-- When the current stage ends, if it does by the clock.
function Contest:EndsAt(p)
  local cur, stage = self:Current(), self:Stage(p)
  if not cur then return nil end
  local party = cur.parties[p]
  local _, voteAt, countAt = clock(cur, party)
  if stage == "standing" then return voteAt end
  if stage == "voting" then return party.runEnd or countAt end
end

-- Polling day, moved back 14 days by an emergency contest.
function Contest:PollAt()
  local cur = self:Current()
  if not cur then return nil end
  return cur.at + (cur.emergency and self.DELAY or 0)
end

function Contest:IsEmergency(p)
  local cur = self:Current()
  return cur ~= nil and cur.emergency ~= nil and cur.emergency.p == p
end

-- Charter 3.6: has this party's contest ended with no leader, in time to try again?
function Contest:Failed(p)
  local cur = self:Current()
  if not cur or cur.emergency then return false end
  local now = GetServerTime()
  if now < openAt(cur) or now >= cur.at then return false end
  local stage = self:Stage(p)
  if stage == "done" then return self:Leader(p) == nil end
  if stage == "counting" then return #self:Candidates(p) == 0 end
  return false
end

function Contest:CallEmergency(p)
  local cur = self:Current()
  if not MOTA:IsCrown(MOTA.me) then return nil, "Only the King and the Crown can call an emergency contest." end
  if not cur then return nil, "No election has been called." end
  if p ~= "sh" and p ~= "ex" then return nil, "Name the party: sh or ex." end
  if cur.emergency then return nil, "This election has had its emergency contest already (Charter 3.6)." end
  if GetServerTime() >= cur.at then return nil, "Polling day has come." end
  if self:Leader(p) then return nil, "That party has a leader." end
  local stage = self:Stage(p)
  if stage ~= "done" and stage ~= "counting" then return nil, "Wait until its contest has ended." end
  return Book:Write("contest.emergency", { id = cur.id, p = p })
end

function Contest:Candidates(p)
  local cur, out = self:Current(), {}
  if not cur then return out end
  local party = cur.parties[p]
  for name, c in pairs(party.cands) do
    if MOTA.Party:Of(name) == p and (not party.among or party.among[name]) then out[#out + 1] = c end
  end
  table.sort(out, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return a.name < b.name
  end)
  return out
end

-- Members who joined 14 days before the contest opened, except in the first contest.
function Contest:Eligible(name, p)
  if MOTA.Party:Of(name) ~= p then return false, "Only members of the party can take part." end
  local data = self:Get()
  if data.past == 0 and not data.leaders[p] then
    local hadOne = false
    for _ in pairs(data.leaders) do hadOne = true end
    if not hadOne then return true end
  end
  local cur = data.cur
  local joined = MOTA.Party:Roll().joined[name]
  if cur and joined and joined > openAt(cur) - self.JOIN_WAIT then
    return false, "You must join 14 days before a contest opens."
  end
  return true
end

---------------------------------------------------------------------------
-- The Crown's actions
---------------------------------------------------------------------------

function Contest:SetDate(days)
  days = tonumber(days)
  if not days or days < self.MIN_DAYS then
    return nil, ("The election must be at least %d days away, for the timetable to fit."):format(self.MIN_DAYS)
  end
  return Book:Write("election.date", { at = GetServerTime() + math.floor(days * DAY) })
end

function Contest:Open()
  local cur = self:Current()
  if not cur then return nil, "Set the election date first." end
  if cur.openedAt then return nil, "The contests are already open." end
  if GetServerTime() < cur.at - OPEN_BEFORE then return nil, "Contests open 28 days before the election." end
  return Book:Write("contest.open", { id = cur.id })
end

-- Moves both contests on early; mainly for testing.
function Contest:Advance()
  local cur = self:Current()
  if not cur then return nil, "Set the election date first." end
  local em = cur.emergency and cur.emergency.p
  if em and self:Stage(em) ~= "done" then
    local s = self:Stage(em)
    if s == "none" or s == "standing" then return Book:Write("contest.advance", { id = cur.id, stage = "voting", p = em }) end
    if s == "voting" then return Book:Write("contest.advance", { id = cur.id, stage = "counting", p = em }) end
    return nil, "The emergency contest is counting. Ratify it."
  end
  local stage = self:Stage("sh")
  if stage == "done" then stage = self:Stage("ex") end
  if stage == "none" or stage == "standing" then return Book:Write("contest.advance", { id = cur.id, stage = "voting" }) end
  if stage == "voting" then return Book:Write("contest.advance", { id = cur.id, stage = "counting" }) end
  return nil, "There's nothing to move on."
end

local function tally(id, round, p)
  local db = MOTA.db.contestTally or {}
  return db[id .. "|" .. round .. "|" .. p] or {}
end

function Contest:Count(p)
  local cur = self:Current()
  local counts, votes, total = {}, {}, 0
  if not cur then return counts, votes, 0 end
  local party = cur.parties[p]
  for _, c in ipairs(self:Candidates(p)) do counts[c.name] = 0 end
  for voter, cand in pairs(tally(cur.id, party.round, p)) do
    if counts[cand] and MOTA.Party:Of(voter) == p then
      counts[cand] = counts[cand] + 1
      votes[voter] = cand
      total = total + 1
    end
  end
  return counts, votes, total
end

-- Ratifies the count. A first tie goes to a run-off; a second needs a King's
-- public /roll, whose winner is named here.
function Contest:Ratify(p, chosen)
  local cur = self:Current()
  if not MOTA:IsCrown(MOTA.me) then return nil, "Only the King and the Crown can ratify a count." end
  if not cur then return nil, "No election has been called, so there is nothing to ratify." end
  if self:Stage(p) ~= "counting" then return nil, "That contest isn't ready to count." end
  local cands = self:Candidates(p)
  if #cands == 0 then return nil, "Nobody stood in that contest." end
  local counts, votes = self:Count(p)
  local top, tied = -1, {}
  for _, c in ipairs(cands) do
    local n = counts[c.name]
    if n > top then top, tied = n, { c.name } elseif n == top then tied[#tied + 1] = c.name end
  end
  if #tied > 1 and not chosen then
    if cur.parties[p].round % 2 == 1 then
      return Book:Write("contest.runoff", { id = cur.id, p = p, a = tied[1], b = tied[2] })
    end
    return nil, "It's tied again. Roll publicly in guild chat, then /mota contest declare " .. p .. " <name>."
  end
  local winner = tied[1]
  if chosen then
    local ok = false
    for _, name in ipairs(tied) do ok = ok or name == chosen end
    if not ok then return nil, "They aren't among those tied." end
    winner = chosen
  end
  return Book:Write("contest.result", { id = cur.id, p = p, w = winner, votes = votes })
end

---------------------------------------------------------------------------
-- A member's actions
---------------------------------------------------------------------------

function Contest:Stand(on, off, prop)
  local p = MOTA.Party:Of(MOTA.me)
  local cur = self:Current()
  if not p or not cur then return nil, "Only party members can stand." end
  if self:Stage(p) ~= "standing" then return nil, "Standing isn't open." end
  local ok, why = self:Eligible(MOTA.me, p)
  if not ok then return nil, why end
  if cur.parties[p].cands[MOTA.me] then return nil, "You're already standing." end
  return Book:Write("contest.stand", { id = cur.id, p = p, on = (on or ""):sub(1, 120), off = (off or ""):sub(1, 120), prop = (prop or ""):sub(1, 120) })
end

function Contest:Unstand()
  local p = MOTA.Party:Of(MOTA.me)
  local cur = self:Current()
  if not p or not cur or self:Stage(p) ~= "standing" then return nil, "You can't drop out now." end
  return Book:Write("contest.unstand", { id = cur.id, p = p })
end

local function myVotes()
  MOTA.db.contestVotes = MOTA.db.contestVotes or {}
  return MOTA.db.contestVotes
end

local function kingsOnline()
  local out = {}
  for _, name in ipairs(MOTA:CrownMembers()) do
    if not MOTA:IsMe(name) and MOTA.Hello.heard[name] and MOTA:IsOnline(name) then out[#out + 1] = name end
  end
  return out
end

function Contest:MyVote(p)
  local cur = self:Current()
  if not cur then return nil end
  return myVotes()[cur.id .. "|" .. cur.parties[p].round .. "|" .. p .. "|" .. MOTA.me]
end

local function deliver(key, v)
  for _, king in ipairs(kingsOnline()) do
    Comm:Send(Comm:Pack("LV", v.id, v.round, v.p, v.cand), "WHISPER", king)
  end
end

function Contest:Vote(cand)
  local p = MOTA.Party:Of(MOTA.me)
  local cur = self:Current()
  if not p or not cur then return nil, "Only party members can vote." end
  if self:Stage(p) ~= "voting" then return nil, "Voting isn't open." end
  local ok, why = self:Eligible(MOTA.me, p)
  if not ok then return nil, why end
  if self:MyVote(p) then return nil, "You've already voted, and a vote can't be changed." end
  local found = false
  for _, c in ipairs(self:Candidates(p)) do found = found or c.name == cand end
  if not found then return nil, "They aren't standing." end
  local round = cur.parties[p].round
  local v = { id = cur.id, round = round, p = p, cand = cand }
  myVotes()[cur.id .. "|" .. round .. "|" .. p .. "|" .. MOTA.me] = v
  deliver(nil, v)
  MOTA:Fire("CONTEST_CHANGED")
  return true
end

local function record(id, round, p, voter, cand)
  MOTA.db.contestTally = MOTA.db.contestTally or {}
  local key = id .. "|" .. round .. "|" .. p
  local t = MOTA.db.contestTally[key] or {}
  MOTA.db.contestTally[key] = t
  if t[voter] then return false end -- the first vote stands
  t[voter] = cand
  MOTA:Fire("CONTEST_CHANGED")
  return true
end

Comm:Handle("LV", function(self, sender, channel, f)
  if channel ~= "WHISPER" or not self:IsCrown(self.me) then return end
  local id, round, p, cand = f[1], tonumber(f[2]), f[3], f[4]
  local cur = Contest:Current()
  if not cur or cur.id ~= id or not cur.parties[p] or not Contest:Eligible(sender, p) then return end
  if record(id, round, p, sender, cand) then
    for _, king in ipairs(kingsOnline()) do
      Comm:Send(Comm:Pack("LF", id, round, p, sender, cand), "WHISPER", king)
    end
  end
  Comm:Send(Comm:Pack("LR", id, round, p), "WHISPER", sender)
end)

Comm:Handle("LR", function(self, sender, channel, f)
  if channel ~= "WHISPER" or not self:IsCrown(sender) then return end
  local v = myVotes()[f[1] .. "|" .. f[2] .. "|" .. f[3] .. "|" .. self.me]
  if v and not v.delivered then
    v.delivered = true
    self:Fire("CONTEST_CHANGED")
  end
end)

Comm:Handle("LF", function(self, sender, channel, f)
  if channel ~= "WHISPER" or not self:IsCrown(sender) or not self:IsCrown(self.me) then return end
  record(f[1], tonumber(f[2]), f[3], f[4], f[5])
end)

-- Someone came online: a King gets any held votes; Kings share their tallies.
MOTA:Listen("HELLO_HEARD", function(self, name)
  if not self:IsCrown(name) or not self.db then return end
  for key, v in pairs(myVotes()) do
    if not v.delivered and key:sub(-#self.me) == self.me then
      Comm:Send(Comm:Pack("LV", v.id, v.round, v.p, v.cand), "WHISPER", name)
    end
  end
  if self:IsCrown(self.me) then
    for key, t in pairs(self.db.contestTally or {}) do
      local id, round, p = key:match("^(.-)|(%d+)|(%a+)$")
      for voter, cand in pairs(t) do
        Comm:Send(Comm:Pack("LF", id, round, p, voter, cand), "WHISPER", name, "bulk")
      end
    end
  end
end)

---------------------------------------------------------------------------
-- What the pages say, and the heralds
---------------------------------------------------------------------------

function Contest:Banner(p)
  local stage = self:Stage(p)
  local ends = self:EndsAt(p)
  local left = ends and math.max(1, math.ceil((ends - GetServerTime()) / DAY))
  local days = left and (left .. (left == 1 and " day" or " days")) or ""
  local kind = self:IsEmergency(p) and "Emergency contest" or "Leadership contest"
  if stage == "standing" then return kind .. " · standing closes in " .. days end
  if stage == "voting" then
    local run = self:Current().parties[p].runEnd ~= nil
    return (run and "Run-off · voting closes in " or (kind .. " · voting closes in ")) .. days
  end
  if stage == "counting" then return kind .. " · the Crown is counting" end
  local leader = self:Leader(p)
  if leader then return "Led by " .. MOTA:Short(leader.name) end
  if stage == "done" then return "No leader · the election goes ahead without one" end
  return "Awaiting the election"
end

local function herald(h)
  if MOTA.Herald and not Book.replaying then MOTA.Herald:Announce(h) end
end

local function changed()
  cache = nil
  MOTA:Fire("CONTEST_CHANGED")
end
MOTA:Listen("GUILD_READY", changed)
MOTA:Listen("PARTY_CHANGED", changed)

MOTA:Listen("RECORD_ADDED", function(self, rec)
  if not rec.k:find("^contest%.") and rec.k ~= "election.date" then return end
  changed()
  local d = rec.d or {}
  if rec.k == "contest.open" then
    herald({ seal = "crown", eyebrow = "By the Crown", title = "The contests are open",
      text = "Party members may now stand for leader.", button = { label = "Open", style = "blue", page = 4 } })
  elseif rec.k == "contest.stand" then
    herald({ seal = SEALS[d.p] or "official", eyebrow = "Leadership contest", title = self:Short(rec.a) .. " stands",
      text = "A candidate for leader of " .. (self.Party.NAMES[d.p] or "a party") .. ".", button = { label = "Read it", style = "quiet", page = 4 } })
  elseif rec.k == "contest.runoff" then
    herald({ seal = SEALS[d.p] or "official", eyebrow = "A tie", title = "A run-off is called",
      text = self:Short(d.a) .. " and " .. self:Short(d.b) .. " face 48 hours more voting.", button = { label = "Open", style = "blue", page = 4 } })
  elseif rec.k == "contest.emergency" then
    local name = self.Party.NAMES[d.p] or "a party"
    herald({ seal = SEALS[d.p] or "official", eyebrow = "Charter 3.6", title = "Polling day moves back 14 days",
      text = name:sub(1, 1):upper() .. name:sub(2) .. " has no leader, so it holds an emergency contest. Polling day is now " .. date("%d %b", Contest:PollAt()) .. ".",
      button = { label = "Open", style = "blue", page = 4 } })
  elseif rec.k == "contest.result" then
    herald({ seal = SEALS[d.p] or "official", eyebrow = "Inaugurated by the Crown", title = self:Short(d.w) .. " leads",
      text = "Leader of " .. (self.Party.NAMES[d.p] or "a party") .. ". The votes are published.", button = { label = "Read it", style = "quiet", page = 4 } })
  end
end)

-- A Crown copy calls the emergency contest itself, after a short random wait
-- so two Kings online don't both write it. The first record stands anyway.
local calling
local function checkEmergency()
  local self = MOTA
  if calling or not self.guild or not self.me or not self:IsCrown(self.me) or Book.replaying then return end
  for _, p in ipairs(KEYS) do
    if Contest:Failed(p) then
      calling = true
      C_Timer.After(2 + math.random() * 6, function()
        calling = false
        if Contest:Failed(p) then
          local rec = Contest:CallEmergency(p)
          if rec then self:Print("Called an emergency contest for", self.Party.NAMES[p] .. ": polling day moves back 14 days (Charter 3.6).") end
        end
      end)
      return
    end
  end
end
Contest.CheckEmergency = checkEmergency
MOTA:Listen("CONTEST_CHANGED", function() checkEmergency() end)
MOTA:Listen("PARTY_CHANGED", function() C_Timer.After(0, checkEmergency) end)

-- Reminders: the Kings until they've opened the contests, voters until they've voted.
local function remind()
  local self = MOTA
  if not self.guild or not self.me then return end
  checkEmergency()
  local cur = Contest:Current()
  if not cur then return end
  local now = GetServerTime()
  if self:IsCrown(self.me) and not cur.openedAt and now >= cur.at - OPEN_BEFORE and now < cur.at - AUTO_BEFORE then
    self:Print("The leadership contests are ready for the Crown to open, on the Chamber ribbon of The Parties.")
  end
  local p = self.Party:Of(self.me)
  if p and Contest:Stage(p) == "voting" and not Contest:MyVote(p) and Contest:Eligible(self.me, p) then
    local ends = Contest:EndsAt(p)
    self:Print("You haven't voted in your party's leadership contest yet. See the Chamber on The Parties.")
    if ends and ends - now < 2 * DAY then
      herald({ seal = SEALS[p], eyebrow = "The last 48 hours", title = "Your vote is waiting",
        text = "Voting in your party's contest closes soon.", button = { label = "Vote now", style = "blue", page = 4 } })
    end
  end
end
MOTA:Listen("GUILD_READY", function()
  C_Timer.After(12, remind)
  if not Contest.reminding then
    Contest.reminding = true
    C_Timer.NewTicker(1800, remind)
  end
end)
