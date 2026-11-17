-- Ministry of the Allied: the market, as our own auction house searches see it (Duncan, 14 Nov 2026).
--
-- Auctionator keeps one price per item: the cheapest listing. For a batch that's wrong: one Tin
-- Ore at 1s 50c and nineteen at 2s cost 1s 97c each, not 1s 50c. A search of a stackable good
-- returns every price level with its quantity (/mota probe market, 14 Nov), so a batch can be
-- priced by buying up the levels, cheapest first.
--
-- Searches run only when the player presses "Scan" on the Workshop's strip at the auction house:
-- one material at a time, a second and a half apart. A search replaces what the auction house
-- window is showing, so it's never started behind the player's back.
--
-- Saved account-wide in MOTADB.market[itemID] = { at, levels = { {p, q}, ... } } (cheapest first),
-- or { at, notStack = true } for an item that came back as a single-listing item (gear).
--
--   Market:Levels(id)           the levels and their age in seconds, or nil
--   Market:Buy(id, n)           copper to buy n, how many are listed in all (up to n), age
--   Market:Lowest(id)           the cheapest price and its age
--   Market:Scan(ids)            searches these, in turn
--   Market:Scanning()           how many are left, or nil

local _, MOTA = ...
local Market = {}
MOTA.Market = Market

Market.FRESH = -1         -- scans are never skipped for being recent (Duncan, 17 Nov: the market moves all the time; more data is better)
Market.STALE = 48 * 3600  -- older than this, it's not used for prices at all
Market.GAP = 1.5          -- seconds between searches
Market.WAIT = 6           -- give up on one search after this

local function db()
  MOTA.db.market = MOTA.db.market or {}
  return MOTA.db.market
end

function Market:Available()
  return C_AuctionHouse ~= nil and C_AuctionHouse.SendSearchQuery ~= nil and C_AuctionHouse.GetCommoditySearchResultInfo ~= nil
end

function Market:Levels(id)
  local e = id and db()[id]
  if not e or not e.levels then return nil end
  local age = GetServerTime() - (e.at or 0)
  if age > self.STALE then return nil end
  return e.levels, age
end

function Market:Lowest(id)
  local levels, age = self:Levels(id)
  if levels and levels[1] then return levels[1].p, age end
end

-- What n cost bought cheapest first: copper, how many could be bought (at most n), the scan's age.
function Market:Buy(id, n)
  local levels, age = self:Levels(id)
  if not levels then return nil end
  local cost, got = 0, 0
  for _, l in ipairs(levels) do
    local take = math.min(l.q, n - got)
    cost, got = cost + take * l.p, got + take
    if got >= n then break end
  end
  return cost, got, age
end

-- When we last looked at an item, whatever we found.
function Market:Age(id)
  local e = id and db()[id]
  return e and e.at and (GetServerTime() - e.at) or nil
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------

local queue, current, timer = {}, nil, nil
local frame = CreateFrame("Frame")

local function done() MOTA:Fire("MARKET_CHANGED") end

local nextSearch

-- The next search as soon as the auction house will take one (Duncan, 14 Nov: the scan was
-- slow with a fixed 1.5 s gap). The game says when its search throttle is ready; this checks
-- every tenth of a second, and goes after GAP seconds at most whatever it says.
Market.MIN_GAP = 0.2
function Market:WhenReady(fn)
  local AH = C_AuctionHouse
  local ready = AH and AH.IsThrottledMessageSystemReady
  if not ready then C_Timer.After(self.GAP, fn) return end
  local waited = 0
  local function try()
    if ready() or waited >= self.GAP then fn() return end
    waited = waited + 0.1
    C_Timer.After(0.1, try)
  end
  C_Timer.After(self.MIN_GAP, function() waited = self.MIN_GAP; try() end)
end

local function finish(id, entry)
  if current ~= id then return end
  if timer then timer:Cancel(); timer = nil end
  if entry then entry.at = GetServerTime(); Market:Record(id, db()[id], entry); db()[id] = entry end
  current = nil
  done()
  if #queue > 0 then Market:WhenReady(nextSearch) else
    frame:UnregisterAllEvents()
    MOTA:Fire("MARKET_SCANNED")
  end
end

local function readCommodity(id)
  local AH = C_AuctionHouse
  local rows = {}
  for i = 1, AH.GetNumCommoditySearchResults(id) or 0 do
    local info = AH.GetCommoditySearchResultInfo(id, i)
    if info and info.unitPrice and info.quantity then
      rows[#rows + 1] = { p = info.unitPrice, q = info.quantity, left = info.timeLeftSeconds }
    end
  end
  table.sort(rows, function(a, b) return a.p < b.p end)
  local levels = {}
  for _, r in ipairs(rows) do
    local last = levels[#levels]
    if last and last.p == r.p then
      last.q = last.q + r.q
      if r.left and (not last.left or r.left < last.left) then last.left = r.left end -- the soonest to expire
    else
      levels[#levels + 1] = r
    end
  end
  return { levels = levels }
end

-- Gear and other single listings: each with its auction ID and time-left band, to tell later
-- whether a listing that's gone was bought or simply ran out.
local function readItem(id, key)
  local AH = C_AuctionHouse
  local levels, auctions = {}, {}
  for i = 1, AH.GetNumItemSearchResults(key) or 0 do
    local info = AH.GetItemSearchResultInfo(key, i)
    if info and info.buyoutAmount and info.buyoutAmount > 0 then
      local q = info.quantity or 1
      levels[#levels + 1] = { p = math.floor(info.buyoutAmount / q), q = q }
      if info.auctionID then auctions[info.auctionID] = info.timeLeft or 3 end
    end
  end
  table.sort(levels, function(a, b) return a.p < b.p end)
  return { levels = levels, auctions = auctions, single = true }
end
Market.readItem = readItem

function nextSearch()
  if current or not Market.atAuctionHouse then return end
  local id = table.remove(queue, 1)
  if not id then return end
  current = id
  frame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  frame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
  local ok = pcall(C_AuctionHouse.SendSearchQuery, C_AuctionHouse.MakeItemKey(id), { { sortOrder = order, reverseSort = false } }, false)
  if not ok then finish(id, nil) return end
  done()
  timer = C_Timer.NewTimer(Market.WAIT, function() timer = nil; finish(id, nil) end)
end

frame:SetScript("OnEvent", function(_, ev, a)
  if not current then return end
  local id = current
  if ev == "COMMODITY_SEARCH_RESULTS_UPDATED" and a == id then
    C_Timer.After(0.3, function() if current == id then finish(id, readCommodity(id)) end end)
  elseif ev == "ITEM_SEARCH_RESULTS_UPDATED" and type(a) == "table" and a.itemID == id then
    C_Timer.After(0.3, function() if current == id then finish(id, readItem(id, a)) end end)
  end
end)

-- Searches these item IDs in turn, skipping any looked at in the last FRESH seconds
-- (unless all is true). Returns how many it will search.
function Market:Scan(ids, all)
  if not self:Available() then return nil, "This client has no auction house search." end
  if not self.atAuctionHouse then return nil, "Open the auction house first." end
  local seen = {}
  for _, id in ipairs(queue) do seen[id] = true end
  if current then seen[current] = true end
  local n = 0
  for _, id in ipairs(ids) do
    local age = self:Age(id)
    if not seen[id] and (all or not age or age > self.FRESH) then
      queue[#queue + 1] = id
      seen[id] = true
      n = n + 1
    end
  end
  if n > 0 and not current then nextSearch() end
  done()
  return n
end

function Market:Scanning()
  local left = #queue + (current and 1 or 0)
  return left > 0 and left or nil
end

function Market:Stop()
  wipe(queue)
  if timer then timer:Cancel(); timer = nil end
  current = nil
  frame:UnregisterAllEvents()
  done()
end

local ah = CreateFrame("Frame")
for _, ev in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do pcall(ah.RegisterEvent, ah, ev) end
ah:SetScript("OnEvent", function(_, ev)
  Market.atAuctionHouse = ev == "AUCTION_HOUSE_SHOW"
  if not Market.atAuctionHouse then Market:Stop() end
  MOTA:Fire(Market.atAuctionHouse and "AUCTION_OPEN" or "AUCTION_CLOSED")
end)

---------------------------------------------------------------------------
-- The market watch (Duncan, 14 Nov): what sold between two scans, and each day's prices.
--
-- Stackables (bars, potions) come grouped by price. Buyers always take the cheapest first, so
-- between two scans: every unit priced below the new cheapest level is gone, and at the new
-- cheapest level any drop in quantity is gone. Those went to buyers, unless they were about
-- to expire (each level keeps its soonest time left) or were cancelled; that can't be told
-- apart, so it's an estimate, better the more scans there are.
-- Single listings (gear) each have an auction ID and a time-left band: one that's gone before
-- it could have run out was bought (or, now and then, cancelled).
--
-- MOTADB.market[id].hist["2026-11-14"] = { low, median, qty, sold, hours }
--   sold and hours add up over the day's scan pairs; the rate is sold per hour watched.
---------------------------------------------------------------------------

Market.KEEP_DAYS = 14
Market.PAIR_MAX = 36 * 3600 -- two scans further apart than this aren't compared
Market.MIN_HOURS = 4        -- below this much watching, no sell rate is given
local BAND_MIN = { [0] = 0, [1] = 1800, [2] = 7200, [3] = 43200 } -- the least a band can have left

-- The units-weighted median of what's listed.
local function median(levels)
  local total = 0
  for _, l in ipairs(levels) do total = total + l.q end
  local half, seen = total / 2, 0
  for _, l in ipairs(levels) do
    seen = seen + l.q
    if seen >= half then return l.p end
  end
end

-- Units bought between two stackable scans.
function Market:SoldStack(prev, new, elapsed)
  local low = new.levels[1] and new.levels[1].p or math.huge
  local now = {}
  for _, l in ipairs(new.levels) do now[l.p] = l.q end
  local sold = 0
  for _, l in ipairs(prev.levels or {}) do
    if not (l.left and l.left <= elapsed) then -- could have run out: not counted
      if l.p < low then sold = sold + l.q
      elseif l.p == low then sold = sold + math.max(0, l.q - (now[l.p] or 0)) end
    end
  end
  return sold
end

-- Listings bought between two scans of single listings.
function Market:SoldSingle(prev, new, elapsed)
  local sold = 0
  for aid, band in pairs(prev.auctions or {}) do
    if not new.auctions[aid] and elapsed < (BAND_MIN[band] or 0) then sold = sold + 1 end
  end
  return sold
end

local function day(t) return date("%Y-%m-%d", t) end

function Market:Record(id, prev, new)
  new.hist = (prev and prev.hist) or {}
  local h = new.hist[day(new.at)] or {}
  new.hist[day(new.at)] = h
  if new.levels[1] then
    h.low = math.min(h.low or math.huge, new.levels[1].p)
    h.median = median(new.levels)
  end
  local qty = 0
  for _, l in ipairs(new.levels) do qty = qty + l.q end
  h.qty = qty
  if prev and prev.at and prev.levels then
    local elapsed = new.at - prev.at
    if elapsed > 0 and elapsed <= self.PAIR_MAX then
      local sold = new.single and self:SoldSingle(prev, new, elapsed) or self:SoldStack(prev, new, elapsed)
      h.sold = (h.sold or 0) + sold
      h.hours = (h.hours or 0) + elapsed / 3600
    end
  end
  local oldest = day(new.at - self.KEEP_DAYS * 86400)
  for k in pairs(new.hist) do if k < oldest then new.hist[k] = nil end end
end

-- Units sold a day over the last week, and the hours that rests on; nil when too few hours.
function Market:SellRate(id)
  local e = id and db()[id]
  if not e or not e.hist then return nil, 0 end
  local from = day(GetServerTime() - 7 * 86400)
  local sold, hours = 0, 0
  for k, h in pairs(e.hist) do
    if k >= from then sold, hours = sold + (h.sold or 0), hours + (h.hours or 0) end
  end
  if hours < self.MIN_HOURS then return nil, hours end
  return sold / hours * 24, hours
end

-- The usual price: the median of the last week's daily medians.
function Market:Normal(id)
  local e = id and db()[id]
  if not e or not e.hist then return nil end
  local from, list = day(GetServerTime() - 7 * 86400), {}
  for k, h in pairs(e.hist) do if k >= from and h.median then list[#list + 1] = h.median end end
  if #list == 0 then return nil end
  table.sort(list)
  return list[math.floor((#list + 1) / 2)]
end

-- "~6 a day", "~2 a week", "slow", or nil with no data.
function Market:RateText(id)
  local rate, hours = self:SellRate(id)
  if not rate then return nil, hours end
  if rate >= 1 then return "~" .. math.floor(rate + 0.5) .. " a day" end
  if rate * 7 >= 1 then return "~" .. math.floor(rate * 7 + 0.5) .. " a week" end
  return "barely sells"
end
