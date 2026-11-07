-- Ministry of the Allied: the ledger (ADDON_SPEC.md, section 10.7).
-- The ledger is the reasons people give, worked out from the book of records.
-- The bank's real balance and money log only check it; they never add lines.
--
--   bank.open     Crown   { bal }                      opens the books; the latest stands
--   bank.move     anyone  { io, amt, r, note }         a player's own move (Bank.lua)
--   bank.fill     Crown   { who, io, amt, r, note }    a reason entered for someone else
--   bank.balance  anyone  { bal }                      the balance a member saw at the bank
--
-- Only the Crown can fill in reasons until a Minister of the Treasury can be
-- appointed. All amounts are in copper.

local _, MOTA = ...
local Ledger = {}
MOTA.Ledger = Ledger

local rules = MOTA.Book.rules
local function crown(author) return MOTA:IsCrown(author) end
rules["bank.open"] = crown
rules["bank.fill"] = crown
rules["bank.balance"] = function() return true end

local cache

local function build()
  local out = { lines = {}, moneyIn = 0, moneyOut = 0 }
  local list = MOTA.Book:Latest()
  for i = #list, 1, -1 do
    local r = list[i]
    local d = r.d or {}
    if r.k == "bank.open" and type(d.bal) == "number" then
      out.open = { t = r.t, bal = d.bal, by = r.a }
      out.lines, out.moneyIn, out.moneyOut = {}, 0, 0
      out.balance, out.balanceAt = d.bal, r.t
    elseif out.open and r.k == "bank.balance" and type(d.bal) == "number" then
      out.balance, out.balanceAt = d.bal, r.t
    elseif out.open and (r.k == "bank.move" or r.k == "bank.fill") and type(d.amt) == "number"
      and (d.at or r.t) >= out.open.t then -- answered later, but it moved before the count: already counted
      local line = { t = d.at or r.t, who = r.k == "bank.fill" and MOTA:Bare(d.who) or r.a, io = d.io, amt = d.amt,
        r = d.r, note = d.note, entered = r.k == "bank.fill" and r.a or nil }
      out.lines[#out.lines + 1] = line
      if d.io == "w" then out.moneyOut = out.moneyOut + d.amt else out.moneyIn = out.moneyIn + d.amt end
    end
  end
  if out.open then
    out.expected = out.open.bal + out.moneyIn - out.moneyOut
    out.unexplained = (out.balance or out.expected) - out.expected
    local party = MOTA.Party:Funds("sh") + MOTA.Party:Funds("ex")
    out.treasury = out.expected - party
  end
  return out
end

function Ledger:Get()
  if not cache then cache = build() end
  return cache
end

-- Lines newest first, one page at a time.
function Ledger:Page(first, count)
  local lines, out = self:Get().lines, {}
  for i = #lines - first + 1, math.max(1, #lines - first - count + 2), -1 do out[#out + 1] = lines[i] end
  return out, #lines
end

local LOG_IO = { deposit = "d", withdraw = "w", repair = "w" }

-- Recent money log entries the ledger has no line for, as seen on this
-- computer only. Each ledger line can answer for one log entry. A log entry
-- only gives its age in hours, so one from before the books opened can show
-- here for up to an hour.
function Ledger:Unmatched()
  local data, out = self:Get(), {}
  if not data.open then return out end
  local used = {}
  for _, e in ipairs(MOTA.guild and MOTA.guild.bankLog or {}) do
    local io = LOG_IO[e.kind]
    if io and (not e.latest or e.latest >= data.open.t) then
      local found = false
      for n, line in ipairs(data.lines) do
        if not used[n] and line.who == e.name and line.io == io and line.amt == e.amount then
          used[n], found = true, true
          break
        end
      end
      if not found then out[#out + 1] = e end
    end
  end
  return out
end

-- Opening again restarts the ledger: the latest opening stands.
function Ledger:OpenBooks()
  local bal = MOTA.Bank.seenBalance
  if bal == nil then return nil, "Open the guild bank first, so the balance can be counted." end
  return MOTA.Book:Write("bank.open", { bal = bal })
end

-- A member saw the balance at the bank: share it if the guild doesn't have it.
function Ledger:SawBalance(bal)
  local data = self:Get()
  if data.open and data.balance ~= bal then MOTA.Book:Write("bank.balance", { bal = bal }) end
end

local function changed()
  cache = nil
  MOTA:Fire("LEDGER_CHANGED")
end
MOTA:Listen("GUILD_READY", changed)
MOTA:Listen("PARTY_CHANGED", changed)
MOTA:Listen("BANK_LOG_READ", function() MOTA:Fire("LEDGER_CHANGED") end)
