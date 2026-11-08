-- Ministry of the Allied: one player, many characters (Duncan, 2026-11-08).
-- A player may vote on any of their characters, but only once per account,
-- and their party membership is the account's, not one character's.
--
-- Each character writes its account's key to the book once:
--   acct.link  anyone  { h }   "this character belongs to account h"
--
-- The key is a one-way hash of the player's BattleTag, the same on every
-- computer and every WoW licence on one Battle.net account; nobody sees the
-- BattleTag itself. If the game gives no BattleTag, it's a random ID kept in
-- the account-wide saved variables (MOTADB.accountId), shared by every
-- character on this WoW account on this computer.
--
-- A character with no link yet is its own account ("c:Name").
-- Limits: two separate Battle.net accounts can't be linked by any add-on, and
-- a tampered add-on could claim a false key. Those are for the Crown and Court.

local _, MOTA = ...
local Account = {}
MOTA.Account = Account

local function str(v, max) return type(v) == "string" and v ~= "" and #v <= max end
MOTA.Book.rules["acct.link"] = function(a, rec) return str(rec and rec.d and rec.d.h, 24) end

-- Two 32-bit rolling hashes of the text, as 16 hex digits.
local function hash(text)
  local h1, h2 = 5381, 52711
  for i = 1, #text do
    local b = text:byte(i)
    h1 = (h1 * 33 + b) % 4294967296
    h2 = (h2 * 31 + b * 7 + 1) % 4294967296
  end
  return string.format("%08x%08x", h1, h2)
end
Account.Hash = hash

-- This player's key, worked out on this computer.
function Account:MyKey()
  if self.myKey then return self.myKey end
  local tag = BNGetInfo and select(2, BNGetInfo())
  if type(tag) == "string" and tag ~= "" then
    self.myKey = "b" .. hash("MOTA|" .. tag:lower())
  else
    local db = MOTA.db
    if db then
      db.accountId = db.accountId or (GetServerTime() .. "." .. math.random(100000, 999999))
      self.myKey = "a" .. hash("MOTA|" .. db.accountId)
    end
  end
  return self.myKey
end

local cache
local function build()
  local c = { key = {}, names = {}, first = {} }
  local list = MOTA.Book:Latest()
  for i = #list, 1, -1 do -- oldest first: a character's newest link wins
    local r = list[i]
    if r.k == "acct.link" and r.d and str(r.d.h, 24) then
      c.key[r.a] = r.d.h
      c.first[r.a] = c.first[r.a] or r.t
    end
  end
  for name, h in pairs(c.key) do
    c.names[h] = c.names[h] or {}
    table.insert(c.names[h], name)
  end
  for _, names in pairs(c.names) do
    table.sort(names, function(a, b)
      if c.first[a] ~= c.first[b] then return c.first[a] < c.first[b] end
      return a < b
    end)
  end
  return c
end

local function get()
  if not cache then cache = build() end
  return cache
end

-- The account a character belongs to.
function Account:Key(name)
  name = MOTA:Bare(name)
  if not name then return nil end
  if MOTA:IsMe(name) and self:MyKey() then return self:MyKey() end
  return get().key[name] or ("c:" .. name)
end

-- Every character on the same account as name, the first linked first.
function Account:Alts(name)
  name = MOTA:Bare(name)
  if not name then return {} end
  local names = get().names[self:Key(name)]
  if not names then return { name } end
  local out, has = {}, false
  for _, n in ipairs(names) do
    out[#out + 1] = n
    has = has or n == name
  end
  if not has then table.insert(out, 1, name) end
  return out
end

function Account:Same(a, b)
  return a ~= nil and b ~= nil and self:Key(a) == self:Key(b)
end

-- Players' accounts as groups of characters, for the Kings: only those with
-- more than one character in the guild.
function Account:Groups()
  local out = {}
  for _, names in pairs(get().names) do
    local inGuild = {}
    for _, n in ipairs(names) do
      if MOTA.roster[n] or MOTA:IsMe(n) then inGuild[#inGuild + 1] = n end
    end
    if #inGuild > 1 then out[#out + 1] = inGuild end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

-- The first character of an alt's account, or nil if it's that one (or alone).
-- The minimap seal's tooltip shows it (MOTA:OnlineSections).
function MOTA:MainOf(name)
  local alts = Account:Alts(name)
  if #alts > 1 and alts[1] ~= self:Bare(name) then return alts[1] end
end

-- True if any character on name's account holds a Crown rank. The Crown
-- stands apart, on every character.
function MOTA:IsCrownAccount(name)
  for _, n in ipairs(Account:Alts(name)) do
    if self:IsCrown(n) then return true end
  end
  return false
end

-- Counts accounts rather than characters, among the names given as a set.
function Account:CountPlayers(set)
  local seen, n = {}, 0
  for name in pairs(set) do
    local k = self:Key(name)
    if not seen[k] then seen[k], n = true, n + 1 end
  end
  return n
end

MOTA:Listen("RECORD_ADDED", function(self, rec)
  if rec.k == "acct.link" then
    cache = nil
    self:Fire("ACCOUNT_CHANGED")
  end
end)
Account.LINK_DELAY = 3 -- seconds after the guild is ready
MOTA:Listen("GUILD_READY", function(self)
  cache = nil
  -- Write this character's link, if the book doesn't have it already.
  C_Timer.After(Account.LINK_DELAY, function()
    if not self.me or not self.guild then return end
    local key = Account:MyKey()
    if key and get().key[self.me] ~= key then self.Book:Write("acct.link", { h = key }) end
  end)
end)
MOTA:Listen("ME_LEARNED", function() cache = nil end)
