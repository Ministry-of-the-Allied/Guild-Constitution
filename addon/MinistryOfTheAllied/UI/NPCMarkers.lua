-- Ministry of the Allied: party quest markers over NPCs, the drawing side
-- (ADDON_SPEC.md, section 10.18; the facts are in NPCMarkers.lua).
--
-- Near: when a marked NPC's nameplate shows, a quest marker stands over it, drawn
-- like the game's own (a tall tapered "!" with a dot, or a "?" for a hand-in) but
-- in the party's colours. Far: a compass arrow round the middle of the screen,
-- pips along a compass strip at the top, or both (Settings), pointing at marked
-- NPCs on the same continent. UI/NPCPlates.lua turns the game's friendly NPC
-- nameplates on near a marked NPC, names only, and off again after.
--
-- To keep Blizzard's code clean ("taint"), nothing of the game's is replaced:
-- the marker is our own frame, anchored TO the nameplate (allowed in combat; the
-- nameplate is never shown, hidden or moved by us), and every call into the
-- game's nameplate or position API is protected. The marker (and the name, in
-- UI/NPCPlates.lua) hangs on WorldFrame, as the game's nameplates do, so every
-- window of the interface covers it (Max, 12 Nov: on UIParent it showed over the
-- character sheet and the map). The far arrows and strip stay on UIParent, low.

local _, MOTA = ...
local Markers = MOTA.Markers
local UI = {}
Markers.UI = UI

local TEXTURE = MOTA.Media.dir .. "marker.tga"

local DEFAULT_SIZE, DEFAULT_LIFT = 44, 18 -- the marker's height, and how far above the nameplate it stands
local NAME_GAP = 2         -- over a name-only nameplate (UI/NPCPlates.lua): the gap above the name (lift moves it too)
local MAX_FAR = 3          -- how many far NPCs get an arrow or a pip (the nearest)
local ARRIVED = 10         -- yards: this near, the arrow has done its work
local TICK = 0.1           -- seconds between placing the far arrows
local STRIP_W = 360        -- the compass strip's width (its two ends are 90 degrees left and right)

---------------------------------------------------------------------------
-- The looks: which cells of Media/marker.tga (tools/textures/marker.py)
---------------------------------------------------------------------------

-- The sheet is 512 x 256: the "!" in the four looks, then the "?" (64 x 128 each)
-- along the top row; the arrows (128 x 128) along the bottom.
local COLUMN = { UNREGISTERED = 0, SILVERHAND = 1, AZEROTH_EXCHANGE = 2, CROWN = 3 }

-- l, r, t, b of a cell: kind "bang", "query" or "arrow", in the look of a skin key.
function UI:Cell(kind, key)
  local c = COLUMN[key] or COLUMN.CROWN
  if kind == "arrow" then return c * 0.25, (c + 1) * 0.25, 0.5, 1 end
  local x = (kind == "query" and 4 or 0) + c
  return x / 8, (x + 1) / 8, 0, 0.5
end

-- Which of the four looks a marker wears: a test look's, or its party's. A quest
-- for everyone is just a regular quest the Crown gives, so it wears the Crown's
-- dark purple on every screen (Max, 12 Nov).
function UI:SkinOf(m)
  if m.skin then return m.skin end
  if m.p == "sh" then return "SILVERHAND" end
  if m.p == "ex" then return "AZEROTH_EXCHANGE" end
  return "CROWN"
end

-- key, ink: the marker's look, and the light colour for words beside it (the skin's
-- pale accent: the Ministry's and Silverhand's pale blue, the Exchange's and the Crown's own).
function UI:Look(m)
  local key = self:SkinOf(m)
  local acc = (MOTA.Skin and MOTA.Skin.accents) or {}
  local hex = (key == "CROWN" and acc.cr or key == "AZEROTH_EXCHANGE" and acc.ex or acc.sh or {}).PALE or "FFFFFF"
  local r, g, b = MOTA:RGB(hex)
  return key, { r = r, g = g, b = b }
end

---------------------------------------------------------------------------
-- The marker
---------------------------------------------------------------------------

-- Our frames that hang on WorldFrame (with the nameplates, under the interface).
local function world() return WorldFrame or UIParent end

-- WorldFrame doesn't follow the interface's scale: this makes a frame on it the size
-- it would be on UIParent.
function UI.WorldScale()
  local ok, ui = pcall(function() return UIParent:GetEffectiveScale() end)
  local ok2, wf = pcall(function() return world():GetEffectiveScale() end)
  if ok and ok2 and type(ui) == "number" and type(wf) == "number" and wf > 0 then return ui / wf end
  return 1
end

local function newMark(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetFrameStrata("LOW")
  f:EnableMouse(false)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetAllPoints()
  f.tex:SetTexture(TEXTURE)
  return f
end

-- Dresses a marker frame for m at a height (its width is half: the cells are 1:2).
local function paintMark(f, m, h)
  local key = UI:SkinOf(m)
  f.tex:SetTexCoord(UI:Cell(m.q == "in" and "query" or "bang", key))
  f:SetSize(h / 2, h)
  f.m, f.key = m, key
end

-- The marker's size and height settings, each with the range it really has (Max, 12 Nov:
-- the commands took numbers that did nothing past the ends). One table, read by the
-- commands (/mota marker size, lift, namesize, scale, namey), the Admin Controls and the
-- drawing, so what a command accepts is what the screen shows.
--   key: the saved setting · min, max: the range · default · step: the smallest change
--   what: what it is, in a few words
UI.SIZES = {
  size = { key = "markerSize", min = 24, max = 96, default = DEFAULT_SIZE, step = 1, what = "the marker's height" },
  lift = { key = "markerLift", min = -20, max = 80, default = DEFAULT_LIFT, step = 1,
           what = "how far the marker stands above the nameplate or the name" },
  namesize = { key = "markerNameSize", min = 8, max = 32, default = 16, step = 1, what = "the names' text size" },
  scale = { key = "markerScale", min = 0.5, max = 2.5, default = 1, step = 0.05, what = "the markers and names, bigger or smaller together" },
  namey = { key = "markerNameY", min = -40, max = 80, default = 0, step = 1, what = "how high the names stand on the nameplate" },
}

-- A setting's value: the saved one, rounded to its step and held in its range, or its default.
function UI.Setting(name)
  local s = UI.SIZES[name]
  local v = MOTA.db and tonumber(MOTA.db.settings[s.key])
  if not v then return s.default end
  v = math.floor(v / s.step + 0.5) * s.step
  return math.max(s.min, math.min(s.max, v))
end

-- "24 to 96" (for the commands and the Admin Controls).
function UI.RangeText(name)
  local s = UI.SIZES[name]
  local function n(v) return (v == math.floor(v)) and tostring(v) or ("%.2f"):format(v):gsub("0$", "") end
  return n(s.min) .. " to " .. n(s.max)
end

function UI:Size()
  return UI.Setting("size")
end

-- One scale for the markers and the names on the nameplates together (/mota marker
-- scale), so they stay in step with each other (Max, 12 Nov). 1 as drawn.
function UI.UserScale()
  return UI.Setting("scale")
end

function UI:Lift()
  return UI.Setting("lift")
end

---------------------------------------------------------------------------
-- Over a nameplate
---------------------------------------------------------------------------

UI.plates = {} -- unit token -> { seal, npc }: the markers standing now
local pool = {}

local function plateFor(unit)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
  local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
  return ok and plate or nil
end

-- Takes the marker off a nameplate (the name-only dress is UI/NPCPlates.lua's).
function UI:Unplate(unit)
  local p = self.plates[unit]
  if not p then return end
  p.seal:Hide()
  p.seal:ClearAllPoints()
  pool[#pool + 1] = p.seal
  self.plates[unit] = nil
end

-- A nameplate came up, or its unit changed: dress it name-only if we turned the
-- nameplates on (UI/NPCPlates.lua), and stand a marker over it if its NPC is marked.
UI.npcOf = {} -- unit token -> creature ID, for the plates up now (to spot an NPC with copies)

function UI:Plate(unit)
  if type(unit) ~= "string" then return end
  local ok, guid = pcall(UnitGUID, unit)
  local npc = ok and Markers:NpcId(guid) or nil
  self.npcOf[unit] = npc
  if npc and not Markers:Many(npc) and Markers:For(npc) then -- (only marked NPCs: the saved list stays short)
    for u, other in pairs(self.npcOf) do
      if u ~= unit and other == npc then
        -- two copies of this NPC at once: from now only the marked copy carries the mark
        Markers:SeenMany(npc)
        return self:Rescan()
      end
    end
  end
  local m = npc and Markers:Showing() and Markers:ForUnit(npc, guid) or nil
  local plate = plateFor(unit)
  local name = plate and self.Names and self.Names:Style(unit, m, plate)
  if not (m and plate) then return self:Unplate(unit) end
  local p = self.plates[unit]
  if not p then
    p = { seal = table.remove(pool) or newMark(world()) }
    self.plates[unit] = p
  end
  p.npc = npc
  paintMark(p.seal, m, self:Size())
  p.seal:ClearAllPoints()
  if name then
    p.seal:SetPoint("BOTTOM", name, "TOP", 0, NAME_GAP + self:Lift() - DEFAULT_LIFT)
    -- (it shrinks with its name over distance: UI/NPCPlates.lua)
    if self.Names.Follow then self.Names.Follow(self.Names.styled[unit].label, 0) end
  else
    p.seal:SetScale(UI.WorldScale() * UI.UserScale())
    p.seal:SetPoint("BOTTOM", plate, "TOP", 0, self:Lift())
  end
  p.seal:Show()
end

local function unitOf(plate)
  local ok, unit = pcall(function() return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit) end)
  return ok and type(unit) == "string" and unit or nil
end

-- Look at every nameplate again (the marks changed, or a setting did).
function UI:Rescan()
  local seen = {}
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      for _, plate in ipairs(plates) do
        local unit = unitOf(plate)
        if unit then
          seen[unit] = true
          self:Plate(unit)
        end
      end
    end
  end
  for unit in pairs(self.plates) do
    if not seen[unit] then self:Unplate(unit) end
  end
  for unit in pairs(self.npcOf) do
    if not seen[unit] then self.npcOf[unit] = nil end
  end
  if self.Names then self.Names:Forget(seen) end
  self:PaintFar()
end

MOTA:On("NAME_PLATE_UNIT_ADDED", function(_, _, unit)
  UI:Plate(unit)
  UI:PaintFar()
end)
MOTA:On("NAME_PLATE_UNIT_REMOVED", function(_, _, unit)
  UI.npcOf[unit] = nil
  UI:Unplate(unit)
  if UI.Names then UI.Names:Unstyle(unit) end
  UI:PaintFar()
end)
MOTA:Listen("MARKERS_CHANGED", function() UI:Rescan() end)
MOTA:Listen("SKIN_CHANGED", function() UI:Rescan() end)

---------------------------------------------------------------------------
-- Far away: where the NPC lies from here
---------------------------------------------------------------------------

-- Where I am in the game's world: first, second (as UnitPosition gives them) and the
-- continent. nil where the game won't say (an instance, or a client without it).
function UI.MyWorld()
  if not UnitPosition then return nil end
  local ok, a, b, _, instance = pcall(UnitPosition, "player")
  if not ok or (issecretvalue and (issecretvalue(a) or issecretvalue(b))) or type(a) ~= "number" or type(b) ~= "number" then
    return nil
  end
  return a, b, instance
end

-- Where a marked NPC stands in the game's world, kept on the marker (it never moves).
function UI.WorldOf(m)
  if m.wmap == m.map and m.wx == m.x and m.wy == m.y then return m.wa, m.wb, m.winstance end
  if not (m.map and m.x and m.y and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, instance, pos = pcall(C_Map.GetWorldPosFromMapPos, m.map, CreateVector2D(m.x, m.y))
  if not ok or not pos then return nil end
  local ok2, a, b = pcall(pos.GetXY, pos)
  if not ok2 or type(a) ~= "number" or type(b) ~= "number" then return nil end
  m.wmap, m.wx, m.wy, m.wa, m.wb, m.winstance = m.map, m.x, m.y, a, b, instance
  return a, b, instance
end

-- The turn from where I face to where they lie, in radians (0 straight ahead, positive
-- to the right, -pi to pi), and the distance in yards. As on the minimap, in the game's
-- world the first coordinate grows to the north and the second to the west, and
-- facing is turned counter-clockwise from north.
function UI.Bearing(ma, mb, ta, tb, facing)
  local east, north = mb - tb, ta - ma
  local sin, cos = math.sin(facing), math.cos(facing)
  local right, ahead = east * cos + north * sin, north * cos - east * sin
  return math.atan2(right, ahead), math.sqrt(east * east + north * north)
end

-- The near-to-far list of marked NPCs to point at: { m, angle, yards }.
function UI:FarList()
  local out = {}
  if not Markers:Showing() or Markers:Far() == "off" then return out end
  local list = Markers:List()
  if #list == 0 then return out end
  local ma, mb, instance = UI.MyWorld()
  if not ma then return out end
  local facing = GetPlayerFacing and GetPlayerFacing()
  if (issecretvalue and issecretvalue(facing)) or type(facing) ~= "number" then return out end
  local standing = {}
  for _, p in pairs(self.plates) do standing[p.npc] = true end
  for _, m in ipairs(list) do
    if not standing[m.npc] then -- its marker is over its head: no arrow for it
      local ta, tb, ti = UI.WorldOf(m)
      if ta and ti == instance then
        local angle, yards = self.Bearing(ma, mb, ta, tb, facing)
        if yards > ARRIVED then out[#out + 1] = { m = m, angle = angle, yards = yards } end
      end
    end
  end
  table.sort(out, function(a, b) return a.yards < b.yards end)
  for i = #out, MAX_FAR + 1, -1 do out[i] = nil end
  return out
end

local function yards(n)
  if n >= 1000 then return ("%.1f km"):format(n / 1000) end
  return ("%d yd"):format(math.floor(n + 0.5))
end
UI.Yards = yards

local function label(parent, font)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(MOTA:Font(font or "tipHint"))
  fs:SetJustifyH("CENTER")
  fs:SetWordWrap(false)
  return fs
end

local function shortName(m)
  return m.name or ("NPC " .. m.npc)
end

-- The arrows: one per far NPC, round the middle of the screen on an ellipse.
UI.arrows = {}
local function arrow(i)
  if not UI.arrows[i] then
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(36, 36)
    f:SetFrameStrata("LOW")
    f:EnableMouse(false)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexture(TEXTURE)
    f.text = label(f)
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.text:SetWidth(180)
    f:Hide()
    UI.arrows[i] = f
  end
  return UI.arrows[i]
end

-- The compass strip along the top: a small marker per far NPC.
UI.pips = {}
local function pip(i)
  if not UI.pips[i] then
    UI.pips[i] = newMark(UI.strip)
  end
  return UI.pips[i]
end

local function buildStrip()
  local f = CreateFrame("Frame", "MinistryOfTheAlliedMarkerStrip", UIParent)
  f:SetSize(STRIP_W + 40, 26)
  f:SetPoint("TOP", UIParent, "TOP", 0, -96)
  f:SetFrameStrata("LOW")
  f:EnableMouse(false)
  f.back = f:CreateTexture(nil, "BACKGROUND")
  f.back:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.back:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  f.back:SetHeight(4)
  f.back:SetColorTexture(0, 0, 0, 0.45)
  f.ticks = {}
  for i, frac in ipairs({ -1, -0.5, 0, 0.5, 1 }) do
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetSize(1, frac == 0 and 12 or 7)
    t:SetPoint("CENTER", f, "CENTER", frac * STRIP_W / 2, 0)
    t:SetColorTexture(0.95, 0.85, 0.54, frac == 0 and 0.9 or 0.55)
    f.ticks[i] = t
  end
  f.text = label(f)
  f.text:SetPoint("TOP", f, "BOTTOM", 0, -4)
  f.text:SetWidth(260)
  f:Hide()
  UI.strip = f
end

local function hideArrows()
  for _, f in pairs(UI.arrows) do f:Hide() end
end

local function hideStrip()
  if not UI.strip then return end
  UI.strip:Hide()
  for _, p in pairs(UI.pips) do p:Hide() end
end

function UI:HideFar()
  hideArrows()
  hideStrip()
end

local function paintStrip(list)
  if not UI.strip then buildStrip() end
  UI.strip:Show()
  local half = STRIP_W / 2
  for i = 1, MAX_FAR do
    local e = list[i]
    local p = pip(i)
    if e then
      local frac = math.max(-1, math.min(1, e.angle / (math.pi / 2)))
      paintMark(p, e.m, 22)
      p:ClearAllPoints()
      p:SetPoint("CENTER", UI.strip, "CENTER", frac * half, 0)
      p:SetAlpha(math.abs(e.angle) > math.pi / 2 and 0.55 or 1)
      p:Show()
    else
      p:Hide()
    end
  end
  local near = list[1]
  local _, ink = UI:Look(near.m)
  UI.strip.text:SetText(shortName(near.m) .. "  ·  " .. yards(near.yards))
  UI.strip.text:SetTextColor(ink.r, ink.g, ink.b)
end

local function paintArrows(list)
  local w, h = UIParent:GetWidth() or 1024, UIParent:GetHeight() or 768
  local rx, ry = math.min(w * 0.22, 300), math.min(h * 0.24, 200)
  for i = 1, MAX_FAR do
    local e = list[i]
    local f = arrow(i)
    if e then
      local key, ink = UI:Look(e.m)
      f.tex:SetTexCoord(UI:Cell("arrow", key))
      if f.tex.SetRotation then f.tex:SetRotation(-e.angle) end
      f:ClearAllPoints()
      f:SetPoint("CENTER", UIParent, "CENTER", math.sin(e.angle) * rx, 40 + math.cos(e.angle) * ry)
      f.text:SetText(shortName(e.m) .. "  ·  " .. yards(e.yards))
      f.text:SetTextColor(ink.r, ink.g, ink.b)
      f.m, f.angle, f.key = e.m, e.angle, key
      f:Show()
    else
      f:Hide()
    end
  end
end

-- Places the arrows, the strip, or both, for this setting. Run every 0.1 s and when a nameplate comes or goes.
function UI:PaintFar()
  local list = self:FarList()
  local mode = Markers:Far()
  if #list == 0 then return self:HideFar() end
  if mode == "strip" or mode == "both" then paintStrip(list) else hideStrip() end
  if mode == "arrow" or mode == "both" then paintArrows(list) else hideArrows() end
end

MOTA:On("PLAYER_LOGIN", function()
  C_Timer.NewTicker(TICK, function() UI:PaintFar() end)
end)
MOTA:On("PLAYER_ENTERING_WORLD", function()
  C_Timer.After(1, function() UI:Rescan() end)
end)
