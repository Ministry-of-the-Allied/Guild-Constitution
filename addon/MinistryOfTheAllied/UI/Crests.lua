-- Ministry of the Allied: the crest finder.
-- The plan says to use the game's own Alliance crest if it has one, before
-- shipping our picture (ADDON_PLAN.md, section 3). The game can't list its
-- textures, so this shows a few likely ones to look at:
--
--   /mota crests        show the candidates, numbered
--   /mota crest <n>     try candidate n in the window's corner
--   /mota crest ours    go back to our own crest
--
-- Atlases the game doesn't have are skipped. Texture files can't be checked
-- that way, so an empty box just means the game doesn't have that one.

local _, MotA = ...
local UI = MotA.UI

UI.crestCandidates = {
  { file = [[Interface\Timer\Alliance-Logo]] },
  { file = [[Interface\TargetingFrame\UI-PVP-Alliance]] },
  { file = [[Interface\FriendsFrame\PlusManz-Alliance]] },
  { file = [[Interface\PVPFrame\PVP-Currency-Alliance]] },
  { file = [[Interface\WorldStateFrame\AllianceIcon]] },
  { file = [[Interface\BattlefieldFrame\Battleground-Alliance]] },
  { file = [[Interface\Icons\INV_BannerPVP_02]] },
  { file = [[Interface\Icons\Achievement_PVP_A_A]] },
  { file = [[Interface\Icons\INV_Misc_Tournaments_Symbol_Human]] },
  { atlas = "bfa-landingbutton-alliance-up" },
  { atlas = "AllianceEmblem" },
  { atlas = "AllianceSymbol" },
  { atlas = "Alliance-Logo" },
  { atlas = "QuestPortraitIcon-Alliance" },
  { atlas = "MountJournalIcons-Alliance" },
  { atlas = "alliance_icon_and_flag-icon" },
  { atlas = "nameplates-icon-flag-alliance" },
  { atlas = "communities-create-button-wow-alliance" },
  { atlas = "ui-frame-alliancecrest" },
  { atlas = "honorsystem-icon-faction-alliance" },
}

local function exists(c)
  if c.atlas then return C_Texture.GetAtlasInfo(c.atlas) ~= nil end
  return true -- can't tell for files
end

local panel

local function build()
  local list = {}
  for i, c in ipairs(UI.crestCandidates) do
    if exists(c) then list[#list + 1] = i end
  end
  local cols, size, gap = 5, 96, 14
  local rows = math.ceil(#list / cols)

  panel = CreateFrame("Frame", "MinistryOfTheAlliedCrests", UIParent)
  panel:SetSize(cols * (size + gap) + gap, rows * (size + 34) + 70)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("DIALOG")
  panel:EnableMouse(true)
  panel:SetMovable(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  tinsert(UISpecialFrames, "MinistryOfTheAlliedCrests")

  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.08, 0.17, 0.95)
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -12)
  title:SetText("The game's own crests")
  local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
  hint:SetText("/mota crest <number> tries one in the window · /mota crest ours goes back · Escape closes")

  for k, i in ipairs(list) do
    local c = UI.crestCandidates[i]
    local col, row = (k - 1) % cols, math.floor((k - 1) / cols)
    local x, y = gap + col * (size + gap), -(56 + row * (size + 34))
    local box = panel:CreateTexture(nil, "BORDER")
    box:SetColorTexture(1, 1, 1, 0.06)
    box:SetSize(size, size)
    box:SetPoint("TOPLEFT", x, y)
    local t = panel:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetPoint("TOPLEFT", x, y)
    if c.atlas then t:SetAtlas(c.atlas) else t:SetTexture(c.file) end
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOP", t, "BOTTOM", 0, -3)
    label:SetWidth(size + gap)
    label:SetText(i .. "  " .. (c.atlas or c.file:match("[^\\]+$")))
  end
  local skipped = #UI.crestCandidates - #list
  if skipped > 0 then
    MotA:Print(skipped, "of the candidate atlases aren't in this client, so they're not shown.")
  end
end

function UI:ShowCrests()
  if not panel then build() end
  panel:Show()
end

function UI:ChooseCrest(arg)
  if arg == "ours" or arg == "" then
    MotA.db.crest = nil
    MotA:Print("Back to our own crest.")
  else
    local c = self.crestCandidates[tonumber(arg) or 0]
    if not c then return MotA:Print("There's no candidate", arg .. ". /mota crests shows them.") end
    if not exists(c) then return MotA:Print("This client doesn't have that one.") end
    MotA.db.crest = c
    MotA:Print("Trying crest", arg, "in the window. /mota crest ours goes back.")
  end
  self:Build()
  self:ApplyCrest()
  self.window:Show()
end
