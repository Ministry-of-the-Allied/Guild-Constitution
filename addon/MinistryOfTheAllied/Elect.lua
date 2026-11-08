-- Ministry of the Allied: the election cycle (Charter 2.3, 3.3, 3.5; decided
-- with Duncan 2026-11-08).
--
--   Recruitment  No election until the guild has 20 active players with the
--                add-on (seen in the last 14 days) and each party has 6 members.
--                Then the Crown begins the first election: polling day 28 days on,
--                leadership contests first, the 14-day campaign after.
--   Government   A General or Snap Election's declared winner is Prime Minister
--                from the result. The term runs three calendar months; a Crown
--                copy then sets the next General Election for the term's end.
--   48 hours     The Prime Minister names the Cabinet and the Leader of the
--                Opposition the shadow cabinet, on the front bench (Bench.lua).
--                After that, empty posts stay empty until named; reminders go on.
--   Snap         The Crown dissolves the government or calls a Snap Election:
--                polling day 14 days on, campaign only, no leadership contests.
--
-- Records: election.date { at, kind = "general" | "snap" } (Contest.lua) and
-- ballot.result (Ballot.lua). Nothing new is written here.

local _, MOTA = ...
local Elect = {}
MOTA.Elect = Elect

local DAY = 86400
Elect.GATE_PLAYERS = 20
Elect.GATE_PARTY = 6
Elect.ACTIVE_DAYS = 14
Elect.FIRST_DAYS = 28
Elect.SNAP_DAYS = 14
Elect.TERM_MONTHS = 3
Elect.NAME_WINDOW = 48 * 3600
local KEYS = { "sh", "ex" }
local SEALS = { sh = "silverhand", ex = "exchange" }

local function monthDays(y, m)
  if m == 2 and y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0) then return 29 end
  return ({ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 })[m]
end

-- The same day n calendar months later (the month's last day if it's shorter).
function Elect:AddMonths(t, n)
  local c = date("*t", t)
  local y, m, diff = c.year, c.month, 0
  for _ = 1, n do
    diff = diff + monthDays(y, m)
    m = m + 1
    if m > 12 then m, y = 1, y + 1 end
  end
  local last = monthDays(y, m)
  if c.day > last then diff = diff - (c.day - last) end
  return t + diff * DAY
end

---------------------------------------------------------------------------
-- Who's active, and the gates
---------------------------------------------------------------------------

-- Answers worked out from the whole book are kept until a record arrives or
-- the roster changes, so the pages don't re-read the book on every redraw.
local cache = {}
local function forget() cache = {} end
MOTA:Listen("RECORD_ADDED", forget)
MOTA:Listen("GUILD_READY", forget)
MOTA:Listen("ROSTER_UPDATED", forget)
MOTA:Listen("HELLO_HEARD", function() cache.players = nil end)

-- Guild members whose add-on has spoken, or written a record, in the last 14 days.
-- Kept for a minute, as people come and go by the clock too.
function Elect:ActivePlayers()
  local now = GetServerTime()
  if cache.players and now - cache.playersAt < 60 then return cache.players end
  cache.players, cache.playersAt = self:CountActive(), now
  return cache.players
end

function Elect:CountActive()
  local since = GetServerTime() - self.ACTIVE_DAYS * DAY
  local seen = {}
  if MOTA.me then seen[MOTA.me] = true end
  for name, p in pairs(MOTA.guild and MOTA.guild.peers or {}) do
    if (p.seen or 0) >= since then seen[name] = true end
  end
  for _, r in ipairs(MOTA.Book:Latest()) do
    if r.t < since then break end
    seen[r.a] = true
  end
  local n = 0
  for name in pairs(seen) do
    if MOTA.roster[name] then n = n + 1 end
  end
  return n
end

-- { players, sh, ex, ok }
function Elect:Gates()
  local g = { players = self:ActivePlayers(), sh = #MOTA.Party:Members("sh"), ex = #MOTA.Party:Members("ex") }
  g.ok = g.players >= self.GATE_PLAYERS and g.sh >= self.GATE_PARTY and g.ex >= self.GATE_PARTY
  return g
end

---------------------------------------------------------------------------
-- The government
---------------------------------------------------------------------------

local GOVERNS = { general = true, snap = true, runoff = true }

-- The latest declared winner: { name, p, t, ends, kind }, or nil before the first.
function Elect:Government()
  if cache.gov == nil then cache.gov = self:FindGovernment() or false end
  return cache.gov or nil
end

function Elect:FindGovernment()
  for _, r in ipairs(MOTA.Book:Latest()) do
    local d = r.d or {}
    if r.k == "ballot.result" and GOVERNS[d.kind] and d.w and type(d.cands) == "table" and d.cands[d.w] then
      local c = d.cands[d.w]
      local p = (c.p == "sh" or c.p == "ex") and c.p or nil
      -- The ballot names candidates by hand: find the member that name means.
      local name = c.n
      for full in pairs(MOTA.roster) do
        if full == c.n or MOTA:Short(full) == c.n then name = full end
      end
      return { name = name, p = p, t = r.t, kind = d.kind,
        ends = self:AddMonths(r.t, self.TERM_MONTHS) }
    end
  end
end

-- The party in opposition: the other of the two, when one governs.
function Elect:Opposition()
  local gov = self:Government()
  if not gov or not gov.p then return nil end
  return gov.p == "sh" and "ex" or "sh"
end

function Elect:Begun()
  return MOTA.Contest:Current() ~= nil or self:Government() ~= nil
end

-- Has an election been called (or set for the term's end) and not yet declared?
function Elect:Pending()
  local cur = MOTA.Contest:Current()
  if not cur then return false end
  local gov = self:Government()
  return not gov or gov.t < cur.t
end

-- Is it under way: a snap or the first election from the call, a General
-- Election from 28 days before polling day, when its contests open.
function Elect:Underway()
  if not self:Pending() then return false end
  local cur = MOTA.Contest:Current()
  if cur.kind == "snap" or not self:Government() then return true end
  return GetServerTime() >= cur.at - self.FIRST_DAYS * DAY
end

-- "Cabinet" for the governing party, "Shadow cabinet" for the other.
function Elect:BenchName(p)
  local gov = self:Government()
  return (gov and gov.p == p) and "The Cabinet" or "Shadow cabinet"
end

---------------------------------------------------------------------------
-- The Crown's actions
---------------------------------------------------------------------------

function Elect:BeginFirst()
  if not MOTA:IsCrown(MOTA.me) then return nil, "Only the King and the Crown can call an election." end
  if self:Begun() then return nil, "The election cycle has already begun." end
  local g = self:Gates()
  if not g.ok then
    return nil, ("Not yet: %d of %d active players, the Silverhand %d of %d, the Exchange %d of %d."):format(
      g.players, self.GATE_PLAYERS, g.sh, self.GATE_PARTY, g.ex, self.GATE_PARTY)
  end
  return MOTA.Book:Write("election.date", { at = GetServerTime() + self.FIRST_DAYS * DAY, kind = "general" })
end

-- Dissolution and a Snap Election are the same act for the add-on.
function Elect:CallSnap()
  if not MOTA:IsCrown(MOTA.me) then return nil, "Only the King and the Crown can call a Snap Election." end
  if not self:Government() then return nil, "There's no government to dissolve yet." end
  if self:Underway() then return nil, "An election is already under way." end
  return MOTA.Book:Write("election.date", { at = GetServerTime() + self.SNAP_DAYS * DAY, kind = "snap" })
end

-- After a result, a Crown copy sets the next General Election for the term's end.
local scheduling
local function scheduleNext()
  if scheduling or not MOTA.me or not MOTA:IsCrown(MOTA.me) or MOTA.Book.replaying then return end
  local gov = Elect:Government()
  if not gov or Elect:Pending() then return end
  local cur = MOTA.Contest:Current()
  if cur and cur.t > gov.t then return end
  scheduling = true
  C_Timer.After(2 + math.random() * 6, function()
    scheduling = false
    local g = Elect:Government()
    local c = MOTA.Contest:Current()
    if g and not (c and c.t > g.t) then
      MOTA.Book:Write("election.date", { at = g.ends, kind = "general" })
    end
  end)
end
Elect.ScheduleNext = scheduleNext

---------------------------------------------------------------------------
-- Reminders and heralds
---------------------------------------------------------------------------

-- The posts a leader still has to fill, for the 48 hours after a result.
function Elect:Vacant(p)
  local out = {}
  for _, post in ipairs(MOTA.Bench.POSTS) do
    if not MOTA.Bench:Holder(p, post) then out[#out + 1] = MOTA.Bench.TITLES[post] end
  end
  return out
end

local nagged = {}
local function remind()
  local self = MOTA
  if not self.guild or not self.me then return end
  scheduleNext()
  local gov = Elect:Government()
  if not gov or not gov.p then return end
  for _, p in ipairs(KEYS) do
    if self.Bench:IsLeader(self.me, p) then
      local vacant = Elect:Vacant(p)
      if #vacant > 0 then
        local what = p == gov.p and "your Cabinet" or "your shadow cabinet"
        local left = gov.t + Elect.NAME_WINDOW - GetServerTime()
        if left > 0 then
          local hours = math.max(1, math.ceil(left / 3600))
          self:Print("Name " .. what .. ": " .. hours .. " hours left. Still empty: " .. table.concat(vacant, ", ") .. ". See the Chamber on The Parties.")
          if not nagged[gov.t] and self.Herald then
            nagged[gov.t] = true
            self.Herald:Announce({ seal = SEALS[p], eyebrow = "The 48 hours", title = p == gov.p and "Name your Cabinet" or "Name your shadow cabinet",
              text = hours .. " hours left to fill the front bench. Posts left empty stay empty until named.",
              button = { label = "Open", style = "blue", page = 4 } })
          end
        else
          self:Print("Posts still empty in " .. what .. ": " .. table.concat(vacant, ", ") .. ". Name them in the Chamber on The Parties.")
        end
      end
    end
  end
end
Elect.Remind = remind

-- The Crown, once, when the gates first open.
local function gateCheck()
  local self = MOTA
  if not self.guild or not self.me or not self:IsCrown(self.me) or Elect:Begun() then return end
  if Elect:Gates().ok and not self.guild.gatesHeralded and self.Herald then
    self.guild.gatesHeralded = true
    self.Herald:Announce({ seal = "crown", eyebrow = "By the Crown", title = "The guild is ready to vote",
      text = "Enough players and party members for the first General Election. Begin it on the Crown's desk.",
      button = { label = "Open", style = "blue", page = 4 } })
  end
end

MOTA:Listen("GUILD_READY", function()
  C_Timer.After(20, function() remind(); gateCheck() end)
  if not Elect.ticking then
    Elect.ticking = true
    C_Timer.NewTicker(1800, function() remind(); gateCheck() end)
  end
end)
MOTA:Listen("PARTY_CHANGED", function() C_Timer.After(0, gateCheck) end)

MOTA:Listen("RECORD_ADDED", function(self, rec)
  local d = rec.d or {}
  if rec.k == "ballot.result" then
    C_Timer.After(1, function() scheduleNext() end)
    if not self.Book.replaying then C_Timer.After(3, remind) end
    return
  end
  if rec.k ~= "election.date" or self.Book.replaying or not self.Herald then return end
  local gov = Elect:Government()
  if d.kind == "snap" then
    self.Herald:Announce({ seal = "crown", eyebrow = "By the Crown", title = "A Snap Election is called",
      text = "Polling day is " .. date("%d %b", d.at) .. ". A 14-day campaign, with no leadership contests.",
      button = { label = "Open", style = "blue", page = 4 } })
  elseif not gov then
    self.Herald:Announce({ seal = "crown", eyebrow = "By the Crown", title = "The first General Election",
      text = "Polling day is " .. date("%d %b", d.at) .. ". The leadership contests open first.",
      button = { label = "Open", style = "blue", page = 4 } })
  end
end)
