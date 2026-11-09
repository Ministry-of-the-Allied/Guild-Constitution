-- Ministry of the Allied: the Ballot Hall page (window page 2), drawn from the
-- Ballot Hall board on the design canvas. Milestone 4 (ADDON_SPEC.md 16.2).
--
-- Ribbons switch the views:
--   Ballot   the ballot paper while polls are open; "the Crown is counting" once
--            they close; "the Ballot Hall is quiet" when none are open
--   Results  the last proclamation, its count and turnout, and the record
--   Crown    (the two Crown ranks only) the Open Polls form, or the live count
--            with the two Kings' counts, Close polls, Declare or the run-off
-- The Petition ribbon on the board comes in a later milestone.
--
-- Fixed pieces (ribbons, seals, buttons, pills, papers) are textures from
-- tools/textures/ballot.html; everything with live text is game text.

local _, MOTA = ...
local UI, M, Ballot = MOTA.UI, MOTA.Media, MOTA.Ballot
local Page = {}
MOTA.BallotHall = Page

local PAGE_ID = "ballot"
local PAD_L, PAD_T, PAD_R, PAD_B = 34, 20, 24, 20 -- the board's parchment padding
local CW = M.slots.parch.w - PAD_L - PAD_R         -- 710
local CH = M.slots.parch.h - PAD_T - PAD_B         -- 510
local VIEW_Y = 52                                  -- the ribbons, then a 16 gap
local VH = CH - VIEW_Y                             -- 458
local LEFT_W, GAP = 397, 20                        -- the board's 1.35fr / 1fr columns
local RIGHT_X = LEFT_W + GAP
local RIGHT_W = CW - RIGHT_X

local C = {
  ink = "2A1F14", ink2 = "5E4B33", inkGold = "7A5719", rb = "1B3570", leaf = "F3D98A",
  brown = "6E4F17", gold = "C9A24A", sky = "E8EEFF", oxblood = "6E1712", white = "FFFFFF",
}
local CHIP = { sh = "1F4290", ex = "9E1B22", ink = "5E4B33", teal = "1F7A70", ox = "6E1712" }
local BAR = { sh = "2E59AC", ex = "AC2D2C", ind = "74603F" }

local root, views, ribbons, topNote
local built = false
local CAND_ROW, CAND_VIEW = 80, 164 -- the Open the polls form: one candidate's height, and the list's window

-- The accent (UI/Skin.lua): the blue the board draws in is the window skin's
-- accent here, so ink, plates and the lit ribbons follow it. Party colours
-- (CHIP, BAR) stay as they are. What is drawn in the accent is remembered, so
-- a new skin recolours it at once.
local ACCENT_FIELD = { ["1B3570"] = "INK", ["142B5E"] = "DARK", ["1D3B7C"] = "FILL" }
local inked, wearing = {}, {}
local function accentHex(hex) return MOTA:Accent()[ACCENT_FIELD[hex]] end
local function inkIt(apply)
  inked[#inked + 1] = apply
  apply()
end
local function wear(t) -- a blue picture, in the accent's drawn copy
  local name = "b_" .. t.name .. MOTA:Accent().SUFFIX
  if not M.pieces[name] then name = "b_" .. t.name end
  local p = M.pieces[name]
  t:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
  t:SetTexCoord(p.l, p.r, p.t, p.b)
  MOTA.LiveText:Set(t, name)
end
MOTA:Listen("SKIN_CHANGED", function()
  for _, apply in ipairs(inked) do apply() end
  for _, t in ipairs(wearing) do wear(t) end
end)

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------

-- A piece from the Ballot Hall layout. Its "box" is the element's own box
-- (from the layout), without the shadow the piece may carry around it.
local function art(parent, name, layer, sub)
  local p, s = M.pieces["b_" .. name], M.slots[name]
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
  t:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
  t:SetTexCoord(p.l, p.r, p.t, p.b)
  t:SetSize(p.w, p.h)
  t.piece, t.slot, t.k = p, s, 1
  MOTA.LiveText:Set(t, "b_" .. name)
  if M.pieces["b_" .. name .. "~cr"] then
    t.name = name
    wearing[#wearing + 1] = t
    wear(t)
  end
  return t
end

-- Draws a piece so that its box is size wide.
local function scaled(t, size)
  t.k = size / t.slot.w
  t:SetSize(t.piece.w * t.k, t.piece.h * t.k)
  return t
end

-- Places a piece so that its box's top-left corner is at x, y.
local function put(t, anchor, x, y)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", anchor, "TOPLEFT", x + (t.piece.x - t.slot.x) * t.k, -(y + (t.piece.y - t.slot.y) * t.k))
  return t
end

-- ...or its box's centre (for the rotated stamps).
local function putCenter(t, anchor, cx, cy)
  return put(t, anchor, cx - t.slot.w * t.k / 2, cy - t.slot.h * t.k / 2)
end

local function boxOf(name) return M.slots[name] end

-- The seal of a candidate's party (the Official seal for an independent): the
-- mark on the name you pick, and the seal on the Seal my ballot button, wear it.
local SEAL_OF = { sh = "seal-sh", ex = "seal-ex" }
local function sealOf(p) return SEAL_OF[p] or "seal-off" end

-- Shows another seal on a piece drawn by art(), at the same size and place.
local function swapSeal(t, name, size, anchor, x, y)
  if t.sealName == name then return end
  t.sealName = name
  local p = M.pieces["b_" .. name]
  t:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
  t:SetTexCoord(p.l, p.r, p.t, p.b)
  t.piece, t.slot = p, M.slots[name]
  scaled(t, size)
  put(t, anchor, x, y)
end

local function at(region, anchor, x, y, point)
  region:ClearAllPoints()
  region:SetPoint(point or "TOPLEFT", anchor, "TOPLEFT", x, -y)
  return region
end

local function text(parent, font, color, justify, width)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(MOTA:Font(font))
  fs:SetTextColor(MOTA:RGB(color))
  fs:SetJustifyH(justify or "LEFT")
  fs:SetJustifyV("TOP")
  if width then fs:SetWidth(width) end
  if ACCENT_FIELD[color] then inkIt(function() fs:SetTextColor(MOTA:RGB(accentHex(color))) end) end
  return fs
end

local function color(t, hex, alpha)
  local r, g, b = MOTA:RGB(hex)
  t:SetColorTexture(r, g, b, alpha or 1)
  if ACCENT_FIELD[hex] and not t.accented then
    t.accented = true
    inkIt(function()
      local r2, g2, b2 = MOTA:RGB(accentHex(hex))
      t:SetColorTexture(r2, g2, b2, alpha or 1)
    end)
  end
  return t
end

-- A flat panel with lines round it, following the frame's size:
-- fill = { hex, alpha }, lines = { { inset, width, hex, alpha }, ... }
local function panel(f, fill, lines)
  if fill then
    local t = color(f:CreateTexture(nil, "BACKGROUND", nil, 1), fill[1], fill[2])
    t:SetAllPoints()
  end
  for _, l in ipairs(lines or {}) do
    local i, w = l[1], l[2]
    local function edge(p1, x1, y1, p2, x2, y2)
      local t = color(f:CreateTexture(nil, "BACKGROUND", nil, 2), l[3], l[4])
      t:SetPoint(p1, f, p1, x1, y1)
      t:SetPoint(p2, f, p2, x2, y2)
    end
    edge("TOPLEFT", i, -i, "TOPRIGHT", -i, -(i + w)) -- top: from its top corners down by w
    edge("BOTTOMLEFT", i, i + w, "BOTTOMRIGHT", -i, i)
    edge("TOPLEFT", i, -i, "BOTTOMLEFT", i + w, i)
    edge("TOPRIGHT", -(i + w), -i, "BOTTOMRIGHT", -i, i)
  end
  return f
end

local function frame(parent, x, y, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  at(f, parent, x, y)
  return f
end

local function line(parent, x, y, w, hex, alpha, h)
  local t = color(parent:CreateTexture(nil, "ARTWORK"), hex, alpha)
  t:SetSize(w, h or 1)
  return at(t, parent, x, y)
end

-- The board's rules: a fine gold-brown line, and a double one.
local function rule(parent, x, y, w)
  return line(parent, x + w * 0.06, y, w * 0.88, C.inkGold, 0.9)
end

local function doubleRule(parent, x, y, w)
  line(parent, x, y, w, C.inkGold, 0.75)
  line(parent, x, y + 3, w, C.inkGold, 0.4)
end

-- Spaced-out capitals, wrapped onto more lines when they don't fit.
local function caps(parent, font, hex, tracking)
  local o = { lines = {}, parent = parent }
  local size = MOTA:FontSize(font)
  function o:Set(str, x, y, width, align)
    local words = {}
    for w in tostring(str):upper():gmatch("%S+") do words[#words + 1] = w end
    local n, cur = 0, nil
    local function lineObj(i)
      if not self.lines[i] then
        local l = MOTA:Tracked(self.parent, font, hex, tracking)
        self.lines[i] = l
        if ACCENT_FIELD[hex] then inkIt(function() l:SetColor(accentHex(hex)) end) end
      end
      return self.lines[i]
    end
    local texts = {}
    for _, w in ipairs(words) do
      local try = cur and (cur .. " " .. w) or w
      local probe = lineObj(1)
      probe:SetText(try)
      if cur and width and probe:GetWidth() > width then
        texts[#texts + 1] = cur
        cur = w
      else
        cur = try
      end
    end
    if cur then texts[#texts + 1] = cur end
    local lh = size * 1.3 + 2
    for i, s in ipairs(texts) do
      local l = lineObj(i)
      l:SetText(s)
      l:ClearAllPoints()
      if align == "CENTER" then
        l:SetPoint("TOP", self.parent, "TOPLEFT", x, -(y + (i - 1) * lh))
      elseif align == "RIGHT" then
        l:SetPoint("TOPRIGHT", self.parent, "TOPLEFT", x, -(y + (i - 1) * lh))
      else
        l:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x, -(y + (i - 1) * lh))
      end
      l:Show()
      n = i
    end
    for i = n + 1, #self.lines do self.lines[i]:Hide() end
    self.height = n * lh - 2
    return self.height
  end
  function o:SetShown(v) for _, l in ipairs(self.lines) do l:SetShown(v) end end
  return o
end

-- A coloured chip with a gold diamond and spaced-out text (.chip).
local function chip(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(60, 22)
  f.bg = color(f:CreateTexture(nil, "BACKGROUND"), CHIP.ink)
  f.bg:SetAllPoints()
  f.dia = put(art(f, "diamond"), f, 7, 8)
  f.label = MOTA:Tracked(f, "bEyebrow", C.white, 0.14)
  f.label:SetPoint("LEFT", f, "LEFT", 19, 0)
  function f:Set(str, key)
    color(self.bg, CHIP[key] or CHIP.ink)
    self.label:SetText(tostring(str):upper())
    self:SetWidth(19 + self.label:GetWidth() + 9)
  end
  return f
end

-- A bar (.bar) with its fill.
local function bar(parent, w, h)
  local f = panel(CreateFrame("Frame", nil, parent), { C.brown, 0.16 }, { { 0, 1, C.brown, 0.55 } })
  f:SetSize(w, h)
  f.fill = f:CreateTexture(nil, "ARTWORK")
  f.fill:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.fill:SetHeight(h - 2)
  f.shine = color(f:CreateTexture(nil, "ARTWORK", nil, 1), C.white, 0.3)
  f.shine:SetPoint("TOPLEFT", f.fill, "TOPLEFT")
  f.shine:SetPoint("TOPRIGHT", f.fill, "TOPRIGHT")
  f.shine:SetHeight(1)
  function f:Set(frac, party)
    color(self.fill, BAR[party] or BAR.ind)
    local w2 = math.max(0, math.min(1, frac)) * (w - 2)
    self.fill:SetWidth(math.max(w2, 0.01))
    self.fill:SetShown(w2 > 0)
    self.shine:SetShown(w2 > 0)
  end
  return f
end

-- A button drawn from one piece. SetUsable(false) greys it out (the board's
-- disabled look) and stops clicks.
local function pieceButton(parent, name, onClick)
  local s = boxOf(name)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(s.w, s.h)
  b.art = put(art(b, name, "ARTWORK"), b, 0, 0)
  local glow = put(art(b, name, "HIGHLIGHT"), b, 0, 0)
  glow:SetBlendMode("ADD")
  glow:SetAlpha(0.25)
  b.usable = true
  b:SetScript("OnClick", function()
    if not b.usable then return end
    if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    onClick(b)
  end)
  function b:SetUsable(v)
    self.usable = v and true or false
    self:SetAlpha(v and 1 or 0.45)
  end
  return b
end

local function short(name) return MOTA:Short(name) end

local function initials(name) return MOTA:Initials(name) end

local function party(p) return Ballot.PARTIES[p] or Ballot.PARTIES.ind end

local function pct(v, t) return t > 0 and math.floor(v * 100 / t + 0.5) or 0 end

---------------------------------------------------------------------------
-- The ribbons
---------------------------------------------------------------------------

local function buildRibbons()
  ribbons = {}
  local defs = {
    { id = "ballot", rest = "rb-ballot", on = "rb-ballot-on", restDot = "rb-ballot-dot", onDot = "rb-ballot-on-dot" },
    { id = "results", rest = "rb-results", on = "rb-results-on" },
    { id = "crown", rest = "rb-crown", on = "rb-crown-on", tip = "Only the two Crown ranks see this" },
  }
  for _, d in ipairs(defs) do
    local b = CreateFrame("Button", nil, root)
    b.def = d
    b.looks = {}
    for _, key in ipairs({ "rest", "on", "restDot", "onDot" }) do
      if d[key] then
        b.looks[key] = put(art(b, d[key], "ARTWORK"), b, 0, 0)
        b.looks[key].box = boxOf(d[key])
      end
    end
    b:SetScript("OnClick", function()
      if Page.view ~= d.id then
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        Page:SetView(d.id)
      end
    end)
    if d.tip then
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(d.tip, 1, 0.95, 0.77)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    ribbons[d.id] = b
  end
  topNote = MOTA:Tracked(root, "bEyebrow", C.inkGold, 0.32)
end

local function layoutRibbons(view, dot, king)
  local x = 0
  for _, id in ipairs({ "ballot", "results", "crown" }) do
    local b = ribbons[id]
    local show = id ~= "crown" or king
    b:SetShown(show)
    if show then
      local on = view == id
      local key = (on and "on" or "rest") .. ((dot and b.looks.onDot) and "Dot" or "")
      for k, t in pairs(b.looks) do t:SetShown(k == key) end
      local box = b.looks[key].box
      b:SetSize(box.w, box.h)
      at(b, root, x, 0)
      x = x + box.w + 6
    end
  end
end

---------------------------------------------------------------------------
-- Ballot: polls open
---------------------------------------------------------------------------

local O = {} -- the open ballot's parts

local function buildOpen(v)
  -- The left column
  O.eyebrow = caps(v, "bEyebrow", C.inkGold, 0.32)
  O.bl = panel(frame(v, 0, 22, 206, 56), { C.rb, 0.09 }, { { 0, 1, C.rb, 1 } })
  line(O.bl, 0, 0, 4, C.rb, 1, 56)
  put(scaled(art(O.bl, "seal-off"), 36), O.bl, 10, 10)
  O.blName = at(text(O.bl, "bName13", C.ink, "LEFT", 140), O.bl, 56, 10)
  O.blName:SetMaxLines(2)
  O.blKind = text(O.bl, "bSmall13", C.ink2, "LEFT", 140)
  O.blKind:SetPoint("TOPLEFT", O.blName, "BOTTOMLEFT", 0, -1)

  O.plate = panel(frame(v, 0, 90, 206, 80), { C.brown, 0.07 }, { { 0, 1, C.brown, 0.45 } })
  caps(O.plate, "eyebrow", C.inkGold, 0.32):Set("Polls close in", 12, 10)
  O.left = at(text(O.plate, "bNum22", C.rb), O.plate, 12, 26)
  O.at = at(text(O.plate, "bSmall13", C.ink2), O.plate, 12, 56)

  caps(v, "eyebrow", C.inkGold, 0.32):Set("Your ballot goes to", 0, 184)
  O.kings = {}
  for i = 1, 3 do
    local r = frame(v, 0, 202 + (i - 1) * 22, 206, 20)
    r.on = put(art(r, "kdot-on"), r, 0, 5)
    r.off = put(art(r, "kdot-off"), r, 0, 5)
    r.name = at(text(r, "bSmall", C.ink, "LEFT", 130), r, 17, 1)
    r.name:SetMaxLines(1)
    r.state = text(r, "bItalic13", C.ink2, "RIGHT")
    r.state:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -1)
    O.kings[i] = r
  end
  O.delivery = text(v, "bSmall13", C.ink2, "LEFT", 206)
  O.secret = text(v, "bItalic", C.ink2, "LEFT", 206)
  O.secret:SetPoint("BOTTOMLEFT", v, "TOPLEFT", 0, -VH)
  O.secret:SetJustifyV("BOTTOM")
  O.secret:SetText("Your vote is secret. The Ministry records only that you voted, never how.")

  -- The ballot paper
  local px, pw = 226, CW - 226
  local paper = frame(v, px, 0, pw, VH)
  O.paper = paper
  put(art(paper, "paper-ballot", "BACKGROUND"), paper, 0, 0)
  O.official = caps(paper, "bEyebrow", C.inkGold, 0.32)
  O.title = at(text(paper, "bTitle", C.rb, "CENTER", pw - 60), paper, 30, 38)
  O.title:SetMaxLines(2)
  O.mark = text(paper, "bItalic", C.ink2, "CENTER", pw - 60)
  O.mark:SetPoint("TOP", O.title, "BOTTOM", 0, -4)
  O.mark:SetText("Mark one name. Every citizen's vote counts the same.")
  O.rule = CreateFrame("Frame", nil, paper)
  O.rule:SetSize(pw - 60, 4)
  O.rule:SetPoint("TOP", O.mark, "BOTTOM", 0, -12)
  doubleRule(O.rule, 0, 0, pw - 60)

  O.opts = {}
  for i = 1, Ballot.MAX_CANDS do
    local b = CreateFrame("Button", nil, paper)
    b:SetSize(pw - 60, 58)
    b.index = i
    b.sel = color(b:CreateTexture(nil, "BACKGROUND", nil, 3), C.gold, 0.2)
    b.sel:SetAllPoints()
    local hl = color(b:CreateTexture(nil, "HIGHLIGHT"), C.gold, 0.12)
    hl:SetAllPoints()
    line(b, 0, 57, pw - 60, C.brown, 0.35)
    b.ring = put(art(b, "ring"), b, 10, 10)
    b.marked = put(scaled(art(b, "seal-off"), 38), b, 10, 10)
    b.name = at(text(b, "bName", C.ink, "LEFT", pw - 60 - 62 - 120), b, 62, 11)
    b.name:SetMaxLines(1)
    b.line = at(text(b, "bItalic", C.ink2, "LEFT", pw - 60 - 62 - 120), b, 62, 31)
    b.chip = chip(b)
    b.chip:SetPoint("RIGHT", b, "RIGHT", -14, 0)
    b:SetScript("OnClick", function() Page:Pick(i) end)
    O.opts[i] = b
  end

  O.hint = at(text(paper, "bHint", C.ink, "LEFT", 230), paper, 30, VH - 20 - 46)
  O.hintSub = text(paper, "bItalic13", C.ink2, "LEFT", 230)
  O.hintSub:SetPoint("TOPLEFT", O.hint, "BOTTOMLEFT", 0, -2)
  O.seal = pieceButton(paper, "btn-seal", function() Page:Seal() end)
  local sb = boxOf("btn-seal")
  at(O.seal, paper, pw - 30 - sb.w, VH - 20 - 29 - sb.h / 2)
  -- The button is drawn without its seal: the chosen candidate's party's goes in the gap.
  local ico = boxOf("btn-seal-ico")
  O.sealIco = art(O.seal, "seal-off", "ARTWORK", 1)
  O.sealIco.home = { ico.x - sb.x, ico.y - sb.y, ico.w }
  scaled(O.sealIco, ico.w)
  put(O.sealIco, O.seal, O.sealIco.home[1], O.sealIco.home[2])

  -- The stamp once a King has it; the held block while it waits.
  local over = CreateFrame("Frame", nil, paper)
  over:SetAllPoints()
  over:SetFrameLevel(paper:GetFrameLevel() + 10)
  O.stamp = putCenter(art(over, "stamp", "OVERLAY"), paper, pw - 26 - 75, VH - 18 - 75)
  local hb = boxOf("held")
  O.held = putCenter(art(over, "held", "OVERLAY"), paper, pw - 22 - hb.w / 2, VH - 16 - hb.h / 2)
  O.held.home = { paper, pw - 22 - hb.w / 2, VH - 16 - hb.h / 2 }
end

local HINTS = {
  sent = { "Sealed and sent to the Crown.", nil },
  held = { "Sealed, waiting for the Crown.", "It goes when a King logs in." },
  sending = { "Sealed. Sending it to the Crown.", "Waiting for a King's receipt." },
  late = { "Your ballot arrived too late.", "It reached the Crown after the polls closed." },
  ready = { "Ready to seal.", "Once sealed, it cannot be changed." },
  none = { "Mark your choice, then seal it.", "One name only." },
}

local function deliveryNote(state, kings)
  if state == "held" then
    return "Held here until a King comes online. The Kings see that a ballot is waiting, never how you voted. "
      .. "It counts if it arrives before the result is declared."
  end
  local on, off, me = {}, {}, false
  for _, k in ipairs(kings) do
    if k.me then me = true elseif k.online then on[#on + 1] = short(k.name) else off[#off + 1] = short(k.name) end
  end
  local later = #off > 0 and (" " .. table.concat(off, " and ") .. " is handed the count on logging in.") or ""
  if me then return "Counted in your own add-on." .. (#on > 0 and (" Also sent to " .. table.concat(on, " and ") .. ".") or "") .. later end
  if #on == 0 then
    return "No King is online. Seal it anyway: your add-on keeps it, even through a /reload, and sends it when one logs in."
  end
  if #off == 0 then
    return "By private whisper to " .. (#on == 2 and "the two Kings" or table.concat(on, " and ")) .. ". No one else receives it."
  end
  return "By private whisper to " .. table.concat(on, " and ") .. "." .. later
end

local function fillOpen(b)
  local d = b.d
  local kind = Ballot.KINDS[d.kind] or ""
  local state = Ballot:MyState(b)
  local e = Ballot:Mine(b.id)
  O.eyebrow:Set("Open ballot", 0, 0)
  O.blName:SetText(d.name)
  O.blKind:SetText(kind .. " · 2 hours")
  local closes = Ballot:CloseTime(b)
  O.left:SetText(Ballot:Left(closes))
  O.at:SetText("At " .. Ballot:Clock(closes) .. " realm time")

  local kings = Ballot:Kings()
  for i, r in ipairs(O.kings) do
    local k = kings[i]
    r:SetShown(k ~= nil)
    if k then
      r.on:SetShown(k.online)
      r.off:SetShown(not k.online)
      r.name:SetText(short(k.name) .. (k.me and " (you)" or ""))
      r.state:SetText(k.online and "online" or "offline")
    end
  end
  at(O.delivery, O.eyebrow.parent, 0, 202 + math.max(#kings, 1) * 22 + 2)
  O.delivery:SetText(#kings == 0 and "No one holds a Crown rank yet." or deliveryNote(state, kings))

  O.official:Set("Official ballot · " .. kind, (CW - 226) / 2, 22, CW - 226 - 60, "CENTER")
  O.title:SetText(d.name)
  local pick = Page.picked and Page.picked.id == b.id and Page.picked.i or nil
  local chosen = e and e.choice or pick
  local locked = state ~= "none"
  local prev = O.rule
  for i, opt in ipairs(O.opts) do
    local c = d.cands[i]
    opt:SetShown(c ~= nil)
    if c then
      local p = party(c.p)
      opt.name:SetText(c.n)
      opt.line:SetText(p.line)
      opt.chip:Set(p.chip, c.p)
      local on = chosen == i
      opt.sel:SetShown(on)
      swapSeal(opt.marked, sealOf(c.p), 38, opt, 10, 10)
      opt.marked:SetShown(on)
      opt.ring:SetShown(not on)
      opt:ClearAllPoints()
      opt:SetPoint("TOP", prev, "BOTTOM", 0, i == 1 and -4 or 0)
      opt:SetAlpha(1)
      opt.locked = locked
      prev = opt
    end
  end

  local key = state == "none" and (pick and "ready" or "none") or state
  local h = HINTS[key]
  O.hint:SetText(h[1])
  if key == "sent" then
    O.hintSub:SetText(e and e.receiptAt and ("Receipt from the Crown · " .. Ballot:Clock(e.receiptAt)) or "Recorded by the Crown")
  else
    O.hintSub:SetText(h[2])
  end
  O.seal:SetShown(state == "none")
  O.seal:SetUsable(pick ~= nil)
  local pc = pick and d.cands[pick]
  local home = O.sealIco.home
  swapSeal(O.sealIco, sealOf(pc and pc.p), home[3], O.seal, home[1], home[2])
  O.stamp:SetShown(state == "sent")
  -- the held block wears the seal of the party you voted for
  local held = O.held
  local hp = chosen and d.cands[chosen]
  local HELD_OF = { sh = "held-sh", ex = "held-ex" }
  local hname = HELD_OF[hp and hp.p] or "held"
  if held.artName ~= hname then
    held.artName = hname
    local piece = M.pieces["b_" .. hname]
    held:SetTexture(M.dir .. M.textures[piece.tex], "CLAMP", "CLAMP", "TRILINEAR")
    held:SetTexCoord(piece.l, piece.r, piece.t, piece.b)
    held.piece, held.slot = piece, M.slots[hname]
    MOTA.LiveText:Set(held, "b_" .. hname)
    held:SetSize(piece.w * held.k, piece.h * held.k)
    putCenter(held, held.home[1], held.home[2], held.home[3])
  end
  O.held:SetShown(state == "held")
end

---------------------------------------------------------------------------
-- Ballot: polls closed, or none open (one centred paper)
---------------------------------------------------------------------------

local Q = {}

local function buildQuiet(v)
  put(art(v, "paper-wide", "BACKGROUND"), v, 0, 0)
  Q.crown = scaled(art(v, "seal-crown"), 76)
  Q.official = scaled(art(v, "seal-off"), 112) -- large, so its ring text can be read
  Q.eyebrow = caps(v, "bEyebrow", C.inkGold, 0.32)
  Q.title = text(v, "bTitle", C.rb, "CENTER", 600)
  Q.prose = text(v, "bProse", C.ink, "CENTER", 460)
  Q.note = text(v, "bItalic", C.ink2, "CENTER", 560)
  Q.last = pieceButton(v, "btn-last", function() Page:SetView("results") end)
end

-- Stacks the parts down the middle, centred as a group.
local function fillQuiet(closed, b)
  local cx = CW / 2
  Q.crown:SetShown(closed)
  Q.official:SetShown(not closed)
  Q.last:SetShown(not closed)
  Q.note:SetShown(closed)
  local seal = closed and Q.crown or Q.official
  local sealH = closed and 76 or 112
  local eyebrow = closed and ("Polls closed · " .. b.d.name) or "No polls open"
  Q.title:SetText(closed and "The Crown is counting" or "The Ballot Hall is quiet")
  Q.prose:SetText(closed and "The result will be proclaimed here, and a herald will announce it to everyone online."
    or "When the Crown opens the polls, a herald calls \"The polls are open!\" and your ballot appears here.")
  if closed then
    local state = Ballot:MyState(b)
    Q.note:SetText(({ sent = "Your ballot was received.",
      held = "Your sealed ballot is still held. It counts if it reaches a King before the result is declared.",
      sending = "Your sealed ballot is still held. It counts if it reaches a King before the result is declared.",
      late = "Your ballot reached the Crown too late to count." })[state] or "You did not vote in this election.")
  end
  local eh = Q.eyebrow:Set(eyebrow, cx, 0, 600, "CENTER")
  local parts = { sealH, eh, Q.title:GetStringHeight(), Q.prose:GetStringHeight(),
    closed and Q.note:GetStringHeight() or (boxOf("btn-last").h + 6) }
  local total = 0
  for _, h in ipairs(parts) do total = total + h end
  total = total + 10 * (#parts - 1)
  local y = math.max(20, (VH - total) / 2)
  putCenter(seal, Q.eyebrow.parent, cx, y + sealH / 2)
  y = y + sealH + 10
  Q.eyebrow:Set(eyebrow, cx, y, 600, "CENTER")
  y = y + eh + 10
  at(Q.title, Q.eyebrow.parent, cx, y, "TOP")
  y = y + Q.title:GetStringHeight() + 10
  at(Q.prose, Q.eyebrow.parent, cx, y, "TOP")
  y = y + Q.prose:GetStringHeight() + 10
  if closed then
    at(Q.note, Q.eyebrow.parent, cx, y, "TOP")
  else
    at(Q.last, Q.eyebrow.parent, cx - boxOf("btn-last").w / 2, y + 6)
  end
end

---------------------------------------------------------------------------
-- Results: the proclamation and the record
---------------------------------------------------------------------------

local R = {}

local function buildRows(parent, n, nameW, barW, numW, rowH, font)
  local rows = {}
  for i = 1, n do
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(nameW + barW + numW + 24, rowH)
    r.name = at(text(r, "bName13", C.ink, "LEFT", nameW), r, 0, 0)
    r.name:SetMaxLines(1)
    r.tag = at(text(r, "bSmall13", C.ink2, "LEFT", nameW), r, 0, 17)
    r.bar = bar(r, barW, rowH > 30 and 16 or 14)
    r.bar:SetPoint("LEFT", r, "LEFT", nameW + 12, 0)
    r.num = text(r, font or "bNum", C.rb, "RIGHT")
    r.num:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    rows[i] = r
  end
  return rows
end

local function fillRows(rows, r, votes, anchor, x, y, gap, withPct)
  local total = Ballot.Sum(votes)
  for i, row in ipairs(rows) do
    local c = r.cands[i]
    row:SetShown(c ~= nil)
    if c then
      local v = tonumber(votes[i]) or 0
      row.name:SetText(c.n)
      row.tag:SetText(party(c.p).tag)
      row.bar:Set(total > 0 and v / total or 0, c.p)
      row.num:SetText(withPct and (v .. " · " .. pct(v, total) .. "%") or tostring(v))
      at(row, anchor, x, y)
      y = y + row:GetHeight() + gap
    end
  end
  return y - gap
end

local function buildResults(v)
  local paper = frame(v, 0, 0, LEFT_W, VH)
  R.paper = paper
  put(art(paper, "paper-half", "BACKGROUND"), paper, 0, 0)
  R.seal = putCenter(scaled(art(paper, "seal-tilt", "OVERLAY"), 74), paper, LEFT_W - 18 - 37, 14 + 37)
  R.eyebrow = caps(paper, "bEyebrow", C.inkGold, 0.32)
  R.title = text(paper, "bTitle", C.rb, "LEFT", LEFT_W - 60 - 70)
  R.prose = text(paper, "bProse", C.ink, "LEFT", LEFT_W - 60)
  R.prose:SetSpacing(3)
  R.rows = buildRows(paper, Ballot.MAX_CANDS, 150, LEFT_W - 60 - 150 - 70 - 24, 70, 32)
  R.rule = CreateFrame("Frame", nil, paper)
  R.rule:SetSize(LEFT_W - 60, 1)
  rule(R.rule, 0, 0, LEFT_W - 60)
  R.turnout = text(paper, "bSmall", C.ink2, "LEFT", LEFT_W - 60)

  -- The record of past elections
  caps(v, "bSec", C.rb, 0.22):Set("The record", RIGHT_X, 0)
  local head = frame(v, RIGHT_X, 26, RIGHT_W, 26)
  line(head, 0, 25, RIGHT_W, C.brown, 0.7)
  caps(head, "bRecHead", C.inkGold, 0.2):Set("Election", 10, 7)
  caps(head, "bRecHead", C.inkGold, 0.2):Set("Outcome", RIGHT_W - 10, 7, nil, "RIGHT")
  R.rec = {}
  for i = 1, 6 do
    local r = frame(v, RIGHT_X, 52 + (i - 1) * 50, RIGHT_W, 50)
    line(r, 0, 49, RIGHT_W, C.brown, 0.3)
    r.name = at(text(r, "bRow", C.ink, "LEFT", RIGHT_W - 130), r, 10, 8)
    r.name:SetMaxLines(1)
    r.sub = at(text(r, "bSmall13", C.ink2, "LEFT", RIGHT_W - 130), r, 10, 27)
    r.chip = chip(r)
    r.chip:SetPoint("RIGHT", r, "RIGHT", -10, 0)
    R.rec[i] = r
  end
  R.empty = at(text(v, "bItalic", C.ink2, "LEFT", RIGHT_W - 20), v, RIGHT_X + 10, 62)
  R.empty:SetText("No election has been declared yet.")
end

local function shortName(n)
  return (tostring(n):gsub("^(Lady) ", ""):gsub("^(Lord) ", ""):gsub("^(Sir) ", ""):gsub("^(Dame) ", ""))
end

local function fillResults()
  local list = Ballot:Results()
  local last = list[1]
  local x, w = 30, LEFT_W - 60
  local y = 24
  if last then
    local r = last.result
    y = y + R.eyebrow:Set("Proclaimed by the Crown · " .. Ballot:Date(last.resultT), x, y, w - 60) + 8
    R.title:SetText(r.name)
    at(R.title, R.paper, x, y)
    y = y + R.title:GetStringHeight() + 12
    R.prose:SetText(Ballot:Proclamation(r))
    at(R.prose, R.paper, x, y)
    y = y + R.prose:GetStringHeight() + 16
    y = fillRows(R.rows, r, r.votes, R.paper, x, y, 10, true) + 8
    R.rule:Show()
    at(R.rule, R.paper, x, y)
    local elig = tonumber(r.eligible) or 0
    R.turnout:SetText(("Turnout %d of %d active citizens (%d%%) · %s"):format(r.total, elig, pct(r.total, elig),
      r.tie and "Run-off within 48 hours" or "Announced by herald to everyone online"))
    at(R.turnout, R.paper, x, y + 12)
    R.turnout:Show()
    R.seal:Show()
  else
    y = y + R.eyebrow:Set("The record is empty", x, y, w) + 8
    R.title:SetText("No result yet")
    at(R.title, R.paper, x, y)
    R.prose:SetText("When the Crown declares a result, it is proclaimed here, and a herald announces it to everyone online.")
    at(R.prose, R.paper, x, y + R.title:GetStringHeight() + 12)
    for _, row in ipairs(R.rows) do row:Hide() end
    R.rule:Hide()
    R.turnout:Hide()
    R.seal:Hide()
  end
  for i, row in ipairs(R.rec) do
    local b = list[i]
    row:SetShown(b ~= nil)
    if b then
      local r = b.result
      row.name:SetText(r.name)
      row.sub:SetText((Ballot.KINDS[r.kind] or "Election") .. " · " .. date("%d %b", b.resultT):gsub("^0", ""))
      if r.tie then
        row.chip:Set("Tied · run-off", "ox")
      elseif r.w and r.cands[r.w] then
        row.chip:Set(shortName(r.cands[r.w].n), r.cands[r.w].p == "ind" and "ink" or r.cands[r.w].p)
      else
        row.chip:Set("No votes", "ink")
      end
    end
  end
  R.empty:SetShown(#list == 0)
end

---------------------------------------------------------------------------
-- Crown: the Open Polls form
---------------------------------------------------------------------------

local F = {}

local function input(parent, w, placeholder, onChange)
  local box = panel(CreateFrame("Frame", nil, parent), { "FFFAEB", 0.78 }, { { 0, 1, C.brown, 0.6 } })
  box:SetSize(w, 34)
  local e = CreateFrame("EditBox", nil, box)
  e:SetAllPoints()
  e:SetAutoFocus(false)
  e:SetFontObject(MOTA:Font("bProse"))
  e:SetTextColor(MOTA:RGB(C.ink))
  e:SetTextInsets(10, 10, 0, 0)
  e:SetMaxLetters(48)
  e.hint = text(box, "bItalic", "76634A")
  e.hint:SetPoint("LEFT", box, "LEFT", 10, 0)
  e.hint:SetText(placeholder)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnTextChanged", function(self)
    local t = self:GetText() or ""
    self.hint:SetShown(t == "")
    onChange(t)
  end)
  box.edit = e
  function box:Set(t)
    if (e:GetText() or "") ~= t then e:SetText(t) end
    e.hint:SetShown(t == "")
  end
  return box
end

local function blankForm()
  return { name = "", kind = "general", cands = { { n = "", p = "sh" }, { n = "", p = "ex" } } }
end

-- With an election called, the form comes filled in: its name and kind, and
-- each party's leader as its candidate (Charter 3.2: the leader stands for
-- Prime Minister). The Crown can still change any of it before opening.
local function electionForm()
  local El, Co = MOTA.Elect, MOTA.Contest
  if not (El and El:Pending() and Co:Current()) then return blankForm() end
  local cur = Co:Current()
  local f = { name = Co:Kind() .. ", " .. date("%B %Y", Co:PollAt()), kind = cur.kind == "snap" and "snap" or "general", cands = {}, auto = true }
  for _, p in ipairs({ "sh", "ex" }) do
    local leader = Co:Leader(p)
    if leader then f.cands[#f.cands + 1] = { n = MOTA:Short(leader.name), p = p } end
  end
  for _, p in ipairs({ "sh", "ex" }) do
    if #f.cands >= 2 then break end
    local taken = false
    for _, c in ipairs(f.cands) do taken = taken or c.p == p end
    if not taken then f.cands[#f.cands + 1] = { n = "", p = p } end
  end
  return f
end
Page.ElectionForm = electionForm

local function formReady()
  local f = Page.form
  local named = 0
  for _, c in ipairs(f.cands) do
    if (c.n or ""):match("%S") then named = named + 1 end
  end
  return (f.name or ""):match("%S") ~= nil and named >= 2
end

local function updateFormButtons()
  local ready = formReady()
  F.open:SetUsable(ready)
  F.add:SetUsable(#Page.form.cands < Ballot.MAX_CANDS)
  F.note:SetText(ready and ("Polls stay open 2 hours, until "
    .. Ballot:Clock(GetServerTime() + MOTA.CONST.BALLOT_WINDOW_SECONDS) .. " realm time.")
    or "Give the election a name and at least two candidates.")
end

local function buildForm(v)
  local paper = frame(v, 0, 0, LEFT_W, VH)
  F.paper = paper
  put(art(paper, "paper-half", "BACKGROUND"), paper, 0, 0)
  local x, w = 24, LEFT_W - 48
  at(text(paper, "bTitle21", C.rb), paper, x, 20):SetText("Open the polls")
  caps(paper, "eyebrow", C.inkGold, 0.32):Set("Crown only", x + w, 28, nil, "RIGHT")

  caps(paper, "bEyebrow", C.inkGold, 0.24):Set("Election", x, 60)
  F.name = input(paper, w, "e.g. The Snap Election", function(t) Page.form.name = t; Page.form.auto = nil; updateFormButtons() end)
  at(F.name, paper, x, 76)

  caps(paper, "bEyebrow", C.inkGold, 0.24):Set("Kind", x, 122)
  F.kinds = {}
  local px = x
  for _, k in ipairs(Ballot.KIND_ORDER) do
    local name = "pill-" .. k
    local b = CreateFrame("Button", nil, paper)
    local box = boxOf(name)
    b:SetSize(box.w, box.h)
    b.off = put(art(b, name), b, 0, 0)
    b.on = put(art(b, name .. "-on"), b, 0, 0)
    b:SetScript("OnClick", function() Page.form.kind = k; Page:Refresh() end)
    at(b, paper, px, 138)
    px = px + box.w + 6
    b.kind = k
    F.kinds[#F.kinds + 1] = b
  end

  caps(paper, "bEyebrow", C.inkGold, 0.24):Set("Candidates", x, 182)
  F.cands = {}
  local xw = boxOf("xbtn").w
  -- The name and party boxes run the full width, like the Election box. The
  -- remove X floats inside the name box at its right end, with no ring.
  local nameW = w
  -- Each candidate has two rows: the name, then their party beneath it. Room
  -- for two shows at once; the list scrolls for a third and fourth.
  local scroll = CreateFrame("ScrollFrame", nil, paper)
  scroll:SetSize(w, CAND_VIEW)
  at(scroll, paper, x, 198)
  local list = CreateFrame("Frame", nil, scroll)
  list:SetSize(w, CAND_ROW * Ballot.MAX_CANDS)
  scroll:SetScrollChild(list)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local top = math.max(0, CAND_ROW * #Page.form.cands - CAND_VIEW)
    self:SetVerticalScroll(math.max(0, math.min(top, self:GetVerticalScroll() - delta * 40)))
  end)
  F.scroll = scroll
  for i = 1, Ballot.MAX_CANDS do
    local row = frame(list, 0, (i - 1) * CAND_ROW, w, 72)
    row.name = input(row, nameW, "Name", function(t)
      if Page.form.cands[i] then Page.form.cands[i].n = t; Page.form.auto = nil end
      updateFormButtons()
    end)
    at(row.name, row, 0, 0)
    row.name.edit:SetTextInsets(10, xw + 6, 0, 0) -- typing stops short of the X
    row.remove = pieceButton(row, "xbtn", function()
      table.remove(Page.form.cands, i)
      Page:Refresh()
    end)
    at(row.remove, row, w - xw - 2, 2)
    row.remove:SetFrameLevel(row.name.edit:GetFrameLevel() + 2) -- above the typing box, so it takes the click
    local pb = panel(CreateFrame("Button", nil, row), { "FFFAEB", 0.78 }, { { 0, 1, C.brown, 0.6 } })
    pb:SetSize(nameW, 34)
    at(pb, row, 0, 38)
    pb.label = text(pb, "bProse", C.ink)
    pb.label:SetPoint("LEFT", pb, "LEFT", 8, 0)
    pb.caret = text(pb, "bSmall13", C.ink2, "RIGHT")
    pb.caret:SetPoint("RIGHT", pb, "RIGHT", -8, 0)
    pb.caret:SetText("change")
    local hl = color(pb:CreateTexture(nil, "HIGHLIGHT"), C.gold, 0.15)
    hl:SetAllPoints()
    pb:SetScript("OnClick", function()
      local c = Page.form.cands[i]
      if not c then return end
      local order = Ballot.PARTY_ORDER
      for j, p in ipairs(order) do
        if p == c.p then c.p = order[j % #order + 1]; break end
      end
      Page:Refresh()
    end)
    row.party = pb
    F.cands[i] = row
  end
  F.note = text(paper, "bItalic13", C.ink2, "LEFT", w)

  F.add = pieceButton(paper, "btn-add", function()
    if #Page.form.cands < Ballot.MAX_CANDS then
      table.insert(Page.form.cands, { n = "", p = "ind" })
      Page:Refresh()
      F.scroll:SetVerticalScroll(math.max(0, CAND_ROW * #Page.form.cands - CAND_VIEW)) -- show the new one
    end
  end)
  local ab, ob = boxOf("btn-add"), boxOf("btn-open")
  at(F.add, paper, x, VH - 20 - ob.h + (ob.h - ab.h) / 2)
  F.open = pieceButton(paper, "btn-open", function() Page:OpenPolls() end)
  at(F.open, paper, x + w - ob.w, VH - 20 - ob.h)

  -- What happens when the polls open (.plate.blue)
  local plate = panel(frame(v, RIGHT_X, 0, RIGHT_W, 300), { "1D3B7C", 1 },
    { { 0, 1, C.leaf, 1 }, { 1, 2, "142B5E", 1 }, { 3, 1, C.gold, 0.55 } })
  F.plate = plate
  F.sec = caps(plate, "bSec", C.leaf, 0.22)
  F.ticks = {}
  for i = 1, 6 do
    local fs = text(plate, "bRow", C.sky, "LEFT", RIGHT_W - 40 - 18)
    local d = art(plate, "diamond")
    F.ticks[i] = { fs = fs, dia = d }
  end
end

local TICKS = {
  "A herald calls \"The polls are open!\" to everyone online.",
  "Each ballot comes by private whisper to the two Kings, never to the guild or the officers.",
  "Anyone who logs in while polls are open is sent the ballot.",
  "Who may vote: members active in the last 30 days (%d today).",
  "With no King online, sealed ballots wait with their voters. They still count if they reach you before you declare.",
  "Ballots are taken for two hours. Then you close the polls and declare the result.",
}

local function fillForm()
  local f = Page.form
  F.name:Set(f.name or "")
  for _, b in ipairs(F.kinds) do
    b.on:SetShown(f.kind == b.kind)
    b.off:SetShown(f.kind ~= b.kind)
  end
  local n = #f.cands
  for i, row in ipairs(F.cands) do
    local c = f.cands[i]
    row:SetShown(c ~= nil)
    if c then
      row.name:Set(c.n or "")
      row.party.label:SetText(party(c.p).tag)
      row.remove:SetUsable(n > 2)
    end
  end
  at(F.note, F.paper, 24, 198 + CAND_VIEW + 6)
  local top = math.max(0, CAND_ROW * n - CAND_VIEW)
  if F.scroll:GetVerticalScroll() > top then F.scroll:SetVerticalScroll(top) end
  updateFormButtons()

  local y = 18
  y = y + F.sec:Set("When you open the polls", 20, y, RIGHT_W - 40) + 12
  for i, t in ipairs(F.ticks) do
    local s = TICKS[i]
    if i == 4 then s = s:format(MOTA:ActiveCitizens()) end
    t.fs:SetText(s)
    at(t.fs, F.plate, 38, y)
    putCenter(t.dia, F.plate, 25, y + 8)
    t.dia:SetVertexColor(MOTA:RGB(C.leaf))
    y = y + t.fs:GetStringHeight() + 9
  end
  F.plate:SetHeight(y + 9)
end

---------------------------------------------------------------------------
-- Crown: the live count, closing, declaring
---------------------------------------------------------------------------

local K = {}

local function buildCount(v)
  local paper = frame(v, 0, 0, LEFT_W, VH)
  K.view = v
  K.paper = paper
  put(art(paper, "paper-half", "BACKGROUND"), paper, 0, 0)
  putCenter(scaled(art(paper, "seal-tilt", "OVERLAY"), 60), paper, LEFT_W - 16 - 30, 12 + 30)
  local w = LEFT_W - 52
  K.eyebrow = caps(paper, "eyebrow", C.inkGold, 0.32)
  K.title = text(paper, "bTitle", C.rb, "LEFT", w - 60)
  K.title:SetMaxLines(2)
  K.when = text(paper, "bSmall", C.ink2, "LEFT", w)
  K.dbl = CreateFrame("Frame", nil, paper)
  K.dbl:SetSize(w, 4)
  doubleRule(K.dbl, 0, 0, w)
  K.rows = buildRows(paper, Ballot.MAX_CANDS, 140, w - 140 - 34 - 24, 34, 30, "bNum")
  K.rule = CreateFrame("Frame", nil, paper)
  K.rule:SetSize(w, 1)
  rule(K.rule, 0, 0, w)
  K.turnout = text(paper, "bSmall", C.ink2, "LEFT", w)
  K.heldNote = panel(CreateFrame("Frame", nil, paper), { C.gold, 0.12 }, { { 0, 1, C.brown, 0.45 } })
  K.heldNote:SetWidth(w)
  K.heldText = at(text(K.heldNote, "bSmall", C.ink, "LEFT", w - 20), K.heldNote, 10, 7)
  K.proc = text(paper, "bItalic", C.ink, "LEFT", w)
  K.warn = panel(CreateFrame("Frame", nil, paper), { "9E1B22", 0.08 }, { { 0, 1, C.oxblood, 0.45 } })
  K.warn:SetWidth(w)
  K.warnText = at(text(K.warn, "bSmall", C.oxblood, "LEFT", w - 20), K.warn, 10, 7)

  local function bottomButton(name, fn)
    local b = pieceButton(paper, name, fn)
    local box = boxOf(name)
    at(b, paper, 26 + w - box.w, VH - 20 - box.h)
    return b
  end
  K.close = bottomButton("btn-close", function() Page:ClosePolls() end)
  K.declare = bottomButton("btn-declare", function() Page:Declare() end)
  K.runoff = bottomButton("btn-runoff", function() Page:Runoff() end)
  K.foot = text(paper, "bItalic13", C.ink2, "LEFT", 150)

  -- The two counts
  local plate = panel(frame(v, RIGHT_X, 0, RIGHT_W, 200), { "FFF9E6", 0.45 },
    { { 0, 1, C.brown, 0.55 }, { 4, 1, C.brown, 0.3 } })
  K.plate = plate
  caps(plate, "bSec", C.rb, 0.22):Set("The two counts", 18, 16)
  K.kings = {}
  for i = 1, 3 do
    local r = frame(plate, 18, 42 + (i - 1) * 46, RIGHT_W - 36, 36)
    put(art(r, "portrait-king"), r, 0, 0)
    r.init = text(r, "bPortrait", C.leaf, "CENTER")
    r.init:SetPoint("CENTER", r, "TOPLEFT", 18, -18)
    r.name = at(text(r, "bName13", C.ink, "LEFT", 150), r, 46, 2)
    r.name:SetMaxLines(1)
    r.role = at(text(r, "bSmall13", C.ink2, "LEFT", 150), r, 46, 19)
    r.num = text(r, "bNum", C.rb, "RIGHT")
    r.num:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.off = text(r, "bItalic13", C.ink2, "RIGHT")
    r.off:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    K.kings[i] = r
  end
  K.plateRule = CreateFrame("Frame", nil, plate)
  K.plateRule:SetSize(RIGHT_W - 36, 1)
  rule(K.plateRule, 0, 0, RIGHT_W - 36)
  K.status = chip(plate)
  K.statusText = text(plate, "bItalic13", C.ink2, "LEFT", RIGHT_W - 36)
  K.statusText:SetFontObject(MOTA:Font("bSmall13"))

  K.sunk = panel(frame(v, RIGHT_X, 0, RIGHT_W, 59), { C.brown, 0.07 }, { { 0, 1, C.brown, 0.45 } })
  at(text(K.sunk, "bSmall", C.ink), K.sunk, 12, 9):SetText("Sealed, not yet delivered")
  at(text(K.sunk, "bSmall", C.ink), K.sunk, 12, 32):SetText("Second ballots refused")
  K.heldNum = text(K.sunk, "bNum", C.rb, "RIGHT")
  K.heldNum:SetPoint("TOPRIGHT", K.sunk, "TOPRIGHT", -12, -8)
  K.refusedNum = text(K.sunk, "bNum", C.rb, "RIGHT")
  K.refusedNum:SetPoint("TOPRIGHT", K.sunk, "TOPRIGHT", -12, -31)
  K.keeps = text(v, "bItalic13", C.ink2, "LEFT", RIGHT_W)
  K.keeps:SetText("The count keeps no names. The guild's record shows who voted, never how.")
end

-- The count shown in the Crown view, and what the two Kings' counts say.
local function countInfo(b)
  local t = Ballot:Tally(b.id)
  local votes = {}
  for i = 1, #b.d.cands do votes[i] = t.counts[i] or 0 end
  local total = Ballot.Sum(votes)
  local others = {}
  for _, k in ipairs(Ballot:Kings()) do
    if not k.me then others[#others + 1] = k end
  end
  local status
  for _, k in ipairs(others) do
    local pc = Ballot:PeerCount(b.id, k.name)
    k.count = pc
    if not k.online then
      status = status or { "ink", short(k.name) .. " offline",
        "When " .. short(k.name) .. " logs in, your add-on whispers the count across, so both Kings hold it." }
    elseif pc and not pc.same then
      local diff = math.abs(pc.total - total)
      status = { "ox", "Counts differ by " .. diff, short(k.name) .. "'s add-on has " .. diff .. " "
        .. (pc.total < total and "fewer" or "more") .. " ballots, perhaps after a disconnect. Settle it between you before declaring.",
        differ = diff }
    elseif not pc then
      status = status or { "ink", "Comparing counts", "Your add-on is comparing its count with " .. short(k.name) .. "'s." }
    end
  end
  if not status then
    status = #others > 0 and { "teal", "Counts agree", "Both Kings' add-ons hold the same count." }
      or { "ink", "One King", "Only one Crown member is on the roster, so there is no second count." }
  end
  return votes, total, t, others, status
end

local function fillCount(b, stage)
  local closed = stage == "closed"
  local x, w = 26, LEFT_W - 52
  local votes, total, t, others, status = countInfo(b)
  local y = 20
  y = y + K.eyebrow:Set(closed and "Polls closed · final count" or "Live count · only the Crown sees this", x, y, w - 64) + 8
  K.title:SetText(b.d.name)
  at(K.title, K.paper, x, y)
  y = y + K.title:GetStringHeight() + 6
  K.when:SetShown(not closed)
  if not closed then
    local c = Ballot:CloseTime(b)
    K.when:SetText("Polls close in " .. Ballot:Left(c) .. " · " .. Ballot:Clock(c) .. " realm time")
    at(K.when, K.paper, x, y)
    y = y + K.when:GetStringHeight() + 8
  end
  at(K.dbl, K.paper, x, y)
  y = y + 14
  y = fillRows(K.rows, b.d, votes, K.paper, x, y, 9, false) + 10
  at(K.rule, K.paper, x, y)
  y = y + 10
  local elig = MOTA:ActiveCitizens()
  K.turnout:SetText(("%s%d of %d active citizens (%d%%)"):format(closed and "Turnout " or "So far ", total, elig, pct(total, elig)))
  at(K.turnout, K.paper, x, y)
  y = y + K.turnout:GetStringHeight() + 10

  local held = Ballot:HeldCount(b)
  K.heldNote:SetShown(closed and held > 0)
  if closed and held > 0 then
    K.heldText:SetText(held .. (held == 1 and " sealed ballot hasn't" or " sealed ballots haven't")
      .. " reached the Crown yet. They still count if their voters log in before the result is declared.")
    K.heldNote:SetHeight(K.heldText:GetStringHeight() + 14)
    at(K.heldNote, K.paper, x, y)
    y = y + K.heldNote:GetHeight() + 10
  end

  local leaders, top = Ballot:Leaders(votes, #votes)
  local tie = closed and total > 0 and #leaders > 1
  K.close:SetShown(not closed)
  K.declare:SetShown(closed and not tie)
  K.runoff:SetShown(tie)
  K.proc:SetShown(closed)
  K.warn:SetShown(closed and not tie and status.differ ~= nil)
  local button = not closed and K.close or tie and K.runoff or K.declare
  if closed then
    if tie then
      local scores = {}
      for _ in ipairs(leaders) do scores[#scores + 1] = top end
      K.proc:SetText("Tied, " .. table.concat(scores, " to ") .. ". By the Charter, the tied candidates face a run-off within 48 hours.")
    else
      local r = { cands = b.d.cands, votes = votes, total = total, w = total > 0 and leaders[1] or nil }
      K.proc:SetText("\"" .. Ballot:Proclamation(r) .. "\"")
    end
    at(K.proc, K.paper, x, y)
    y = y + K.proc:GetStringHeight() + 8
    if status.differ then
      K.warnText:SetText("The Kings' counts differ by " .. status.differ .. ". Settle it before declaring.")
      K.warn:SetHeight(K.warnText:GetStringHeight() + 14)
      at(K.warn, K.paper, x, y)
    end
  end
  local bw = boxOf(not closed and "btn-close" or tie and "btn-runoff" or "btn-declare").w
  K.foot:SetWidth(w - bw - 12)
  K.foot:SetText(not closed and "Close now, or when the two hours are up."
    or tie and "The tie is proclaimed, and the run-off is set up for you."
    or "A herald announces it to everyone online.")
  K.foot:ClearAllPoints()
  K.foot:SetPoint("LEFT", button, "LEFT", -(w - bw), 0)

  -- The two counts
  local list = { { name = MOTA.me, me = true, online = true } }
  for _, k in ipairs(others) do list[#list + 1] = k end
  for i, r in ipairs(K.kings) do
    local k = list[i]
    r:SetShown(k ~= nil)
    if k then
      r.init:SetText(initials(k.name))
      r.name:SetText(short(k.name))
      r.role:SetText((MOTA:RankOf(k.name) or "The Crown") .. (k.me and " · you" or ""))
      local num = k.me and tostring(total) or (k.online and k.count and tostring(k.count.total)) or nil
      r.num:SetText(num or "")
      r.off:SetText(num and "" or (k.online and "comparing" or "offline"))
    end
  end
  local py = 42 + #list * 46
  at(K.plateRule, K.plate, 18, py)
  K.status:Set(status[2], status[1])
  at(K.status, K.plate, 18, py + 10)
  K.statusText:SetText(status[3])
  at(K.statusText, K.plate, 18, py + 40)
  K.plate:SetHeight(py + 40 + K.statusText:GetStringHeight() + 16)
  at(K.sunk, K.view, RIGHT_X, K.plate:GetHeight() + 12)
  K.heldNum:SetText(tostring(held))
  K.refusedNum:SetText(tostring(t.refused or 0))
  at(K.keeps, K.view, RIGHT_X, K.plate:GetHeight() + 12 + 59 + 12)
end

---------------------------------------------------------------------------
-- Building, switching and refreshing
---------------------------------------------------------------------------

local function build()
  if built then return end
  built = true
  root = CreateFrame("Frame", nil, UI.window)
  root:SetSize(CW, CH)
  local parch = M.slots.parch
  root:SetPoint("TOPLEFT", UI.window, "TOPLEFT", parch.x + PAD_L, -(parch.y + PAD_T))
  buildRibbons()
  views = {}
  for _, id in ipairs({ "open", "quiet", "results", "form", "count" }) do
    views[id] = frame(root, 0, VIEW_Y, CW, VH)
  end
  buildOpen(views.open)
  buildQuiet(views.quiet)
  buildResults(views.results)
  buildForm(views.form)
  buildCount(views.count)
  Page.frames = views
end

Page.form = electionForm()

-- The view a ribbon shows: "ballot", "results" or "crown".
function Page:CurrentView()
  local b = Ballot:Current()
  local stage = Ballot:Stage(b)
  local view = self.view
  if view == "crown" and not Ballot:IsKing() then view = nil end
  return view or (stage == "open" and "ballot" or "results"), b, stage
end

function Page:SetView(view)
  self.view = view
  self:Refresh()
end

function Page:Refresh()
  if not root or not root:IsShown() then return end
  local view, b, stage = self:CurrentView()
  local king = Ballot:IsKing()
  local dot = stage == "open" and Ballot:MyState(b) == "none"
  layoutRibbons(view, dot, king)

  local show
  if view == "ballot" then
    show = stage == "open" and "open" or "quiet"
  elseif view == "results" then
    show = "results"
  else
    show = stage == "none" and "form" or "count"
  end
  for id, f in pairs(views) do f:SetShown(id == show) end
  if show == "open" then
    fillOpen(b)
  elseif show == "quiet" then
    fillQuiet(stage == "closed", b)
  elseif show == "results" then
    fillResults()
  elseif show == "form" then
    fillForm()
  else
    fillCount(b, stage)
  end
  self.shown = show

  topNote:SetShown(not king)
  if not king then
    topNote:SetText(stage == "open" and ("Polls close " .. Ballot:Clock(Ballot:CloseTime(b)))
      or stage == "closed" and "Polls closed" or "No polls open")
    topNote:ClearAllPoints()
    topNote:SetPoint("TOPRIGHT", root, "TOPLEFT", CW, -12)
  end
end

---------------------------------------------------------------------------
-- What the buttons do
---------------------------------------------------------------------------

local function say(ok, why)
  if not ok and why then MOTA:Print(why) end
  return ok
end

function Page:Pick(i)
  local b = Ballot:Current()
  if Ballot:Stage(b) ~= "open" or Ballot:MyState(b) ~= "none" or not b.d.cands[i] then return end
  self.picked = { id = b.id, i = i }
  self:Refresh()
end

function Page:Seal()
  local b = Ballot:Current()
  local pick = self.picked and b and self.picked.id == b.id and self.picked.i
  if not pick then return end
  if say(Ballot:Seal(pick)) then
    self.picked = nil
    if SOUNDKIT and SOUNDKIT.READY_CHECK then PlaySound(SOUNDKIT.READY_CHECK) end
  end
  self:Refresh()
end

function Page:OpenPolls()
  if not formReady() then return end
  if say(Ballot:Open(self.form.name, self.form.kind, self.form.cands)) then
    self.form = electionForm()
    self.view = "crown"
  end
  self:Refresh()
end

function Page:ClosePolls()
  say(Ballot:Close())
  self:Refresh()
end

function Page:Declare()
  if say(Ballot:Declare(false)) then self.view = "results" end
  self:Refresh()
end

function Page:Runoff()
  local rec = say(Ballot:Declare(true))
  if rec then
    self.form = Ballot:RunoffForm(rec.d)
    self.view = "crown"
  end
  self:Refresh()
end

function Page:Show(show)
  if show then build() end
  if not root then return end
  root:SetShown(show)
  if self.ticker then self.ticker:Cancel() self.ticker = nil end
  if show then
    -- A form the Crown hasn't touched follows the election (leaders can change).
    local f = self.form
    local untouched = f.auto or (f.name == "" and not (f.cands[1].n or ""):match("%S") and not (f.cands[2] and (f.cands[2].n or ""):match("%S")))
    if untouched then self.form = electionForm() end
    self:Refresh()
    -- The countdown and the close of the polls move with the clock.
    self.ticker = C_Timer.NewTicker(5, function() Page:Refresh() end)
  end
end

MOTA:Listen("PAGE_SHOWN", function(_, id) Page:Show(id == PAGE_ID) end)
MOTA:Listen("BALLOT_CHANGED", function() Page:Refresh() end)
MOTA:Listen("ROSTER_UPDATED", function() Page:Refresh() end)

-- For the pretend game client's checks (tools/sim).
Page.parts = { open = O, quiet = Q, results = R, form = F, count = K }
