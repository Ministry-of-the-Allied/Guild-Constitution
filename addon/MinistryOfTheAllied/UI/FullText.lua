-- Any text in our windows that is cut short ("Kíng Atwood & Kin...") shows its
-- full words in a tooltip while the mouse is over it (Max, 9 Nov).
-- The text itself never takes the mouse, so buttons and rows under it work as
-- before: a light watcher looks for a cut-short line under the cursor instead.
local _, MOTA = ...

local ROOTS = {
  "MinistryOfTheAlliedFrame",
  "MinistryOfTheAlliedOptions",
  "MinistryOfTheAlliedBankPrompt",
  "MinistryOfTheAlliedCrests",
}

local strings, showing = {}, nil
local sinceScan, sinceCheck = 99, 0

local function collect(frame, out, depth)
  if depth > 30 or not frame:IsVisible() then return end
  for _, r in ipairs({ frame:GetRegions() }) do
    if r.IsTruncated and r.GetObjectType and r:GetObjectType() == "FontString" then out[#out + 1] = r end
  end
  for _, child in ipairs({ frame:GetChildren() }) do collect(child, out, depth + 1) end
end

local function rescan()
  local out = {}
  for _, name in ipairs(ROOTS) do
    local f = _G[name]
    if f and f.IsVisible and f:IsVisible() then collect(f, out, 0) end
  end
  strings = out
end

local function hide()
  if showing and GameTooltip:GetOwner() == showing.owner then GameTooltip:Hide() end
  showing = nil
end

local function under()
  for i = #strings, 1, -1 do -- later regions sit on top
    local s = strings[i]
    if s:IsVisible() and s:IsMouseOver() and s:IsTruncated() then return s end
  end
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function(_, elapsed)
  sinceScan, sinceCheck = sinceScan + elapsed, sinceCheck + elapsed
  if sinceCheck < 0.1 then return end
  sinceCheck = 0
  if sinceScan > 1 then sinceScan = 0; rescan() end
  if #strings == 0 then hide(); return end
  local s = under()
  if s == (showing and showing.text) then return end
  hide()
  if not s then return end
  -- A tooltip someone else is showing (a pin, a button's own hint) wins.
  if GameTooltip:IsShown() then return end
  local owner = s:GetParent()
  GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
  GameTooltip:SetText(s:GetText() or "", 1, 1, 1, 1, true)
  GameTooltip:Show()
  showing = { text = s, owner = owner }
end)

MOTA.FullText = { Rescan = rescan }
