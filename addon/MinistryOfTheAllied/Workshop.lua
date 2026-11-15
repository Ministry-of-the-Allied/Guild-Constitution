-- Ministry of the Allied: the Workshop, a crafting guide for this character (Duncan, 14 Nov 2026).
--
-- Auctionator already prices every item. What it doesn't do is guide the player by their own
-- professions and skill: what to craft for profit, the cheapest way to the next skill point,
-- and which unlearned recipes are worth training. This reads the open profession window (the
-- modern C_TradeSkillUI, which Forever has: /mota probe craft, 14 Nov) and prices it with
-- Auctionator's API. Market watching (what actually sells) comes next, on the auction house.
--
-- Saved per character in MOTADB.workshop[character][professionID], so alts are remembered:
--   { name, rank, max, at, recipes = { [recipeID] = { name, colour, learned, item, made, ups, mats = { {item, count} } } } }
--
--   Workshop:Scan()            reads the open profession window; returns the profession's record
--   Workshop:Price(itemID)     copper and how many days old (Auctionator), or nil
--   Workshop:Cost(r)           materials' cost, and whether any are unpriced
--   Workshop:Profit(prof)      learned recipes, most profitable first
--   Workshop:Levelling(prof)   learned recipes that still give skill, cheapest per point first
--   Workshop:ToLearn(prof)     unlearned recipes, most profitable first

local _, MOTA = ...
local Workshop = {}
MOTA.Workshop = Workshop

Workshop.CUT = 0.05 -- the auction house's cut of a sale
local CALLER = "MinistryOfTheAllied"
local DIFF = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
-- Roughly how many skill points a craft gives at each colour (orange always, yellow usually,
-- green now and then, grey never). Used to rank the levelling list by cost per point.
Workshop.CHANCE = { optimal = 1, medium = 0.75, easy = 0.25, trivial = 0 }

-- Forever has C_Item's versions, not the old globals.
local function itemInfo(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if f then return f(id) end
end
Workshop.ItemInfo = itemInfo

local function itemID(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

---------------------------------------------------------------------------
-- Reading the profession window
---------------------------------------------------------------------------

function Workshop:Available()
  return C_TradeSkillUI ~= nil and C_TradeSkillUI.GetAllRecipeIDs ~= nil and C_TradeSkillUI.GetRecipeInfo ~= nil
end

local function readRecipe(id)
  local T = C_TradeSkillUI
  local info = T.GetRecipeInfo(id)
  if not info then return nil end
  local r = { name = info.name, learned = info.learned ~= false, ups = info.numSkillUps, mats = {} }
  r.colour = info.difficulty or (info.relativeDifficulty and DIFF[info.relativeDifficulty]) or "trivial"
  local s = T.GetRecipeSchematic and T.GetRecipeSchematic(id, false)
  if s and s.reagentSlotSchematics then
    r.item, r.made = s.outputItemID, s.quantityMin or 1
    for _, slot in ipairs(s.reagentSlotSchematics) do
      local first = slot.reagents and slot.reagents[1]
      if first and first.itemID then r.mats[#r.mats + 1] = { item = first.itemID, count = slot.quantityRequired or 1 } end
    end
  elseif T.GetRecipeNumReagents then
    r.item = itemID(T.GetRecipeItemLink and T.GetRecipeItemLink(id))
    for j = 1, T.GetRecipeNumReagents(id) or 0 do
      local _, _, count = T.GetRecipeReagentInfo(id, j)
      local mid = itemID(T.GetRecipeReagentItemLink and T.GetRecipeReagentItemLink(id, j))
      if mid then r.mats[#r.mats + 1] = { item = mid, count = count or 1 } end
    end
  end
  r.item = r.item or itemID(info.hyperlink)
  r.made = r.made or 1
  return r
end

local function store()
  MOTA.db.workshop = MOTA.db.workshop or {}
  local me = MOTA.me or (UnitName and UnitName("player")) or "?"
  MOTA.db.workshop[me] = MOTA.db.workshop[me] or {}
  return MOTA.db.workshop[me]
end

-- Reads the open profession window into this character's record. Returns the profession.
function Workshop:Scan()
  if not self:Available() then return nil end
  local T = C_TradeSkillUI
  if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return nil end
  local base = (T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()) or {}
  local child = (T.GetChildProfessionInfo and T.GetChildProfessionInfo()) or {}
  local p = (child.professionName and child.professionName ~= "") and child or base
  if not p.professionName or p.professionName == "" then return nil end
  local key = p.professionID or p.professionName
  local prof = { name = p.professionName, rank = p.skillLevel or 0, max = p.maxSkillLevel or 0, at = GetServerTime(), recipes = {} }
  for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local ok, r = pcall(readRecipe, id)
    if ok and r and r.name then prof.recipes[id] = r end
  end
  -- one record per profession: an older one saved under another key (its expansion's) goes
  for k, p in pairs(store()) do
    if k ~= key and p.name == prof.name then store()[k] = nil end
  end
  store()[key] = prof
  self.current = prof
  MOTA:Fire("WORKSHOP_CHANGED")
  return prof
end

-- This character's professions, as last seen.
function Workshop:Mine() return store() end

-- Every material this character's learned recipes use, for the auction house scan.
function Workshop:Materials()
  local ids, seen = {}, {}
  for pass = 1, 1 do
    for _, prof in pairs(store()) do
      for _, r in pairs(prof.recipes or {}) do
        if (pass == 1) == (r.learned ~= false) then
          for _, m in ipairs(r.mats or {}) do
            if not seen[m.item] then seen[m.item] = true; ids[#ids + 1] = m.item end
          end
        end
      end
    end
  end
  return ids
end

-- Learned recipes' results, for the scan too (their sale price and depth).
function Workshop:Results()
  local ids, seen = {}, {}
  for _, prof in pairs(store()) do
    for _, r in pairs(prof.recipes or {}) do
      if r.learned ~= false and r.item and not seen[r.item] then seen[r.item] = true; ids[#ids + 1] = r.item end
    end
  end
  return ids
end

---------------------------------------------------------------------------
-- Prices (Auctionator)
---------------------------------------------------------------------------

function Workshop:HasPrices()
  return Auctionator ~= nil and Auctionator.API ~= nil and Auctionator.API.v1 ~= nil
    and Auctionator.API.v1.GetAuctionPriceByItemID ~= nil
end

-- The auction price of one, in copper, and its age in days; nil when Auctionator has none.
function Workshop:Price(id)
  if not id or not self:HasPrices() then return nil end
  local api = Auctionator.API.v1
  local ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, id)
  if not ok or type(price) ~= "number" or price <= 0 then return nil end
  local age
  if api.GetAuctionAgeByItemID then
    local okA, a = pcall(api.GetAuctionAgeByItemID, CALLER, id)
    if okA then age = a end
  end
  return price, age
end

-- What a vendor pays for one (for a craft nobody lists).
function Workshop:Vendor(id)
  local sell = id and select(11, itemInfo(id))
  return type(sell) == "number" and sell > 0 and sell or nil
end

---------------------------------------------------------------------------
-- Batches (Duncan, 14 Nov): one cheap listing doesn't price fifty crafts. Materials are
-- bought up the price levels our own scans saw (Market.lua), cheapest first; with no scan,
-- Auctionator's cheapest price stands in for every one, and the line says so.
---------------------------------------------------------------------------

Workshop.BATCHES = { 1, 5, 20, 50 }

function Workshop:Batch()
  local s = MOTA.db and MOTA.db.settings
  return (s and s.workshopBatch) or 1
end

function Workshop:SetBatch(n)
  if MOTA.db and MOTA.db.settings then MOTA.db.settings.workshopBatch = n end
  MOTA:Fire("WORKSHOP_CHANGED")
end

-- One material for n crafts: { item, need, cost, got, src = "scan" | "auctionator" | nil, age }
function Workshop:Material(m, n)
  local need = m.count * n
  local out = { item = m.item, need = need }
  local Market = MOTA.Market
  local cost, got, age
  if Market then cost, got, age = Market:Buy(m.item, need) end
  if cost and got > 0 then
    out.cost, out.got, out.age, out.src = cost, got, age, "scan"
    if got < need then
      -- more than is listed: the rest at the dearest level seen, and flagged short
      local levels = Market:Levels(m.item)
      out.cost = cost + (need - got) * levels[#levels].p
      out.short = true
    end
    return out
  end
  local p, days = self:Price(m.item)
  if p then out.cost, out.got, out.src, out.days = p * need, need, "auctionator", days end
  return out
end

-- The materials' cost for one craft when making n (n defaults to the chosen batch), how many
-- materials have no price, which are short on the market, and the per-material detail.
function Workshop:Cost(r, n)
  n = n or self:Batch()
  local total, missing, short, mats, scanned = 0, 0, {}, {}, 0
  for _, m in ipairs(r.mats) do
    local d = self:Material(m, n)
    mats[#mats + 1] = d
    if d.cost then total = total + d.cost else missing = missing + 1 end
    if d.short then short[#short + 1] = d end
    if d.src == "scan" then scanned = scanned + 1 end
  end
  return math.floor(total / n + 0.5), missing, short, mats, scanned
end

-- What one sells for: the cheapest listing our scan saw, else Auctionator's.
function Workshop:SalePrice(id)
  local Market = MOTA.Market
  local p, age
  if Market then p, age = Market:Lowest(id) end
  if p then return p, nil, "scan", age end
  local a, days = self:Price(id)
  if a then return a, days, "auctionator" end
end

-- One recipe's numbers at the chosen batch size:
-- { id, r, n, cost (per craft), missing, short, mats, scanned, sale, profit, age, saleSrc }
function Workshop:Value(id, r)
  local n = self:Batch()
  local cost, missing, short, mats, scanned = self:Cost(r, n)
  local price, age, saleSrc = self:SalePrice(r.item)
  local v = { id = id, r = r, n = n, cost = cost, missing = missing, short = short, mats = mats, scanned = scanned, age = age, saleSrc = saleSrc }
  if price then
    v.sale = price * (r.made or 1)
    v.profit = math.floor(v.sale * (1 - self.CUT)) - cost
  else
    local vendor = self:Vendor(r.item)
    if vendor then v.vendor = vendor * (r.made or 1); v.vendorProfit = v.vendor - cost end
  end
  return v
end

---------------------------------------------------------------------------
-- The three lists
---------------------------------------------------------------------------

local function each(prof, learned, fn)
  local out = {}
  for id, r in pairs(prof and prof.recipes or {}) do
    if r.learned == learned then
      local v = fn(id, r)
      if v then out[#out + 1] = v end
    end
  end
  return out
end

-- Learned recipes with a price, most profit first; those with unpriced materials last.
function Workshop:Profit(prof)
  local list = each(prof, true, function(id, r) local v = Workshop:Value(id, r) if v.sale then return v end end)
  table.sort(list, function(a, b)
    if (a.missing > 0) ~= (b.missing > 0) then return a.missing == 0 end
    if a.profit ~= b.profit then return a.profit > b.profit end
    return a.r.name < b.r.name
  end)
  return list
end

-- Learned recipes that still give skill, ranked by what each expected point costs after
-- selling the result (a craft that makes money and levels comes first).
function Workshop:Levelling(prof)
  local list = each(prof, true, function(id, r)
    local chance = Workshop.CHANCE[r.colour] or 0
    if chance <= 0 then return nil end
    local v = Workshop:Value(id, r)
    v.chance = chance
    local back = v.sale and math.floor(v.sale * (1 - Workshop.CUT)) or v.vendor or 0
    v.net = v.cost - back -- what a craft really costs once its result is sold
    v.perPoint = v.net / chance
    return v
  end)
  table.sort(list, function(a, b)
    if (a.missing > 0) ~= (b.missing > 0) then return a.missing == 0 end
    if a.perPoint ~= b.perPoint then return a.perPoint < b.perPoint end
    return a.r.name < b.r.name
  end)
  return list
end

-- Unlearned recipes with a price, most profit first.
function Workshop:ToLearn(prof)
  local list = each(prof, false, function(id, r) local v = Workshop:Value(id, r) if v.sale then return v end end)
  table.sort(list, function(a, b)
    if (a.missing > 0) ~= (b.missing > 0) then return a.missing == 0 end
    if a.profit ~= b.profit then return a.profit > b.profit end
    return a.r.name < b.r.name
  end)
  return list
end

-- "1g 2s 30c", short: "1g 2s" above a gold, "-45c" for a loss.
function Workshop:Money(c)
  if not c then return "?" end
  local neg = c < 0
  c = math.abs(math.floor(c + 0.5))
  local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local txt
  if g > 0 then txt = g .. "g " .. s .. "s"
  elseif s > 0 then txt = s .. "s " .. cp .. "c"
  else txt = cp .. "c" end
  return (neg and "-" or "") .. txt
end

-- Rescan as the window changes (learning a recipe, skill going up).
local watch = CreateFrame("Frame")
for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED" }) do
  pcall(watch.RegisterEvent, watch, ev)
end
watch:SetScript("OnEvent", function(_, ev)
  if ev == "TRADE_SKILL_SHOW" then Workshop.open = true end
  if Workshop.pending then return end
  Workshop.pending = true
  C_Timer.After(0.3, function()
    Workshop.pending = false
    if Workshop.open then Workshop:Scan() end
  end)
end)
local close = CreateFrame("Frame")
pcall(close.RegisterEvent, close, "TRADE_SKILL_CLOSE")
close:SetScript("OnEvent", function()
  Workshop.open = false
  MOTA:Fire("WORKSHOP_CLOSED")
end)
