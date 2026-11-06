-- Ministry of the Allied: the settings panel (Extras board), in the game's
-- own options: Escape > Options > AddOns > Ministry of the Allied.
-- The window's gear, a right-click on the minimap seal and /mota settings
-- open it too. Switches for features not built yet are shown greyed out.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media

local ROWS = {
  { key = "herald", label = "Herald pop-ups", small = "Announce votes, laws and defections live" },
  { key = "fanfare", label = "Fanfare", small = "Play the game's own trumpet with each herald" },
  { key = "glow", label = "District glow", small = "Light your district on the world map", later = true },
  { key = "cards", label = "Citizen cards", small = "Show the card when hovering guild members", later = true },
  { key = "heraldSize", label = "Herald size", small = "How grand the pop-ups appear", choice = true },
}

local panel, page

local function piece(name, layer, dx, dy)
  return UI:Piece(page, name, layer, nil, dx, dy, page)
end

local function play(kit)
  if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

-- A switch: the on and off pictures, drawn where this row's switch goes.
local function buildSwitch(i, row)
  local slot = M.slots["sw" .. i]
  local b = CreateFrame("Button", nil, page)
  UI:AtSlot(b, "sw" .. i, 0, 0, page)
  b:SetSize(slot.w, slot.h)
  b.on = piece("swOn", "ARTWORK", 0, slot.y - M.slots.sw1.y)
  b.off = piece("swOff", "ARTWORK", 0, slot.y - M.slots.sw4.y)
  function b:Update()
    local v = MOTA.db.settings[row.key] and true or false
    self.on:SetShown(v)
    self.off:SetShown(not v)
  end
  b:SetScript("OnClick", function(self)
    if row.later then return end
    MOTA.db.settings[row.key] = not MOTA.db.settings[row.key]
    play(MOTA.db.settings[row.key] and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
    self:Update()
  end)
  if row.later then
    b.on:SetAlpha(0.45)
    b.off:SetAlpha(0.45)
  end
  return b
end

-- Modest or Royal.
local function buildChoice()
  piece("segBox", "BORDER")
  local buttons = {}
  for _, opt in ipairs({ { "small", "seg-modest", "segModest" }, { "full", "seg-royal", "segRoyal" } }) do
    local value, slotName, prefix = opt[1], opt[2], opt[3]
    local b = CreateFrame("Button", nil, page)
    local s = UI:AtSlot(b, slotName, 0, 0, page)
    b:SetSize(s.w, s.h)
    b.on = piece(prefix .. "On", "ARTWORK")
    b.off = piece(prefix .. "Off", "ARTWORK")
    function b:Update()
      local chosen = MOTA.db.settings.heraldSize == value
      self.on:SetShown(chosen)
      self.off:SetShown(not chosen)
    end
    b:SetScript("OnClick", function()
      MOTA.db.settings.heraldSize = value
      play("IG_MAINMENU_OPTION_CHECKBOX_ON")
      for _, other in ipairs(buttons) do other:Update() end
    end)
    buttons[#buttons + 1] = b
  end
  return buttons
end

local function build()
  panel = CreateFrame("Frame", "MinistryOfTheAlliedOptions")
  panel.name = "Ministry of the Allied"
  page = CreateFrame("Frame", nil, panel)
  local root = M.slots.settings
  page:SetSize(root.w, root.h)
  page:SetPoint("TOP", panel, "TOP", 0, -12)
  piece("settingsPage", "BACKGROUND")

  panel.controls = {}
  for i, row in ipairs(ROWS) do
    if i < #ROWS then piece("rowLine", "BORDER", 0, M.slots["row" .. i].y - M.slots.row1.y) end
    local label = MOTA:Tracked(page, "setLabel", "2A1F14", 0.08)
    UI:AtSlot(label, "slabel" .. i, 0, 0, page)
    label:SetText(row.label:upper())
    local small = page:CreateFontString(nil, "OVERLAY")
    small:SetFontObject(MOTA:Font("setSmall"))
    small:SetTextColor(MOTA:RGB("5E4B33"))
    small:SetJustifyH("LEFT")
    UI:AtSlot(small, "ssmall" .. i, 0, 0, page)
    small:SetText(row.small .. (row.later and " · later" or ""))
    if row.later then
      label:SetAlpha(0.5)
      small:SetAlpha(0.6)
    end
    if row.choice then
      for _, b in ipairs(buildChoice()) do panel.controls[#panel.controls + 1] = b end
    else
      panel.controls[#panel.controls + 1] = buildSwitch(i, row)
    end
  end

  -- Fit the page to the space the game's options give it.
  local function fitPage()
    local w, h = panel:GetWidth(), panel:GetHeight()
    if w and w > 50 and h and h > 50 then
      page:SetScale(math.min((w - 20) / root.w, (h - 24) / root.h, 1.4))
    end
  end
  panel:SetScript("OnShow", function()
    fitPage()
    for _, c in ipairs(panel.controls) do c:Update() end
  end)
  panel:SetScript("OnSizeChanged", fitPage)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    UI.settingsCategory = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

function UI:OpenSettings()
  if not panel then build() end
  if InCombatLockdown() then
    return MOTA:Print("The game doesn't let add-ons open its options during combat. Try again afterwards.")
  end
  if self.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(self.settingsCategory:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
  else
    MOTA:Print("Open the game's options (Escape > Options), then AddOns > Ministry of the Allied.")
  end
end

MOTA:On("PLAYER_LOGIN", function()
  if not panel then build() end
end)
