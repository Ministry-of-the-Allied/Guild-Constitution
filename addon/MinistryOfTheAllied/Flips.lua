-- Ministry of the Allied: the flipping ledger (Duncan, 15 Nov 2026).
--
-- Buying at the auction house to sell again (as is, or crafted: Iron Ore smelted to Iron Bars),
-- and keeping the score. With "Flipping mode" on, every auction house purchase starts or adds to
-- a flip; anything posted that belongs to an open flip is logged against it, whatever the
-- toggle says, and so are its sales, expiries and cancellations. Profit is what the mail paid,
-- less what was spent and every deposit paid. Personal: kept per character, never sent anywhere.
--
-- Saved in MOTADB.flips[character] = { on, n, list = { flip, ... } }:
--   flip = { id, item, name, makes, makesName, ratio, at, closed,
--            buys  = { { q, c (copper, all of them), at, est (price guessed) } },
--            lists = { { item, name, q, p (each), dur, dep, at, aid, tier, sold, back, got, first, last } } }
--
-- Where things come from (the modern auction house API, which Forever has):
--   buys       C_AuctionHouse.ConfirmCommoditiesPurchase / PlaceBid, confirmed by the purchase
--              events; the "You won an auction" chat line as a fallback
--   listings   C_AuctionHouse.PostCommodity / PostItem; AUCTION_HOUSE_AUCTION_CREATED gives the ID
--   sales      the "Auction successful" mail, as its money is taken (its invoice says how much)
--   expiries   the "Auction expired" mail, as its items are taken
--   cancelled  C_AuctionHouse.CancelAuction

local _, MOTA = ...
local Flips = {}
MOTA.Flips = Flips

Flips.MAIL_DAYS = 30 -- an auction mail's life, to tell when it was sent

local function db()
  MOTA.db.flips = MOTA.db.flips or {}
  local me = MOTA.me or "?"
  local d = MOTA.db.flips[me]
  if not d then
    d = { on = false, n = 0, list = {} }
    MOTA.db.flips[me] = d
  end
  return d
end
Flips.db = db

local function itemInfo(id) return MOTA.Workshop and MOTA.Workshop.ItemInfo(id) end
local function changed() MOTA:Fire("FLIPS_CHANGED") end
local function now() return GetServerTime() end

-- A format string from the game ("Auction successful: %s") as a pattern with one capture.
local function pattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  return "^" .. p .. "$"
end

---------------------------------------------------------------------------
-- The toggle and the list
---------------------------------------------------------------------------

function Flips:On() return db().on == true end

function Flips:SetOn(on)
  db().on = on and true or false
  MOTA:Print(MOTA:Color("leaf", "Workshop:"), "flipping mode " .. (on and "on: auction house purchases are logged as flips." or "off."))
  changed()
end

function Flips:All() return db().list end

function Flips:Get(id)
  for _, f in ipairs(db().list) do if f.id == id then return f end end
end

function Flips:Open()
  local out = {}
  for _, f in ipairs(db().list) do if not f.closed then out[#out + 1] = f end end
  return out
end

-- The open flip for an item bought, or nil.
function Flips:ForBuy(item)
  for _, f in ipairs(db().list) do
    if not f.closed and f.item == item then return f end
  end
end

-- A recipe of this character's that turns `mat` into `out`: the units of `out` from one `mat`.
local function yieldOf(mat, out)
  local W = MOTA.Workshop
  if not (W and W.Mine) then return nil end
  for _, prof in pairs(W:Mine()) do
    for _, r in pairs(prof.recipes or {}) do
      if r.item == out and r.mats and #r.mats == 1 and r.mats[1].item == mat then
        return (r.made or 1) / (r.mats[1].count or 1)
      end
    end
  end
end

-- The open flip a posted item belongs to: one that bought it, one that already sells it, or one
-- whose purchase this character's recipes turn into it.
function Flips:ForSale(item)
  local open = self:Open()
  for _, f in ipairs(open) do if f.item == item or f.makes == item then return f end end
  for _, f in ipairs(open) do
    if not f.makes then
      local y = yieldOf(f.item, item)
      if y then
        f.makes, f.makesName, f.ratio = item, itemInfo(item), y
        return f
      end
    end
  end
end

local function newFlip(item, name)
  local d = db()
  d.n = (d.n or 0) + 1
  local f = { id = d.n, item = item, name = name or itemInfo(item) or ("item " .. item), at = now(), buys = {}, lists = {} }
  table.insert(d.list, 1, f)
  return f
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

-- A purchase: q units of item for c copper in all. With flipping mode off it's not a flip.
function Flips:Bought(item, q, c, est)
  if not (self:On() and item and q and q > 0) then return nil end
  local f = self:ForBuy(item) or newFlip(item)
  f.buys[#f.buys + 1] = { q = q, c = c or 0, at = now(), est = est or nil }
  self.lastBuy = { item = item, name = f.name, at = GetTime() }
  MOTA:Print(MOTA:Color("leaf", "Flip:"), ("bought %d %s for %s%s."):format(q, f.name, MOTA.Workshop:Money(c or 0), est and " (price estimated)" or ""))
  changed()
  return f
end

-- Where a price sits against the market when posted: "low", "usual" or "high".
function Flips:Tier(item, p)
  local M = MOTA.Market
  if not M then return nil end
  local low, usual = M:Lowest(item), M:Normal(item)
  if not usual and not low then return nil end
  if low and p <= low then return "low" end
  usual = usual or low
  if p < usual * 0.98 then return "low" end
  if p <= usual * 1.02 then return "usual" end
  return "high"
end

-- A posting: q units of item at p copper each. Logged when it belongs to an open flip; with
-- flipping mode on, stock that wasn't bought as a flip starts one of its own (no cost).
function Flips:Listed(item, q, p, dur, dep)
  if not (item and q and q > 0 and p) then return nil end
  local f = self:ForSale(item)
  if not f then
    if not self:On() then return nil end
    f = newFlip(item)
    f.own = true
  end
  local l = { item = item, name = itemInfo(item) or ("item " .. item), q = q, p = p, dur = dur, dep = dep or 0,
    at = now(), tier = self:Tier(item, p), sold = 0, back = 0, got = 0 }
  f.lists[#f.lists + 1] = l
  self.pending = l
  changed()
  return f, l
end

local function active(l) return l.q - l.sold - l.back end

-- The listings still up, cheapest first (buyers take the cheapest first).
local function up(name)
  local out = {}
  for _, f in ipairs(db().list) do
    for _, l in ipairs(f.lists) do
      if l.name == name and active(l) > 0 then out[#out + 1] = { f = f, l = l } end
    end
  end
  table.sort(out, function(a, b) return a.l.p < b.l.p end)
  return out
end

-- Every unit the flip can sell: what was bought, through the recipe if it's crafted.
function Flips:Units(f)
  local n = 0
  for _, b in ipairs(f.buys) do n = n + b.q end
  if f.own then
    for _, l in ipairs(f.lists) do n = math.max(n, l.q) end
  end
  return math.floor(n * (f.ratio or 1) + 0.5)
end

local function settle(f)
  if f.closed then return end
  local sold, left = 0, 0
  for _, l in ipairs(f.lists) do sold, left = sold + l.sold, left + active(l) end
  if left == 0 and sold > 0 and sold >= Flips:Units(f) then
    f.closed = now()
    local s = Flips:Sum(f)
    MOTA:Print(MOTA:Color("leaf", "Flip done:"), f.name .. ", profit " .. MOTA.Workshop:Money(s.profit) .. ".")
  end
end

-- A sale, from its mail: q units of the item called name, money paid (after the cut, with any
-- deposit back), sold at about `at`, for `gross` before the cut.
function Flips:Sold(name, q, money, at, gross)
  local list = up(name)
  if #list == 0 then return nil end
  q = q or 1
  -- the listing at this price first, if the invoice says what each went for
  local each = gross and q > 0 and math.floor(gross / q + 0.5)
  if each then
    table.sort(list, function(a, b)
      local x, y = a.l.p == each, b.l.p == each
      if x ~= y then return x end
      return a.l.p < b.l.p
    end)
  end
  local left, pay, hit = q, money or 0, nil
  for i, e in ipairs(list) do
    if left <= 0 then break end
    local take = math.min(left, active(e.l))
    local share = (i == #list or take == left) and pay or math.floor((money or 0) * take / q)
    e.l.sold, e.l.got = e.l.sold + take, e.l.got + share
    e.l.first = e.l.first or at
    e.l.last = math.max(e.l.last or 0, at or 0)
    left, pay, hit = left - take, pay - share, e.f
  end
  if hit then settle(hit); changed() end
  return hit
end

-- An expired or cancelled listing coming back: q units of name.
function Flips:Back(name, q)
  local list = up(name)
  -- a whole listing comes back at once: one with exactly that many still up, else the oldest
  table.sort(list, function(a, b)
    local x, y = active(a.l) == q, active(b.l) == q
    if x ~= y then return x end
    return a.l.at < b.l.at
  end)
  local left = q or 1
  for _, e in ipairs(list) do
    if left <= 0 then break end
    local take = math.min(left, active(e.l))
    e.l.back = e.l.back + take
    left = left - take
  end
  if #list > 0 then changed() end
  return #list > 0
end

function Flips:Cancelled(aid)
  for _, f in ipairs(db().list) do
    for _, l in ipairs(f.lists) do
      if l.aid == aid and active(l) > 0 then
        l.back, l.cancelled = l.back + active(l), true
        changed()
        return l
      end
    end
  end
end

function Flips:Close(id)
  local f = self:Get(id)
  if not f then return nil, "No flip " .. tostring(id) .. "." end
  f.closed = (not f.closed) and now() or nil
  changed()
  return f
end

function Flips:Delete(id)
  local list = db().list
  for i, f in ipairs(list) do
    if f.id == id then table.remove(list, i); changed() return true end
  end
end

---------------------------------------------------------------------------
-- The score
---------------------------------------------------------------------------

-- bought, cost, units, listed, sold, up (still listed), got (paid by mail), deps, profit,
-- tiers = { low/usual/high = { sold, listed, got, hours (to the first sale) } }
function Flips:Sum(f)
  local s = { bought = 0, cost = 0, listed = 0, sold = 0, up = 0, got = 0, deps = 0, tiers = {}, est = false }
  for _, b in ipairs(f.buys) do
    s.bought, s.cost = s.bought + b.q, s.cost + (b.c or 0)
    if b.est then s.est = true end
  end
  for _, l in ipairs(f.lists) do
    s.listed, s.sold, s.up = s.listed + l.q, s.sold + l.sold, s.up + active(l)
    s.got, s.deps = s.got + l.got, s.deps + (l.dep or 0)
    local t = s.tiers[l.tier or "?"] or { sold = 0, listed = 0, got = 0 }
    s.tiers[l.tier or "?"] = t
    t.listed, t.sold, t.got, t.p = t.listed + l.q, t.sold + l.sold, t.got + l.got, l.p
    if l.first then
      local h = math.max(0, (l.first - l.at) / 3600)
      t.hours = t.hours and math.min(t.hours, h) or h
    end
  end
  s.units = self:Units(f)
  s.profit = s.got - s.cost - s.deps
  -- if what's still up sells at its price, after the cut
  local cut = MOTA.Workshop and MOTA.Workshop.CUT or 0.05
  local more = 0
  for _, l in ipairs(f.lists) do more = more + math.floor(active(l) * l.p * (1 - cut)) end
  s.outlook = s.profit + more
  return s
end

function Flips:Totals()
  local t = { flips = 0, done = 0, profit = 0 }
  for _, f in ipairs(db().list) do
    t.flips = t.flips + 1
    if f.closed then
      t.done = t.done + 1
      t.profit = t.profit + self:Sum(f).profit
    end
  end
  return t
end

---------------------------------------------------------------------------
-- Watching the auction house and the mail
---------------------------------------------------------------------------

local hooked = {}
local function hook(tbl, name, fn)
  local key = tostring(tbl) .. name
  if hooked[key] or type(tbl) ~= "table" or type(tbl[name]) ~= "function" then return end
  hooked[key] = true
  hooksecurefunc(tbl, name, fn)
end

local price = {}   -- the commodity purchase being confirmed: item, q, total
local bids = {}    -- auctionID -> { item, c } for an item bought outright
local function itemOf(loc)
  if type(loc) == "number" then return loc end
  local ok, id = pcall(function() return C_Item and C_Item.GetItemID and C_Item.GetItemID(loc) end)
  return ok and id or nil
end

function Flips:HookAuctionHouse()
  local AH = C_AuctionHouse
  if not AH then return end
  hook(AH, "StartCommoditiesPurchase", function(item, q) price = { item = item, q = q } end)
  hook(AH, "ConfirmCommoditiesPurchase", function(item, q)
    price.item, price.q, price.confirmed = item, q, true
  end)
  hook(AH, "PlaceBid", function(aid, amount)
    local item
    local ok, info = pcall(AH.GetAuctionInfoByID, aid)
    if ok and type(info) == "table" and info.itemKey then item = info.itemKey.itemID end
    bids[aid] = { item = item, c = amount }
  end)
  hook(AH, "PostCommodity", function(loc, dur, q, p)
    local item = itemOf(loc)
    local dep
    if item and AH.CalculateCommodityDeposit then
      local ok, v = pcall(AH.CalculateCommodityDeposit, item, dur, q)
      dep = ok and v or nil
    end
    Flips:Listed(item, q, p, dur, dep)
  end)
  hook(AH, "PostItem", function(loc, dur, q, bid, buyout)
    local item = itemOf(loc)
    local dep
    if AH.CalculateItemDeposit then
      local ok, v = pcall(AH.CalculateItemDeposit, loc, dur, q)
      dep = ok and v or nil
    end
    local each = buyout or bid
    if each and q and q > 0 then Flips:Listed(item, q, math.floor(each / q), dur, dep) end
  end)
  hook(AH, "CancelAuction", function(aid) Flips:Cancelled(aid) end)
end

local SUBJECT = {}
local function subjects()
  SUBJECT.sold = pattern(_G.AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s")
  SUBJECT.expired = pattern(_G.AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s")
  SUBJECT.cancelled = pattern(_G.AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s")
  SUBJECT.won = pattern(_G.ERR_AUCTION_WON_S or "You won an auction for %s")
  SUBJECT.found = pattern(_G.ERR_AUCTION_SOLD_S or "A buyer has been found for your auction of %s.")
end

-- "Iron Bar (12)" -> "Iron Bar", 12
local function split(s)
  local name, n = s:match("^(.-)%s*%((%d+)%)$")
  if name then return name, tonumber(n) end
  name, n = s:match("^(.-)%s*x(%d+)$")
  if name then return name, tonumber(n) end
  return s, nil
end

local seenMail = {}
local function mailKey(i)
  local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
  return table.concat({ tostring(sender), tostring(subject), tostring(money), ("%.4f"):format(daysLeft or 0) }, "|"), subject, money, daysLeft
end

-- Reads mail i before its money or items are taken.
function Flips:ReadMail(i, takingItems)
  if not GetInboxHeaderInfo then return end
  local key, subject, money, daysLeft = mailKey(i)
  if not subject or seenMail[key] then return end
  local sent = now() - math.floor((self.MAIL_DAYS - (daysLeft or self.MAIL_DAYS)) * 86400)
  local what = SUBJECT.sold and subject:match(SUBJECT.sold)
  if what and (money or 0) > 0 then
    seenMail[key] = true
    local name, n = split(what)
    local gross, count
    if GetInboxInvoiceInfo then
      local r = { pcall(GetInboxInvoiceInfo, i) }
      if r[1] and r[2] == "seller" then
        gross = r[6] or r[5] -- buyout, else the winning bid
        if type(r[12]) == "number" and r[12] > 0 then count = r[12] end
      end
    end
    local at = (self.found and self.found[name]) or sent
    if self.found then self.found[name] = nil end
    self:Sold(name, count or n or 1, money, at, gross)
    return
  end
  what = takingItems and SUBJECT.expired and subject:match(SUBJECT.expired)
  if what then
    seenMail[key] = true
    local name, n = split(what)
    local count = n
    if GetInboxItem then
      local ok, _, _, _, c = pcall(GetInboxItem, i, 1)
      if ok and type(c) == "number" then count = c end
    end
    self:Back(name, count or 1)
  end
end

function Flips:HookMail()
  if hooked.mail then return end
  hooked.mail = true
  local function g(name, fn) if type(_G[name]) == "function" then hooksecurefunc(name, fn) end end
  -- hooks run after the call, but the mail stays readable until the server answers
  g("TakeInboxMoney", function(i) Flips:ReadMail(i, false) end)
  g("TakeInboxItem", function(i) Flips:ReadMail(i, true) end)
  g("AutoLootMailItem", function(i) Flips:ReadMail(i, true) end)
end

-- The chat lines: "You won an auction for X" (a fallback for a purchase the API hooks missed)
-- and "A buyer has been found for your auction of X" (when it sold; the mail can come later).
function Flips:System(msg)
  if type(msg) ~= "string" then return end
  local what = SUBJECT.found and msg:match(SUBJECT.found)
  if what then
    local name = split(what)
    if #up(name) > 0 then
      self.found = self.found or {}
      self.found[name] = self.found[name] or now()
    end
    return
  end
  what = SUBJECT.won and msg:match(SUBJECT.won)
  if what and self:On() then
    local name, n = split(what)
    local last = self.lastBuy
    if last and last.name == name and GetTime() - last.at < 5 then return end -- the API saw it
    -- not seen by the API: price it at the market's cheapest, marked as a guess
    C_Timer.After(1, function()
      local l2 = self.lastBuy
      if l2 and l2.name == name and GetTime() - l2.at < 5 then return end
      local id = self:IdByName(name)
      if not id then
        MOTA:Print(MOTA:Color("leaf", "Flip:"), "couldn't tell which item \"" .. name .. "\" is; not logged.")
        return
      end
      local p = MOTA.Market and MOTA.Market:Lowest(id) or 0
      self:Bought(id, n or 1, p * (n or 1), true)
    end)
  end
end

-- An item ID from its name, among what the Workshop and the flips know.
function Flips:IdByName(name)
  for _, f in ipairs(db().list) do
    if f.name == name then return f.item end
    if f.makesName == name then return f.makes end
  end
  local market = MOTA.db and MOTA.db.market or {}
  for id in pairs(market) do
    if itemInfo(id) == name then return id end
  end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "MAIL_SHOW", "COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_SUCCEEDED",
  "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_AUCTION_CREATED", "CHAT_MSG_SYSTEM",
  "PLAYER_LOGIN" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, a, b)
  if e == "PLAYER_LOGIN" then subjects()
  elseif e == "AUCTION_HOUSE_SHOW" then subjects(); Flips:HookAuctionHouse()
  elseif e == "MAIL_SHOW" then subjects(); Flips:HookMail()
  elseif e == "COMMODITY_PRICE_UPDATED" then price.total = b or (a and price.q and a * price.q)
  elseif e == "COMMODITY_PURCHASE_SUCCEEDED" then
    if price.confirmed and price.item then Flips:Bought(price.item, price.q, price.total) end
    price = {}
  elseif e == "COMMODITY_PURCHASE_FAILED" then price = {}
  elseif e == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    local bid = bids[a]
    if bid and bid.item then Flips:Bought(bid.item, 1, bid.c) end
    bids[a] = nil
  elseif e == "AUCTION_HOUSE_AUCTION_CREATED" then
    if Flips.pending then Flips.pending.aid = a; Flips.pending = nil end
  elseif e == "CHAT_MSG_SYSTEM" then Flips:System(a)
  end
end)
subjects()
