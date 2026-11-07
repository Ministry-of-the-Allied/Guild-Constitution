-- Ministry of the Allied: the canvas's parts for page contents, drawn live
-- (design/canvas-source/ministry.css): plates, ribbons, buttons, gems and labels.
-- Colours and gradients are the stylesheet's own. Pages use these rather than
-- plain boxes, so every page matches the design guide.

local _, MOTA = ...
local Kit = {}
MOTA.Kit = Kit

-- The accent (UI/Skin.lua): pages never say "blue", they say "ink" or draw a
-- blue part, and Kit gives it the colour of the skin, or of a party whose page
-- it is (Kit:With). Whatever is drawn this way is remembered here, so a new
-- skin recolours it at once.
local BLUE_INK, BLUE_PALE = "1B3570", "C9D6F5"
local tracked = {}
local function track(fn)
  tracked[#tracked + 1] = fn
  fn()
end
MOTA:Listen("SKIN_CHANGED", function()
  for _, fn in ipairs(tracked) do fn() end
end)

Kit.Track = function(_, fn) track(fn) end

-- Builds a page's parts in a party's accent ("sh", "ex" or "cr"), whatever skin is worn.
function Kit:With(key, build)
  local before = self.force
  self.force = key
  local result = build()
  self.force = before
  return result
end

local function rgba(hex, alpha)
  local r, g, b = MOTA:RGB(hex)
  return r, g, b, alpha or 1
end

function Kit:Solid(texture, hex, alpha)
  texture:SetColorTexture(rgba(hex, alpha))
end

-- A gradient, or the first colour if this client's SetGradient differs.
function Kit:Gradient(texture, top, bottom, topAlpha, bottomAlpha, horizontal)
  texture:SetColorTexture(1, 1, 1, 1)
  local ok = CreateColor and pcall(texture.SetGradient, texture, horizontal and "HORIZONTAL" or "VERTICAL",
    CreateColor(rgba(bottom, bottomAlpha)), CreateColor(rgba(top, topAlpha)))
  if not ok then self:Solid(texture, top, topAlpha) end
end

function Kit:Fill(frame, top, bottom, topAlpha, bottomAlpha)
  local t = frame:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints()
  self:Gradient(t, top, bottom or top, topAlpha, bottomAlpha or topAlpha)
  return t
end

-- An inset line around a frame (box-shadow: inset 0 0 0 Npx).
function Kit:Outline(frame, hex, alpha, inset, thickness)
  inset, thickness = inset or 0, thickness or 1
  local sides = {}
  local function side(a, b, x1, y1, x2, y2)
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetColorTexture(rgba(hex, alpha))
    t:SetPoint(a, frame, a, x1, y1)
    t:SetPoint(b, frame, b, x2, y2)
    sides[#sides + 1] = t
    return t
  end
  side("TOPLEFT", "TOPRIGHT", inset, -inset, -inset, -inset):SetHeight(thickness)
  side("BOTTOMLEFT", "BOTTOMRIGHT", inset, inset, -inset, inset):SetHeight(thickness)
  side("TOPLEFT", "BOTTOMLEFT", inset, -inset, inset, inset):SetWidth(thickness)
  side("TOPRIGHT", "BOTTOMRIGHT", -inset, -inset, -inset, inset):SetWidth(thickness)
  return sides
end

local function recolor(sides, hex, alpha)
  for _, t in ipairs(sides) do t:SetColorTexture(rgba(hex, alpha)) end
end

-- .plate, .plate.sunk and .plate.blue (the blue one is the accent's)
function Kit:Plate(frame, kind)
  if kind == "sunk" then
    self:Fill(frame, "6E4F17", "6E4F17", 0.07)
    self:Outline(frame, "6E4F17", 0.45)
  elseif kind == "blue" then
    local fill = self:Fill(frame, "24478F", "152D63")
    self:Outline(frame, "F3D98A", 1, 0, 1)
    local edge = self:Outline(frame, "142B5E", 1, 1, 2)
    self:Outline(frame, "C9A24A", 0.55, 3, 1)
    local key = self.force
    track(function()
      local a = MOTA:Accent(key)
      self:Gradient(fill, a.PLATE_TOP, a.PLATE_BOT)
      recolor(edge, a.DARK, 1)
    end)
  else
    self:Fill(frame, "FFF9E6", "D9C49A", 0.55, 0.28)
    self:Outline(frame, "6E4F17", 0.55, 0, 1)
    self:Outline(frame, "F4EAD0", 0.55, 1, 3)
    self:Outline(frame, "6E4F17", 0.3, 4, 1)
  end
  return frame
end

function Kit:Text(parent, font, hex, justify)
  local t = parent:CreateFontString(nil, "OVERLAY")
  t:SetFontObject(MOTA:Font(font))
  t:SetTextColor(MOTA:RGB(hex or "2A1F14"))
  if hex == BLUE_INK then -- the accent's ink
    local key = self.force
    track(function() t:SetTextColor(MOTA:RGB(MOTA:Accent(key).INK)) end)
  end
  t:SetJustifyH(justify or "LEFT")
  t:SetJustifyV("TOP")
  return t
end

-- A spaced-out capital label, as .eyebrow and .h-sec are.
function Kit:Label(parent, font, hex, tracking, text)
  local box = MOTA:Tracked(parent, font, hex or "7A5719", tracking or 0.22)
  if hex == BLUE_INK or hex == BLUE_PALE then -- the accent's ink, or its light text on a plate
    local key, field = self.force, hex == BLUE_INK and "INK" or "PALE"
    track(function() box:SetColor(MOTA:Accent(key)[field]) end)
  end
  local plain = box.SetText
  function box:SetText(s) plain(self, tostring(s or ""):upper()) end
  if text then box:SetText(text) end
  return box
end

-- .rule: a thin line that fades at both ends.
function Kit:Rule(parent, width)
  local half = width / 2
  local left = parent:CreateTexture(nil, "ARTWORK")
  left:SetSize(half, 1)
  self:Gradient(left, "7A5719", "7A5719", 0, 1, true)
  local right = parent:CreateTexture(nil, "ARTWORK")
  right:SetSize(half, 1)
  right:SetPoint("LEFT", left, "RIGHT", 0, 0)
  self:Gradient(right, "7A5719", "7A5719", 1, 0, true)
  return left
end

-- A part drawn from the canvas (tools/textures/extras.html), at its own size.
local function art(parent, name, layer)
  local M = MOTA.Media
  local p = M.pieces[name]
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
  t:SetTexCoord(p.l, p.r, p.t, p.b)
  t:SetSize(p.w, p.h)
  return t, p
end
Kit.Art = function(_, parent, name, layer) return art(parent, name, layer) end

-- Shows another part in the same texture.
function Kit:Look(texture, name)
  local M = MOTA.Media
  local p = M.pieces[name]
  texture:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
  texture:SetTexCoord(p.l, p.r, p.t, p.b)
  texture:SetSize(p.w, p.h)
end

-- .gem: a small diamond, tinted. Hollow marks an empty place.
function Kit:Gem(parent, hex)
  local g = art(parent, "kitGem")
  self:Tint(g, hex)
  return g
end

function Kit:Tint(gem, hex, hollow, alpha)
  self:Look(gem, hollow and "kitGemHollow" or "kitGem")
  gem:SetVertexColor(MOTA:RGB(hex or "5E4B33"))
  gem:SetAlpha(alpha or 1)
end

-- .amt: gold and silver with their coins, right-aligned.
function Kit:Amount(parent, font, hex)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(110, 16)
  local g, s = Kit:Text(f, font, hex or "1B3570"), Kit:Text(f, font, hex or "1B3570")
  local coinG, coinS = art(f, "kitCoinG"), art(f, "kitCoinS")
  function f:SetGold(amount)
    local gold = math.floor(amount)
    local silver = math.floor((amount - gold) * 100 + 0.5)
    local showS, showG = silver > 0, gold > 0 or silver == 0
    s:SetShown(showS) coinS:SetShown(showS) g:SetShown(showG) coinG:SetShown(showG)
    s:SetText(silver) g:SetText(gold)
    local anchor, point, gap = f, "RIGHT", 0
    if showS then
      coinS:ClearAllPoints() coinS:SetPoint("RIGHT", anchor, point, gap, 0)
      s:ClearAllPoints() s:SetPoint("RIGHT", coinS, "LEFT", -2, 0)
      anchor, point, gap = s, "LEFT", -5
    end
    if showG then
      coinG:ClearAllPoints() coinG:SetPoint("RIGHT", anchor, point, gap, 0)
      g:ClearAllPoints() g:SetPoint("RIGHT", coinG, "LEFT", -2, 0)
    end
  end
  return f
end

local BUTTONS = {
  blue = { top = "3460B4", bottom = "12285A", text = "F3D98A", ring = "D2AE5C" },
  gold = { top = "FFF3C4", bottom = "C9A24A", text = "0E1F45", ring = "4A330C" },
  quiet = { top = "FFFAEB", bottom = "FFFAEB", alpha = 0.35, text = "1B3570", ring = "1B3570" },
}

-- .btn, .btn.gold and .btn.quiet
function Kit:Button(parent, width, height, label, style, onClick)
  local look = BUTTONS[style or "blue"]
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, height)
  local bg = self:Fill(b, look.top, look.bottom, look.alpha)
  local ring = self:Outline(b, look.ring, 0.8)
  local glow = b:CreateTexture(nil, "HIGHLIGHT")
  glow:SetColorTexture(1, 0.95, 0.7, 0.18)
  glow:SetAllPoints()
  b.label = self:Label(b, "kitButton", look.text, 0.14)
  local key = self.force
  track(function()
    local a = MOTA:Accent(key)
    if (style or "blue") == "blue" then
      self:Gradient(bg, a.TOP, a.BOT)
    elseif style == "gold" then
      b.label:SetColor(a.ON)
    else
      recolor(ring, a.INK, 0.8)
    end
  end)
  function b:SetLabel(text)
    self.label:SetText(text)
    self.label:ClearAllPoints()
    self.label:SetPoint("CENTER", self, "CENTER", 0, 0)
  end
  b:SetLabel(label)
  b:SetScript("OnClick", onClick)
  return b
end

-- The name of a blue part's drawn copy for the accent in force (or the part itself).
function Kit:AccentName(name, key)
  local drawn = name .. MOTA:Accent(key or self.force).SUFFIX
  return MOTA.Media.pieces[drawn] and drawn or name
end

-- A blue part of the canvas, drawn again in the Crown's and the Exchange's
-- colours (Media.lua: "<piece>~cr", "<piece>~ex"). Follows the accent.
function Kit:AccentArt(parent, name, layer)
  local t, p = art(parent, name, layer)
  local key = self.force
  track(function()
    local drawn = name .. MOTA:Accent(key).SUFFIX
    self:Look(t, MOTA.Media.pieces[drawn] and drawn or name)
  end)
  return t, p
end

-- .ribbon, with the board's cut ends: drawn from the canvas. n picks the label.
-- The lit one is a blue part, so it follows the accent.
function Kit:Ribbon(parent, n, onClick)
  local b = CreateFrame("Button", nil, parent)
  local rest = MOTA.Media.pieces["kitRibbonOff" .. n] and art(b, "kitRibbonOff" .. n, "BACKGROUND")
  local on, p = self:AccentArt(b, "kitRibbonOn" .. n, "BACKGROUND")
  b:SetSize(p.w, p.h)
  on:SetPoint("CENTER")
  if rest then rest:SetPoint("CENTER") end
  local glow
  if rest then
    glow = art(b, "kitRibbonOff" .. n, "HIGHLIGHT")
  else
    glow = self:AccentArt(b, "kitRibbonOn" .. n, "HIGHLIGHT")
  end
  glow:SetPoint("CENTER")
  glow:SetBlendMode("ADD")
  glow:SetAlpha(0.2)
  function b:SetOn(chosen)
    on:SetShown(chosen)
    if rest then rest:SetShown(not chosen) end
  end
  b:SetOn(false)
  b:SetScript("OnClick", onClick)
  return b
end
