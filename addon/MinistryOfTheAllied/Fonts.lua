-- Ministry of the Allied: fonts.
-- The canvas fonts ship inside the add-on (SIL Open Font License, see
-- Media/Fonts/OFL-*.txt): Cinzel Decorative for titles, Cinzel for headings
-- and labels, EB Garamond for reading text. If the game can't load them, the
-- game's own font (Friz Quadrata) is used instead.

local _, MOTA = ...

local DIR = [[Interface\AddOns\MinistryOfTheAllied\Media\Fonts\]]
local FALLBACK = STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]]

local FILES = {
  cinzelSemi = "Cinzel-SemiBold.ttf",
  cinzel = "Cinzel-Bold.ttf",
  -- Ministry Decorative: Cinzel Decorative with its joined "h" pairs (as in "the") spaced
  -- normally, the double O kept (tools/fonts/make_ministry_decorative.py; renamed as the OFL asks)
  decoBold = "MinistryDecorative-Bold.ttf",
  decoBlack = "MinistryDecorative-Black.ttf",
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
  tabLabel = { "cinzel", 12 },              -- .tab (spaced out, see Tracked)
  tabSmall = { "garamondMedium", 12.5 },    -- .tab small
  tool = { "garamond", 13 },                -- small print in tool windows
  eyebrow = { "cinzel", 9.5 },              -- .herald .eyebrow (spaced out, see Tracked)
  heraldTitle = { "decoBold", 21 },         -- .herald h3
  heraldBody = { "garamond", 16 },          -- .herald p
  setLabel = { "cinzel", 12.5 },            -- .setrow label (spaced out)
  setSmall = { "garamond", 14 },            -- .setrow label small
  -- The canvas's sizes for page contents (UI/Kit.lua).
  kitSection = { "cinzel", 11 },            -- .h-sec at the boards' size
  kitTiny = { "cinzel", 9 },                -- small .eyebrow
  kitButton = { "cinzel", 11 },             -- .btn.sm
  kitRibbon = { "cinzel", 11 },             -- .ribbon
  kitStage = { "cinzel", 17 },              -- the event plate's stage
  kitCofferBig = { "cinzel", 30 },          -- the coffer's gold figure
  kitCofferSmall = { "cinzel", 18 },        -- its silver and copper
  kitName = { "cinzel", 14 },               -- .h-name at 14
  kitNameSmall = { "cinzel", 12 },          -- a full character name in a narrow place
  kitMotto = { "garamondItalic", 17 },      -- the party banner's motto
  kitNotice = { "garamond", 15 },           -- .notice .prose
  kitChamber = { "decoBold", 19 },          -- a chamber's title
  kitVersus = { "decoBold", 11.5 },         -- .next-bout .vs
  kitAwaiting = { "decoBold", 22 },         -- .h-page at 22
  kitLaurel = { "decoBold", 10.5 },         -- .laurel
  kitAmount = { "cinzel", 13 },             -- .amt
  kitSmall = { "garamond", 14 },            -- .small
  kitItalic = { "garamondItalic", 13.5 },   -- .small.muted.italic
  kitDuelist = { "garamond", 14.5 },        -- .duelist, .entry
  kitDuelistBold = { "garamondMedium", 14.5 },
  kitSmallest = { "garamond", 13 },
  kitLawTitle = { "decoBold", 25 },         -- .h-page at 25 (a statute's title)
  kitProse = { "garamond", 15.5 },          -- .prose on the Statute Book
  kitRoman = { "cinzel", 13 },              -- .roman
  constitutionPart = { "decoBold", 17 },    -- The Constitution page
  constitutionSection = { "cinzel", 12.5 },
  constitutionSmall = { "garamond", 12 },
  constitutionAction = { "cinzel", 11 },
  -- The Ballot Hall (BallotHall board)
  bEyebrow = { "cinzel", 10 },              -- .eyebrow at 10px, .fld-lab, .chip (spaced out)
  bRecHead = { "cinzel", 10.5 },            -- .rec-head (spaced out)
  bSec = { "cinzel", 13 },                  -- .h-sec (spaced out)
  bName = { "cinzel", 16 },                 -- .h-name on the ballot paper
  bName13 = { "cinzel", 13.5 },             -- .h-name in lists
  bNum = { "cinzel", 16 },                  -- .num
  bNum22 = { "cinzel", 22 },
  bTitle = { "decoBold", 24 },              -- .h-page on the papers
  bTitle21 = { "decoBold", 21 },
  bProse = { "garamond", 15.5 },            -- .prose and the form's inputs
  bRow = { "garamond", 14.5 },              -- .rec-row and .ticks
  bSmall = { "garamond", 14 },              -- .small
  bSmall13 = { "garamond", 13 },
  bHint = { "garamondMedium", 14 },         -- .small, font-weight 600
  bItalic = { "garamondItalic", 14 },       -- .small.italic
  bItalic13 = { "garamondItalic", 13.5 },
  bPortrait = { "decoBold", 13, true },     -- .portrait.sm initials
}

function MOTA:FontSize(name)
  return STYLES[name][2]
end

MOTA.fonts = {}
MOTA.fontsFailed = {} -- names of fonts that fell back to the game's font

function MOTA:Font(name)
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

-- A font by its file key (FILES) at any size, for text laid over the canvas
-- pictures (UI/LiveText.lua). Sizes are kept to half points so few are made.
local sized = {}
function MOTA:FontAt(key, size)
  size = math.max(4, math.floor(size * 2 + 0.5) / 2)
  local id = key .. "@" .. size
  if sized[id] then return sized[id] end
  local font = CreateFont(("MinistryOfTheAlliedFont_%s_%s"):format(key, (tostring(size):gsub("%.", "_"))))
  local ok = font:SetFont(DIR .. (FILES[key] or FILES.garamond), size, "")
  if ok == false or not font:GetFont() then font:SetFont(FALLBACK, size, "") end
  sized[id] = font
  return font
end

-- Letter-spaced text. The canvas spaces out its capital-letter labels
-- (CSS letter-spacing), which game text can't do, so each letter gets its own
-- font string. tracking is in em, like the canvas (.32em = 0.32).
-- Returns a frame: use SetText, SetColor and the usual SetPoint and SetAlpha.
function MOTA:Tracked(parent, font, hex, tracking)
  local box = CreateFrame("Frame", nil, parent)
  local size = self:FontSize(font)
  box:SetSize(1, size * 1.25)
  box.letters = {}
  box.color = hex

  function box:SetColor(c)
    self.color = c
    for _, fs in ipairs(self.letters) do fs:SetTextColor(MOTA:RGB(c)) end
  end

  function box:SetText(text)
    local x, n = 0, 0
    for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      n = n + 1
      local fs = self.letters[n]
      if not fs then
        fs = self:CreateFontString(nil, "OVERLAY")
        fs:SetFontObject(MOTA:Font(font))
        self.letters[n] = fs
      end
      fs:SetTextColor(MOTA:RGB(self.color))
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
      fs:SetText(ch)
      fs:Show()
      local w = ch == " " and size * 0.28 or fs:GetStringWidth()
      x = x + w + size * tracking
    end
    for i = n + 1, #self.letters do self.letters[i]:Hide() end
    self:SetWidth(math.max(1, x - size * tracking))
  end

  return box
end

-- "RRGGBB" to r, g, b in 0-1.
function MOTA:RGB(hex)
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
