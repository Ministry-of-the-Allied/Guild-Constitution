-- Ministry of the Allied: the Constitution, on the Statute Book page (ADDON_SPEC.md, section 12.6).
-- The Charter to read on the left, the narration to replay on the right.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Page = {}
MOTA.ConstitutionPage = Page

local PAGE_ID = "statute"
local TOP, HEIGHT = 196, 438 -- under the heading, down to the page's foot
local TEXT_W, ROW_W = 410, 250
local ROW_H, ROW_GAP = 34, 3
local WHEEL_STEP = 60

local STYLE = {
  part = { font = "constitutionPart", color = "1B3570", before = 18 },
  section = { font = "constitutionSection", color = "7A5719", before = 12 },
  body = { font = "tool", color = "2A1F14", before = 6 },
  note = { font = "bodyItalic", color = "5E4B33", before = 6 },
}

local root, scroll, child, slider, blocks, rows, hint

local function fontString(parent, font, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(MOTA:Font(font))
  fs:SetTextColor(MOTA:RGB(color))
  fs:SetJustifyH(justify or "LEFT")
  fs:SetJustifyV("TOP")
  return fs
end

-- Heights are only right once the page is on screen, so this runs on each show.
local function layoutText()
  local total = 12
  for _, b in ipairs(blocks) do total = total + b.before + b.fs:GetStringHeight() end
  child:SetHeight(total)
  local range = math.max(total - HEIGHT, 0)
  slider:SetMinMaxValues(0, range)
  slider:SetShown(range > 0)
end

local function buildText()
  scroll = CreateFrame("ScrollFrame", nil, root)
  scroll:SetSize(TEXT_W, HEIGHT)
  scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
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
  slider:SetSize(8, HEIGHT)
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
  local x = TEXT_W + 28
  local head = fontString(root, "constitutionSection", "7A5719")
  head:SetPoint("TOPLEFT", root, "TOPLEFT", x, 0)
  head:SetText("Hear the Charter")
  hint = fontString(root, "bodyItalic", "5E4B33")
  hint:SetPoint("TOPLEFT", root, "TOPLEFT", x, -(22 + 10 * (ROW_H + ROW_GAP) + 2))
  hint:SetWidth(ROW_W)

  rows = {}
  for i, clip in ipairs(MOTA.Voice:Clips()) do
    local b = CreateFrame("Button", nil, root)
    b:SetSize(ROW_W, ROW_H)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", x, -(22 + (i - 1) * (ROW_H + ROW_GAP)))
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetColorTexture(1, 0.9, 0.6, 0.18)
    glow:SetAllPoints()
    b.title = fontString(b, "tool", "2A1F14")
    b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -2)
    b.title:SetWidth(ROW_W - 66)
    b.title:SetMaxLines(1)
    b.title:SetText(clip.title)
    b.small = fontString(b, "constitutionSmall", "5E4B33")
    b.small:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, 0)
    b.action = fontString(b, "constitutionAction", "1B3570", "RIGHT")
    b.action:SetPoint("TOPRIGHT", b, "TOPRIGHT", -8, -11)
    b:SetScript("OnClick", function() Page:Press(i) end)
    rows[i] = b
  end
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
    local r, g, bl = MOTA:RGB(on and "E6CF8F" or "EADDBB")
    b.bg:SetColorTexture(r, g, bl, 0.75)
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
    root:SetSize(M.slots.note.w, HEIGHT)
    root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", M.slots.note.x, -TOP)
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
