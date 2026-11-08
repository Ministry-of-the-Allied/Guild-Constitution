-- Ministry of the Allied: the Vote of No Confidence (Charter Part V; decided
-- with Duncan 2026-11-08).
--
-- A citizen's vote opens a motion if none is open: a seven-day window. If 40%
-- of active citizens (logged in within 30 days) vote within it, the government
-- falls and a Snap Election follows. A motion that fails starts a 30-day cooling
-- period. The Crown stands apart: Kings and Crown ranks neither vote nor count.
--
-- Like a mailed vote, the names reach only the Kings. The guild sees the count.
--
--   nc.open    Crown   { need, active }   a motion opens (a King writes it on the first vote)
--   nc.count   Crown   { id, n }          the count so far; the highest stands
--   nc.result  Crown   { id, passed }     passed, or failed when the week ran out
--
--   NV <number|new>      WHISPER  a citizen's vote, to each online King
--   NR <number>          WHISPER  a King's receipt (0: no motion could be opened)
--   NF <number> <voter>  WHISPER  a King passing a vote to the other
--
-- Motions are numbered in order, so two Kings opening at once count as one.

local _, MOTA = ...
local Confidence = {}
MOTA.Confidence = Confidence

local Book, Comm = MOTA.Book, MOTA.Comm
local DAY = 86400
Confidence.WINDOW = 7 * DAY
Confidence.COOLING = 30 * DAY
Confidence.THRESHOLD = MOTA.CONST.NO_CONFIDENCE_THRESHOLD or 0.40

local function crown(author) return MOTA:IsCrown(author) end
for _, k in ipairs({ "nc.open", "nc.count", "nc.result" }) do Book.rules[k] = crown end

---------------------------------------------------------------------------
-- The motion, from the book
---------------------------------------------------------------------------

local cache

local function build()
  local out = {}
  local list = Book:Latest()
  for i = #list, 1, -1 do
    local r = list[i]
    local d = r.d or {}
    if r.k == "nc.open" and type(d.need) == "number" then
      local cur = out.cur
      -- A second King's opening while one is open is the same motion.
      if cur and not cur.result and r.t < cur.ends then
        cur.ids = cur.ids or {}
        cur.ids[r.a .. "#" .. r.n] = true
      else
        if cur then out.last = cur end
        out.cur = { id = r.a .. "#" .. r.n, seq = (cur and cur.seq or 0) + 1, t = r.t, ends = r.t + Confidence.WINDOW, need = d.need, active = d.active or 0, n = 0 }
      end
    elseif out.cur and (d.id == out.cur.id or (out.cur.ids and out.cur.ids[d.id])) then
      if r.k == "nc.count" and type(d.n) == "number" and d.n > out.cur.n then out.cur.n = d.n
      elseif r.k == "nc.result" and not out.cur.result then out.cur.result = { passed = d.passed and true or false, t = r.t } end
    end
  end
  return out
end

local function get()
  if not cache then cache = build() end
  return cache
end

-- The latest motion: { id, t, ends, need, active, n, result }, or nil.
function Confidence:Motion() return get().cur end

function Confidence:IsOpen()
  local m = self:Motion()
  return m ~= nil and not m.result and GetServerTime() < m.ends
end

-- When another motion may be opened, after a failed one.
function Confidence:CoolingUntil()
  local m = self:Motion()
  if not m or (m.result and m.result.passed) then return nil end
  if self:IsOpen() then return nil end
  local ended = m.result and m.result.t or m.ends
  local at = ended + self.COOLING
  if at > GetServerTime() then return at end
end

-- Active citizens, without the Crown (Charter 5.3, and 1.5).
function Confidence:Electorate()
  local n = 0
  for name in pairs(MOTA.roster) do
    if MOTA:IsActive(name) and not MOTA:IsCrown(name) then n = n + 1 end
  end
  return n
end

function Confidence:Need(active)
  return math.max(1, math.ceil((active or self:Electorate()) * self.THRESHOLD - 1e-9))
end

-- Why a motion can't be opened now, or nil if it can.
function Confidence:Blocked()
  if not MOTA.Elect:Government() then return "There's no government yet." end
  if MOTA.Elect:Underway() then return "An election is already under way." end
  local cool = self:CoolingUntil()
  if cool then return "The last vote failed. Another can be called from " .. date("%d %b", cool) .. " (Charter 5.2)." end
end

---------------------------------------------------------------------------
-- A citizen's vote
---------------------------------------------------------------------------

local function mine()
  MOTA.db.ncVote = MOTA.db.ncVote or {}
  return MOTA.db.ncVote
end

local function kingsOnline()
  local out = {}
  for _, name in ipairs(MOTA:CrownMembers()) do
    if not MOTA:IsMe(name) and MOTA.Hello.heard[name] and MOTA:IsOnline(name) then out[#out + 1] = name end
  end
  return out
end

-- Have I voted in the motion now open (or in the one my vote will open)?
function Confidence:MyVote()
  local v = mine()[MOTA.me]
  if not v then return nil end
  local m = self:Motion()
  if m and v.seq == m.seq then return self:IsOpen() and v or nil end
  if v.id == "new" and not v.delivered and (not m or v.at >= m.t) then return v end
end

local function deliver(v)
  for _, king in ipairs(kingsOnline()) do
    Comm:Send(Comm:Pack("NV", v.seq and tostring(v.seq) or "new"), "WHISPER", king)
  end
end

function Confidence:Vote()
  if MOTA:IsCrown(MOTA.me) then return nil, "The Crown stands apart, and doesn't vote no confidence (Charter 1.5)." end
  if self:MyVote() then return nil, "You've already voted no confidence in this motion." end
  local m = self:Motion()
  local id, seq
  if self:IsOpen() then id, seq = m.id, m.seq
  else
    local why = self:Blocked()
    if why then return nil, why end
    id = "new"
  end
  local v = { id = id, seq = seq, at = GetServerTime() }
  mine()[MOTA.me] = v
  deliver(v)
  MOTA:Fire("CONFIDENCE_CHANGED")
  return true
end

Comm:Handle("NR", function(self, sender, channel, f)
  if channel ~= "WHISPER" or not self:IsCrown(sender) then return end
  local v = mine()[self.me]
  if v and not v.delivered then
    v.delivered, v.seq = true, tonumber(f[1])
    local m = Confidence:Motion()
    if m and m.seq == v.seq then v.id = m.id end
    self:Fire("CONFIDENCE_CHANGED")
  end
end)

---------------------------------------------------------------------------
-- The Kings' count: names only in their own saved variables
---------------------------------------------------------------------------

local function tally(id)
  MOTA.db.ncTally = MOTA.db.ncTally or {}
  local key = MOTA.guildKey .. "|" .. tostring(id)
  MOTA.db.ncTally[key] = MOTA.db.ncTally[key] or {}
  return MOTA.db.ncTally[key]
end

local function size(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local writing
local function writeCount()
  if writing then return end
  writing = true
  C_Timer.After(2 + math.random() * 3, function()
    writing = false
    local m = Confidence:Motion()
    if not Confidence:IsOpen() then return end
    local n = size(tally(m.seq))
    if n > m.n then Book:Write("nc.count", { id = m.id, n = n }) end
    m = Confidence:Motion()
    if n >= m.need and not m.result then
      Book:Write("nc.result", { id = m.id, passed = true })
      MOTA.Elect:CallSnap()
    end
  end)
end

local function eligible(name)
  return MOTA:IsGuildMember(name) and MOTA:IsActive(name) and not MOTA:IsCrown(name)
end

local function count(id, voter)
  local t = tally(id)
  if t[voter] then return false end
  t[voter] = true
  writeCount()
  return true
end

Comm:Handle("NV", function(self, sender, channel, f)
  if channel ~= "WHISPER" or not self:IsCrown(self.me) or not eligible(sender) then return end
  local m = Confidence:Motion()
  local id = f[1] -- the motion's number, or "new"
  if not Confidence:IsOpen() then
    if Confidence:Blocked() then return Comm:Send(Comm:Pack("NR", "0"), "WHISPER", sender) end
    local active = Confidence:Electorate()
    local rec = Book:Write("nc.open", { need = Confidence:Need(active), active = active })
    if not rec then return end
    m = Confidence:Motion()
  end
  if id ~= "new" and tonumber(id) ~= m.seq then return Comm:Send(Comm:Pack("NR", "0"), "WHISPER", sender) end
  if count(m.seq, sender) then
    for _, king in ipairs(kingsOnline()) do
      Comm:Send(Comm:Pack("NF", tostring(m.seq), sender), "WHISPER", king)
    end
  end
  Comm:Send(Comm:Pack("NR", tostring(m.seq)), "WHISPER", sender)
end)

Comm:Handle("NF", function(self, sender, channel, f)
  if channel ~= "WHISPER" or not self:IsCrown(sender) or not self:IsCrown(self.me) then return end
  local voter = self:Bare(f[2])
  local seq = tonumber(f[1])
  if voter and seq and eligible(voter) then count(seq, voter) end
end)

-- A King comes online: held votes go to them, and Kings share their counts.
MOTA:Listen("HELLO_HEARD", function(self, name)
  if not self.db or not self:IsCrown(name) then return end
  local v = mine()[self.me]
  if v and not v.delivered then Comm:Send(Comm:Pack("NV", v.seq and tostring(v.seq) or "new"), "WHISPER", name) end
  if self:IsCrown(self.me) then
    local m = Confidence:Motion()
    if m and Confidence:IsOpen() then
      for voter in pairs(tally(m.seq)) do Comm:Send(Comm:Pack("NF", tostring(m.seq), voter), "WHISPER", name, "bulk") end
    end
  end
end)

---------------------------------------------------------------------------
-- The week running out, the pages and the heralds
---------------------------------------------------------------------------

local closing
local function checkClose()
  if closing or not MOTA.me or not MOTA:IsCrown(MOTA.me) or Book.replaying then return end
  local m = Confidence:Motion()
  if not m or m.result or GetServerTime() < m.ends then return end
  closing = true
  C_Timer.After(2 + math.random() * 6, function()
    closing = false
    local now = Confidence:Motion()
    if now and not now.result and GetServerTime() >= now.ends then
      Book:Write("nc.result", { id = now.id, passed = false })
    end
  end)
end
Confidence.CheckClose = checkClose

-- One line for the Crown's desk and /mota noconfidence.
function Confidence:Line()
  local m = self:Motion()
  if self:IsOpen() then
    return ("No confidence: %d of %d votes needed, until %s."):format(m.n, m.need, date("%d %b", m.ends))
  end
  if m and m.result and m.result.passed and GetServerTime() - m.result.t < 30 * DAY then
    return "No confidence passed on " .. date("%d %b", m.result.t) .. "."
  end
  local cool = self:CoolingUntil()
  if cool then return "No confidence failed. Another vote can be called from " .. date("%d %b", cool) .. "." end
end

local function changed()
  cache = nil
  MOTA:Fire("CONFIDENCE_CHANGED")
end
MOTA:Listen("GUILD_READY", function()
  changed()
  C_Timer.After(25, checkClose)
  if not Confidence.ticking then
    Confidence.ticking = true
    C_Timer.NewTicker(600, checkClose)
  end
end)

local function voteHerald(m)
  local h
  h = { seal = "official", eyebrow = "Part V of the Charter", title = "A Vote of No Confidence", stay = false, closeX = true,
    text = ("Citizens have 7 days. %d of %d active citizens bring down the government."):format(m.need, m.active),
    button = { label = "Vote now", style = "blue", keep = true, onPress = function()
      if not h.armed then
        h.armed = true
        h.text = "Press again to vote no confidence in the government. Only the Kings see who voted."
        MOTA.Herald:Update(h)
        return
      end
      local ok, err = Confidence:Vote()
      if err then MOTA:Print(err) else MOTA:Print("Your vote of no confidence is cast. Only the Kings see who voted.") end
      MOTA.Herald:Close(h)
    end } }
  return h
end

MOTA:Listen("RECORD_ADDED", function(self, rec)
  if rec.k:sub(1, 3) ~= "nc." then return end
  changed()
  if Book.replaying or not self.Herald then return end
  local m = Confidence:Motion()
  if rec.k == "nc.open" and m and m.id == rec.a .. "#" .. rec.n then
    if self:IsCrown(self.me) or Confidence:MyVote() then
      self.Herald:Announce({ seal = "official", eyebrow = "Part V of the Charter", title = "A Vote of No Confidence",
        text = ("Citizens have 7 days. %d of %d active citizens bring down the government."):format(m.need, m.active),
        button = { label = "Dismiss", style = "quiet" } })
    else
      self.Herald:Announce(voteHerald(m))
    end
  elseif rec.k == "nc.result" and m and m.result then
    if m.result.passed then
      self.Herald:Announce({ seal = "crown", eyebrow = "By proclamation of the Crown", title = "The government falls",
        text = ("No confidence, by %d of %d active citizens. A Snap Election follows."):format(m.n, m.active),
        button = { label = "Dismiss", style = "quiet" } })
    else
      self.Herald:Announce({ seal = "crown", eyebrow = "By proclamation of the Crown", title = "The government survives",
        text = ("%d of the %d votes needed. Another can't be called for 30 days."):format(m.n, m.need),
        button = { label = "Dismiss", style = "quiet" } })
    end
  end
end)

-- At login, a citizen who hasn't voted in an open motion is told.
MOTA:Listen("GUILD_READY", function(self)
  C_Timer.After(14, function()
    if not self.me or self:IsCrown(self.me) or not Confidence:IsOpen() or Confidence:MyVote() then return end
    self:Print(Confidence:Line(), "Vote with /mota noconfidence yes. Only the Kings see who voted.")
  end)
end)
