-- Ministry of the Allied: the districts on the game's world map (Batch D4;
-- ADDON_SPEC.md 10; Max's answer A4). On the Stormwind City map only, all five
-- districts are drawn as outlines in their own colours and yours is lit with
-- the gold edge and a faint fill. Nothing is drawn on any other map.
--
-- The outlines come from tools/textures/districts.py. The world map has its
-- own heavier ones (D4b, Max 8 Nov: thicker dashes on a thin dark edge, so they
-- stand off yellow and green map art alike); the fill is the page's. They are
-- laid on the map's canvas, so they follow zoom, enlarge and shrink, and sit
-- under the map's own pins and labels.
--
-- Hovering a district names it (D4b, Q-D5-2): a small tooltip in the window's
-- skin, where the game's own tooltip shows, with the district's name, "Your district" when it is yours, its
-- Representative and how many citizens it has, and the outline brightens. The
-- layer still takes no mouse: a light OnUpdate reads where the cursor is on the
-- map and tests it against the same shapes as the Districts page
-- (District:At). When a pin (a quest, a flight master) has the game's tooltip
-- up, ours stays hidden, and we only ever hide our own tooltip.
--
-- To keep Blizzard's map code clean ("taint"), nothing of Blizzard's is
-- replaced or written to: the layer and the tooltip are our own frames, and we
-- only listen after the fact (hooksecurefunc and HookScript). Settings:
-- "District glow" (MOTA.db.settings.glow) turns it on and off.

local _, MOTA = ...
local M = MOTA.Media
local Kit = MOTA.Kit
local W = {}
MOTA.WorldMap = W

local DZ = M.districts
local REST_ALPHA = 0.62 -- the other four: faint (A4); a touch stronger after Max's look in game
local FILL_ALPHA = 0.15 -- yours: a faint wash inside the gold edge
local HOVER_FILL = 0.1  -- another district under the cursor: a lighter wash
local HOVER_MINE = 0.24 -- yours under the cursor: the wash a little stronger
local LOOKS = { "fill", "rest", "lit" }
-- The world map's own pieces for each look; the page's when they're missing.
local WM_PIECE = { fill = "fill", rest = "wmrest", lit = "wmlit" }
local TICK = 0.05       -- how often the hover is checked, in seconds

local METALS = {
  gold = { edge = "C9A24A", head = "F3D98A", rule = "C9A24A" },
  silver = { edge = "AEB8C6", head = "F1F4F8", rule = "D6DEE9" },
}

local map, layer, looks, tip
local hovered, wait = nil, 0

local function enabled()
  return MOTA.db ~= nil and MOTA.db.settings.glow and true or false
end

local function mine()
  local d = MOTA.me and MOTA.District and MOTA.District:Of(MOTA.me)
  return d and d.code
end

-- The map's own layer for highlights sits above the base map and its explored
-- parts and below every pin (quests, flight masters, the player arrow). Asked of
-- the map's level manager each time, as the map may have moved levels.
-- With OpenMap, its stitched art can reach above that: the layer goes just over
-- it (OpenMap lifts the pins two over its art, so they stay on top; D5e).
local function overOpenMap(l)
  local api = _G.OpenMapAPI
  local ok, top = false, nil
  if type(api) == "table" and type(api.ArtTopLevel) == "function" then ok, top = pcall(api.ArtTopLevel) end
  if ok and type(top) == "number" and top >= l then return top + 1 end
  return l
end

local function level(canvas)
  local mgr = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
  if mgr and mgr.GetValidFrameLevel then
    for _, kind in ipairs({ "PIN_FRAME_LEVEL_MAP_HIGHLIGHT", "PIN_FRAME_LEVEL_MAP_EXPLORATION" }) do
      local ok, l = pcall(mgr.GetValidFrameLevel, mgr, kind)
      if ok and type(l) == "number" then return overOpenMap(l) end
    end
  end
  return overOpenMap(canvas:GetFrameLevel() + 1)
end

---------------------------------------------------------------------------
-- The hover tooltip: our own frame, in the window's skin (as the online tip)
---------------------------------------------------------------------------

local PAD_X, PAD_Y, ROW_H, MIN_W = 14, 10, 17, 150

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

local function buildTip()
  tip = CreateFrame("Frame", "MinistryOfTheAlliedMapTip", UIParent)
  tip:SetFrameStrata("TOOLTIP")
  tip:SetClampedToScreen(true)
  tip.fill = tip:CreateTexture(nil, "BACKGROUND")
  tip.fill:SetAllPoints()
  tip.edge = Kit:Outline(tip, "C9A24A", 1, 0, 2)
  tip.dark = Kit:Outline(tip, "000000", 0.65, 2, 1)
  tip.frame = Kit:Outline(tip, "C9A24A", 0.55, 5, 1)
  tip.name = text("tipName")
  tip.yours = text("tipHint")
  tip.yours:SetText("Your district")
  tip.line = tip:CreateTexture(nil, "ARTWORK")
  tip.repLabel = text("tipHead")
  tip.repLabel:SetText("REP.")
  tip.rep = text("tipHint", "RIGHT")
  tip.countLabel = text("tipHead")
  tip.countLabel:SetText("CITIZENS")
  tip.count = text("tipHint", "RIGHT")
  tip:Hide()
  W.tip = tip
end

-- The district's colour, lifted towards white so the darker ones read on leather.
local function bright(hex)
  local r, g, b = MOTA:RGB(hex)
  return r + (1 - r) * 0.4, g + (1 - g) * 0.4, b + (1 - b) * 0.4
end

-- Fills the tooltip for one district and sizes it.
function W:FillTip(code)
  if not tip then buildTip() end
  local D = MOTA.District
  local d = D.byCode[code]
  local skin = MOTA.skin
  local metal = METALS[skin.METAL] or METALS.gold
  local accent = MOTA:Accent()
  local pale = skin.PALE_INK
  Kit:Gradient(tip.fill, accent.TOP, accent.DARK)
  paint(tip.edge, metal.edge)
  paint(tip.dark, "000000", 0.65)
  paint(tip.frame, metal.rule, 0.55)
  Kit:Solid(tip.line, metal.rule, 0.55)

  tip.name:SetText(d.short)
  tip.name:SetTextColor(bright(d.color))
  local yours = code == mine()
  tip.yours:SetShown(yours)
  tip.yours:SetTextColor(pale.r, pale.g, pale.b)
  local rep = D:Rep(code)
  tip.rep:SetText(rep and MOTA:Short(rep) or "Vacant")
  local n = D:Size(code)
  tip.count:SetText(tostring(n))
  for _, fs in ipairs({ tip.repLabel, tip.countLabel }) do fs:SetTextColor(MOTA:RGB(metal.head)) end
  for _, fs in ipairs({ tip.rep, tip.count }) do fs:SetTextColor(pale.r, pale.g, pale.b) end

  local labelW = math.max(tip.repLabel:GetStringWidth(), tip.countLabel:GetStringWidth()) + 14
  local valueW = math.max(tip.rep:GetStringWidth(), tip.count:GetStringWidth())
  local w = math.max(MIN_W, tip.name:GetStringWidth(), yours and tip.yours:GetStringWidth() or 0, labelW + valueW)

  local function at(region, x, y, rw, rh)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", tip, "TOPLEFT", x, -y)
    region:SetSize(rw, rh)
  end
  local y = PAD_Y
  at(tip.name, PAD_X, y, w + 2, 20)
  y = y + 20
  if yours then
    at(tip.yours, PAD_X, y, w + 2, 15)
    y = y + 15
  end
  y = y + 6
  at(tip.line, PAD_X, y, w, 1)
  y = y + 1 + 5
  at(tip.repLabel, PAD_X, y, labelW, ROW_H)
  at(tip.rep, PAD_X + labelW, y, w - labelW, ROW_H)
  y = y + ROW_H
  at(tip.countLabel, PAD_X, y, labelW, ROW_H)
  at(tip.count, PAD_X + labelW, y, w - labelW, ROW_H)
  y = y + ROW_H + PAD_Y
  tip:SetSize(w + 2 * PAD_X, y)
  W.tipState = { code = code, name = d.short, yours = yours, rep = tip.rep:GetText(), count = n }
end

-- Where the game puts its own tooltip (Max, 8 Nov: "use the position of the
-- game's tooltip"). Each time the game's tooltip shows at its default place
-- (anchor type ANCHOR_NONE, as GameTooltip_SetDefaultAnchor leaves it, after
-- Edit Mode, ElvUI's mover or any other add-on has placed it), its first point
-- is copied. Until it has shown once: the game's default container, ElvUI's
-- tooltip mover, or the screen's bottom right corner. If ElvUI is set to put
-- tooltips at the cursor, ours goes there too.
local spot -- { point, relativeTo, relativePoint, x, y }

local function learn()
  local gt = GameTooltip
  if not gt or not gt.GetAnchorType or gt:GetAnchorType() ~= "ANCHOR_NONE" then return end
  local point, rel, relPoint, x, y = gt:GetPoint(1)
  if point and rel ~= tip then spot = { point, rel or UIParent, relPoint or point, x or 0, y or 0 } end
end

local function elvCursor()
  local E = ElvUI and ElvUI[1]
  local ok, on = pcall(function() return E.private.tooltip.enable and E.db.tooltip.cursorAnchor end)
  return ok and on and true or false
end

local function fallback()
  local box = GameTooltipDefaultContainer or TooltipMover
  if box then return { "BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0 } end
  return { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -(CONTAINER_OFFSET_X or 0) - 13, CONTAINER_OFFSET_Y or 64 }
end

local function place()
  tip:ClearAllPoints()
  if elvCursor() then
    local cx, cy = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    tip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / s + 16, cy / s + 14)
    W.tipAt = "cursor"
    return
  end
  local p = spot or fallback()
  tip:SetPoint(p[1], p[2], p[3], p[4], p[5])
  W.tipAt = spot and "game" or "default"
end

if GameTooltip and GameTooltip.HookScript then GameTooltip:HookScript("OnShow", learn) end

local function hideTip()
  if tip then tip:Hide() end
end

---------------------------------------------------------------------------
-- The layer
---------------------------------------------------------------------------

-- A pin or another part of the map has the game's tooltip up: it wins.
local function gameTipBusy()
  -- a guild member's dot has its own tip up (UI/Dots.lua)
  if MOTA.Dots and MOTA.Dots.TipBusy and MOTA.Dots:TipBusy() then return true end
  local gt = GameTooltip
  if not gt or not gt:IsShown() then return false end
  return not gt.GetOwner or gt:GetOwner() ~= nil
end

-- Where the cursor is, in the shapes' pixels (District:At), or nil when it's
-- not over the map itself (over the quest log, the frame, another window).
function W:Cursor()
  local box = map.ScrollContainer or map:GetCanvas()
  if box.IsMouseOver and not box:IsMouseOver() then return nil end
  local nx, ny
  if map.GetNormalizedCursorPosition then
    nx, ny = map:GetNormalizedCursorPosition()
  else
    local canvas = map:GetCanvas()
    local left, top, w, h = canvas:GetLeft(), canvas:GetTop(), canvas:GetWidth(), canvas:GetHeight()
    if not left or not top or not w or w <= 0 or not h or h <= 0 then return nil end
    local cx, cy = GetCursorPosition()
    local s = canvas:GetEffectiveScale()
    nx, ny = (cx / s - left) / w, (top - cy / s) / h
  end
  if type(nx) ~= "number" or type(ny) ~= "number" or nx < 0 or nx > 1 or ny < 0 or ny > 1 then return nil end
  return nx * DZ.shot.w - DZ.crop.x, ny * DZ.shot.h - DZ.crop.y
end

-- Checks what's under the cursor; called by the layer's OnUpdate.
function W:Hover()
  if not layer or not layer:IsShown() then return end
  local x, y = self:Cursor()
  local code = x and MOTA.District:At(x, y)
  if code ~= hovered then
    hovered = code
    self:Shade()
  end
  if code and not gameTipBusy() then
    if not tip or not tip:IsShown() or self.tipState.code ~= code then
      self:FillTip(code)
      place()
    elseif self.tipAt == "cursor" then
      place()
    end
    tip:Show()
  else
    hideTip()
  end
end

local function art(look, code)
  local p = M.pieces["dz_" .. code .. "_" .. WM_PIECE[look]] or M.pieces["dz_" .. code .. "_" .. look]
  local t = layer:CreateTexture(nil, "ARTWORK", nil, ({ fill = 1, rest = 2, lit = 3 })[look])
  t:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
  t:SetTexCoord(p.l, p.r, p.t, p.b)
  t.piece = p
  return t
end

local function build()
  local canvas = map:GetCanvas()
  layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:EnableMouse(false) -- clicks and hovers go through to the map
  looks = {}
  for _, d in ipairs(MOTA.CONST.DISTRICTS) do
    local l = {}
    for _, look in ipairs(LOOKS) do l[look] = art(look, d.code) end
    looks[d.code] = l
  end
  layer:SetScript("OnSizeChanged", function() W:Place() end)
  layer:SetScript("OnUpdate", function(_, elapsed)
    wait = wait - (elapsed or 0)
    if wait > 0 then return end
    wait = TICK
    W:Hover()
  end)
  layer:SetScript("OnHide", function()
    hovered = nil
    hideTip()
  end)
  layer:Hide()
  W.layer, W.looks = layer, looks
end

-- The screenshot the shapes were traced on covers the whole Stormwind City map
-- edge to edge (Set waypoint lands where it should, Max 8 Nov), so a screenshot
-- pixel is a share of the canvas by the screenshot's size.
function W:Place()
  if not layer then return end
  local canvas = map:GetCanvas()
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  if not w or not h or w <= 0 or h <= 0 then return end
  local sx, sy = w / DZ.shot.w, h / DZ.shot.h
  for _, l in pairs(looks) do
    for _, t in pairs(l) do
      local p = t.piece
      t:SetSize(p.w * sx, p.h * sy)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", layer, "TOPLEFT", (p.x + DZ.crop.x) * sx, -(p.y + DZ.crop.y) * sy)
    end
  end
  self.scale = { sx, sy }
end

-- Yours lit, the others faint; the one under the cursor brighter.
function W:Shade()
  if not looks then return end
  local you = mine()
  for code, l in pairs(looks) do
    local yours, over = code == you, code == hovered
    l.lit:SetShown(yours)
    l.fill:SetShown(yours or over)
    l.fill:SetAlpha(yours and (over and HOVER_MINE or FILL_ALPHA) or HOVER_FILL)
    l.rest:SetShown(not yours)
    l.rest:SetAlpha(over and 1 or REST_ALPHA)
  end
  self.drawn = { lit = you, hovered = hovered }
end

-- Shown on Stormwind City with the switch on.
function W:Paint()
  if not map then return end
  local show = enabled() and map.GetMapID and map:GetMapID() == MOTA.CONST.STORMWIND_MAP_ID
  if not show then
    if layer then layer:Hide() end
    hovered = nil
    hideTip()
    self.drawn = nil
    return
  end
  if not layer then build() end
  layer:SetFrameLevel(level(map:GetCanvas()))
  self:Place()
  self:Shade()
  layer:Show()
end

local function refresh()
  if map and map:IsShown() then W:Paint() end
end

-- Hooked on to the world map once it exists (it may load after us).
function W:Attach()
  if map or not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
  map = WorldMapFrame
  self.map = map
  if type(map.OnMapChanged) == "function" then
    hooksecurefunc(map, "OnMapChanged", refresh)
  end
  map:HookScript("OnShow", refresh)
  map:HookScript("OnHide", function()
    hovered = nil
    hideTip()
  end)
  refresh()
end

MOTA:On("PLAYER_LOGIN", function() W:Attach() end)
MOTA:On("ADDON_LOADED", function(_, _, name)
  if name == "Blizzard_WorldMap" then W:Attach() end
end)
MOTA:Listen("DISTRICT_CHANGED", refresh)
MOTA:Listen("GLOW_CHANGED", refresh)
MOTA:Listen("GUILD_READY", refresh)
MOTA:Listen("ME_LEARNED", refresh)
MOTA:Listen("SKIN_CHANGED", function()
  if tip and tip:IsShown() and W.tipState then W:FillTip(W.tipState.code) end
end)
