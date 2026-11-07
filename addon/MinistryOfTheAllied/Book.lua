-- Ministry of the Allied: the book of records.
-- Everything that happens is written down as a record, and records are only
-- ever added, never edited or deleted (ADDON_SPEC.md, section 7.1).
--
-- A record: { a = author "Name-Realm", n = the author's running number,
--             t = server time, k = type such as "test.note", d = details }
-- Author + number is the record's ID: "Max's record 57".
--
-- Milestone 1 only takes records sent live by their own author. Records passed
-- on by someone else arrive with catch-up in a later milestone (section 4).

local _, MOTA = ...
local Book = {}
MOTA.Book = Book

-- Who may create each type of record. Types this copy doesn't know are still
-- kept (so they can be passed on later) but never acted on (section 7).
Book.rules = {
  ["test.note"] = function(author) return true end, -- anyone, for testing
}

function Book:Ready()
  return MOTA.guild ~= nil and MOTA.me ~= nil
end

function Book:Get(author, n)
  local list = MOTA.guild and MOTA.guild.records[author]
  return list and list[n]
end

function Book:Top(author)
  return MOTA.guild and MOTA.guild.tops[author] or 0
end

-- A guild member holds our records up to number n (from their hello reply).
function Book:Reserve(author, n)
  local g = MOTA.guild
  if g and n and n > (g.reserved[author] or 0) then g.reserved[author] = n end
end

-- The next number for one of my own records. It never reuses a number that a
-- guild member already holds, even if this computer lost records in a crash.
function Book:NextNumber()
  local g, me = MOTA.guild, MOTA.me
  return math.max(g.tops[me] or 0, g.reserved[me] or 0) + 1
end

function Book:Allowed(rec)
  local rule = self.rules[rec.k]
  if not rule then return true end
  return rule(rec.a, rec) and true or false
end

-- Returns "added", "known" (the same record is already held) or "conflict"
-- (a different record with the same ID; the first one is kept).
function Book:Add(rec)
  local g = MOTA.guild
  g.records[rec.a] = g.records[rec.a] or {}
  local have = g.records[rec.a][rec.n]
  if have then
    if have.t == rec.t and have.k == rec.k then return "known" end
    MOTA.stats.conflicts = MOTA.stats.conflicts + 1
    return "conflict"
  end
  g.records[rec.a][rec.n] = { t = rec.t, k = rec.k, d = rec.d, got = GetServerTime() }
  if rec.n > (g.tops[rec.a] or 0) then g.tops[rec.a] = rec.n end
  MOTA:Fire("RECORD_ADDED", rec)
  return "added"
end

-- Writes one of my own records and sends it to the guild straight away.
-- Returns the record, or nil and the reason it wasn't written.
function Book:Write(kind, details)
  if not self:Ready() then return nil, "not in a guild yet, or the roster hasn't loaded" end
  if MOTA.outdated then return nil, "a newer version is in use; update before writing records" end
  local rec = { a = MOTA.me, n = self:NextNumber(), t = GetServerTime(), k = kind, d = details or {} }
  local msg = MOTA.Comm:EncodeRecord(rec)
  if #msg > MOTA.Comm.MAX_LEN then return nil, "too long to send (" .. #msg .. " bytes)" end
  self:Add(rec)
  MOTA.Comm:Send(msg, "GUILD")
  return rec
end

function Book:Count()
  local total, authors, mine = 0, 0, 0
  if not MOTA.guild then return 0, 0, 0 end
  for author, list in pairs(MOTA.guild.records) do
    authors = authors + 1
    for _ in pairs(list) do
      total = total + 1
      if author == MOTA.me then mine = mine + 1 end
    end
  end
  return total, authors, mine
end

-- The newest records first.
function Book:Latest(limit)
  local all = {}
  if not MOTA.guild then return all end
  for author, list in pairs(MOTA.guild.records) do
    for n, r in pairs(list) do
      all[#all + 1] = { a = author, n = n, t = r.t, k = r.k, d = r.d }
    end
  end
  table.sort(all, function(x, y)
    if x.t ~= y.t then return x.t > y.t end
    if x.a ~= y.a then return x.a < y.a end
    return x.n > y.n
  end)
  for i = #all, (limit or #all) + 1, -1 do all[i] = nil end
  return all
end

-- A short one-line description of a record's details.
function Book:Describe(rec)
  if rec.k == "test.note" then return "\"" .. tostring(rec.d.text or "") .. "\"" end
  if (rec.k == "bank.move" or rec.k == "bank.fill") and MOTA.BankPrompt then
    return MOTA:Money(rec.d.amt) .. " " .. (rec.d.io == "w" and "withdrawn" or "deposited") .. ": "
      .. tostring(rec.d.note or MOTA.BankPrompt:LabelFor(rec.d.io, rec.d.r))
  end
  local parts = {}
  for k, v in pairs(rec.d or {}) do parts[#parts + 1] = k .. "=" .. tostring(v) end
  table.sort(parts)
  return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Records arriving from the guild
---------------------------------------------------------------------------

MOTA.Comm:Handle("RC", function(self, sender, channel, fields)
  if channel ~= "GUILD" then return end
  local rec = MOTA.Comm:DecodeRecord(fields)
  if not rec or rec.a ~= sender or not Book:Allowed(rec) then
    self.stats.ignored = self.stats.ignored + 1
    self:Debug("record ignored from", sender)
    return
  end
  if Book:Add(rec) == "added" then
    self.stats.lastReceived = GetServerTime()
  end
end)

-- Test records are announced in chat, so two testers can see them arrive.
MOTA:Listen("RECORD_ADDED", function(self, rec)
  if rec.k ~= "test.note" then return end
  if rec.a == self.me then
    self:Print("Test record", self:Color("leaf", "#" .. rec.n), "written and sent to the guild:", Book:Describe(rec))
  else
    self:Print("Test record", self:Color("leaf", "#" .. rec.n), "from", self:Color("leaf", self:Short(rec.a)) .. ":", Book:Describe(rec))
  end
end)
