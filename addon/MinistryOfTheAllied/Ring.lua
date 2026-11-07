-- Ministry of the Allied: The Ring, the monthly duelling tournament (ADDON_SPEC.md, section 11).
-- Everything is worked out from the book of records, so every member who holds
-- the same records sees the same tournament.
--
--   ring.create   organiser { season, bracket, fee (gold), closes (server time) }
--                 Records can't be edited, so nobody can change the terms once
--                 a tournament is open.
--
-- The organisers are whoever holds the Minister of War guild rank, and the
-- Crown, who hold every power the government does. No tournament can be opened
-- until someone holds that rank.
--   ring.enter    anyone   { id }            signing yourself up
--   ring.withdraw anyone   { id }            before the draw
--   ring.paid     organiser   { id, p, paid }   by hand, for anyone paying without the add-on;
--                                               paid = false also marks a refund as given
--
-- A fee is paid by depositing it in the guild bank and choosing "Ring entry
-- fee" (Bank.lua). Nobody holds a place until they've paid: the first eight paid
-- are in, and anyone else who paid and has no place is owed a refund.
--   ring.bout     organiser   { id, s, x, y }   one per quarter-final (y empty is a bye)
--   ring.result   organiser   { id, s, w }      the first result for a bout stands
--
-- Bouts are numbered 1-4 quarter-finals, 5-6 semi-finals, 7 The Final.

local _, MOTA = ...
local Ring = {}
MOTA.Ring = Ring

Ring.MAX_ENTRANTS = 8
Ring.GUILD_CUT = 0.10
local CALL_DELAY = 1 -- seconds, so one draw's several records make one herald

local FEEDERS = { [5] = { 1, 2 }, [6] = { 3, 4 }, [7] = { 5, 6 } }

local function isMinister(name) return MOTA:RankOf(name) == MOTA.CONST.MINISTER_OF_WAR_RANK end
local function organiser(author) return MOTA:IsCrown(author) or isMinister(author) end
local rules = MOTA.Book.rules
rules["ring.create"] = organiser
rules["ring.paid"] = organiser
rules["ring.bout"] = organiser
rules["ring.result"] = organiser
rules["ring.enter"] = function() return true end
rules["ring.withdraw"] = function() return true end

---------------------------------------------------------------------------
-- Working out the tournament from the records
---------------------------------------------------------------------------

local function settleBouts(cur)
  local results, bouts = cur.results, {}
  for s = 1, 7 do
    local b = { slot = s }
    local settled = true
    if s <= 4 then
      local q = cur.draw[s]
      if q then b.a, b.b = q.x, q.y end
    else
      local f = FEEDERS[s]
      for i, side in ipairs({ "a", "b" }) do
        local feeder = bouts[f[i]]
        b[side] = feeder.w
        if not feeder.settled then settled = false end
      end
    end
    if settled then
      if b.a and b.b then
        local w = results[s]
        if w == b.a or w == b.b then b.w = w end
        b.settled = b.w ~= nil
      else
        b.w = b.a or b.b -- a bye, or an empty bout
        b.bye = b.w ~= nil
        b.settled = true
      end
    end
    bouts[s] = b
  end
  cur.bouts = bouts
  cur.next = nil
  for s = 1, 7 do
    local b = bouts[s]
    if b.a and b.b and not b.w then cur.next = b break end
  end
  cur.champion = bouts[7].settled and bouts[7].w or nil
end

-- Each record names its tournament, so a record is counted even if it sorts
-- ahead of the tournament's own (two records in the same second, say).
local function build()
  local list = MOTA.Book:Latest()
  local byId, order = {}, {}
  for i = #list, 1, -1 do
    local r = list[i]
    if r.k == "ring.create" then
      local d = r.d or {}
      local t = { id = r.a .. "#" .. r.n, season = d.season, bracket = d.bracket, fee = d.fee or 0, closes = d.closes,
        entrants = {}, draw = {}, results = {}, drawn = false, paid = {}, fees = {}, paidAt = {}, lastT = r.t }
      byId[t.id] = t
      order[#order + 1] = t
    end
  end

  -- The draw first: it decides which entries and withdrawals came too late.
  for i = #list, 1, -1 do
    local r = list[i]
    local d = r.d or {}
    local t = d.id and byId[d.id]
    if t and r.k == "ring.bout" and d.s and d.s >= 1 and d.s <= 4 then
      t.draw[d.s] = t.draw[d.s] or { x = d.x, y = d.y }
      t.drawn = true
      t.drawnAt = t.drawnAt or r.t
    end
  end

  local running -- the latest tournament, which fee deposits go towards
  for i = #list, 1, -1 do
    local r = list[i]
    local d = r.d or {}
    if r.k == "ring.create" then running = byId[r.a .. "#" .. r.n] end
    if (r.k == "bank.move" or r.k == "bank.fill") and d.r == "ring_fee" and d.io == "d" and running
      and type(d.amt) == "number" and (not running.drawn or (d.at or r.t) <= running.drawnAt) then
      local who = r.k == "bank.fill" and MOTA:Bare(d.who) or r.a
      if who then
        running.fees[who] = (running.fees[who] or 0) + d.amt
        if running.fees[who] >= running.fee * 10000 and not running.paidAt[who] then running.paidAt[who] = r.t end
      end
    end
    local t = d.id and byId[d.id]
    if t then
      local open = not t.drawn or r.t <= t.drawnAt
      if r.k == "ring.enter" and open then
        local known = false
        for _, e in ipairs(t.entrants) do known = known or e.name == r.a end
        if not known then t.entrants[#t.entrants + 1] = { name = r.a, t = r.t } end
      elseif r.k == "ring.withdraw" and open then
        for n, e in ipairs(t.entrants) do
          if e.name == r.a then table.remove(t.entrants, n) break end
        end
      elseif r.k == "ring.paid" and d.p then
        if d.paid then
          t.paidAt[d.p] = t.paidAt[d.p] or r.t
        else
          t.paidAt[d.p], t.fees[d.p] = nil, nil
        end
      elseif r.k == "ring.result" and d.s and not t.results[d.s] then
        -- The first result that names someone actually in the bout stands.
        settleBouts(t)
        local b = t.bouts[d.s]
        if b and b.a and b.b and (d.w == b.a or d.w == b.b) then t.results[d.s] = d.w end
      end
      t.lastT = math.max(t.lastT, r.t)
    end
  end

  local hall = {}
  for _, t in ipairs(order) do
    -- Only the paid hold a place, first paid first; the sheet also lists the rest.
    local signed = t.entrants
    local paidList, waiting = {}, {}
    for _, e in ipairs(signed) do
      local at = t.fee == 0 and e.t or t.paidAt[e.name]
      if at then
        e.at = at
        paidList[#paidList + 1] = e
      else
        waiting[#waiting + 1] = e
      end
    end
    table.sort(paidList, function(a, b)
      if a.at ~= b.at then return a.at < b.at end
      return a.name < b.name
    end)
    t.entrants, t.sheet, t.refunds = {}, {}, {}
    local placed = {}
    for i, e in ipairs(paidList) do
      if i <= Ring.MAX_ENTRANTS then
        t.entrants[i] = e
        t.sheet[i] = e
        t.paid[e.name] = true
        placed[e.name] = true
      end
    end
    for i = Ring.MAX_ENTRANTS + 1, #paidList do t.sheet[#t.sheet + 1] = paidList[i] end
    for _, e in ipairs(waiting) do t.sheet[#t.sheet + 1] = e end
    if t.fee > 0 then
      for name in pairs(t.paidAt) do
        local inDraw = false
        for _, q in pairs(t.draw) do inDraw = inDraw or q.x == name or q.y == name end
        if not placed[name] and not inDraw then t.refunds[#t.refunds + 1] = name end
      end
      table.sort(t.refunds)
    end
    -- Anyone in the draw is an entrant, whatever order the records came in.
    for _, q in pairs(t.draw) do
      for _, name in ipairs({ q.x, q.y }) do
        local known = false
        for _, e in ipairs(t.entrants) do known = known or e.name == name end
        if not known then t.entrants[#t.entrants + 1] = { name = name } end
      end
    end
    settleBouts(t)
    t.stage = t.champion and "done" or (t.drawn and "bouts" or "signup")
    if t.champion then
      local final = t.bouts[7]
      local paid = 0
      for _, e in ipairs(t.entrants) do if t.paid[e.name] then paid = paid + 1 end end
      hall[#hall + 1] = { season = t.season, bracket = t.bracket, champion = t.champion, t = t.lastT,
        runnerUp = final.a == t.champion and final.b or final.a, pot = paid * t.fee }
    end
  end
  return order[#order], hall
end

local cached, cachedHall
local built = false

function Ring:Current()
  if not MOTA.guild then return nil end
  if not built then
    cached, cachedHall = build()
    built = true
  end
  return cached
end

-- The first character holding the rank, by name; the roster has offline members too.
function Ring:Minister()
  local found
  for name in pairs(MOTA.roster or {}) do
    if isMinister(name) and (not found or name < found) then found = name end
  end
  return found
end

function Ring:Hall()
  self:Current()
  return cachedHall or {}
end

function Ring:Purse(cur)
  local paid = 0
  for _, e in ipairs(cur.entrants) do
    if cur.paid[e.name] then paid = paid + 1 end
  end
  local pot = paid * cur.fee
  local bank = pot * self.GUILD_CUT
  return pot, pot - bank, bank, paid
end

function Ring:IsEntered(cur)
  for i, e in ipairs(cur.sheet or cur.entrants) do
    if e.name == MOTA.me then return true, i end
  end
  return false
end

function Ring:CanOrganise()
  return MOTA.me ~= nil and organiser(MOTA.me)
end

-- The form opens only once there is a Minister of War, even for the Crown.
function Ring:CanSetTerms()
  return self:Minister() ~= nil and self:CanOrganise()
end

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------

local function write(kind, details)
  local rec, why = MOTA.Book:Write(kind, details)
  if not rec then MOTA:Print("The Ring:", why) end
  return rec
end

function Ring:Create(season, bracket, fee, days)
  if not self:Minister() then return false, "No Minister of War has been appointed yet." end
  if not self:CanSetTerms() then return false, "Only the Minister of War or the Crown can open a tournament." end
  local cur = self:Current()
  if cur and cur.stage ~= "done" then return false, cur.season .. " hasn't finished yet." end
  if not season or season == "" then return false, "The tournament needs a name." end
  fee, days = tonumber(fee), tonumber(days)
  if not fee or fee < 0 or fee ~= math.floor(fee) then return false, "The entry fee must be a whole number of gold." end
  if not days or days <= 0 then return false, "Sign-ups must stay open for at least a day." end
  if bracket == nil or bracket == "" then bracket = "Open" end
  local rec = write("ring.create", { season = season:sub(1, 40), bracket = bracket:sub(1, 20), fee = fee,
    closes = GetServerTime() + math.floor(days * 86400) })
  return rec ~= nil
end

function Ring:Enter()
  local cur = self:Current()
  if not cur or cur.stage ~= "signup" then return false, "Sign-ups aren't open." end
  if self:IsEntered(cur) then return false, "You've already entered." end
  if GetServerTime() > cur.closes then return false, "Sign-ups have closed." end
  if #cur.entrants >= self.MAX_ENTRANTS then return false, "The Ring is full." end
  return write("ring.enter", { id = cur.id }) ~= nil
end

function Ring:Withdraw()
  local cur = self:Current()
  if not cur or cur.stage ~= "signup" or not self:IsEntered(cur) then return false, "You can't withdraw now." end
  return write("ring.withdraw", { id = cur.id }) ~= nil
end

-- Marks a refund as given: the entrant no longer counts as having paid.
function Ring:Refunded(name)
  local cur = self:Current()
  if not cur or not self:CanOrganise() then return false end
  for _, n in ipairs(cur.refunds or {}) do
    if n == name then return write("ring.paid", { id = cur.id, p = name, paid = false }) ~= nil end
  end
  return false
end

function Ring:SetPaid(name, paid)
  local cur = self:Current()
  if not cur or not self:CanOrganise() then return false end
  return write("ring.paid", { id = cur.id, p = name, paid = paid }) ~= nil
end

-- Closes sign-ups and draws at random. With fewer than eight, the spare places
-- become byes, so everyone still fights in a bracket of the same shape.
function Ring:Draw()
  local cur = self:Current()
  if not self:CanOrganise() then return false, "Only the Minister of War or the Crown can make the draw." end
  if not cur or cur.stage ~= "signup" then return false, "There's nothing to draw." end
  local n = math.min(#cur.entrants, self.MAX_ENTRANTS)
  if n < 2 then return false, "The draw needs at least two entrants who have paid." end
  local unpaid = #cur.sheet - #cur.entrants
  if unpaid > 0 then
    MOTA:Print("The Ring:", unpaid, unpaid == 1 and "entrant hasn't" or "entrants haven't", "paid or has no place, and won't be in the draw.")
  end
  local names = {}
  for i = 1, n do names[i] = cur.entrants[i].name end
  for i = n, 2, -1 do
    local j = math.random(i)
    names[i], names[j] = names[j], names[i]
  end
  for s = 1, 4 do
    if names[s] then
      write("ring.bout", { id = cur.id, s = s, x = names[s], y = names[s + 4] })
    end
  end
  return true
end

function Ring:Result(slot, winner)
  local cur = self:Current()
  if not cur or not self:CanOrganise() then return false end
  local b = cur.bouts[slot]
  if not b or not b.a or not b.b or b.w then return false end
  if winner ~= b.a and winner ~= b.b then return false end
  return write("ring.result", { id = cur.id, s = slot, w = winner }) ~= nil
end

---------------------------------------------------------------------------
-- Heralds: the next bout is called, and the champion is named
---------------------------------------------------------------------------

local called, callPending

local function callOut()
  callPending = nil
  local cur = Ring:Current()
  if not cur then return end
  if cur.champion then
    if called ~= "champion:" .. cur.id then
      called = "champion:" .. cur.id
      MOTA.Herald:Announce({ seal = "official", eyebrow = "The Ring",
        title = MOTA:Short(cur.champion) .. " is champion!", text = "The Gladiator of Stormwind, by victory in Old Town.",
        button = { label = "Dismiss", style = "quiet" } })
    end
  elseif cur.next then
    local key = cur.id .. ":" .. cur.next.slot
    if called ~= key then
      called = key
      MOTA.Herald:Announce({ seal = "official", eyebrow = "The Ring",
        title = "Next bout", text = MOTA:Short(cur.next.a) .. " v " .. MOTA:Short(cur.next.b) .. ", Old Town",
        button = { label = "Dismiss", style = "quiet" } })
    end
  end
end

MOTA:Listen("RECORD_ADDED", function(_, rec)
  if not rec.k:find("^ring%.") and not rec.k:find("^bank%.") then return end
  built = false
  MOTA:Fire("RING_CHANGED")
  if (rec.k == "ring.bout" or rec.k == "ring.result") and not callPending and not MOTA.Book.replaying then
    callPending = true
    C_Timer.After(CALL_DELAY, callOut)
  end
end)

local function forget() built = false end
MOTA:Listen("GUILD_READY", forget)
MOTA:Listen("GUILD_LOST", forget)

---------------------------------------------------------------------------
-- Duel results, read from the game's message on the organiser's copy
---------------------------------------------------------------------------

local function pattern(format)
  local first = format:find("%1$s", 1, true)
  local second = format:find("%2$s", 1, true)
  local p = format:gsub("%%%d%$s", ""):gsub("%%s", "")
  p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1"):gsub("", "(.+)")
  return "^" .. p .. "%.?$", first and second and second < first
end

local function duelMessages()
  local list = {}
  for _, format in ipairs({ DUEL_WINNER_KNOCKOUT or "%1$s has defeated %2$s in a duel",
    DUEL_WINNER_RETREAT or "%2$s has fled from %1$s in a duel" }) do
    local p, swapped = pattern(format)
    list[#list + 1] = { p = p, swapped = swapped }
  end
  return list
end

function Ring:ReadDuel(message)
  local cur = self:Current()
  if not cur or not cur.next or not self:CanOrganise() then return false end
  for _, m in ipairs(duelMessages()) do
    local winner, loser = message:match(m.p)
    if winner then
      if m.swapped then winner, loser = loser, winner end
      for s = 1, 7 do
        local b = cur.bouts[s]
        if b.a and b.b and not b.w then
          local a, c = Ambiguate(b.a, "none"), Ambiguate(b.b, "none")
          if a == winner and c == loser then return self:Result(s, b.a) end
          if c == winner and a == loser then return self:Result(s, b.b) end
        end
      end
      return false
    end
  end
  return false
end

MOTA:On("CHAT_MSG_SYSTEM", function(_, _, message) Ring:ReadDuel(message) end)
