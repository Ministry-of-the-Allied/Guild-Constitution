-- Ministry of the Allied: the treasure hunt's glow (Duncan, 2026-11-09).
-- A gold glow round the edge of the screen, from the game's own low-health
-- vignette with its colour taken out and gold put in, so nobody takes it for
-- dying. It begins, faint, 50 yards from the spot you're hunting and grows as
-- you close in; walking away, it fades, smoothly and steady (no pulse: a
-- flashing screen edge was too much, and a risk for some). It goes out in combat, where it could hide real danger, and anyone
-- can turn it off (/mota hunt glow), keeping the chat lines every 10 yards.

local _, MOTA = ...
local Glow = {}
MOTA.HuntGlow = Glow

local TEXTURE = "Interface\\FullScreenTextures\\LowHealth"
local GOLD = { 1.0, 0.82, 0.32 }
local FADE = 1.6           -- how fast it follows: the share of the gap closed each second

local frame, tex
Glow.target, Glow.now = 0, 0

function Glow:Enabled()
  return MOTA.db == nil or MOTA.db.settings.huntGlow ~= false
end

function Glow:SetEnabled(on)
  MOTA.db.settings.huntGlow = on and true or false
  if not on then self:Set(0) end
end

local function build()
  frame = CreateFrame("Frame", "MinistryOfTheAlliedHuntGlow", UIParent)
  frame:SetAllPoints(UIParent)
  frame:SetFrameStrata("BACKGROUND")
  frame:EnableMouse(false)
  tex = frame:CreateTexture(nil, "BACKGROUND")
  tex:SetTexture(TEXTURE)
  tex:SetAllPoints()
  tex:SetBlendMode("ADD")
  if tex.SetDesaturated then tex:SetDesaturated(true) end
  tex:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
  tex:SetAlpha(0)
  frame:Hide()
  frame:SetScript("OnUpdate", function(_, elapsed)
    Glow:Step(elapsed)
  end)
end

-- How strong the glow should be, 0 (none) to 1 (on the spot).
function Glow:Set(strength)
  strength = math.max(0, math.min(1, strength or 0))
  if not self:Enabled() then strength = 0 end
  self.target = strength
  if strength > 0 then
    if not frame then build() end
    frame:Show()
  end
end

-- Each frame: follow the target smoothly.
function Glow:Step(elapsed)
  local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
  local goal = inCombat and 0 or self.target
  self.now = self.now + (goal - self.now) * math.min(1, elapsed * FADE)
  local alpha = self.now
  if tex then tex:SetAlpha(alpha) end
  if goal == 0 and self.now < 0.01 then
    self.now = 0
    if tex then tex:SetAlpha(0) end
    if frame then frame:Hide() end
  end
  return alpha
end
