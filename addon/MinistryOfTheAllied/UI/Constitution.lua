-- Ministry of the Allied: the Constitution, on the Statute Book page (ADDON_SPEC.md, section 12.6).
-- The Charter to read on the left, the narration to replay on the right.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Page = {}
MOTA.ConstitutionPage = Page

local PAGE_ID = "statute"
local Kit = MOTA.Kit
-- The Statute Book board: ribbons along the top, then an open book of two pages.
local PARCH = M.slots.parch
local LEFT, TOP = PARCH.x + 34, PARCH.y + 20
local WIDTH, HEIGHT = PARCH.w - 60, PARCH.h - 44
local BOOK_TOP = 36 + 16
local BOOK_H = HEIGHT - BOOK_TOP
local TEXT_W, ROW_W = 370, 270
local TEXT_X, ROWS_X = 22, WIDTH - 270 - 18
local TEXT_H = BOOK_H - 40
local ROW_H, ROW_GAP = 37, 0
local WHEEL_STEP = 60
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

local STYLE = {
  part = { font = "kitName", color = "1B3570", before = 18 },
  section = { font = "kitSection", color = "7A5719", before = 12 },
  body = { font = "kitProse", color = "2A1F14", before = 6 },
  note = { font = "kitItalic", color = "5E4B33", before = 6 },
}

local root, scroll, child, slider, blocks, rows, hint

local function fontString(parent, font, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(MOTA:Font(font))
  fs:SetTextColor(MOTA:RGB(color))
  if color == "1B3570" then -- the accent's ink
    Kit:Track(function() fs:SetTextColor(MOTA:RGB(MOTA:Accent().INK)) end)
  end
  fs:SetJustifyH(justify or "LEFT")
  fs:SetJustifyV("TOP")
  return fs
end

-- Heights are only right once the page is on screen, so this runs on each show.
local function layoutText()
  local total = 12
  for _, b in ipairs(blocks) do total = total + b.before + b.fs:GetStringHeight() end
  child:SetHeight(total)
  local range = math.max(total - TEXT_H, 0)
  slider:SetMinMaxValues(0, range)
  slider:SetShown(range > 0)
end

local function buildText()
  scroll = CreateFrame("ScrollFrame", nil, root)
  scroll:SetSize(TEXT_W, TEXT_H)
  scroll:SetPoint("TOPLEFT", root, "TOPLEFT", TEXT_X, -(BOOK_TOP + 20))
  child = CreateFrame("Frame", nil, scroll)
  child:SetSize(TEXT_W, 1)
  scroll:SetScrollChild(child)

  blocks = {}
  local previous
  for i, entry in ipairs(MOTA.Charter) do
    local style = STYLE[entry[1]] or STYLE.body
    local fs = fontString(child, style.font, style.color)
    fs:SetWidth(TEXT_W - 8)
    fs:SetText(entry[2])
    local before = i == 1 and 0 or style.before
    if previous then
      fs:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -before)
    else
      fs:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    end
    blocks[i] = { fs = fs, before = before }
    previous = fs
  end

  slider = CreateFrame("Slider", nil, root)
  slider:SetOrientation("VERTICAL")
  slider:SetSize(8, TEXT_H)
  slider:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
  local track = slider:CreateTexture(nil, "BACKGROUND")
  local r, g, b = MOTA:RGB("C9B58A")
  track:SetColorTexture(r, g, b, 0.6)
  track:SetAllPoints()
  local thumb = slider:CreateTexture(nil, "ARTWORK")
  r, g, b = MOTA:RGB("7A5719")
  thumb:SetColorTexture(r, g, b, 1)
  thumb:SetSize(8, 44)
  slider:SetThumbTexture(thumb)
  slider:SetValueStep(1)
  slider:SetObeyStepOnDrag(true)
  slider:SetMinMaxValues(0, 1)
  slider:SetValue(0)
  slider:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)

  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, delta)
    slider:SetValue(slider:GetValue() - delta * WHEEL_STEP)
  end)
end

local function buildRows()
  local x = ROWS_X
  local head = Kit:Label(root, "kitTiny", "7A5719", 0.3, "Hear the Charter")
  head:SetPoint("TOPLEFT", root, "TOPLEFT", x + 2, -(BOOK_TOP + 16))
  local top = BOOK_TOP + 32

  rows = {}
  for i, clip in ipairs(MOTA.Voice:Clips()) do
    local b = CreateFrame("Button", nil, root)
    b:SetSize(ROW_W, ROW_H)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", x, -(top + (i - 1) * (ROW_H + ROW_GAP)))
    b.bg = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.bg:SetAllPoints()
    local dots = b:CreateTexture(nil, "BORDER")
    Kit:Solid(dots, "6E4F17", 0.3)
    dots:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    dots:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    dots:SetHeight(1)
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetColorTexture(0.79, 0.64, 0.29, 0.12)
    glow:SetAllPoints()
    b.roman = Kit:Text(b, "kitRoman", "7A5719", "CENTER")
    b.roman:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.roman:SetWidth(32)
    b.roman:SetText(ROMAN[i] or tostring(i))
    b.title = Kit:Text(b, "kitAmount", "2A1F14")
    b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 36, -4)
    b.title:SetWidth(ROW_W - 90)
    b.title:SetMaxLines(1)
    b.title:SetText(clip.title)
    b.small = Kit:Text(b, "kitItalic", "5E4B33")
    b.small:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, 0)
    b.action = Kit:Label(b, "kitTiny", "1B3570", 0.16)
    b.action:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b:SetScript("OnClick", function() Page:Press(i) end)
    rows[i] = b
  end
  hint = Kit:Text(root, "kitItalic", "5E4B33")
  hint:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x + 2, 8)
  hint:SetWidth(ROW_W - 4)
end

function Page:Press(i)
  local p = MOTA.Voice:Playing()
  if p and p.index == i then
    MOTA.Voice:Stop()
  else
    MOTA.Voice:Replay(i)
  end
  self:Refresh()
end

function Page:Refresh()
  if not rows then return end
  local p = MOTA.Voice:Playing()
  local locked = MOTA.Voice:Locked()
  local heard = MOTA.Voice:State().heard
  for i, b in ipairs(rows) do
    local clip = MOTA.Voice:Clips()[i]
    local on = p and p.index == i
    local ink = MOTA:Accent().INK
    Kit:Gradient(b.bg, ink, ink, on and 0.13 or 0, 0, true)
    b.roman:SetTextColor(MOTA:RGB(on and ink or "7A5719"))
    b.small:SetText(MOTA.Voice:Length(clip.length) .. (heard[i] and " · heard" or ""))
    b.action:SetText(on and (locked and "Playing" or "Stop") or (locked and "" or "Play"))
    b:SetEnabled(not locked)
  end
  hint:SetText(locked and "The introduction is being read. The list opens when it ends."
    or "Stopping a clip resets it: it plays again from the beginning.")
end

function Page:Show(show)
  if show and not root then
    root = CreateFrame("Frame", nil, UI.window)
    root:SetSize(WIDTH, HEIGHT)
    root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", LEFT, -TOP)
    local ribbon = Kit:Ribbon(root, 4)
    ribbon:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    ribbon:SetOn(true)
    local count = Kit:Label(root, "kitTiny", "7A5719", 0.3, "Ten readings")
    count:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -13)
    -- The open book: two pages and the gutter between them.
    local book = CreateFrame("Frame", nil, root)
    book:SetSize(WIDTH, BOOK_H)
    book:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -BOOK_TOP)
    Kit:Fill(book, "F6ECD2", "F6ECD2")
    Kit:Outline(book, "6E4F17", 0.6)
    local gutter = book:CreateTexture(nil, "BORDER")
    Kit:Solid(gutter, "6E4F17", 0.3)
    gutter:SetSize(2, BOOK_H)
    gutter:SetPoint("TOPLEFT", book, "TOPLEFT", ROWS_X - 16, 0)
    buildText()
    buildRows()
  end
  if not root then return end
  root:SetShown(show)
  if show then
    layoutText()
    self:Refresh()
  end
end

MOTA:Listen("PAGE_SHOWN", function(_, id) Page:Show(id == PAGE_ID) end)
MOTA:Listen("VOICE_CHANGED", function() Page:Refresh() end)
