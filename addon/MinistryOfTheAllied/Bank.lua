-- Ministry of the Allied: watching the guild bank (ADDON_SPEC.md, section 10.7).
-- When this player deposits or withdraws gold, the reason prompt asks why
-- (UI/BankPrompt.lua) and the answer becomes a public record:
--
--   bank.move  anyone  { io = "d" | "w", amt = copper, r = reason, note, at = when it moved }
--
-- The move only counts once the game reports the balance changed, so a refused
-- withdrawal raises no prompt. Unanswered prompts are saved, and come back
-- after a reload or login. The money log is read when the bank opens or moves;
-- it's kept on this computer only, to check donations against.

local _, MOTA = ...
local Bank = {}
MOTA.Bank = Bank

local rules = MOTA.Book.rules
rules["bank.move"] = function() return true end

-- Copper as "5g 20s", dropping the parts that are zero.
function MOTA:Money(copper)
  copper = copper or 0
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 or #parts == 0 then parts[#parts + 1] = c .. (g == 0 and s == 0 and copper == 0 and "g" or "c") end
  return table.concat(parts, " ")
end

local awaiting -- { io, amt }: seen, but the balance hasn't changed yet
local hooked = {}

-- This character's unanswered moves.
function Bank:Pending()
  if not MOTA.db or not MOTA.me then return {} end
  MOTA.db.bankPrompts = MOTA.db.bankPrompts or {}
  MOTA.db.bankPrompts[MOTA.me] = MOTA.db.bankPrompts[MOTA.me] or {}
  return MOTA.db.bankPrompts[MOTA.me]
end

function Bank:Answer(reason, note)
  local list = self:Pending()
  local move = list[1]
  if not move then return nil end
  local rec, err
  if move.who then
    rec, err = MOTA.Book:Write("bank.fill", { who = move.who, io = move.io, amt = move.amt, r = reason, note = note })
  else
    rec, err = MOTA.Book:Write("bank.move", { io = move.io, amt = move.amt, r = reason, note = note, at = move.t })
  end
  if not rec then return nil, err end
  table.remove(list, 1)
  MOTA:Fire("BANK_PROMPT")
  return rec
end

-- The Crown gives the reason for a log entry nobody explained.
function Bank:AskFor(entry)
  local list = self:Pending()
  list[#list + 1] = { io = entry.kind == "deposit" and "d" or "w", amt = entry.amount, who = entry.name,
    repair = entry.kind == "repair" or nil, t = GetServerTime() }
  MOTA:Fire("BANK_PROMPT")
end

local function query()
  if QueryGuildBankLog then QueryGuildBankLog((MAX_GUILDBANK_TABS or 8) + 1) end
end

function Bank:ReadLog()
  if not MOTA.guild or not GetNumGuildBankMoneyTransactions or not GetGuildBankMoneyTransaction then return end
  local entries = {}
  for i = 1, GetNumGuildBankMoneyTransactions() or 0 do
    local kind, name, amount, years, months, days, hours = GetGuildBankMoneyTransaction(i)
    local age = (years or 0) * 31536000 + (months or 0) * 2592000 + (days or 0) * 86400 + (hours or 0) * 3600
    entries[#entries + 1] = { kind = kind, name = MOTA:Bare(name), amount = amount, latest = GetServerTime() - age }
  end
  MOTA.guild.bankLog = entries
  self:SeeBalance()
  MOTA:Fire("BANK_LOG_READ")
end

-- The balance is only trusted once the bank has answered, not as it opens.
function Bank:SeeBalance()
  if not GetGuildBankMoney then return end
  self.seenBalance = GetGuildBankMoney()
  if MOTA.Ledger then MOTA.Ledger:SawBalance(self.seenBalance) end
end

-- Is there a deposit of at least this much by this person in the last log read?
function Bank:InLog(name, amount)
  for _, e in ipairs(MOTA.guild and MOTA.guild.bankLog or {}) do
    if e.kind == "deposit" and e.name == name and (e.amount or 0) >= amount then return true end
  end
  return false
end

-- Safe to call again: functions the game adds later get hooked too.
function Bank:Install()
  for name, io in pairs({ DepositGuildBankMoney = "d", WithdrawGuildBankMoney = "w" }) do
    if _G[name] and not hooked[name] then
      hooked[name] = true
      hooksecurefunc(name, function(amount)
        if type(amount) == "number" and amount > 0 then awaiting = { io = io, amt = amount } end
      end)
    end
  end
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANK_UPDATE_MONEY", "GUILDBANKLOG_UPDATE" }) do
  pcall(watcher.RegisterEvent, watcher, event) -- a client without one would raise an error
end
watcher:SetScript("OnEvent", function(_, event)
  if event == "GUILDBANKLOG_UPDATE" then
    Bank:ReadLog()
  elseif event == "GUILDBANKFRAME_OPENED" then
    query()
  elseif event == "GUILDBANK_UPDATE_MONEY" then
    query()
    Bank:SeeBalance()
    if awaiting then
      local list = Bank:Pending()
      list[#list + 1] = { io = awaiting.io, amt = awaiting.amt, t = GetServerTime() }
      awaiting = nil
      MOTA:Fire("BANK_PROMPT")
    end
  end
end)

MOTA:On("PLAYER_LOGIN", function() Bank:Install() end)
MOTA:Listen("GUILD_READY", function(self) self:Fire("BANK_PROMPT") end)
