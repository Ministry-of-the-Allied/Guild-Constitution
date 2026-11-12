-- Ministry of the Allied: guild members on the maps, the drawing side
-- (ADDON_SPEC.md, section 10.17; the facts and the messages are in Dots.lua).
--
-- Each member who shares is a small class-coloured dot on the world map (where
-- they stand, when the map shows the place they are in) and on the minimap
-- (placed by distance, turning with a rotating minimap, held on the rim when
-- they are further off than the minimap reaches). Hovering a dot shows our own
-- tip in the window's skin, with or without OpenMap.
--
-- Also here: the one-time question ("Share my place / Keep private") that
-- appears the first time the world map opens, and the Settings rows' helpers.
--
-- To keep Blizzard's map code clean ("taint"), nothing of the game's is
-- replaced or written to: our layer is our own frame on the map's canvas, and
-- we only listen after the fact (HookScript).

local _, MOTA = ...
local Kit = MOTA.Kit
local Dots = MOTA.Dots
local UI = {}
Dots.UI = UI

local DOT = 13               -- a dot's size, in game units
local RING = 2               -- the dark ring round it
local ATLAS = "WhiteCircle-RaidBlips" -- Blizzard's Interface\Minimap\PartyRaidBlips, drawn white, tinted by class
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MINIMAP_DOT = 11
local WORLD_TICK = 0.25      -- how often the world map's dots are checked for zoom or a moved map
local MINIMAP_TICK = 0.1     -- how often the minimap's dots are placed
local EDGE = 0.9             -- the minimap's usable radius, as a share of its half width (a dot is held here)

-- The minimap's reach in yards, by zoom level (the game's own scale).
local REACH = {
  indoor = { [0] = 300, 240, 180, 120, 80, 50 },
  outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}

---------------------------------------------------------------------------
-- A dot
---------------------------------------------------------------------------

local function hasAtlas()
  if UI.atlas == nil then
    UI.atlas = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ATLAS)) and true or false
  end
  return UI.atlas
end

local function classColour(class)
  local c = class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
    or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
  if c then return c.r, c.g, c.b end
  return 0.85, 0.8, 0.6
end

-- A round picture of the given size on a dot: Blizzard's white blip, or (where the
-- client doesn't have it) a plain colour cut round with the portrait mask.
local function circle(parent, layer, size)
  local t = parent:CreateTexture(nil, layer)
  t:SetSize(size, size)
  t:SetPoint("CENTER", parent, "CENTER", 0, 0)
  if hasAtlas() then
    t:SetAtlas(ATLAS)
  else
    t:SetColorTexture(1, 1, 1, 1)
    local m = parent:CreateMaskTexture()
    m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
  end
  return t
end

local function newDot(parent, size)
  local d = CreateFrame("Button", nil, parent)
  d:SetSize(size, size)
  d.ring = circle(d, "BORDER", size + RING * 2)
  d.ring:SetVertexColor(0, 0, 0, 0.8)
  d.fill = circle(d, "ARTWORK", size)
  d:SetScript("OnEnter", function(self) UI:ShowTip(self) end)
  d:SetScript("OnLeave", function() UI:HideTip() end)
  return d
end

local function paintDot(d, name, p)
  d.name, d.p = name, p
  d.fill:SetVertexColor(classColour(p.class))
end

---------------------------------------------------------------------------
-- The tip: our own frame in the window's skin, like the district tip
---------------------------------------------------------------------------

local tip
local PAD_X, PAD_Y = 14, 10
local METALS = {
  gold = { edge = "C9A24A", rule = "C9A24A" },
  silver = { edge = "AEB8C6", rule = "D6DEE9" },
}

local function tipText(font, justify)
  local fs = tip:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(MOTA:Font(font))
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function buildTip()
  tip = CreateFrame("Frame", "MinistryOfTheAlliedDotTip", UIParent)
  tip:SetFrameStrata("TOOLTIP")
  tip:SetClampedToScreen(true)
  tip.fill = tip:CreateTexture(nil, "BACKGROUND")
  tip.fill:SetAllPoints()
  tip.edge = Kit:Outline(tip, "C9A24A", 1, 0, 2)
  tip.dark = Kit:Outline(tip, "000000", 0.65, 2, 1)
  tip.frame = Kit:Outline(tip, "C9A24A", 0.55, 5, 1)
  tip.name = tipText("tipName")
  tip.who = tipText("tipHint")
  tip.where = tipText("tipHint")
  tip.ago = tipText("tipHint")
  tip:Hide()
  UI.tip = tip
end

local function paint(sides, hex, alpha)
  for _, t in ipairs(sides) do t:SetColorTexture(MOTA:RGB(hex)) t:SetAlpha(alpha or 1) end
end

local function zoneName(map)
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return info and info.name or "?"
end

local function className(class)
  local names = LOCALIZED_CLASS_NAMES_MALE
  return names and names[class] or (class and class:sub(1, 1) .. class:sub(2):lower()) or ""
end

-- Shows the tip for a dot, beside it.
function UI:ShowTip(dot)
  if not dot.p then return end
  if not tip then buildTip() end
  local skin, accent = MOTA.skin, MOTA:Accent()
  local metal = METALS[skin.METAL] or METALS.gold
  local pale = skin.PALE_INK
  Kit:Gradient(tip.fill, accent.TOP, accent.DARK)
  paint(tip.edge, metal.edge)
  paint(tip.dark, "000000", 0.65)
  paint(tip.frame, metal.rule, 0.55)

  local p = dot.p
  local r, g, b = classColour(p.class)
  tip.name:SetText(MOTA:Short(dot.name))
  tip.name:SetTextColor(r + (1 - r) * 0.35, g + (1 - g) * 0.35, b + (1 - b) * 0.35)
  local level = p.level and p.level > 0 and ("Level " .. p.level .. " ") or ""
  tip.who:SetText(level .. className(p.class))
  tip.where:SetText(("%s  %.1f, %.1f"):format(zoneName(p.map), p.x * 100, p.y * 100))
  local ago = math.floor(GetTime() - p.at)
  tip.ago:SetText(ago >= 20 and ("Heard " .. ago .. " s ago") or "")
  for _, fs in ipairs({ tip.who, tip.where, tip.ago }) do fs:SetTextColor(pale.r, pale.g, pale.b) end

  local w = math.max(120, tip.name:GetStringWidth(), tip.who:GetStringWidth(), tip.where:GetStringWidth(),
    tip.ago:GetStringWidth())
  local y = PAD_Y
  local function at(fs, h)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", tip, "TOPLEFT", PAD_X, -y)
    fs:SetSize(w + 2, h)
    y = y + h
  end
  at(tip.name, 20)
  at(tip.who, 15)
  at(tip.where, 15)
  tip.ago:SetShown(ago >= 20)
  if ago >= 20 then at(tip.ago, 15) end
  tip:SetSize(w + 2 * PAD_X, y + PAD_Y)
  tip:ClearAllPoints()
  tip:SetPoint("BOTTOMLEFT", dot, "TOPRIGHT", 6, 4)
  tip:Show()
  UI.hovering = dot
  UI.tipState = { name = dot.name, who = tip.who:GetText(), where = tip.where:GetText() }
end

function UI:HideTip()
  UI.hovering = nil
  if tip then tip:Hide() end
end

-- The district tip steps aside while a dot has its own up (UI/WorldMap.lua asks).
function Dots:TipBusy()
  return UI.hovering ~= nil
end

---------------------------------------------------------------------------
-- The world map
---------------------------------------------------------------------------

local map, layer
local worldDots = {}        -- the pool
local drawn = {}            -- the dots now up
local cache = { sig = nil } -- what the last draw looked like, to redraw only on a change

-- The frame level the layer stands on: above the districts and OpenMap's art,
-- among the map's own pins.
local function level(canvas)
  local base
  local mgr = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
  if mgr and mgr.GetValidFrameLevel then
    for _, kind in ipairs({ "PIN_FRAME_LEVEL_GROUP_MEMBER", "PIN_FRAME_LEVEL_MAP_HIGHLIGHT", "PIN_FRAME_LEVEL_MAP_EXPLORATION" }) do
      local ok, l = pcall(mgr.GetValidFrameLevel, mgr, kind)
      if ok and type(l) == "number" then base = l break end
    end
  end
  base = base or canvas:GetFrameLevel() + 1
  local api = _G.OpenMapAPI
  if type(api) == "table" and type(api.ArtTopLevel) == "function" then
    local ok, top = pcall(api.ArtTopLevel)
    if ok and type(top) == "number" and top >= base then base = top + 1 end
  end
  return base + 3
end

local function openMapStitched()
  local api = _G.OpenMapAPI
  if type(api) ~= "table" or type(api.IsStitched) ~= "function" then return false end
  local ok, on = pcall(api.IsStitched)
  return ok and on and true or false
end

-- Where a place is on the canvas, 0..1 across and down (it may be past the edge
-- on OpenMap's stitched map, which shows more than one zone); nil when this map
-- doesn't show it.
function UI:CanvasPlace(shown, p)
  if openMapStitched() then
    local api = _G.OpenMapAPI
    local ok, u, v = pcall(api.WorldFromMap, p.map, p.x, p.y)
    if ok and u then
      local ok2, cx, cy = pcall(api.MapFromWorld, shown, u, v)
      if ok2 and type(cx) == "number" and type(cy) == "number" then return cx, cy end
    end
    return nil
  end
  if p.map == shown then return p.x, p.y end
  -- a bigger map (a continent) that holds the zone they are in
  if C_Map and C_Map.GetMapRectOnMap then
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, p.map, shown)
    if ok and type(minX) == "number" and type(maxX) == "number" and maxX > minX and maxY > minY
      and (maxX - minX) < 0.999 then
      return minX + p.x * (maxX - minX), minY + p.y * (maxY - minY)
    end
  end
  return nil
end

local function canvasScale()
  local ok, s = pcall(function() return map:GetCanvasScale() end)
  return ok and type(s) == "number" and s > 0 and s or 1
end

local function worldDot(i)
  if not worldDots[i] then worldDots[i] = newDot(layer, DOT) end
  return worldDots[i]
end

-- Draws the dots for the map being shown.
function UI:PaintWorld()
  if not layer then return end
  local canvas = map:GetCanvas()
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  local shown = map.GetMapID and map:GetMapID()
  if not w or not h or w <= 0 or h <= 0 or not shown or not map:IsShown() then
    layer:Hide()
    return
  end
  layer:SetFrameLevel(level(canvas))
  layer:Show()
  local scale = canvasScale()
  local n = 0
  for _, e in ipairs(Dots:List()) do
    local cx, cy = self:CanvasPlace(shown, e.p)
    if cx then
      n = n + 1
      local d = worldDot(n)
      paintDot(d, e.name, e.p)
      d:SetScale(1 / scale)
      d:ClearAllPoints()
      d:SetPoint("CENTER", layer, "TOPLEFT", cx * w, -cy * h)
      d:Show()
    end
  end
  for i = n + 1, #worldDots do
    worldDots[i]:Hide()
    if UI.hovering == worldDots[i] then UI:HideTip() end
  end
  drawn.count = n
  cache.sig = ("%s|%s|%.3f|%.0f|%.0f|%s"):format(tostring(shown), tostring(openMapStitched()), scale, w, h, tostring(self.version))
end

local worldWait = 0
local function buildWorld()
  local canvas = map:GetCanvas()
  layer = CreateFrame("Frame", "MinistryOfTheAlliedDotsLayer", canvas)
  layer:SetAllPoints(canvas)
  layer:EnableMouse(false) -- hovers and clicks go through to the map; only the dots take the mouse
  layer:SetScript("OnUpdate", function(_, elapsed)
    worldWait = worldWait - (elapsed or 0)
    if worldWait > 0 then return end
    worldWait = WORLD_TICK
    -- a zoom, a resize, another map or OpenMap's switch since the last draw: draw again
    local canvas = map:GetCanvas()
    local sig = ("%s|%s|%.3f|%.0f|%.0f|%s"):format(tostring(map.GetMapID and map:GetMapID()), tostring(openMapStitched()),
      canvasScale(), canvas:GetWidth() or 0, canvas:GetHeight() or 0, tostring(UI.version))
    if sig ~= cache.sig then UI:PaintWorld() end
  end)
  layer:SetScript("OnHide", function() UI:HideTip() end)
  UI.layer, UI.worldDots = layer, worldDots
end

function UI:Refresh()
  self.version = (self.version or 0) + 1
  if map and map:IsShown() then
    if not layer then buildWorld() end
    self:PaintWorld()
  end
  self:PaintMinimap()
end

function UI:Attach()
  if map or not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
  map = WorldMapFrame
  UI.map = map
  if type(map.OnMapChanged) == "function" then hooksecurefunc(map, "OnMapChanged", function() UI:Refresh() end) end
  map:HookScript("OnShow", function()
    UI:Refresh()
    C_Timer.After(0.2, function() UI:MaybeAsk() end)
  end)
  map:HookScript("OnHide", function() UI:HideTip() end)
  UI:Refresh() -- (the map may already be open)
end

---------------------------------------------------------------------------
-- The minimap
---------------------------------------------------------------------------

local mini
local miniDots = {}
local miniWait = 0
local shapes = {
  -- as the game's GetMinimapShape gives them: { upper-left, lower-left, upper-right, lower-right } rounded or square
  ["SQUARE"] = { false, false, false, false }, ["CORNER-TOPLEFT"] = { true, false, false, false },
  ["CORNER-TOPRIGHT"] = { false, false, true, false }, ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
  ["CORNER-BOTTOMRIGHT"] = { false, false, false, true }, ["SIDE-LEFT"] = { true, true, false, false },
  ["SIDE-RIGHT"] = { false, false, true, true }, ["SIDE-TOP"] = { true, false, true, false },
  ["SIDE-BOTTOM"] = { false, true, false, true }, ["TRICORNER-TOPLEFT"] = { true, true, true, false },
  ["TRICORNER-TOPRIGHT"] = { true, false, true, true }, ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
  ["TRICORNER-BOTTOMRIGHT"] = { false, true, true, true },
}

-- Where I am in the game's world: first, second (as UnitPosition gives them) and the
-- continent. nil where the game won't say (an instance, or a client without it).
local function myWorld()
  if not UnitPosition then return nil end
  local ok, a, b, _, instance = pcall(UnitPosition, "player")
  if not ok or (issecretvalue and (issecretvalue(a) or issecretvalue(b))) or type(a) ~= "number" or type(b) ~= "number" then
    return nil
  end
  return a, b, instance
end

-- A place on a map in the game's world, kept on the dot (it only changes when they move).
local function worldOf(p)
  if p.wmap == p.map and p.wx == p.x and p.wy == p.y then return p.wa, p.wb, p.winstance end
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, instance, pos = pcall(C_Map.GetWorldPosFromMapPos, p.map, CreateVector2D(p.x, p.y))
  if not ok or not pos then return nil end
  local ok2, a, b = pcall(pos.GetXY, pos)
  if not ok2 or type(a) ~= "number" or type(b) ~= "number" then return nil end
  p.wmap, p.wx, p.wy, p.wa, p.wb, p.winstance = p.map, p.x, p.y, a, b, instance
  return a, b, instance
end

local function reach()
  if C_Minimap and C_Minimap.GetViewRadius then
    local ok, r = pcall(C_Minimap.GetViewRadius)
    if ok and type(r) == "number" and r > 0 then return r end
  end
  local zoom = Minimap:GetZoom() or 0
  local set = (IsIndoors and IsIndoors()) and REACH.indoor or REACH.outdoor
  return (set[zoom] or set[0]) / 2
end

-- The pixel offset from the minimap's centre for a dot, or nil for none to show.
-- mine: my place; theirs: theirs; the rest is the minimap's state this look.
local function minimapOffset(ma, mb, ta, tb, radius, rotate, sin, cos, shape, half)
  -- In the game's world the second coordinate grows to the west and the first to
  -- the north, so east of me is mb - tb and north of me is ta - ma, in yards.
  local east, north = mb - tb, ta - ma
  -- a minimap that turns with the player: the same turn as the player's facing
  if rotate then east, north = east * cos + north * sin, north * cos - east * sin end
  local fx, fy = east / radius, north / radius
  local round = true
  if shape and fx ~= 0 and fy ~= 0 then
    local i = fx < 0 and 1 or 3
    round = (fy > 0) and shape[i] or shape[i + 1]
  end
  local dist = round and (fx * fx + fy * fy) / (EDGE * EDGE) or math.max(fx * fx, fy * fy) / (EDGE * EDGE)
  local rim = dist > 1
  if rim then
    dist = dist ^ 0.5
    fx, fy = fx / dist, fy / dist
  end
  return fx * half, fy * half, rim
end
UI.MinimapOffset = minimapOffset

local function miniDot(i)
  if not miniDots[i] then
    miniDots[i] = newDot(mini, MINIMAP_DOT)
  end
  return miniDots[i]
end

function UI:PaintMinimap()
  if not Minimap then return end
  if not mini then
    mini = CreateFrame("Frame", "MinistryOfTheAlliedMinimapDots", Minimap)
    mini:SetAllPoints(Minimap)
    mini:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    mini:EnableMouse(false)
    mini:SetScript("OnUpdate", function(_, elapsed)
      miniWait = miniWait - (elapsed or 0)
      if miniWait > 0 then return end
      miniWait = MINIMAP_TICK
      UI:PaintMinimap()
    end)
    UI.mini, UI.miniDots = mini, miniDots
  end
  local ma, mb, mi = myWorld()
  local list = Dots:List()
  local n = 0
  if ma and #list > 0 then
    local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing and GetPlayerFacing()
    local sin, cos = 0, 1
    if rotate and not facing then rotate = false end
    if rotate then sin, cos = math.sin(facing), math.cos(facing) end
    local shape = GetMinimapShape and shapes[GetMinimapShape() or "ROUND"]
    local radius = reach()
    local half = (Minimap:GetWidth() or 140) / 2
    for _, e in ipairs(list) do
      local ta, tb, ti = worldOf(e.p)
      if ta and ti == mi then
        local ox, oy, rim = minimapOffset(ma, mb, ta, tb, radius, rotate, sin, cos, shape, half)
        n = n + 1
        local d = miniDot(n)
        paintDot(d, e.name, e.p)
        d:ClearAllPoints()
        d:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
        d:SetAlpha(rim and 0.75 or 1)
        d:Show()
      end
    end
  end
  for i = n + 1, #miniDots do
    miniDots[i]:Hide()
    if UI.hovering == miniDots[i] then UI:HideTip() end
  end
  mini:SetShown(n > 0)
end

---------------------------------------------------------------------------
-- The one-time question
---------------------------------------------------------------------------

local ask

local INK = "2A1F14"
local BODY = "Fellow members who run the Ministry's add-on can show as dots on your maps. "
  .. "Share your own place and they see you in the same way: a dot, only to the guild. "
  .. "Nothing is sent from dungeons, raids or battlegrounds, and you can stop at any time in Settings."

function UI:Answer(share)
  MOTA.db.settings.dotsAsked = true
  if share then MOTA.db.settings.dotsShare = true end
  if ask then ask:Hide() end
  Dots:Changed()
  if MOTA.SettingsPage and MOTA.SettingsPage.Refresh then MOTA.SettingsPage:Refresh() end
end

local function buildAsk()
  ask = CreateFrame("Frame", "MinistryOfTheAlliedDotsAsk", map)
  ask:SetSize(430, 244)
  ask:SetPoint("CENTER", map.ScrollContainer or map, "CENTER", 0, 0)
  ask:SetFrameStrata("DIALOG")
  ask:EnableMouse(true)
  Kit:Fill(ask, "F4EAD0", "E6D5AC")
  Kit:Outline(ask, "6E4F17", 0.9)
  Kit:Outline(ask, "C9A24A", 0.6, 3, 1)

  ask.eyebrow = MOTA:Tracked(ask, "pageEyebrow", "7A5719", 0.32)
  ask.eyebrow:SetPoint("TOPLEFT", ask, "TOPLEFT", 24, -20)
  ask.eyebrow:SetText("THE GUILD'S MAPS")
  ask.title = Kit:Text(ask, "dotsTitle", INK)
  ask.title:SetPoint("TOPLEFT", ask, "TOPLEFT", 24, -40)
  ask.title:SetWidth(382)
  ask.title:SetWordWrap(true)
  ask.title:SetText("Stand where the guild can see you?")
  Kit:Track(function() ask.title:SetTextColor(MOTA:RGB(MOTA:Accent().INK)) end)
  ask.body = Kit:Text(ask, "kitSmall", "5E4B33")
  ask.body:SetPoint("TOPLEFT", ask, "TOPLEFT", 24, -112)
  ask.body:SetWidth(382)
  ask.body:SetWordWrap(true)
  ask.body:SetText(BODY)

  ask.yes = Kit:Button(ask, 160, 30, "Share my place", "blue", function() UI:Answer(true) end)
  ask.yes:SetPoint("BOTTOMLEFT", ask, "BOTTOMLEFT", 24, 22)
  ask.no = Kit:Button(ask, 160, 30, "Keep private", "quiet", function() UI:Answer(false) end)
  ask.no:SetPoint("BOTTOMRIGHT", ask, "BOTTOMRIGHT", -24, 22)
  ask:Hide()
  UI.ask = ask
end

-- Asked once, the first time the world map opens in a guild: nothing is shared until yes.
function UI:MaybeAsk()
  if not map or not map:IsShown() or not MOTA.guild or not MOTA.db then return end
  if MOTA.db.settings.dotsAsked or MOTA.db.settings.dotsShare then return end
  if InCombatLockdown() then return end
  if not ask then buildAsk() end
  ask:Show()
end

-- Asks the question again (/mota dots reset, and the Settings' Ask again button):
-- sharing goes off, and the box comes back at once if the world map is open.
function UI:Reset()
  MOTA.db.settings.dotsAsked = false
  MOTA.db.settings.dotsShare = false
  if ask and ask:IsShown() then ask:Hide() end
  Dots:Changed()
  if MOTA.SettingsPage and MOTA.SettingsPage.Refresh then MOTA.SettingsPage:Refresh() end
  self:MaybeAsk()
  MOTA:Print("The guild-maps question will be asked again. Sharing is off until you answer.")
end

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------

MOTA:On("PLAYER_LOGIN", function() UI:Attach() end)
MOTA:On("ADDON_LOADED", function(_, _, name)
  if name == "Blizzard_WorldMap" then UI:Attach() end
end)
MOTA:Listen("DOTS_UPDATED", function() UI:Refresh() end)
MOTA:Listen("SKIN_CHANGED", function()
  if tip and tip:IsShown() and UI.hovering then UI:ShowTip(UI.hovering) end
end)
