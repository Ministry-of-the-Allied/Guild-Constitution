-- Ministry of the Allied: the Workshop on item tooltips (Duncan, 15 Nov 2026).
-- Any item's tooltip, wherever it's shown (bags, the auction house, chat links), gets the
-- Workshop's lines when it has something to say:
--   Craft profit   for an item this character crafts: the sale after the 5% cut, less the
--                  materials, at the latest prices (green makes money, red loses it)
--   Sells          how fast it sells, from the market watch's scans
--   Your flips     how many you've sold through flips, and their profit
-- Turned off with the Workshop itself (settings.workshop = false).

local _, MOTA = ...
local Tip = {}
MOTA.WorkshopTooltip = Tip

local GAIN, LOSS = "1EFF00", "FF2020"

local function money(c) return MOTA.Workshop:Money(c) end
local function signed(c) return (c >= 0 and "+" or "") .. money(c) end

-- This character's learned recipe that makes the item, or nil.
local function recipeFor(item)
  for _, prof in pairs(MOTA.Workshop:Mine()) do
    for id, r in pairs(prof.recipes or {}) do
      if r.item == item and r.learned ~= false then return id, r end
    end
  end
end

-- Units sold and profit over every flip that bought or sold the item.
local function flips(item)
  local F = MOTA.Flips
  if not F then return nil end
  local sold, profit, n = 0, 0, 0
  for _, f in ipairs(F:All()) do
    if f.item == item or f.makes == item then
      local s = F:Sum(f)
      n, sold, profit = n + 1, sold + s.sold, profit + s.profit
    end
  end
  if n > 0 then return sold, profit, n end
end

-- The lines for an item: { left, right, colour of right }, or an empty list.
function Tip:Lines(item)
  local out = {}
  if not item or not MOTA.Workshop then return out end
  local s = MOTA.db and MOTA.db.settings
  if s and s.workshop == false then return out end
  local id, r = recipeFor(item)
  if id then
    local ok, v = pcall(MOTA.Workshop.Value, MOTA.Workshop, id, r)
    if ok and v and v.sale and v.profit then
      out[#out + 1] = { "Craft profit (after 5% cut)", signed(v.profit) .. ((v.missing or 0) > 0 and "*" or ""), v.profit >= 0 and GAIN or LOSS }
    end
  end
  local rate = MOTA.Market and MOTA.Market:RateText(item)
  if rate then out[#out + 1] = { "Sells", rate, "FFFFFF" } end
  local sold, profit, n = flips(item)
  if sold then
    out[#out + 1] = { ("Your flips (%d)"):format(n), ("%d sold, %s"):format(sold, signed(profit)), profit >= 0 and GAIN or LOSS }
  end
  return out
end

function Tip:Add(tooltip, item)
  local lines = self:Lines(item)
  if #lines == 0 or not tooltip or not tooltip.AddDoubleLine then return end
  tooltip:AddLine(MOTA:Color("gold", "Workshop"))
  for _, l in ipairs(lines) do
    local r, g, b = MOTA:RGB(l[3])
    tooltip:AddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, r, g, b)
  end
  if tooltip.Show then tooltip:Show() end
end

local function itemFromLink(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- The modern tooltip hook where the client has it; the old OnTooltipSetItem otherwise.
local T = _G.TooltipDataProcessor
if T and T.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
  T.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    local item = data and data.id
    if not item and tooltip and tooltip.GetItem then item = itemFromLink(select(2, tooltip:GetItem())) end
    pcall(Tip.Add, Tip, tooltip, item)
  end)
else
  for _, tt in ipairs({ _G.GameTooltip, _G.ItemRefTooltip }) do
    if tt and tt.HookScript then
      pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self)
        local _, link = self:GetItem()
        pcall(Tip.Add, Tip, self, itemFromLink(link))
      end)
    end
  end
end
