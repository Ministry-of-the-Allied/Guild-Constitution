-- Pretend UI widgets: frames, textures, font strings and animations.
-- Unknown methods are allowed but recorded, so they can be checked by hand
-- against the real game API.

UNKNOWN = {}
TEXTURES_USED = {}

local Methods = {}
local MT = {}
MT.__index = function(t, k)
  local m = Methods[k]
  if m then return m end
  local kind = rawget(t, "kind") or "?"
  UNKNOWN[kind .. ":" .. k] = true
  return function() end
end

local function region(kind, parent)
  local r = setmetatable({ kind = kind, shown = kind ~= "Frame-hidden", points = {}, w = 0, h = 0,
    parent = parent, scripts = {}, events = {}, level = parent and (rawget(parent, "level") or 0) + 1 or 0,
    alpha = 1, scale = 1 }, MT)
  return r
end

local allFrames = {}

function Methods:SetSize(w, h) self.w, self.h = w, h end
function Methods:SetWidth(w) self.w = w end
function Methods:SetHeight(h) self.h = h end
function Methods:GetWidth() return self.w end
function Methods:GetHeight() return self.h end
function Methods:GetSize() return self.w, self.h end
function Methods:SetPoint(...)
  local a = { ... }
  assert(type(a[1]) == "string", "SetPoint needs a point name")
  self.points[#self.points + 1] = a
end
function Methods:ClearAllPoints() self.points = {} end
function Methods:SetAllPoints() self.points = { { "ALL" } } end
function Methods:GetPoint(i)
  local p = self.points[i or 1]
  if not p then return nil end
  return p[1], p[2], p[3], p[4], p[5]
end
function Methods:Show()
  local was = self.shown
  self.shown = true
  if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Methods:Hide()
  local was = self.shown
  self.shown = false
  if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Methods:SetShown(v) if v then self:Show() else self:Hide() end end
function Methods:IsShown() return self.shown end
function Methods:IsVisible() return self.shown end
function Methods:SetScript(name, fn) self.scripts[name] = fn end
function Methods:GetScript(name) return self.scripts[name] end
function Methods:HookScript(name, fn) self.scripts[name] = fn end
function Methods:RegisterEvent(e) self.events[e] = true end
function Methods:UnregisterEvent(e) self.events[e] = nil end
function Methods:SetFrameLevel(l) self.level = l end
function Methods:GetFrameLevel() return self.level end
function Methods:SetFrameStrata(s) self.strata = s end
function Methods:SetToplevel() end
function Methods:SetClampedToScreen() end
function Methods:SetClampRectInsets() end
function Methods:EnableMouse() end
function Methods:SetMovable() end
function Methods:RegisterForDrag() end
function Methods:RegisterForClicks() end
function Methods:StartMoving() end
function Methods:StopMovingOrSizing() end
function Methods:SetClipsChildren() end
function Methods:SetScale(s) self.scale = s end
function Methods:GetScale() return self.scale end
function Methods:GetEffectiveScale() return self.scale end
function Methods:SetAlpha(a) self.alpha = a end
function Methods:GetCenter() return self.cx or 500, self.cy or 400 end

function Methods:CreateTexture(name, layer, template, sublevel)
  assert(layer == nil or ({ BACKGROUND = 1, BORDER = 1, ARTWORK = 1, OVERLAY = 1, HIGHLIGHT = 1 })[layer], "bad layer " .. tostring(layer))
  assert(sublevel == nil or (sublevel >= -8 and sublevel <= 7), "bad sublevel")
  local t = region("Texture", self)
  return t
end
function Methods:SetTexture(path, wrapH, wrapV, filter)
  self.texture = path
  if type(path) == "string" then TEXTURES_USED[path] = true end
  assert(filter == nil or ({ LINEAR = 1, TRILINEAR = 1, NEAREST = 1 })[filter], "bad filter")
  return true
end
function Methods:SetColorTexture() end
function Methods:SetAtlas(name) self.atlas = name end
function Methods:SetTexCoord(l, r, t, b)
  for _, v in ipairs({ l, r, t, b }) do assert(type(v) == "number" and v >= 0 and v <= 1.0001, "texcoord out of range") end
  assert(l < r and t < b, "texcoords back to front")
end
function Methods:SetVertexColor(r, g, b)
  for _, v in ipairs({ r, g, b }) do assert(v >= 0 and v <= 1, "colour out of range") end
end
function Methods:SetBlendMode(m) assert(({ ADD = 1, BLEND = 1, MOD = 1, ALPHAKEY = 1, DISABLE = 1 })[m], "bad blend") end

function Methods:CreateFontString(name, layer, template)
  local fs = region("FontString", self)
  fs.text = ""
  return fs
end
function Methods:SetFontObject(f) assert(f, "SetFontObject(nil)") self.font = f end
function Methods:SetText(t) assert(self.kind ~= "FontString" or self.font, "text without a font") self.text = t end
function Methods:GetText() return rawget(self, "text") end
function Methods:SetTextColor(r, g, b) for _, v in ipairs({ r, g, b }) do assert(v >= 0 and v <= 1, "colour out of range") end end
function Methods:SetJustifyH(j) assert(({ LEFT = 1, CENTER = 1, RIGHT = 1 })[j], "bad justify") end
function Methods:SetJustifyV(j) assert(({ TOP = 1, MIDDLE = 1, BOTTOM = 1 })[j], "bad justify") end
function Methods:SetSpacing() end

function Methods:CreateAnimationGroup()
  local g = region("AnimationGroup", self)
  g.anims = {}
  return g
end
function Methods:CreateAnimation(kind)
  assert(kind == "Translation" or kind == "Alpha" or kind == "Scale" or kind == "Rotation", "bad animation " .. kind)
  local a = region("Animation", self)
  return a
end
function Methods:SetLooping(l) assert(({ NONE = 1, REPEAT = 1, BOUNCE = 1 })[l], "bad looping") end
function Methods:SetOffset() end
function Methods:SetDuration() end
function Methods:SetStartDelay() end
function Methods:SetSmoothing(s) assert(({ NONE = 1, IN = 1, OUT = 1, IN_OUT = 1, OUT_IN = 1 })[s], "bad smoothing") end
function Methods:Play() self.playing = true end

function Methods:SetScaleFrom(x, y) assert(type(x) == "number" and type(y) == "number") end
function Methods:SetScaleTo(x, y) assert(type(x) == "number" and type(y) == "number") end
function Methods:SetOrigin(p) assert(type(p) == "string") end
function Methods:SetFromAlpha() end
function Methods:SetToAlpha() end
-- An animation group finishes at once in the pretend game.
function Methods:Play()
  self.playing = true
  if self.scripts.OnFinished then self.scripts.OnFinished(self) end
end
function Methods:GetStringWidth() return #(self.text or "") * 6 end
function Methods:SetMaxLines() end
function Methods:SetWordWrap() end

function Methods:Stop() self.playing = false end

-- scroll frames and sliders
function Methods:SetScrollChild(c) self.scrollChild = c end
function Methods:SetVerticalScroll(v) self.vscroll = v end
function Methods:GetVerticalScroll() return self.vscroll or 0 end
function Methods:EnableMouseWheel() end
function Methods:SetOrientation() end
function Methods:SetThumbTexture() end
function Methods:SetValueStep() end
function Methods:SetObeyStepOnDrag() end
function Methods:SetMinMaxValues(a, b) self.minV, self.maxV = a, b end
function Methods:SetValue(v)
  self.value = math.max(self.minV or v, math.min(self.maxV or v, v))
  if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, self.value) end
end
function Methods:GetValue() return self.value or 0 end
function Methods:SetEnabled(v) self.enabled = v end
function Methods:GetStringHeight() return 16 end

-- sounds
VOICE_PLAYED, VOICE_STOPPED = {}, 0
local nextHandle = 100
function PlaySoundFile(path, channel)
  assert(type(path) == "string" and channel == "Master", "bad PlaySoundFile")
  TEXTURES_USED[path] = true
  VOICE_PLAYED[#VOICE_PLAYED + 1] = path
  nextHandle = nextHandle + 1
  return true, nextHandle
end
function StopSound(h) assert(type(h) == "number") VOICE_STOPPED = VOICE_STOPPED + 1 end

-- tooltip
function Methods:SetOwner() end
function Methods:AddLine() end

function CreateFrame(kind, name, parent)
  local f = region(kind or "Frame", parent)
  allFrames[#allFrames + 1] = f
  if name then _G[name] = f end
  return f
end

function mock_fire(event, ...)
  for _, f in ipairs(allFrames) do
    if f.events[event] and f.scripts.OnEvent then
      local ok, err = pcall(f.scripts.OnEvent, f, event, ...)
      if not ok then py_error(event .. ": " .. tostring(err)) end
    end
  end
end

function CreateFont(name)
  local f = region("Font", nil)
  function f:SetFont(path, size, flags)
    assert(type(path) == "string" and type(size) == "number", "bad SetFont")
    TEXTURES_USED[path] = true
    self.path = path
    return true
  end
  function f:GetFont() return self.path, 12, "" end
  function f:SetShadowColor() end
  function f:SetShadowOffset() end
  _G[name] = f
  return f
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent.w, UIParent.h = 1365, 768
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap.w, Minimap.h, Minimap.cx, Minimap.cy = 140, 140, 1280, 680
GameTooltip = CreateFrame("Frame", "GameTooltip", UIParent)
UISpecialFrames = {}
tinsert = table.insert
SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 839, IG_CHARACTER_INFO_CLOSE = 840, IG_CHARACTER_INFO_TAB = 841,
  LEVELUPSOUND = 888, READY_CHECK = 8960, RAID_WARNING = 8959,
  IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
LAST_SOUND = nil
COMBAT = false
function InCombatLockdown() return COMBAT end
function C_Timer.NewTimer(d, fn)
  local t = { cancelled = false }
  function t:Cancel() self.cancelled = true end
  C_Timer.After(d, function() if not t.cancelled then fn(t) end end)
  return t
end
SETTINGS_OPENED = nil
Settings = {
  RegisterCanvasLayoutCategory = function(frame, name)
    assert(frame and type(name) == "string")
    SETTINGS_FRAME = frame
    return { GetID = function() return 7 end }
  end,
  RegisterAddOnCategory = function(c) assert(c) end,
  OpenToCategory = function(id) SETTINGS_OPENED = id end,
}
SOUNDS_PLAYED = 0
function PlaySound(kit) assert(type(kit) == "number", "PlaySound needs a number") SOUNDS_PLAYED = SOUNDS_PLAYED + 1 LAST_SOUND = kit end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
ATLASES = { ["bfa-landingbutton-alliance-up"] = true }
C_Texture = { GetAtlasInfo = function(n) if ATLASES[n] then return { width = 128, height = 128 } end end }
function GetSubZoneText() return "Trade District" end
function GetZoneText() return "Stormwind City" end
C_DateAndTime = { GetCurrentCalendarTime = function() return { weekday = 5 } end }
CALENDAR_WEEKDAY_NAMES = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
date = os.date
function GetCursorPosition() return 1180, 700 end

function mock_unknown()
  local t = {}
  for k in pairs(UNKNOWN) do t[#t + 1] = k end
  table.sort(t)
  return table.concat(t, ", ")
end
function mock_textures()
  local t = {}
  for k in pairs(TEXTURES_USED) do t[#t + 1] = k end
  table.sort(t)
  return table.concat(t, "\n")
end

---------------------------------------------------------------------------
-- What AceComm-3.0 and ChatThrottleLib need (added 2026-11-06)
---------------------------------------------------------------------------

function Methods:RegisterEvent(e) self.events[e] = true end
function Methods:UnregisterAllEvents() self.events = {} end

-- OnUpdate runs on every shown frame each time the clock moves.
local advanceTimers = mock_advance
function mock_advance(dt)
  advanceTimers(dt)
  for _, f in ipairs(allFrames) do
    if f.shown and f.scripts.OnUpdate then
      local ok, err = pcall(f.scripts.OnUpdate, f, dt)
      if not ok then py_error("OnUpdate: " .. tostring(err)) end
    end
  end
end

function GetFramerate() return 60 end
table.wipe = wipe
function securecallfunction(fn, ...) return fn(...) end

-- The game's xpcall passes extra arguments on; Lua 5.1's doesn't.
local xpcall51 = xpcall
function xpcall(fn, handler, ...)
  local n, args = select("#", ...), { ... }
  return xpcall51(function() return fn(unpack(args, 1, n)) end, handler)
end

-- hooksecurefunc([table,] name, fn): runs fn after the original.
function hooksecurefunc(a, b, c)
  local tbl, name, hook = _G, a, b
  if type(a) == "table" then tbl, name, hook = a, b, c end
  local orig = tbl[name]
  assert(type(orig) == "function", "hooksecurefunc: no function " .. tostring(name))
  tbl[name] = function(...)
    local r = { orig(...) }
    hook(...)
    return unpack(r)
  end
end
C_ChatInfo.SendAddonMessageLogged = function(...) return C_ChatInfo.SendAddonMessage(...) end
function SendChatMessage() end
function BNSendGameData() end

-- C_EncodingUtil: the pretend packer writes a Lua table as text and reads it
-- back; Base64 is real, so messages stay free of control characters.
local function ser(v)
  local t = type(v)
  if t == "table" then
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = "[" .. ser(k) .. "]=" .. ser(x) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then
    return string.format("%q", v)
  else
    return tostring(v)
  end
end
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64enc(s)
  return ((s:gsub(".", function(c)
    local r, b = "", c:byte()
    for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
    return r
  end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
    if #x < 6 then return "" end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
    return B64:sub(c + 1, c + 1)
  end) .. ({ "", "==", "=" })[#s % 3 + 1])
end
local function b64dec(s)
  s = s:gsub("[^" .. B64 .. "=]", "")
  return (s:gsub(".", function(x)
    if x == "=" then return "" end
    local r, f = "", (B64:find(x, 1, true) - 1)
    for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0") end
    return r
  end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
    if #x ~= 8 then return "" end
    local c = 0
    for i = 1, 8 do c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0) end
    return string.char(c)
  end))
end
C_EncodingUtil = {
  SerializeCBOR = function(v) return ser(v) end,
  DeserializeCBOR = function(s)
    local fn = assert(loadstring("return " .. s))
    setfenv(fn, {})
    return fn()
  end,
  CompressString = function(s) return s end,
  DecompressString = function(s) return s end,
  EncodeBase64 = b64enc,
  DecodeBase64 = b64dec,
}

-- Edit boxes (the Ballot Hall's Open Polls form)
function Methods:SetAutoFocus() end
function Methods:SetTextInsets() end
function Methods:SetMaxLetters() end
function Methods:ClearFocus() end
function Methods:SetFocus() end
function Methods:HasFocus() return false end
