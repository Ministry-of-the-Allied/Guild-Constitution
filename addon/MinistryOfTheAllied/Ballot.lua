-- Ministry of the Allied: the secret ballot (ADDON_SPEC.md 8.2 and 8.3,
-- CODING_BRIEF.md "Vote secrecy rule"). Milestone 4.
--
-- Records, in the shared book (GUILD). A ballot's ID is "<author>#<number>"
-- of its ballot.open record.
--   ballot.open    Crown   name, kind ("general"|"snap"|"runoff"), cands = {{n, p}}, closes
--   ballot.sealed  voter   b: a ballot sealed while no King could take it. Who and when, never how
--   ballot.voted   Crown   b, v: who voted, never how
--   ballot.close   Crown   b: polls closed early
--   ballot.result  Crown   b, name, kind, cands, votes, total, eligible, w (winner) or tie + tied
--
-- Whispers, never GUILD or OFFICER:
--   BV <ballot> <choice> <token> <sealed record number>   voter -> each online King
--   BR <ballot> <ok|dup|closed|unknown>                   King -> voter (receipt)
--   BT <packed count>                                     King <-> King (hand-over and comparison)
--   BO <packed records>                                   King -> a member who said hello
--   BS <ballot> <packed {voter = time}>                    member -> a King logging in: sealed
--                                                         ballots heard of (only for the count of
--                                                         ballots still to come)
--
-- The voter's choice is kept only until a King's receipt arrives. The Kings'
-- add-ons keep a count per candidate and the names of who was counted, never
-- the two together (MOTADB.ballotTally).

local _, MOTA = ...
local Ballot = {}
MOTA.Ballot = Ballot
local Book, Comm = MOTA.Book, MOTA.Comm

local RECEIPT_WAIT = 10        -- seconds to wait for a King's receipt before holding the ballot
local HANDOVER_DELAY = 3       -- seconds after counting before the count goes to the other King
local SEALED_WAIT = 5          -- after the close: how long to wait for a held ballot's sealed record
local RESULT_FRESH = 7 * 86400 -- a result is sent to members logging in for a week
local BATCH = 8                -- records per BO message
local MAX_CANDS = 4

Ballot.KINDS = { general = "General Election", snap = "Snap Election", runoff = "Run-off" }
Ballot.KIND_ORDER = { "general", "snap", "runoff" }
Ballot.PARTIES = {
  sh = { tag = "Silverhand", chip = "Silverhand", the = "the Silverhand", line = "Standing for the Silverhand", color = "1F4290" },
  ex = { tag = "Azeroth Exchange", chip = "Exchange", the = "the Azeroth Exchange", line = "Standing for the Azeroth Exchange", color = "9E1B22" },
  ind = { tag = "Independent", chip = "Independent", line = "Standing as an Independent", color = "5E4B33" },
}
Ballot.PARTY_ORDER = { "sh", "ex", "ind" }
Ballot.MAX_CANDS = MAX_CANDS

local ballots = {}    -- [id] = { id, a, n, t, d, closeT, closeRef, result, resultT, resultRef, voted, votedRef, sealed }
local reminded = {}   -- [id] = true once the open herald or the reminder has shown this session
local sentOpen = {}   -- [name] = what was last sent to them by BO this session
local waits = {}      -- [voter .. id] = a ballot that came after the close, waiting for its sealed record
local peerCounts = {} -- [id] = { [King] = { total, same } }: the other King's count, from BT
local handover = {}   -- [id] = true while a hand-over is due
local heardSealed = {} -- [id] = { [voter] = time }: sealed ballots other members told this King of (BS)
Ballot.ballots = ballots

---------------------------------------------------------------------------
-- Who may write each record type (Book.rules), with a check of the details
---------------------------------------------------------------------------

local function str(v, max) return type(v) == "string" and v ~= "" and #v <= max end
local function crown(name) return MOTA:IsCrown(name) end

local function validCands(cands)
  if type(cands) ~= "table" or #cands < 2 or #cands > MAX_CANDS then return false end
  for _, c in ipairs(cands) do
    if type(c) ~= "table" or not str(c.n, 48) or not Ballot.PARTIES[c.p] then return false end
  end
  return true
end

Book.rules["ballot.open"] = function(a, rec)
  local d = rec and rec.d or {}
  return crown(a) and str(d.name, 80) and Ballot.KINDS[d.kind] ~= nil and type(d.closes) == "number"
    and validCands(d.cands)
end
Book.rules["ballot.sealed"] = function(a, rec) return str(rec and rec.d.b, 120) end
Book.rules["ballot.voted"] = function(a, rec) return crown(a) and str(rec and rec.d.b, 120) and str(rec.d.v, 80) end
Book.rules["ballot.close"] = function(a, rec) return crown(a) and str(rec and rec.d.b, 120) end
Book.rules["ballot.result"] = function(a, rec)
  local d = rec and rec.d or {}
  return crown(a) and str(d.b, 120) and str(d.name, 80) and validCands(d.cands) and type(d.votes) == "table"
    and type(d.total) == "number"
end

---------------------------------------------------------------------------
-- The index: each ballot worked out from the book
---------------------------------------------------------------------------

local function entry(id)
  local b = ballots[id]
  if not b then
    b = { id = id, voted = {}, votedRef = {}, sealed = {} }
    ballots[id] = b
  end
  return b
end

local function index(a, n, r)
  local k, d = r.k, r.d or {}
  if k == "ballot.open" then
    local b = entry(a .. "#" .. n)
    b.a, b.n, b.t, b.d = a, n, r.t, d
  elseif type(d.b) ~= "string" then
    return
  elseif k == "ballot.close" then
    local b = entry(d.b)
    if not b.closeT or r.t < b.closeT then b.closeT, b.closeRef = r.t, { a, n } end
  elseif k == "ballot.result" then
    local b = entry(d.b) -- the first result written is the one that stands
    if not b.resultT or r.t < b.resultT then b.result, b.resultT, b.resultRef = d, r.t, { a, n } end
  elseif k == "ballot.voted" and type(d.v) == "string" then
    local b = entry(d.b)
    b.voted[d.v] = true
    b.votedRef[d.v] = b.votedRef[d.v] or { a, n }
  elseif k == "ballot.sealed" then
    local s = entry(d.b).sealed
    if not s[a] or r.t < s[a].t then s[a] = { t = r.t, n = n } end
  end
end

function Ballot:Rebuild()
  wipe(ballots)
  local g = MOTA.guild
  if not g then return end
  for a, list in pairs(g.records) do
    for n, r in pairs(list) do
      if type(r.k) == "string" and r.k:sub(1, 7) == "ballot." then index(a, n, r) end
    end
  end
end

---------------------------------------------------------------------------
-- Stages and times
---------------------------------------------------------------------------

function Ballot:CloseTime(b)
  local c = b.d.closes
  if b.closeT and b.closeT < c then c = b.closeT end
  return c
end

-- "open", "closed" (no new ballots, not declared yet), "declared" or "none".
function Ballot:Stage(b)
  if not b or not b.d then return "none" end
  if b.result then return "declared" end
  if GetServerTime() < self:CloseTime(b) then return "open" end
  return "closed"
end

-- The ballot the Ballot Hall is about: the newest one not yet declared.
function Ballot:Current()
  local best
  for _, b in pairs(ballots) do
    if b.d and not b.result and (not best or b.t > best.t or (b.t == best.t and b.id > best.id)) then best = b end
  end
  return best
end

-- Declared results, newest first.
function Ballot:Results()
  local list = {}
  for _, b in pairs(ballots) do
    if b.result then list[#list + 1] = b end
  end
  table.sort(list, function(x, y)
    if x.resultT ~= y.resultT then return x.resultT > y.resultT end
    return x.id > y.id
  end)
  return list
end

function Ballot:Get(id) return ballots[id] end

-- The realm's clock: "9:40 pm" for a server time.
function Ballot:Clock(t)
  local h, m = GetGameTime()
  local mins = (h * 60 + m + math.floor((t - GetServerTime()) / 60 + 0.5)) % 1440
  local hh, mm = math.floor(mins / 60), mins % 60
  local suffix = hh < 12 and "am" or "pm"
  hh = hh % 12
  if hh == 0 then hh = 12 end
  return ("%d:%02d %s"):format(hh, mm, suffix)
end

-- "1 h 12 min" from now until t.
function Ballot:Left(t)
  local s = math.max(0, t - GetServerTime())
  if s < 60 then return "under a minute" end
  local h, m = math.floor(s / 3600), math.floor((s % 3600) / 60)
  if h > 0 then return ("%d h %d min"):format(h, m) end
  return m .. " min"
end

function Ballot:Date(t)
  return (date("%d %B", t):gsub("^0", ""))
end

---------------------------------------------------------------------------
-- The Kings
---------------------------------------------------------------------------

function Ballot:IsKing() return MOTA.me ~= nil and MOTA:IsCrown(MOTA.me) end

-- Other Crown members online whose add-on has said hello this session: the
-- only ones a ballot can reach.
function Ballot:OnlineKings()
  local list = {}
  for _, name in ipairs(MOTA:CrownMembers()) do
    if not MOTA:IsMe(name) and MOTA.Hello.heard[name] and MOTA:IsOnline(name) then list[#list + 1] = name end
  end
  return list
end

-- Every Crown member, for the ballot's "Your ballot goes to" list.
function Ballot:Kings()
  local list = {}
  for _, name in ipairs(MOTA:CrownMembers()) do
    local me = MOTA:IsMe(name)
    list[#list + 1] = { name = name, me = me,
      online = me or (MOTA.Hello.heard[name] and MOTA:IsOnline(name)) and true or false }
  end
  return list
end

---------------------------------------------------------------------------
-- The voter's side
---------------------------------------------------------------------------

-- Saved per account (Account.lua), so an alt can't vote again:
-- guild.myBallots[account key][ballot] =
--   { choice, tok, sealedN, held, delivered, late, receiptAt }
-- The choice is deleted as soon as a receipt arrives.
local function mine()
  local g = MOTA.guild
  g.myBallots = g.myBallots or {}
  local key = MOTA.Account:Key(MOTA.me)
  g.myBallots[key] = g.myBallots[key] or {}
  return g.myBallots[key]
end

-- Has any character on this account voted in ballot b?
local function anyVoted(b)
  for _, n in ipairs(MOTA.Account:Alts(MOTA.me)) do
    if b.voted[n] then return true end
  end
  return false
end

function Ballot:Mine(id)
  return MOTA.guild and MOTA.me and mine()[id]
end

-- "none", "sending", "held", "sent" or "late".
function Ballot:MyState(b)
  if not b or not MOTA.guild then return "none" end
  local e = mine()[b.id]
  if e then
    if e.delivered then return "sent" end
    if e.late then return "late" end
    if e.held then return "held" end
    return "sending"
  end
  if anyVoted(b) then return "sent" end
  return "none"
end

local function changed() MOTA:Fire("BALLOT_CHANGED") end

local function sendBallot(king, b, e)
  Comm:Send(Comm:Pack("BV", b.id, e.choice, e.tok, e.sealedN or ""), "WHISPER", king)
end

-- No King took it: write the public "sealed" record (who, not how) and keep it.
function Ballot:Hold(b, e)
  if e.delivered or e.late then return end
  if not e.sealedN and self:Stage(b) == "open" then
    local rec = Book:Write("ballot.sealed", { b = b.id })
    if rec then e.sealedN = rec.n end
  end
  if not e.held then
    e.held = true
    MOTA:Print("No King has your ballot yet: it is sealed and kept here, and goes to the Crown when a King logs in.")
  end
  changed()
end

function Ballot:Seal(choice)
  if not MOTA.guild or not MOTA.me then return nil, "The guild hasn't loaded yet." end
  local b = self:Current()
  if self:Stage(b) ~= "open" then return nil, "The polls aren't open." end
  choice = tonumber(choice)
  if not choice or not b.d.cands[choice] then return nil, "Mark one name first." end
  local my = mine()
  if my[b.id] or anyVoted(b) then return nil, "You have already voted in this election, on this account." end
  local e = { choice = choice, tok = GetServerTime() .. "." .. math.random(1000, 9999) }
  my[b.id] = e
  local kings = self:OnlineKings()
  for _, king in ipairs(kings) do sendBallot(king, b, e) end
  if self:IsKing() then
    -- A King's own ballot is counted in their own add-on.
    self:Receipt(MOTA.me, b.id, self:Receive(MOTA.me, b.id, choice, e.tok))
  elseif #kings == 0 then
    self:Hold(b, e)
  else
    C_Timer.After(RECEIPT_WAIT, function()
      if not e.delivered and not e.late then self:Hold(b, e) end
    end)
  end
  changed()
  return e
end

-- A King's receipt.
function Ballot:Receipt(king, id, status)
  local e = mine()[id]
  if not e then return end
  if status == "ok" or status == "dup" then
    local first = not e.delivered
    e.delivered, e.receiptAt, e.held, e.late = true, GetServerTime(), nil, nil
    e.choice = nil -- no longer needed: forget it
    if first and king ~= MOTA.me then
      MOTA:Print("Your ballot was received by the Crown (" .. MOTA:Short(king) .. "). It is secret: only that you voted is recorded.")
    end
  elseif status == "closed" then
    if not e.delivered then
      e.late, e.choice, e.held = true, nil, nil
      MOTA:Print(MOTA:Color("crimson", "Your ballot reached the Crown too late to count."))
    end
  elseif status == "unknown" then
    -- That King's add-on doesn't know this ballot yet: keep it for another.
    local b = ballots[id]
    if b and not e.delivered then self:Hold(b, e) end
  end
  changed()
end

-- A King's add-on said hello: hand over any ballot held for the Crown.
function Ballot:Deliver(king)
  if not MOTA.guild or not MOTA.me then return end
  for id, e in pairs(mine()) do
    local b = ballots[id]
    if e.choice and not e.delivered and not e.late and b and b.d then
      if b.result then
        e.choice, e.late, e.held = nil, true, nil
      else
        if e.sealedN then
          -- Send the sealed record again, so the King holds it before the ballot.
          local r = Book:Get(MOTA.me, e.sealedN)
          if r then Comm:Send(Comm:EncodeRecord({ a = MOTA.me, n = e.sealedN, t = r.t, k = r.k, d = r.d }), "GUILD") end
        end
        sendBallot(king, b, e)
      end
    end
  end
  changed()
end

---------------------------------------------------------------------------
-- The Kings' side: counting
---------------------------------------------------------------------------

function Ballot:Tally(id)
  local b = ballots[id]
  MOTA.db.ballotTally = MOTA.db.ballotTally or {}
  local t = MOTA.db.ballotTally[id]
  if not t then
    t = { counts = {}, counted = {}, refused = 0 }
    for i = 1, (b and b.d and #b.d.cands or 0) do t.counts[i] = 0 end
    MOTA.db.ballotTally[id] = t
  end
  t.counted = t.counted or {}
  return t
end

local function sum(list)
  local n = 0
  for _, v in pairs(list or {}) do n = n + (tonumber(v) or 0) end
  return n
end
Ballot.Sum = sum

function Ballot:ScheduleHandover(id)
  if handover[id] then return end
  handover[id] = true
  C_Timer.After(HANDOVER_DELAY, function()
    handover[id] = nil
    self:SendCount(id)
  end)
end

-- Counts one ballot. Returns the receipt: "ok", "dup", "closed", "unknown",
-- "wait" (after the close, its sealed record hasn't arrived) or "bad".
function Ballot:Receive(voter, id, choice, tok, sealedN)
  if not self:IsKing() then return nil end
  local b = ballots[id]
  if not b or not b.d then return "unknown" end
  if b.result then return "closed" end
  choice = tonumber(choice)
  if not choice or not b.d.cands[choice] or choice ~= math.floor(choice) then return "bad" end
  tok = tostring(tok or "")
  local t = self:Tally(id)
  local voterName = voter
  voter = MOTA.Account:Key(voter) -- one ballot per player, on whichever character
  -- Only a voter this King has already counted is refused (also after a
  -- hand-over), not one merely on the public voted list: the other King may
  -- have counted the very same ballot.
  if t.counted[voter] then
    if t.counted[voter] == tok then return "ok" end -- the same ballot again
    t.refused = t.refused + 1
    changed()
    return "dup"
  end
  if self:Stage(b) == "closed" then
    local s = b.sealed[voterName]
    if not s then return sealedN and "wait" or "closed" end
    if s.t > self:CloseTime(b) then return "closed" end
  end
  t.counts[choice] = (t.counts[choice] or 0) + 1
  t.counted[voter] = tok
  if not b.voted[voterName] then Book:Write("ballot.voted", { b = id, v = voterName }) end
  self:ScheduleHandover(id)
  changed()
  return "ok"
end

local function reply(voter, id, status)
  if status and status ~= "bad" then Comm:Send(Comm:Pack("BR", id, status), "WHISPER", voter) end
end

-- A ballot from after the close whose sealed record is still on its way.
local function settleWait(key)
  local w = waits[key]
  if not w then return end
  waits[key] = nil
  local status = Ballot:Receive(w.voter, w.id, w.choice, w.tok, nil)
  reply(w.voter, w.id, status)
end

MOTA.Comm:Handle("BV", function(self, sender, channel, f)
  if channel ~= "WHISPER" then return end
  local status = Ballot:Receive(sender, f[1], f[2], f[3], tonumber(f[4]))
  if status == "wait" then
    local key = sender .. "|" .. f[1]
    waits[key] = { voter = sender, id = f[1], choice = f[2], tok = f[3] }
    C_Timer.After(SEALED_WAIT, function() settleWait(key) end)
    return
  end
  reply(sender, f[1], status)
end)

MOTA.Comm:Handle("BR", function(self, sender, channel, f)
  if channel ~= "WHISPER" or not MOTA:IsCrown(sender) then return end
  Ballot:Receipt(sender, f[1], f[2])
end)

---------------------------------------------------------------------------
-- The Kings' side: hand-over and comparing the two counts
---------------------------------------------------------------------------

function Ballot:SendCount(id, to, isReply)
  local b = ballots[id]
  if not self:IsKing() or not b or not b.d or b.result then return end
  local t = self:Tally(id)
  local msg = Comm:Pack("BT", Comm:Encode({ b = id, c = t.counts, n = t.counted, r = t.refused, p = isReply and 1 or nil }))
  local targets = to and { to } or self:OnlineKings()
  for _, king in ipairs(targets) do Comm:Send(msg, "WHISPER", king) end
end

local function covers(a, x)
  for name, tok in pairs(x) do
    if a[name] ~= tok then return false end
  end
  return true
end

local function disjoint(a, x)
  for name in pairs(x) do
    if a[name] ~= nil then return false end
  end
  return true
end

-- The other King's count arrived. If it covers ours, take it; if ours covers
-- theirs, answer with ours; if they share nobody, add them up. If they
-- partly overlap, keep ours and show that the counts differ.
function Ballot:Compare(king, p)
  local b = ballots[p.b]
  if not b or not b.d or b.result or type(p.c) ~= "table" or type(p.n) ~= "table" then return end
  local t = self:Tally(p.b)
  local theirs, ours = p.n, t.counted
  local outcome
  if covers(theirs, ours) and covers(ours, theirs) then
    outcome = "agree"
  elseif covers(theirs, ours) then
    outcome = "adopted"
    t.counts, t.counted = CopyTable(p.c), CopyTable(theirs)
  elseif covers(ours, theirs) then
    outcome = "ahead"
  elseif disjoint(ours, theirs) then
    outcome = "added"
    for i = 1, #b.d.cands do t.counts[i] = (t.counts[i] or 0) + (tonumber(p.c[i]) or 0) end
    for name, tok in pairs(theirs) do t.counted[name] = tok end
  else
    outcome = "differ"
  end
  t.refused = math.max(t.refused or 0, tonumber(p.r) or 0)
  peerCounts[p.b] = peerCounts[p.b] or {}
  if outcome == "differ" then
    peerCounts[p.b][king] = { total = sum(p.c), same = false }
  else
    -- After this exchange both hold the same count (an "ahead" King's reply
    -- is adopted on the other side).
    peerCounts[p.b][king] = { total = sum(t.counts), same = true }
  end
  MOTA:Debug("count from", MOTA:Short(king), outcome)
  if not p.p then self:SendCount(p.b, king, true) end
  changed()
  return outcome
end

-- The other King's count as last heard: { total, same } or nil.
function Ballot:PeerCount(id, king)
  return peerCounts[id] and peerCounts[id][king]
end

MOTA.Comm:Handle("BT", function(self, sender, channel, f)
  if channel ~= "WHISPER" or not Ballot:IsKing() or not MOTA:IsCrown(sender) then return end
  local p = f[1] and Comm:Decode(f[1])
  if type(p) == "table" and type(p.b) == "string" then Ballot:Compare(sender, p) end
end)

-- Ballots sealed while no King could take them, not yet counted: from the
-- sealed records this add-on holds, and those other members told it of (BS).
function Ballot:HeldCount(b)
  local t = self:IsKing() and self:Tally(b.id) or { counted = {} }
  local names = {}
  for name in pairs(b.sealed) do names[name] = true end
  for name in pairs(heardSealed[b.id] or {}) do names[name] = true end
  local n = 0
  for name in pairs(names) do
    if not b.voted[name] and not t.counted[MOTA.Account:Key(name)] then n = n + 1 end
  end
  return n
end

-- A King logged in: tell them of sealed ballots still waiting that this add-on
-- heard of while they were away, so their view can count them. Only the
-- voter's own record (sent with the ballot) decides whether a ballot counts.
function Ballot:TellSealed(king)
  local b = self:Current()
  if not b or b.result then return end
  local list, any = {}, false
  for name, s in pairs(b.sealed) do
    if not b.voted[name] then list[name] = s.t; any = true end
  end
  if not any then return end
  C_Timer.After(1 + math.random() * 4, function()
    Comm:Send(Comm:Pack("BS", b.id, Comm:Encode(list)), "WHISPER", king, "bulk")
  end)
end

MOTA.Comm:Handle("BS", function(self, sender, channel, f)
  if channel ~= "WHISPER" or not Ballot:IsKing() then return end
  local b = ballots[f[1]]
  local list = f[2] and Comm:Decode(f[2])
  if not b or not b.d or type(list) ~= "table" then return end
  heardSealed[b.id] = heardSealed[b.id] or {}
  for name, t in pairs(list) do
    if type(name) == "string" and type(t) == "number" then heardSealed[b.id][name] = t end
  end
  changed()
end)

---------------------------------------------------------------------------
-- The Crown's actions
---------------------------------------------------------------------------

function Ballot:Open(name, kind, cands)
  if not self:IsKing() then return nil, "Only the Crown can open the polls." end
  if self:Current() then return nil, "The last election hasn't been declared yet." end
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil, "Give the election a name." end
  if not self.KINDS[kind] then return nil, "Choose the kind of election." end
  local list = {}
  for _, c in ipairs(cands or {}) do
    local n = tostring(c.n or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if n ~= "" then list[#list + 1] = { n = n:sub(1, 48), p = self.PARTIES[c.p] and c.p or "ind" } end
  end
  if #list < 2 then return nil, "Name at least two candidates." end
  if #list > MAX_CANDS then return nil, "At most " .. MAX_CANDS .. " candidates." end
  return Book:Write("ballot.open", { name = name:sub(1, 80), kind = kind, cands = list,
    closes = GetServerTime() + MOTA.CONST.BALLOT_WINDOW_SECONDS })
end

function Ballot:Close()
  local b = self:Current()
  if not self:IsKing() then return nil, "Only the Crown can close the polls." end
  if self:Stage(b) ~= "open" then return nil, "The polls aren't open." end
  return Book:Write("ballot.close", { b = b.id })
end

-- The leading candidates' indices and their score.
function Ballot:Leaders(votes, n)
  local top, leaders = -1, {}
  for i = 1, n do
    local v = tonumber(votes[i]) or 0
    if v > top then top, leaders = v, { i } elseif v == top then leaders[#leaders + 1] = i end
  end
  return leaders, math.max(top, 0)
end

-- Declares the result from this King's own count. A tie is declared only by
-- setting up the run-off (runoff = true).
function Ballot:Declare(runoff)
  local b = self:Current()
  if not self:IsKing() then return nil, "Only the Crown can declare the result." end
  if self:Stage(b) ~= "closed" then return nil, "Close the polls first." end
  local t = self:Tally(b.id)
  local votes = {}
  for i = 1, #b.d.cands do votes[i] = t.counts[i] or 0 end
  local total = sum(votes)
  local leaders = self:Leaders(votes, #votes)
  local tie = total > 0 and #leaders > 1
  if tie and not runoff then return nil, "The vote is tied: set up the run-off." end
  if runoff and not tie then return nil, "There is no tie." end
  local d = { b = b.id, name = b.d.name, kind = b.d.kind, cands = b.d.cands, votes = votes, total = total,
    eligible = MOTA:ActiveCitizens() }
  if tie then
    d.tie, d.tied = true, leaders
  elseif total > 0 then
    d.w = leaders[1]
  end
  local rec, why = Book:Write("ballot.result", d)
  if rec then t.counted = {} end -- the names aren't needed once the result is declared
  return rec, why
end

-- The form the Crown view fills in for a run-off: the tied candidates.
function Ballot:RunoffForm(result)
  local name = tostring(result.name):gsub(" run%-off$", "") .. " run-off"
  local cands = {}
  for _, i in ipairs(result.tied or {}) do
    local c = result.cands[i]
    if c then cands[#cands + 1] = { n = c.n, p = c.p } end
  end
  return { name = name, kind = "runoff", cands = cands }
end

---------------------------------------------------------------------------
-- Members logging in mid-poll: an online King sends them the ballot (BO)
---------------------------------------------------------------------------

local TRUSTED = { ["ballot.open"] = true, ["ballot.close"] = true, ["ballot.result"] = true, ["ballot.voted"] = true }

local function recordFor(a, n)
  local r = Book:Get(a, n)
  if r then return { a = a, n = n, t = r.t, k = r.k, d = r.d } end
end

function Ballot:SendOpen(to)
  local recs, key = {}, ""
  local function add(a, n)
    local r = a and recordFor(a, n)
    if r then recs[#recs + 1] = r end
  end
  local b = self:Current()
  if b then
    key = b.id .. (b.closeRef and "c" or "")
    add(b.a, b.n)
    if b.closeRef then add(b.closeRef[1], b.closeRef[2]) end
    if MOTA:IsCrown(to) then
      -- The other King gets who voted and who sealed, for the Crown view.
      for _, ref in pairs(b.votedRef) do add(ref[1], ref[2]) end
      for name, s in pairs(b.sealed) do add(name, s.n) end
    elseif b.votedRef[to] then
      add(b.votedRef[to][1], b.votedRef[to][2])
    end
  end
  local last = self:Results()[1]
  if last and GetServerTime() - last.resultT < RESULT_FRESH then
    key = key .. "|" .. last.id
    add(last.resultRef[1], last.resultRef[2])
  end
  if #recs == 0 or sentOpen[to] == key then return end
  sentOpen[to] = key
  for i = 1, #recs, BATCH do
    local part = {}
    for j = i, math.min(i + BATCH - 1, #recs) do part[#part + 1] = recs[j] end
    Comm:Send(Comm:Pack("BO", Comm:Encode(part)), "WHISPER", to)
  end
end

local function validRecord(r)
  return type(r) == "table" and type(r.a) == "string" and r.a ~= "" and type(r.n) == "number" and r.n >= 1
    and r.n == math.floor(r.n) and type(r.t) == "number" and type(r.k) == "string" and type(r.d) == "table"
end

MOTA.Comm:Handle("BO", function(self, sender, channel, f)
  if channel ~= "WHISPER" or not MOTA:IsCrown(sender) then return end
  local list = f[1] and Comm:Decode(f[1])
  if type(list) ~= "table" then return end
  Ballot.passing = true
  for _, r in ipairs(list) do
    -- Records passed on by a King: the Crown's own ballot records, and the
    -- voters' sealed records.
    if validRecord(r) and (TRUSTED[r.k] and MOTA:IsCrown(r.a) or r.k == "ballot.sealed") and Book:Allowed(r) then
      Book:Add({ a = r.a, n = r.n, t = r.t, k = r.k, d = r.d })
    end
  end
  Ballot.passing = false
  C_Timer.After(1, function() Ballot:Remind() end)
end)

---------------------------------------------------------------------------
-- Heralds and the login reminder
---------------------------------------------------------------------------

local function openBallotHall(view)
  return function() if MOTA.BallotHall then MOTA.BallotHall:SetView(view) end end
end

function Ballot:Proclamation(r)
  if r.tie then
    local names = {}
    for _, i in ipairs(r.tied or {}) do names[#names + 1] = r.cands[i] and r.cands[i].n or "?" end
    local _, top = self:Leaders(r.votes, #r.cands)
    return ("The citizens are evenly divided: %s have %d votes each. By the Charter, they face a run-off within 48 hours.")
      :format(table.concat(names, " and "), top)
  end
  local c = r.w and r.cands[r.w]
  if not c then return "No ballots were cast." end
  local party = self.PARTIES[c.p] or self.PARTIES.ind
  return ("By the will of the citizens, %s%s is named Prime Minister, with %d of %d votes."):format(
    c.n, party.the and (" of " .. party.the) or ", standing as an Independent,", tonumber(r.votes[r.w]) or 0, r.total)
end

local function heraldOpen(b)
  MOTA.Herald:Announce({
    seal = "official", eyebrow = "Hear ye · the Ballot Hall", title = "The polls are open!",
    text = b.d.name .. ": seal your ballot before " .. Ballot:Clock(Ballot:CloseTime(b)) .. ", realm time.",
    button = { label = "Vote now", style = "blue", page = 2, onPress = openBallotHall("ballot") },
  })
end

local function heraldResult(r)
  local title
  if r.tie then
    title = "A tie: a run-off follows"
  elseif r.w and r.cands[r.w] then
    title = r.cands[r.w].n .. " is elected"
  else
    title = "No ballots were cast"
  end
  MOTA.Herald:Announce({
    seal = "crown", eyebrow = "By proclamation of the Crown", title = title,
    text = r.name .. ". " .. (r.tie and "The tied candidates face a run-off." or
      ("Turnout " .. r.total .. " of " .. (r.eligible or "?") .. " active citizens.")),
    button = { label = "Open", style = "quiet", page = 2, onPress = openBallotHall("results") },
  })
end

-- Once per ballot per session: polls are open and you haven't voted.
function Ballot:Remind()
  local b = self:Current()
  if self:Stage(b) ~= "open" or reminded[b.id] or self:MyState(b) ~= "none" then return end
  reminded[b.id] = true
  local left = self:Left(self:CloseTime(b))
  MOTA:Print(MOTA:Color("leaf", "You haven't voted yet:"), b.d.name, "· polls close in", left .. ". /mota ballot opens the Ballot Hall.")
  MOTA.Herald:Announce({
    seal = "official", eyebrow = "Hear ye · the Ballot Hall", title = "You haven't voted yet",
    text = b.d.name .. ": polls close in " .. left .. ", at " .. self:Clock(self:CloseTime(b)) .. " realm time.",
    button = { label = "Vote now", style = "blue", page = 2, onPress = openBallotHall("ballot") },
  })
end

---------------------------------------------------------------------------
-- The last King's logout warning (ADDON_SPEC.md 8.2; to test, section 18)
---------------------------------------------------------------------------

StaticPopupDialogs["MOTA_LAST_KING"] = {
  text = "You are the last King online\n\nPolls are open for %s. If you log out, ballots sealed from now on wait "
    .. "with their voters until a King returns. They still count if they reach the Crown before the result is declared.",
  button1 = "Stay online",
  button2 = "Log out anyway",
  OnAccept = function() Ballot.stayed = true; if CancelLogout then CancelLogout() end end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = false,
  showAlert = true,
}

function Ballot:LogoutCheck()
  if not MOTA.guild or not self:IsKing() then return false end
  local b = self:Current()
  if self:Stage(b) ~= "open" or #self:OnlineKings() > 0 then return false end
  StaticPopup_Show("MOTA_LAST_KING", b.d.name)
  return true
end

MOTA:On("PLAYER_CAMPING", function() Ballot:LogoutCheck() end)

---------------------------------------------------------------------------
-- Keeping up with the book
---------------------------------------------------------------------------

MOTA:Listen("GUILD_READY", function()
  Ballot:Rebuild()
  changed()
  C_Timer.After(12, function() Ballot:Remind() end)
end)

MOTA:Listen("RECORD_ADDED", function(self, rec)
  if type(rec.k) ~= "string" or rec.k:sub(1, 7) ~= "ballot." then return end
  index(rec.a, rec.n, rec)
  local own = rec.a == self.me
  if rec.k == "ballot.open" then
    local b = ballots[rec.a .. "#" .. rec.n]
    if own then
      reminded[b.id] = true
    elseif not Ballot.passing and Ballot:Stage(b) == "open" then
      reminded[b.id] = true
      heraldOpen(b)
    end
  elseif rec.k == "ballot.result" then
    local e = Ballot:Mine(rec.d.b)
    if e and e.choice and not e.delivered then
      e.choice, e.late, e.held = nil, true, nil
      self:Print(self:Color("crimson", "Your sealed ballot reached no King before the result was declared, so it didn't count."))
    end
    if not Ballot.passing and not own then heraldResult(rec.d) end
  elseif rec.k == "ballot.voted" and rec.d.v == self.me then
    -- A King recorded our vote: as good as a receipt.
    local e = Ballot:Mine(rec.d.b)
    if e and not e.delivered then Ballot:Receipt(rec.a, rec.d.b, "ok") end
  elseif rec.k == "ballot.sealed" then
    settleWait(rec.a .. "|" .. tostring(rec.d.b))
  end
  changed()
end)

MOTA:Listen("HELLO_HEARD", function(self, name, how)
  if not self.guild then return end
  if MOTA:IsCrown(name) then
    Ballot:Deliver(name)
    if how == "HI" then Ballot:TellSealed(name) end
    -- Two Kings meet: compare counts (the hand-over).
    local b = Ballot:Current()
    if b and Ballot:IsKing() then Ballot:ScheduleHandover(b.id) end
  end
  if Ballot:IsKing() then Ballot:SendOpen(name) end
end)
