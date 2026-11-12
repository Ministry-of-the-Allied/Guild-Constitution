-- Ministry of the Allied: the Admin Controls window (Max, 10 Nov).
-- The Crown's own window: a knob to the left of the gear opens it, in a window of its
-- own on the left of the main one. It is laid out like the Settings page, on the same
-- parchment, and holds every /mota command as a button, so nothing has to be typed.
--
-- The rows come from MOTA.Commands.list (Commands.lua), so a command added there
-- shows up here by itself, with a Run button and a box for its words. SPEC below says
-- how a command is better shown: the choices to press, which section it sits in.
-- Hover anything for the same description /mota help shows (one source: the command's
-- own help text). Results appear in chat, as when the command is typed.
--
-- Announce New Version sits at the top: one press becomes "Are You Sure?", a second
-- sends a herald to the guild saying a new update is out. Only the Crown's message is
-- believed (the receiving side checks who sent it).

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Kit = MOTA.Kit
local Admin = {}
MOTA.AdminControls = Admin

local BLUE = "1B3570"
local ASK_FOR = 5 -- seconds "Are You Sure?" waits before it goes back

---------------------------------------------------------------------------
-- How each command is shown
---------------------------------------------------------------------------

-- Sections, in order. A command not named here goes in "More commands".
local SECTIONS = {
  { title = "Government and elections",
    "ballot", "contest", "noconfidence", "justice", "ring", "refunds", "district", "alts" },
  { title = "Treasury", "books" },
  { title = "Games and honours", "games", "lottery", "hunt", "honour", "honours" },
  -- party quest markers (ADDON_SPEC.md 10.18): /mota marker split into a row per part (Max, 12 Nov)
  { title = "NPC markers", "marker" },
  { title = "Records and sync", "sync", "who", "missing", "test", "book", "probe", "debug" },
  { title = "Look and sound",
    "skin", "scale", "minimap", "settings", "voice", "fanfare", "herald", "heralds", "throne",
    "crests", "crest", "constitution" },
  { title = "Help", "help" },
}
local MORE = "More commands"

-- choices: { button label, the words sent }. input = false takes the words box away
-- (nothing to type); a command with no choices and no usage is a lone Run button.
-- run: the Run button's label.
local SPEC = {
  skin = { choices = { { "Crown", "crown" }, { "Silverhand", "silverhand" }, { "Exchange", "exchange" },
    { "Ministry", "ministry" }, { "Mine", "" } }, input = false },
  voice = { choices = { { "Status", "" }, { "On", "on" }, { "Off", "off" }, { "Stop", "stop" },
    { "Next", "next" }, { "Reset", "reset" } }, input = false },
  ballot = { choices = { { "Open Hall", "" }, { "The count", "count" } }, input = false },
  probe = { choices = { { "Report", "" }, { "Limits", "limits" }, { "Bank", "bank" }, { "Map", "map" } }, input = false },
  contest = { choices = { { "Status", "" }, { "Advance", "advance" } } },
  books = { choices = { { "Open books", "open" } }, input = false },
  noconfidence = { choices = { { "Status", "" }, { "Vote yes", "yes" } }, input = false },
  hunt = { choices = { { "Status", "" }, { "Unmark", "unmark" }, { "Discard", "discard" }, { "End", "end" },
    { "Glow", "glow" } } },
  lottery = { choices = { { "Status", "" }, { "Draw", "draw" }, { "Cancel", "cancel" } } },
  justice = { choices = { { "Status", "" } } },
  games = { choices = { { "Log", "" } } },
  honours = { choices = { { "Roll", "" } } },
  district = { choices = { { "Status", "" } } },
  refunds = { choices = { { "Who's owed", "" } } },
  scale = { choices = { { "0.7", "0.7" }, { "0.85", "0.85" }, { "1.0", "1" }, { "Default", "" } } },
  herald = { choices = { { "1", "1" }, { "2", "2" }, { "3", "3" }, { "All", "" } }, input = false },
  heralds = { choices = { { "Show all", "all" } } },
  fanfare = { choices = { { "List", "" } } },
  throne = { choices = { { "Preview on", "preview" }, { "Preview off", "preview off" } }, input = false },
  crest = { choices = { { "Ours", "ours" } } },
  -- /mota marker, one row per part (rows): sub is the word after "marker". A choice's
  -- label and words can be functions, read when it is pressed (the test's Off / On).
  marker = { rows = {
    { sub = "", usage = "", help = "Whether markers are on, the far mode, how many you can see, and the nameplates. Help says what the colours and choices mean.",
      choices = { { "Status", "" }, { "Help", "help" }, { "List", "list" }, { "Probe", "probe" } }, input = false },
    { sub = "test", usage = "[look] [?]", help = "A marker on your target, on your screen only (nothing is sent). Off takes it away and becomes On, which brings the same marker back.",
      choices = { { "Silverhand", "sh" }, { "Exchange", "ex" }, { "Crown", "crown" }, { "Ministry", "ministry" }, { "?", "crown ?" },
        { function() return MOTA.Markers:Testing() and "Off" or "On" end,
          function() return MOTA.Markers:Testing() and "off" or "on" end } } },
    { sub = "add", usage = "sh|ex|all [?]", help = "Marks your target for a party (the Crown): stand beside the NPC. With ?, a quest to hand in.",
      choices = { { "Silverhand", "sh" }, { "Exchange", "ex" }, { "Everyone", "all" }, { "SH ?", "sh ?" }, { "EX ?", "ex ?" }, { "All ?", "all ?" } }, input = false },
    { sub = "clear", usage = "[npc ID]", help = "Takes the mark off your target, or off an NPC by its ID (the Crown).",
      choices = { { "Target", "" } } },
    { sub = "scale", usage = function() return MOTA.Markers.UI.RangeText("scale") end, help = "The markers and the names on the nameplates, bigger or smaller together (1 is as drawn).",
      choices = { { "0.8", "0.8" }, { "1.2", "1.2" }, { "1.5", "1.5" }, { "Default", "default" } } },
    { sub = "namesize", usage = function() return MOTA.Markers.UI.RangeText("namesize") end, help = "The names' font size on the nameplates (16 unless changed).",
      choices = { { "14", "14" }, { "18", "18" }, { "Default", "default" } } },
    { sub = "size", usage = function() return MOTA.Markers.UI.RangeText("size") end, help = "The marker's height (44 unless changed).", choices = { { "Default", "default" } } },
    { sub = "lift", usage = function() return MOTA.Markers.UI.RangeText("lift") end, help = "How far the marker stands above the nameplate or the name (18 unless changed).", choices = { { "Default", "default" } } },
    { sub = "namey", usage = function() return MOTA.Markers.UI.RangeText("namey") end, help = "How high the names stand on the nameplates (0 unless changed).", choices = { { "Default", "default" } } },
  } },
}

-- A choice's label or words: a word, or a function that gives it when asked.
local function now(v) if type(v) == "function" then return v() end return v end
local live = {} -- buttons whose label changes (the test's Off / On): relabelled when the markers change

local function sectionOf(name)
  for _, s in ipairs(SECTIONS) do
    for _, n in ipairs(s) do
      if n == name then return s.title end
    end
  end
  return MORE
end

---------------------------------------------------------------------------
-- Layout, from the Settings page
---------------------------------------------------------------------------

local PARCH = M.slots.parch
local LEFT, TOP = 34, 20 -- the page's place on the parchment, as Settings has it
local WIDTH, HEIGHT = PARCH.w - 60, PARCH.h - 42
local EYEBROW_Y = M.slots.eyebrow.y - PARCH.y - TOP
local HEADING_Y = M.slots.heading.y - PARCH.y - TOP
local DIVIDER_Y = M.slots.divider.y - PARCH.y
local LIST_Y = M.slots.divider.y + M.slots.divider.h - PARCH.y - TOP + 4
local FOOT_H = 30
local LIST_H = HEIGHT - FOOT_H - 6 - LIST_Y
local BAR_W, BAR_GAP = 10, 14
local LIST_W = WIDTH - BAR_W - BAR_GAP
local ROW_H, GROUP_H, WHEEL = 55, 28, 40
local LABEL_W = 250    -- the command's name and usage, on the left
local BTN_H = 28

local frame, scroll, child, bar, thumb, footText
local rows, built = {}, false
local controls = {} -- { name, label, button, box }: every press-able control (for the sim)
local announce, asking, askTimer -- the button, whether it says Are You Sure?, and the timer that takes it back

local function isCrown()
  return MOTA.me ~= nil and MOTA:IsCrown(MOTA.me)
end

local function play(kit)
  if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

-- The tooltip: the command as typed, then its description, word for word what
-- /mota help shows.
local function tip(owner, title, text)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(title, 1, 0.95, 0.77)
  if text and text ~= "" then GameTooltip:AddLine(text, 1, 1, 1, true) end
  GameTooltip:Show()
end

local function hover(region, title, text)
  region:SetScript("OnEnter", function(self) tip(self, title, text) end)
  region:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function typed(c)
  local head = "/mota " .. c.name .. ((c.sub and c.sub ~= "") and " " .. c.sub or "")
  return head .. (c.usage ~= "" and " " .. c.usage or "")
end

-- Runs a row's command with its words (a part's own word first, for /mota marker's rows).
local function runRow(c, words)
  words = words or ""
  if c.sub and c.sub ~= "" then words = strtrim(c.sub .. " " .. words) end
  MOTA.Commands:Run(c.name, words)
end

-- A dotted rule along a row's foot.
local function rule(parent, y, w)
  local t = parent:CreateTexture(nil, "BORDER")
  Kit:Solid(t, "6E4F17", 0.22)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
  t:SetSize(w, 1)
end

-- A small edit box for the words that follow the command.
local function wordsBox(parent, w)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(w, 26)
  e:SetAutoFocus(false)
  e:SetFontObject(MOTA:Font("kitSmall"))
  e:SetTextColor(MOTA:RGB("2A1F14"))
  e:SetTextInsets(7, 7, 0, 0)
  Kit:Fill(e, "FBF4E1", "F0E2BE")
  Kit:Outline(e, "6E4F17", 0.6)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  return e
end

-- One row for one command. Returns the row and its height: a command whose choices
-- don't fit in a line beside the words box and Run stacks them in two lines, and the
-- row grows to hold them. Each button is as wide as its (letter-spaced) label needs.
local PAD, MIN_W, GAP = 24, 56, 6
local TALL_H, TALL_BTN = 64, 24

local function buildRow(parent, c, y, last)
  local spec = c.spec or SPEC[c.name] or {}
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(LIST_W, ROW_H)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
  row:EnableMouse(true)
  hover(row, typed(c), c.help)

  local label = MOTA:Tracked(row, "setLabel", "2A1F14", 0.08)
  label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -11)
  label:SetText(("/mota " .. c.name .. ((c.sub and c.sub ~= "") and " " .. c.sub or "")):upper())
  local small = row:CreateFontString(nil, "OVERLAY")
  small:SetFontObject(MOTA:Font("setSmall"))
  small:SetTextColor(MOTA:RGB("5E4B33"))
  small:SetJustifyH("LEFT")
  small:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -29)
  small:SetWidth(LABEL_W)
  small:SetWordWrap(false)
  small:SetText(c.usage ~= "" and c.usage or "no words needed")

  local choices = spec.choices or {}
  local wantsWords = spec.input
  if wantsWords == nil then wantsWords = (c.usage ~= "") end
  if #choices == 0 and not wantsWords then choices = { { "Run", "" } } end

  -- the choices first, each sized to its label, to know whether they fit in one line
  local btns, widths = {}, {}
  for i, ch in ipairs(choices) do
    local lab, words = ch[1], ch[2]
    local b
    b = Kit:Button(row, MIN_W, BTN_H, now(lab), (lab == "Run") and "blue" or "gold", function()
      play("IG_MAINMENU_OPTION_CHECKBOX_ON")
      runRow(c, now(words))
      if type(lab) == "function" and b.SetLabel then b:SetLabel(lab()) end
    end)
    if type(lab) == "function" then live[#live + 1] = { button = b, label = lab } end
    btns[i] = b
    widths[i] = math.max(MIN_W, math.ceil((b.label:GetWidth() or 0) + PAD))
  end
  local function span(from, to)
    local sum = 0
    for i = from, to do sum = sum + widths[i] + (i > from and GAP or 0) end
    return sum
  end

  -- from the right: the Run button, the words box, then the choices
  local x = LIST_W
  local boxW = (#choices > 0) and 130 or 250
  local avail = (x - (wantsWords and (56 + 8 + boxW + 8) or 0)) - LABEL_W - 16
  local lines = { { 1, #choices } }
  if #choices > 1 and span(1, #choices) > avail then
    local half = math.ceil(#choices / 2)
    lines = { { 1, half }, { half + 1, #choices } }
    -- a narrower words box buys room before the buttons are squeezed
    if wantsWords and math.max(span(1, half), span(half + 1, #choices)) > avail then
      boxW = 100
      avail = avail + 30
    end
  end
  local rowH = (#lines > 1) and TALL_H or ROW_H
  local bh = (#lines > 1) and TALL_BTN or BTN_H
  row:SetSize(LIST_W, rowH)

  local box, run
  if wantsWords then
    local y0 = (rowH - BTN_H) / 2
    run = Kit:Button(row, 56, BTN_H, "Run", "blue", function()
      play("IG_MAINMENU_OPTION_CHECKBOX_ON")
      runRow(c, strtrim(box:GetText() or ""))
    end)
    x = x - 56
    run:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y0)
    hover(run, typed(c), c.help)
    controls[#controls + 1] = { name = c.name, sub = c.sub, label = "Run", button = run, row = row }
    box = wordsBox(row, boxW)
    x = x - 8 - boxW
    box:SetPoint("TOPLEFT", row, "TOPLEFT", x, -(y0 + 1))
    box:SetScript("OnEnterPressed", function(self)
      self:ClearFocus()
      runRow(c, strtrim(self:GetText() or ""))
    end)
    hover(box, typed(c), c.help)
    row.box = box
    x = x - 8
  end
  -- each line of buttons runs right to left, ending at x
  local top = (rowH - (#lines * bh + (#lines - 1) * 4)) / 2
  for li, ln in ipairs(lines) do
    local lx = x
    local ly = top + (li - 1) * (bh + 4)
    for i = ln[2], ln[1], -1 do
      local b = btns[i]
      b:SetSize(widths[i], bh)
      lx = lx - widths[i]
      b:SetPoint("TOPLEFT", row, "TOPLEFT", lx, -ly)
      lx = lx - GAP
      hover(b, typed(c), c.help)
      controls[#controls + 1] = { name = c.name, sub = c.sub, label = now(choices[i][1]), button = b, row = row }
    end
  end
  if not last then rule(row, rowH - 1, LIST_W) end
  return row, rowH
end

---------------------------------------------------------------------------
-- Announce New Version
---------------------------------------------------------------------------

local UPDATE_TEXT = "A new update for the add-on is available. Please download the newest update and restart your game."

-- The herald every member sees: the Crown's seal and the news, until closed.
local function showUpdateHerald()
  MOTA.Herald:Announce({
    seal = "crown", eyebrow = "By Royal Notice", title = "A new update is available",
    text = UPDATE_TEXT, stay = false, closeX = true,
    button = { label = "Dismiss", style = "quiet" },
  }, true)
end

-- Sends it: the Crown only, to the whole guild; the sender sees it too.
function Admin:SendUpdate()
  if not isCrown() then return false, "Only the Crown can announce a new version." end
  if not MOTA.guild then return false, "The guild roster hasn't loaded yet. Try again in a moment." end
  MOTA.Comm:Send(MOTA.Comm:Pack("UP", MOTA.VERSION), "GUILD")
  showUpdateHerald()
  return true
end

local lastHeard = {} -- sender -> when, so a repeated notice doesn't stack up heralds

MOTA.Comm:Handle("UP", function(self, sender, channel)
  if channel ~= "GUILD" then return end
  if not self:IsCrown(sender) then -- anyone else's notice is ignored
    self.stats.ignored = self.stats.ignored + 1
    return
  end
  local now = GetTime()
  if lastHeard[sender] and now - lastHeard[sender] < 60 then return end
  lastHeard[sender] = now
  showUpdateHerald()
end)

local function resetAnnounce()
  if not announce then return end
  if askTimer then askTimer:Cancel() askTimer = nil end
  asking = false
  announce:SetLabel("Announce New Version")
end

local function buildAnnounce(parent, y)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(LIST_W, ROW_H)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
  row:EnableMouse(true)
  local title, body = "Announce New Version",
    "Sends every guild member with the add-on a herald with the Crown's seal, telling them a new update is out and to restart their game."
  hover(row, title, body)
  local label = MOTA:Tracked(row, "setLabel", "2A1F14", 0.08)
  label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -11)
  label:SetText("A NEW VERSION")
  local small = row:CreateFontString(nil, "OVERLAY")
  small:SetFontObject(MOTA:Font("setSmall"))
  small:SetTextColor(MOTA:RGB("5E4B33"))
  small:SetJustifyH("LEFT")
  small:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -29)
  small:SetWidth(LABEL_W + 120)
  small:SetWordWrap(false)
  small:SetText("Tell the guild to update and restart their game")
  announce = Kit:Button(row, 220, BTN_H + 4, "Announce New Version", "gold", function(self)
    if not asking then
      asking = true
      self:SetLabel("Are You Sure?")
      askTimer = C_Timer.NewTimer(ASK_FOR, resetAnnounce)
      return
    end
    resetAnnounce()
    local ok, why = Admin:SendUpdate()
    if ok then
      play("IG_MAINMENU_OPTION_CHECKBOX_ON")
      MOTA:Print("The guild has been told a new update is available.")
    else
      MOTA:Print(why)
    end
  end)
  announce:SetPoint("TOPLEFT", row, "TOPLEFT", LIST_W - 220, -(ROW_H - BTN_H - 4) / 2)
  hover(announce, title, body)
  rule(row, ROW_H - 1, LIST_W)
  return row
end

---------------------------------------------------------------------------
-- Scrolling, as the Settings page does it
---------------------------------------------------------------------------

local function range()
  return math.max(0, (child:GetHeight() or 0) - LIST_H)
end

local function placeThumb()
  local r = range()
  bar:SetShown(r > 0)
  if r <= 0 then return end
  local h = math.max(30, LIST_H * LIST_H / (LIST_H + r))
  thumb:SetHeight(h)
  local at = (scroll:GetVerticalScroll() or 0) / r
  thumb:ClearAllPoints()
  thumb:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -(2 + at * (LIST_H - 4 - h)))
end

local function scrollTo(v)
  scroll:SetVerticalScroll(math.max(0, math.min(range(), v)))
  placeThumb()
end

local function cursorY()
  local _, y = GetCursorPosition()
  return y / (bar:GetEffectiveScale() or 1)
end

local function silver()
  return MOTA.skin and MOTA.skin.METAL == "silver"
end

local function buildBar(root)
  bar = CreateFrame("Button", nil, root)
  bar:SetSize(BAR_W, LIST_H)
  bar:SetPoint("TOPLEFT", root, "TOPLEFT", LIST_W + BAR_GAP, -LIST_Y)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  Kit:Solid(track, "6E4F17", 0.18)
  track:SetAllPoints()
  Kit:Outline(bar, "6E4F17", 0.4)
  thumb = CreateFrame("Button", nil, bar)
  thumb:SetWidth(BAR_W - 2)
  local left = thumb:CreateTexture(nil, "ARTWORK")
  left:SetPoint("TOPLEFT")
  left:SetPoint("BOTTOMRIGHT", thumb, "BOTTOM", 0, 0)
  local right = thumb:CreateTexture(nil, "ARTWORK")
  right:SetPoint("TOPLEFT", thumb, "TOP", 0, 0)
  right:SetPoint("BOTTOMRIGHT")
  Kit:Outline(thumb, "4A330C", 0.7)
  Kit:Track(function()
    local dark, light = "8A6420", "E9C979"
    if silver() then dark, light = "6B7483", "EEF2F6" end
    Kit:Gradient(left, dark, light, 1, 1, true)
    Kit:Gradient(right, light, dark, 1, 1, true)
  end)
  bar:SetScript("OnClick", function()
    local top = thumb:GetTop() or 0
    scrollTo(scroll:GetVerticalScroll() + (cursorY() > top and -LIST_H or LIST_H))
  end)
  thumb:SetScript("OnMouseDown", function(self)
    self.from, self.start = cursorY(), scroll:GetVerticalScroll()
    self:SetScript("OnUpdate", function()
      local free = LIST_H - 4 - self:GetHeight()
      if free <= 0 then return end
      scrollTo(self.start + (self.from - cursorY()) / free * range())
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

-- The commands, grouped: sections in order, then anything that has no section yet.
local function grouped()
  local by, titles = {}, {}
  for _, c in ipairs(MOTA.Commands.list) do
    local t = sectionOf(c.name)
    if not by[t] then by[t] = {} titles[#titles + 1] = t end
    local parts = SPEC[c.name] and SPEC[c.name].rows
    if parts then
      -- a command in parts: a row for each (/mota marker)
      for _, r in ipairs(parts) do
        table.insert(by[t], { name = c.name, sub = r.sub, usage = now(r.usage), help = r.help or c.help, spec = r })
      end
    else
      table.insert(by[t], c)
    end
  end
  local result = {}
  for _, s in ipairs(SECTIONS) do
    if by[s.title] then result[#result + 1] = { title = s.title, list = by[s.title] } end
  end
  if by[MORE] then result[#result + 1] = { title = MORE, list = by[MORE] } end
  return result
end

local function buildList()
  local y = 0
  local head = Kit:Label(child, "kitSection", BLUE, 0.22, "Guild notice")
  head:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(y + 10))
  y = y + GROUP_H
  rows[#rows + 1] = buildAnnounce(child, y)
  y = y + ROW_H
  for _, g in ipairs(grouped()) do
    local h = Kit:Label(child, "kitSection", BLUE, 0.22, g.title)
    h:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(y + 10))
    y = y + GROUP_H
    for i, c in ipairs(g.list) do
      local row, h = buildRow(child, c, y, i == #g.list)
      rows[#rows + 1] = row
      y = y + h
    end
  end
  child:SetHeight(y + 6)
  built = true
end

local function build()
  frame = CreateFrame("Frame", "MinistryOfTheAlliedAdmin", UIParent)
  frame:SetSize(PARCH.w, PARCH.h)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:Hide()
  tinsert(UISpecialFrames, "MinistryOfTheAlliedAdmin")

  -- the main window's parchment, whole
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  UI:SetPiece(bg, "parch", 0, 0, frame, { 0, 0 })
  Kit:Outline(frame, "6E4F17", 0.8)

  local root = CreateFrame("Frame", nil, frame)
  root:SetSize(WIDTH, HEIGHT)
  root:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT, -TOP)
  frame.root = root

  local eyebrow = MOTA:Tracked(root, "pageEyebrow", "7A5719", 0.32)
  eyebrow:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -EYEBROW_Y)
  eyebrow:SetText("THE CROWN ONLY · EVERY COMMAND")
  local heading = Kit:Text(root, "heading", BLUE)
  heading:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -HEADING_Y)
  heading:SetText("Admin Controls")
  local aside = Kit:Text(root, "kitItalic", "5E4B33", "RIGHT")
  aside:SetPoint("BOTTOMRIGHT", root, "TOPRIGHT", 0, -(DIVIDER_Y - TOP - 2))
  aside:SetText("Hover a control for what it does.\nResults appear in chat.")
  local divider = frame:CreateTexture(nil, "ARTWORK")
  local d = M.slots.divider
  UI:SetPiece(divider, "divider", 0, 0, frame, { d.x - PARCH.x, DIVIDER_Y })

  scroll = CreateFrame("ScrollFrame", nil, root)
  scroll:SetSize(LIST_W, LIST_H)
  scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -LIST_Y)
  child = CreateFrame("Frame", nil, scroll)
  child:SetSize(LIST_W, 1)
  scroll:SetScrollChild(child)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, delta) scrollTo(scroll:GetVerticalScroll() - delta * WHEEL) end)
  buildBar(root)

  local foot = CreateFrame("Frame", nil, root)
  foot:SetSize(WIDTH, FOOT_H)
  foot:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
  local line = foot:CreateTexture(nil, "BORDER")
  Kit:Solid(line, "6E4F17", 0.35)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT")
  line:SetPoint("TOPRIGHT")
  footText = Kit:Text(foot, "kitSmall", "5E4B33")
  footText:SetPoint("LEFT", foot, "LEFT", 0, -2)
  footText:SetWidth(WIDTH)
  footText:SetWordWrap(false)
  footText:SetText("Only the Crown sees this window. The same commands still work typed: /mota help.")

  frame:SetScript("OnHide", function()
    resetAnnounce()
    GameTooltip:Hide()
    if UI.knobAdmin then UI.knobAdmin.lit:Hide() end
  end)
  frame:SetScript("OnShow", function()
    if UI.knobAdmin then UI.knobAdmin.lit:Show() end
  end)
end

-- Docks the window on the main one's left, level with the parchment, at the same size.
-- The test's Off / On says what a press will do now.
MOTA:Listen("MARKERS_CHANGED", function()
  for _, l in ipairs(live) do
    if l.button.SetLabel then l.button:SetLabel(l.label()) end
  end
end)

function Admin:Dock()
  if not frame or not UI.window then return end
  frame:SetScale(UI.window:GetScale())
  frame:ClearAllPoints()
  frame:SetPoint("TOPRIGHT", UI.window, "TOPLEFT", -64, -PARCH.y)
end

-- open nil toggles. The window opens beside the main one, so that comes up too.
function UI:ShowAdmin(open)
  if not isCrown() then return end
  local win = self:Build()
  if not frame then build() end
  if open == nil then open = not frame:IsShown() end
  if not open then frame:Hide() return end
  if not win:IsShown() then win:Show() end
  if not built then buildList() end -- once, from every command Commands.lua has by now
  Admin:Dock()
  frame:Show()
  scrollTo(0)
end

function UI:HideAdmin()
  if frame and frame:IsShown() then frame:Hide() end
end

function Admin:Frame() return frame end
function Admin:Rows() return rows end
function Admin:Controls() return controls end
function Admin:Announce() return announce end
Admin.SPEC, Admin.SECTIONS = SPEC, SECTIONS
