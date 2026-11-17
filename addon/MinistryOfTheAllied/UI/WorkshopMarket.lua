-- Ministry of the Allied: the Workshop's tab at the auction house (Duncan, 14 Nov 2026).
-- A tab along the auction house's bottom row, after Auctionator's, that opens the Workshop's
-- page inside the auction house window. Drawn like the game's own (Duncan, 14 Nov: the
-- parchment looked out of place): the game's tab, buttons, fonts and colours.
--
-- Two views:
--   Market  every item the Workshop watches: lowest and usual price, how many are listed, how
--           fast it sells, when it was last scanned
--   Crafts  every learned recipe of this character's professions, priced at the chosen batch
--           size: what the materials cost, what it sells for, the profit, the margin, how fast
--           it sells and so the profit a day. Sorted most profitable first, or hot sellers.
-- Any column's heading sorts by it; a second click turns the order round.
--
-- Choosing the tab works as Auctionator's own tabs do (LibAHTab): the auction house is told it
-- has no display mode, its tabs are deselected, and the page is shown; any other tab hides it.

local _, MOTA = ...
local Kit = MOTA.Kit
local W = MOTA.Workshop
local Panel = MOTA.WorkshopPanel
local Page = {}
MOTA.WorkshopMarket = Page

local ROW_H, ROWS = 20, 17
local GAIN, LOSS = "1EFF00", "FF2020"
local COLOUR = { optimal = "FF8040", medium = "FFFF00", easy = "40BF40", trivial = "808080" }

local tab, page, rows = nil, nil, {}
local top = 0
local view = "crafts"
local sorts = { market = { key = "name", up = true }, crafts = { key = "profit", up = false }, flips = { key = "at", up = false } }
local TIER = { low = "lowest", usual = "usual", high = "above", ["?"] = "no market data" }

local function money(c) return c and W:Money(c) or "-" end
local function signed(c) return c and ((c >= 0 and "+" or "") .. W:Money(c)) or "-" end

-- "5 min ago", "3 h ago", "2 days ago"
function Panel:Ago(s)
  if s < 90 then return "just now" end
  if s < 3600 then return math.floor(s / 60) .. " min ago" end
  if s < 2 * 86400 then return math.floor(s / 3600) .. " h ago" end
  return math.floor(s / 86400) .. " days ago"
end

-- The age of the freshest scan of any material, or nil.
function Panel:NewestScan()
  local newest
  for _, id in ipairs(W:Materials()) do
    local a = MOTA.Market:Age(id)
    if a and (not newest or a < newest) then newest = a end
  end
  return newest
end

local function scanList()
  local ids = W:Materials()
  for _, id in ipairs(W:Results()) do ids[#ids + 1] = id end
  return ids
end

---------------------------------------------------------------------------
-- The rows of each view
---------------------------------------------------------------------------

-- The watched items, with what the market knows of each.
function Page:Items()
  local out, M = {}, MOTA.Market
  local crafts = {}
  for _, id in ipairs(W:Results()) do crafts[id] = true end
  local seen = {}
  for _, id in ipairs(scanList()) do
    if not seen[id] then
      seen[id] = true
      local levels = M:Levels(id)
      local listed = 0
      for _, l in ipairs(levels or {}) do listed = listed + l.q end
      -- a flip: bought at the cheapest, sold at the usual price less the 5% cut
      local low, usual = M:Lowest(id), M:Normal(id)
      local profit = low and usual and (math.floor(usual * (1 - W.CUT)) - low) or nil
      out[#out + 1] = { id = id, name = W.ItemInfo(id) or ("item " .. id), craft = crafts[id],
        low = low, usual = usual, profit = profit, margin = profit and low > 0 and profit / low or nil,
        listed = levels and listed or nil,
        rate = (M:SellRate(id)), sells = M:RateText(id), age = M:Age(id) }
    end
  end
  return out
end

-- Every learned recipe this character has, priced: the cost/price comparison.
function Page:Crafts()
  local out, M = {}, MOTA.Market
  local seen = {} -- a profession can be saved twice (by its ID and by its expansion): each recipe once
  for _, prof in pairs(W:Mine()) do
    for id, r in pairs(prof.recipes or {}) do
      if r.learned ~= false and r.item and not seen[id] then
        seen[id] = true
        local v = W:Value(id, r)
        if v.sale then
          local made = r.made or 1
          local net = math.floor(v.sale * (1 - W.CUT))
          local rate = (M:SellRate(r.item))
          out[#out + 1] = { id = r.item, recipe = id, name = r.name, colour = r.colour, prof = prof.name,
            cost = v.cost, sale = net, gross = v.sale, cut = v.sale - net, profit = v.profit, margin = v.cost > 0 and v.profit / v.cost or nil,
            rate = rate, sells = M:RateText(r.item), perDay = rate and (v.profit / made * rate) or nil,
            missing = v.missing, short = #v.short > 0 }
        end
      end
    end
  end
  for _, f in ipairs(self:StraightFlips()) do out[#out + 1] = f end
  return out
end

-- Straight flips: every watched item (materials and crafts) bought from the cheapest listings at
-- the batch size and relisted at its usual price, after the cut. Priced per unit, so they rank
-- with the crafts (per craft) on the same columns. Only those that make money are listed.
Page.FLIP_COLOUR = "66CCFF"
function Page:StraightFlips()
  local out, M, n, seen = {}, MOTA.Market, W:Batch(), {}
  for _, id in ipairs(scanList()) do
    if not seen[id] then
      seen[id] = true
      local usual = M:Normal(id)
      local cost, got = M:Buy(id, n)
      if usual and cost and got and got > 0 then
        local each = cost / got
        local net = math.floor(usual * (1 - W.CUT))
        local profit = math.floor(net - each + 0.5)
        if profit > 0 then
          local rate = (M:SellRate(id))
          local name = W.ItemInfo(id) or ("item " .. id)
          out[#out + 1] = { id = id, straight = true, name = "Flip: " .. name, itemName = name,
            cost = math.floor(each + 0.5), sale = net, gross = usual, cut = usual - net, profit = profit,
            margin = each > 0 and profit / each or nil, rate = rate, sells = M:RateText(id),
            perDay = rate and profit * rate or nil, missing = 0, short = got < n, low = M:Lowest(id) }
        end
      end
    end
  end
  return out
end

function Page:StraightTip(it)
  GameTooltip:AddLine(it.name, 0.4, 0.8, 1)
  GameTooltip:AddDoubleLine("Buy at (cheapest " .. W:Batch() .. ")", money(it.cost) .. " each", 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Relist at the usual price", money(it.gross), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Auction house cut (5%)", "-" .. money(it.cut), 0.8, 0.8, 0.8, MOTA:RGB(LOSS))
  GameTooltip:AddDoubleLine("Profit each", signed(it.profit), 1, 1, 1, MOTA:RGB(GAIN))
  GameTooltip:AddLine("The usual price is the last week's median: a low price today may be a bargain, or the market falling. Check how fast it sells.", 0.6, 0.6, 0.6, true)
end

-- The flips (Flips.lua), newest first: what each cost, what's sold, the profit so far.
function Page:Flips()
  local out, F = {}, MOTA.Flips
  for _, f in ipairs(F:All()) do
    local s = F:Sum(f)
    out[#out + 1] = { id = f.makes or f.item, flip = f, sum = s, at = f.at,
      name = f.name .. (f.makesName and (" > " .. f.makesName) or ""),
      bought = s.bought, cost = s.cost, sold = s.sold, units = s.units, up = s.up, got = s.got,
      profit = f.closed and s.profit or s.outlook }
  end
  return out
end

-- The columns of each view: heading, width, alignment, the text and colour of a cell, and what
-- it sorts by.
local COLS = {
  market = {
    { key = "name", label = "Item", w = 190, justify = "LEFT", text = function(it) return it.name end,
      colour = function(it) return it.craft and "FFD100" or "FFFFFF" end },
    { key = "low", label = "Lowest", w = 76, text = function(it) return money(it.low) end },
    { key = "usual", label = "Usual", w = 76, text = function(it) return money(it.usual) end },
    { key = "profit", label = "Profit", w = 76, text = function(it) return signed(it.profit) end,
      colour = function(it) return not it.profit and "808080" or (it.profit >= 0 and GAIN or LOSS) end },
    { key = "margin", label = "Margin", w = 56, text = function(it) return it.margin and (math.floor(it.margin * 100 + 0.5) .. "%") or "-" end,
      colour = function(it) return not it.margin and "808080" or (it.margin >= 0 and GAIN or LOSS) end },
    { key = "listed", label = "Listed", w = 56, text = function(it) return it.listed and tostring(it.listed) or "-" end },
    { key = "rate", label = "Sells", w = 104, text = function(it) return it.sells or "no data yet" end,
      colour = function(it) return it.sells and "FFFFFF" or "808080" end },
    { key = "age", label = "Scanned", w = 80, text = function(it) return it.age and Panel:Ago(it.age) or "never" end,
      colour = function() return "808080" end },
  },
  crafts = {
    { key = "name", label = "Craft", w = 210, justify = "LEFT", text = function(it) return it.name end,
      colour = function(it) return it.straight and Page.FLIP_COLOUR or COLOUR[it.colour] or "FFD100" end },
    { key = "cost", label = "Materials", w = 86, text = function(it) return money(it.cost) .. (it.missing > 0 and "*" or "") end },
    { key = "sale", label = "Sells for", w = 86, text = function(it) return money(it.sale) end },
    { key = "profit", label = "Profit", w = 86, text = function(it) return signed(it.profit) end,
      colour = function(it) return it.profit >= 0 and GAIN or LOSS end },
    { key = "margin", label = "Margin", w = 64, text = function(it) return it.margin and (math.floor(it.margin * 100 + 0.5) .. "%") or "-" end,
      colour = function(it) return (it.margin or 0) >= 0 and "FFFFFF" or LOSS end },
    { key = "rate", label = "Sells", w = 104, text = function(it) return it.sells or "no data yet" end,
      colour = function(it) return it.sells and "FFFFFF" or "808080" end },
    { key = "perDay", label = "A day", w = 84, text = function(it) return it.perDay and signed(it.perDay) or "-" end,
      colour = function(it) return not it.perDay and "808080" or (it.perDay >= 0 and GAIN or LOSS) end },
  },
  flips = {
    { key = "name", label = "Flip", w = 220, justify = "LEFT", text = function(it) return it.name end,
      colour = function(it) return it.flip.closed and "808080" or "FFD100" end },
    { key = "bought", label = "Bought", w = 60, text = function(it) return it.flip.mats and "linked" or it.flip.usedIn and "used" or it.flip.own and "own" or tostring(it.bought) end },
    { key = "cost", label = "Cost", w = 84, text = function(it) return money(it.cost) .. (it.sum.est and "*" or "") end },
    { key = "up", label = "Listed", w = 60, text = function(it) return tostring(it.up) end },
    { key = "sold", label = "Sold", w = 70, text = function(it) return it.sold .. "/" .. it.units end },
    { key = "got", label = "Received", w = 90, text = function(it) return money(it.got) end },
    { key = "profit", label = "Profit", w = 110, text = function(it) return signed(it.profit) .. (it.flip.closed and "" or " ?") end,
      colour = function(it) return it.profit >= 0 and GAIN or LOSS end },
  },
}

-- Sorted by the chosen column; empty values last whichever way round.
function Page:Rows()
  local list = view == "crafts" and self:Crafts() or view == "flips" and self:Flips() or self:Items()
  local s = sorts[view]
  table.sort(list, function(a, b)
    local x, y = a[s.key], b[s.key]
    if x == nil and y == nil then return a.name < b.name end
    if x == nil then return false end
    if y == nil then return true end
    if type(x) == "string" then x, y = x:lower(), y:lower() end
    if x == y then return a.name < b.name end
    if s.up then return x < y end
    return x > y
  end)
  return list
end

function Page:SortBy(key)
  local s = sorts[view]
  if s.key == key then s.up = not s.up else s.key, s.up = key, key == "name" end
  top = 0
  self:Refresh()
end

function Page:View(v)
  view = v
  top = 0
  self:Refresh()
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function fontString(parent, template, justify)
  local t = parent:CreateFontString(nil, "OVERLAY", template)
  t:SetJustifyH(justify or "RIGHT")
  t:SetWordWrap(false)
  return t
end

local function button(parent, w, h, label, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local MAXCOLS = 8

local function buildPage(ah)
  page = CreateFrame("Frame", "MOTAWorkshopMarket", ah)
  page:SetPoint("TOPLEFT", ah, "TOPLEFT", 6, -24)
  page:SetPoint("BOTTOMRIGHT", ah, "BOTTOMRIGHT", -6, 28)
  page:SetFrameLevel(ah:GetFrameLevel() + 20)
  page:EnableMouse(true)
  -- the auction house's own dark backing, so the page reads as part of the window
  local bg = page:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.05, 0.05, 0.96)
  local edge = page:CreateTexture(nil, "BORDER")
  edge:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -96)
  edge:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -96)
  edge:SetHeight(1)
  edge:SetColorTexture(1, 0.82, 0, 0.35)

  page.title = fontString(page, "GameFontNormalLarge", "LEFT")
  page.title:SetPoint("TOPLEFT", page, "TOPLEFT", 72, -14)
  page.title:SetText("The Workshop")
  page.status = fontString(page, "GameFontHighlightSmall", "LEFT")
  page.status:SetPoint("TOPLEFT", page, "TOPLEFT", 72, -38)
  page.status:SetWidth(470)
  page.status:SetWordWrap(true)

  page.go = button(page, 120, 24, "Scan", function()
    local n, why = MOTA.Market:Scan(scanList())
    if not n then MOTA:Print(why) elseif n == 0 then MOTA:Print("Workshop: a scan is already running.") end
    Page:Refresh()
  end)
  page.go:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, -12)
  page.stop = button(page, 120, 24, "Stop", function() MOTA.Market:Stop() end)
  page.stop:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, -12)

  -- the two views, and the quick sorts of the Crafts view
  page.views = {}
  page.views.crafts = button(page, 90, 22, "Crafts", function() Page:View("crafts") end)
  page.views.crafts:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -68)
  page.views.market = button(page, 90, 22, "Market", function() Page:View("market") end)
  page.views.market:SetPoint("LEFT", page.views.crafts, "RIGHT", 4, 0)
  page.views.flips = button(page, 90, 22, "Flips", function() Page:View("flips") end)
  page.views.flips:SetPoint("LEFT", page.views.market, "RIGHT", 4, 0)
  page.flipping = button(page, 170, 22, "Flipping mode: off", function() MOTA.Flips:SetOn(not MOTA.Flips:On()) end)
  page.flipping:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, -68)
  page.quick = {}
  page.quick.profit = button(page, 120, 22, "Most profitable", function() sorts.crafts = { key = "profit", up = false }; Page:View("crafts") end)
  page.quick.hot = button(page, 100, 22, "Hot sellers", function() sorts.crafts = { key = "rate", up = false }; Page:View("crafts") end)
  page.quick.day = button(page, 110, 22, "Profit a day", function() sorts.crafts = { key = "perDay", up = false }; Page:View("crafts") end)
  page.quick.day:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, -68)
  page.quick.hot:SetPoint("RIGHT", page.quick.day, "LEFT", -4, 0)
  page.quick.profit:SetPoint("RIGHT", page.quick.hot, "LEFT", -4, 0)

  -- headings: each a button that sorts by its column
  page.heads = {}
  for i = 1, MAXCOLS do
    local h = CreateFrame("Button", nil, page)
    h:SetHeight(18)
    h.text = fontString(h, "GameFontNormalSmall")
    h.text:SetAllPoints()
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.12)
    h:SetScript("OnClick", function(self) if self.key then Page:SortBy(self.key) end end)
    page.heads[i] = h
  end

  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, page)
    r:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -(122 + (i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, -(122 + (i - 1) * ROW_H))
    r:SetHeight(ROW_H)
    if i % 2 == 0 then
      local band = r:CreateTexture(nil, "BACKGROUND")
      band:SetAllPoints()
      band:SetColorTexture(1, 1, 1, 0.03)
    end
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.cells = {}
    for c = 1, MAXCOLS do r.cells[c] = fontString(r, "GameFontHighlightSmall") end
    r:SetScript("OnEnter", function(self)
      if not self.id then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) end
      local it = self.it
      if it and it.flip then Page:FlipTip(it) GameTooltip:Show() return end
      if it and view == "market" and it.profit then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("As a flip: bought at the lowest, sold at the usual price", 0.6, 0.6, 0.6)
        GameTooltip:AddDoubleLine("Sells for (usual)", money(it.usual), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Auction house cut (5%)", "-" .. money(it.usual - math.floor(it.usual * (1 - W.CUT))), 0.8, 0.8, 0.8, MOTA:RGB(LOSS))
        GameTooltip:AddDoubleLine("Bought at (lowest)", "-" .. money(it.low), 0.8, 0.8, 0.8, MOTA:RGB(LOSS))
        GameTooltip:AddDoubleLine("Profit each", signed(it.profit), 1, 1, 1, MOTA:RGB(it.profit >= 0 and GAIN or LOSS))
      end
      if it and it.recipe then Page:CraftTip(it) end
      if it and it.straight then Page:StraightTip(it) end
      if it and it.short then GameTooltip:AddLine("Not enough materials listed for the whole batch.", 1, 0.5, 0.3) end
      if it and it.missing and it.missing > 0 then GameTooltip:AddLine("* Some materials have no price.", 1, 0.5, 0.3) end
      GameTooltip:AddLine("Click to search the auction house for it.", 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    r:SetScript("OnClick", function(self, mouse)
      if self.it and self.it.flip and mouse == "RightButton" then Page:LinkMenu(self.it.flip, self) return end
      if self.it and self.it.flip and IsShiftKeyDown() then MOTA.Flips:Close(self.it.flip.id) return end
      if self.id then Panel:SearchAuctions(self.id, W.ItemInfo(self.id) or (self.it and self.it.name)) end end)
    rows[i] = r
  end
  page.foot = fontString(page, "GameFontDisableSmall", "CENTER")
  page.foot:SetPoint("BOTTOM", page, "BOTTOM", 0, 8)
  page.foot:SetWidth(700)
  page:EnableMouseWheel(true)
  page:SetScript("OnMouseWheel", function(_, d) top = top - d * 3; Page:Refresh() end)
  page:Hide()
  Page.page, Page.rows = page, rows
end

-- Lays the headings and cells out for the view's columns.
local function layout(cols)
  local x = 14
  for i = 1, MAXCOLS do
    local c, h = cols[i], page.heads[i]
    h:SetShown(c ~= nil)
    if c then
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", page, "TOPLEFT", x, -100)
      h:SetWidth(c.w)
      h.key = c.key
      h.text:SetJustifyH(c.justify or "RIGHT")
      local s = sorts[view]
      h.text:SetText(c.label .. (s.key == c.key and (s.up and "  ^" or "  v") or ""))
    end
    for _, r in ipairs(rows) do
      local cell = r.cells[i]
      cell:SetShown(c ~= nil)
      if c then
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", r, "LEFT", x - 8, 0)
        cell:SetWidth(c.w)
        cell:SetJustifyH(c.justify or "RIGHT")
      end
    end
    if c then x = x + c.w + 8 end
  end
end

function Page:Refresh()
  if not page or not page:IsShown() then return end
  local M = MOTA.Market
  local left = M:Scanning()
  local list = self:Rows()
  local cols = COLS[view]
  local function hold(b, on) if on then b:LockHighlight() else b:UnlockHighlight() end end
  for k, b in pairs(page.views) do hold(b, k == view) end
  local s = sorts.crafts
  hold(page.quick.profit, view == "crafts" and s.key == "profit")
  hold(page.quick.hot, view == "crafts" and s.key == "rate")
  hold(page.quick.day, view == "crafts" and s.key == "perDay")
  local flips = view == "flips"
  for _, b in pairs(page.quick) do b:SetShown(not flips) end
  page.flipping:SetShown(flips)
  page.flipping:SetText("Flipping mode: " .. (MOTA.Flips:On() and "|cff1EFF00on|r" or "off"))
  hold(page.flipping, MOTA.Flips:On())

  if left then
    page.status:SetText(("Scanning: %d to go. Each search shows briefly on the Buy tab."):format(left))
    page.go:Hide(); page.stop:Show()
  else
    local newest = Panel:NewestScan()
    local n = #W:Materials()
    page.status:SetText(n == 0 and "Open a profession once so the Workshop knows your recipes."
      or (("Your crafts, and in blue the straight flips worth making (buy the cheapest, relist at the usual price). Last scan %s. Priced at a batch of %d. Profit is after the auction house's 5%% cut: green makes money, red loses it. Deposits come back when it sells.")
        :format(newest and Panel:Ago(newest) or "never", W:Batch())))
    page.go:SetShown(n > 0); page.stop:Hide()
  end

  layout(cols)
  top = math.max(0, math.min(top, #list - ROWS))
  for i, r in ipairs(rows) do
    local it = list[top + i]
    r.id, r.it = it and it.id, it
    r:SetShown(it ~= nil)
    if it then
      for c, col in ipairs(cols) do
        local cell = r.cells[c]
        cell:SetText(col.text(it))
        cell:SetTextColor(MOTA:RGB(col.colour and col.colour(it) or "FFFFFF"))
      end
    end
  end
  if flips then
    local t = MOTA.Flips:Totals()
    page.status:SetText((MOTA.Flips:On() and "Flipping mode is on: what you buy here is logged as a flip. "
      or "Turn flipping mode on before buying to log a flip. ")
      .. ("%d finished, %s profit in all. ? = so far, if what's listed sells."):format(t.done, signed(t.profit)))
    page.foot:SetText(#list == 0 and "No flips yet." or (#list .. " flips · hover for each price's sales · shift-click to close or reopen · right-click to link materials"))
    return
  end
  local what = view == "crafts" and "crafts and flips" or "items"
  page.foot:SetText(#list == 0 and (view == "crafts" and "No priced crafts yet: scan, or visit the auction house with Auctionator." or "Nothing watched yet.")
    or (#list > ROWS and ("%d to %d of %d %s · scroll for more · click a heading to sort"):format(top + 1, math.min(#list, top + ROWS), #list, what)
      or ("%d %s · click a heading to sort · click a row to search for it"):format(#list, what)))
end

-- A craft's sums: the sale, the cut, the materials and the deposit that's only lost unsold.
function Page:CraftTip(it)
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Sells for", money(it.gross), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Auction house cut (5%)", "-" .. money(it.cut), 0.8, 0.8, 0.8, MOTA:RGB(LOSS))
  GameTooltip:AddDoubleLine("Materials", "-" .. money(it.cost), 0.8, 0.8, 0.8, MOTA:RGB(LOSS))
  GameTooltip:AddDoubleLine("Profit", signed(it.profit), 1, 1, 1, MOTA:RGB(it.profit >= 0 and GAIN or LOSS))
  local AH = C_AuctionHouse
  if AH and AH.CalculateCommodityDeposit then
    local ok, dep = pcall(AH.CalculateCommodityDeposit, it.id, 2, 1)
    if ok and type(dep) == "number" and dep > 0 then
      GameTooltip:AddDoubleLine("Deposit (24 h, each)", money(dep), 0.8, 0.8, 0.8, 1, 1, 1)
      GameTooltip:AddLine("Refunded when it sells; lost if it expires or you cancel.", 0.6, 0.6, 0.6, true)
    end
  end
end

-- A flip's tooltip: its listings by price, what sold and how fast.
---------------------------------------------------------------------------
-- Linking materials to a flip (right-click a flip): the materials bought as flips of their own,
-- linked at the price paid, and the links already made, to undo.
---------------------------------------------------------------------------

local MENU_ROWS = 10
local menu

local function buildMenu()
  menu = CreateFrame("Frame", "MOTAFlipLinkMenu", page, BackdropTemplateMixin and "BackdropTemplate" or nil)
  menu:SetSize(320, 80)
  menu:SetFrameStrata("DIALOG")
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  local bg = menu:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.08, 0.07, 0.05, 0.97)
  local rim = menu:CreateTexture(nil, "BORDER")
  rim:SetPoint("TOPLEFT", -1, 1); rim:SetPoint("BOTTOMRIGHT", 1, -1)
  rim:SetColorTexture(1, 0.82, 0, 0.5)
  rim:SetDrawLayer("BACKGROUND", -1)
  menu.title = fontString(menu, "GameFontNormal", "LEFT")
  menu.title:SetPoint("TOPLEFT", 10, -8)
  menu.title:SetWidth(270)
  menu.close = button(menu, 22, 20, "x", function() menu:Hide() end)
  menu.close:SetPoint("TOPRIGHT", -4, -4)
  menu.countLabel = fontString(menu, "GameFontHighlightSmall", "LEFT")
  menu.countLabel:SetPoint("TOPLEFT", 10, -30)
  menu.countLabel:SetText("How many (blank links all):")
  menu.count = CreateFrame("EditBox", nil, menu, "InputBoxTemplate")
  menu.count:SetSize(50, 18)
  menu.count:SetPoint("LEFT", menu.countLabel, "RIGHT", 10, 0)
  menu.count:SetAutoFocus(false)
  if menu.count.SetNumeric then menu.count:SetNumeric(true) end
  menu.count:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  menu.rows = {}
  for i = 1, MENU_ROWS do
    local b = CreateFrame("Button", nil, menu)
    b:SetHeight(18)
    b:SetPoint("TOPLEFT", 8, -50 - (i - 1) * 19)
    b:SetPoint("TOPRIGHT", -8, -50 - (i - 1) * 19)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.text = fontString(b, "GameFontHighlightSmall", "LEFT")
    b.text:SetAllPoints()
    b:SetScript("OnClick", function(self) if self.act then self.act() end end)
    menu.rows[i] = b
  end
  menu.note = fontString(menu, "GameFontDisableSmall", "LEFT")
  menu.note:SetWidth(300)
  menu:Hide()
  Page.menu = menu
end

-- Fills the menu for flip f: unlinks first, then what can be linked.
function Page:FillMenu(f)
  local F = MOTA.Flips
  local items = {}
  for i, m in ipairs(f.mats or {}) do
    items[#items + 1] = { text = ("|cffFF6060Unlink|r %d %s (%s each)"):format(m.q, m.name, money(math.floor(m.each + 0.5))),
      act = function() F:Unlink(f.id, i); Page:FillMenu(f) end }
  end
  for _, src in ipairs(F:Sources(f)) do
    local each = F:Each(src)
    items[#items + 1] = { text = ("|cff1EFF00Link|r %s: %d free at %s each"):format(src.name, F:Free(src), money(math.floor(each + 0.5))),
      act = function()
        local n = tonumber(menu.count:GetText() or "")
        local ok, err = F:Link(f.id, src.id, n)
        if not ok and err then MOTA:Print(err) end
        menu.count:SetText("")
        Page:FillMenu(f)
      end }
  end
  menu.title:SetText("Materials for " .. (f.makesName or f.name))
  for i, b in ipairs(menu.rows) do
    local it = items[i]
    b:SetShown(it ~= nil)
    b.act = it and it.act
    b.text:SetText(it and it.text or "")
  end
  local shown = math.min(#items, MENU_ROWS)
  menu.note:ClearAllPoints()
  menu.note:SetPoint("TOPLEFT", 10, -54 - shown * 19)
  menu.note:SetText(#items == 0 and "No other flips have materials free to link. Buy them with flipping mode on."
    or "Linked materials count at the price you paid, locked in.")
  menu:SetHeight(80 + shown * 19)
end

function Page:LinkMenu(f, anchor)
  if not menu then buildMenu() end
  menu.flip = f
  menu.count:SetText("")
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 40, 0)
  self:FillMenu(f)
  menu:Show()
end

function Page:FlipTip(it)
  local f, s = it.flip, it.sum
  GameTooltip:AddLine(it.name, 1, 0.82, 0)
  if not f.own then GameTooltip:AddDoubleLine("Bought", s.bought .. " for " .. money(s.cost) .. (s.est and " (estimated)" or ""), 1, 1, 1, 1, 1, 1) end
  for _, key in ipairs({ "low", "usual", "high", "?" }) do
    local t = s.tiers[key]
    if t then
      local speed = t.hours and ("first in " .. (t.hours < 1 and "<1 h" or (math.floor(t.hours + 0.5) .. " h"))) or "none yet"
      GameTooltip:AddDoubleLine(("At %s (%s each)"):format(TIER[key], money(t.p)), ("%d/%d sold, %s"):format(t.sold, t.listed, speed), 0.8, 0.8, 0.8, 1, 1, 1)
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Sales", money(s.gross), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Auction house cut (5%)", "-" .. money(s.cut), 0.8, 0.8, 0.8, MOTA:RGB(LOSS))
  GameTooltip:AddDoubleLine("Bought for", "-" .. money(s.cost - s.mats), 0.8, 0.8, 0.8, MOTA:RGB(LOSS))
  for _, m in ipairs(f.mats or {}) do
    GameTooltip:AddDoubleLine(("  %d %s (linked)"):format(m.q, m.name), "-" .. money(math.floor(m.q * m.each + 0.5)), 0.8, 0.8, 0.8, MOTA:RGB(LOSS))
  end
  if f.out then
    local to = MOTA.Flips:Get(f.usedIn or -1)
    GameTooltip:AddLine(("%d linked to %s at what they cost."):format(f.out, to and (to.makesName or to.name) or "crafts"), 0.6, 0.6, 0.6, true)
  end
  GameTooltip:AddDoubleLine("Deposits paid", "-" .. money(s.deps), 0.8, 0.8, 0.8, MOTA:RGB(LOSS))
  GameTooltip:AddDoubleLine("Deposits refunded on sale", "+" .. money(s.refund), 0.8, 0.8, 0.8, MOTA:RGB(GAIN))
  if s.up > 0 then GameTooltip:AddLine(("Deposits on the %d still listed come back if they sell."):format(s.up), 0.6, 0.6, 0.6, true) end
  GameTooltip:AddDoubleLine(f.closed and "Profit" or "Profit so far", signed(s.profit), 1, 1, 1, MOTA:RGB(s.profit >= 0 and GAIN or LOSS))
  if not f.closed then GameTooltip:AddDoubleLine("If the rest sells", signed(s.outlook), 0.8, 0.8, 0.8, MOTA:RGB(s.outlook >= 0 and GAIN or LOSS)) end
  GameTooltip:AddLine((f.closed and "Shift-click to reopen." or "Shift-click to close it.") .. " Right-click to link materials.", 0.6, 0.6, 0.6)
end

---------------------------------------------------------------------------
-- The tab: the auction house's own tab, as Auctionator's are
---------------------------------------------------------------------------

-- The last tab that isn't ours.
local function lastTab(ah)
  local lib = LibStub and LibStub("LibAHTab-1-0", true)
  for _, list in ipairs({ lib and lib.internalState and lib.internalState.Tabs or {}, ah.Tabs or {} }) do
    for i = #list, 1, -1 do
      if list[i] ~= tab then return list[i] end
    end
  end
end

local function light(on)
  if not tab then return end
  tab.selected = on
  if tab.native then
    if on and PanelTemplates_SelectTab then PanelTemplates_SelectTab(tab) end
    if not on and PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(tab) end
  else
    tab.lit:SetShown(on)
  end
end

local function deselectOthers(ah)
  local lib = LibStub and LibStub("LibAHTab-1-0", true)
  for _, t in ipairs((lib and lib.internalState and lib.internalState.Tabs) or {}) do
    if t.frameRef then t.frameRef:Hide() end
    if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(t) end
  end
  for _, t in ipairs(ah.Tabs or {}) do
    if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(t) end
  end
end

function Page:Select()
  local ah = AuctionHouseFrame
  if not ah or not page then return end
  if ah.SetDisplayMode then pcall(ah.SetDisplayMode, ah, {}) end
  ah.displayMode = nil
  deselectOthers(ah)
  if ah.SetTitle then pcall(ah.SetTitle, ah, "The Workshop") end
  page:Show()
  light(true)
  self:Refresh()
end

function Page:Deselect()
  if page then page:Hide() end
  light(false)
end

local function buildTab(ah)
  -- the auction house's own tab template, so it matches the tabs beside it
  local ok, t = pcall(CreateFrame, "Button", "MOTAWorkshopAHTab", ah, "AuctionHouseFrameDisplayModeTabTemplate")
  if ok and t and t.SetText then
    tab = t
    tab.native = true
    -- The template joins the auction house's own list of tabs (Forever, 14 Nov: it then tried to
    -- anchor to itself). Ours is kept out of it, as LibAHTab's are.
    if type(ah.Tabs) == "table" then
      for i = #ah.Tabs, 1, -1 do
        if ah.Tabs[i] == tab then table.remove(ah.Tabs, i) end
      end
    end
    tab:SetText("Workshop")
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 20, nil, 70) end
    if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, tab) end
  else
    tab = CreateFrame("Button", "MOTAWorkshopAHTab", ah)
    tab:SetSize(104, 30)
    Kit:Fill(tab, "2A2A2A", "151515")
    Kit:Outline(tab, "8C6A2A", 1, 0, 1)
    tab.lit = CreateFrame("Frame", nil, tab)
    tab.lit:SetAllPoints()
    Kit:Outline(tab.lit, "FFD100", 1, 0, 2)
    tab.lit:Hide()
    local label = fontString(tab, "GameFontNormalSmall", "CENTER")
    label:SetAllPoints()
    label:SetText("Workshop")
  end
  tab:SetScript("OnClick", function() Page:Select() end)
  -- Any other tab hides the page, as Auctionator's tabs do.
  if hooksecurefunc and ah.SetDisplayMode then
    hooksecurefunc(ah, "SetDisplayMode", function(_, mode)
      if type(mode) == "table" and #mode > 0 then Page:Deselect() end
    end)
  end
  local lib = LibStub and LibStub("LibAHTab-1-0", true)
  if hooksecurefunc and lib and lib.SetSelected then hooksecurefunc(lib, "SetSelected", function() Page:Deselect() end) end
  Page.tab = tab
end

-- Along the bottom, after the last tab (Auctionator adds its own when the auction house opens,
-- so this waits a moment and places itself after them). The same overlap as LibAHTab's tabs.
local function placeTab(ah)
  local last = lastTab(ah)
  tab:ClearAllPoints()
  -- the same small gap as between the game's own tabs (Forever, 14 Nov: Classic's -14 overlap
  -- put Auctionator's tab over ours)
  local dx = tab.native and 3 or 2
  if last then tab:SetPoint("TOPLEFT", last, "TOPRIGHT", dx, 0) else tab:SetPoint("TOPLEFT", ah, "BOTTOMLEFT", 20, 2) end
end

local function onOpen()
  local ah = AuctionHouseFrame
  if not ah or not MOTA.Market:Available() then return end
  local s = MOTA.db and MOTA.db.settings
  if s and s.workshop == false then return end
  if not tab then buildTab(ah); buildPage(ah) end
  tab:Show()
  placeTab(ah)
  C_Timer.After(0.5, function() if tab then placeTab(ah) end end)
end

MOTA:Listen("AUCTION_OPEN", onOpen)
MOTA:Listen("AUCTION_CLOSED", function() Page:Deselect() Panel:Refresh() end)
MOTA:Listen("MARKET_CHANGED", function() Page:Refresh(); Panel:Refresh() end)
MOTA:Listen("WORKSHOP_CHANGED", function() Page:Refresh() end)
MOTA:Listen("FLIPS_CHANGED", function()
  Page:Refresh()
  if menu and menu:IsShown() and menu.flip then Page:FillMenu(menu.flip) end
end)
