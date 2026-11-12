-- Ministry of the Allied: the Chronicle book on the Throne Room (Max, 10 Nov 2026; ADDON_SPEC.md 10.3).
-- Below Recent decrees, on a dark plate, lies a closed leatherbound tome. Hovering lifts its cover a
-- little, light spilling from the page edge; a click flings the cover open and the pages up into a fan in
-- an explosive holy light (Max: grand, regal, almost aggressive, as if blessed by the heavens), with a holy
-- sound: rays turning behind the book, a shaft of light from above, a golden aura, one great swell that
-- engulfs it, a shockwave, motes flung out and twinkling stars. The pages hang a moment and fall slowly.
-- It comes to rest open, still lit; a click on the open book opens the Charter on the Statute Book tab. Leaving the Throne
-- Room (or going to the Chronicle) closes it again. It is the Statute Book (11 Nov): the open book opens the Charter.
--
-- The pictures are drawn in 3D by tools/textures/chronicle.py (chronicle.html): the cover and a turning
-- page at many angles, and the lights. Here one clock (OnUpdate) steps through them and fades the lights;
-- no FlipBook, no texture rotation (the rays "turn" by fading between three drawn turns). The timings and
-- places are Media.chronicle.timing, the same numbers as the previews Max saw.
--
--   MOTA.ChronicleBook:Build(plate, w, h)   the book on its plate (UI/ThroneRoom.lua); returns the book
--   book:Reset()     closed again, at once (the Throne Room calls it when its page goes)
--   book:Click()     what a click does: open, skip to open, or open the Charter
--   book.state       "closed", "opening" or "open"; book.lift: the hover lift, 0 to 1

local _, MOTA = ...
local Book = {}
Book.__index = Book
MOTA.ChronicleBook = Book

local M = MOTA.Media
local C = M.chronicle
local T = C and C.timing
local FOOT = 14       -- the closed book's foot sits this far above the plate's foot (and the open book's too)
local MOTES = 56      -- the most motes and stars in the air at once (the burst's, and a few rising after)
local TURNING = 10    -- the most covers and pages turning at once (one draw sublevel each)
local SOUND = "IG_ABILITY_PAGE_TURN"

-- The holy sound with the light (Max, 10 Nov): the one chosen with /mota booksound, or the first of
-- these the client plays (Forever may not have them all).
Book.holyNames = {
  "UI_COVENANT_CHOICE_CELEBRATION_ANIMATION_BASTION", "UI_COVENANT_SANCTUM_RENOWN_MAX_KYRIAN",
  "UI_LEGENDARY_LOOT_TOAST", "UI_70_ARTIFACT_FORGE_TRAIT_GOLD_TRAIT", "UI_EPICLOOT_TOAST", "LEVELUPSOUND",
}

-- The holy sounds this client has, in list order.
function Book:HolySounds()
  local list = {}
  for _, name in ipairs(self.holyNames) do
    if SOUNDKIT and SOUNDKIT[name] then list[#list + 1] = name end
  end
  return list
end

function Book:PlayHoly(name)
  if not SOUNDKIT then return end
  local settings = MOTA.db and MOTA.db.settings
  name = name or (settings and settings.bookSound)
  if name and SOUNDKIT[name] then
    PlaySound(SOUNDKIT[name])
    return
  end
  for _, n in ipairs(Book:HolySounds()) do
    if PlaySound(SOUNDKIT[n]) then return end
  end
end

local function ease(t)
  if t <= 0 then return 0 elseif t >= 1 then return 1 end
  return t * t * (3 - 2 * t)
end
local function ramp(t, a, b)
  if b <= a then return t >= a and 1 or 0 end
  return ease((t - a) / (b - a))
end

-- The two drawn angles either side of an angle, and how far between them (0..1). On a drawn angle, just it.
local function between(angle, angles)
  if angle <= angles[1] then return angles[1], angles[1], 0 end
  for i = 1, #angles - 1 do
    local a, b = angles[i], angles[i + 1]
    if angle < b then return a, b, (angle - a) / (b - a) end
  end
  return angles[#angles], angles[#angles], 0
end
local function coverName(a) return ("cover%03d"):format(a) end
local function pageName(a) return ("page%03d"):format(a) end

-- A part's piece in the skin worn (the leather, metal and emblem), or the shared one.
local function piece(part)
  local file = MOTA.skin and MOTA.skin.FILE or "ministry"
  local own = "chronicle_" .. file .. ":" .. part
  if M.pieces[own] then return own end
  if M.pieces["chronicle:" .. part] then return "chronicle:" .. part end
  return "chronicle_ministry:" .. part
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

-- Media.chronicle as tools/textures/chronicle.py writes it now. A Media.lua built before the explosive
-- light (10 Nov) lacks its lights and timings and the book would error mid-build, leaving the Throne Room
-- half built; then there is no book (the plate shows its title only) until build.py is run again.
function Book:Ready()
  return (C and T and C.rays and C.page and T.front and T.place and T.place.ring and T.place.halo.rest
    and T.pages and T.pages.fan and T.hover and T.hover.bloomClosed and T.hover.openRays and T.engulf and T.flare
    and T.ring and T.motes and T.motes.burstFor and T.motes.fling and M.pieces["chronicle:rays00"]
    and M.pieces["chronicle:ring"]) and true or false
end

function Book:Build(plate, w, h)
  if not self:Ready() then return nil end
  local b = setmetatable({ plate = plate, w = w, h = h, state = "closed", t = 0, spin = 0, lift = 0,
    hover = false, owed = 0 }, Book)
  -- the scene: every picture is placed from its top-left; it slides as the book opens
  local scene = CreateFrame("Frame", nil, plate)
  scene:SetSize(C.scene.w, C.scene.h)
  scene:SetFrameLevel(plate:GetFrameLevel() + 2)
  b.scene = scene
  local function tex(layer, sub, add)
    local t = scene:CreateTexture(nil, layer, nil, sub)
    if add then t:SetBlendMode("ADD") end
    t:Hide()
    return t
  end
  -- behind the book: the halo, the turning rays, the shaft from above
  b.halo = tex("BACKGROUND", 0, true)
  b.raysA = tex("BACKGROUND", 1, true)
  b.raysB = tex("BACKGROUND", 2, true)
  b.shaft = tex("BACKGROUND", 3, true)
  -- under it: its shadow and its aura
  b.shadow = tex("BORDER", 0)
  b.bloomClosed = tex("BORDER", 1, true)
  b.bloom = tex("BORDER", 2, true)
  -- the book
  b.base = tex("ARTWORK", -8)
  b.leak = tex("ARTWORK", -7, true)
  b.open = tex("ARTWORK", -6)
  b.pages = tex("ARTWORK", -5)
  b.ribbons = tex("ARTWORK", -4)
  b.turn = {}
  for i = 1, TURNING do b.turn[i] = tex("ARTWORK", -4 + i) end
  -- over it: the light on the pages, the bright core, the shaft and the swell that bathe it, the
  -- shockwave, the burst's bright heart, the motes
  b.glow = tex("OVERLAY", 0, true)
  b.beam = tex("OVERLAY", 1, true)
  b.shaftFront = tex("OVERLAY", 2, true)
  b.haloFront = tex("OVERLAY", 3, true)
  b.ring = tex("OVERLAY", 4, true)
  b.flare = tex("OVERLAY", 5, true)
  b.motes = {}
  for i = 1, MOTES do b.motes[i] = { tex = tex("OVERLAY", 6, true) } end
  -- the live line on the open book's left page: how much the Chronicle holds
  b.live = scene:CreateFontString(nil, "OVERLAY")
  b.live:SetFontObject(MOTA:FontAt("garamondItalic", 7))
  b.live:SetTextColor(MOTA:RGB("5E3C1E"))
  b.live:SetJustifyH("CENTER")
  if b.live.SetWordWrap then b.live:SetWordWrap(false) end
  local ll = C.liveLine
  b.live:SetWidth(ll.w + 28)
  b.live:SetPoint("TOP", scene, "TOPLEFT", ll.x + ll.w / 2, -(ll.y - 0.5))
  b.live:Hide()
  -- (the count at the plate's top right was removed on 11 Nov: the plate says Statute Book and no count)

  -- what the mouse meets: the book as it lies now
  local hit = CreateFrame("Button", nil, plate)
  hit:SetFrameLevel(plate:GetFrameLevel() + 6)
  hit:EnableMouse(true)
  hit:RegisterForClicks("LeftButtonUp")
  hit:SetScript("OnEnter", function(self)
    b.hover = true
    b:Run()
    b:Tip(self)
  end)
  hit:SetScript("OnLeave", function()
    b.hover = false
    b:Run()
    if GameTooltip then GameTooltip:Hide() end
  end)
  hit:SetScript("OnClick", function() b:Click() end)
  -- in the game a frame hides with its page or the window: the book is closed when it's next seen
  hit:SetScript("OnHide", function() b:Reset() end)
  b.hit = hit

  -- a new skin: the leather, metal and emblem follow it
  MOTA.Kit:Track(function()
    b:Draw()
  end)
  -- new entries: the count follows (many records can arrive at once: one redraw for the lot)
  for _, event in ipairs({ "RECORD_ADDED", "GUILD_READY", "CAUGHT_UP" }) do
    MOTA:Listen(event, function()
      if b.pending then return end
      b.pending = true
      C_Timer.After(0.3, function()
        b.pending = false
        b:Refresh()
      end)
    end)
  end
  b:Reset()
  return b
end

---------------------------------------------------------------------------
-- Where things go
---------------------------------------------------------------------------

-- The scene's top-left on the plate: the closed book centred with its foot FOOT above the plate's foot,
-- the open book centred with its foot at the same height; slide (0..1) moves between them.
function Book:Origin(slide)
  local cb, ob = C.closed, C.open
  local foot, cx = self.h - FOOT, self.w / 2
  local s = ease(slide)
  local x0, y0 = cx - (cb.x + cb.w / 2), foot - (cb.y + cb.h)
  local x1, y1 = cx - (ob.x + ob.w / 2), foot - (ob.y + ob.h)
  return x0 + (x1 - x0) * s, y0 + (y1 - y0) * s
end

-- The hit box: the closed book where it lies, or the open book once it opens.
function Book:Aim()
  local box, slide = C.closed, 0
  if self.state ~= "closed" then box, slide = C.open, 1 end
  local ox, oy = self:Origin(slide)
  self.hit:ClearAllPoints()
  self.hit:SetPoint("TOPLEFT", self.plate, "TOPLEFT", ox + box.x, -(oy + box.y))
  self.hit:SetSize(box.w, box.h)
end

-- A drawn piece at its own place in the scene.
local function show(tex, scene, name, alpha)
  if not alpha or alpha <= 0.003 then
    tex:Hide()
    return
  end
  if tex.name ~= name then
    local p = M.pieces[name]
    tex:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
    tex:SetTexCoord(p.l, p.r, p.t, p.b)
    tex:SetSize(p.w, p.h)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", scene, "TOPLEFT", p.x, -p.y)
    tex.name = name
  end
  tex:SetAlpha(math.min(1, alpha))
  tex:Show()
end

-- A light (or the shadow, or a mote), sized and centred on a point of the scene.
local function sprite(tex, scene, name, cx, cy, w, h, alpha)
  if not alpha or alpha <= 0.003 then
    tex:Hide()
    return
  end
  if tex.name ~= name then
    local p = M.pieces["chronicle:" .. name]
    tex:SetTexture(M.dir .. M.textures[p.tex], "CLAMP", "CLAMP", "TRILINEAR")
    tex:SetTexCoord(p.l, p.r, p.t, p.b)
    tex.name = name
  end
  tex:SetSize(w, h)
  tex:ClearAllPoints()
  tex:SetPoint("CENTER", scene, "TOPLEFT", cx, -cy)
  tex:SetAlpha(math.min(1, alpha))
  tex:Show()
end

-- The book's box now, going from the closed book's to the open book's as it slides (Draw sets it): the
-- lights and the motes are centred on it.
local here = { x = 0, y = 0, w = 0, h = 0 }

-- A light at its place (Media.chronicle.timing.place): its middle on the book's middle across, and that
-- share of the book's height down; grown by grow.
local function light(tex, scene, name, place, alpha, grow)
  local pl = T.place[place]
  grow = grow or 1
  sprite(tex, scene, name, here.x + here.w / 2, here.y + here.h * pl.y, pl.w * grow, pl.h * grow, alpha)
end

---------------------------------------------------------------------------
-- Drawing: what the book shows now (tools/textures/chronicle.py, state(), does the same)
---------------------------------------------------------------------------

local LIGHTS = { "halo", "raysA", "raysB", "shaft", "bloom", "glow", "beam", "shaftFront", "haloFront", "ring", "flare" }

-- Page i's angle (i from 0) t seconds after the click, or nil while it lies flat (not flung yet, or
-- landed): flung up fast, slowing as it rises, to its place in a fan; hanging there a moment, drifting on
-- a little; then falling slowly to the left (Max, 10 Nov). chronicle.py: page_angle.
local function pageAngle(i, t, P)
  local s = P.start + i * P.every
  if t <= s then return nil end
  local h = P.fan[1] + (P.fan[2] - P.fan[1]) * i / (P.n - 1)
  local u = (t - s) / P.rise
  if u < 1 then return h * (1 - (1 - u) ^ 3) end
  local up, f0 = s + P.rise, P.hold + i * P.fallEvery
  if t < f0 then return h + P.drift * (t - up) / (f0 - up) end
  local a = h + P.drift
  local v = (t - f0) / (P.fall[1] + P.fall[2] * (180 - a) / 180)
  if v < 1 then return a + (180 - a) * ease(v) end
  return nil
end

function Book:Draw()
  if not self.scene then return end
  local scene, cb, ob = self.scene, C.closed, C.open
  local hv, pk, st = T.hover, T.peak, T.settle
  local turning = {}   -- { upright, part, alpha }: the most upright is nearest the eye, so drawn last
  local slide, base, leak, opened, bloomClosed, live = 0, 1, 0, 0, 0, 0

  if self.state == "closed" then
    leak = hv.leak * self.lift
    bloomClosed = hv.bloomClosed * self.lift
    local a, z, f = between(C.rest * self.lift, C.cover)
    turning[1] = { 0, coverName(a), 1 }
    if f > 0 then turning[2] = { 1e-6, coverName(z), f } end   -- over the first (the sort below keeps it so)
    for _, name in ipairs(LIGHTS) do self[name]:Hide() end
  else
    local t = self.state == "open" and T.done or self.t
    local s0, s1, s2 = T.swap[1], T.swap[2], T.swap[3]
    local g0, g1, g2 = T.glow[1], T.glow[2], T.glow[3]
    local full, settle = ramp(t, g0, g1), ramp(t, g1, g2)
    -- the light on the pages has its own burst and settles sooner, so the pages show as they hang
    local ffull, fsettle = ramp(t, T.front[1], T.front[2]), ramp(t, T.front[2], T.front[3])
    local function lit(name, front)
      local a, s = full, settle
      if front then a, s = ffull, fsettle end
      return pk[name] * a * (1 - s) + st[name] * s
    end
    -- a light's size: grown over the burst, settling to its rest size with the light (inside the plate)
    local function size(name)
      local pl = T.place[name]
      local g = pl.grow and (pl.grow[1] + (pl.grow[2] - pl.grow[1]) * full) or 1
      return g * (1 - settle) + (pl.rest or 1) * settle
    end
    slide = ramp(t, T.slide[1], T.slide[2])
    local sl = ease(slide)
    for _, k in ipairs({ "x", "y", "w", "h" }) do here[k] = cb[k] + (ob[k] - cb[k]) * sl end

    -- behind: the halo, the rays (turning: two drawn turns either side of now, faded across), the shaft
    light(self.halo, scene, "halo", "halo", lit("halo"), size("halo"))
    local rays = lit("rays") + ((self.state == "open" and self.hover) and hv.openRays or 0)
    local steps, at = C.rays, self.spin / T.turn
    local k, f = math.floor(at) % #steps, at - math.floor(at)
    local grow = size("rays")
    light(self.raysA, scene, ("rays%02d"):format(steps[k + 1]), "rays", rays * (1 - f), grow)
    light(self.raysB, scene, ("rays%02d"):format(steps[(k + 1) % #steps + 1]), "rays", rays * f, grow)
    light(self.shaft, scene, "shaft", "shaft", lit("shaft") * ramp(t, 0.25, 0.9), size("shaft"))

    -- under: the closed book's aura flares as it opens and gives way to the open book's
    bloomClosed = (hv.bloomClosed + (pk.bloomClosed - hv.bloomClosed) * ramp(t, 0, 0.15)) * (1 - ramp(t, 0.45, 0.9))
    show(self.bloom, scene, "chronicle:bloom", lit("bloom") * ramp(t, 0.35, 0.9))

    base = 1 - ramp(t, s1, s2)
    leak = (hv.leak + (pk.leak - hv.leak) * ramp(t, 0, 0.18)) * (1 - ramp(t, 0.3, 0.7))
    opened = ramp(t, s0, s1)
    if t < s1 then   -- the cover, at the drawn angle nearest (two far apart would show double)
      local angle = C.rest + (180 - C.rest) * ease((t - T.cover[1]) / (T.cover[2] - T.cover[1]))
      local a, z, fr = between(angle, C.cover)
      turning[#turning + 1] = { math.sin(math.rad(angle)), coverName(fr >= 0.5 and z or a), 1 }
    end
    local P, pa = T.pages, C.page
    for i = 0, P.n - 1 do
      local angle = pageAngle(i, t, P)
      if angle then
        local part, alpha
        if angle < pa[1] then
          part, alpha = pageName(pa[1]), angle / pa[1]
        elseif angle > pa[#pa] then
          part, alpha = pageName(pa[#pa]), (180 - angle) / (180 - pa[#pa])
        else
          local a, z, fr = between(angle, pa)
          part, alpha = pageName(fr >= 0.5 and z or a), 1
        end
        turning[#turning + 1] = { math.sin(math.rad(angle)) + (i + 1) * 1e-4, part, alpha }   -- (never ties the cover)
      end
    end

    -- over: the light on the pages, the core rising from them, the shaft and the swell bathing the book,
    -- the shockwave flung out (fast at first, slowing, fading as it goes), the burst's bright heart
    show(self.glow, scene, piece("glowOpen"), lit("glowOpen", true) * ramp(t, 0.2, 0.45))
    light(self.beam, scene, "beam", "beam", lit("beam", true) * ramp(t, 0.15, 0.4), size("beam"))
    light(self.shaftFront, scene, "shaft", "shaft", lit("shaftFront", true) * ramp(t, 0.1, 0.4), size("shaft"))
    local e0, e1, e2 = T.engulf[1], T.engulf[2], T.engulf[3]
    light(self.haloFront, scene, "halo", "haloFront",
      pk.haloFront * ramp(t, e0, e1) * (1 - ramp(t, e1, e2)) + st.haloFront * ramp(t, e1, e2), size("haloFront"))
    local r0, r1 = T.ring[1], T.ring[2]
    if t > r0 and t < r1 then
      local u = (t - r0) / (r1 - r0)
      local rg = T.place.ring.grow
      light(self.ring, scene, "ring", "ring", (1 - u) ^ 1.5, rg[1] + (rg[2] - rg[1]) * (1 - (1 - u) ^ 2))
    else
      self.ring:Hide()
    end
    local f0, f1, f2 = T.flare[1], T.flare[2], T.flare[3]
    local fg = T.place.flare.grow
    light(self.flare, scene, "flare", "flare", ramp(t, f0, f1) * (1 - ramp(t, f1, f2)),
      fg[1] + (fg[2] - fg[1]) * ramp(t, f0, f2))
    live = ramp(t, T.done - 0.4, T.done)
  end

  local ox, oy = self:Origin(slide)
  scene:ClearAllPoints()
  scene:SetPoint("TOPLEFT", self.plate, "TOPLEFT", ox, -oy)
  local s = ease(slide)

  -- the shadow under the book's foot, widening as it opens
  local sw = cb.w + (ob.w - cb.w) * s
  local mid = cb.x + cb.w / 2 + (ob.x + ob.w / 2 - cb.x - cb.w / 2) * s
  local foot = cb.y + cb.h + (ob.y + ob.h - cb.y - cb.h) * s
  sprite(self.shadow, scene, "shadow", mid, foot - 7, sw * 1.04, 30, 1)
  show(self.bloomClosed, scene, "chronicle:bloomClosed", bloomClosed)

  show(self.base, scene, piece("base"), base)
  show(self.leak, scene, piece("leak"), leak)
  show(self.open, scene, piece("open"), opened)
  show(self.pages, scene, piece("pages"), opened)
  show(self.ribbons, scene, piece("ribbons"), opened)

  table.sort(turning, function(x, y) return x[1] < y[1] end)
  for i, tx in ipairs(self.turn) do
    local item = turning[i]
    if item then
      show(tx, scene, piece(item[2]), item[3])
    else
      tx:Hide()
    end
  end

  self:DrawMotes()
  if live > 0.003 then
    self.live:SetAlpha(live)
    self.live:Show()
  else
    self.live:Hide()
  end
end

---------------------------------------------------------------------------
-- Motes: golden specks and twinkling stars rising from the pages: a burst flung out as the light bursts
-- (m.burst of them over m.burstFor seconds from just after the pages start), then a few now and then
-- (chronicle.py: Motes)
---------------------------------------------------------------------------

function Book:StepMotes(dt)
  local m = T.motes
  local t = self.state == "open" and T.done + 1 or self.t
  local start = T.pages.start + 0.1
  if self.state ~= "closed" and t >= start then
    local burst = t < start + m.burstFor
    self.owed = self.owed + (burst and m.burst / m.burstFor or m.ambient) * dt
    while self.owed >= 1 do
      self.owed = self.owed - 1
      for _, mote in ipairs(self.motes) do
        if not mote.on then
          local r = math.random
          mote.on, mote.age = true, 0
          mote.x, mote.y = (r() - 0.5) * m.spread, -(r() * 30)
          mote.life = m.life[1] + r() * (m.life[2] - m.life[1])
          mote.rise = m.rise[1] + r() * (m.rise[2] - m.rise[1])
          mote.size = m.size[1] + r() * (m.size[2] - m.size[1])
          mote.sway, mote.phase = (r() - 0.5) * 16, r() * 6.28
          mote.star = r() < m.stars
          mote.fx, mote.fy = 0, 0
          if burst then   -- flung out in an upward fan, fast at first, then rising like the rest
            local far = m.fling[1] + r() * (m.fling[2] - m.fling[1])
            local ang = math.rad(200 + r() * 140)
            mote.fx, mote.fy = far * math.cos(ang), far * math.sin(ang)
          end
          break
        end
      end
    end
  end
  for _, mote in ipairs(self.motes) do
    if mote.on then
      mote.age = mote.age + dt
      if mote.age >= mote.life then mote.on = false end
    end
  end
end

function Book:DrawMotes()
  local cx, cy = here.x + here.w / 2, here.y + here.h * 0.45
  for _, mote in ipairs(self.motes) do
    if mote.on then
      local u = mote.age / mote.life
      local a = math.min(1, u / 0.15) * (1 - math.max(0, (u - 0.6) / 0.4))
      local size = mote.size
      if mote.star then   -- a star twinkles, gently, and is drawn larger (its points are thin)
        a = a * (0.6 + 0.4 * math.sin(mote.phase + mote.age * 7))
        size = size * 1.7
      end
      local flung = 1 - math.exp(-5 * mote.age)
      sprite(mote.tex, self.scene, mote.star and "star" or "mote",
        cx + mote.x + mote.fx * flung + mote.sway * math.sin(mote.phase + u * 4),
        cy + mote.y + mote.fy * flung - mote.rise * u, size, size, a)
    else
      mote.tex:Hide()
    end
  end
end

---------------------------------------------------------------------------
-- The clock, the click, the tooltip
---------------------------------------------------------------------------

-- One step of the clock. A long frame (a hitch) moves it on at most a tenth of a second.
function Book:Step(dt)
  dt = math.min(dt or 0, 0.1)
  if self.state == "closed" then
    local goal = self.hover and 1 or 0
    self.lift = self.lift + (goal - self.lift) * (1 - math.exp(-dt / T.lift))
    if math.abs(goal - self.lift) < 0.002 then
      self.lift = goal
      self.scene:SetScript("OnUpdate", nil)   -- still: the clock stops
    end
  else
    self.spin = self.spin + dt   -- the rays keep turning while the book is open
    if self.state == "opening" then
      self.t = self.t + dt
      if self.t >= T.done then
        self.state = "open"
        self:Aim()
        if self.hover then self:Tip(self.hit) end
      end
    end
  end
  self:StepMotes(dt)
  self:Draw()
end

-- Starts the clock (it stops itself once the closed book is still; the open book keeps its rays turning).
function Book:Run()
  local book = self
  self.scene:SetScript("OnUpdate", function(_, elapsed) book:Step(elapsed) end)
end

function Book:Click()
  if self.state == "closed" then
    self.state, self.t, self.spin, self.owed = "opening", 0, 0, 0
    if GameTooltip then GameTooltip:Hide() end
    if SOUNDKIT and SOUNDKIT[SOUND] then PlaySound(SOUNDKIT[SOUND]) end
    self:PlayHoly()
    self:Refresh()
    self:Aim()
    self:Run()
    self:Draw()
  elseif self.state == "opening" then
    self.state, self.t = "open", T.done   -- impatient: straight to the open book
    self:Aim()
    if self.hover then self:Tip(self.hit) end
    self:Draw()
  else
    local page = MOTA.ThronePage
    if page and page.OpenCharter then page:OpenCharter() end -- the Charter, on the Statute Book tab (Max, 11 Nov)
  end
end

function Book:Tip(owner)
  if not GameTooltip or self.state == "opening" then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(self.state == "open" and "Opens Statute Book · Charter" or "Statute Book · click to open the book",
    1, 0.95, 0.77)
  GameTooltip:Show()
end

-- How many entries the Chronicle holds, and since when: on the open book's left page.
function Book:Refresh()
  local Ch = MOTA.Chronicle
  local all = Ch and Ch.All and Ch:All("all") or {}
  local n, first = #all, all[#all]
  local text = "Nothing is written yet"
  if n > 0 and first and first.t then
    text = ("%d %s since %d %s"):format(n, n == 1 and "entry" or "entries", tonumber(date("%d", first.t)),
      date("%B", first.t))
  end
  self.live:SetText(text)
end

function Book:Reset()
  self.state, self.t, self.spin, self.lift, self.hover, self.owed = "closed", 0, 0, 0, false, 0
  for _, mote in ipairs(self.motes) do mote.on = false end
  self.scene:SetScript("OnUpdate", nil)
  self:Refresh()
  self:Aim()
  self:Draw()
end
