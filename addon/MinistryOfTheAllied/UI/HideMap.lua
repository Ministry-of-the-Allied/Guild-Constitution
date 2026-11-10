-- Ministry of the Allied: Hide and Seek on the world map (Duncan, 2026-11-10).
-- The play area's edge is drawn on the game's world map as a ring of dots, for
-- everyone, while a game is open or being played (with "No map" on, players
-- see it on the Games Hall page instead, as the map stays shut for them).
-- The organiser can also pick the play area's middle by clicking the map.
--
-- World yards (UnitPosition: y first, then x) are turned into map places with
-- C_Map.GetMapPosFromWorldPos, and back with GetWorldPosFromMapPos. As
-- elsewhere, nothing of Blizzard's is replaced: the dots are our own textures
-- on the map's canvas, and we only listen after the fact.

local _, MOTA = ...
local HM = {}
MOTA.HideMap = HM

local DOTS = 64
local dots, hooked = {}, false
HM.picking = false

local function map() return _G.WorldMapFrame end

-- A world spot (inst, x, y) to the open map's 0-1 place, or nil.
local function toMap(inst, x, y, mapID)
  if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
  local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, inst, CreateVector2D(y, x), mapID)
  if ok and pos then
    local px, py = pos:GetXY()
    if px and px >= 0 and px <= 1 and py >= 0 and py <= 1 then return px, py end
  end
end

-- The open map's 0-1 place to a world spot: inst, x, y.
local function toWorld(mapID, px, py)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(px, py))
  if ok and inst and pos then
    local wy, wx = pos:GetXY()
    return inst, wx, wy
  end
end
HM.ToMap, HM.ToWorld = toMap, toWorld

-- The circle to draw: the game on now, or the organiser's draft.
local function circle()
  local Hi = MOTA.Hide
  local G = Hi:Current()
  if G and Hi:Live(G) then return G end
  local d = MOTA.db and MOTA.db.hideDraft
  if d and d.cx and MOTA.Games:CanRun(MOTA.me) then return { inst = d.inst, cx = d.cx, cy = d.cy, rad = d.rad } end
end

function HM:Paint()
  local m = map()
  if not m or not m.GetCanvas or not m:IsShown() then return end
  local canvas = m:GetCanvas()
  local c = circle()
  local mapID = m.GetMapID and m:GetMapID()
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  for i = 1, DOTS do
    local t = dots[i]
    if not t then
      t = canvas:CreateTexture(nil, "OVERLAY")
      t:SetSize(5, 5)
      t:SetColorTexture(MOTA:RGB("C9A24A"))
      dots[i] = t
    end
    local px, py
    if c and mapID then
      local ang = (i - 1) / DOTS * 2 * math.pi
      px, py = toMap(c.inst, c.cx + c.rad * math.cos(ang), c.cy + c.rad * math.sin(ang), mapID)
    end
    if px then
      t:ClearAllPoints()
      t:SetPoint("CENTER", canvas, "TOPLEFT", px * w, -py * h)
      t:Show()
    else
      t:Hide()
    end
  end
end

-- The organiser clicks the map to set the middle.
function HM:Pick()
  if not MOTA.Games:CanRun(MOTA.me) then return nil, "Only the Crown and the Minister of Games run Hide and Seek." end
  local m = map()
  if not m then return nil, "The world map isn't available." end
  self:Hook()
  self.picking = true
  if ToggleWorldMap and not m:IsShown() then ToggleWorldMap() elseif not m:IsShown() then m:Show() end
  MOTA:Print("Click the middle of the play area on the map.")
  return true
end

function HM:Picked(mapID, px, py)
  self.picking = false
  local inst, x, y = toWorld(mapID, px, py)
  if not inst then return nil, "That map has no place in the world; pick on a zone map." end
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  local ok, err = MOTA.Hide:SetCentre(inst, x, y, info and info.name or "Somewhere")
  if ok then MOTA:Print("Play area set, in", (info and info.name or "the world") .. ".") self:Paint() end
  return ok, err
end

function HM:Hook()
  local m = map()
  if hooked or not m or not m.HookScript then return end
  hooked = true
  m:HookScript("OnShow", function() HM:Paint() end)
  if m.OnMapChanged then hooksecurefunc(m, "OnMapChanged", function() HM:Paint() end) end
  local canvas = m.GetCanvas and m:GetCanvas()
  local scroll = m.ScrollContainer
  local target = scroll or canvas
  if target and target.HookScript then
    target:HookScript("OnMouseUp", function(_, button)
      if not HM.picking or button ~= "LeftButton" then return end
      local px, py
      if scroll and scroll.GetNormalizedCursorPosition then px, py = scroll:GetNormalizedCursorPosition() end
      if px then
        local _, err = HM:Picked(m:GetMapID(), px, py)
        if err then MOTA:Print(err) end
      end
    end)
  end
end

for _, s in ipairs({ "HIDE_CHANGED", "GUILD_READY" }) do
  MOTA:Listen(s, function() HM:Hook() HM:Paint() end)
end
