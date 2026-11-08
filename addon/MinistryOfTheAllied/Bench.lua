-- Ministry of the Allied: each party's front bench (Charter 3.2, version 1.3).
-- The leader names a Deputy Leader and a shadow cabinet, one member to each post.
-- If the leader leaves the party, the Deputy becomes leader without a vote.
--
--   party.post   the leader   { p, post, v }   names v to a post; no v leaves it empty
--
-- Worked out from the book of records, oldest first. A new leader from a
-- contest starts with an empty bench, as a new Prime Minister names their own
-- Cabinet (Charter 2.2).

local _, MOTA = ...
local Bench = {}
MOTA.Bench = Bench

-- The posts follow the Cabinet in Charter 2.2, less Justice: the Crown appoints
-- the Minister of Justice (Duncan, 2026-11-08; the Charter's wording is to follow).
-- Games runs the guild's games, hunts and draws (Duncan, 2026-11-08; Charter 1.4 draft).
Bench.POSTS = { "deputy", "treasury", "war", "trade", "recruitment", "games" }
Bench.TITLES = {
  deputy = "Deputy Leader",
  treasury = "Treasury",
  war = "War",
  trade = "Trade",
  recruitment = "Recruitment",
  games = "Games",
}
local VALID = {}
for _, post in ipairs(Bench.POSTS) do VALID[post] = true end

local cache

-- When someone stopped being a member of p, counting from a time they were one.
-- math.huge if they still are, without a break.
local function goneAt(name, p, since)
  local Party = MOTA.Party
  if Party:Of(name) == p and (Party:Joined(name) or 0) <= since then return math.huge end
  local left = Party:Left(name)
  if left and left.t >= since then return left.t end
  return since
end

local function build()
  local out = { sh = { posts = {} }, ex = { posts = {} } }
  local elected = MOTA.Contest:Get().leaders -- latest result per party
  local list = MOTA.Book:Latest()
  local events = {}
  for i = #list, 1, -1 do
    local r = list[i]
    local d = r.d or {}
    if (r.k == "contest.result" or r.k == "party.post") and out[d.p] then
      events[#events + 1] = r
    end
  end

  -- If the leader has gone by time t, the Deputy steps up (once per vacancy).
  local function settle(b, p, t)
    while b.leader and goneAt(b.leader, p, b.since) <= t do
      local at = goneAt(b.leader, p, b.since)
      local deputy = b.posts.deputy
      b.posts.deputy = nil
      if deputy and goneAt(deputy, p, b.postedAt.deputy or 0) > at then
        b.leader, b.since, b.succeeded = deputy, at, true
        -- They can't hold a shadow post as well as lead.
        for post, who in pairs(b.posts) do if who == deputy then b.posts[post] = nil end end
      else
        b.leader, b.since, b.succeeded = nil, nil, nil
      end
    end
  end

  for _, r in ipairs(events) do
    local d = r.d
    local b = out[d.p]
    settle(b, d.p, r.t)
    if r.k == "contest.result" then
      b.leader, b.since, b.succeeded = d.w, r.t, nil
      b.posts, b.postedAt = {}, {}
    elseif r.k == "party.post" and r.a == b.leader and VALID[d.post] then
      b.postedAt = b.postedAt or {}
      if d.v and d.v ~= b.leader then
        for post, who in pairs(b.posts) do if who == d.v then b.posts[post] = nil end end
        b.posts[d.post] = d.v
        b.postedAt[d.post] = r.t
      else
        b.posts[d.post] = nil
      end
    end
  end
  for p, b in pairs(out) do
    b.postedAt = b.postedAt or {}
    settle(b, p, GetServerTime())
    b.elected = elected[p]
  end
  return out
end

local function get()
  if not cache then cache = build() end
  return cache
end

-- The party's leader now: { name, succeeded = true if the Deputy stepped up,
-- plus the platform and votes when they won the contest themselves }.
function Bench:Leader(p)
  local b = get()[p]
  if not b or not b.leader then return nil end
  local e = b.elected
  if not b.succeeded and e and e.name == b.leader then return e end
  return { name = b.leader, succeeded = true, t = b.since, votes = {} }
end

-- Who holds a post, while they're still in the party.
function Bench:Holder(p, post)
  local b = get()[p]
  local who = b and b.posts[post]
  if who and MOTA.Party:Of(who) == p then return who end
end

function Bench:IsLeader(name, p)
  local l = self:Leader(p)
  return l ~= nil and l.name == name
end

-- The leader names someone to a post, or leaves it empty (name nil).
function Bench:Name(post, name)
  local p = MOTA.Party:Of(MOTA.me)
  if not p or not self:IsLeader(MOTA.me, p) then return nil, "Only your party's leader names the front bench." end
  if not VALID[post] then return nil, "There's no such post." end
  if name then
    if name == MOTA.me then return nil, "You lead the party already." end
    if MOTA.Party:Of(name) ~= p then return nil, MOTA:Short(name) .. " isn't a member of your party." end
    if MOTA.Judiciary and MOTA.Judiciary:IsJustice(name) then return nil, MOTA:Short(name) .. " sits as a Justice, and may hold no other office." end
    if self:Holder(p, post) == name then return nil, MOTA:Short(name) .. " already holds that post." end
  elseif not self:Holder(p, post) then
    return nil, "That post is already empty."
  end
  return MOTA.Book:Write("party.post", { p = p, post = post, v = name })
end

MOTA.Book.rules["party.post"] = function(author, rec)
  local d = rec.d or {}
  return (d.p == "sh" or d.p == "ex") and VALID[d.post] and Bench:IsLeader(author, d.p)
end

local SEALS = { sh = "silverhand", ex = "exchange" }

-- Leaders already known, so a Deputy stepping up is announced once.
local seen

local function checkSuccession(quiet)
  local first = seen == nil
  seen = seen or {}
  for _, p in ipairs({ "sh", "ex" }) do
    local now = Bench:Leader(p)
    local name = now and now.name or false
    if not first and not quiet and now and now.succeeded and seen[p] ~= name and MOTA.Herald then
      MOTA.Herald:Announce({ seal = SEALS[p], eyebrow = "The front bench",
        title = MOTA:Short(name) .. " takes the lead",
        text = "The Deputy becomes leader of " .. MOTA.Party.NAMES[p] .. ", without a vote (Charter 3.2).",
        button = { label = "Open", style = "blue", page = 4 } })
    end
    seen[p] = name
  end
end

local function changed()
  cache = nil
end
MOTA:Listen("GUILD_READY", function()
  cache, seen = nil, nil
  C_Timer.After(15, function() checkSuccession(true) end)
end)
MOTA:Listen("PARTY_CHANGED", changed)
MOTA:Listen("CONTEST_CHANGED", changed)
MOTA:Listen("CAUGHT_UP", function() cache = nil; if seen then checkSuccession(true) end end)
MOTA:Listen("RECORD_ADDED", function(self, rec)
  if rec.k == "party.leave" or rec.k == "party.remove" or rec.k == "contest.result" then
    cache = nil
    if seen then checkSuccession(self.Book.replaying) end
    return
  end
  if rec.k ~= "party.post" then return end
  cache = nil
  self:Fire("PARTY_CHANGED")
  local d = rec.d or {}
  if self.Book.replaying or not self.Herald or not d.v then return end
  -- A herald for the guild when a Deputy is named; a note to anyone named to a post.
  if d.post == "deputy" then
    self.Herald:Announce({ seal = SEALS[d.p] or "official", eyebrow = "The front bench",
      title = self:Short(d.v) .. " is named Deputy",
      text = "Deputy Leader of " .. (self.Party.NAMES[d.p] or "a party") .. ", named by " .. self:Short(rec.a) .. ".",
      button = { label = "Dismiss", style = "quiet" } })
  elseif d.v == self.me then
    self:Print(self:Short(rec.a), "has named you to the shadow cabinet:", Bench.TITLES[d.post] .. ".")
  end
end)
