-- Ministry of the Allied: catching up (ADDON_SPEC.md, section 7).
-- Records someone missed while offline reach them from any member who holds them.
--
--   SY <summary>      GUILD    for each author, { the number up to which I hold every
--                              record, then any numbers held beyond a gap }
--   CO <name>         GUILD    "I'm sending to this member", so the others stand down
--   CU <records>      WHISPER  the missing records, packed, on the slow queue
--
-- Passed-on records are taken straight away, under the usual permission rules
-- (decided 2026-11-07). The guild is small, and the risk of a modified add-on
-- forging a record is accepted. A record the rules refuse is noted, so nobody
-- asks for it again. Old records raise no heralds.
--
-- Records come author by author, so one may arrive before the records that
-- allow it (a hunt from the Minister of Games before the result and the
-- appointment that made them minister). A refused record is kept aside and
-- tried again after every batch, and taken once the rules allow it.

local _, MOTA = ...
local Sync = {}
MOTA.Sync = Sync

local Comm, Book = MOTA.Comm, MOTA.Book

local OFFER_MIN, OFFER_SPREAD = 1, 4 -- seconds to wait before offering, at random
local MAX_OFFER = 120                -- records per offer; the next summary brings the rest
local CHUNK = 25                     -- records per message, halved if still too long
local ASK_GAP = 30                   -- seconds between summaries sent because someone has more
local FIRST_DELAY = 10               -- seconds after the guild is known

local offers = {} -- [name] = true while waiting to send to them
local lastSummary = 0

-- The number up to which every record is held (or was refused). Going by this
-- rather than the highest number means gaps get filled as well.
function Sync:Upto(author)
  local g = MOTA.guild
  local list = g.records[author] or {}
  local refused = g.refused and g.refused[author] or {}
  local n = 0
  while list[n + 1] or refused[n + 1] do n = n + 1 end
  return n
end

function Sync:Summary()
  local out = {}
  for author, list in pairs(MOTA.guild.records) do
    local upto = self:Upto(author)
    local entry = { upto }
    -- Records beyond a gap are listed, or they'd be sent again every time.
    -- A gap can be permanent: a reset loses records nobody else ever held.
    local beyond = {}
    for n in pairs(list) do
      if n > upto then beyond[#beyond + 1] = n end
    end
    table.sort(beyond)
    for _, n in ipairs(beyond) do entry[#entry + 1] = n end
    if upto > 0 or #beyond > 0 then out[author] = entry end
  end
  return out
end

function Sync:Send()
  if not MOTA.guild or not next(MOTA.roster) then return false end
  lastSummary = GetServerTime()
  Comm:Send(Comm:Pack("SY", Comm:Encode(self:Summary(), true)), "GUILD", nil, "bulk")
  return true
end

-- Everything I hold that a summary doesn't cover, oldest first per author.
function Sync:Missing(theirs)
  local out = {}
  for author, list in pairs(MOTA.guild.records) do
    local entry = theirs[author]
    local from, held = entry and entry.upto or 0, entry and entry.held or {}
    local numbers = {}
    for n in pairs(list) do
      if n > from and not held[n] then numbers[#numbers + 1] = n end
    end
    table.sort(numbers)
    for _, n in ipairs(numbers) do
      if #out >= MAX_OFFER then return out end
      local r = list[n]
      out[#out + 1] = { a = author, n = n, t = r.t, k = r.k, d = r.d or {} }
    end
  end
  return out
end

local function sendChunk(records, first, last, target)
  local part = {}
  for i = first, last do part[#part + 1] = records[i] end
  local msg = Comm:Pack("CU", Comm:Encode(part, true))
  if #msg <= Comm.MAX_LEN or first == last then
    Comm:Send(msg, "WHISPER", target, "bulk")
  else
    local mid = math.floor((first + last) / 2)
    sendChunk(records, first, mid, target)
    sendChunk(records, mid + 1, last, target)
  end
end

function Sync:Offer(target, theirs)
  if not offers[target] or not MOTA.guild then return end
  offers[target] = nil
  local records = self:Missing(theirs)
  if #records == 0 then return end
  Comm:Send(Comm:Pack("CO", target), "GUILD", nil, "bulk")
  for first = 1, #records, CHUNK do
    sendChunk(records, first, math.min(first + CHUNK - 1, #records), target)
  end
end

-- Takes passed-on records. Returns how many were new.
-- Records refused so far are tried again: one taken may allow another.
function Sync:Retry()
  local g = MOTA.guild
  if not g or not g.waiting then return 0 end
  local added, again = 0, true
  while again do
    again = false
    for author, list in pairs(g.waiting) do
      for n, rec in pairs(list) do
        if Book:Allowed(rec) then
          list[n] = nil
          if g.refused and g.refused[author] then g.refused[author][n] = nil end
          if Book:Add(rec) == "added" then
            added = added + 1
            again = true
          end
        end
      end
      if not next(list) then g.waiting[author] = nil end
    end
  end
  return added
end

function Sync:Take(records)
  local g, added = MOTA.guild, 0
  Book.replaying = true
  if MOTA.Ballot then MOTA.Ballot.passing = true end
  for _, raw in ipairs(records) do
    local rec = Comm:CheckRecord(raw)
    if rec then
      if Book:Allowed(rec) then
        if Book:Add(rec) == "added" then added = added + 1 end
      else
        g.refused = g.refused or {}
        g.refused[rec.a] = g.refused[rec.a] or {}
        g.refused[rec.a][rec.n] = true
        g.waiting = g.waiting or {}
        g.waiting[rec.a] = g.waiting[rec.a] or {}
        g.waiting[rec.a][rec.n] = { a = rec.a, n = rec.n, t = rec.t, k = rec.k, d = rec.d }
      end
    end
  end
  added = added + self:Retry()
  Book.replaying = false
  if MOTA.Ballot then MOTA.Ballot.passing = false end
  return added
end

Comm:Handle("SY", function(self, sender, channel, f)
  if channel ~= "GUILD" then return end
  local raw = f[1] and Comm:Decode(f[1], true)
  if type(raw) ~= "table" then return end
  local theirs = {}
  for author, e in pairs(raw) do
    local name = self:Bare(author)
    if name and type(e) == "table" and type(e[1]) == "number" then
      local entry = { upto = e[1], held = {} }
      for i = 2, #e do entry.held[e[i]] = true end
      theirs[name] = entry
    elseif name and type(e) == "number" then -- a copy from before 0.6.2
      theirs[name] = { upto = e, held = {} }
    end
  end
  if #Sync:Missing(theirs) > 0 and not offers[sender] then
    offers[sender] = true
    C_Timer.After(OFFER_MIN + math.random() * OFFER_SPREAD, function() Sync:Offer(sender, theirs) end)
  end
  -- They hold something I don't: tell the guild what I have, so I'm sent it.
  local g = self.guild
  local want = false
  for author, entry in pairs(theirs) do
    local mine = g.records[author] or {}
    local refused = g.refused and g.refused[author] or {}
    if entry.upto > Sync:Upto(author) then want = true end
    for n in pairs(entry.held) do
      if not mine[n] and not refused[n] then want = true end
    end
  end
  if want and GetServerTime() - lastSummary >= ASK_GAP then Sync:Send() end
end)

Comm:Handle("CO", function(self, _, channel, f)
  if channel ~= "GUILD" then return end
  local target = self:Bare(f[1])
  if target then offers[target] = nil end
end)

Comm:Handle("CU", function(self, _, channel, f)
  if channel ~= "WHISPER" then return end
  local records = f[1] and Comm:Decode(f[1], true)
  if type(records) ~= "table" then return end
  local added = Sync:Take(records)
  if added > 0 then
    self.stats.lastReceived = GetServerTime()
    self:Debug("caught up on", added, "records")
    self:Fire("CAUGHT_UP", added)
  end
end)

local ticker
MOTA:Listen("GUILD_READY", function(self)
  local g = self.guild
  if g and (g.refusedV or 0) < 2 then
    g.refused, g.refusedV = nil, 2
  end
  local function first()
    if not Sync:Send() then C_Timer.After(5, first) end
  end
  C_Timer.After(FIRST_DELAY, first)
  if not ticker then
    ticker = C_Timer.NewTicker(self.CONST.SYNC_STALE_SECONDS, function() Sync:Send() end)
  end
end)
