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
local HEAD_H, TABS_H, FOOT_H, BATCH_H = 56, 24, 30, 28
local HEIGHT = HEAD_H + TABS_H + BATCH_H + 8 + ROWS * ROW_H + FOOT_H
-- the game's own recipe colours, and its green and red for money
local COLOUR = { optimal = "FF8040", medium = "FFFF00", easy = "40BF40", trivial = "808080" }
local GAIN, LOSS = "1EFF00", "FF2020"
local TABS = {
  { key = "profit", label = "Profit" },
  { key = "level", label = "Level" },
  { key = "learn", label = "Learn" },
}

local f, rows, tabs = nil, {}, {}
local tab, top = "profit", 0
-- Closed with the x or the side tab: it stays closed, at every profession, until the tab opens it.
local function hidden()
  local s = MOTA.db and MOTA.db.settings
  return s and s.workshopHidden == true
end
local function setHidden(v)
  if MOTA.db and MOTA.db.settings then MOTA.db.settings.workshopHidden = v or nil end
end

-- The window the Workshop sits beside: a profession's own window, or else the Professions
-- book (Duncan, 14 Nov: quick access out mining, away from a crafting station). Returns the
-- frame and whether it's the book.
local BOOKS = { "ProfessionsBookFrame" }
local function hostFrame()
  for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame" }) do
    local h = _G[name]
    if h and h.IsShown and h:IsShown() then return h, false end
  end
  for _, name in ipairs(BOOKS) do
    local h = _G[name]
    if h and h.IsShown and h:IsShown() then return h, true end
  end
end

-- Away from a crafting station the Workshop shows the profession last opened; the name under
-- the title switches between this character's saved professions.
local function professions()
  local list = {}
  for _, p in pairs(W:Mine()) do list[#list + 1] = p end
  table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return list
end

local SIDE = 48 -- room on the profession window's right edge for the side tabs (Duncan, 14 Nov)
local TAB = 42  -- our side tab, the size of the game's own (36 looked small beside them)

local function place()
  f:ClearAllPoints()
  local h = hostFrame()
  if h then f:SetPoint("TOPLEFT", h, "TOPRIGHT", SIDE, 0)
  else f:SetPoint("CENTER", UIParent, "CENTER", 360, 0) end
end

---------------------------------------------------------------------------
-- The side tab: an icon tab on the window's right edge, drawn like the game's own (the
-- profession tabs Forever puts there), that opens and closes the Workshop. It hangs under
-- the last profession tab, however many there are (none to four), above the "?" further down.
---------------------------------------------------------------------------

local side
local ICON = "Interface\\Icons\\INV_Misc_Coin_02"

local function buildSide()
  -- A plain button (Duncan, 14 Nov: as a CheckButton its icon vanished when clicked: the
  -- checked texture drew a black box over it on Forever). The open glow is drawn here instead.
  side = CreateFrame("Button", "MOTAWorkshopSideTab", UIParent)
  side:SetSize(TAB, TAB)
  side:SetFrameStrata("HIGH")
  -- the game's side-tab frame behind the icon, as the spellbook's tabs have
  side.frame = side:CreateTexture(nil, "BACKGROUND")
  side.frame:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
  side.frame:SetSize(TAB * 64 / 32, TAB * 64 / 32)
  side.frame:SetPoint("TOPLEFT", side, "TOPLEFT", -3 * TAB / 32, 11 * TAB / 32)
  side.icon = side:CreateTexture(nil, "ARTWORK")
  side.icon:SetAllPoints()
  side.icon:SetTexture(ICON)
  side.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local hl = side:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  hl:SetBlendMode("ADD")
  -- "lit" while the Workshop is open: a gold edge and a warm wash over the icon
  side.lit = CreateFrame("Frame", nil, side)
  side.lit:SetAllPoints()
  side.lit:SetFrameLevel(side:GetFrameLevel() + 2)
  local wash = side.lit:CreateTexture(nil, "OVERLAY")
  wash:SetAllPoints()
  wash:SetColorTexture(1, 0.82, 0.2, 0.18)
  wash:SetBlendMode("ADD")
  Kit:Outline(side.lit, "FFD100", 1, 0, 2)
  side.lit:Hide()
  side:SetScript("OnClick", function() Panel:Toggle() end)
  side:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("The Workshop", 1, 0.82, 0)
    GameTooltip:AddLine("Ministry of the Allied", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("What to craft for profit and for skill.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  side:SetScript("OnLeave", function() GameTooltip:Hide() end)
  Panel.side = side
end

-- The game's tabs down the window's right edge, top to bottom: anything icon-sized whose left
-- edge sits on the window's right edge. The first run of them (each close under the last) is
-- the professions; the "?" further down is left out.
local function children(frame, out, depth)
  if depth > 2 or not frame.GetChildren then return end
  local ok, list = pcall(function() return { frame:GetChildren() } end)
  if not ok then return end
  for _, c in ipairs(list) do
    out[#out + 1] = c
    children(c, out, depth + 1)
  end
end

function Panel:LastSideTab(h)
  local right = h.GetRight and h:GetRight()
  if type(right) ~= "number" then return nil end
  local all = {}
  children(h, all, 1)
  local found = {}
  for _, c in ipairs(all) do
    if c ~= side and c.IsShown and c:IsShown() and c.GetLeft then
      local l, t, w, ht = c:GetLeft(), c:GetTop(), c:GetWidth(), c:GetHeight()
      if type(l) == "number" and type(t) == "number" and w >= 24 and w <= 64 and ht >= 24 and ht <= 64
        and l >= right - 14 and l <= right + 18 then
        found[#found + 1] = c
      end
    end
  end
  table.sort(found, function(a, b) return a:GetTop() > b:GetTop() end)
  local last
  for _, c in ipairs(found) do
    if last and c:GetTop() < last:GetBottom() - 20 then break end -- a gap: the professions ended
    last = c
  end
  return last
end

function Panel:ShowSide(show)
  if show and not side then buildSide() end
  if not side then return end
  local h = hostFrame()
  side:ClearAllPoints()
  local last = h and self:LastSideTab(h)
  if last then
    side:SetPoint("TOP", last, "BOTTOM", 0, -10)
  elseif h then
    side:SetPoint("TOPLEFT", h, "TOPRIGHT", 4, -56)
  else
    side:SetPoint("CENTER", UIParent, "CENTER", 120, 0)
  end
  side:SetShown(show)
  side.lit:SetShown(f ~= nil and f:IsShown())
  -- the game may add its tabs a moment after the window opens: look again then
  if show and h and not self.relooking then
    self.relooking = true
    C_Timer.After(0.3, function()
      self.relooking = false
      if side:IsShown() then
        local l2 = self:LastSideTab(h)
        if l2 then side:ClearAllPoints(); side:SetPoint("TOP", l2, "BOTTOM", 0, -10) end
      end
    end)
  end
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
  local out = { name = r.name, hex = COLOUR[r.colour] or "FFD100" }
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

-- Drawn like the game's own windows (Duncan, 14 Nov: the parchment looked out of place beside
-- the profession window): the same frame and title bar, the game's buttons and fonts, the
-- game's colours for recipe difficulty and for profit and loss.
local function fontString(parent, template, justify)
  local t = parent:CreateFontString(nil, "OVERLAY", template)
  if justify then t:SetJustifyH(justify) end
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

local function build()
  local ok, frame = pcall(CreateFrame, "Frame", "MOTAWorkshopPanel", UIParent, "ButtonFrameTemplate")
  f = ok and frame or CreateFrame("Frame", "MOTAWorkshopPanel", UIParent)
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(true)
  if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, f) end
  if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, f) end
  if f.SetTitle then pcall(f.SetTitle, f, "The Workshop") end
  if type(f.TitleText) == "table" and f.TitleText.SetText then f.TitleText:SetText("The Workshop") end
  if type(f.CloseButton) == "table" and f.CloseButton.SetScript then
    f.CloseButton:SetScript("OnClick", function() Panel:Hide() end)
    f.close = f.CloseButton
  else
    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    x:SetScript("OnClick", function() Panel:Hide() end)
    f.close = x
  end

  -- the profession, in gold: click to switch to another this character knows
  f.sub = fontString(f, "GameFontNormal", "LEFT")
  f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -34)
  f.sub:SetWidth(WIDTH - 28)
  local swap = CreateFrame("Button", nil, f)
  swap:SetAllPoints(f.sub)
  swap:SetScript("OnClick", function() Panel:NextProfession() end)
  swap:SetScript("OnEnter", function(self)
    if #professions() < 2 then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Click for your other profession.", 1, 1, 1)
    GameTooltip:Show()
  end)
  swap:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.swap = swap

  -- Profit, Level, Learn, and Market: Market opens the auction house page in its own window,
  -- with the figures on file (Duncan, 17 Nov 2026)
  local tw = math.floor((WIDTH - 28 - 3 * 4) / 4)
  for i, t in ipairs(TABS) do
    local key = t.key
    local b = button(f, tw, TABS_H, t.label, function() Panel:Tab(key) end)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + (i - 1) * (tw + 4), -HEAD_H)
    tabs[key] = b
  end
  -- the small panel steps aside for the big window (Duncan, 17 Nov); only hidden for now, so it
  -- still opens with the profession window next time
  f.market = button(f, tw, TABS_H, "Market", function()
    f:Hide()
    if side then side.lit:Hide() end
    MOTA.WorkshopMarket:OpenWindow()
  end)
  f.market:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + #TABS * (tw + 4), -HEAD_H)

  -- the batch size: how many you mean to make
  local by = HEAD_H + TABS_H + 6
  local bl = fontString(f, "GameFontNormalSmall", "LEFT")
  bl:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -(by + 5))
  bl:SetText("Batch")
  f.batches = {}
  for i, n in ipairs(W.BATCHES) do
    local b = button(f, 40, 20, "x" .. n, function() W:SetBatch(n) end)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 54 + (i - 1) * 42, -by)
    f.batches[n] = b
  end
  f.src = fontString(f, "GameFontDisableSmall", "RIGHT")
  f.src:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -(by + 5))
  f.src:SetWidth(WIDTH - 54 - 4 * 42 - 14)

  local y0 = HEAD_H + TABS_H + BATCH_H + 8
  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetSize(WIDTH - 28, ROW_H)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -(y0 + (i - 1) * ROW_H))
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.name = fontString(r, "GameFontNormal", "LEFT")
    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -2)
    r.name:SetWidth(WIDTH - 28 - 84)
    r.right = fontString(r, "GameFontHighlight", "RIGHT")
    r.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -2)
    r.right:SetWidth(80)
    r.sub = fontString(r, "GameFontDisableSmall", "LEFT")
    r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -17)
    r.sub:SetWidth(WIDTH - 36)
    local line = r:CreateTexture(nil, "BORDER")
    line:SetColorTexture(1, 1, 1, 0.06)
    line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    r:SetScript("OnEnter", tooltip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self) Panel:Click(self.v) end)
    rows[i] = r
  end
  f.none = fontString(f, "GameFontHighlightSmall", "LEFT")
  f.none:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -(y0 + 6))
  f.none:SetWidth(WIDTH - 32)
  f.none:SetWordWrap(true)

  f.foot = fontString(f, "GameFontDisableSmall", "CENTER")
  f.foot:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
  f.foot:SetWidth(WIDTH - 28)

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
  -- the chosen tab and batch hold their highlight, as the game's toggle buttons do
  local function hold(b, on) if on then b:LockHighlight() else b:UnlockHighlight() end end
  for key, b in pairs(tabs) do hold(b, key == tab) end
  local batch = W:Batch()
  for n, b in pairs(f.batches) do hold(b, n == batch) end
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
      r.right:SetTextColor(MOTA:RGB(d.loss and LOSS or GAIN))
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
  if type(bar) == "table" and bar.SetSearchText and bar.StartSearch and name then
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

function Panel:NextProfession()
  local list = professions()
  if #list < 2 then return end
  for i, p in ipairs(list) do
    if p == W.current then W.current = list[i % #list + 1]; break end
  end
  self:Refresh()
end

function Panel:Show()
  if not f then build() end
  if not W.current then W.current = professions()[1] end
  setHidden(false)
  place()
  f:Show()
  self:Refresh()
  if side then side.lit:Show() end
end

function Panel:Hide()
  setHidden(true)
  if f then f:Hide() end
  if side then side.lit:Hide() end
end

function Panel:Toggle()
  if f and f:IsShown() then self:Hide() else self:Show() end
end

local function settingOn()
  local s = MOTA.db and MOTA.db.settings
  return not s or s.workshop ~= false
end

MOTA:Listen("WORKSHOP_CHANGED", function()
  if not settingOn() then return end
  Panel:ShowSide(true)
  if hidden() then return end
  if f and f:IsShown() then Panel:Refresh() return end
  Panel:Show()
end)
MOTA:Listen("WORKSHOP_CLOSED", function()
  if f then f:Hide() end
  Panel:ShowSide(false)
  if Panel.bookOpen then Panel:BookShown(true) end -- back to the book, if it's still open
end)

-- The Professions book: the side tab on its edge, and the Workshop beside it if it was left open.
function Panel:BookShown(open)
  self.bookOpen = open
  if W.open or not settingOn() then return end -- a profession's own window takes precedence
  if open then
    if not next(W:Mine()) then return end -- nothing known yet: open a profession once first
    self:ShowSide(true)
    if not hidden() then self:Show() end
  else
    if f then f:Hide() end
    self:ShowSide(false)
  end
end

local hooked = {}
local function hookBooks()
  for _, name in ipairs(BOOKS) do
    local b = _G[name]
    if b and b.HookScript and not hooked[name] then
      hooked[name] = true
      b:HookScript("OnShow", function() Panel:BookShown(true) end)
      b:HookScript("OnHide", function() Panel:BookShown(false) end)
      if b:IsShown() then Panel:BookShown(true) end
    end
  end
end
local books = CreateFrame("Frame")
books:RegisterEvent("ADDON_LOADED")
books:RegisterEvent("PLAYER_LOGIN")
books:SetScript("OnEvent", hookBooks)

