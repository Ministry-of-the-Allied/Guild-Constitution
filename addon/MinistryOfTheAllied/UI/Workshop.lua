-- Ministry of the Allied: the Workshop panel (Duncan, 14 Nov 2026).
-- Docks beside the profession window when it opens: three lists for this character's
-- profession (Workshop.lua): Profit, Level (cheapest skill per point) and Learn (unlearned
-- recipes worth training). Hover a row for its materials and prices; click it to show the
-- recipe in the profession window. The x hides it until the window next opens;
-- /mota workshop brings it back.

local _, MOTA = ...
local Kit = MOTA.Kit
local W = MOTA.Workshop
local Panel = {}
MOTA.WorkshopPanel = Panel

local WIDTH, ROW_H, ROWS = 300, 30, 12
local HEAD_H, TABS_H, FOOT_H, BATCH_H = 52, 26, 30, 28
local HEIGHT = HEAD_H + TABS_H + BATCH_H + 8 + ROWS * ROW_H + FOOT_H
local COLOUR = { optimal = "B4501A", medium = "8A6D00", easy = "2E6B2E", trivial = "6E6E6E" }
local TABS = {
  { key = "profit", label = "Profit" },
  { key = "level", label = "Level" },
  { key = "learn", label = "Learn" },
}

local f, rows, tabs = nil, {}, {}
local tab, top = "profit", 0
local hidden -- closed with the x, until the profession window opens again

local function hostFrame()
  for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame" }) do
    local h = _G[name]
    if h and h.IsShown and h:IsShown() then return h end
  end
end

local function place()
  f:ClearAllPoints()
  local h = hostFrame()
  if h then f:SetPoint("TOPLEFT", h, "TOPRIGHT", 4, 0)
  else f:SetPoint("CENTER", UIParent, "CENTER", 360, 0) end
end

---------------------------------------------------------------------------
-- The list's rows, by tab
---------------------------------------------------------------------------

local function list(prof)
  if tab == "level" then return W:Levelling(prof) end
  if tab == "learn" then return W:ToLearn(prof) end
  return W:Profit(prof)
end

local function money(c) return W:Money(c) end

-- { name, right, sub, hex }
local function describe(v)
  local r = v.r
  local out = { name = r.name, hex = COLOUR[r.colour] or "2A1F14" }
  local unpriced = v.missing > 0 and (" · " .. v.missing .. " material" .. (v.missing == 1 and "" or "s") .. " unpriced") or ""
  if #v.short > 0 then
    local d = v.short[1]
    unpriced = unpriced .. " · only " .. d.got .. " " .. (W.ItemInfo(d.item) or "of a material") .. " listed"
  end
  if tab == "level" then
    if v.net <= 0 then
      out.right = "+" .. money(-v.net)
      out.sub = "makes money and levels" .. unpriced
    else
      out.right = money(v.perPoint) .. "/pt"
      out.sub = "costs " .. money(v.net) .. " a craft after selling" .. unpriced
    end
    local word = ({ optimal = "always a point", medium = "usually a point", easy = "sometimes a point" })[r.colour]
    out.sub = word .. " · " .. out.sub
  else
    out.right = (v.profit >= 0 and "+" or "") .. money(v.profit)
    local rate = MOTA.Market:RateText(r.item)
    out.sub = "sells " .. money(v.sale) .. (r.made > 1 and (" for " .. r.made) or "") .. (rate and (" " .. rate) or "") .. " · materials " .. money(v.cost) ..
      (v.n > 1 and " each" or "") .. unpriced
    if tab == "learn" then out.sub = "not learned · " .. out.sub end
  end
  out.loss = (tab ~= "level" and v.profit < 0) or (tab == "level" and false)
  return out
end

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------

local function tooltip(row)
  local v = row.v
  if not v then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(v.r.name .. (v.n > 1 and ("  x" .. v.n) or ""), 1, 0.82, 0)
  for _, d in ipairs(v.mats) do
    local name = W.ItemInfo(d.item) or ("item " .. d.item)
    local right = d.cost and money(d.cost) or "no price"
    if d.src == "scan" then right = right .. (d.short and "  (only " .. d.got .. " listed)" or "")
    elseif d.src == "auctionator" then right = right .. "  (cheapest only)" end
    GameTooltip:AddDoubleLine(d.need .. "x " .. name, right, 1, 1, 1, 1, d.cost and 1 or 0.4, d.cost and 1 or 0.4)
  end
  GameTooltip:AddDoubleLine("Materials, each craft", money(v.cost), 0.8, 0.8, 0.8, 1, 1, 1)
  if v.scanned < #v.mats then
    GameTooltip:AddLine("Prices marked \"cheapest only\" come from Auctionator and ignore how many are listed. Scan at the auction house for real batch prices.", 0.6, 0.6, 0.6, true)
  end
  if v.sale then
    GameTooltip:AddDoubleLine("Sells for (after the 5% cut)", money(math.floor(v.sale * (1 - W.CUT))), 0.8, 0.8, 0.8, 1, 1, 1)
  elseif v.vendor then
    GameTooltip:AddDoubleLine("No auction price; a vendor pays", money(v.vendor), 0.8, 0.8, 0.8, 1, 1, 1)
  end
  if v.age then GameTooltip:AddLine("Auctionator's price is " .. v.age .. " day" .. (v.age == 1 and "" or "s") .. " old.", 0.6, 0.6, 0.6) end
  local M = MOTA.Market
  local rate, hours = M:SellRate(v.r.item)
  if rate then
    GameTooltip:AddDoubleLine("Sells (estimated)", M:RateText(v.r.item), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddLine(("From %d hours of scans this week."):format(math.floor(hours + 0.5)), 0.6, 0.6, 0.6)
    local made = v.n * (v.r.made or 1)
    if rate > 0 and made / rate > 3 then
      GameTooltip:AddLine(("A batch of %d is about %d days of sales at this rate."):format(made, math.floor(made / rate + 0.5)), 1, 0.5, 0.3, true)
    elseif rate == 0 then
      GameTooltip:AddLine("None seen selling this week.", 1, 0.5, 0.3)
    end
  else
    GameTooltip:AddLine(("Sell rate: not enough scans yet (%d of %d hours watched)."):format(math.floor((hours or 0) + 0.5), M.MIN_HOURS), 0.6, 0.6, 0.6, true)
  end
  local normal = M:Normal(v.r.item)
  if normal then GameTooltip:AddDoubleLine("Usual price this week", money(normal), 0.8, 0.8, 0.8, 1, 1, 1) end
  GameTooltip:Show()
end

local function build()
  f = CreateFrame("Frame", "MOTAWorkshopPanel", UIParent)
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(true)
  Kit:Fill(f, "F4E8C8", "E3CFA0")
  Kit:Outline(f, "6E4F17", 0.9, 0, 2)

  local eyebrow = Kit:Label(f, "kitTiny", "7A5719", 0.22, "Ministry of the Allied")
  eyebrow:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
  f.title = Kit:Text(f, "kitStage", "1B3570")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -22)
  f.title:SetText("The Workshop")
  f.sub = Kit:Text(f, "kitItalic", "5E4B33", "RIGHT")
  f.sub:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -28)
  f.sub:SetWidth(140)
  f.sub:SetMaxLines(1)

  local x = CreateFrame("Button", nil, f)
  x:SetSize(18, 18)
  x:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
  local xt = Kit:Text(x, "kitSmall", "6E4F17", "CENTER")
  xt:SetAllPoints()
  xt:SetText("x")
  x:SetScript("OnClick", function() hidden = true; f:Hide() end)
  f.close = x

  local tw = math.floor((WIDTH - 28 - 2 * 4) / 3)
  for i, t in ipairs(TABS) do
    local key = t.key
    local quiet = Kit:Button(f, tw, TABS_H, t.label, "quiet", function() Panel:Tab(key) end)
    quiet:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + (i - 1) * (tw + 4), -HEAD_H)
    local lit = Kit:Button(f, tw, TABS_H, t.label, "blue", function() Panel:Tab(key) end)
    lit:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + (i - 1) * (tw + 4), -HEAD_H)
    tabs[key] = { quiet = quiet, lit = lit }
  end

  -- the batch size: how many you mean to make
  local by = HEAD_H + TABS_H + 6
  local bl = Kit:Label(f, "kitTiny", "7A5719", 0.2, "BATCH")
  bl:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -(by + 7))
  f.batches = {}
  for i, n in ipairs(W.BATCHES) do
    local label = "x" .. n
    local quiet = Kit:Button(f, 40, 20, label, "quiet", function() W:SetBatch(n) end)
    quiet:SetPoint("TOPLEFT", f, "TOPLEFT", 62 + (i - 1) * 44, -by)
    local lit = Kit:Button(f, 40, 20, label, "blue", function() W:SetBatch(n) end)
    lit:SetPoint("TOPLEFT", f, "TOPLEFT", 62 + (i - 1) * 44, -by)
    f.batches[n] = { quiet = quiet, lit = lit }
  end
  f.src = Kit:Text(f, "kitItalic", "5E4B33", "RIGHT")
  f.src:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -(by + 4))
  f.src:SetWidth(60)
  f.src:SetMaxLines(1)

  local y0 = HEAD_H + TABS_H + BATCH_H + 8
  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetSize(WIDTH - 28, ROW_H)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -(y0 + (i - 1) * ROW_H))
    local glow = r:CreateTexture(nil, "HIGHLIGHT")
    glow:SetColorTexture(1, 0.95, 0.7, 0.3)
    glow:SetAllPoints()
    r.name = Kit:Text(r, "kitSmall")
    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -2)
    r.name:SetWidth(WIDTH - 28 - 80)
    r.name:SetMaxLines(1)
    r.right = Kit:Text(r, "kitSmall", "2E6B2E", "RIGHT")
    r.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2, -2)
    r.right:SetWidth(78)
    r.sub = Kit:Text(r, "kitItalic", "5E4B33")
    r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -16)
    r.sub:SetWidth(WIDTH - 32)
    r.sub:SetMaxLines(1)
    local line = r:CreateTexture(nil, "BORDER")
    Kit:Solid(line, "6E4F17", 0.25)
    line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    r:SetScript("OnEnter", tooltip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self) Panel:Click(self.v) end)
    rows[i] = r
  end
  f.none = Kit:Text(f, "kitItalic", "5E4B33")
  f.none:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -(y0 + 6))
  f.none:SetWidth(WIDTH - 32)

  f.foot = Kit:Text(f, "kitItalic", "5E4B33", "CENTER")
  f.foot:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
  f.foot:SetWidth(WIDTH - 28)
  f.foot:SetMaxLines(2)

  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, d) top = top - d * 3; Panel:Refresh() end)
  f:Hide()
  Panel.frame, Panel.rows, Panel.tabs = f, rows, tabs -- for the pretend client's checks
end

---------------------------------------------------------------------------
-- Filling it in
---------------------------------------------------------------------------

function Panel:Refresh()
  if not f or not f:IsShown() then return end
  local prof = W.current
  for key, t in pairs(tabs) do t.lit:SetShown(key == tab); t.quiet:SetShown(key ~= tab) end
  local batch = W:Batch()
  for n, b in pairs(f.batches) do b.lit:SetShown(n == batch); b.quiet:SetShown(n ~= batch) end
  local newest = Panel:NewestScan()
  f.src:SetText(newest and ("scan " .. Panel:Ago(newest)) or "no scan yet")
  f.sub:SetText(prof and (prof.name .. " " .. prof.rank .. "/" .. prof.max) or "")

  local items = prof and list(prof) or {}
  top = math.max(0, math.min(top, #items - ROWS))
  for i, r in ipairs(rows) do
    local v = items[top + i]
    r.v = v
    r:SetShown(v ~= nil)
    if v then
      local d = describe(v)
      r.name:SetText(d.name)
      r.name:SetTextColor(MOTA:RGB(d.hex))
      r.right:SetText(d.right)
      r.right:SetTextColor(MOTA:RGB(d.loss and "8B2A1E" or "2E6B2E"))
      r.sub:SetText(d.sub)
    end
  end

  f.none:SetShown(#items == 0)
  if not prof then
    f.none:SetText("Open a profession to see what to craft.")
  elseif not W:HasPrices() then
    f.none:SetText("Needs Auctionator for prices. Install it, visit the auction house once, and the lists fill in.")
  elseif tab == "level" then
    f.none:SetText(prof.rank >= prof.max and "You're at this level's cap. Train the next rank to keep levelling."
      or "No recipe you know still gives skill. Check the Learn tab.")
  elseif tab == "learn" then
    f.none:SetText("No priced recipes left to learn at this level.")
  else
    f.none:SetText("None of your recipes has an auction price yet. Scan the auction house with Auctionator.")
  end

  local n = #items
  f.foot:SetText(n > ROWS and ("%d to %d of %d · scroll for more"):format(top + 1, math.min(n, top + ROWS), n)
    or (n > 0 and ("%d recipe%s · %s"):format(n, n == 1 and "" or "s",
      (MOTA.Market and MOTA.Market.atAuctionHouse) and "click to search the auction house" or "hover for materials, click to open") or ""))
end

-- A row's click (Duncan, 14 Nov): at the auction house, search for the crafted item there;
-- shift-click puts its link in chat; otherwise open the recipe in the profession window.
function Panel:Click(v)
  if not v then return end
  local item = v.r.item
  local link = item and select(2, W.ItemInfo(item))
  if IsShiftKeyDown and IsShiftKeyDown() and link then
    if ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
    return
  end
  if MOTA.Market and MOTA.Market.atAuctionHouse and item then
    self:SearchAuctions(item, W.ItemInfo(item) or v.r.name)
    return
  end
  if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, v.id) end
end

-- Shows an item's listings at the auction house: through Auctionator's shopping search when
-- it's there, else the auction house's own search box. Returns how it searched.
function Panel:SearchAuctions(item, name)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if api and api.MultiSearchExact and name then
    if pcall(api.MultiSearchExact, "MinistryOfTheAllied", { name }) then return "auctionator" end
  end
  local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
  if bar and bar.SetSearchText and bar.StartSearch and name then
    if pcall(function() bar:SetSearchText(name); bar:StartSearch() end) then return "searchbar" end
  end
  if C_AuctionHouse and C_AuctionHouse.SendSearchQuery then
    local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
    pcall(C_AuctionHouse.SendSearchQuery, C_AuctionHouse.MakeItemKey(item), { { sortOrder = order, reverseSort = false } }, false)
    return "query"
  end
end

function Panel:Tab(key)
  tab, top = key, 0
  self:Refresh()
end

function Panel:Show()
  if not f then build() end
  hidden = false
  place()
  f:Show()
  self:Refresh()
end

function Panel:Toggle()
  if f and f:IsShown() then hidden = true; f:Hide() else self:Show() end
end

local function settingOn()
  local s = MOTA.db and MOTA.db.settings
  return not s or s.workshop ~= false
end

MOTA:Listen("WORKSHOP_CHANGED", function()
  if not settingOn() or hidden then return end
  if f and f:IsShown() then Panel:Refresh() return end
  Panel:Show()
end)
MOTA:Listen("WORKSHOP_CLOSED", function()
  hidden = false
  if f then f:Hide() end
end)

---------------------------------------------------------------------------
-- The strip at the auction house: scan this character's materials (Market.lua)
---------------------------------------------------------------------------

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

local strip
local function ahFrame()
  for _, name in ipairs({ "AuctionHouseFrame", "AuctionFrame" }) do
    local h = _G[name]
    if h and h.IsShown and h:IsShown() then return h end
  end
end

local function scanList()
  local ids = W:Materials()
  for _, id in ipairs(W:Results()) do ids[#ids + 1] = id end
  return ids
end

function Panel:RefreshStrip()
  if not strip or not strip:IsShown() then return end
  local M = MOTA.Market
  local left = M:Scanning()
  local mats = #W:Materials()
  if left then
    strip.text:SetText(("Scanning prices: %d to go. The auction house window shows each search."):format(left))
    strip.go:Hide(); strip.stop:Show()
  else
    local newest = self:NewestScan()
    strip.text:SetText(mats == 0 and "Open a profession once so the Workshop knows your recipes."
      or (("%d materials and your crafts. Last scan %s."):format(mats, newest and self:Ago(newest) or "never")))
    strip.go:SetShown(mats > 0); strip.stop:Hide()
  end
end

local function buildStrip()
  strip = CreateFrame("Frame", "MOTAWorkshopStrip", UIParent)
  strip:SetSize(430, 34)
  strip:SetFrameStrata("HIGH")
  Kit:Fill(strip, "F4E8C8", "E3CFA0")
  Kit:Outline(strip, "6E4F17", 0.9, 0, 2)
  local t = Kit:Label(strip, "kitTiny", "1B3570", 0.2, "WORKSHOP")
  t:SetPoint("LEFT", strip, "LEFT", 10, 0)
  strip.text = Kit:Text(strip, "kitItalic", "5E4B33")
  strip.text:SetPoint("LEFT", strip, "LEFT", 100, 0)
  strip.text:SetWidth(430 - 100 - 80)
  strip.text:SetMaxLines(2)
  strip.go = Kit:Button(strip, 66, 22, "Scan", "blue", function()
    local n, why = MOTA.Market:Scan(scanList())
    if not n then MOTA:Print(why) elseif n == 0 then MOTA:Print("Workshop: every price was scanned in the last hour.") end
    Panel:RefreshStrip()
  end)
  strip.go:SetPoint("RIGHT", strip, "RIGHT", -8, 0)
  strip.stop = Kit:Button(strip, 66, 22, "Stop", "quiet", function() MOTA.Market:Stop() end)
  strip.stop:SetPoint("RIGHT", strip, "RIGHT", -8, 0)
  Panel.strip = strip
end

MOTA:Listen("AUCTION_OPEN", function()
  if not MOTA.Market:Available() then return end
  local s = MOTA.db and MOTA.db.settings
  if s and s.workshop == false then return end
  if not strip then buildStrip() end
  strip:ClearAllPoints()
  local h = ahFrame()
  if h then strip:SetPoint("BOTTOMLEFT", h, "TOPLEFT", 60, 2) else strip:SetPoint("TOP", UIParent, "TOP", 0, -80) end
  strip:Show()
  Panel:RefreshStrip()
end)
MOTA:Listen("AUCTION_CLOSED", function() if strip then strip:Hide() end Panel:Refresh() end)
MOTA:Listen("MARKET_CHANGED", function() Panel:RefreshStrip(); Panel:Refresh() end)
