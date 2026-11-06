-- Ministry of the Allied: fonts.
-- The canvas fonts ship inside the add-on (SIL Open Font License, see
-- Media/Fonts/OFL-*.txt): Cinzel Decorative for titles, Cinzel for headings
-- and labels, EB Garamond for reading text. If the game can't load them, the
-- game's own font (Friz Quadrata) is used instead.

local _, MotA = ...

local DIR = [[Interface\AddOns\MinistryOfTheAllied\Media\Fonts\]]
local FALLBACK = STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]]

local FILES = {
  cinzelSemi = "Cinzel-SemiBold.ttf",
  cinzel = "Cinzel-Bold.ttf",
  decoBold = "CinzelDecorative-Bold.ttf",
  decoBlack = "CinzelDecorative-Black.ttf",
  garamond = "EBGaramond-Regular.ttf",
  garamondMedium = "EBGaramond-Medium.ttf",
  garamondItalic = "EBGaramond-Italic.ttf",
}

-- name = { file, size, shadow? }  Sizes are the canvas's, in window units.
local STYLES = {
  heading = { "decoBold", 30 },             -- .h-page
  body = { "garamond", 16 },                -- .prose
  bodyItalic = { "garamondItalic", 14 },    -- .prose.italic.small
  who = { "cinzel", 12.5, true },           -- .rail-foot .who
  whoSmall = { "garamondMedium", 12.5, true },
  initials = { "decoBold", 13, true },      -- .portrait.sm
  foot = { "cinzelSemi", 10.5, true },      -- .win-foot
  tool = { "garamond", 13 },                -- small print in tool windows
}

MotA.fonts = {}
MotA.fontsFailed = {} -- names of fonts that fell back to the game's font

function MotA:Font(name)
  if self.fonts[name] then return self.fonts[name] end
  local style = STYLES[name]
  local font = CreateFont("MinistryOfTheAlliedFont_" .. name)
  -- SetFont reports failure on newer clients; GetFont catches it on older ones.
  local ok = font:SetFont(DIR .. FILES[style[1]], style[2], "")
  if ok == false or not font:GetFont() then
    font:SetFont(FALLBACK, style[2], "")
    self.fontsFailed[#self.fontsFailed + 1] = name
  end
  if style[3] then
    font:SetShadowColor(0, 0, 0, 0.75)
    font:SetShadowOffset(0, -1)
  end
  self.fonts[name] = font
  return font
end

-- "RRGGBB" to r, g, b in 0-1.
function MotA:RGB(hex)
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
