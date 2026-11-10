-- Ministry of the Allied: "What was it for?" (ADDON_SPEC.md, section 10.7).
-- The herald's royal banner (UI/Herald.lua, Max's reference picture) with a
-- list of reasons on its parchment. It stays on screen until answered, with no
-- close button, and comes back after a reload. It only blocks itself, and
-- steps aside during combat.

local _, MOTA = ...
local M = MOTA.Media
local Kit = MOTA.Kit
local Prompt = {}
MOTA.BankPrompt = Prompt

local REASONS = {
  d = {
    { "tax", "Tax" }, { "ring_fee", "Ring entry fee" }, { "fine", "Treasury fine" }, { "donation", "Donation" },
    { "lottery", "Lottery tickets" }, { "party_sh", "Silverhand donation" }, { "party_ex", "Exchange donation" }, { "other", "Other" },
  },
  w = {
    { "supplies", "Guild supplies" }, { "repairs", "Repairs" }, { "ring_prize", "Ring prize" }, { "ring_refund", "Ring refund" }, { "lottery_prize", "Lottery payout" },
    { "party_sh", "Silverhand funds" }, { "party_ex", "Exchange funds" }, { "other", "Other" },
  },
}
Prompt.REASONS = REASONS

local SCALE = 0.8   -- as a Royal herald
local TOP = 110     -- where the herald stands
local SEAL_FOR = { party_sh = "silverhand", party_ex = "exchange" }
local ROW_H = 26
local MAX_ROWS = 8
local BOX_H = 28    -- the chooser and the note box
local ROW_DOWN = 4  -- the chooser's middle, below the herald's first text line
local OTHER_W = 100 -- the chooser's width beside the note box
-- Ink, as on the herald: the heading line in the parchment's ink, the title in
-- the skin's accent ink, the blue button's label pale gold (pale silver on silver skins).
local INK = "2A1F14"
local LABEL = { blue = "E4DDAE", blueSilver = "EEF2F6" }

local frame, slices, seal, eyebrow, title, chooser, chooserText, list, rows, noteBox, confirm
local chosen, sealName

function Prompt:LabelFor(io, reason)
  for _, r in ipairs(REASONS[io] or {}) do
    if r[1] == reason then return r[2] end
  end
  return reason
end

---------------------------------------------------------------------------
-- The banner, drawn as the herald draws it (UI/Herald.lua)
---------------------------------------------------------------------------

-- The skin's own drawing of a banner part: "frame", "seal_<name>", "btn_blue".
local function part(name)
  local file = MOTA.skin and MOTA.skin.FILE or "ministry"
  return M.pieces["herald_" .. file .. ":" .. name] or M.pieces["herald_ministry:" .. name]
end

local function paint(tex, p)
  tex:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
end

-- A part's picture at its place on the banner, moved down by dy.
local function layPart(tex, name, dy)
  local p = part(name)
  paint(tex, p)
  tex:SetTexCoord(p.l, p.r, p.t, p.b)
  tex:SetSize(p.w, p.h)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", frame, "TOPLEFT", p.x, -(p.y + dy))
end

-- The frame in five bands: the second and fourth stretch, half the extra height each.
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

-- A spaced-out line of capitals: a font string a letter, all on one middle line.
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

-- The herald's text column: from its text line up to the blue button, less the gap.
local function column()
  local T = M.herald.text
  return T.x, M.herald.buttons.blue.x - T.gap - T.x
end

-- Lays the banner out. While the list is open the banner grows to hold it, the
-- seal and the button kept in its middle, as the herald grows for longer text.
local function fit()
  local B, T = M.herald, M.herald.text
  local x, width = column()
  local rowY = T.body + ROW_DOWN - BOX_H / 2
  local extra = 0
  if list:IsShown() then
    local bottom = rowY + BOX_H + 2 + list:GetHeight()
    extra = math.max(0, math.ceil(bottom - (T.body + T.line * 1.5)))
  end
  frame:SetHeight(B.h + extra)
  layFrame(extra)
  layPart(seal, "seal_" .. (sealName or "treasury"), extra / 2)

  eyebrow:ClearAllPoints()
  eyebrow:SetPoint("LEFT", frame, "TOPLEFT", x, -T.eyebrow)
  title:SetWidth(width)
  title:SetTextColor(MOTA:RGB(MOTA:Accent().INK))
  title:ClearAllPoints()
  title:SetPoint("LEFT", frame, "TOPLEFT", x, -T.title)

  chooser:ClearAllPoints()
  chooser:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -rowY)
  chooser:SetWidth(chosen == "other" and OTHER_W or width)
  noteBox:ClearAllPoints()
  noteBox:SetPoint("TOPLEFT", frame, "TOPLEFT", x + OTHER_W + 8, -rowY)
  noteBox:SetWidth(width - OTHER_W - 8)
  list:SetWidth(width)
  local r, g, b = MOTA:RGB(MOTA:Accent().INK)
  for _, row in ipairs(rows) do
    row:SetWidth(width - 2)
    row.glow:SetColorTexture(r, g, b, 0.15)
  end

  local box = B.buttons.blue
  confirm:ClearAllPoints()
  confirm:SetPoint("TOPLEFT", frame, "TOPLEFT", box.x, -(box.y + extra / 2))
  layPart(confirm.art, "btn_blue", extra / 2)
  layPart(confirm.glow, "btn_blue", extra / 2)
  local silver = MOTA.skin and MOTA.skin.METAL == "silver"
  confirm.label:SetText("CONFIRM", silver and LABEL.blueSilver or LABEL.blue, true)
  confirm.label:ClearAllPoints()
  confirm.label:SetPoint("CENTER", confirm, "CENTER", 0, T.label_up)
end

local function choose(reason)
  chosen = reason
  list:Hide()
  local move = MOTA.Bank:Pending()[1]
  chooserText:SetText(reason and Prompt:LabelFor(move and move.io, reason) or "Choose a reason")
  sealName = SEAL_FOR[reason] or "treasury" -- the Treasury's own form of the Seal of the State
  local other = reason == "other"
  noteBox:SetShown(other)
  if other then
    noteBox:SetText("")
    noteBox:SetFocus()
  end
  confirm:SetEnabled(reason ~= nil)
  confirm:SetAlpha(reason and 1 or 0.45)
  fit()
end

local function build()
  local B = M.herald
  frame = CreateFrame("Frame", "MinistryOfTheAlliedBankPrompt", UIParent)
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
  frame.slices, frame.seal = slices, seal

  eyebrow = spaced(frame, "eyebrow", 0.32)
  title = frame:CreateFontString(nil, "OVERLAY")
  title:SetFontObject(MOTA:Font("heraldTitle"))
  title:SetJustifyH("LEFT")
  title:SetMaxLines(1)
  if title.SetWordWrap then title:SetWordWrap(false) end
  frame.eyebrow, frame.title = eyebrow, title

  chooser = CreateFrame("Button", nil, frame)
  chooser:SetHeight(BOX_H)
  chooser:SetFrameLevel(frame:GetFrameLevel() + 5)
  Kit:Fill(chooser, "FBF4E1", "F0E2BE")
  Kit:Outline(chooser, "6E4F17", 0.6)
  local glow = chooser:CreateTexture(nil, "HIGHLIGHT")
  glow:SetColorTexture(1, 0.95, 0.7, 0.25)
  glow:SetAllPoints()
  chooserText = Kit:Text(chooser, "kitSmall")
  chooserText:SetPoint("LEFT", chooser, "LEFT", 9, 0)
  chooserText:SetPoint("RIGHT", chooser, "RIGHT", -20, 0)
  chooserText:SetMaxLines(1)
  local arrow = Kit:Text(chooser, "kitSmall", "7A5719")
  arrow:SetPoint("RIGHT", chooser, "RIGHT", -8, 0)
  arrow:SetText("v")
  chooser:SetScript("OnClick", function()
    list:SetShown(not list:IsShown())
    fit()
  end)

  noteBox = CreateFrame("EditBox", nil, frame)
  noteBox:SetHeight(BOX_H)
  noteBox:SetFrameLevel(frame:GetFrameLevel() + 5)
  noteBox:SetAutoFocus(false)
  noteBox:SetMaxLetters(60)
  noteBox:SetFontObject(MOTA:Font("kitSmall"))
  noteBox:SetTextColor(MOTA:RGB(INK))
  noteBox:SetTextInsets(7, 7, 0, 0)
  Kit:Fill(noteBox, "FBF4E1", "F0E2BE")
  Kit:Outline(noteBox, "6E4F17", 0.6)
  noteBox:SetScript("OnEscapePressed", noteBox.ClearFocus)
  noteBox:SetScript("OnEnterPressed", function() Prompt:Answer("other", noteBox:GetText()) end)

  -- Confirm: the herald's blue button, its label laid on live.
  local box = B.buttons.blue
  confirm = CreateFrame("Button", nil, frame)
  confirm:SetSize(box.w, box.h)
  confirm:SetFrameLevel(frame:GetFrameLevel() + 5)
  confirm.art = confirm:CreateTexture(nil, "ARTWORK")
  confirm.glow = confirm:CreateTexture(nil, "HIGHLIGHT")
  confirm.glow:SetBlendMode("ADD")
  confirm.glow:SetAlpha(0.25)
  confirm.label = spaced(confirm, "kitButton", 0.16)
  confirm:SetScript("OnClick", function()
    if chosen then Prompt:Answer(chosen, chosen == "other" and noteBox:GetText() or nil) end
  end)

  -- The list opens under the chooser, on the parchment: the banner grows to hold it.
  list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", chooser, "BOTTOMLEFT", 0, -2)
  list:SetFrameLevel(frame:GetFrameLevel() + 20)
  list:EnableMouse(true)
  Kit:Fill(list, "F4EAD0", "E6D5AC")
  Kit:Outline(list, "6E4F17", 0.8)
  rows = {}
  for i = 1, MAX_ROWS do
    local b = CreateFrame("Button", nil, list)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -1 - (i - 1) * ROW_H)
    b.glow = b:CreateTexture(nil, "HIGHLIGHT") -- the skin's accent ink, faint
    b.glow:SetAllPoints()
    b.text = Kit:Text(b, "kitSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 9, 0)
    rows[i] = b
  end
  list:Hide()
  frame.chooser, frame.noteBox, frame.confirm, frame.list, frame.rows = chooser, noteBox, confirm, list, rows

  -- A change of skin redraws the banner in the new one.
  Kit:Track(function() fit() end)
end

---------------------------------------------------------------------------
-- Asking
---------------------------------------------------------------------------

function Prompt:Update()
  local move = MOTA.Bank:Pending()[1]
  if not move or InCombatLockdown() then
    if frame then frame:Hide() end
    return
  end
  if not frame then build() end
  local left = #MOTA.Bank:Pending() - 1
  eyebrow:SetText(((move.who and (MOTA:Short(move.who) .. "'s entry · ") or "The Treasury asks · ") .. MOTA:Money(move.amt) .. (left > 0 and (" · " .. left .. " more after this") or "")):upper(), INK)
  title:SetText(move.io == "d" and "Why this deposit?" or "Why this withdrawal?")
  local options = REASONS[move.io] or REASONS.d
  -- Entered in the Ring and not yet paid: the fee comes first.
  local cur = MOTA.Ring and MOTA.Ring:Current()
  if move.io == "d" and not move.who and cur and cur.stage == "signup" and MOTA.Ring:IsEntered(cur) and not cur.paid[MOTA.me] then
    local first = { { "ring_fee", "Ring entry fee" } }
    for _, r in ipairs(options) do
      if r[1] ~= "ring_fee" then first[#first + 1] = r end
    end
    options = first
  end
  for i, b in ipairs(rows) do
    local reason = options[i]
    b:SetShown(reason ~= nil)
    if reason then
      b.text:SetText(reason[2])
      b:SetScript("OnClick", function() choose(reason[1]) end)
    end
  end
  list:SetHeight(#options * ROW_H + 2)
  if not frame:IsShown() or not chosen then choose(nil) else fit() end
  frame:Show()
end

function Prompt:Answer(reason, note)
  note = note and note:gsub("^%s+", ""):gsub("%s+$", "") or nil
  if reason == "other" and (not note or note == "") then
    MOTA:Print("Please say what it was for.")
    return nil
  end
  local rec, err = MOTA.Bank:Answer(reason, note)
  if not rec then
    MOTA:Print("That wasn't recorded:", tostring(err))
    return nil
  end
  MOTA:Print("Recorded in the guild's book:", MOTA:Money(rec.d.amt), rec.d.io == "d" and "deposit" or "withdrawal",
    "· " .. (note or self:LabelFor(rec.d.io, reason)) .. (MOTA.Ledger:Get().open and ". It's on the Treasury page." or ". The ledger starts once a King opens the books."))
  chosen = nil
  self:Update()
  return rec
end

function Prompt:IsShown()
  return frame ~= nil and frame:IsShown()
end

MOTA:Listen("BANK_PROMPT", function() Prompt:Update() end)
MOTA:On("PLAYER_REGEN_DISABLED", function() Prompt:Update() end)
MOTA:On("PLAYER_REGEN_ENABLED", function() Prompt:Update() end)
