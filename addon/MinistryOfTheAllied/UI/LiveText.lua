-- Ministry of the Allied: live text over the canvas pictures.
-- The texture build (tools/textures/build.py) draws each piece without its words and
-- records them in Media.texts: the words, font, size, letter-spacing, colour, shadow and
-- where they sit. LiveText:Set(texture, pieceName) lays them over the texture as game
-- text, which the game draws fresh at the window's real size, so it stays sharp when the
-- window is small (Max, 8 Nov). The text follows its texture: shown, hidden, faded,
-- tinted (a white piece coloured in the game) and resized (a piece drawn larger).

local _, MOTA = ...
local LT = {}
MOTA.LiveText = LT

local TRACKED = 0.02 -- letter-spacing (em) above which each letter is placed by hand

-- What each texture carries, kept beside it (weak keys: a texture that goes, goes from here too).
local state = setmetatable({}, { __mode = "k" })

local function runsFor(name)
  local T = MOTA.Media.texts
  if not T or not name then return nil end
  return T[name] or T[(name:gsub("~%a+$", ""))]
end

-- Each letter of a spaced-out run is its own font string (game text can't be letter-spaced).
local function newTracked(parent)
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(1, 1)
  box.letters = {}
  return box
end

local function setTracked(box, rec, font, k)
  local x, n, gap = 0, 0, rec.t * rec.z * k
  for ch in rec.s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    n = n + 1
    local fs = box.letters[n]
    if not fs then
      fs = box:CreateFontString(nil, "OVERLAY")
      box.letters[n] = fs
    end
    fs:SetFontObject(font)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", box, "LEFT", x, 0)
    fs:SetText(ch)
    fs:Show()
    local w = ch == " " and rec.z * k * 0.28 or fs:GetStringWidth()
    x = x + w + gap
  end
  for i = n + 1, #box.letters do box.letters[i]:Hide() end
  box:SetSize(math.max(1, x - gap), rec.h * k)
end

local function stringsOf(item)
  return item.box and item.box.letters or { item.fs }
end

-- Puts every run in its place, at the texture's present size.
local function place(t)
  local st = state[t]
  local p = MOTA.Media.pieces[st.name]
  local k, w = 1, t:GetWidth()
  if p and p.w and p.w > 0 and w and w > 0 then k = w / p.w end
  for _, item in ipairs(st.live) do
    local rec = item.rec
    local font = MOTA:FontAt(rec.f, rec.z * k)
    -- the middle of the letters: CSS letter-spacing also adds a space after the last letter
    local cx = (rec.x + (rec.w - (rec.t or 0) * rec.z) / 2) * k
    local cy = (rec.y + rec.h / 2) * k
    if item.box then
      setTracked(item.box, rec, font, k)
      item.box:ClearAllPoints()
      item.box:SetPoint("CENTER", t, "TOPLEFT", cx, -cy)
    else
      local fs = item.fs
      fs:SetFontObject(font)
      fs:SetText(rec.s)
      fs:ClearAllPoints()
      if (rec.n or 1) > 1 then -- a paragraph: the same width, wrapped by the game
        fs:SetWidth(rec.w * k + 2)
        fs:SetJustifyH(rec.j or "LEFT")
        fs:SetPoint("TOP", t, "TOPLEFT", (rec.x + rec.w / 2) * k, -rec.y * k)
      else
        fs:SetWidth(0)
        fs:SetPoint("CENTER", t, "TOPLEFT", cx, -cy)
      end
    end
    for _, fs in ipairs(stringsOf(item)) do
      fs:SetShadowOffset((rec.sx or 0) * k, -(rec.sy or 0) * k)
    end
  end
end

-- Colours every run: its own colour, times the texture's tint and alpha.
local function paint(t)
  local st = state[t]
  local tint, alpha = st.tint, st.alpha or 1
  for _, item in ipairs(st.live) do
    local rec = item.rec
    local r, g, b = MOTA:RGB(rec.c)
    if tint then r, g, b = r * tint[1], g * tint[2], b * tint[3] end
    local sr, sg, sb = 0, 0, 0
    if rec.sc then sr, sg, sb = MOTA:RGB(rec.sc) end
    for _, fs in ipairs(stringsOf(item)) do
      fs:SetTextColor(r, g, b, (rec.a or 1) * alpha)
      fs:SetShadowColor(sr, sg, sb, rec.sc and (rec.sa or 1) * alpha or 0)
    end
  end
end

local function sync(t)
  local shown = t:IsShown()
  for _, item in ipairs(state[t].live) do
    local region = item.box or item.fs
    region:SetShown(shown)
  end
end

-- The texture's own Show, Hide, SetAlpha, SetVertexColor and SizeTo also move its text.
local function hook(t)
  if state[t].hooked then return end
  state[t].hooked = true
  local show, hide, setShown = t.Show, t.Hide, t.SetShown
  local setAlpha, setColor = t.SetAlpha, t.SetVertexColor
  local setSize, setWidth, setHeight = t.SetSize, t.SetWidth, t.SetHeight
  t.Show = function(self) show(self) sync(self) end
  t.Hide = function(self) hide(self) sync(self) end
  t.SetShown = function(self, on) setShown(self, on) sync(self) end
  t.SetAlpha = function(self, a) setAlpha(self, a) state[self].alpha = a paint(self) end
  t.SetVertexColor = function(self, r, g, b, a)
    setColor(self, r, g, b, a)
    state[self].tint = { r or 1, g or 1, b or 1 }
    paint(self)
  end
  t.SetSize = function(self, w, h) setSize(self, w, h) place(self) end
  t.SetWidth = function(self, w) setWidth(self, w) place(self) end
  t.SetHeight = function(self, h) setHeight(self, h) place(self) end
end

local function same(a, b)
  if not a or #a ~= #b then return false end
  for i, rec in ipairs(b) do
    local item = a[i]
    if item.rec.s ~= rec.s or (item.box ~= nil) ~= ((rec.t or 0) > TRACKED) then return false end
  end
  return true
end

-- Lays piece name's text over texture t (call it whenever t is given a piece).
function LT:Set(t, name)
  if t.GetDrawLayer and t:GetDrawLayer() == "HIGHLIGHT" then return end -- a hover glow: its piece already has the words
  local runs = runsFor(name)
  local st = state[t]
  if not st then
    if not runs then return end
    st = { live = {} }
    state[t] = st
  end
  st.name = name
  if st.runs == runs then return end
  st.runs = runs
  if not runs then
    for _, item in ipairs(st.live) do (item.box or item.fs):Hide() end
    st.live = {}
    return
  end
  hook(t)
  if same(st.live, runs) then
    for i, rec in ipairs(runs) do st.live[i].rec = rec end -- the same words in another skin's colours
  else
    for _, item in ipairs(st.live) do (item.box or item.fs):Hide() end
    st.live = {}
    local parent = t:GetParent()
    for i, rec in ipairs(runs) do
      local item = { rec = rec }
      if (rec.t or 0) > TRACKED then
        item.box = newTracked(parent)
      else
        item.fs = parent:CreateFontString(nil, "OVERLAY", nil, 7)
        item.fs:SetJustifyH("CENTER")
        item.fs:SetWordWrap((rec.n or 1) > 1)
      end
      st.live[i] = item
    end
  end
  place(t)
  paint(t)
  sync(t)
end
