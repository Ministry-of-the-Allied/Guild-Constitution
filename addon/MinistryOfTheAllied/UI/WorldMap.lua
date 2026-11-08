-- Ministry of the Allied: the districts on the game's world map (Batch D4;
-- ADDON_SPEC.md 10; Max's answer A4). On the Stormwind City map only, all five
-- districts are drawn as faint outlines in their own colours and yours is lit
-- with the gold edge and a faint fill. Nothing is drawn on any other map.
--
-- The outlines are the same pieces as the Districts page (tools/textures/
-- districts.py), laid on the map's canvas, so they follow zoom, enlarge and
-- shrink with the map. They sit under the map's own pins and labels.
--
-- To keep Blizzard's map code clean ("taint"), nothing of Blizzard's is
-- replaced or written to: the layer is our own frame on the canvas, and we only
-- listen after the fact (hooksecurefunc and HookScript). Settings: "District
-- glow" (MOTA.db.settings.glow) turns it on and off.

local _, MOTA = ...
local M = MOTA.Media
local W = {}
MOTA.WorldMap = W

local DZ = M.districts
local REST_ALPHA = 0.62 -- the other four: faint (A4); a touch stronger after Max's look in game
local FILL_ALPHA = 0.15 -- yours: a faint wash inside the gold edge
local LOOKS = { "fill", "rest", "lit" }

local map, layer, looks

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
local function level(canvas)
  local mgr = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
  if mgr and mgr.GetValidFrameLevel then
    for _, kind in ipairs({ "PIN_FRAME_LEVEL_MAP_HIGHLIGHT", "PIN_FRAME_LEVEL_MAP_EXPLORATION" }) do
      local ok, l = pcall(mgr.GetValidFrameLevel, mgr, kind)
      if ok and type(l) == "number" then return l end
    end
  end
  return canvas:GetFrameLevel() + 1
end

local function build()
  local canvas = map:GetCanvas()
  layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:EnableMouse(false) -- clicks and hovers go through to the map
  looks = {}
  for _, d in ipairs(MOTA.CONST.DISTRICTS) do
    local l = {}
    for i, look in ipairs(LOOKS) do
      local p = M.pieces["dz_" .. d.code .. "_" .. look]
      local t = layer:CreateTexture(nil, "ARTWORK", nil, i)
      t:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
      t:SetTexCoord(p.l, p.r, p.t, p.b)
      t.piece = p
      l[look] = t
    end
    looks[d.code] = l
  end
  layer:SetScript("OnSizeChanged", function() W:Place() end)
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

-- Shown on Stormwind City with the switch on; yours lit, the others faint.
function W:Paint()
  if not map then return end
  local show = enabled() and map.GetMapID and map:GetMapID() == MOTA.CONST.STORMWIND_MAP_ID
  if not show then
    if layer then layer:Hide() end
    self.drawn = nil
    return
  end
  if not layer then build() end
  layer:SetFrameLevel(level(map:GetCanvas()))
  self:Place()
  local you = mine()
  for code, l in pairs(looks) do
    local yours = code == you
    l.lit:SetShown(yours)
    l.fill:SetShown(yours)
    l.fill:SetAlpha(FILL_ALPHA)
    l.rest:SetShown(not yours)
    l.rest:SetAlpha(REST_ALPHA)
  end
  layer:Show()
  self.drawn = { lit = you }
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
