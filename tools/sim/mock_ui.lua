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
    alpha = 1, scale = 1, regions = {} }, MT)
  -- a frame's textures and font strings, as GetRegions gives them (added 2026-11-08, D5c)
  if parent and (kind == "Texture" or kind == "FontString") then
    local list = rawget(parent, "regions")
    if list then list[#list + 1] = r end
  end
  return r
end

local POINTS = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 1, CENTER = 1, RIGHT = 1, BOTTOMLEFT = 1,
  BOTTOM = 1, BOTTOMRIGHT = 1, ALL = 1 }

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
  assert(POINTS[a[1]], "bad point " .. a[1])
  if type(a[3]) == "string" then assert(POINTS[a[3]], "bad relative point " .. a[3]) end
  self.points[#self.points + 1] = a
end
function Methods:ClearAllPoints() self.points = {} end
function Methods:SetAllPoints() self.points = { { "ALL" } } end
function Methods:GetPoint(i)
  local p = self.points[i or 1]
  if not p then return nil end
  return p[1], p[2], p[3], p[4], p[5]
end
function Methods:GetNumPoints() return #self.points end
function Methods:SetHitRectInsets(l, r, t, b)
  for _, v in ipairs({ l, r, t, b }) do assert(type(v) == "number", "SetHitRectInsets needs four numbers") end
  rawset(self, "hitInsets", { l, r, t, b })
end
function Methods:GetHitRectInsets()
  local i = rawget(self, "hitInsets") or { 0, 0, 0, 0 }
  return i[1], i[2], i[3], i[4]
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
-- As in the game, a hook runs after what the frame already had; hooks stack (11 Nov: a second add-on
-- hooking the world map's OnShow used to replace the first's).
function Methods:HookScript(name, fn)
  local prev = self.scripts[name]
  if not prev then self.scripts[name] = fn return end
  self.scripts[name] = function(...)
    prev(...)
    return fn(...)
  end
end
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
function Methods:GetEffectiveScale()
  local p = rawget(self, "parent")
  return (self.scale or 1) * (p and p.GetEffectiveScale and p:GetEffectiveScale() or 1)
end
function Methods:SetAlpha(a) self.alpha = a end
function Methods:GetAlpha() return self.alpha end
function Methods:IsObjectType(t) return self.kind == t or (t == "Frame" and self.kind == "Button") end
function Methods:GetRegions() return unpack(self.regions) end
-- The frame's edges in its own units, from its first point (added 11 Nov, the drag-to-resize window).
-- Only a point on UIParent is understood, as the window has. As in the game, an edge is given in the frame's own
-- units: GetLeft() * GetEffectiveScale() is the place in pixels.
local ANCHOR = { BOTTOMLEFT = { 0, 0 }, BOTTOM = { .5, 0 }, BOTTOMRIGHT = { 1, 0 }, LEFT = { 0, .5 }, CENTER = { .5, .5 },
  RIGHT = { 1, .5 }, TOPLEFT = { 0, 1 }, TOP = { .5, 1 }, TOPRIGHT = { 1, 1 } }
-- Opt-in (a test sets `frame.mockRects = true`): other code asks frames for their edges and expects nothing back.
local function edges(self)
  if not rawget(self, "mockRects") then return nil end
  local p = self.points[1]
  local s = self:GetScale() or 1
  local w, h = (self.w or 0) * s, (self.h or 0) * s
  if not p then return 0, 0, w, h end
  local a = ANCHOR[p[1]]
  local r = ANCHOR[p[3] or p[1]]
  local x = (p[4] or 0) * s + r[1] * UIParent.w
  local y = (p[5] or 0) * s + r[2] * UIParent.h
  local left, bottom = x - a[1] * w, y - a[2] * h
  return left / s, bottom / s, (left + w) / s, (bottom + h) / s
end
function Methods:GetLeft() local l = edges(self) return l end
function Methods:GetBottom() local _, b = edges(self) return b end
function Methods:GetRight() local _, _, r = edges(self) return r end
function Methods:GetTop() local _, _, _, t = edges(self) return t end
function Methods:GetCenter() return rawget(self, "cx") or 500, rawget(self, "cy") or 400 end

function Methods:CreateTexture(name, layer, template, sublevel)
  assert(layer == nil or ({ BACKGROUND = 1, BORDER = 1, ARTWORK = 1, OVERLAY = 1, HIGHLIGHT = 1 })[layer], "bad layer " .. tostring(layer))
  assert(sublevel == nil or (sublevel >= -8 and sublevel <= 7), "bad sublevel")
  local t = region("Texture", self)
  return t
end
-- A round cut for a texture (added 11 Nov, the guild dots' fallback circle): a texture that takes SetAllPoints and SetTexture.
function Methods:CreateMaskTexture() return region("Texture", self) end
function Methods:AddMaskTexture(mask) self.mask = mask end
function Methods:SetTexture(path, wrapH, wrapV, filter)
  self.texture = path
  self.wrap = wrapH
  if type(path) == "string" then TEXTURES_USED[path] = true end
  assert(filter == nil or ({ LINEAR = 1, TRILINEAR = 1, NEAREST = 1 })[filter], "bad filter")
  return true
end
function Methods:SetColorTexture() end
-- A texture's turn in radians (added 11 Nov, the NPC marker's compass arrow).
function Methods:SetRotation(r) assert(type(r) == "number", "SetRotation needs a number") self.rotation = r end
function Methods:SetAtlas(name) self.atlas = name end
-- Coordinates past 1 only on a repeating (tiled) texture; swapped ends mirror the picture.
function Methods:SetTexCoord(l, r, t, b)
  local max = rawget(self, "wrap") == "REPEAT" and 64 or 1.0001
  for _, v in ipairs({ l, r, t, b }) do assert(type(v) == "number" and v >= 0 and v <= max, "texcoord out of range") end
  assert(l ~= r and t ~= b, "texcoords of no size")
  self.coords = { l, r, t, b }
end
function Methods:SetVertexColor(r, g, b)
  for _, v in ipairs({ r, g, b }) do assert(v >= 0 and v <= 1, "colour out of range") end
  self.color = { r, g, b }
end
function Methods:SetBlendMode(m) assert(({ ADD = 1, BLEND = 1, MOD = 1, ALPHAKEY = 1, DISABLE = 1 })[m], "bad blend") end
function Methods:CreateFontString(name, layer, template)
  local fs = region("FontString", self)
  fs.text = ""
  if template then fs.font = template end -- a template (GameFontNormal...) brings its font
  return fs
end
function Methods:SetFontObject(f) assert(f, "SetFontObject(nil)") self.font = f end
-- the game refuses words on a font string before it has a font (fixed 2026-11-08: the old check read
-- self.font through the unknown-method fallback, which is never nil, so it never fired)
function Methods:SetText(t)
  assert(self.kind ~= "FontString" or rawget(self, "font") or rawget(self, "fontPath"), "text without a font")
  self.text = t
end
function Methods:GetText() return rawget(self, "text") end
function Methods:SetFont(path, size, flags)
  assert(type(path) == "string" and type(size) == "number" and size > 0, "bad font")
  self.fontPath, self.fontSize, self.fontFlags = path, size, flags
  return true
end
function Methods:GetFont() return rawget(self, "fontPath"), rawget(self, "fontSize"), rawget(self, "fontFlags") end
function Methods:GetTextColor()
  local c = rawget(self, "color") or { 1, 1, 1 }
  return c[1], c[2], c[3], 1
end
function Methods:SetTextColor(r, g, b)
  for _, v in ipairs({ r, g, b }) do assert(v >= 0 and v <= 1, "colour out of range") end
  self.color = { r, g, b }
end
function Methods:GetObjectType() return self.kind end
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

-- edit boxes
function Methods:ClearFocus() end
function Methods:SetAutoFocus() end
function Methods:SetTextInsets() end

-- scroll frames and sliders
function Methods:SetScrollChild(c) self.scrollChild = c end
function Methods:SetVerticalScroll(v) self.vscroll = v end
function Methods:GetVerticalScroll() return type(self.vscroll) == "number" and self.vscroll or 0 end
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
function Methods:SetOwner() self.lines = {} end
function Methods:AddLine(text) self.lines = self.lines or {} table.insert(self.lines, text) end

function CreateFrame(kind, name, parent)
  local f = region(kind or "Frame", parent)
  allFrames[#allFrames + 1] = f
  if name then _G[name] = f end
  -- a frame's child frames, as GetChildren gives them (added 12 Nov, the NPC nameplates)
  if parent then
    local kids = rawget(parent, "kids") or {}
    kids[#kids + 1] = f
    rawset(parent, "kids", kids)
  end
  return f
end
function Methods:GetChildren() return unpack(rawget(self, "kids") or {}) end

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
  IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857,
  IG_ABILITY_PAGE_TURN = 836,   -- the spellbook's page turn (the Chronicle book, 10 Nov)
  UI_COVENANT_CHOICE_CELEBRATION_ANIMATION_BASTION = 171877 }  -- the book's holy sound (10 Nov)
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
-- as the game: willPlay, and a handle
function PlaySound(kit) assert(type(kit) == "number", "PlaySound needs a number") SOUNDS_PLAYED = SOUNDS_PLAYED + 1 LAST_SOUND = kit return true, SOUNDS_PLAYED end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
ATLASES = { ["bfa-landingbutton-alliance-up"] = true }
C_Texture = { GetAtlasInfo = function(n) if ATLASES[n] then return { width = 128, height = 128 } end end }
function GetSubZoneText() return "Trade District" end
function GetZoneText() return ZONE or "Stormwind City" end
C_DateAndTime = { GetCurrentCalendarTime = function() return { weekday = 5 } end }
CALENDAR_WEEKDAY_NAMES = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
date = os.date
CURSOR = { 1180, 700 }
function GetCursorPosition() return CURSOR[1], CURSOR[2] end
CURSOR_SHAPE = nil
function SetCursor(c) CURSOR_SHAPE = c end

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
