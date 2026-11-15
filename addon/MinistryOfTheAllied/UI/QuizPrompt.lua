-- Ministry of the Allied: the Pub Quiz's answer herald (Duncan, 2026-11-12).
-- A team captain's question: the herald's royal banner (as UI/BankPrompt.lua
-- draws it) with the question in full, an answer box and Send. It stays on
-- screen until the captain answers, the question closes, or they leave the
-- quiz; it steps aside in combat and comes back after. Only captains get it.

local _, MOTA = ...
local M = MOTA.Media
local Kit = MOTA.Kit
local Prompt = {}
MOTA.QuizPrompt = Prompt

local SCALE = 0.8
local TOP = 110
local BOX_H = 28
local INK = "2A1F14"
local LABEL = { blue = "E4DDAE", blueSilver = "EEF2F6" }
local MAX_LINES = 4

local frame, slices, seal, eyebrow, title, body, box, send

local function part(name)
  local file = MOTA.skin and MOTA.skin.FILE or "ministry"
  return M.pieces["herald_" .. file .. ":" .. name] or M.pieces["herald_ministry:" .. name]
end

local function paint(tex, p)
  tex:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
end

local function layPart(tex, name, dy)
  local p = part(name)
  paint(tex, p)
  tex:SetTexCoord(p.l, p.r, p.t, p.b)
  tex:SetSize(p.w, p.h)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", frame, "TOPLEFT", p.x, -(p.y + dy))
end

local function layFrame(extra)
  local p, bands = part("frame"), M.herald.bands
  local cuts = { p.y, bands[1][1], bands[1][2], bands[2][1], bands[2][2], p.y + p.h }
  local function v(y) return p.t + (y - p.y) / p.h * (p.b - p.t) end
  local shift = 0
  for i = 1, 5 do
    local y0, y1 = cuts[i], cuts[i + 1]
    local grow = (i == 2 or i == 4) and extra / 2 or 0
    local t = slices[i]
    paint(t, p)
    t:SetTexCoord(p.l, p.r, v(y0), v(y1))
    t:SetSize(p.w, y1 - y0 + grow)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", p.x, -(y0 + shift))
    shift = shift + grow
  end
end

-- A spaced-out line of capitals (as the herald's heading line).
local function spaced(parent, font, tracking)
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(1, 1)
  b.letters = {}
  b.size = MOTA:FontSize(font)
  function b:SetText(text, hex, shadow)
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
  return b
end

local function column()
  local T = M.herald.text
  return T.x, M.herald.buttons.blue.x - T.gap - T.x
end

-- Lays the banner out: the question's lines, then the answer box, the banner
-- growing to hold them.
local function fit()
  local B, T = M.herald, M.herald.text
  local x, width = column()
  body:SetWidth(width)
  local lines = math.max(1, math.min(MAX_LINES, math.ceil((body:GetStringHeight() or T.line) / T.line)))
  local boxY = T.body - T.line / 2 + lines * T.line + 6
  local extra = math.max(0, math.ceil(boxY + BOX_H - (T.body + T.line * 1.5)))
  frame:SetHeight(B.h + extra)
  layFrame(extra)
  layPart(seal, "seal_official", extra / 2)

  eyebrow:ClearAllPoints()
  eyebrow:SetPoint("LEFT", frame, "TOPLEFT", x, -T.eyebrow)
  title:SetWidth(width)
  title:SetTextColor(MOTA:RGB(MOTA:Accent().INK))
  title:ClearAllPoints()
  title:SetPoint("LEFT", frame, "TOPLEFT", x, -T.title)
  body:ClearAllPoints()
  body:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -(T.body - T.line / 2))
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -boxY)
  box:SetWidth(width)

  local b = B.buttons.blue
  send:ClearAllPoints()
  send:SetPoint("TOPLEFT", frame, "TOPLEFT", b.x, -(b.y + extra / 2))
  layPart(send.art, "btn_blue", extra / 2)
  layPart(send.glow, "btn_blue", extra / 2)
  local silver = MOTA.skin and MOTA.skin.METAL == "silver"
  send.label:SetText("SEND", silver and LABEL.blueSilver or LABEL.blue, true)
  send.label:ClearAllPoints()
  send.label:SetPoint("CENTER", send, "CENTER", 0, T.label_up)
end

local function build()
  local B = M.herald
  frame = CreateFrame("Frame", "MinistryOfTheAlliedQuizPrompt", UIParent)
  frame:SetSize(B.w, B.h)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -TOP)
  frame:SetFrameStrata("DIALOG")
  frame:SetScale(SCALE)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  slices = {}
  for i = 1, 5 do slices[i] = frame:CreateTexture(nil, "BACKGROUND") end
  seal = frame:CreateTexture(nil, "ARTWORK")

  eyebrow = spaced(frame, "eyebrow", 0.32)
  title = frame:CreateFontString(nil, "OVERLAY")
  title:SetFontObject(MOTA:Font("heraldTitle"))
  title:SetJustifyH("LEFT")
  title:SetMaxLines(1)
  if title.SetWordWrap then title:SetWordWrap(false) end

  body = frame:CreateFontString(nil, "OVERLAY")
  body:SetFontObject(MOTA:Font("kitSmall"))
  body:SetTextColor(MOTA:RGB(INK))
  body:SetJustifyH("LEFT")
  body:SetJustifyV("TOP")
  body:SetMaxLines(MAX_LINES)
  if body.SetWordWrap then body:SetWordWrap(true) end

  box = CreateFrame("EditBox", nil, frame)
  box:SetHeight(BOX_H)
  box:SetFrameLevel(frame:GetFrameLevel() + 5)
  box:SetAutoFocus(false)
  box:SetMaxLetters(100)
  box:SetFontObject(MOTA:Font("kitSmall"))
  box:SetTextColor(MOTA:RGB(INK))
  box:SetTextInsets(7, 7, 0, 0)
  Kit:Fill(box, "FBF4E1", "F0E2BE")
  Kit:Outline(box, "6E4F17", 0.6)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  box:SetScript("OnEnterPressed", function() Prompt:Send() end)

  local b = B.buttons.blue
  send = CreateFrame("Button", nil, frame)
  send:SetSize(b.w, b.h)
  send:SetFrameLevel(frame:GetFrameLevel() + 5)
  send.art = send:CreateTexture(nil, "ARTWORK")
  send.glow = send:CreateTexture(nil, "HIGHLIGHT")
  send.glow:SetBlendMode("ADD")
  send.glow:SetAlpha(0.25)
  send.label = spaced(send, "kitButton", 0.16)
  send:SetScript("OnClick", function() Prompt:Send() end)
  frame.box, frame.send, frame.body = box, send, body

  -- The time left, every second.
  local wait = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    wait = wait - elapsed
    if wait > 0 then return end
    wait = 1
    Prompt:Update()
  end)
  Kit:Track(function() if frame:IsShown() then fit() end end)
end

local shownKey

function Prompt:Update()
  local Quiz = MOTA.Quiz
  if not Quiz:Waiting() or InCombatLockdown() then
    if frame then frame:Hide() end
    shownKey = nil
    return
  end
  if not frame then build() end
  local L = Quiz.live
  local Q = Quiz:Current()
  local left = math.max(0, math.floor(L.ends - GetTime()))
  local where = L.key == "tie" and "Tie-break" or ("Round " .. L.r .. " · Question " .. L.i)
  eyebrow:SetText(("The Pub Quiz · " .. where .. " · " .. string.format("%d:%02d", math.floor(left / 60), left % 60)):upper(), INK)
  title:SetText(L.key == "tie" and "Closest number wins" or ("Question " .. L.i))
  body:SetText(L.text)
  if shownKey ~= L.key then
    shownKey = L.key
    box:SetText("")
    fit()
    if MOTA.Herald and MOTA.Herald.PlayFanfare then pcall(MOTA.Herald.PlayFanfare, MOTA.Herald) end
  end
  frame:Show()
end

function Prompt:Send()
  local ok, err = MOTA.Quiz:Answer(box and box:GetText())
  if not ok then
    MOTA:Print(err)
    return nil
  end
  MOTA:Print(MOTA:Color("leaf", "Pub Quiz:"), "answer sent for your team: " .. strtrim(box:GetText()) .. ".")
  if box then box:ClearFocus() end
  self:Update()
  return true
end

function Prompt:IsShown()
  return frame ~= nil and frame:IsShown()
end

MOTA:Listen("QUIZ_ASKED", function() Prompt:Update() end)
MOTA:Listen("QUIZ_CHANGED", function() Prompt:Update() end)
MOTA:On("PLAYER_REGEN_DISABLED", function() Prompt:Update() end)
MOTA:On("PLAYER_REGEN_ENABLED", function() Prompt:Update() end)
