-- Ministry of the Allied: the game's Map & Quest Log, dressed in the window's
-- skin (Batch D5c; World map skins board, approved by Max 8 Nov).
--
-- The dress is our own pictures (Media/wmap_<skin>.tga, tools/textures/
-- worldmap.html) and the board's fonts, on the board's layout:
--   our own two frames on the map: the leather and grain behind everything
--   (with the quest log's panel and the divider), and the rim, title, rule,
--   seal, the map's edge and (the Crown) the filigree corners;
--   the game's own buttons and boxes, moved and sized to the board (out of
--   combat), each wearing our picture under its own art, whose own art is
--   faded out: the close and enlarge knobs (flush in the rim's corner), the
--   location bar and its crumbs, the tracking filter and its reset, the
--   quest log's search box, count, gear, zone headers and scroll bar (its
--   arrows taken away, Max 8 Nov), the map pin button (a gold diamond), the
--   position plate and the quest log toggle;
--   their words in the board's fonts and inks (Cinzel crumbs and headers,
--   EB Garamond in the search box, the count as "QUESTS:" and its number).
-- Their clicks, and the quest rows, stay the game's.
--
-- Board sizes are canvas units (World map skins board: the window 1100 x
-- 749, the map's top 100 below the window's): in the game one canvas unit is
-- (the map's top below the frame's) / 100, so the header fits the game's map
-- exactly. Pictures that stretch are nine-slices (Media.lua wmap.slice/box).
--
-- Everything changed is remembered and put back for Plain: the game's art's
-- alpha, the moved parts' anchors and sizes, the words' fonts and colours.
-- Nothing of Blizzard's code is replaced: we listen after the fact
-- (hooksecurefunc, HookScript). A part this client doesn't have is left
-- plain, never an error. In combat nothing is moved: that waits for
-- PLAYER_REGEN_ENABLED (the pictures and fonts may change, but not on a
-- protected part).
--
-- Settings: MOTA.db.settings.mapSkin = "party" (as the window: the Crown's to
-- the Crown, a party's to its members, the Ministry's to the rest),
-- "ministry" or "plain". On from the start; kept until changed by hand.

local _, MOTA = ...
local M = MOTA.Media
local WS = {}
MOTA.WorldMapSkin = WS

local WM = M.wmap
local FILE_OF = { UNREGISTERED = "ministry", SILVERHAND = "silverhand", AZEROTH_EXCHANGE = "exchange", CROWN = "crown" }

-- The board's layout (canvas units from the window's top-left; World map skins board).
local B = {
  mapTop = 100,                 -- the map's top
  titleH = 44, sepH = 3,        -- the title strip and the rule along its foot
  -- the title's capitals centred between the rim's inner rule and the rule under the strip
  -- (Max, 8 Nov: it sat high); they sit 1.8 above the picture's middle (Q's tail, the shadow)
  titleMid = 25, titleCaps = 1.8,
  knobW = 36, knobH = 38, knobGap = 2, inset = 2, -- enlarge and close, flush in the rim's corner
  rowTop = 58, rowH = 30,       -- the search box, count and gear
  -- the location bar: 9 under the rule and 8 above the map, the leather showing (Max, 8 Nov);
  -- its crumbs 2 in each side
  navLeft = 100, navTop = 56, navH = 36, crumbH = 32, navToMapRight = 58,
  -- the filter at the map's top right, 14 past the bar; as tall as the bar (Max, 8 Nov)
  trackW = 38, trackH = 32, trackToMapRight = 6, navToTrack = 14,
  resetX = 26, resetY = -10, resetS = 19,       -- its reset cross, on its corner
  searchW = 226, countW = 118, gearS = 30, gap = 6, gearRight = 10,
  searchIn = 6,                 -- the search box's magnifier and words, this much further in than the game's
  logRight = 32, scrollW = 18,  -- the log's panel and its scroll bar: 2 above and below the map
  rowInset = 6,                 -- the log's first row (the zone header) below the panel's top
  chevS = 11, chevGap = 7,      -- a crumb's dropdown chevron, past its words
  pinS = 30, pinIn = 10,        -- the map pin button, 10 in from the map's top-left corner
  -- the seal: the board's against the window, at 0.7 (the size Max kept on 8 Nov; the game's
  -- header is shallower than the board's against its window), moved up and left together
  -- until it clears the map as on the board (Max, 8 Nov)
  sealFit = 0.7,
}
-- The board's fonts and sizes (px = canvas units).
local FONT = {
  crumb = { "cinzel", 12.5 }, search = { "garamondItalic", 14 }, countLabel = { "cinzel", 11 },
  countNum = { "garamondMedium", 15 }, zone = { "cinzel", 13 }, plateLabel = { "cinzel", 10.5 },
  plateNum = { "garamondMedium", 15 },
}
-- The board's inks per skin: --home-ink, --crumb-ink, --cur-ink.
local INKS = {
  ministry = { home = "E5CF92", step = "C9D6F5", cur = "FFF3C4" },
  silverhand = { home = "1F4290", step = "D5DEF0", cur = "FFFFFF" },
  exchange = { home = "5A0E13", step = "F2CDBE", cur = "FFF3C4" },
  crown = { home = "3E0A2F", step = "EBCBDF", cur = "FFF3C4" },
}

local map, back, front
local weak = { __mode = "k" }
local dressed = setmetatable({}, weak) -- [frame or region] = our dress
local faded = setmetatable({}, weak)   -- [region or frame] = its alpha before we faded it
local moved = setmetatable({}, weak)   -- [frame] = { points, w, h } before we moved it
local styled = setmetatable({}, weak)  -- [font string] = { font = { file, size, flags }, color = { r, g, b, a }, role }
local heights = setmetatable({}, weak) -- [frame] = its height before we set it (the crumbs)
local insets = setmetatable({}, weak)  -- [button] = its mouse insets before we set them (the crumbs' arrows)
local textInsets = setmetatable({}, weak) -- [edit box] = its text insets before we set them (the search box)
local pending = false

-- One of the game's parts, if this client has it (a frame or a table; anything else is not one).
local function get(obj, key)
  local v = type(obj) == "table" and obj[key] or nil
  if type(v) == "table" then return v end
end

-- A position or size the game tells us, if it's a plain number (this client
-- can hand back secret values, which can't be counted with).
local function num(v)
  if type(v) ~= "number" then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

---------------------------------------------------------------------------
-- Which skin, and the scale
---------------------------------------------------------------------------

-- The skin key the map wears, or nil for Plain.
function WS:Key()
  local s = MOTA.db and MOTA.db.settings.mapSkin or "party"
  if s == "plain" then return nil end
  if s == "ministry" then return "UNREGISTERED" end
  return MOTA.skin and MOTA.skin.KEY or "UNREGISTERED"
end

local function file() return FILE_OF[WS.on] or "ministry" end
local function piece(name) return M.pieces["wm_" .. file() .. ":" .. name] end
local function path(tex) return M.dir .. M.textures[tex] end

local function box() return get(map, "BorderFrame") or map end

-- Game units per canvas unit: the map's top below the frame's, against the board's.
-- Before the map is laid out: the location bar's height against the board's.
local function scale()
  local sc, bx = get(map, "ScrollContainer"), box()
  local ft, st = num(bx and bx.GetTop and bx:GetTop()), num(sc and sc.GetTop and sc:GetTop())
  if ft and st and ft - st > 40 then return (ft - st) / B.mapTop end
  local nav = get(map, "NavBar")
  local h = nav and nav.GetHeight and nav:GetHeight()
  if type(h) == "number" and h > 10 and not WS.navMoved then return h / B.navH end
  return WS.k or 0.8
end

-- Game units per canvas unit by the window's height (the board's window is 749
-- tall): for what the header's room doesn't bound (the seal, the quest log's
-- words). The game's header is shallower than the board's against its window,
-- so by the header alone these came out about a fifth too small (Max, 8 Nov).
local function scaleH()
  local bx = box()
  local h = num(bx and bx.GetHeight and bx:GetHeight())
  if h and h > 200 then return h / 749 end
  return WS.k or 1
end

-- The seal: its picture (Media "wm_<file>:seal", the board's emblem with a
-- tight shadow), its scale, and where it sits: x, y of its top-left from the
-- frame's (y up), and its right edge from the frame's left. At the board's
-- place, moved up and left together by however much its foot would reach
-- lower than the board's against the map's top (Max, 8 Nov: it touched the map).
local function sealAt(k)
  local sp = piece("seal")
  if not sp then return end
  local ks = scaleH() * B.sealFit
  local d = math.max(0, (sp.y + sp.h) * (ks - k))
  return sp, ks, sp.x * ks - d, -sp.y * ks + d, (sp.x + sp.w) * ks - d
end

-- A part we may change now: in combat a protected part waits.
local function free(f)
  return not (InCombatLockdown() and f.IsProtected and f:IsProtected())
end

---------------------------------------------------------------------------
-- Fading, moving and restyling the game's parts (each remembered for Plain)
---------------------------------------------------------------------------

local function fade(r)
  if not r or not r.SetAlpha or dressed[r] then return end
  if faded[r] == nil then faded[r] = r:GetAlpha() end
  r:SetAlpha(0)
end

-- Every texture region of a frame, but ours and the ones in keep.
local function fadeRegions(f, keep)
  if not f or not f.GetRegions then return end
  for _, r in ipairs({ f:GetRegions() }) do
    if r.IsObjectType and r:IsObjectType("Texture") and not dressed[r] and not (keep and keep[r]) then fade(r) end
  end
end

-- A button's state art (normal, pushed, highlight, disabled) and its other pictures.
local function fadeButton(b, keep)
  if not b then return end
  for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
    local fn = b[g]
    local t = fn and fn(b)
    if type(t) == "table" and not (keep and keep[t]) then fade(t) end
  end
  fadeRegions(b, keep)
end

-- Moves a game part (out of combat only), remembering where the game had it.
local function place(f, w, h, ...)
  if not f or not f.SetPoint or InCombatLockdown() then return false end
  if not moved[f] then
    local pts = {}
    for i = 1, 8 do
      local p, rel, rp, x, y = f:GetPoint(i)
      if not p then break end
      pts[i] = { p, rel, rp, x, y }
    end
    local ow, oh = f:GetWidth(), f:GetHeight()
    moved[f] = { pts = pts, w = ow, h = oh }
  end
  f:ClearAllPoints()
  local a = { ... }
  for i = 1, #a do f:SetPoint(unpack(a[i])) end
  if w then f:SetWidth(w) end
  if h then f:SetHeight(h) end
  return true
end

-- Moves a game part's top edge down by delta (up if less than 0), its foot
-- where it is: each top anchor lower, a middle one half as much (and the
-- height less), a foot anchor left alone. Nothing if the game won't say
-- where it is.
local function lowerTop(f, delta)
  local n = f and f.GetNumPoints and f:GetNumPoints() or 0
  if n == 0 then return end
  local pts, foot = {}, false
  for i = 1, n do
    local p, rel, rp, x, y = f:GetPoint(i)
    x, y = num(x), num(y)
    if not p or not x or not y then return end
    if p:find("TOP") then
      y = y - delta
    elseif p:find("BOTTOM") then
      foot = true
    else
      y = y - delta / 2
    end
    pts[#pts + 1] = { p, rel, rp, x, y }
  end
  local h = num(f:GetHeight())
  place(f, nil, (not foot and h) and h - delta or nil, unpack(pts))
end

-- The top of the quest log's first row (a header, a campaign's, a quest's,
-- the story header): whichever is highest, all scrolled together.
local function firstRowTop(qs)
  local top
  local function see(f)
    if type(f) == "table" and f.IsShown and f:IsShown() and f.GetTop then
      local t = num(f:GetTop())
      if t and (not top or t > top) then top = t end
    end
  end
  for _, key in ipairs({ "headerFramePool", "campaignHeaderFramePool", "campaignHeaderMinimalFramePool", "titleFramePool" }) do
    local pool = get(qs, key)
    if pool and pool.EnumerateActive then
      pcall(function() for f in pool:EnumerateActive() do see(f) end end)
    end
  end
  see(get(get(qs, "Contents"), "StoryHeader"))
  return top
end

-- Moves a game part's left-hand anchors dx right of where the game had them
-- (out of combat), its others where they are; from the game's own place
-- each time, so laying it again doesn't move it further.
local function nudgeRight(f, dx)
  if not f or not f.GetNumPoints or InCombatLockdown() then return end
  local orig = moved[f] and moved[f].pts
  if not orig then
    orig = {}
    for i = 1, f:GetNumPoints() do
      local p, rel, rp, x, y = f:GetPoint(i)
      if not p then break end
      orig[i] = { p, rel, rp, x, y }
    end
  end
  local pts = {}
  for i, o in ipairs(orig) do
    local x, y = num(o[4] or 0), num(o[5] or 0)
    if not x or not y then return end
    pts[i] = { o[1], o[2], o[3], o[1]:find("LEFT") and x + dx or x, y }
  end
  if #pts > 0 then place(f, nil, nil, unpack(pts)) end
end

-- Sets a game part's height only (out of combat), remembering the game's.
local function setHeight(f, h)
  if not f or not f.SetHeight or InCombatLockdown() then return end
  if heights[f] == nil and not moved[f] then heights[f] = f:GetHeight() end
  f:SetHeight(h)
end

-- A font string in one of the board's fonts at the scale (kk, else the header's), in an ink (a hex, or a role's).
local function style(fs, font, hex, role, kk)
  if type(fs) ~= "table" or not fs.SetFont then return end
  local e = styled[fs]
  if not e then
    local f1, f2, f3 = fs:GetFont()
    local r, g, b, a = fs:GetTextColor()
    e = { font = { f1, f2, f3 }, color = { r, g, b, a } }
    styled[fs] = e
  end
  e.role = role
  local spec = FONT[font]
  if spec then
    local fo = MOTA:FontAt(spec[1], spec[2] * (kk or WS.k or 1))
    local p, s = fo:GetFont()
    if p then fs:SetFont(p, s, "") end
  end
  local ink = hex or (role and INKS[file()] and INKS[file()][role])
  if ink then fs:SetTextColor(MOTA:RGB(ink)) end
end

-- The game recolours some words on hover: ink them again after it.
local function keepInk(b, fs)
  if not b or not b.HookScript or dressed[fs] then return end
  dressed[fs] = true
  local function again()
    local e = styled[fs]
    if not e or not WS.on then return end
    local ink = e.role and INKS[file()] and INKS[file()][e.role]
    if ink then fs:SetTextColor(MOTA:RGB(ink)) end
  end
  b:HookScript("OnEnter", again)
  b:HookScript("OnLeave", again)
end

local function putBack()
  for r, a in pairs(faded) do
    if r.SetAlpha then r:SetAlpha(a) end
    faded[r] = nil
  end
  if not InCombatLockdown() then
    for f, m in pairs(moved) do
      f:ClearAllPoints()
      for _, p in ipairs(m.pts) do f:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
      if type(m.w) == "number" and m.w > 0 then f:SetWidth(m.w) end
      if type(m.h) == "number" and m.h > 0 then f:SetHeight(m.h) end
      moved[f] = nil
    end
    for f, h in pairs(heights) do
      if type(h) == "number" and h > 0 then f:SetHeight(h) end
      heights[f] = nil
    end
    for f, i in pairs(insets) do
      f:SetHitRectInsets(i[1] or 0, i[2] or 0, i[3] or 0, i[4] or 0)
      insets[f] = nil
    end
    for f, i in pairs(textInsets) do
      f:SetTextInsets(i[1] or 0, i[2] or 0, i[3] or 0, i[4] or 0)
      textInsets[f] = nil
    end
    WS.navMoved = nil
  end
  for fs, e in pairs(styled) do
    if e.font[1] then fs:SetFont(e.font[1], e.font[2], e.font[3] or "") end
    if type(e.color[1]) == "number" then fs:SetTextColor(e.color[1], e.color[2], e.color[3], e.color[4] or 1) end
    styled[fs] = nil
  end
end

---------------------------------------------------------------------------
-- Pictures: one whole, or a nine-slice laid over a box
---------------------------------------------------------------------------

-- One picture on a texture; flipX/flipY mirror it.
local function look(t, name, flipX, flipY)
  local p = piece(name)
  if not p then t:Hide() return nil end
  t:SetTexture(path(p.tex), "CLAMP", "CLAMP", "TRILINEAR")
  local l, r, tp, b = p.l, p.r, p.t, p.b
  if flipX then l, r = r, l end
  if flipY then tp, b = b, tp end
  t:SetTexCoord(l, r, tp, b)
  t:Show()
  return p
end

-- Nine textures on owner, ready to lay a stretched piece over a box.
local function newSlice(owner, layer, sub)
  local s = { parts = {} }
  for i = 1, 9 do
    s.parts[i] = owner:CreateTexture(nil, layer, nil, sub)
    dressed[s.parts[i]] = s
  end
  return s
end

-- Lays the stretched piece name over anchor's box, its edges kept whole at k
-- game units per canvas unit, its overflow (shadow, hairline) reaching past
-- the box as on the board. right, rightX: the box's right edge is instead
-- right's left edge plus rightX (a crumb reaching into the next one's notch).
local function laySlice(s, name, anchor, k, right, rightX)
  local p = piece(name)
  local sl, bx = WM.slice[name], WM.box and WM.box[name]
  if not p or not sl or not bx then
    for _, t in ipairs(s.parts) do t:Hide() end
    return
  end
  local ox, oy = math.max(0, (p.w - bx.w) / 2), math.max(0, (p.h - bx.h) / 2)
  local L, T, R, Bt = sl.l + ox, sl.t + oy, sl.r + ox, sl.b + oy
  local du, dv = (p.r - p.l) / p.w, (p.b - p.t) / p.h
  local us = { { 0, L }, { L, p.w - R }, { p.w - R, p.w } }
  local vs = { { 0, T }, { T, p.h - Bt }, { p.h - Bt, p.h } }
  local xs = { { "LEFT", -ox, "LEFT", L - ox }, { "LEFT", L - ox, "RIGHT", -(R - ox) }, { "RIGHT", -(R - ox), "RIGHT", ox } }
  local ys = { { "TOP", oy, "TOP", -(T - oy) }, { "TOP", -(T - oy), "BOTTOM", Bt - oy }, { "BOTTOM", Bt - oy, "BOTTOM", -oy } }
  local tex = path(p.tex)
  local i = 0
  for row = 1, 3 do
    for col = 1, 3 do
      i = i + 1
      local t = s.parts[i]
      local u, v, x, y = us[col], vs[row], xs[col], ys[row]
      if u[2] - u[1] <= 0.01 or v[2] - v[1] <= 0.01 then
        t:Hide()
      else
        t:SetTexture(tex, "CLAMP", "CLAMP", "TRILINEAR")
        t:SetTexCoord(p.l + du * u[1], p.l + du * u[2], p.t + dv * v[1], p.t + dv * v[2])
        t:ClearAllPoints()
        local r1, h1, dx1 = anchor, x[1], x[2] * k
        local r2, h2, dx2 = anchor, x[3], x[4] * k
        if right then
          if h1 == "RIGHT" then r1, h1, dx1 = right, "LEFT", dx1 + rightX end
          if h2 == "RIGHT" then r2, h2, dx2 = right, "LEFT", dx2 + rightX end
        end
        t:SetPoint("TOPLEFT", r1, y[1] .. h1, dx1, y[2] * k)
        t:SetPoint("BOTTOMRIGHT", r2, y[3] .. h2, dx2, y[4] * k)
        t:Show()
      end
    end
  end
end

local function hideSlice(s)
  if s then for _, t in ipairs(s.parts) do t:Hide() end end
end

---------------------------------------------------------------------------
-- Dressing the game's own buttons and boxes
---------------------------------------------------------------------------

-- Lays a whole piece's picture on t over owner as the board lays it over its
-- box: the box fills the owner and the picture's shadow and hairline reach
-- past it. (Filling the owner with the whole picture shrank the knob inside
-- by its shadow: the pin came out a third too small, the gear short of the
-- count; Max, 8 Nov.) Without the board's box, the picture fills the owner.
local function fitTo(t, name, owner, flipX, flipY)
  local p, at = piece(name), WM.at and WM.at[name]
  local w, h = owner.GetWidth and owner:GetWidth(), owner.GetHeight and owner:GetHeight()
  t:ClearAllPoints()
  if not p or not at or type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
    t:SetAllPoints(owner)
    return
  end
  local sx, sy = w / at.w, h / at.h
  local l, r = at.x - p.x, (p.x + p.w) - (at.x + at.w)
  local tp, bt = at.y - p.y, (p.y + p.h) - (at.y + at.h)
  if flipX then l, r = r, l end
  if flipY then tp, bt = bt, tp end
  t:SetPoint("TOPLEFT", owner, "TOPLEFT", -l * sx, tp * sy)
  t:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", r * sx, -bt * sy)
end

-- A button wears one whole picture under its own art, with a soft glow of
-- the same picture on hover (its own highlight is faded). The picture's box
-- fills the button (which is sized to the board where the layout moves it).
local function dressButton(b, name, flipX, flipY, keep)
  if not b or not b.CreateTexture or not free(b) then return false end
  local d = dressed[b]
  if not d then
    d = { kind = "button" }
    d.t = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    d.hl = b:CreateTexture(nil, "HIGHLIGHT")
    d.hl:SetBlendMode("ADD")
    d.hl:SetAlpha(0.25)
    dressed[b], dressed[d.t], dressed[d.hl] = d, d, d
  end
  look(d.t, name, flipX, flipY)
  look(d.hl, name, flipX, flipY)
  fitTo(d.t, name, b, flipX, flipY)
  fitTo(d.hl, name, b, flipX, flipY)
  fadeButton(b, keep)
  return true
end

-- A box (search, count, bar, header, crumb, plate) wears a nine-slice under its own art.
local function dressBox(f, name, keep, right, rightX)
  if not f or not f.CreateTexture or not free(f) then return false end
  local d = dressed[f]
  if not d then
    d = { kind = "box", s = newSlice(f, "BACKGROUND", -8) }
    dressed[f] = d
  end
  laySlice(d.s, name, f, WS.k or 1, right, rightX)
  if f.GetNormalTexture then fadeButton(f, keep) else fadeRegions(f, keep) end
  return true
end

local function undressAll()
  for f, d in pairs(dressed) do
    if type(d) == "table" and dressed[f] == d then
      if d.t then d.t:Hide() end
      if d.hl then d.hl:Hide() end
      if d.s then hideSlice(d.s) end
      if d.own then d.own:Hide() end
    end
  end
end

---------------------------------------------------------------------------
-- Our own frames: behind (leather) and in front (rim, title, seal, edges)
---------------------------------------------------------------------------

local function build()
  local bx = box()
  back = CreateFrame("Frame", nil, map)
  back:SetAllPoints(bx)
  back:EnableMouse(false)
  back.leather = back:CreateTexture(nil, "BACKGROUND", nil, -7)
  back.leather:SetAllPoints(back)
  back.grain = back:CreateTexture(nil, "BACKGROUND", nil, -6)
  back.grain:SetAllPoints(back)
  back.log = newSlice(back, "BACKGROUND", -5)
  back.logBox = CreateFrame("Frame", nil, back) -- the log's panel: beside the map, as tall as it
  back.divider = newSlice(back, "BORDER", 0)
  back.divBox = CreateFrame("Frame", nil, back) -- between the map and the log

  front = CreateFrame("Frame", nil, map)
  front:SetAllPoints(bx)
  front:EnableMouse(false)
  front.rim = newSlice(front, "OVERLAY", 0)
  front.mapRim = newSlice(front, "ARTWORK", 0)
  front.sep = newSlice(front, "ARTWORK", 1)
  front.sepBox = CreateFrame("Frame", nil, front) -- the rule along the title strip's foot
  front.title = front:CreateTexture(nil, "OVERLAY", nil, 1)
  front.seal = front:CreateTexture(nil, "OVERLAY", nil, 3)
  front.cornerL = front:CreateTexture(nil, "OVERLAY", nil, 2)
  front.cornerR = front:CreateTexture(nil, "OVERLAY", nil, 2)
  back:SetScript("OnSizeChanged", function() WS:Lay() end)
  WS.back, WS.front = back, front
end

-- Levels: the leather on the map frame's own level (under the map and the
-- log), the front just over it: the game's own buttons (children of the
-- border frame) stay over our rim, as the board's knobs sit over its rule.
local function levels()
  local base = map:GetFrameLevel() or 0
  back:SetFrameLevel(base)
  front:SetFrameLevel(base + 1)
end

-- Lays out our own frames' pictures.
function WS:Lay()
  if not back or not self.on then return end
  local k = scale()
  self.k = k
  local f = file()

  -- leather, with the shared grain tiled over it (as the window)
  look(back.leather, "leather")
  local w, h = back:GetWidth() or 0, back:GetHeight() or 0
  back.grain:SetTexture(path("grain"), "REPEAT", "REPEAT", "TRILINEAR")
  local tile = (M.grain and M.grain.tile or 400) * k
  back.grain:SetTexCoord(0, math.max(1, w / tile), 0, math.max(1, h / tile))
  back.grain:Show()

  laySlice(front.rim, "rim", front, k)

  -- the title strip: the title centred in it, the rule along its foot
  local tp = look(front.title, "title")
  if tp then
    front.title:SetSize(tp.w * k, tp.h * k)
    front.title:ClearAllPoints()
    front.title:SetPoint("CENTER", front, "TOP", 0, -(B.titleMid + B.titleCaps) * k)
  end
  local sb = front.sepBox
  sb:ClearAllPoints()
  sb:SetPoint("TOPLEFT", front, "TOPLEFT", B.inset * k, -B.titleH * k)
  sb:SetPoint("TOPRIGHT", front, "TOPRIGHT", -B.inset * k, -B.titleH * k)
  sb:SetHeight(B.sepH * k)
  laySlice(front.sep, "sep", sb, k)

  -- the seal breaking out of the top left: the skin's own emblem, its own
  -- picture for the map with a tight shadow (the window's soft one showed as a
  -- grey haze over the bright game world; Max, 8 Nov)
  local sp, ks, sx, sy = sealAt(k)
  if sp and look(front.seal, "seal") then
    front.seal:SetSize(sp.w * ks, sp.h * ks)
    front.seal:ClearAllPoints()
    front.seal:SetPoint("TOPLEFT", front, "TOPLEFT", sx, sy)
  else
    front.seal:Hide()
  end

  -- the Crown's filigree on the two bottom corners (the window's corner, mirrored)
  local corner = M.pieces["gold:corner"]
  if f == "crown" and corner then
    for side, t in pairs({ L = front.cornerL, R = front.cornerR }) do
      t:SetTexture(path(corner.tex), "CLAMP", "CLAMP", "TRILINEAR")
      if side == "L" then
        t:SetTexCoord(corner.r, corner.l, corner.b, corner.t)
      else
        t:SetTexCoord(corner.l, corner.r, corner.b, corner.t)
      end
      t:SetSize(52 * k, 52 * k)
      t:ClearAllPoints()
      local pt = side == "L" and "BOTTOMLEFT" or "BOTTOMRIGHT"
      t:SetPoint(pt, front, pt, side == "L" and -1 or 1, -1)
      t:Show()
    end
  else
    front.cornerL:Hide()
    front.cornerR:Hide()
  end

  local sc = get(map, "ScrollContainer")
  if sc then laySlice(front.mapRim, "mapRim", sc, k) else hideSlice(front.mapRim) end

  -- the quest log's panel and the divider, while the log shows. The panel runs
  -- from 2 above the map's top to 2 below its foot, as on the board: the
  -- search row sits on the leather above it (Max, 8 Nov: laid over the game's
  -- quest log frame, it reached up behind the row and over the rule)
  local qm = QuestMapFrame
  if qm and qm:IsShown() and sc then
    local lb = back.logBox
    local ql, sr = num(qm.GetLeft and qm:GetLeft()), num(sc.GetRight and sc:GetRight())
    local gx = (ql and sr) and ql - sr or 10 * k
    lb:ClearAllPoints()
    lb:SetPoint("TOPRIGHT", back, "TOPRIGHT", -B.logRight * k, -(B.mapTop - 2) * k)
    lb:SetPoint("BOTTOMLEFT", sc, "BOTTOMRIGHT", gx, -2 * k)
    laySlice(back.log, "log", lb, k)
    local db = back.divBox
    db:ClearAllPoints()
    db:SetPoint("TOPLEFT", sc, "TOPRIGHT", 0, 2 * k)
    db:SetPoint("BOTTOMLEFT", sc, "BOTTOMRIGHT", 0, -2 * k)
    db:SetWidth(6 * k)
    laySlice(back.divider, "divider", db, k)
  else
    hideSlice(back.log)
    hideSlice(back.divider)
  end
end

---------------------------------------------------------------------------
-- The header, on the board's layout (out of combat)
---------------------------------------------------------------------------

local function sidePanelToggle()
  local tg = get(map, "SidePanelToggle")
  if tg then return tg end
  for _, f in ipairs(get(map, "overlayFrames") or {}) do
    if get(f, "OpenButton") and get(f, "CloseButton") then return f end
  end
end

local function tracking()
  local tb = get(map, "WorldMapTrackingOptionsButton")
  if tb then return tb end
  for _, f in ipairs(get(map, "overlayFrames") or {}) do
    if get(f, "ResetButton") then return f end
  end
end

-- The game's coordinates panel ("Player 62.2, 72.9"): one of the map's overlay frames.
local function coords()
  for _, f in ipairs(get(map, "overlayFrames") or {}) do
    if get(f, "PlayerCoords") then return f end
  end
end

function WS:LayHeader()
  if not map or not self.on then return end
  if InCombatLockdown() then pending = true return end
  local k = scale()
  self.k = k
  local bx, sc = box(), get(map, "ScrollContainer")
  local bf = get(map, "BorderFrame")

  -- enlarge and close, flush in the rim's top-right corner
  local close = get(bf, "CloseButton")
  if close then
    place(close, B.knobW * k, B.knobH * k, { "TOPRIGHT", bx, "TOPRIGHT", -B.inset * k, -B.inset * k })
  end
  local mm = get(bf, "MaximizeMinimizeFrame")
  if mm and close then
    place(mm, B.knobW * k, B.knobH * k, { "TOPRIGHT", close, "TOPLEFT", -B.knobGap * k, 0 })
    for _, key in ipairs({ "MaximizeButton", "MinimizeButton" }) do
      local b = get(mm, key)
      if b then place(b, B.knobW * k, B.knobH * k, { "CENTER", mm, "CENTER", 0, 0 }) end
    end
  end

  -- the filter at the map's top right, as tall as the location bar and level
  -- with it (Max, 8 Nov), the board's shape (38 by 32); its reset cross on its corner
  local nav = get(map, "NavBar")
  local tb = tracking()
  local th = B.navH * k
  if tb and sc then
    local tw = th * B.trackW / B.trackH
    place(tb, tw, th, { "TOPRIGHT", sc, "TOPRIGHT", -B.trackToMapRight * k, (B.mapTop - B.navTop) * k })
    local rb = get(tb, "ResetButton")
    if rb then
      local rs = B.resetS * th / B.trackH
      place(rb, rs, rs, { "TOPLEFT", tb, "TOPLEFT", B.resetX * th / B.trackH, -B.resetY * th / B.trackH })
    end
  end

  -- the location bar, the board's 36 deep: the leather shows above it and below
  -- (its crumbs are set to the board's 32 in DressNav). From the board's gap
  -- past the seal, to 14 short of the filter (Max, 8 Nov: it touched both).
  if nav and sc then
    local _, _, _, _, sealRight = sealAt(k)
    local sp = piece("seal")
    local left = (sealRight and sp) and sealRight + (B.navLeft - sp.x - sp.w) * k or B.navLeft * k
    local right = (tb and moved[tb]) and { "TOPRIGHT", tb, "TOPLEFT", -B.navToTrack * k, 0 }
      or { "TOPRIGHT", sc, "TOPRIGHT", -B.navToMapRight * k, (B.mapTop - B.navTop) * k }
    place(nav, nil, B.navH * k, { "TOPLEFT", bx, "TOPLEFT", left, -B.navTop * k }, right)
    self.navMoved = true
  end

  -- the quest log's row: the gear at the right, the count beside it, the search box beside that
  local qs = QuestScrollFrame
  local gear = get(qs, "SettingsDropdown")
  if gear then place(gear, B.gearS * k, B.gearS * k, { "TOPRIGHT", bx, "TOPRIGHT", -B.gearRight * k, -B.rowTop * k }) end
  if QuestLogCount then
    if gear then
      place(QuestLogCount, B.countW * k, B.rowH * k, { "TOPRIGHT", gear, "TOPLEFT", -B.gap * k, 0 })
    else
      place(QuestLogCount, B.countW * k, B.rowH * k, { "TOPRIGHT", bx, "TOPRIGHT", -B.gearRight * k, -B.rowTop * k })
    end
  end
  local search = get(qs, "SearchBox")
  if search then
    local right = QuestLogCount or gear
    local w = B.searchW * k
    -- from the log's left edge to the count box, as on the board (226 there)
    local ql = num(QuestMapFrame and QuestMapFrame.GetLeft and QuestMapFrame:GetLeft())
    local rl = num(right and right.GetLeft and right:GetLeft())
    if ql and rl and rl - B.gap * k - ql > 40 then w = rl - B.gap * k - ql end
    if right then
      place(search, w, B.rowH * k, { "TOPRIGHT", right, "TOPLEFT", -B.gap * k, 0 })
    else
      place(search, w, B.rowH * k, { "TOPRIGHT", bx, "TOPRIGHT", -B.gearRight * k, -B.rowTop * k })
    end
  end

  -- the scroll bar beside the log's panel, as tall as it: clear of the gear
  -- (Max, 8 Nov: the game's reached up behind it)
  local bar = get(qs, "ScrollBar")
  if bar and sc then
    local sh = num(sc.GetHeight and sc:GetHeight())
    place(bar, B.scrollW * k, (sh and sh > 0) and sh + 4 * k or nil,
      { "TOPRIGHT", bx, "TOPRIGHT", -B.gearRight * k, -(B.mapTop - 2) * k })
  end

  -- the quest list inside its panel: its first row 6 below the panel's top,
  -- as the board's zone header (Max, 8 Nov: the game's list began above the
  -- panel). The list's own top, where it cuts its rows off, no higher than
  -- the panel's. Measured each time the game lays the list out, so it holds
  -- wherever the game puts the list.
  if qs and qs.IsShown and qs:IsShown() then
    local first, qt, ft = firstRowTop(qs), num(qs.GetTop and qs:GetTop()), num(bx.GetTop and bx:GetTop())
    if first and qt and ft then
      local scrolled = num(qs.GetVerticalScroll and qs:GetVerticalScroll()) or 0
      local panelTop = ft - (B.mapTop - 2) * k
      local off = qt - (first - scrolled) -- the first row below the list's top, scrolled back up
      local delta = qt - math.min(panelTop, panelTop - B.rowInset * k + off)
      if math.abs(delta) > 0.5 then lowerTop(qs, delta) end
    end
  end

  -- the map pin button: the board's size, 10 in from the map's top-left
  -- corner (Max, 8 Nov: it sat on the map's edge)
  local pin = get(map, "WorldMapTrackingPinButton")
  if pin and sc then
    place(pin, B.pinS * k, B.pinS * k, { "TOPLEFT", sc, "TOPLEFT", B.pinIn * k, -B.pinIn * k })
  end
end

---------------------------------------------------------------------------
-- The game's parts: pictures, fonts and inks
---------------------------------------------------------------------------

-- The border frame's own art: its regions, nine-slice, portrait, title and bg.
local function fadeBorder()
  local bf = get(map, "BorderFrame")
  if not bf then return end
  fadeRegions(bf)
  fadeRegions(get(bf, "NineSlice"))
  local bg = get(bf, "Bg")
  if bg then fade(bg) fadeRegions(bg) end
  fadeRegions(get(bf, "PortraitContainer"))
  if WorldMapFramePortrait then fade(WorldMapFramePortrait) end
  fade(get(map, "Bg"))
  fade(get(get(bf, "TitleContainer"), "TitleText") or get(bf, "TitleText"))
  fade(get(bf, "TopTileStreaks"))
end

local function dressKnobs()
  local bf = get(map, "BorderFrame")
  dressButton(get(bf, "CloseButton"), "knobClose")
  local mm = get(bf, "MaximizeMinimizeFrame")
  if mm then
    fadeRegions(mm)
    dressButton(get(mm, "MaximizeButton"), "knobEnlarge")
    dressButton(get(mm, "MinimizeButton"), "knobEnlarge", true, true) -- the enlarge knob turned about: shrink
  end
end

-- A crumb's words, and its dropdown arrow in the same ink.
local function crumbText(b)
  local fs = get(b, "text")
  if not fs and b.GetFontString then fs = b:GetFontString() end
  if type(fs) == "table" and fs.SetFont then return fs end
end

-- A crumb's dropdown arrow: the board's chevron in the crumb's ink, 7 past its
-- words and level with them (Max, 8 Nov: the game's arrow sat at the crumb's
-- foot once the crumbs were the board's height). Still the game's button, so
-- its clicks stay; it reaches 5 past the chevron each side for the mouse.
local function dressArrow(b, fs, role)
  local ma = get(b, "MenuArrowButton")
  if not ma or not ma.CreateTexture or not free(ma) then return end
  local k = WS.k or 1
  local d = dressed[ma]
  if not d then
    d = { kind = "button", t = ma:CreateTexture(nil, "OVERLAY") }
    dressed[ma], dressed[d.t] = d, d
    -- the game shows its own arrow art again on hover: fade it again after
    local function again() if WS.on then fadeButton(ma, { [d.t] = true }) end end
    if ma.HookScript then
      ma:HookScript("OnEnter", again)
      ma:HookScript("OnLeave", again)
    end
  end
  if fs and fs.GetStringWidth then
    local sw = num(fs:GetStringWidth()) or 0
    local fw = num(fs.GetWidth and fs:GetWidth()) or sw
    local j = fs.GetJustifyH and fs:GetJustifyH() or "LEFT"
    local x = (j == "CENTER" and (fw + sw) / 2) or (j == "RIGHT" and fw) or sw -- the words' right end
    place(ma, B.chevS * k, B.chevS * k, { "LEFT", fs, "LEFT", x + B.chevGap * k, 0 })
    if ma.SetHitRectInsets and ma.GetHitRectInsets then
      if not insets[ma] then insets[ma] = { ma:GetHitRectInsets() } end
      local m = -5 * k
      ma:SetHitRectInsets(m, m, m, m)
    end
  end
  look(d.t, "chev")
  fitTo(d.t, "chev", ma)
  local hex = INKS[file()] and INKS[file()][role]
  if hex then d.t:SetVertexColor(MOTA:RGB(hex)) end
  fadeButton(ma, { [d.t] = true })
end

local function untintArrows()
  for r, d in pairs(dressed) do
    if type(d) == "table" and d.tint then
      if r.SetDesaturated then r:SetDesaturated(false) end
      if r.SetVertexColor then r:SetVertexColor(1, 1, 1) end
      dressed[r] = nil
    end
  end
end

-- The location bar: the bar, the home crumb, the steps and the current place.
function WS:DressNav()
  local nav = get(map, "NavBar")
  if not nav or not self.on then return end
  dressBox(nav, "nav")
  for _, key in ipairs({ "InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderBottom",
                         "InsetBorderLeft", "InsetBorderRight" }) do
    fade(get(nav, key))
  end
  fadeRegions(get(nav, "overlay"))
  local list = get(nav, "navList") or {}
  local last = list[#list]
  local home = get(nav, "homeButton")
  -- each crumb reaches into the next one's notch, so no gap shows between them
  -- whatever room the game leaves (Max, 8 Nov: a gap after "Eastern Kingdoms")
  local shown = {}
  if home then shown[1] = home end
  for _, b in ipairs(list) do
    if b ~= home and (not b.IsShown or b:IsShown()) then shown[#shown + 1] = b end
  end
  local notch = 12 * (WS.k or 1)
  local function crumb(b, piece_, role, nextOne)
    setHeight(b, B.crumbH * (WS.k or 1)) -- the board's 32: 2 in from the bar's edges
    dressBox(b, piece_, nil, nextOne, nextOne and notch or nil)
    local fs = crumbText(b)
    style(fs, "crumb", nil, role)
    keepInk(b, fs)
    dressArrow(b, fs, role)
  end
  for i, b in ipairs(shown) do
    local role = (b == home) and "home" or (i == #shown and "cur" or "step")
    local pieceName = (b == home) and "crumbHome" or (i == #shown and "crumbCur" or "crumbStep")
    crumb(b, pieceName, role, shown[i + 1])
  end
end

local function dressTracking()
  local tb = tracking()
  if not tb then return end
  dressButton(tb, "track")
  fade(get(tb, "Icon")) -- the game sets its picture again on each click; faded, it stays hidden
  dressButton(get(tb, "ResetButton"), "reset")
end

-- The quest count: the game's words hidden, ours in the board's two fonts
-- ("QUESTS:" in Cinzel, the number in EB Garamond), kept up to date.
local function countText()
  local qc = QuestLogCount
  if not qc then return end
  local fs = get(qc, "Text") or get(qc, "text")
  if not fs and qc.GetRegions then
    for _, r in ipairs({ qc:GetRegions() }) do
      if r.IsObjectType and r:IsObjectType("FontString") then fs = r break end
    end
  end
  return fs
end

function WS:Count()
  local qc, fs = QuestLogCount, countText()
  local d = qc and dressed[qc]
  if not d or not d.own or not self.on then return end
  local text = fs and fs.GetText and fs:GetText() or ""
  if type(text) ~= "string" then text = "" end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") -- the game may colour its words
  local label, num = text:match("^(.-)%s*(%d+%s*/%s*%d+)%s*$")
  if not label then label, num = text, "" end
  -- the font first: the game refuses words on a font string without one
  -- (Max's game, 8 Nov: the words came first and the whole dress stopped here)
  d.own.label:SetFontObject(MOTA:FontAt(FONT.countLabel[1], FONT.countLabel[2] * (self.k or 1)))
  d.own.num:SetFontObject(MOTA:FontAt(FONT.countNum[1], FONT.countNum[2] * (self.k or 1)))
  local inks = INKS[file()]
  d.own.label:SetTextColor(MOTA:RGB(inks.step))
  d.own.num:SetTextColor(MOTA:RGB(inks.cur))
  d.own.label:SetText((label or ""):upper())
  d.own.num:SetText(num or "")
  d.own:Show()
end

local function dressCount()
  local qc = QuestLogCount
  if not qc or not dressBox(qc, "count") then return end
  local d = dressed[qc]
  local fs = countText()
  if fs then fade(fs) end
  if not d.own then
    local own = CreateFrame("Frame", nil, qc)
    own:SetAllPoints(qc)
    own:EnableMouse(false)
    own.num = own:CreateFontString(nil, "OVERLAY")
    own.num:SetFontObject(MOTA:FontAt(FONT.countNum[1], FONT.countNum[2] * (WS.k or 1)))
    own.num:SetPoint("RIGHT", own, "RIGHT", -10 * (WS.k or 1), 0)
    own.label = own:CreateFontString(nil, "OVERLAY")
    own.label:SetFontObject(MOTA:FontAt(FONT.countLabel[1], FONT.countLabel[2] * (WS.k or 1)))
    own.label:SetPoint("RIGHT", own.num, "LEFT", -6 * (WS.k or 1), 0)
    d.own = own
    WS.countFrame = own
    if fs and type(fs.SetText) == "function" then
      hooksecurefunc(fs, "SetText", function() WS:Count() end)
      if type(fs.SetFormattedText) == "function" then hooksecurefunc(fs, "SetFormattedText", function() WS:Count() end) end
    end
  end
  WS:Count()
end

-- The search box keeps its magnifier and its own words, in the board's font.
local function dressSearch()
  local qs = QuestScrollFrame
  local sb = get(qs, "SearchBox")
  if not sb then return end
  local keep = {}
  local icon = get(sb, "searchIcon") or get(sb, "SearchIcon") or (sb.GetName and sb:GetName() and _G[sb:GetName() .. "SearchIcon"])
  if icon then keep[icon] = true end
  dressBox(sb, "search", keep)
  local inks = INKS[file()]
  if sb.SetFont and sb.GetFont then style(sb, "search", inks.step) end
  local hint = get(sb, "Instructions")
  if hint then style(hint, "search", inks.step) end
  if icon and icon.SetVertexColor then -- the magnifier in the skin's metal, as the board's
    if not dressed[icon] then dressed[icon] = { tint = true } end
    if icon.SetDesaturated then icon:SetDesaturated(true) end
    icon:SetVertexColor(MOTA:RGB(file() == "silverhand" and "AEB8C6" or "C9A24A"))
  end
  -- the magnifier and the words further in from the box's left edge (Max, 8 Nov)
  local dx = B.searchIn * (WS.k or 1)
  nudgeRight(icon, dx)
  nudgeRight(hint, dx)
  if sb.SetTextInsets and sb.GetTextInsets and not InCombatLockdown() then
    if not textInsets[sb] then textInsets[sb] = { sb:GetTextInsets() } end
    local o = textInsets[sb]
    sb:SetTextInsets((num(o[1]) or 0) + dx, num(o[2]) or 0, num(o[3]) or 0, num(o[4]) or 0)
  end
end

-- The scroll bar: the track down its whole length, our thumb, no arrows (Max, 8 Nov).
local function dressScroll()
  local bar = get(QuestScrollFrame, "ScrollBar")
  if not bar then return end
  dressBox(bar, "scroll")
  local track = get(bar, "Track")
  if track then
    fadeRegions(track)
    local thumb = get(track, "Thumb") or (bar.GetThumb and bar:GetThumb())
    if type(thumb) == "table" then dressBox(thumb, "thumb") end
  end
  -- the arrows stay where the game has them (still clickable) but out of sight
  fade(get(bar, "Back"))
  fade(get(bar, "Forward"))
end

-- The zone headers (pooled rows: dressed again on each quest log update).
-- Their wide band art is faded; the small +/- stays the game's.
function WS:DressHeaders()
  local qs = QuestScrollFrame
  if not qs or not self.on then return end
  local pool = get(qs, "headerFramePool")
  if not pool or not pool.EnumerateActive then return end
  pcall(function()
    for btn in pool:EnumerateActive() do
      if free(btn) then
        local d = dressed[btn]
        if not d then
          d = { kind = "box", s = newSlice(btn, "BACKGROUND", -8) }
          dressed[btn] = d
        end
        laySlice(d.s, "zone", btn, WS.k or 1)
        for _, r in ipairs({ btn:GetRegions() }) do
          if r.IsObjectType and r:IsObjectType("Texture") and not dressed[r] then
            local w = r:GetWidth()
            if type(w) == "number" and w > 40 then fade(r) end
          end
        end
        local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
        if type(hl) == "table" then fade(hl) end
        local fs = get(btn, "ButtonText") or get(btn, "Text") or get(btn, "text")
        if fs then
          style(fs, "zone", nil, "cur", scaleH())
          keepInk(btn, fs)
        end
      end
    end
  end)
end

-- The map pin button: our gold diamond in place of the game's picture; the
-- game's "pin active" look still shows over it.
local function dressPin()
  local pin = get(map, "WorldMapTrackingPinButton")
  if not pin then return end
  local keep = {}
  local active = get(pin, "ActiveTexture")
  if active then keep[active] = true end
  dressButton(pin, "round", nil, nil, keep)
  fade(get(pin, "Icon"))
end

-- The position plate: the game's coordinates panel, in the board's plate and fonts.
local function dressPlate()
  local c = coords()
  if not c then return end
  for _, key in ipairs({ "PlayerCoords", "CursorCoords" }) do
    local p = get(c, key)
    if p then
      dressBox(p, "plate")
      local label = get(p, "Label")
      for _, r in ipairs({ p:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("FontString") then
          if r == label then
            style(r, "plateLabel", nil, "step")
          else
            style(r, "plateNum", nil, "cur")
          end
        end
      end
    end
  end
end

-- The quest log's own backgrounds and divider, faded (our panel shows instead).
local function dressQuestLogArt()
  local qs = QuestScrollFrame
  if not qs then return end
  for _, key in ipairs({ "Edge", "Background", "Center" }) do fade(get(qs, key)) end
  fadeRegions(get(qs, "BorderFrame"))
  if QuestMapFrame then
    fade(get(QuestMapFrame, "VerticalSeparator"))
    fade(get(QuestMapFrame, "Background"))
  end
end

local function dressToggle()
  local tg = sidePanelToggle()
  if not tg then return end
  dressButton(get(tg, "OpenButton"), "toggle")
  dressButton(get(tg, "CloseButton"), "toggle")
end

---------------------------------------------------------------------------
-- On, off, again
---------------------------------------------------------------------------

-- Dresses everything for the skin in force, or puts the game's look back.
function WS:Apply()
  if not map then return end
  local key = self:Key()
  if InCombatLockdown() and not free(map) then pending = true return end
  if not key then
    if InCombatLockdown() and next(moved) then pending = true return end
    self.on = nil
    if back then back:Hide() front:Hide() end
    undressAll()
    untintArrows()
    putBack()
    return
  end
  self.on = key
  if not back then build() end
  levels()
  back:Show()
  front:Show()
  self.k = scale()
  -- each part on its own: one that fails (a client with a part unlike ours)
  -- is reported once and the rest still dress (Max's game, 8 Nov: one error
  -- in the count left the gear, the thumb, the pin, the plate and the toggle bare)
  for _, step in ipairs({
    function() self:LayHeader() end, fadeBorder, dressKnobs, function() self:DressNav() end, dressTracking,
    dressSearch, dressCount, function() dressButton(get(QuestScrollFrame, "SettingsDropdown"), "gear") end,
    dressQuestLogArt, dressScroll, function() self:DressHeaders() end, dressPin, dressPlate, dressToggle,
    function() self:Lay() end,
  }) do
    local ok, err = pcall(step)
    if not ok then
      self.errors = (self.errors or 0) + 1
      if self.errors <= 3 then geterrorhandler()(err) end
    end
  end
  if not InCombatLockdown() then pending = false end
end

local function refresh()
  if map and map:IsShown() then WS:Apply() end
end

-- Hooked on to the world map once it exists (it may load after us).
function WS:Attach()
  if map or not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
  map = WorldMapFrame
  self.map = map
  map:HookScript("OnShow", function()
    refresh()
    -- the game lays the map out on its first frame shown: lay ours again after it
    if C_Timer and C_Timer.After then C_Timer.After(0, refresh) end
  end)
  if type(map.OnMapChanged) == "function" then hooksecurefunc(map, "OnMapChanged", function() WS:DressNav() end) end
  for _, fn in ipairs({ "Maximize", "Minimize" }) do
    -- a new size: everything again (the buttons' pictures fit their new sizes)
    if type(map[fn]) == "function" then hooksecurefunc(map, fn, refresh) end
  end
  if QuestMapFrame then
    QuestMapFrame:HookScript("OnShow", function() WS:LayHeader() WS:Lay() WS:DressHeaders() end)
    QuestMapFrame:HookScript("OnHide", function() WS:LayHeader() WS:Lay() end)
  end
  if type(NavBar_AddButton) == "function" then
    hooksecurefunc("NavBar_AddButton", function(bar) if bar == get(map, "NavBar") then WS:DressNav() end end)
  end
  if type(QuestLogQuests_Update) == "function" then
    -- the game lays its quest log out again on each update: put the row back where the board has it
    hooksecurefunc("QuestLogQuests_Update", function()
      if not WS.on then return end
      if not InCombatLockdown() then WS:LayHeader() end
      WS:DressHeaders()
      WS:Count()
    end)
  end
  refresh()
end

MOTA:On("PLAYER_LOGIN", function() WS:Attach() end)
MOTA:On("ADDON_LOADED", function(_, _, name)
  if name == "Blizzard_WorldMap" then WS:Attach() end
end)
MOTA:On("PLAYER_REGEN_ENABLED", function()
  if pending then refresh() end
end)
MOTA:Listen("SKIN_CHANGED", refresh)
MOTA:Listen("MAP_SKIN_CHANGED", function()
  if map then WS:Apply() end
end)
