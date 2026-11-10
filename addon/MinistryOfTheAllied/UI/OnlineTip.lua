-- Ministry of the Allied: the "who's online" tooltip on the minimap seal
-- (OnlineTooltip board). Our own frame, not the game's GameTooltip, so other
-- add-ons' tooltips are untouched. The number online at the top, then the
-- online members by office (Roster.lua, MOTA:OnlineSections), each name in its
-- class colour with a green dot.
--   up to LIST_MAX online: one name per line under the office headings;
--   more: one column per office side by side, a long office running on into
--   more columns of COL_MAX names under its one heading.
-- The frame wears the window's skin: its leather (the accent) and metal.

local _, MOTA = ...
local Kit = MOTA.Kit
local Tip = {}
MOTA.OnlineTip = Tip

local LIST_MAX, COL_MAX = 20, 9
local PAD_X, PAD_TOP, PAD_BOT = 18, 14, 12
local NAME_H, HEAD_H, SEC_GAP = 17, 18, 10
local DOT, DOT_GAP = 9, 11
local COL_GAP, SUB_GAP = 22, 16
local MIN_W = 200
local HINT = "Click: open · Right-click: settings · Drag: move"
local SHAMAN_ON_BLUE = "4C9EF5" -- the game's blue is hard to read on the blue skins

local METALS = {
  gold = { edge = "C9A24A", head = "F3D98A", rule = "C9A24A" },
  silver = { edge = "AEB8C6", head = "F1F4F8", rule = "D6DEE9" },
}

local tip
local heads, names = {}, {}

local function paint(sides, hex, alpha)
  for _, t in ipairs(sides) do t:SetColorTexture(MOTA:RGB(hex)) t:SetAlpha(alpha or 1) end
end

local function text(font, justify)
  local fs = tip:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(MOTA:Font(font))
  fs:SetJustifyH(justify or "LEFT")
  fs:SetJustifyV("MIDDLE")
  fs:SetWordWrap(false)
  return fs
end

local function build()
  tip = CreateFrame("Frame", "MinistryOfTheAlliedOnlineTip", UIParent)
  tip:SetFrameStrata("TOOLTIP")
  tip:SetClampedToScreen(true)
  tip.fill = tip:CreateTexture(nil, "BACKGROUND")
  tip.fill:SetAllPoints()
  tip.edge = Kit:Outline(tip, "C9A24A", 1, 0, 2)
  tip.dark = Kit:Outline(tip, "000000", 0.65, 2, 1)
  tip.frame = Kit:Outline(tip, "C9A24A", 0.55, 6, 1)
  tip.num = text("tipCount")
  tip.word = text("tipHead")
  tip.word:SetText("ONLINE")
  tip.hint = text("tipHint")
  tip.hint:SetText(HINT)
  tip.empty = text("tipHint")
  tip.line1 = tip:CreateTexture(nil, "ARTWORK")
  tip.line2 = tip:CreateTexture(nil, "ARTWORK")
  tip:Hide()
end

local function head(i)
  local h = heads[i]
  if not h then
    h = { fs = text("tipHead"), line = tip:CreateTexture(nil, "ARTWORK") }
    heads[i] = h
  end
  h.fs:Show()
  h.line:Show()
  return h
end

local function name(i)
  local n = names[i]
  if not n then
    n = { fs = text("tipName") }
    n.dot = Kit:Art(tip, "b_kdot-on", "ARTWORK")
    names[i] = n
  end
  n.fs:Show()
  n.dot:Show()
  return n
end

-- A class colour; the Shaman's blue is lightened on the blue skins.
local function colorOf(p, accent)
  if p.class == "SHAMAN" and accent == "sh" then return MOTA:RGB(SHAMAN_ON_BLUE) end
  return MOTA:ClassColor(p.class)
end

function Tip:Anchor()
  local owner = tip and tip.owner
  if not owner then return end
  local cx, cy = owner:GetCenter()
  local k = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local right = cx and cx * k > UIParent:GetWidth() / 2
  local top = cy and cy * k > UIParent:GetHeight() / 2
  tip:ClearAllPoints()
  tip:SetPoint((top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"), owner,
    (top and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT"), 0, top and -4 or 4)
end

function Tip:Refresh()
  if not tip then return end
  local skin = MOTA.skin
  local metal = METALS[skin.METAL] or METALS.gold
  local accent = MOTA:Accent()
  Kit:Gradient(tip.fill, accent.TOP, accent.DARK)
  paint(tip.edge, metal.edge)
  paint(tip.dark, "000000", 0.65)
  paint(tip.frame, metal.rule, 0.55)
  tip.num:SetTextColor(MOTA:RGB(metal.head))
  tip.word:SetTextColor(skin.PALE_INK.r, skin.PALE_INK.g, skin.PALE_INK.b)
  tip.hint:SetTextColor(skin.PALE_INK.r, skin.PALE_INK.g, skin.PALE_INK.b)
  tip.empty:SetTextColor(skin.PALE_INK.r, skin.PALE_INK.g, skin.PALE_INK.b)
  Kit:Solid(tip.line1, metal.rule, 0.55)
  Kit:Solid(tip.line2, metal.rule, 0.55)
  for _, h in ipairs(heads) do h.fs:Hide() h.line:Hide() end
  for _, n in ipairs(names) do n.fs:Hide() n.dot:Hide() end

  local count, sections = MOTA:OnlineSections()
  local columns = count > LIST_MAX
  local hi, ni = 0, 0

  -- First pass: set every text and measure it.
  local layout = {}
  for si, s in ipairs(sections) do
    hi = hi + 1
    local h = head(hi)
    h.fs:SetText(s.title:upper())
    h.fs:SetTextColor(MOTA:RGB(metal.head))
    Kit:Gradient(h.line, metal.rule, metal.rule, 0.85, 0, true)
    local sec = { head = h, hw = h.fs:GetStringWidth() + 20, entries = {}, nameW = 0 }
    for _, p in ipairs(s.people) do
      ni = ni + 1
      local n = name(ni)
      local letters = MOTA.Honours and MOTA.Honours:Letters(p.name)
      local shown = letters and (p.name .. " |cffC9A24A" .. letters .. "|r") or p.name
      local title = MOTA.Honours and MOTA.Honours:Title(p.name)
      if title then shown = shown .. " |cffC9A24A· " .. title .. "|r" end
      n.fs:SetText(p.main and (shown .. " (" .. p.main .. ")") or shown)
      local r, g, b = colorOf(p, skin.ACCENT)
      n.fs:SetTextColor(r, g, b)
      n.color = { r, g, b }
      n.shown = p.name
      sec.entries[#sec.entries + 1] = n
      sec.nameW = math.max(sec.nameW, n.fs:GetStringWidth() + DOT + DOT_GAP)
    end
    layout[si] = sec
  end

  tip.num:SetText(tostring(count))
  local numW, wordW = tip.num:GetStringWidth(), tip.word:GetStringWidth()
  local topW = numW + 9 + wordW
  local hintW = tip.hint:GetStringWidth()
  local W = math.max(MIN_W, topW, hintW)
  if count == 0 then
    tip.empty:SetText(next(MOTA.roster) and "No one is online." or "Reading the guild roll...")
    tip.empty:Show()
    W = math.max(W, tip.empty:GetStringWidth())
  else
    tip.empty:Hide()
  end

  -- Section sizes.
  local state = { count = count, mode = columns and "columns" or "list", sections = {} }
  if columns then
    local total = 0
    for _, sec in ipairs(layout) do
      sec.nsub = math.ceil(#sec.entries / COL_MAX)
      sec.w = math.max(sec.nsub * sec.nameW + (sec.nsub - 1) * SUB_GAP, sec.hw)
      sec.rows = math.min(#sec.entries, COL_MAX)
      total = total + sec.w
    end
    W = math.max(W, total + COL_GAP * (#layout - 1))
  else
    for _, sec in ipairs(layout) do
      sec.nsub, sec.rows = 1, #sec.entries
      W = math.max(W, sec.nameW, sec.hw)
    end
  end

  -- Second pass: place.
  local function at(region, x, y, point)
    region:ClearAllPoints()
    region:SetPoint(point or "TOPLEFT", tip, "TOPLEFT", x, -y)
  end
  local y = PAD_TOP
  at(tip.num, PAD_X + (W - topW) / 2, y)
  tip.num:SetSize(numW + 2, 28)
  tip.word:SetSize(wordW + 2, 14)
  at(tip.word, PAD_X + (W - topW) / 2 + numW + 9, y + 11)
  y = y + 28 + 8
  at(tip.line1, PAD_X, y)
  tip.line1:SetSize(W, 1)
  y = y + 1 + 10
  if count == 0 then
    at(tip.empty, PAD_X, y)
    tip.empty:SetSize(W, 16)
    y = y + 16 + SEC_GAP
  end

  local function placeSection(sec, x, top)
    sec.head.fs:SetSize(sec.hw, HEAD_H)
    at(sec.head.fs, x, top)
    at(sec.head.line, x + sec.hw - 10, top + HEAD_H / 2)
    sec.head.line:SetSize(math.max(1, sec.w - sec.hw + 10), 1)
    local row, col = 0, 0
    for _, n in ipairs(sec.entries) do
      local nx = x + col * (sec.nameW + SUB_GAP)
      local ny = top + HEAD_H + row * NAME_H
      n.dot:ClearAllPoints()
      -- the dot's picture has a glow round it, so it's centred, not corner-placed
      n.dot:SetPoint("CENTER", tip, "TOPLEFT", nx + DOT / 2, -(ny + NAME_H / 2))
      n.fs:SetSize(sec.nameW - DOT - DOT_GAP + 2, NAME_H)
      at(n.fs, nx + DOT + DOT_GAP, ny)
      row = row + 1
      if row == COL_MAX and columns then row, col = 0, col + 1 end
    end
    local shown = {}
    for i, n in ipairs(sec.entries) do shown[i] = n.fs:GetText() end
    state.sections[#state.sections + 1] = { title = sec.head.fs:GetText(), rows = sec.rows, subcols = sec.nsub, count = #sec.entries, names = shown }
  end

  if columns then
    local x, tallest = PAD_X, 0
    for _, sec in ipairs(layout) do
      placeSection(sec, x, y)
      x = x + sec.w + COL_GAP
      tallest = math.max(tallest, HEAD_H + sec.rows * NAME_H)
    end
    y = y + tallest
  else
    for _, sec in ipairs(layout) do
      sec.w = W
      placeSection(sec, PAD_X, y)
      y = y + HEAD_H + sec.rows * NAME_H + SEC_GAP
    end
    y = y - SEC_GAP
  end

  y = y + 10
  at(tip.line2, PAD_X, y)
  tip.line2:SetSize(W, 1)
  y = y + 1 + 8
  tip.hint:SetSize(W, 15)
  at(tip.hint, PAD_X, y)
  tip.hint:SetJustifyH("CENTER")
  y = y + 15 + PAD_BOT

  local width = W + 2 * PAD_X
  tip:SetSize(width, y)
  tip:SetScale(math.min(1, UIParent:GetWidth() * 0.95 / width))
  state.w, state.h = width, y
  Tip.state = state
  self:Anchor()
end

function Tip:Show(owner)
  if not tip then build() end
  tip.owner = owner
  MOTA:RequestRoster()
  self:Refresh()
  tip:Show()
end

function Tip:Hide()
  if tip then tip:Hide() end
end

MOTA:Listen("ROSTER_UPDATED", function()
  if tip and tip:IsShown() then Tip:Refresh() end
end)
MOTA:Listen("SKIN_CHANGED", function()
  if tip and tip:IsShown() then Tip:Refresh() end
end)
