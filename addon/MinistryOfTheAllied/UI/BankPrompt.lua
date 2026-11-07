-- Ministry of the Allied: "What was it for?" (ADDON_SPEC.md, section 10.7).
-- A herald's scroll with a list of reasons. It stays on screen until answered,
-- with no close button, and comes back after a reload. It only blocks itself,
-- and steps aside during combat.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Kit = MOTA.Kit
local Prompt = {}
MOTA.BankPrompt = Prompt

local REASONS = {
  d = {
    { "tax", "Tax" }, { "ring_fee", "Ring entry fee" }, { "fine", "Treasury fine" }, { "donation", "Donation" },
    { "party_sh", "Silverhand donation" }, { "party_ex", "Exchange donation" }, { "other", "Other" },
  },
  w = {
    { "supplies", "Guild supplies" }, { "ring_prize", "Ring prize" },
    { "party_sh", "Silverhand funds" }, { "party_ex", "Exchange funds" }, { "other", "Other" },
  },
}
Prompt.REASONS = REASONS

local SCALE = 0.8 -- as a Royal herald
local SEAL_FOR = { party_sh = "silverhand", party_ex = "exchange" }
local ROW_H = 26
local MAX_ROWS = 7

local frame, chooser, chooserText, list, rows, noteBox, confirm, seals, eyebrow, title
local chosen

function Prompt:LabelFor(io, reason)
  for _, r in ipairs(REASONS[io] or {}) do
    if r[1] == reason then return r[2] end
  end
  return reason
end

local function showSeal(name)
  for key, t in pairs(seals) do t:SetShown(key == name) end
end

local function choose(reason)
  chosen = reason
  list:Hide()
  local move = MOTA.Bank:Pending()[1]
  chooserText:SetText(reason and Prompt:LabelFor(move and move.io, reason) or "Choose a reason")
  showSeal(SEAL_FOR[reason] or "official")
  local other = reason == "other"
  chooser:SetWidth(other and 100 or 377)
  noteBox:SetShown(other)
  if other then
    noteBox:SetText("")
    noteBox:SetFocus()
  end
  confirm:SetEnabled(reason ~= nil)
  confirm:SetAlpha(reason and 1 or 0.45)
end

local function build()
  local s = M.slots.herald
  frame = CreateFrame("Frame", "MinistryOfTheAlliedBankPrompt", UIParent)
  frame:SetSize(s.w, s.h)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -110)
  frame:SetFrameStrata("DIALOG")
  frame:SetScale(SCALE)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  UI:Piece(frame, "heraldBg", "BACKGROUND", nil, nil, nil, frame)
  seals = {}
  for _, name in ipairs({ "official", "exchange", "silverhand" }) do
    seals[name] = UI:Piece(frame, "hseal_" .. name, "ARTWORK", nil, nil, nil, frame)
  end

  eyebrow = MOTA:Tracked(frame, "eyebrow", "7A5719", 0.32)
  UI:AtSlot(eyebrow, "heyebrow", 0, 1, frame)
  title = frame:CreateFontString(nil, "OVERLAY")
  title:SetFontObject(MOTA:Font("heraldTitle"))
  title:SetTextColor(MOTA:RGB("1B3570"))
  title:SetJustifyH("LEFT")
  title:SetWidth(377)
  UI:AtSlot(title, "htitle", 0, 0, frame)

  local rowY = M.slots.hbody.y + 2
  chooser = CreateFrame("Button", nil, frame)
  chooser:SetSize(377, 28)
  chooser:SetPoint("TOPLEFT", frame, "TOPLEFT", 130, -rowY)
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
  chooser:SetScript("OnClick", function() list:SetShown(not list:IsShown()) end)

  noteBox = CreateFrame("EditBox", nil, frame)
  noteBox:SetSize(269, 28)
  noteBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 238, -rowY)
  noteBox:SetAutoFocus(false)
  noteBox:SetMaxLetters(60)
  noteBox:SetFontObject(MOTA:Font("kitSmall"))
  noteBox:SetTextColor(MOTA:RGB("2A1F14"))
  noteBox:SetTextInsets(7, 7, 0, 0)
  Kit:Fill(noteBox, "FBF4E1", "F0E2BE")
  Kit:Outline(noteBox, "6E4F17", 0.6)
  noteBox:SetScript("OnEscapePressed", noteBox.ClearFocus)
  noteBox:SetScript("OnEnterPressed", function() Prompt:Answer("other", noteBox:GetText()) end)

  confirm = Kit:Button(frame, 108, 36, "Confirm", "blue", function()
    if chosen then Prompt:Answer(chosen, chosen == "other" and noteBox:GetText() or nil) end
  end)
  UI:AtSlot(confirm, "hbutton", 0, 0, frame)

  -- The list opens under the scroll, above everything else.
  list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", chooser, "BOTTOMLEFT", 0, -2)
  list:SetWidth(377)
  list:SetFrameLevel(frame:GetFrameLevel() + 20)
  list:EnableMouse(true)
  Kit:Fill(list, "F4EAD0", "E6D5AC")
  Kit:Outline(list, "6E4F17", 0.8)
  rows = {}
  for i = 1, MAX_ROWS do
    local b = CreateFrame("Button", nil, list)
    b:SetSize(375, ROW_H)
    b:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -1 - (i - 1) * ROW_H)
    local h = b:CreateTexture(nil, "HIGHLIGHT")
    h:SetColorTexture(0.11, 0.21, 0.44, 0.15)
    h:SetAllPoints()
    b.text = Kit:Text(b, "kitSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 9, 0)
    rows[i] = b
  end
  list:Hide()
end

function Prompt:Update()
  local move = MOTA.Bank:Pending()[1]
  if not move or InCombatLockdown() then
    if frame then frame:Hide() end
    return
  end
  if not frame then build() end
  local left = #MOTA.Bank:Pending() - 1
  eyebrow:SetText(("The Treasury asks · " .. MOTA:Money(move.amt) .. (left > 0 and (" · " .. left .. " more after this") or "")):upper())
  title:SetText(move.io == "d" and "What was this deposit for?" or "What was this withdrawal for?")
  local options = REASONS[move.io] or REASONS.d
  for i, b in ipairs(rows) do
    local reason = options[i]
    b:SetShown(reason ~= nil)
    if reason then
      b.text:SetText(reason[2])
      b:SetScript("OnClick", function() choose(reason[1]) end)
    end
  end
  list:SetHeight(#options * ROW_H + 2)
  if not frame:IsShown() or not chosen then choose(nil) end
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
    "· " .. (note or self:LabelFor(rec.d.io, reason)) .. ". The Treasury page will list these; /mota book shows them for now.")
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
