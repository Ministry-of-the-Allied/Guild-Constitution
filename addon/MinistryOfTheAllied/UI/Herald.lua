-- Ministry of the Allied: herald pop-ups (ADDON_SPEC.md, section 10.2).
-- A royal banner at the top of the screen: a gold frame round blue velvet (the
-- skin's colours), a crown, and a parchment panel with a seal, a heading line,
-- a title, a line or two of text and a button. One at a time, each for a few
-- seconds or until dismissed, never during combat.
--
-- The banner is Max's reference picture (design/reference/herald-banners.webp,
-- 9 Nov 2026), drawn per skin by tools/textures/herald.py; the words, the seal
-- and the button are laid on here where the reference has them.
--
--   MOTA.Herald:Announce{ seal = "official" | "crown" | "exchange" | "silverhand" | "ring" | "treasury",
--     eyebrow = "...", title = "...", text = "...",
--     button = { label = "Vote now" | "Read it" | "Open" | "Dismiss" | "Stop" | "Restart",
--                style = "blue" | "gold" | "quiet", page = <window page number>,
--                onPress = function, keep = true to stay open after a press },
--     stay = seconds on screen, or false to stay until closed; noFanfare = true;
--     closeX = true for a corner close button; onShow, onGone = functions }
--
-- Where heralds stand: at the top of the screen, or where the player put them
-- (Settings > Heralds > Preview: unlock the preview, drag it, Save; Max, 10 Nov).
--
-- /mota herald [1-3] shows the reference's examples; /mota fanfare picks the sound.

local _, MOTA = ...
local M = MOTA.Media
local Herald = {}
MOTA.Herald = Herald

-- Royal; Stately, halfway between (Max, 10 Nov); and Modest at 70% of Royal.
local SCALE = { full = 0.8, medium = 0.68, small = 0.56 }
local STAY = { full = 10, medium = 9, small = 8 } -- seconds on screen
local TOP = 110                            -- distance from the top of the screen, unless moved
local MAX_LINES = 6                        -- the body's lines at most (the banner grows past two)
local TITLE_MIN = 12                       -- a long title steps down to fit its line, no smaller than this
local LOCK_AT = 14                         -- the preview's lock knob: its middle, in from the frame's top-left corner

-- The preview's position presets (Max, 10 Nov): the gap between the banner (its crown, at
-- the top) and the edge of the screen, in UIParent units, and where each preset anchors.
-- A preset is kept by name, so it holds its edge whatever the herald's size or length.
local EDGE = 58
local PRESETS = { "top", "left", "center", "right", "bottom" }
local PRESET_NAMES = { top = "Top", left = "Left", center = "Center", right = "Right", bottom = "Bottom" }
-- The preset buttons: a cross of five, its foot just above the middle of the screen (UIParent units).
local CROSS = { y = 70, w = 90, h = 26, dx = 98, dy = 32,
  at = { top = { 0, 1 }, left = { -1, 0 }, center = { 0, 0 }, right = { 1, 0 }, bottom = { 0, -1 } } }

-- Ink, from the reference: the heading line and the text in the parchment's ink;
-- the title in the skin's accent ink; each button's label its own.
local INK = "2A1F14"
local LABEL = { blue = "E4DDAE", blueSilver = "EEF2F6", gold = "2A1A08" } -- quiet: the accent's ink
local SEALS = { "official", "crown", "exchange", "silverhand", "ring", "treasury" }
local STYLES = { "blue", "gold", "quiet" }

local queue = {}
local frame, current, hideTimer
local unlocked = false -- the preview can be dragged
local chosenPreset     -- the preset the preview stands at, until it's dragged

---------------------------------------------------------------------------
-- The fanfare: one of the game's own sounds, chosen with /mota fanfare
---------------------------------------------------------------------------

Herald.fanfareNames = {
  "LEVELUPSOUND", "READY_CHECK", "RAID_WARNING", "PVP_THROUGH_QUEUE", "PVP_ENTER_QUEUE",
  "UI_EPICLOOT_TOAST", "UI_LEGENDARY_LOOT_TOAST", "UI_PERSONAL_LOOT_BANNER",
  "UI_RAID_BOSS_WHISPER_WARNING", "ALARM_CLOCK_WARNING_3", "UI_BNET_TOAST",
}

-- The sounds this client has, in list order.
function Herald:Fanfares()
  local list = {}
  for _, name in ipairs(self.fanfareNames) do
    if SOUNDKIT and SOUNDKIT[name] then list[#list + 1] = name end
  end
  return list
end

function Herald:PlayFanfare(name)
  name = name or MOTA.db.settings.fanfareSound or self:Fanfares()[1]
  if name and SOUNDKIT and SOUNDKIT[name] then PlaySound(SOUNDKIT[name]) end
end

---------------------------------------------------------------------------
-- Building the banner
---------------------------------------------------------------------------

-- The skin's own drawing of a part: "frame", "seal_<name>", "btn_<style>".
local function part(name)
  local file = MOTA.skin and MOTA.skin.FILE or "ministry"
  return M.pieces["herald_" .. file .. ":" .. name] or M.pieces["herald_ministry:" .. name]
end

local function paint(tex, p)
  tex:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
end

-- A spaced-out line of capitals: each letter its own font string (game text can't
-- be letter-spaced), all sharing one middle line so the row sits where it's put.
local function spaced(parent, font, tracking)
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(1, 1)
  box.letters = {}
  box.size = MOTA:FontSize(font)
  function box:SetText(text, hex, shadow)
    local x, n, gap = 0, 0, self.size * tracking
    for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      n = n + 1
      local fs = self.letters[n]
      if not fs then
        fs = self:CreateFontString(nil, "OVERLAY")
        fs:SetFontObject(MOTA:Font(font))
        self.letters[n] = fs
      end
      fs:SetTextColor(MOTA:RGB(hex))
      fs:SetShadowColor(0, 0, 0, shadow and 0.7 or 0)
      fs:SetShadowOffset(0, shadow and -1 or 0)
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", self, "LEFT", x, 0)
      fs:SetText(ch)
      fs:Show()
      x = x + (ch == " " and self.size * 0.28 or fs:GetStringWidth()) + gap
    end
    for i = n + 1, #self.letters do self.letters[i]:Hide() end
    self:SetWidth(math.max(1, x - gap))
  end
  return box
end

local function build()
  local B = M.herald
  frame = CreateFrame("Frame", "MinistryOfTheAlliedHerald", UIParent)
  frame:SetSize(B.w, B.h)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -TOP)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:Hide()

  -- The frame in five bands, so the two thin ones can stretch for longer text.
  frame.slices = {}
  for i = 1, 5 do frame.slices[i] = frame:CreateTexture(nil, "BACKGROUND") end
  frame.seal = frame:CreateTexture(nil, "ARTWORK")

  local T = B.text
  frame.eyebrow = spaced(frame, "eyebrow", 0.32)
  frame.title = frame:CreateFontString(nil, "OVERLAY")
  frame.title:SetFontObject(MOTA:Font("heraldTitle"))
  frame.title:SetJustifyH("LEFT")
  if frame.title.SetWordWrap then frame.title:SetWordWrap(false) end
  -- The text is wrapped here, a font string a line, so the lines keep the reference's spacing.
  frame.lines = {}
  for i = 1, MAX_LINES do
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(MOTA:Font("heraldBody"))
    fs:SetTextColor(MOTA:RGB(INK))
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    frame.lines[i] = fs
  end
  frame.measure = frame:CreateFontString(nil, "OVERLAY")
  frame.measure:SetFontObject(MOTA:Font("heraldBody"))
  frame.measure:Hide()

  -- One button per look; the label is laid on it each time.
  frame.buttons = {}
  for _, style in ipairs(STYLES) do
    local box = B.buttons[style]
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(box.w, box.h)
    b:SetFrameLevel(frame:GetFrameLevel() + 5)
    b.art = b:CreateTexture(nil, "ARTWORK")
    b.glow = b:CreateTexture(nil, "HIGHLIGHT")
    b.glow:SetBlendMode("ADD")
    b.glow:SetAlpha(0.25)
    b.label = spaced(b, "kitButton", 0.16)
    b.style, b.box = style, box
    b:SetScript("OnClick", function() Herald:Press() end)
    b:Hide()
    frame.buttons[style] = b
  end

  -- The corner close button, for heralds whose main button does something else:
  -- on the parchment above the button's right end (the reference has none).
  local x = CreateFrame("Button", nil, frame)
  x:SetSize(24, 24)
  x:SetPoint("CENTER", frame, "TOPLEFT", T.closeX, -T.closeY)
  x:SetFrameLevel(frame:GetFrameLevel() + 6)
  local mark = x:CreateFontString(nil, "OVERLAY")
  mark:SetFontObject(MOTA:Font("setLabel"))
  mark:SetTextColor(MOTA:RGB("7A5719"))
  mark:SetText("X")
  mark:SetPoint("CENTER")
  x:SetScript("OnClick", function() if current then Herald:Close(current) end end)
  x:Hide()
  frame.closeX = x

  -- The preview's round lock: a knob like the window's gear, on the frame's top-left corner.
  -- Open, the banner can be dragged; the preview's Save button keeps where it stands.
  local lock = CreateFrame("Button", nil, frame)
  lock:SetFrameLevel(frame:GetFrameLevel() + 7)
  lock.art = lock:CreateTexture(nil, "ARTWORK")
  lock.art:SetAllPoints()
  lock.glow = lock:CreateTexture(nil, "HIGHLIGHT")
  lock.glow:SetAllPoints()
  lock.glow:SetBlendMode("ADD")
  lock.glow:SetAlpha(0.25)
  lock:SetScript("OnClick", function() Herald:Unlock(not unlocked) end)
  lock:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(unlocked and "Lock the herald in place" or "Unlock to drag the herald")
    GameTooltip:AddLine(unlocked and "Then press Save to keep where it stands."
      or "Drag it where you'd like heralds to appear.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  lock:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  lock:Hide()
  frame.lock = lock

  frame:SetMovable(true)
  -- the game mustn't keep a dragged place of its own: ours (settings.heraldPos) is put back each time
  if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if not unlocked then return end
    chosenPreset = nil -- dragged: its own place now, not a preset's
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

  -- Unrolling (Royal) or fading in (Modest), and fading out.
  frame.unroll = frame:CreateAnimationGroup()
  local grow = frame.unroll:CreateAnimation("Scale")
  if grow.SetScaleFrom then
    grow:SetScaleFrom(0.04, 1)
    grow:SetScaleTo(1, 1)
  end
  grow:SetOrigin("CENTER", 0, 0)
  grow:SetDuration(0.7)
  grow:SetSmoothing("OUT")
  local appear = frame.unroll:CreateAnimation("Alpha")
  appear:SetFromAlpha(0)
  appear:SetToAlpha(1)
  appear:SetDuration(0.25)

  frame.fadeIn = frame:CreateAnimationGroup()
  local fade = frame.fadeIn:CreateAnimation("Alpha")
  fade:SetFromAlpha(0)
  fade:SetToAlpha(1)
  fade:SetDuration(0.3)

  frame.fadeOut = frame:CreateAnimationGroup()
  local out = frame.fadeOut:CreateAnimation("Alpha")
  out:SetFromAlpha(1)
  out:SetToAlpha(0)
  out:SetDuration(0.3)
  frame.fadeOut:SetScript("OnFinished", function()
    frame:Hide()
    local gone = current
    current = nil
    if gone and gone.onGone then gone.onGone(gone) end
    Herald:Next()
  end)

  -- Hovering keeps it on screen.
  frame:SetScript("OnEnter", function() if hideTimer then hideTimer:Cancel() hideTimer = nil end end)
  frame:SetScript("OnLeave", function()
    if current and current.stay ~= false then Herald:HideLater(3) end
  end)

  -- A change of skin redraws the banner in the new one.
  MOTA.Kit:Track(function() if current and frame:IsShown() then Herald:Fit(current) end end)
end

---------------------------------------------------------------------------
-- Laying out one herald
---------------------------------------------------------------------------

-- The words in lines no wider than width: whole words, as the reference breaks them.
local function wrap(text, width)
  local lines, line = {}, nil
  local m = frame.measure
  local function wide(s)
    m:SetText(s)
    return m.GetUnboundedStringWidth and m:GetUnboundedStringWidth() or m:GetStringWidth()
  end
  for word in tostring(text or ""):gmatch("%S+") do
    local try = line and (line .. " " .. word) or word
    if line and wide(try) > width then
      lines[#lines + 1] = line
      line = word
    else
      line = try
    end
  end
  if line then lines[#lines + 1] = line end
  return lines
end

-- The frame's picture in five bands: the second and fourth stretch, half the extra height each.
local function layFrame(extra)
  local p, bands = part("frame"), M.herald.bands
  local cuts = { p.y, bands[1][1], bands[1][2], bands[2][1], bands[2][2], p.y + p.h }
  local function v(y) return p.t + (y - p.y) / p.h * (p.b - p.t) end
  local shift = 0
  for i = 1, 5 do
    local y0, y1 = cuts[i], cuts[i + 1]
    local grow = (i == 2 or i == 4) and extra / 2 or 0
    local t = frame.slices[i]
    paint(t, p)
    t:SetTexCoord(p.l, p.r, v(y0), v(y1))
    t:SetSize(p.w, y1 - y0 + grow)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", p.x, -(y0 + shift))
    shift = shift + grow
  end
end

-- A part's picture at its place in the frame, moved down by dy.
local function layPart(tex, name, dy, anchor)
  local p = part(name)
  paint(tex, p)
  tex:SetTexCoord(p.l, p.r, p.t, p.b)
  tex:SetSize(p.w, p.h)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", anchor or frame, "TOPLEFT", p.x, -(p.y + dy))
end

function Herald:Fit(h)
  local B, T = M.herald, M.herald.text
  local silver = MOTA.skin and MOTA.skin.METAL == "silver"
  local b = h.button or { label = "Dismiss", style = "quiet" }
  local style = frame.buttons[b.style] and b.style or "quiet"
  local chosen = frame.buttons[style]
  for _, button in pairs(frame.buttons) do button:SetShown(button == chosen) end

  -- The text runs up to the button, with the canvas's 16-unit gap.
  local width = chosen.box.x - T.gap - T.x
  local lines = wrap(h.text, width)
  local n = math.min(#lines, MAX_LINES)
  if #lines > MAX_LINES then lines[MAX_LINES] = lines[MAX_LINES] .. "..." end
  -- Two lines is the reference. One line: the words drop half a line, staying beside
  -- the seal. Three or more: the banner grows a line at a time, seal and button kept
  -- in its middle.
  local drop = n < 2 and T.line / 2 or 0
  local extra = math.max(0, n - 2) * T.line
  frame:SetHeight(B.h + extra)
  layFrame(extra)
  layPart(frame.seal, "seal_" .. (h.seal or "official"), extra / 2)

  frame.eyebrow:SetText((h.eyebrow or ""):upper(), INK)
  frame.eyebrow:ClearAllPoints()
  frame.eyebrow:SetPoint("LEFT", frame, "TOPLEFT", T.x, -(T.eyebrow + drop))

  -- A long title steps down half a point at a time until it fits its one line, in the
  -- title's own font (Max, 10 Nov: the plain smaller font it used to drop to looked too small).
  frame.title:SetWidth(0)
  frame.title:SetText(h.title or "")
  local size = MOTA:FontSize("heraldTitle")
  frame.title:SetFontObject(MOTA:Font("heraldTitle"))
  local function wide()
    local t = frame.title
    return t.GetUnboundedStringWidth and t:GetUnboundedStringWidth() or t:GetStringWidth() or 0
  end
  while wide() > width and size > TITLE_MIN do
    size = size - 0.5
    frame.title:SetFontObject(MOTA:FontAt("decoBold", size))
  end
  frame.titleSize = size
  frame.title:SetWidth(width)
  frame.title:SetTextColor(MOTA:RGB(MOTA:Accent().INK))
  frame.title:ClearAllPoints()
  frame.title:SetPoint("LEFT", frame, "TOPLEFT", T.x, -(T.title + drop))

  for i, fs in ipairs(frame.lines) do
    fs:SetText(lines[i] or "")
    fs:SetShown(i <= n)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", frame, "TOPLEFT", T.x, -(T.body + (i - 1) * T.line + drop))
  end

  -- The button: its picture, a glow when hovered, and its label in the middle.
  local box = chosen.box
  chosen:ClearAllPoints()
  chosen:SetPoint("TOPLEFT", frame, "TOPLEFT", box.x, -(box.y + extra / 2))
  layPart(chosen.art, "btn_" .. style, extra / 2)
  layPart(chosen.glow, "btn_" .. style, extra / 2)
  local ink = style == "quiet" and MOTA:Accent().INK
    or style == "gold" and LABEL.gold
    or (silver and LABEL.blueSilver or LABEL.blue)
  chosen.label:SetText((b.label or "Dismiss"):upper(), ink, style == "blue")
  chosen.label:ClearAllPoints()
  chosen.label:SetPoint("CENTER", chosen, "CENTER", 0, T.label_up)
  frame.closeX:SetShown(h.closeX and true or false)
  Herald:LayLock()
end

-- The preview's lock knob, in the skin's own wax, shut or open.
function Herald:LayLock()
  local lock = frame.lock
  local preview = current ~= nil and current.preview == true
  lock:SetShown(preview)
  if preview and not self:Presets() then self:BuildPresets() end
  if self:Presets() then self:Presets():SetShown(preview) end
  if not preview then return end
  local file = MOTA.skin and MOTA.skin.FILE or "ministry"
  local name = (unlocked and ":knobUnlock" or ":knobLock")
  local p = M.pieces[file .. name] or M.pieces["ministry" .. name]
  if not p then return end
  paint(lock.art, p)
  lock.art:SetTexCoord(p.l, p.r, p.t, p.b)
  paint(lock.glow, p)
  lock.glow:SetTexCoord(p.l, p.r, p.t, p.b)
  lock:SetSize(p.w, p.h)
  lock:ClearAllPoints()
  lock:SetPoint("CENTER", frame, "TOPLEFT", LOCK_AT, -LOCK_AT)
end

---------------------------------------------------------------------------
-- Where heralds stand, and the preview that moves them
---------------------------------------------------------------------------

-- A preset's anchor: the frame's point on the screen's same point, and its offset in
-- UIParent units. EDGE is the gap to the banner's edge; at the top that's its crown, and
-- at the sides and middle the crown and banner together are centred.
function Herald:PresetPoint(name)
  local s = frame and frame:GetScale() or SCALE.full
  local crown = -(part("frame").y) * s
  if name == "top" then return "TOP", 0, -(EDGE + crown) end
  if name == "bottom" then return "BOTTOM", 0, EDGE end
  if name == "left" then return "LEFT", EDGE, -crown / 2 end
  if name == "right" then return "RIGHT", -EDGE, -crown / 2 end
  return "CENTER", 0, -crown / 2
end

-- Where heralds stand: a preset by name, or a place of the player's own, saved as the
-- banner's top middle in UIParent's units from the top middle of the screen (so it
-- stays put whatever the herald's size); else the top of the screen.
local function anchor(pos)
  frame:ClearAllPoints()
  local s = frame:GetScale() or 1
  if type(pos) == "table" and PRESET_NAMES[pos.preset] then
    local point, x, y = Herald:PresetPoint(pos.preset)
    frame:SetPoint(point, UIParent, point, x / s, y / s)
  elseif type(pos) == "table" and pos.x and pos.y then
    frame:SetPoint("TOP", UIParent, "TOP", pos.x / s, pos.y / s)
  else
    frame:SetPoint("TOP", UIParent, "TOP", 0, -TOP)
  end
end

local function place()
  anchor(MOTA.db.settings.heraldPos)
end

-- Save on the preview: the preset it stands at, or (dragged) its own place.
local function savePosition()
  if chosenPreset then
    MOTA.db.settings.heraldPos = { preset = chosenPreset }
    return true
  end
  local cx, cy = frame:GetCenter()
  local s, h = frame:GetScale() or 1, frame:GetHeight() or 0
  local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
  if not (cx and cy and pw and ph) then return false end
  MOTA.db.settings.heraldPos = { x = cx * s - pw / 2, y = (cy + h / 2) * s - ph }
  return true
end

-- The preview's preset buttons, a cross of five just above the middle of the screen,
-- each in the place it sends the herald to. Above the herald, so a herald in the
-- middle can't cover them.
local cross
local function buildCross()
  cross = CreateFrame("Frame", "MinistryOfTheAlliedHeraldPresets", UIParent)
  local w = 2 * CROSS.dx + CROSS.w + 24
  local h = 2 * CROSS.dy + CROSS.h + 38
  cross:SetSize(w, h)
  cross:SetPoint("CENTER", UIParent, "CENTER", 0, CROSS.y)
  cross:SetFrameStrata("FULLSCREEN_DIALOG")
  cross:EnableMouse(true)
  MOTA.Kit:Fill(cross, "1B140A", "0E0A05", 0.82, 0.88)
  -- its rules, heading and button rings in the skin's metal: gold, or Silverhand's silver (Max, 10 Nov)
  local rules = { { MOTA.Kit:Outline(cross, "C9A24A", 0.8), 0.8 }, { MOTA.Kit:Outline(cross, "C9A24A", 0.3, 3), 0.3 } }
  local head = MOTA.Kit:Label(cross, "kitTiny", "F3D98A", 0.32, "Herald position")
  head:SetPoint("TOP", cross, "TOP", 0, -9)
  cross.head = head
  cross.buttons = {}
  for _, name in ipairs(PRESETS) do
    local at = CROSS.at[name]
    local b = MOTA.Kit:Button(cross, CROSS.w, CROSS.h, PRESET_NAMES[name], "blue", function()
      if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
      Herald:SetPreset(name)
    end)
    b:SetPoint("CENTER", cross, "CENTER", at[1] * CROSS.dx, at[2] * CROSS.dy - 6)
    -- a ring of our own over the button's gold one, so it can turn silver
    local ring = MOTA.Kit:Outline(b, "D2AE5C", 0.8)
    for _, t in ipairs(ring) do t:SetDrawLayer("OVERLAY") end
    rules[#rules + 1] = { ring, 0.8, true }
    cross.buttons[name] = b
  end
  MOTA.Kit:Track(function()
    local silver = MOTA.skin and MOTA.skin.METAL == "silver"
    for _, r in ipairs(rules) do
      local hex = silver and (r[3] and "C9D1DC" or "AEB8C6") or (r[3] and "D2AE5C" or "C9A24A")
      for _, t in ipairs(r[1]) do t:SetColorTexture(MOTA:RGB(hex)) t:SetAlpha(r[2]) end
    end
    head:SetColor(silver and "EEF2F6" or "F3D98A")
    for _, b in pairs(cross.buttons) do
      if b.label and b.label.SetColor then b.label:SetColor(silver and "EEF2F6" or "F3D98A") end
    end
  end)
  cross:Hide()
end

-- The preview to a preset (kept when Save is pressed).
function Herald:SetPreset(name)
  if not (frame and current and current.preview and PRESET_NAMES[name]) then return end
  chosenPreset = name
  anchor({ preset = name })
end

function Herald:Presets()
  return cross
end

function Herald:BuildPresets()
  if not cross then buildCross() end
  return cross
end

-- Open, the preview can be dragged; shut, it stays.
function Herald:Unlock(open)
  unlocked = open and true or false
  if frame then self:LayLock() end
end

function Herald:IsUnlocked()
  return unlocked
end

-- Back to the top of the screen.
function Herald:ResetPosition()
  MOTA.db.settings.heraldPos = nil
  if frame and current then place() end
end

-- The size chosen in Settings, on the herald showing now too.
function Herald:Resize()
  if not (frame and current) then return end
  local size = MOTA.db.settings.heraldSize
  frame:SetScale(SCALE[size] or SCALE.full)
  if chosenPreset then
    anchor({ preset = chosenPreset })
  elseif not unlocked then
    place()
  end
end

-- Settings > Heralds > Preview: a herald that stays until saved or closed, with the
-- lock on its corner and Save for its button. A herald already up steps back into the
-- queue, first in line after the preview.
function Herald:Preview()
  if current and current.preview then return current end
  local h
  h = { seal = "official", eyebrow = "Herald preview", title = "Where heralds appear",
    text = "Pick a place from the buttons, or open the round lock and drag this banner. Then press Save.",
    noFanfare = true, stay = false, closeX = true, preview = true,
    button = { label = "Save", style = "blue", onPress = function()
      savePosition()
      MOTA:Print("Heralds will appear here from now on. Settings > Heralds > Preview moves them again.")
    end },
    onGone = function()
      unlocked, chosenPreset = false, nil
      if cross then cross:Hide() end
      if frame then place() end
    end }
  if current then
    if hideTimer then hideTimer:Cancel() hideTimer = nil end
    frame.fadeOut:Stop()
    table.insert(queue, 1, current)
    current = nil
    frame:Hide()
  end
  table.insert(queue, 1, h)
  -- a preset already chosen stays chosen, so Save keeps it as a preset
  local pos = MOTA.db.settings.heraldPos
  chosenPreset = type(pos) == "table" and PRESET_NAMES[pos.preset] and pos.preset or nil
  self:Next()
  return h
end

function Herald:HideLater(seconds)
  if hideTimer then hideTimer:Cancel() end
  hideTimer = C_Timer.NewTimer(seconds, function()
    hideTimer = nil
    if current then frame.fadeOut:Play() end
  end)
end

function Herald:Next()
  if current or #queue == 0 then return end
  if InCombatLockdown() then return end -- PLAYER_REGEN_ENABLED tries again
  if not frame then build() end
  current = table.remove(queue, 1)
  local size = SCALE[MOTA.db.settings.heraldSize] and MOTA.db.settings.heraldSize or "full"
  frame:SetScale(SCALE[size])
  place()
  self:Fit(current)
  frame:SetAlpha(1)
  frame:Show()
  -- Royal and Stately unroll; Modest fades in.
  if size == "small" then frame.fadeIn:Play() else frame.unroll:Play() end
  if MOTA.db.settings.fanfare and not current.noFanfare then self:PlayFanfare() end
  if current.stay ~= false then self:HideLater(current.stay or STAY[size]) end
  if current.onShow then current.onShow(current) end
end

-- What the herald's button does: open its page, then the herald goes.
function Herald:Press()
  local button = current and current.button
  if button and button.onPress then button.onPress() end
  if button and button.keep then return end
  local page = button and button.page
  if page then
    MOTA.UI:Build()
    MOTA.UI:SelectPage(page)
    MOTA.UI.window:Show()
  end
  if hideTimer then hideTimer:Cancel() hideTimer = nil end
  frame.fadeOut:Play()
end

-- Queue a herald. Switched off in settings, only forced ones (the samples) show.
function Herald:Announce(h, force)
  if not force and not MOTA.db.settings.herald then return false end
  queue[#queue + 1] = h
  self:Next()
  return true
end

-- Redraws a herald after its text or button changed; it then stays until
-- closed or until HideLater is called.
function Herald:Update(h)
  if h ~= current then return end
  if hideTimer then hideTimer:Cancel() hideTimer = nil end
  frame.fadeOut:Stop() -- it may have been on its way out
  frame:SetAlpha(1)
  self:Fit(h)
end

function Herald:IsShowing(h)
  return h == current
end

-- Takes one herald away, whether it's showing or still waiting its turn.
function Herald:Close(h)
  if h == current then
    if hideTimer then hideTimer:Cancel() hideTimer = nil end
    frame.fadeOut:Play()
    return
  end
  for i, waiting in ipairs(queue) do
    if waiting == h then
      table.remove(queue, i)
      if h.onGone then h.onGone(h) end
      return
    end
  end
end

function Herald:Waiting()
  return #queue + (current and 1 or 0)
end

MOTA:On("PLAYER_REGEN_ENABLED", function() Herald:Next() end)

---------------------------------------------------------------------------
-- The reference's examples, and test records from other members
---------------------------------------------------------------------------

Herald.samples = {
  { seal = "official", eyebrow = "Hear ye · the Ballot Hall", title = "The polls are open!",
    text = "Citizens of the Cathedral Ward: elect your Representative before Friday, 9 pm.",
    button = { label = "Vote now", style = "blue", page = 2 } },
  { seal = "crown", eyebrow = "By Royal Assent", title = "The Guild Bank Levy is law",
    text = "Given under the seal of King Aldmere. In force until 30 January.",
    button = { label = "Read it", style = "gold", page = 3 } },
  { seal = "exchange", eyebrow = "Crossing the floor", title = "Elowen Marsh defects!",
    text = "She leaves the Silverhand for the Azeroth Exchange.",
    button = { label = "Dismiss", style = "quiet" } },
}

function Herald:ShowSamples(n)
  local list = n and { self.samples[n] } or self.samples
  if #list == 0 then return MOTA:Print("There are", #self.samples, "sample heralds: /mota herald 1, 2 or 3.") end
  for _, h in ipairs(list) do self:Announce(h, true) end
  MOTA:Print(#list == 1 and "Showing a sample herald" or "Showing the sample heralds",
    "(the reference's example text, not real news).")
  if InCombatLockdown() then MOTA:Print("It waits until you're out of combat.") end
end

MOTA:Listen("RECORD_ADDED", function(self, rec)
  if rec.k ~= "test.note" or rec.a == self.me or self.Book.replaying then return end
  Herald:Announce({
    seal = "official",
    eyebrow = "Hear ye · a test record",
    title = "A test from " .. self:Short(rec.a),
    text = tostring(rec.d.text or ""),
    button = { label = "Dismiss", style = "quiet" },
  })
end)
