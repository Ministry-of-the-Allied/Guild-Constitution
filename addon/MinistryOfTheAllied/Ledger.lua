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
-- The Crown fills in any entry; the Cabinet's Minister of the Treasury, any
-- but party money (Charter 3.2: party funds are the Crown's to handle).
local PARTY_REASONS = { party_sh = true, party_ex = true }
function Ledger:Minister()
  local gov = MOTA.Elect and MOTA.Elect:Government()
  return gov and gov.p and MOTA.Bench:Holder(gov.p, "treasury")
end
function Ledger:CanFill(name, reason)
  if not name then return false end
  if MOTA:IsCrown(name) then return true end
  return name == self:Minister() and not PARTY_REASONS[reason]
end
rules["bank.fill"] = function(a, rec) return Ledger:CanFill(a, rec and rec.d and rec.d.r) end
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

-- Money in and out this government's term (or since the books opened, if
-- that's later, or there's no government yet).
function Ledger:ThisTerm()
  local data = self:Get()
  if not data.open then return 0, 0 end
  local gov = MOTA.Elect and MOTA.Elect:Government()
  local from = math.max(data.open.t, gov and gov.t or 0)
  local moneyIn, moneyOut = 0, 0
  for _, line in ipairs(data.lines) do
    if line.t >= from then
      if line.io == "w" then moneyOut = moneyOut + line.amt else moneyIn = moneyIn + line.amt end
    end
  end
  return moneyIn, moneyOut
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

-- While the books are closed, nothing at the bank reaches the ledger. A King
-- or Crown rank gets a herald that stays until they act on it, each login,
-- until someone opens the books. At the bank, its button opens them there.
local closedHerald

local function booksClosed()
  return MOTA.me and MOTA:IsCrown(MOTA.me) and not Ledger:Get().open
end

local function remindClosed()
  if not booksClosed() or not MOTA.Herald then return end
  local atBank = MOTA.Bank.seenBalance ~= nil
  local h = {
    seal = "treasury", eyebrow = "The Treasury", stay = false,
    title = "The books are closed",
    text = atBank and ("Open them now at " .. MOTA:Money(MOTA.Bank.seenBalance) .. ". Until then, nothing at the bank is logged.")
      or "Nothing at the bank is logged until a King opens them. Visit the guild bank, then press Open the books.",
    button = atBank and { label = "Open", style = "blue", onPress = function()
      local _, err = Ledger:OpenBooks()
      if err then MOTA:Print(err) end
    end } or { label = "Open", style = "blue", page = 5 },
    onGone = function(h) if closedHerald == h then closedHerald = nil end end,
  }
  if closedHerald then MOTA.Herald:Close(closedHerald) end
  closedHerald = h
  MOTA.Herald:Announce(h, true) -- shown even with heralds switched off
end

function Ledger:ClosedHerald() return closedHerald end

-- After the first catch-up, so a copy that was offline doesn't nag for nothing.
MOTA:Listen("GUILD_READY", function() C_Timer.After(30, remindClosed) end)
-- At the bank: the balance is counted, so the herald can open the books itself.
MOTA:Listen("BANK_LOG_READ", function()
  if booksClosed() and not (closedHerald and closedHerald.button.onPress) then remindClosed() end
end)
MOTA:Listen("RECORD_ADDED", function(self, rec)
  if rec.k == "bank.open" and closedHerald and self.Herald then self.Herald:Close(closedHerald) end
end)
