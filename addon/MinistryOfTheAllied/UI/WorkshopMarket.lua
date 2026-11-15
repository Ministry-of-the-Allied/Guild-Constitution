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
local sorts = { market = { key = "name", up = true }, crafts = { key = "profit", up = false } }

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
      out[#out + 1] = { id = id, name = W.ItemInfo(id) or ("item " .. id), craft = crafts[id],
        low = M:Lowest(id), usual = M:Normal(id), listed = levels and listed or nil,
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
            cost = v.cost, sale = net, profit = v.profit, margin = v.cost > 0 and v.profit / v.cost or nil,
            rate = rate, sells = M:RateText(r.item), perDay = rate and (v.profit / made * rate) or nil,
            missing = v.missing, short = #v.short > 0 }
        end
      end
    end
  end
  return out
end

-- The columns of each view: heading, width, alignment, the text and colour of a cell, and what
-- it sorts by.
local COLS = {
  market = {
    { key = "name", label = "Item", w = 250, justify = "LEFT", text = function(it) return it.name end,
      colour = function(it) return it.craft and "FFD100" or "FFFFFF" end },
    { key = "low", label = "Lowest", w = 90, text = function(it) return money(it.low) end },
    { key = "usual", label = "Usual", w = 90, text = function(it) return money(it.usual) end },
    { key = "listed", label = "Listed", w = 70, text = function(it) return it.listed and tostring(it.listed) or "-" end },
    { key = "rate", label = "Sells", w = 120, text = function(it) return it.sells or "no data yet" end,
      colour = function(it) return it.sells and "FFFFFF" or "808080" end },
    { key = "age", label = "Scanned", w = 100, text = function(it) return it.age and Panel:Ago(it.age) or "never" end,
      colour = function() return "808080" end },
  },
  crafts = {
    { key = "name", label = "Craft", w = 210, justify = "LEFT", text = function(it) return it.name end,
      colour = function(it) return COLOUR[it.colour] or "FFD100" end },
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
}

-- Sorted by the chosen column; empty values last whichever way round.
function Page:Rows()
  local list = view == "crafts" and self:Crafts() or self:Items()
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

local MAXCOLS = 7

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
    if not n then MOTA:Print(why) elseif n == 0 then MOTA:Print("Workshop: every price was scanned in the last hour.") end
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
      if it and it.short then GameTooltip:AddLine("Not enough materials listed for the whole batch.", 1, 0.5, 0.3) end
      if it and it.missing and it.missing > 0 then GameTooltip:AddLine("* Some materials have no price.", 1, 0.5, 0.3) end
      GameTooltip:AddLine("Click to search the auction house for it.", 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self) if self.id then Panel:SearchAuctions(self.id, W.ItemInfo(self.id) or (self.it and self.it.name)) end end)
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

  if left then
    page.status:SetText(("Scanning: %d to go. Each search shows briefly on the Buy tab."):format(left))
    page.go:Hide(); page.stop:Show()
  else
    local newest = Panel:NewestScan()
    local n = #W:Materials()
    page.status:SetText(n == 0 and "Open a profession once so the Workshop knows your recipes."
      or (("Your crafts and their materials. Last scan %s. Scan every visit: sell rates need scans a few hours apart. Crafts priced at a batch of %d.")
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
  local what = view == "crafts" and "crafts" or "items"
  page.foot:SetText(#list == 0 and (view == "crafts" and "No priced crafts yet: scan, or visit the auction house with Auctionator." or "Nothing watched yet.")
    or (#list > ROWS and ("%d to %d of %d %s · scroll for more · click a heading to sort"):format(top + 1, math.min(#list, top + ROWS), #list, what)
      or ("%d %s · click a heading to sort · click a row to search for it"):format(#list, what)))
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
