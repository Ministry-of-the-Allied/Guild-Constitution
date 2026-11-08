-- Ministry of the Allied: the Royal Lottery (Duncan, 2026-11-08).
-- Tickets are bought at the guild bank: deposit gold and give "Lottery" as
-- the reason (UI/BankPrompt.lua). Each whole ticket price buys one ticket.
-- The winner takes 70% of the pot; the Treasury keeps 30%.
--
--   lottery.open  the Crown or the Minister of Games  { name, price, closes, c }
--   lottery.draw  the one who opened it                { id, s }
--   lottery.cancel  the one who opened it, or the Crown  { id }  before the draw
--
-- A fair draw that every copy can check: on opening, the organiser's add-on
-- picks a secret and publishes only its hash (c). At the draw it reveals the
-- secret (s); the winning ticket comes from the secret and the list of
-- tickets, which was fixed when sales closed. The organiser can't change the
-- secret once tickets are sold, and can't buy tickets in their own draw.
-- Both hashes are SHA-256 (Sha256.lua): the secret can't be swapped for
-- another with the same hash, and every ticket has an even chance.
-- If the organiser hasn't drawn within 7 days of the close, the Crown or the
-- Minister of Games may draw without a secret, from the tickets alone.
--
-- The prize is paid by hand: a withdrawal with "Lottery payout" as its reason.
-- A cancelled lottery owes every ticket back, paid the same way; a payout goes
-- to the newest lottery that still owes something (a prize or refunds).

local _, MOTA = ...
local Lottery = {}
MOTA.Lottery = Lottery

Lottery.SHARE = 0.7       -- the winner's part of the pot
Lottery.MIN_PRICE = 100   -- copper: 1 silver
Lottery.MAX_DAYS = 14
Lottery.LATE = 7 * 86400  -- after the close, when someone else may draw
Lottery.REASON, Lottery.PRIZE_REASON = "lottery", "lottery_prize"

local function str(v, max) return type(v) == "string" and v ~= "" and #v <= max end
local function hash(text) return MOTA.Sha256(text) end
local function canRun(name) return MOTA.Games and MOTA.Games:CanRun(name) end

MOTA.Book.rules["lottery.open"] = function(a, rec)
  local d = rec and rec.d or {}
  return canRun(a) and str(d.name, 40) and type(d.price) == "number" and d.price >= Lottery.MIN_PRICE
    and type(d.closes) == "number" and str(d.c, 64)
end
MOTA.Book.rules["lottery.draw"] = function(a, rec)
  local d = rec and rec.d or {}
  -- The organiser draws, even if they've left the post since; or, late, another.
  return str(d.id, 60) and (d.s == nil or str(d.s, 40)) and (canRun(a) or d.id:match("^(.-)#%d+$") == a)
end
MOTA.Book.rules["lottery.cancel"] = function(a, rec)
  local d = rec and rec.d or {}
  return str(d.id, 60) and (MOTA:IsCrown(a) or d.id:match("^(.-)#%d+$") == a)
end

-- The winning ticket, 1 to total, from the secret and the tickets in order.
-- The first 13 hex digits of the hash are a number below 2^52, exact in Lua;
-- its remainder by the number of tickets favours none by more than one in
-- billions. They're read in two parts: the game's tonumber(x, 16) stops at
-- 32 bits, and gives the same largest number for anything longer.
function Lottery:Pick(secret, tickets)
  local names = {}
  for i, t in ipairs(tickets) do names[i] = t.who end
  local h = hash((secret or "") .. "|" .. table.concat(names, ","))
  local n = tonumber(h:sub(1, 7), 16) * 16777216 + tonumber(h:sub(8, 13), 16) -- 28 bits, then 24
  return (n % #tickets) + 1
end

local cache
local function build()
  local out = { all = {} }
  local byId = {}
  local list = MOTA.Book:Latest()
  for i = #list, 1, -1 do -- oldest first
    local r = list[i]
    local d = r.d or {}
    if r.k == "lottery.open" and type(d.price) == "number" and type(d.closes) == "number" then
      local id = r.a .. "#" .. r.n
      local L = { id = id, by = r.a, t = r.t, name = d.name, price = d.price, closes = d.closes, c = d.c,
        tickets = {}, refused = {}, paid = 0 }
      byId[id] = L
      out.all[#out.all + 1] = L
    elseif (r.k == "bank.move" or r.k == "bank.fill") and type(d.amt) == "number" then
      local who = r.k == "bank.fill" and d.who or r.a
      local at = d.at or r.t
      if d.io == "d" and d.r == Lottery.REASON and who then
        -- Tickets go to the lottery that was selling when the gold went in.
        for j = #out.all, 1, -1 do
          local L = out.all[j]
          if at >= L.t and at <= L.closes and not L.drawn and (not L.cancelled or at < L.cancelled.t) then
            if MOTA.Account:Same(who, L.by) then
              L.refused[who] = (L.refused[who] or 0) + d.amt
            else
              for _ = 1, math.floor(d.amt / L.price) do L.tickets[#L.tickets + 1] = { who = who, t = at } end
            end
            break
          end
        end
      elseif d.io == "w" and d.r == Lottery.PRIZE_REASON then
        for j = #out.all, 1, -1 do
          local L = out.all[j]
          local ended = L.drawn or L.cancelled
          if ended and at >= ended.t and L.paid < (L.owe or 0) then L.paid = L.paid + d.amt break end
        end
      end
    elseif r.k == "lottery.draw" and byId[d.id] and not byId[d.id].drawn then
      local L = byId[d.id]
      local fair = d.s ~= nil and hash(d.s) == L.c and r.a == L.by
      local late = d.s == nil and r.t >= L.closes + Lottery.LATE
      if r.t >= L.closes and (fair or late) then
        L.drawn = { t = r.t, by = r.a, s = d.s }
        if #L.tickets > 0 then
          L.win = Lottery:Pick(d.s, L.tickets)
          L.winner = L.tickets[L.win].who
          L.owe = math.floor(#L.tickets * L.price * Lottery.SHARE)
        end
      end
    elseif r.k == "lottery.cancel" and byId[d.id] and not byId[d.id].drawn and not byId[d.id].cancelled then
      local L = byId[d.id]
      L.cancelled = { t = r.t, by = r.a }
      L.owe = #L.tickets * L.price -- every ticket is owed back
    end
  end
  for _, L in ipairs(out.all) do
    L.pot = #L.tickets * L.price
    L.prize = math.floor(L.pot * Lottery.SHARE)
    L.treasury = L.pot - L.prize
  end
  out.cur = out.all[#out.all]
  return out
end

local function get()
  if not cache then cache = build() end
  return cache
end

-- The latest lottery, drawn or not.
function Lottery:Current() return get().cur end
function Lottery:All() return get().all end

-- "selling", "closed" (waiting for the draw), "drawn", "cancelled", or nil.
function Lottery:Stage(L)
  L = L or self:Current()
  if not L then return nil end
  if L.drawn then return "drawn" end
  if L.cancelled then return "cancelled" end
  if GetServerTime() <= L.closes then return "selling" end
  return "closed"
end

-- How many tickets a player holds, on all their characters.
function Lottery:TicketsOf(name, L)
  L = L or self:Current()
  local n = 0
  if not L then return 0 end
  for _, t in ipairs(L.tickets) do
    if MOTA.Account:Same(t.who, name) then n = n + 1 end
  end
  return n
end

-- Players taking part (one per account), for the games log.
function Lottery:Players(L)
  local seen, out = {}, {}
  for _, t in ipairs(L.tickets) do
    local k = MOTA.Account:Key(t.who)
    if not seen[k] then seen[k] = true; out[#out + 1] = t.who end
  end
  return out
end

local function secrets()
  MOTA.db.lotterySecrets = MOTA.db.lotterySecrets or {}
  return MOTA.db.lotterySecrets
end

function Lottery:Open(name, gold, days)
  if not canRun(MOTA.me) then return nil, "Only the Crown and the Minister of Games run the lottery." end
  local s = self:Stage()
  if s == "selling" or s == "closed" then return nil, "A lottery is already under way." end
  name = strtrim(name or "")
  if name == "" then name = "The Royal Lottery" end
  if #name > 40 then return nil, "Keep the name to 40 letters." end
  local price = math.floor((tonumber(gold) or 0) * 10000 + 0.5)
  if price < self.MIN_PRICE then return nil, "A ticket costs at least " .. MOTA:Money(self.MIN_PRICE) .. "." end
  days = tonumber(days)
  if not days or days < 1 or days > self.MAX_DAYS then return nil, "Sales run 1 to " .. self.MAX_DAYS .. " days." end
  local secret = GetServerTime() .. "." .. math.random(100000000, 999999999) .. "." .. math.random(100000000, 999999999)
  local closes = GetServerTime() + math.floor(days * 86400)
  local rec, err = MOTA.Book:Write("lottery.open", { name = name, price = price, closes = closes, c = hash(secret) })
  if rec then secrets()[rec.a .. "#" .. rec.n] = secret end
  return rec, err
end

function Lottery:Draw()
  local L = self:Current()
  local stage = self:Stage(L)
  if stage == "selling" then return nil, "Ticket sales are still open, until " .. date("%d %b %H:%M", L.closes) .. "." end
  if stage ~= "closed" then return nil, "There's no lottery waiting to be drawn." end
  if not canRun(MOTA.me) then return nil, "Only the Crown and the Minister of Games draw the lottery." end
  local secret = secrets()[L.id]
  if MOTA:IsMe(L.by) and not secret then return nil, "This computer has lost the lottery's secret. Another may draw it from " .. date("%d %b", L.closes + self.LATE) .. "." end
  if not MOTA:IsMe(L.by) then
    if GetServerTime() < L.closes + self.LATE then
      return nil, MOTA:Short(L.by) .. " opened this lottery and draws it. If they haven't by " .. date("%d %b", L.closes + self.LATE) .. ", you may."
    end
    secret = nil
  end
  local rec, err = MOTA.Book:Write("lottery.draw", { id = L.id, s = secret })
  if not rec then return nil, err end
  L = self:Current()
  if L.winner and MOTA.Games then
    -- Into the games log: the winner first, then everyone else who played.
    local places = { L.winner }
    for _, who in ipairs(self:Players(L)) do
      if not MOTA.Account:Same(who, L.winner) and #places < MOTA.Games.MAX_PLACES then places[#places + 1] = who end
    end
    MOTA.Games:Record("lottery", L.name, places)
  end
  return rec
end

-- What's left to pay out: the winner's prize, or a cancelled lottery's refunds.
function Lottery:Owed(L)
  L = L or self:Current()
  if not L or not L.owe then return 0 end
  return math.max(0, L.owe - L.paid)
end

-- A cancelled lottery's refunds, one per player: { { name, amt } }, most first.
function Lottery:Refunds(L)
  L = L or self:Current()
  local out, byKey = {}, {}
  if not L or not L.cancelled then return out end
  for _, t in ipairs(L.tickets) do
    local k = MOTA.Account:Key(t.who)
    if not byKey[k] then
      byKey[k] = { name = t.who, amt = 0 }
      out[#out + 1] = byKey[k]
    end
    byKey[k].amt = byKey[k].amt + L.price
  end
  table.sort(out, function(a, b)
    if a.amt ~= b.amt then return a.amt > b.amt end
    return a.name < b.name
  end)
  return out
end

-- The organiser, or any King, may cancel before the draw.
function Lottery:CanCancel(name, L)
  L = L or self:Current()
  local s = self:Stage(L)
  if s ~= "selling" and s ~= "closed" then return false end
  return MOTA:IsCrown(name) or name == L.by
end

function Lottery:Cancel()
  local L = self:Current()
  local s = self:Stage(L)
  if s ~= "selling" and s ~= "closed" then return nil, "There's no lottery to cancel." end
  if not self:CanCancel(MOTA.me, L) then return nil, "Only " .. MOTA:Short(L.by) .. ", who opened it, or the Crown can cancel it." end
  return MOTA.Book:Write("lottery.cancel", { id = L.id })
end

-- One line on the lottery now, for /mota lottery and the Throne Room.
function Lottery:Line(L)
  L = L or self:Current()
  local stage = self:Stage(L)
  if not stage then return "No lottery has been run yet." end
  local pot = MOTA:Money(L.pot) .. " in the pot, " .. #L.tickets .. (#L.tickets == 1 and " ticket" or " tickets")
  if stage == "selling" then
    return "Tickets " .. MOTA:Money(L.price) .. " each · " .. pot .. " · sales close " .. date("%d %b %H:%M", L.closes)
  elseif stage == "closed" then
    return "Sales are closed · " .. pot .. " · waiting for " .. MOTA:Short(L.by) .. " to draw"
  elseif stage == "cancelled" then
    local owed = self:Owed(L)
    if #L.tickets == 0 then return "Cancelled, with no tickets sold." end
    return "Cancelled · " .. (owed > 0 and (MOTA:Money(owed) .. " of refunds still to pay") or "everyone refunded")
  elseif L.winner then
    local owed = self:Owed(L)
    return MOTA:Short(L.winner) .. " won " .. MOTA:Money(L.prize) .. (owed > 0 and " · not yet paid" or " · paid")
  end
  return "Drawn, with no tickets sold."
end

---------------------------------------------------------------------------
-- Heralds and notes
---------------------------------------------------------------------------

local function changed()
  cache = nil
  MOTA:Fire("LOTTERY_CHANGED")
end
MOTA:Listen("GUILD_READY", changed)
MOTA:Listen("CAUGHT_UP", changed)
MOTA:Listen("ACCOUNT_CHANGED", changed)

MOTA:Listen("RECORD_ADDED", function(self, rec)
  local d = rec.d or {}
  local k = rec.k
  if k ~= "lottery.open" and k ~= "lottery.draw" and k ~= "lottery.cancel" and not ((k == "bank.move" or k == "bank.fill") and (d.r == Lottery.REASON or d.r == Lottery.PRIZE_REASON)) then
    if k == "party.post" or k == "ballot.result" then cache = nil end
    return
  end
  local before = Lottery:Current()
  local mineBefore = before and Lottery:TicketsOf(self.me, before) or 0
  changed()
  if self.Book.replaying then return end
  local L = Lottery:Current()
  local H = self.Herald
  if k == "lottery.open" and L and H then
    H:Announce({ seal = "treasury", eyebrow = "The Royal Lottery", title = tostring(d.name) .. " is open",
      text = "Tickets " .. self:Money(d.price) .. " each, bought at the guild bank (choose Lottery as the reason). The draw is after " .. date("%d %b", d.closes) .. ". The winner takes 70% of the pot.",
      button = { label = "Dismiss", style = "quiet" } })
  elseif k == "lottery.draw" and L and L.drawn and H then
    if L.winner then
      local mine = self.Account:Same(L.winner, self.me)
      H:Announce({ seal = "treasury", eyebrow = "The Royal Lottery",
        title = mine and "You've won the lottery!" or (self:Short(L.winner) .. " wins the lottery"),
        text = "Ticket " .. L.win .. " of " .. #L.tickets .. " takes " .. self:Money(L.prize) .. ". " .. self:Money(L.treasury) .. " goes to the Treasury." .. (mine and " The prize is paid from the guild bank." or ""),
        button = { label = "Dismiss", style = "quiet" } })
    else
      self:Print("The lottery was drawn, but no tickets were sold.")
    end
  elseif k == "lottery.cancel" and L and L.cancelled and H then
    local mine = 0
    for _, e in ipairs(Lottery:Refunds(L)) do
      if self.Account:Same(e.name, self.me) then mine = e.amt end
    end
    H:Announce({ seal = "treasury", eyebrow = "The Royal Lottery", title = L.name .. " is cancelled",
      text = (#L.tickets == 0 and "No tickets had been sold." or "Everyone who bought tickets gets their gold back from the guild bank.")
        .. (mine > 0 and (" You're owed " .. self:Money(mine) .. ".") or ""),
      button = { label = "Dismiss", style = "quiet" } })
  elseif (k == "bank.move" or k == "bank.fill") and d.r == Lottery.REASON and L then
    local who = k == "bank.fill" and d.who or rec.a
    if self:IsMe(who) then
      local n = Lottery:TicketsOf(self.me, L) - mineBefore
      if L.refused[who] then
        self:Print("You opened this lottery, so you can't buy tickets in it. Ask the Crown to refund your deposit.")
      elseif n > 0 then
        self:Print("You bought", n, n == 1 and "ticket" or "tickets", "in", L.name .. ". You hold", Lottery:TicketsOf(self.me, L), "in all.")
      elseif Lottery:Stage(L) ~= "selling" then
        self:Print("No lottery is selling tickets just now, so that deposit bought none.")
      else
        self:Print("That's less than a ticket (" .. self:Money(L.price) .. "), so it bought none.")
      end
    end
  end
end)

-- The organiser is reminded to draw, once sales have closed.
MOTA:Listen("GUILD_READY", function(self)
  C_Timer.After(20, function()
    local L = Lottery:Current()
    if L and Lottery:Stage(L) == "closed" and self:IsMe(L.by) then
      self:Print("Ticket sales for", L.name, "have closed. Draw it with /mota lottery draw.")
    end
  end)
end)
