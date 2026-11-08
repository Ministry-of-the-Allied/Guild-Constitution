-- Ministry of the Allied: the minimap seal (Extras board).
-- A wax seal on the minimap's edge. Click: open the Ministry. Right-click:
-- settings. Drag: move it around the minimap. /mota minimap hides or shows it.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media

local SEAL = 34 -- the seal's width on the minimap, in game units

local button

local function place()
  local angle = math.rad(MOTA.db.minimap.angle or 200)
  local radius = Minimap:GetWidth() / 2 + 6
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
end

local function followCursor()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  MOTA.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
  place()
end

local function build()
  button = CreateFrame("Button", "MinistryOfTheAlliedMinimapButton", Minimap)
  button:SetSize(SEAL, SEAL)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("AnyUp")
  button:RegisterForDrag("LeftButton")

  -- The seal picture includes its shadow, so it's drawn a little larger than
  -- the button, centred on the seal itself.
  local p, s = M.pieces.seal, M.slots.seal
  local k = SEAL / s.w
  local cx = (s.x + s.w / 2 - p.x) * k -- the seal's centre inside the picture
  local cy = (s.y + s.h / 2 - p.y) * k
  local function draw(layer)
    local t = button:CreateTexture(nil, layer)
    t:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
    t:SetTexCoord(p.l, p.r, p.t, p.b)
    t:SetSize(p.w * k, p.h * k)
    t:SetPoint("TOPLEFT", button, "CENTER", -cx, cy)
    return t
  end
  draw("ARTWORK")
  local glow = draw("HIGHLIGHT")
  glow:SetBlendMode("ADD")
  glow:SetAlpha(0.3)

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then UI:OpenSettings() else UI:Toggle() end
  end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", followCursor)
    MOTA.OnlineTip:Hide()
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", function(self)
    MOTA.OnlineTip:Show(self)
  end)
  button:SetScript("OnLeave", function() MOTA.OnlineTip:Hide() end)
  place()
end

function UI:ShowMinimapSeal(show)
  MOTA.db.minimap.hide = not show
  if show and not button then build() end
  if button then button:SetShown(show) end
end

MOTA:On("PLAYER_LOGIN", function(self)
  if Minimap and not self.db.minimap.hide then UI:ShowMinimapSeal(true) end
end)
