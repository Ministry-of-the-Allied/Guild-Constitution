-- Ministry of the Allied: Hide and Seek on the world map (Duncan, 2026-11-10).
-- The play area's edge is drawn on the game's world map for everyone while a
-- game is open or being played (with "No map" on, players see it on the Games
-- Hall page instead, as the map stays shut for them), and for the organiser
-- while they set one up.
--
-- Drawing a play area: the organiser presses "Draw on map" and clicks the
-- corners on a zone map, one by one (3 to 16); the shape closes itself.
-- "Undo corner" on the page takes the last one back.
--
-- World yards (UnitPosition: y first, then x) are turned into map places with
-- C_Map.GetMapPosFromWorldPos, and back with GetWorldPosFromMapPos. Nothing of
-- Blizzard's is replaced: the edge is our own dots on the map's canvas, and
-- we only listen after the fact.

local _, MOTA = ...
local HM = {}
MOTA.HideMap = HM

local SPACING = 7  -- pixels between the edge's dots on the map
local dots, used, hooked = {}, 0, false
HM.drawing = false

local function map() return _G.WorldMapFrame end

-- A world spot (inst, x, y) to a map's 0-1 place, or nil.
local function toMap(inst, x, y, mapID)
  if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) or not mapID then return nil end
  local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, inst, CreateVector2D(y, x), mapID)
  if ok and pos then
    local px, py = pos:GetXY()
    if px and py then return px, py end
  end
end

-- A map's 0-1 place to a world spot: inst, x, y.
local function toWorld(mapID, px, py)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(px, py))
  if ok and inst and pos then
    local wy, wx = pos:GetXY()
    return inst, wx, wy
  end
end
HM.ToMap, HM.ToWorld = toMap, toWorld

-- The play area to draw: the game on now, or the organiser's draft.
function HM:Area()
  local Hi = MOTA.Hide
  local G = Hi:Current()
  if G and Hi:Live(G) then return G end
  local d = MOTA.db and MOTA.db.hideDraft
  if d and d.cx and MOTA.Games:CanRun(MOTA.me) then return d end
end

local function dot(canvas)
  used = used + 1
  local t = dots[used]
  if not t then
    t = canvas:CreateTexture(nil, "OVERLAY")
    t:SetSize(4, 4)
    t:SetColorTexture(MOTA:RGB("C9A24A"))
    dots[used] = t
  end
  return t
end

function HM:Paint()
  local m = map()
  if not m or not m.GetCanvas then return end
  for _, t in ipairs(dots) do t:Hide() end
  used = 0
  if not m:IsShown() then return end
  local A = self:Area()
  local mapID = m.GetMapID and m:GetMapID()
  if not A or not mapID then return end
  local canvas = m:GetCanvas()
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  local shape = MOTA.Hide:Shape(A)
  local ring = {}
  for i, q in ipairs(shape) do
    local px, py = toMap(A.inst, q.x, q.y, mapID)
    if not px then return end
    ring[i] = { px * w, py * h }
  end
  -- While drawing, an open line of corners; otherwise the closed edge.
  local last = (self.drawing and #ring) or #ring
  for i = 1, last do
    local a, b = ring[i], ring[i % #ring + 1]
    if self.drawing and i == #ring then b = nil end
    if b then
      local n = math.max(1, math.floor(math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) / SPACING))
      for k = 0, n - 1 do
        local x, y = a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n
        if x >= 0 and x <= w and y >= 0 and y <= h then
          local t = dot(canvas)
          t:SetSize(4, 4)
          t:ClearAllPoints()
          t:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
          t:Show()
        end
      end
    end
  end
  if A.pts then
    for _, c in ipairs(ring) do
      local t = dot(canvas)
      t:SetSize(8, 8)
      t:ClearAllPoints()
      t:SetPoint("CENTER", canvas, "TOPLEFT", c[1], -c[2])
      t:Show()
    end
  end
end

local function openMap()
  local m = map()
  if not m then return false end
  if not m:IsShown() then
    if ToggleWorldMap then ToggleWorldMap() else m:Show() end
  end
  return true
end

-- The organiser draws the play area, corner by corner.
function HM:Draw()
  if not MOTA.Games:CanRun(MOTA.me) then return nil, "Only the Crown and the Minister of Games run Hide and Seek." end
  if not map() then return nil, "The world map isn't available." end
  self:Hook()
  local d = MOTA.Hide:Draft()
  d.pts, d.cx = nil, nil
  self.drawing = true
  openMap()
  MOTA:Print("Click the corners of the play area on a zone map, one by one, then press Finish on the Games Hall page.")
  MOTA:Fire("HIDE_CHANGED")
  return true
end

function HM:Finish()
  self.drawing = false
  local d = MOTA.Hide:Draft()
  MOTA:Fire("HIDE_CHANGED")
  if not d.pts or #d.pts < MOTA.Hide.MIN_PTS then
    return nil, "A play area needs at least " .. MOTA.Hide.MIN_PTS .. " corners."
  end
  return true
end

-- A click on the map while drawing.
function HM:Click(mapID, px, py)
  local inst, x, y = toWorld(mapID, px, py)
  if not inst then return nil, "That map has no place in the world: draw on a zone map." end
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  local n, err = MOTA.Hide:AddCorner(inst, x, y, info and info.name, mapID)
  if n then self:Paint() end
  return n, err
end

function HM:Hook()
  local m = map()
  if hooked or not m or not m.HookScript then return end
  hooked = true
  m:HookScript("OnShow", function() HM:Paint() end)
  m:HookScript("OnHide", function()
    if HM.drawing then MOTA:Print("Map closed: press Finish on the Games Hall page when the shape is done.") end
  end)
  if m.OnMapChanged then hooksecurefunc(m, "OnMapChanged", function() HM:Paint() end) end
  local scroll = m.ScrollContainer
  local target = scroll or (m.GetCanvas and m:GetCanvas())
  if target and target.HookScript then
    target:HookScript("OnMouseUp", function(_, button)
      if not HM.drawing or button ~= "LeftButton" then return end
      local px, py
      if scroll and scroll.GetNormalizedCursorPosition then px, py = scroll:GetNormalizedCursorPosition() end
      if px then
        local _, err = HM:Click(m:GetMapID(), px, py)
        if err then MOTA:Print(err) end
      end
    end)
  end
end

for _, s in ipairs({ "HIDE_CHANGED", "GUILD_READY" }) do
  MOTA:Listen(s, function() HM:Hook() HM:Paint() end)
end
