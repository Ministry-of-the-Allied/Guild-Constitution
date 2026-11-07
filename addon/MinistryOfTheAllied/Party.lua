-- Ministry of the Allied: the party roll (ADDON_SPEC.md, sections 10.7 and 10.16).
-- Worked out from the book of records, so everyone holding the same records
-- sees the same members.
--
--   party.join    anyone  { p }      asking to join ("sh" or "ex")
--   party.decline Crown   { v, p }   turning a request down
--   party.admit   Crown   { v, p }   recording a member, once they've paid
--   party.leave   anyone  { p }      leaving your own party
--   party.remove  Crown   { v, p }   taking someone off the roll
--
-- Party money comes from the reasons on bank.move records (Bank.lua).
-- The Crown stands apart: a Crown rank can't ask or be admitted. Someone who
-- leaves waits 14 days before the other party can admit them.

local _, MOTA = ...
local Party = {}
MOTA.Party = Party

Party.FEE = 5 -- copper. TESTING: the Charter's fee is 5 gold, which is 50000
Party.WAIT = 14 * 86400
Party.NAMES = { sh = "the Silverhand", ex = "the Azeroth Exchange" }
Party.FUND_REASON = { sh = "party_sh", ex = "party_ex" }

local SKINS = { sh = "SILVERHAND", ex = "AZEROTH_EXCHANGE" }
local SEALS = { sh = "silverhand", ex = "exchange" }

local rules = MOTA.Book.rules
local function crown(author) return MOTA:IsCrown(author) end
rules["party.join"] = function() return true end
rules["party.leave"] = function() return true end
rules["party.decline"] = crown
rules["party.admit"] = crown
rules["party.remove"] = crown

local cache

local function build()
  local roll = { joined = {}, members = {}, pending = {}, left = {}, floor = {}, paid = {}, funds = { sh = 0, ex = 0 } }
  local list = MOTA.Book:Latest()
  for i = #list, 1, -1 do
    local r = list[i]
    local d = r.d or {}
    local p, v = d.p, d.v
    if r.k == "party.join" and SKINS[p] then
      if not roll.members[r.a] and not MOTA:IsCrown(r.a) then roll.pending[r.a] = { p = p, t = r.t } end
    elseif r.k == "party.decline" and v then
      if roll.pending[v] and roll.pending[v].p == p then roll.pending[v] = nil end
    elseif r.k == "party.admit" and v then
      local asked, left = roll.pending[v], roll.left[v]
      local waited = not left or left.p == p or r.t - left.t >= Party.WAIT
      if asked and asked.p == p and not roll.members[v] and not MOTA:IsCrown(v) and waited then
        roll.members[v] = p
        roll.joined[v] = r.t
        roll.pending[v] = nil
      end
    elseif (r.k == "party.leave" or r.k == "party.remove") then
      local who = r.k == "party.leave" and r.a or v
      local from = who and roll.members[who]
      if from then
        roll.members[who] = nil
        roll.left[who] = { p = from, t = r.t }
        roll.paid[who] = nil
        roll.floor[#roll.floor + 1] = { name = who, p = from, t = r.t }
      end
    elseif r.k == "bank.open" then
      -- Party funds count from when the books opened, as the ledger does.
      roll.funds = { sh = 0, ex = 0 }
      roll.openT = r.t
    elseif r.k == "bank.move" or r.k == "bank.fill" then
      for key, reason in pairs(Party.FUND_REASON) do
        if d.r == reason and type(d.amt) == "number" then
          local sign = d.io == "w" and -1 or 1
          if not roll.openT or (d.at or r.t) >= roll.openT then
            roll.funds[key] = roll.funds[key] + sign * d.amt
          end
          local who = r.k == "bank.fill" and d.who or r.a
          if d.io == "d" and who then
            roll.paid[who] = roll.paid[who] or {}
            roll.paid[who][key] = (roll.paid[who][key] or 0) + d.amt
          end
        end
      end
    end
  end
  return roll
end

function Party:Roll()
  if not cache then cache = build() end
  return cache
end

function Party:Of(name)
  return name and self:Roll().members[name]
end

-- Names on a party's roll, sorted.
function Party:Members(p)
  local out = {}
  for name, party in pairs(self:Roll().members) do
    if party == p then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- Requests waiting for the Crown, oldest first: { name, p, t, paid, confirmed }.
function Party:Requests()
  local out = {}
  for name, e in pairs(self:Roll().pending) do
    out[#out + 1] = { name = name, p = e.p, t = e.t, paid = self:Paid(name, e.p), confirmed = self:Confirmed(name) }
  end
  table.sort(out, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return a.name < b.name
  end)
  return out
end

-- Copper this person has tagged for a party since they last left it.
function Party:Paid(name, p)
  local paid = self:Roll().paid[name]
  return paid and paid[p] or 0
end

function Party:Confirmed(name)
  return MOTA.Bank ~= nil and MOTA.Bank:InLog(name, self.FEE)
end

function Party:Funds(p)
  return self:Roll().funds[p] or 0
end

-- When a person may next be admitted to party p (nil if they already may).
function Party:WaitUntil(name, p)
  local left = self:Roll().left[name]
  if not left or left.p == p then return nil end
  local at = left.t + self.WAIT
  if at > GetServerTime() then return at end
end

-- What the join button should say for me: label, enabled, action, note.
function Party:JoinState(p)
  local me, roll = MOTA.me, self:Roll()
  if not me or not MOTA.guild then return "Waiting for the guild", false end
  if MOTA:IsCrown(me) then return "The Crown stands apart", false, nil, "The Crown belongs to no party." end
  local mine = roll.members[me]
  if mine == p then return "Leave the party", true, "leave", "You are a member. Leaving is announced to the whole guild." end
  if mine then return "Leave your party first", false end
  local at = self:WaitUntil(me, p)
  if at then return "Can join on " .. date("%d %b", at), false, nil, "You left another party, so you must wait 14 days." end
  local asked = roll.pending[me]
  if asked and asked.p == p then
    local paid = self:Paid(me, p)
    if paid >= self.FEE then return "Awaiting the Crown", false, nil, "Your donation is noted. The Crown will record you as a member." end
    return "Awaiting your fee", false, nil, "Deposit " .. MOTA:Money(self.FEE) .. " in the guild bank and choose this party as the reason."
  end
  if asked then return "Already asked elsewhere", false end
  return "Ask to join", true, "ask", "Joining costs " .. MOTA:Money(self.FEE) .. ", paid into the guild bank. Leaving a party starts a 14-day wait."
end

function Party:Ask(p)
  local state = select(3, self:JoinState(p))
  if state ~= "ask" then return nil, "You can't ask to join just now." end
  local rec, err = MOTA.Book:Write("party.join", { p = p })
  if rec then
    MOTA:Print("Asked to join " .. self.NAMES[p] .. ". Now deposit " .. MOTA:Money(self.FEE) .. " in the guild bank and choose this party as the reason.")
  end
  return rec, err
end

function Party:Leave()
  local p = self:Of(MOTA.me)
  if not p then return nil, "You aren't in a party." end
  return MOTA.Book:Write("party.leave", { p = p })
end

function Party:Admit(name)
  local asked = self:Roll().pending[name]
  if not asked then return nil, "They haven't asked to join." end
  if self:WaitUntil(name, asked.p) then return nil, "Their 14-day wait isn't over." end
  return MOTA.Book:Write("party.admit", { v = name, p = asked.p })
end

function Party:Decline(name)
  local asked = self:Roll().pending[name]
  if not asked then return nil, "They haven't asked to join." end
  return MOTA.Book:Write("party.decline", { v = name, p = asked.p })
end

-- What the window's skin reads (UI/Skin.lua).
function MOTA:PartyOf(name)
  return SKINS[Party:Of(name)]
end

local function changed()
  cache = nil
  MOTA:Fire("PARTY_CHANGED")
end

MOTA:Listen("GUILD_READY", changed)
MOTA:Listen("ROSTER_UPDATED", changed)
MOTA:Listen("RECORD_ADDED", function(self, rec)
  local d = rec.d or {}
  if rec.k:sub(1, 5) == "bank." then return changed() end
  if rec.k:sub(1, 6) ~= "party." then return end
  local before = Party:Of(self.me)
  cache = nil
  local after = Party:Of(self.me)
  if before ~= after and self.Skin then self.Skin:Refresh(true) end
  self:Fire("PARTY_CHANGED")
  local H = self.Herald
  if not H or self.Book.replaying then return end
  if rec.k == "party.leave" or rec.k == "party.remove" then
    local who = rec.k == "party.leave" and rec.a or d.v
    H:Announce({ seal = SEALS[d.p] or "official", eyebrow = "Crossing the floor",
      title = self:Short(who) .. " leaves " .. (Party.NAMES[d.p] or "their party"),
      text = "No other party may admit them for 14 days.", button = { label = "Dismiss", style = "quiet" } })
  elseif rec.k == "party.admit" and d.v == self.me and after == d.p then
    H:Announce({ seal = SEALS[d.p] or "official", eyebrow = "By the Crown's record",
      title = "Welcome to " .. Party.NAMES[d.p], text = "Your party's Chamber is now open to you.",
      button = { label = "Open", style = "blue", page = 4 } })
  elseif rec.k == "party.join" and rec.a ~= self.me and self:IsCrown(self.me) then
    self:Print(self:Short(rec.a), "asks to join", (Party.NAMES[d.p] or "a party") .. ". Admit them in The Parties, on the Chamber ribbon, once they've paid.")
  end
end)

-- At login, tell the Crown what's waiting.
MOTA:Listen("GUILD_READY", function(self)
  C_Timer.After(8, function()
    if not self.me or not self:IsCrown(self.me) then return end
    local n = #Party:Requests()
    if n > 0 then self:Print(n, n == 1 and "citizen is" or "citizens are", "asking to join a party. See The Parties, on the Chamber ribbon.") end
  end)
end)
