-- Ministry of the Allied: herald pop-ups (ADDON_SPEC.md, section 10.2; Extras board).
-- A parchment scroll that unrolls at the top of the screen with a seal, a
-- heading line, a title, a line of text and a button. One at a time, each
-- for a few seconds or until dismissed, never during combat.
--
--   MOTA.Herald:Announce{ seal = "official" | "crown" | "exchange" | "silverhand" | "ring" | "treasury",
--     eyebrow = "...", title = "...", text = "...",
--     button = { label = "Vote now" | "Read it" | "Open" | "Dismiss",
--                style = "blue" | "quiet", page = <window page number>,
--                onPress = function, keep = true to stay open after a press },
--     stay = seconds on screen, or false to stay until closed; noFanfare = true;
--     closeX = true for a corner close button; onShow, onGone = functions }
--
-- /mota herald [1-3] shows the board's examples; /mota fanfare picks the sound.

local _, MOTA = ...
local UI = MOTA.UI
local M = MOTA.Media
local Herald = {}
MOTA.Herald = Herald

local SCALE = { full = 0.8, small = 0.56 } -- Royal, and Modest at 70% of it
local STAY = { full = 10, small = 8 }      -- seconds on screen
local TOP = 110                            -- distance from the top of the screen

local queue = {}
local frame, current, hideTimer

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
-- Building the scroll
---------------------------------------------------------------------------

local function piece(parent, name, layer)
  return UI:Piece(parent, name, layer, nil, nil, nil, frame)
end

local function build()
  local s = M.slots.herald
  frame = CreateFrame("Frame", "MinistryOfTheAlliedHerald", UIParent)
  frame:SetSize(s.w, s.h)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -TOP)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:Hide()

  frame.bg = piece(frame, "heraldBg", "BACKGROUND")
  frame.seals = {}
  for _, seal in ipairs({ "official", "crown", "exchange", "silverhand", "ring", "treasury" }) do
    frame.seals[seal] = piece(frame, "hseal_" .. seal, "ARTWORK")
  end

  frame.eyebrow = MOTA:Tracked(frame, "eyebrow", "7A5719", 0.32)
  UI:AtSlot(frame.eyebrow, "heyebrow", 0, -1, frame)
  frame.title = frame:CreateFontString(nil, "OVERLAY")
  frame.title:SetFontObject(MOTA:Font("heraldTitle"))
  MOTA.Kit:Track(function() frame.title:SetTextColor(MOTA:RGB(MOTA:Accent().INK)) end)
  frame.title:SetJustifyH("LEFT")
  UI:AtSlot(frame.title, "htitle", 0, 0, frame)
  frame.body = frame:CreateFontString(nil, "OVERLAY")
  frame.body:SetFontObject(MOTA:Font("heraldBody"))
  frame.body:SetTextColor(MOTA:RGB("2A1F14"))
  frame.body:SetJustifyH("LEFT")
  frame.body:SetJustifyV("TOP")
  UI:AtSlot(frame.body, "hbody", 0, 0, frame)
  if frame.body.SetMaxLines then frame.body:SetMaxLines(4) end -- the scroll grows past two (fit)

  -- One ready-made button per label and style; the right one is shown.
  frame.buttons = {}
  for _, label in ipairs(M.heraldButtons) do
    for _, style in ipairs({ "blue", "quiet" }) do
      local name = "hbtn_" .. style .. "_" .. label:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end):gsub("%W", "")
      local p = M.pieces[name]
      local b = CreateFrame("Button", nil, frame)
      b:SetSize(p.w, p.h)
      b:SetPoint("TOPLEFT", frame, "TOPLEFT", p.x, -p.y)
      b:SetFrameLevel(frame:GetFrameLevel() + 5)
      local t = b:CreateTexture(nil, "ARTWORK")
      t:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
      t:SetTexCoord(p.l, p.r, p.t, p.b)
      t:SetAllPoints()
      MOTA.LiveText:Set(t, name)
      local glow = b:CreateTexture(nil, "HIGHLIGHT")
      glow:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
      glow:SetTexCoord(p.l, p.r, p.t, p.b)
      glow:SetAllPoints()
      glow:SetBlendMode("ADD")
      glow:SetAlpha(0.25)
      MOTA.Kit:Track(function() -- the blue buttons follow the skin's accent
        local qname = M.pieces[name .. MOTA:Accent().SUFFIX] and name .. MOTA:Accent().SUFFIX or name
        local q = M.pieces[qname]
        for _, tex in ipairs({ t, glow }) do
          tex:SetTexture(M.dir .. M.textures[q.tex], "CLAMP", "CLAMP", "TRILINEAR")
          tex:SetTexCoord(q.l, q.r, q.t, q.b)
        end
        MOTA.LiveText:Set(t, qname)
      end)
      b:SetScript("OnClick", function() Herald:Press() end)
      b:Hide()
      b.left, b.top = p.x, p.y
      frame.buttons[style .. ":" .. label] = b
    end
  end

  -- The corner close button, for heralds whose main button does something else.
  local x = CreateFrame("Button", nil, frame)
  x:SetSize(24, 24)
  x:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -10)
  x:SetFrameLevel(frame:GetFrameLevel() + 6)
  local mark = x:CreateFontString(nil, "OVERLAY")
  mark:SetFontObject(MOTA:Font("setLabel"))
  mark:SetTextColor(MOTA:RGB("7A5719"))
  mark:SetText("X")
  mark:SetPoint("CENTER")
  x:SetScript("OnClick", function() if current then Herald:Close(current) end end)
  x:Hide()
  frame.closeX = x

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
end

---------------------------------------------------------------------------
-- Showing heralds, one at a time
---------------------------------------------------------------------------

local function fit(h)
  for seal, t in pairs(frame.seals) do t:SetShown(seal == (h.seal or "official")) end
  frame.eyebrow:SetText((h.eyebrow or ""):upper())
  frame.title:SetText(h.title or "")
  frame.body:SetText(h.text or "")

  local b = h.button or { label = "Dismiss", style = "quiet" }
  local chosen = frame.buttons[(b.style or "quiet") .. ":" .. (b.label or "Dismiss")] or frame.buttons["quiet:Dismiss"]
  for _, button in pairs(frame.buttons) do button:SetShown(button == chosen) end
  -- The text runs up to the button, with the canvas's 16-unit gap.
  local width = chosen.left - 16 - M.slots.htext.x
  frame.title:SetWidth(width)
  frame.body:SetWidth(width)
  -- A long title takes a smaller font, rather than crowding the line below.
  if frame.title.SetMaxLines then frame.title:SetMaxLines(1) end
  frame.title:SetFontObject(MOTA:Font("heraldTitle"))
  local wide = frame.title.GetUnboundedStringWidth and frame.title:GetUnboundedStringWidth() or frame.title:GetStringWidth()
  if wide and wide > width then frame.title:SetFontObject(MOTA:Font("kitName")) end
  frame.closeX:SetShown(h.closeX and true or false)

  -- The scroll was drawn for two lines of text. Longer text makes it taller,
  -- stretching the parchment, with the seal and the button kept in its middle.
  local two = M.slots.hbody.h
  local tall = frame.body:GetStringHeight() or 0
  local extra = math.max(0, math.ceil(tall - two - 1))
  local s, bg = M.slots.herald, M.pieces.heraldBg
  frame:SetHeight(s.h + extra)
  frame.bg:SetHeight(bg.h + extra)
  for seal, t in pairs(frame.seals) do
    local p = M.pieces["hseal_" .. seal]
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", p.x, -(p.y + extra / 2))
  end
  for _, button in pairs(frame.buttons) do
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", button.left, -(button.top + extra / 2))
  end
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
  local size = MOTA.db.settings.heraldSize == "small" and "small" or "full"
  frame:SetScale(SCALE[size])
  fit(current)
  frame:SetAlpha(1)
  frame:Show()
  if size == "full" then frame.unroll:Play() else frame.fadeIn:Play() end
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
    UI:Build()
    UI:SelectPage(page)
    UI.window:Show()
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
  fit(h)
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
-- The Extras board's examples, and test records from other members
---------------------------------------------------------------------------

Herald.samples = {
  { seal = "official", eyebrow = "Hear ye · the Ballot Hall", title = "The polls are open!",
    text = "Citizens of the Cathedral Ward: elect your Representative before Friday, 9 pm.",
    button = { label = "Vote now", style = "blue", page = 2 } },
  { seal = "crown", eyebrow = "By Royal Assent", title = "The Guild Bank Levy is law",
    text = "Given under the seal of King Aldmere. In force until 30 January.",
    button = { label = "Read it", style = "quiet", page = 3 } },
  { seal = "exchange", eyebrow = "Crossing the floor", title = "Elowen Marsh defects!",
    text = "She leaves the Silverhand for the Azeroth Exchange.",
    button = { label = "Dismiss", style = "quiet" } },
}

function Herald:ShowSamples(n)
  local list = n and { self.samples[n] } or self.samples
  if #list == 0 then return MOTA:Print("There are", #self.samples, "sample heralds: /mota herald 1, 2 or 3.") end
  for _, h in ipairs(list) do self:Announce(h, true) end
  MOTA:Print(#list == 1 and "Showing a sample herald" or "Showing the sample heralds",
    "(the canvas's example text, not real news).")
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
