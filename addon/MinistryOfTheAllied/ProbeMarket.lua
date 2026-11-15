-- Ministry of the Allied: the market probe (Duncan, 14 Nov 2026).
-- Before building the crafting guide (what this character should craft, for profit and for
-- skill, and how likely it is to sell), find out what the Forever client lets an add-on see.
-- Only looks and searches. It never buys, posts or crafts.
--
-- /mota probe craft    with a profession window open: recipes, difficulty colours, materials, skill
-- /mota probe market   with the auction house open: Auctionator's prices, one search of the
--                      auction house (are sellers and time left shown?), the sales mail functions
--
-- Results are printed in chat and saved (on logout or /reload) under probe.craft and probe.market
-- in WTF\Account\<account>\SavedVariables\MinistryOfTheAllied.lua.

local _, MOTA = ...
local Probe = MOTA.Probe

local function P(...) MOTA:Print(...) end
local function yes(v) return v and MOTA:Color("leaf", "yes") or MOTA:Color("crimson", "no") end

-- "C_TradeSkillUI.GetRecipeInfo" -> the function, or nil
local function find(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return v
end

-- Which of these the client has: out[name] = true/false; returns the missing ones.
local function check(out, list)
  local missing = {}
  for _, name in ipairs(list) do
    out[name] = find(name) ~= nil
    if not out[name] then missing[#missing + 1] = name end
  end
  return missing
end

-- Forever has C_Item's versions, not the old globals (probe, 14 Nov).
local function GetItemInfo(id)
  local f = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
  if f then return f(id) end
end
local function GetItemCount(id, bank)
  local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
  return f and f(id, bank) or nil
end

local function itemID(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

local function money(c)
  if type(c) ~= "number" then return tostring(c) end
  return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
end

local function save(key, out)
  MOTA.db.probe = MOTA.db.probe or {}
  MOTA.db.probe[key] = out
end

---------------------------------------------------------------------------
-- /mota probe craft
---------------------------------------------------------------------------

local CLASSIC_TRADE = { "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillLine", "GetTradeSkillItemLink",
  "GetTradeSkillRecipeLink", "GetTradeSkillNumMade", "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo",
  "GetTradeSkillReagentItemLink", "GetTradeSkillCooldown" }
local CLASSIC_CRAFT = { "GetNumCrafts", "GetCraftInfo", "GetCraftDisplaySkillLine", "GetCraftItemLink",
  "GetCraftNumReagents", "GetCraftReagentInfo", "GetCraftReagentItemLink" } -- Enchanting's own window in Classic
local MODERN_TRADE = { "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.GetRecipeSchematic",
  "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetChildProfessionInfo", "C_TradeSkillUI.IsTradeSkillReady" }
local SKILL_LINES = { "GetNumSkillLines", "GetSkillLineInfo", "GetProfessions", "GetProfessionInfo" }

-- The character's professions and levels, from whichever list the client has.
local function skills()
  local list = {}
  if GetProfessions and GetProfessionInfo then
    for _, idx in ipairs({ GetProfessions() }) do
      if idx then
        local name, _, rank, max = GetProfessionInfo(idx)
        list[#list + 1] = { name = name, rank = rank, max = max }
      end
    end
  end
  if #list == 0 and GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
      if not header and name and max and max > 1 then list[#list + 1] = { name = name, rank = rank, max = max } end
    end
  end
  return list
end

-- The first few recipes of the open Classic trade skill window.
local function classicSample(out)
  local n = GetNumTradeSkills() or 0
  local line, rank, max = GetTradeSkillLine()
  out.window = { name = line, rank = rank, max = max, rows = n, recipes = 0, colours = {} }
  out.sample = {}
  for i = 1, n do
    local name, kind = GetTradeSkillInfo(i)
    if kind ~= "header" and kind ~= "subheader" then
      out.window.recipes = out.window.recipes + 1
      out.window.colours[kind or "?"] = (out.window.colours[kind or "?"] or 0) + 1
      if #out.sample < 3 then
        local r = { name = name, colour = kind, link = GetTradeSkillItemLink(i), made = GetTradeSkillNumMade and GetTradeSkillNumMade(i), mats = {} }
        r.item = itemID(r.link)
        for j = 1, (GetTradeSkillNumReagents(i) or 0) do
          local mname, _, count, have = GetTradeSkillReagentInfo(i, j)
          local mlink = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j)
          r.mats[#r.mats + 1] = { name = mname, count = count, have = have, item = itemID(mlink) }
        end
        out.sample[#out.sample + 1] = r
      end
    end
  end
end

-- The same for Enchanting's Craft window in Classic.
local function craftSample(out)
  local n = GetNumCrafts() or 0
  local line, rank, max = GetCraftDisplaySkillLine()
  out.window = { name = line, rank = rank, max = max, rows = n, recipes = 0, colours = {}, craftWindow = true }
  out.sample = {}
  for i = 1, n do
    local name, _, kind = GetCraftInfo(i)
    if kind ~= "header" then
      out.window.recipes = out.window.recipes + 1
      out.window.colours[kind or "?"] = (out.window.colours[kind or "?"] or 0) + 1
      if #out.sample < 3 then
        local r = { name = name, colour = kind, link = GetCraftItemLink and GetCraftItemLink(i), mats = {} }
        for j = 1, (GetCraftNumReagents(i) or 0) do
          local mname, _, count, have = GetCraftReagentInfo(i, j)
          local mlink = GetCraftReagentItemLink and GetCraftReagentItemLink(i, j)
          r.mats[#r.mats + 1] = { name = mname, count = count, have = have, item = itemID(mlink) }
        end
        out.sample[#out.sample + 1] = r
      end
    end
  end
end

-- The modern profession window (C_TradeSkillUI), which Forever has instead (probe, 14 Nov).
-- Two shapes of it exist: GetRecipeSchematic (newer) and GetRecipeNumReagents (older); both are tried.
local DIFF = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
local function modernRecipe(id)
  local T = C_TradeSkillUI
  local info = T.GetRecipeInfo(id) or {}
  local r = { id = id, name = info.name, learned = info.learned, mats = {} }
  r.colour = info.difficulty or (info.relativeDifficulty and DIFF[info.relativeDifficulty]) or "?"
  r.skillUps = info.numSkillUps
  r.link = info.hyperlink or (T.GetRecipeItemLink and T.GetRecipeItemLink(id))
  local s = T.GetRecipeSchematic and T.GetRecipeSchematic(id, false)
  if s and s.reagentSlotSchematics then
    r.item = s.outputItemID
    r.made = s.quantityMin
    for _, slot in ipairs(s.reagentSlotSchematics) do
      local first = slot.reagents and slot.reagents[1]
      local mid = first and first.itemID
      local mname = mid and GetItemInfo(mid)
      r.mats[#r.mats + 1] = { name = mname or ("item " .. tostring(mid)), count = slot.quantityRequired, item = mid,
        have = mid and GetItemCount(mid, true) or nil }
    end
  elseif T.GetRecipeNumReagents then
    r.item = itemID(r.link)
    for j = 1, T.GetRecipeNumReagents(id) or 0 do
      local mname, _, count, have = T.GetRecipeReagentInfo(id, j)
      local mlink = T.GetRecipeReagentItemLink and T.GetRecipeReagentItemLink(id, j)
      r.mats[#r.mats + 1] = { name = mname, count = count, have = have, item = itemID(mlink) }
    end
  end
  r.item = r.item or itemID(r.link)
  return r
end

local function modernSample(out)
  local T = C_TradeSkillUI
  local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo() or {}
  local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo() or {}
  out.rawBase, out.rawChild = base, child -- what Forever calls the fields, if the name comes back blank
  if (child.professionName or base.professionName or "") == "" and T.GetTradeSkillLine then
    local n, r, m = T.GetTradeSkillLine()
    base = { professionName = n, skillLevel = r, maxSkillLevel = m }
  end
  out.window = { name = child.professionName or base.professionName, rank = child.skillLevel or base.skillLevel,
    max = child.maxSkillLevel or base.maxSkillLevel, recipes = 0, unlearned = 0, colours = {}, modern = true }
  out.sample, out.all = {}, {}
  local gear, stack
  for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local ok, r = pcall(modernRecipe, id)
    if ok and r then
      if r.learned == false then
        out.window.unlearned = out.window.unlearned + 1
      else
        out.window.recipes = out.window.recipes + 1
        out.window.colours[r.colour] = (out.window.colours[r.colour] or 0) + 1
        out.all[#out.all + 1] = { id = id, name = r.name, colour = r.colour, item = r.item }
        if #out.sample < 3 then out.sample[#out.sample + 1] = r end
        -- one crafted item that doesn't stack (gear) and one that does, for /mota probe market
        local stackSize = r.item and select(8, GetItemInfo(r.item))
        if r.item and stackSize == 1 and not gear then gear = r end
        if r.item and stackSize and stackSize > 1 and not stack then stack = r end
      end
    elseif not ok then
      out.recipeError = tostring(r)
    end
  end
  out.gear = gear and { item = gear.item, name = gear.name }
  out.stack = stack and { item = stack.item, name = stack.name }
end

function Probe:Craft()
  local out = { at = GetServerTime(), apis = {} }
  local missClassic = check(out.apis, CLASSIC_TRADE)
  local missCraft = check(out.apis, CLASSIC_CRAFT)
  local missModern = check(out.apis, MODERN_TRADE)
  check(out.apis, SKILL_LINES)
  P(MOTA:Color("leaf", "Craft probe") .. ":")
  P("  Classic profession window functions:", #missClassic == 0 and yes(true) or ("missing " .. table.concat(missClassic, ", ")))
  P("  Enchanting's Craft window functions:", #missCraft == 0 and yes(true) or ("missing " .. #missCraft))
  P("  Modern profession functions (C_TradeSkillUI):", #missModern == 0 and yes(true) or ("missing " .. #missModern))

  out.skills = skills()
  local names = {}
  for _, s in ipairs(out.skills) do names[#names + 1] = ("%s %s/%s"):format(tostring(s.name), tostring(s.rank), tostring(s.max)) end
  P("  Skills the game lists:", #names > 0 and table.concat(names, ", ") or "none found")

  local ok, err = pcall(function()
    if #missClassic == 0 and (GetNumTradeSkills() or 0) > 0 then
      classicSample(out)
    elseif #missCraft == 0 and (GetNumCrafts() or 0) > 0 then
      craftSample(out)
    elseif #missModern == 0 and C_TradeSkillUI.IsTradeSkillReady() then
      modernSample(out)
    end
  end)
  if not ok then out.error = tostring(err); P("  " .. MOTA:Color("crimson", "Error reading the window: ") .. out.error) end

  if out.window then
    local w = out.window
    local cols = {}
    for k, v in pairs(w.colours) do cols[#cols + 1] = k .. " " .. v end
    P(("  Open window: %s %s/%s, %d recipes (%s)"):format(tostring(w.name), tostring(w.rank), tostring(w.max), w.recipes, table.concat(cols, ", ")))
    if w.modern then
      P(("  Recipes not yet learned that the game also lists: %d"):format(w.unlearned))
      P("  For the market probe: gear " .. (out.gear and (out.gear.name .. " (" .. out.gear.item .. ")") or "none found") ..
        ", stackable " .. (out.stack and (out.stack.name .. " (" .. out.stack.item .. ")") or "none found"))
      if out.recipeError then P("  " .. MOTA:Color("crimson", "A recipe failed to read: ") .. out.recipeError) end
    end
    for _, r in ipairs(out.sample) do
      local mats = {}
      for _, m in ipairs(r.mats) do mats[#mats + 1] = ("%dx %s%s"):format(m.count or 0, tostring(m.name), m.item and "" or " (no item ID)") end
      P(("  - %s [%s] item %s: %s"):format(tostring(r.name), tostring(r.colour), tostring(r.item or "?"), table.concat(mats, ", ")))
    end
    self.lastCraft = out
  elseif ok then
    P("  No profession window open. Open one (Tailoring, say) and run it again.")
  end
  save("craft", out)
  P("Saved. It writes to the saved file on /reload.")
end

---------------------------------------------------------------------------
-- /mota probe market
---------------------------------------------------------------------------

local AUCTIONATOR = { "Auctionator.API.v1.GetAuctionPriceByItemID", "Auctionator.API.v1.GetAuctionAgeByItemID",
  "Auctionator.API.v1.GetVendorPriceByItemID", "Auctionator.API.v1.GetAuctionPriceByItemLink" }
local CLASSIC_AH = { "QueryAuctionItems", "CanSendAuctionQuery", "GetNumAuctionItems", "GetAuctionItemInfo",
  "GetAuctionItemTimeLeft", "GetAuctionItemLink" }
local MODERN_AH = { "C_AuctionHouse.SendSearchQuery", "C_AuctionHouse.GetItemSearchResultInfo",
  "C_AuctionHouse.GetCommoditySearchResultInfo", "C_AuctionHouse.MakeItemKey" }
local MAIL = { "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxInvoiceInfo" }

local SAMPLE_ITEM, SAMPLE_NAME = 2589, "Linen Cloth" -- if the craft probe found no material to try
local TIME_LEFT = { "under 30 min", "30 min to 2 h", "2 to 12 h", "over 12 h" }

local watcher, pendingSearch

local function readSearch()
  local out = pendingSearch
  pendingSearch = nil
  if not out then return end
  local s = out.search
  local n, total = GetNumAuctionItems("list")
  s.shown, s.total = n, total
  s.rows = {}
  for i = 1, math.min(n or 0, 5) do
    local name, _, count, _, _, _, _, minBid, _, buyout, _, _, _, owner = GetAuctionItemInfo("list", i)
    local left = GetAuctionItemTimeLeft("list", i)
    s.rows[i] = { name = name, count = count, bid = minBid, buyout = buyout, owner = owner, left = left }
  end
  local owners = 0
  for _, r in ipairs(s.rows) do if r.owner and r.owner ~= "" then owners = owners + 1 end end
  P(("  Search for %s: %s listings (%s on this page)"):format(s.name, tostring(total), tostring(n)))
  for _, r in ipairs(s.rows) do
    P(("  - %sx %s, buyout %s, seller %s, time left %s"):format(tostring(r.count), tostring(r.name), money(r.buyout),
      tostring(r.owner or "hidden"), TIME_LEFT[r.left or 0] or tostring(r.left)))
  end
  s.sellersShown = #s.rows > 0 and owners == #s.rows
  P("  Sellers shown:", #s.rows > 0 and yes(s.sellersShown) or "no listings to tell", "· time left shown:", #s.rows > 0 and yes(s.rows[1].left ~= nil) or "no listings to tell")
  P("  (Sellers' names sometimes arrive a moment late. If they say hidden, run it again.)")
  save("market", out)
  P("Saved. It writes to the saved file on /reload.")
end

---------------------------------------------------------------------------
-- The modern auction house (C_AuctionHouse), which Forever has instead (probe, 14 Nov).
-- Two searches: one item that doesn't stack (gear: each listing its own, with a seller, as
-- Duncan saw on hover) and one that does (bars, potions: grouped by price on screen). The
-- first comes from the slash command; the second from a timer two seconds later, with no
-- click, to learn whether the add-on can search by itself while the auction house is open.
---------------------------------------------------------------------------

local BAND = { [0] = "under 30 min", [1] = "30 min to 2 h", [2] = "2 to 12 h", [3] = "12 to 48 h" }
local GEAR_ID, STACK_ID = 25, 2840 -- Worn Shortsword, Copper Bar: when the craft probe found none
local modernRun

local function ownersText(o, total)
  if type(o) ~= "table" or #o == 0 then return total and total > 0 and (total .. " (names hidden)") or "hidden" end
  local s = table.concat(o, ", ")
  if total and total > #o then s = s .. " +" .. (total - #o) end
  return s
end

local function summarise(s, rows)
  local ids, sellers, left = 0, 0, 0
  for _, r in ipairs(rows) do
    if r.auctionID then ids = ids + 1 end
    if type(r.owners) == "table" and #r.owners > 0 then sellers = sellers + 1 end
    if r.left then left = left + 1 end
  end
  s.withIDs, s.withSellers, s.withTimeLeft = ids, sellers, left
  local n = #rows
  P(("  Of %d rows: auction IDs %d, sellers named %d, time left %d"):format(n, ids, sellers, left))
end

local function readItem(run)
  local AH, s = C_AuctionHouse, run.out.itemSearch
  s.answered = true
  local n = AH.GetNumItemSearchResults(run.itemKey) or 0
  s.count, s.full = n, AH.HasFullItemSearchResults and AH.HasFullItemSearchResults(run.itemKey)
  s.rows = {}
  for i = 1, n do
    local info = AH.GetItemSearchResultInfo(run.itemKey, i)
    if info then
      s.rows[#s.rows + 1] = { auctionID = info.auctionID, owners = info.owners, ownersTotal = info.totalNumberOfOwners,
        quantity = info.quantity, buyout = info.buyoutAmount, bid = info.bidAmount, left = info.timeLeft }
    end
  end
  P(("  Item search, %s (%d): %d listings"):format(s.name, s.id, n))
  for i = 1, math.min(5, #s.rows) do
    local r = s.rows[i]
    P(("  - #%s: %sx, buyout %s, seller %s, time left %s"):format(tostring(r.auctionID), tostring(r.quantity), money(r.buyout),
      ownersText(r.owners, r.ownersTotal), BAND[r.left or -1] or tostring(r.left)))
  end
  summarise(s, s.rows)
end

local function readStack(run)
  local AH, s = C_AuctionHouse, run.out.stackSearch
  s.answered = true
  local n = AH.GetNumCommoditySearchResults(s.id) or 0
  s.count, s.full = n, AH.HasFullCommoditySearchResults and AH.HasFullCommoditySearchResults(s.id)
  s.rows = {}
  local total = 0
  for i = 1, n do
    local info = AH.GetCommoditySearchResultInfo(s.id, i)
    if info then
      total = total + (info.quantity or 0)
      s.rows[#s.rows + 1] = { auctionID = info.auctionID, owners = info.owners, ownersTotal = info.totalNumberOfOwners,
        quantity = info.quantity, price = info.unitPrice, left = info.timeLeftSeconds, mine = info.numOwnerItems }
    end
  end
  s.quantity = total
  P(("  Stackable search, %s (%d): %d rows, %d for sale in all"):format(s.name, s.id, n, total))
  for i = 1, math.min(5, #s.rows) do
    local r = s.rows[i]
    P(("  - #%s: %sx at %s each, seller %s, time left %s"):format(tostring(r.auctionID), tostring(r.quantity), money(r.price),
      ownersText(r.owners, r.ownersTotal), r.left and (math.floor(r.left / 60) .. " min") or "not given"))
  end
  summarise(s, s.rows)
end

local function finishModern(run, why)
  if modernRun ~= run then return end
  modernRun = nil
  run.frame:UnregisterAllEvents()
  if why then P("  " .. why) end
  save("market", run.out)
  P("Saved. It writes to the saved file on /reload.")
end

local function sendStack(run)
  local AH, s = C_AuctionHouse, run.out.stackSearch
  s.byTimer = true -- no click: does the game take it?
  local ok, err = pcall(AH.SendSearchQuery, AH.MakeItemKey(s.id), run.sorts, false)
  if not ok then s.error = tostring(err); finishModern(run, MOTA:Color("crimson", "The second search failed: ") .. s.error); return end
  P("  Searching for " .. s.name .. " by itself, with no click...")
  C_Timer.After(10, function()
    if modernRun == run and not s.answered then
      finishModern(run, MOTA:Color("crimson", "No answer to the search with no click.") .. " Searches may need a click on Forever.")
    end
  end)
end

local function modernMarket(out, craft)
  local AH = C_AuctionHouse
  local gear = craft and craft.gear or { item = GEAR_ID, name = "Worn Shortsword" }
  local stack = craft and craft.stack or { item = STACK_ID, name = "Copper Bar" }
  out.itemSearch = { id = gear.item, name = gear.name or GetItemInfo(gear.item) or ("item " .. gear.item) }
  out.stackSearch = { id = stack.item, name = stack.name or GetItemInfo(stack.item) or ("item " .. stack.item) }
  -- Optional: on Forever it wants an item in your bags, not an item ID (probe, 14 Nov), so it may refuse.
  if AH.GetItemCommodityStatus then
    local ok1, a = pcall(AH.GetItemCommodityStatus, gear.item)
    local ok2, b = pcall(AH.GetItemCommodityStatus, stack.item)
    out.itemSearch.status = ok1 and a or nil
    out.stackSearch.status = ok2 and b or nil
  end
  save("market", out) -- what's known so far, in case a search stalls
  local run = { out = out, itemKey = AH.MakeItemKey(gear.item), frame = CreateFrame("Frame") }
  local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
  run.sorts = { { sortOrder = order, reverseSort = false } }
  modernRun = run
  run.frame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  run.frame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  run.frame:SetScript("OnEvent", function(_, ev, a)
    if modernRun ~= run then return end
    if ev == "ITEM_SEARCH_RESULTS_UPDATED" and not out.itemSearch.answered then
      C_Timer.After(0.5, function()
        if modernRun ~= run or out.itemSearch.answered then return end
        local ok, err = pcall(readItem, run)
        if not ok then out.itemSearch.answered, out.itemSearch.readError = true, tostring(err); P("  " .. MOTA:Color("crimson", "Reading the item search failed: ") .. tostring(err)) end
        save("market", out)
        C_Timer.After(2, function() if modernRun == run then sendStack(run) end end)
      end)
    elseif ev == "COMMODITY_SEARCH_RESULTS_UPDATED" then
      if a == out.itemSearch.id and not out.itemSearch.answered then
        out.itemSearch.answered = true
        out.itemSearch.stacks = true
        P("  " .. out.itemSearch.name .. " came back as a stackable, not gear.")
        C_Timer.After(2, function() if modernRun == run then sendStack(run) end end)
      elseif a == out.stackSearch.id and not out.stackSearch.answered then
        C_Timer.After(0.5, function()
          if modernRun ~= run or out.stackSearch.answered then return end
          local ok, err = pcall(readStack, run)
          if not ok then out.stackSearch.answered, out.stackSearch.readError = true, tostring(err); P("  " .. MOTA:Color("crimson", "Reading the stackable search failed: ") .. tostring(err)) end
          finishModern(run)
        end)
      end
    end
  end)
  local ok, err = pcall(AH.SendSearchQuery, run.itemKey, run.sorts, false)
  if not ok then
    out.itemSearch.error = tostring(err)
    finishModern(run, MOTA:Color("crimson", "The search failed: ") .. out.itemSearch.error)
    return
  end
  P("  Searching for " .. out.itemSearch.name .. "...")
  C_Timer.After(10, function()
    if modernRun == run and not out.itemSearch.answered then
      out.itemSearch.answered = true
      P("  " .. MOTA:Color("crimson", "No answer to the first search.") .. " Trying the stackable anyway.")
      sendStack(run)
    end
  end)
end

function Probe:Market()
  local out = { at = GetServerTime(), apis = {} }
  local missA = check(out.apis, AUCTIONATOR)
  local missC = check(out.apis, CLASSIC_AH)
  local missM = check(out.apis, MODERN_AH)
  local missMail = check(out.apis, MAIL)
  P(MOTA:Color("leaf", "Market probe") .. ":")
  P("  Auctionator's price functions:", #missA == 0 and yes(true) or (find("Auctionator") and ("missing " .. table.concat(missA, ", ")) or MOTA:Color("crimson", "Auctionator isn't loaded")))
  P("  Classic auction house search:", #missC == 0 and yes(true) or ("missing " .. table.concat(missC, ", ")))
  P("  Modern auction house search (C_AuctionHouse):", #missM == 0 and yes(true) or ("missing " .. #missM))
  P("  Sales mail functions:", #missMail == 0 and yes(true) or ("missing " .. table.concat(missMail, ", ")))

  -- Auctionator's prices for a crafted item and its materials (from /mota probe craft), else Linen Cloth
  local items = {}
  local craft = self.lastCraft or (MOTA.db.probe and MOTA.db.probe.craft)
  if craft and craft.sample and craft.sample[1] then
    local r = craft.sample[1]
    if r.item then items[#items + 1] = { id = r.item, name = r.name } end
    for _, m in ipairs(r.mats) do if m.item then items[#items + 1] = { id = m.item, name = m.name } end end
  end
  if #items == 0 then items[1] = { id = SAMPLE_ITEM, name = SAMPLE_NAME } end
  out.prices = {}
  if #missA == 0 then
    local api = Auctionator.API.v1
    for _, it in ipairs(items) do
      local ok, price = pcall(api.GetAuctionPriceByItemID, "MinistryOfTheAllied", it.id)
      local okAge, age = pcall(api.GetAuctionAgeByItemID, "MinistryOfTheAllied", it.id)
      local okV, vendor = pcall(api.GetVendorPriceByItemID, "MinistryOfTheAllied", it.id)
      local p = { id = it.id, name = it.name, price = ok and price or ("error: " .. tostring(price)),
        age = okAge and age or nil, vendor = okV and vendor or nil }
      out.prices[#out.prices + 1] = p
      P(("  - %s (%d): Auctionator %s, %s days old, vendor %s"):format(tostring(it.name), it.id,
        type(p.price) == "number" and money(p.price) or tostring(p.price), tostring(p.age), p.vendor and money(p.vendor) or "?"))
    end
  end

  -- Forever's modern auction house: two searches (above)
  if #missC > 0 and #missM == 0 then
    if modernRun and GetServerTime() - modernRun.out.at < 30 then P("  Already searching. Wait for it to finish."); return end
    modernRun = nil
    if not Probe.atAuctionHouse then
      P("  Open the auction house and run it again to test the searches.")
      save("market", out)
      P("Saved. It writes to the saved file on /reload.")
      return
    end
    modernMarket(out, craft)
    return
  end

  -- One search of the auction house, to see what a listing tells us
  local open = AuctionFrame and AuctionFrame:IsShown()
  if #missC == 0 and open then
    if not CanSendAuctionQuery() then
      P("  The auction house isn't ready for a search yet (the game limits how often). Wait a few seconds and run it again.")
      save("market", out)
      return
    end
    local name = items[#items] and items[#items].name or SAMPLE_NAME
    out.search = { name = name }
    pendingSearch = out
    if not watcher then
      watcher = CreateFrame("Frame")
      watcher:SetScript("OnEvent", function(f)
        f:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
        C_Timer.After(0.5, readSearch) -- the list fills a moment after the event
      end)
    end
    watcher:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
    local ok, err = pcall(QueryAuctionItems, name, nil, nil, 0, false, nil, false, true)
    if not ok then
      watcher:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
      pendingSearch = nil
      out.search.error = tostring(err)
      P("  " .. MOTA:Color("crimson", "The search failed: ") .. out.search.error)
      save("market", out)
    else
      P("  Searching the auction house for " .. name .. "...")
    end
  else
    if #missC == 0 then P("  Open the auction house and run it again to test a search.") end
    save("market", out)
    P("Saved. It writes to the saved file on /reload.")
  end
end

-- Is the auction house open? (Forever's frame may not be the one either client names.)
local ah = CreateFrame("Frame")
for _, ev in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do pcall(ah.RegisterEvent, ah, ev) end
ah:SetScript("OnEvent", function(_, ev) Probe.atAuctionHouse = ev == "AUCTION_HOUSE_SHOW" end)
