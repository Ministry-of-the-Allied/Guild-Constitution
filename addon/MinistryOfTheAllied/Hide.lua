-- Ministry of the Allied: Hide and Seek (Duncan, 2026-11-10).
-- The Crown or the Minister of Games opens a game in a play area (a circle in
-- the world). Players join; the organiser starts it with a seeker. Everyone
-- hides for the hiding time, then the seekers seek. Infection style: a player
-- who is found becomes a seeker at once.
--
-- Finding is by distance, and only the hider's own add-on knows where the
-- hider is: seekers send where they stand to the guild every couple of
-- seconds (HP messages, never kept), and each hider's add-on compares. A seeker
-- who stays within the find radius (6 yards) for the dwell (2 seconds) has
-- found them, and the hider's add-on writes it. Hiders never send their place.
-- Within 20 yards a hider's screen glows, as the treasure hunt's does.
--
-- Leaving the play area: 10 seconds outside it and you're out of the game.
-- Options: "Hide names" turns friendly names and nameplates off for players
-- while the game runs (and back on after, even after a crash: the old settings
-- are saved first); "No map" closes the world map while the game runs.
--
--   hide.open   the Crown or the Minister of Games
--               { name, z, inst, cx, cy, rad, hs, ss, nm, nmap, fr, dw, pts?, m? }
--               pts: a shape drawn on the world map, { { x, y }, ... } (3 to 16
--               corners); without it the play area is the circle rad round
--               cx, cy. m: the zone map it was set on, for the page's map.
--   hide.join   a player       { id }
--   hide.leave  a player       { id }       before the start
--   hide.start  the organiser  { id, sk }   the first seeker
--   hide.found  a hider        { id, by }   found by that seeker
--   hide.out    a player       { id }       left the play area
--   hide.flag   a player       { id, f }    "names": turned names back on
--   hide.close  organiser or the Crown { id } ends it with no result
--
-- Placings (Duncan, 2026-11-10), for the games log and the District Cup:
--   everyone found:  1st the seeker with the most finds, 2nd the last found,
--                    3rd the one found before them.
--   time runs out:   1st everyone never found (shared), 2nd the top seeker,
--                    3rd the last found.
-- The top seeker is the one with most finds; a tie goes to who got there first.

local _, MOTA = ...
local Hide = {}
MOTA.Hide = Hide

Hide.FIND = 6        -- yards
Hide.DWELL = 2       -- seconds within FIND
Hide.WARM = 20       -- yards: the hider's glow
Hide.OUT_GRACE = 10  -- seconds outside the play area
Hide.SEND_EVERY = 1.5
Hide.STALE = 5       -- a seeker's place older than this is ignored
Hide.TICK = 0.25
Hide.RADII = { 50, 100, 150, 250, 400 }
Hide.DEFAULTS = { hs = 120, ss = 900, rad = 100 }
Hide.MIN_PLAYERS = 2
Hide.MIN_PTS, Hide.MAX_PTS = 3, 16

-- Add-ons that tell the guild where its members stand, so hiders would show
-- on a map: players with one loaded can't join until they turn it off.
-- { folder = "...", label = "..." }. Empty until we find one in use (OpenMap
-- only draws the map; it shares nothing).
Hide.BLOCKED = {}

-- The game's settings that show friendly players' names.
Hide.CVARS = { "UnitNameFriendlyPlayerName", "nameplateShowFriends" }

local function str(v, max) return type(v) == "string" and v ~= "" and #v <= max end
local function num(v) return type(v) == "number" end
local function canRun(name) return MOTA.Games and MOTA.Games:CanRun(name) end
local function now() return GetServerTime() end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

local function validPts(p)
  if p == nil then return true end
  if type(p) ~= "table" or #p < Hide.MIN_PTS or #p > Hide.MAX_PTS then return false end
  for _, q in ipairs(p) do
    if type(q) ~= "table" or not num(q.x) or not num(q.y) then return false end
  end
  return true
end

local R = MOTA.Book.rules
R["hide.open"] = function(a, rec)
  local d = rec and rec.d or {}
  return canRun(a) and validPts(d.pts) and (d.m == nil or num(d.m)) and str(d.name, 40) and str(d.z, 60) and num(d.inst) and num(d.cx) and num(d.cy)
    and num(d.rad) and d.rad >= 20 and d.rad <= 1000 and num(d.hs) and d.hs >= 10 and d.hs <= 1800
    and num(d.ss) and d.ss >= 60 and d.ss <= 7200 or false
end
for _, k in ipairs({ "hide.join", "hide.leave", "hide.out", "hide.close" }) do
  R[k] = function(a, rec) return str(rec and rec.d and rec.d.id, 60) or false end
end
R["hide.start"] = function(a, rec)
  local d = rec and rec.d or {}
  return str(d.id, 60) and d.id:match("^(.-)#%d+$") == a and str(d.sk, 40) or false
end
R["hide.found"] = function(a, rec)
  local d = rec and rec.d or {}
  return str(d.id, 60) and str(d.by, 40) and d.by ~= a or false
end
R["hide.flag"] = function(a, rec)
  local d = rec and rec.d or {}
  return str(d.id, 60) and (d.f == "names") or false
end

local cache

local function build()
  local out = { all = {} }
  local byId = {}
  local list = MOTA.Book:Latest()
  for i = #list, 1, -1 do -- oldest first
    local r = list[i]
    local d = r.d or {}
    local G = byId[d.id]
    if r.k == "hide.open" then
      G = { id = r.a .. "#" .. r.n, by = r.a, t = r.t, name = d.name, z = d.z, inst = d.inst, cx = d.cx, cy = d.cy,
        rad = d.rad, pts = d.pts, m = d.m, hs = d.hs, ss = d.ss, nm = d.nm and true or false, nmap = d.nmap and true or false,
        fr = num(d.fr) and d.fr or Hide.FIND, dw = num(d.dw) and d.dw or Hide.DWELL,
        players = {}, joined = {}, seekers = {}, finds = {}, reached = {}, found = {}, foundBy = {}, out = {}, flags = {} }
      byId[G.id] = G
      out.all[#out.all + 1] = G
    elseif G and not G.closed then
      local playing = G.start and not G.ended
      if r.k == "hide.close" and (MOTA:IsCrown(r.a) or r.a == G.by) and not G.ended and not (G.ends and r.t >= G.ends) then
        G.closed = { t = r.t, by = r.a }
      elseif not G.start and r.k == "hide.join" and not G.joined[r.a] then
        G.joined[r.a] = true
        G.players[#G.players + 1] = r.a
      elseif not G.start and r.k == "hide.leave" and G.joined[r.a] then
        G.joined[r.a] = nil
        for j, p in ipairs(G.players) do if p == r.a then table.remove(G.players, j) break end end
      elseif not G.start and r.k == "hide.start" and r.a == G.by and G.joined[d.sk] and #G.players >= Hide.MIN_PLAYERS then
        G.start = r.t
        G.sk = d.sk
        G.seekers[d.sk] = r.t
        G.seekFrom = r.t + G.hs
        G.ends = G.seekFrom + G.ss
      elseif playing and r.t < G.ends and r.k == "hide.found" and G.joined[r.a] and not G.seekers[r.a] and not G.out[r.a]
        and G.seekers[d.by] and r.t >= G.seekFrom then
        G.seekers[r.a] = r.t
        G.found[#G.found + 1] = { name = r.a, t = r.t, by = d.by }
        G.foundBy[r.a] = d.by
        G.finds[d.by] = (G.finds[d.by] or 0) + 1
        G.reached[d.by] = r.t
      elseif playing and r.t < G.ends and r.k == "hide.out" and G.joined[r.a] and not G.out[r.a] and not G.seekers[r.a] then
        G.out[r.a] = r.t
      elseif r.k == "hide.flag" and G.joined[r.a] then
        G.flags[r.a] = G.flags[r.a] or {}
        G.flags[r.a][d.f] = true
      end
      -- Nobody left hidden: the game is over at once.
      if G.start and not G.ended and (r.k == "hide.found" or r.k == "hide.out") then
        local left = 0
        for _, p in ipairs(G.players) do
          if not G.seekers[p] and not G.out[p] then left = left + 1 end
        end
        if left == 0 then G.ended = { t = r.t, all = true } end
      end
    end
  end
  out.cur = out.all[#out.all]
  return out
end

local function get()
  if not cache then cache = build() end
  return cache
end

function Hide:Current() return get().cur end
function Hide:All() return get().all end
function Hide:Get(id)
  for _, G in ipairs(get().all) do if G.id == id then return G end end
end

-- "lobby", "hiding", "seeking", "done", "closed", or nil.
function Hide:Stage(G, at)
  G = G or self:Current()
  if not G then return nil end
  if G.closed then return "closed" end
  if not G.start then return "lobby" end
  if G.ended then return "done" end
  at = at or now()
  if at >= G.ends then return "done" end
  if at < G.seekFrom then return "hiding" end
  return "seeking"
end

function Hide:Live(G)
  local s = self:Stage(G)
  return s == "lobby" or s == "hiding" or s == "seeking"
end

-- Seconds left in this phase.
function Hide:Left(G, at)
  G = G or self:Current()
  at = at or now()
  local s = self:Stage(G, at)
  if s == "hiding" then return G.seekFrom - at end
  if s == "seeking" then return G.ends - at end
  return 0
end

function Hide:Role(name, G)
  G = G or self:Current()
  if not G or not G.joined[name] then return nil end
  if G.out[name] then return "out" end
  if G.seekers[name] then return "seeker" end
  return "hider"
end

-- Still hidden: { name, ... }.
function Hide:Hidden(G)
  local out = {}
  for _, p in ipairs(G.players) do
    if not G.seekers[p] and not G.out[p] then out[#out + 1] = p end
  end
  return out
end

-- Seekers, most finds first (a tie: the one who got there first).
function Hide:Seekers(G)
  local out = {}
  for name in pairs(G.seekers) do
    out[#out + 1] = { name = name, n = G.finds[name] or 0, t = G.reached[name] or G.seekers[name], first = name == G.sk }
  end
  table.sort(out, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    if a.t ~= b.t then return a.t < b.t end
    return a.name < b.name
  end)
  return out
end

-- The placings once it's over: places = { name, ... }, at = { rank, ... }.
function Hide:Places(G)
  local places, at, seen = {}, {}, {}
  local function put(name, rank)
    if name and not seen[name] and #places < MOTA.Games.MAX_PLACES then
      seen[name] = true
      places[#places + 1] = name
      at[#at + 1] = rank
    end
  end
  local s = self:Seekers(G)
  local top = s[1] and s[1].n > 0 and s[1].name or nil
  local last, before = G.found[#G.found], G.found[#G.found - 1]
  local hidden = self:Hidden(G)
  if #hidden == 0 then
    put(top, 1)
    put(last and last.name, 2)
    put(before and before.name, 3)
  else
    table.sort(hidden)
    for _, h in ipairs(hidden) do put(h, 1) end
    put(top, 2)
    put(last and last.name, 3)
  end
  return places, at
end

---------------------------------------------------------------------------
-- The play area: a circle or a drawn shape
---------------------------------------------------------------------------

-- The edge as corners: the drawn shape, or the circle as 48 of them.
function Hide:Shape(A)
  if A.pts then return A.pts end
  local out = {}
  for i = 1, 48 do
    local ang = (i - 1) / 48 * 2 * math.pi
    out[i] = { x = A.cx + A.rad * math.cos(ang), y = A.cy + A.rad * math.sin(ang) }
  end
  return out
end

local function inPolygon(p, x, y)
  local inside, j = false, #p
  for i = 1, #p do
    local a, b = p[i], p[j]
    if (a.y > y) ~= (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x then inside = not inside end
    j = i
  end
  return inside
end

local function toSegment(x, y, a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  local len = dx * dx + dy * dy
  local t = len > 0 and math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / len)) or 0
  local px, py = a.x + t * dx, a.y + t * dy
  return math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
end

-- Whether a spot is inside the play area.
function Hide:Inside(A, inst, x, y)
  if inst ~= A.inst then return false end
  if A.pts then return inPolygon(A.pts, x, y) end
  return math.sqrt((x - A.cx) ^ 2 + (y - A.cy) ^ 2) <= A.rad
end

-- Yards to the edge (negative outside), or nil in another world.
function Hide:ToEdge(A, inst, x, y)
  if inst ~= A.inst then return nil end
  if not A.pts then return A.rad - math.sqrt((x - A.cx) ^ 2 + (y - A.cy) ^ 2) end
  local best = math.huge
  local p = A.pts
  for i = 1, #p do
    best = math.min(best, toSegment(x, y, p[i], p[i % #p + 1]))
  end
  return inPolygon(p, x, y) and best or -best
end

---------------------------------------------------------------------------
-- The organiser
---------------------------------------------------------------------------

function Hide:Draft()
  MOTA.db.hideDraft = MOTA.db.hideDraft or { name = "", rad = self.DEFAULTS.rad, hs = self.DEFAULTS.hs, ss = self.DEFAULTS.ss, nm = true, nmap = true }
  return MOTA.db.hideDraft
end

-- Where the player stands: the world and x, y in yards (as the hunt).
function Hide:Where() return MOTA.Hunt:Where() end

-- The play area's centre: where you stand, or a spot picked on the map.
function Hide:SetCentre(inst, x, y, zone)
  if not inst then
    inst, x, y = self:Where()
    if not x then return nil, "The game won't say where you are here. Play areas are outdoors." end
    zone = GetZoneText and GetZoneText() or ""
  end
  local d = self:Draft()
  d.inst, d.cx, d.cy = inst, math.floor(x * 10 + 0.5) / 10, math.floor(y * 10 + 0.5) / 10
  d.z = (zone and zone ~= "") and zone or "Somewhere"
  d.pts = nil
  d.m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
  MOTA:Fire("HIDE_CHANGED")
  return true
end

-- Drawing a shape: corners added one at a time (UI/HideMap.lua clicks them on the map).
function Hide:AddCorner(inst, x, y, zone, mapID)
  local d = self:Draft()
  if d.pts and #d.pts > 0 and d.inst ~= inst then return nil, "Every corner must be in the same part of the world." end
  if not d.pts then d.pts = {} end
  if #d.pts >= self.MAX_PTS then return nil, "A shape has at most " .. self.MAX_PTS .. " corners." end
  if #d.pts == 0 then
    d.inst, d.z, d.m = inst, (zone and zone ~= "") and zone or "Somewhere", mapID
  end
  d.pts[#d.pts + 1] = { x = math.floor(x * 10 + 0.5) / 10, y = math.floor(y * 10 + 0.5) / 10 }
  self:FitShape()
  MOTA:Fire("HIDE_CHANGED")
  return #d.pts
end

function Hide:UndoCorner()
  local d = self:Draft()
  if not d.pts or #d.pts == 0 then return nil, "No corners to take back." end
  table.remove(d.pts)
  if #d.pts == 0 then d.pts, d.cx = nil, nil end
  self:FitShape()
  MOTA:Fire("HIDE_CHANGED")
  return true
end

-- A shape's middle and reach (for the page's map and the size limit).
function Hide:FitShape()
  local d = self:Draft()
  if not d.pts or #d.pts == 0 then return end
  local sx, sy = 0, 0
  for _, q in ipairs(d.pts) do sx, sy = sx + q.x, sy + q.y end
  d.cx, d.cy = math.floor(sx / #d.pts * 10 + 0.5) / 10, math.floor(sy / #d.pts * 10 + 0.5) / 10
  local far = 0
  for _, q in ipairs(d.pts) do far = math.max(far, math.sqrt((q.x - d.cx) ^ 2 + (q.y - d.cy) ^ 2)) end
  d.rad = math.max(20, math.ceil(far))
end

function Hide:SetRadius(r)
  if self:Draft().pts then return end -- a drawn shape keeps its own size
  self:Draft().rad = math.max(20, math.min(1000, r))
  MOTA:Fire("HIDE_CHANGED")
end

function Hide:Open(name)
  if not canRun(MOTA.me) then return nil, "Only the Crown and the Minister of Games run Hide and Seek." end
  if self:Live() then return nil, "A game is already on." end
  local d = self:Draft()
  if not d.cx then return nil, "Set the play area first: stand in its middle, or draw it on the map." end
  if d.pts and #d.pts < self.MIN_PTS then return nil, "A drawn play area needs at least " .. self.MIN_PTS .. " corners." end
  if d.rad > 1000 then return nil, "That play area is too big: keep it within 1000 yards of its middle." end
  name = strtrim(name or d.name or "")
  if name == "" then name = "Hide and Seek" end
  if #name > 40 then return nil, "Keep the name to 40 letters." end
  local rec, err = MOTA.Book:Write("hide.open", { name = name, z = d.z, inst = d.inst, cx = d.cx, cy = d.cy, rad = d.rad,
    hs = d.hs, ss = d.ss, nm = d.nm and true or false, nmap = d.nmap and true or false, fr = self.FIND, dw = self.DWELL,
    pts = d.pts, m = d.m })
  if rec then MOTA.db.hideDraft = nil end
  return rec, err
end

-- seeker: a player's name, or nil to pick one at random.
function Hide:Start(seeker)
  local G = self:Current()
  if self:Stage(G) ~= "lobby" then return nil, "No game is waiting to start." end
  if not MOTA:IsMe(G.by) then return nil, "Only " .. MOTA:Short(G.by) .. ", who opened it, can start it." end
  if #G.players < self.MIN_PLAYERS then return nil, "At least " .. self.MIN_PLAYERS .. " players must join first." end
  if seeker and not G.joined[seeker] then return nil, MOTA:Short(seeker) .. " hasn't joined." end
  seeker = seeker or G.players[math.random(#G.players)]
  return MOTA.Book:Write("hide.start", { id = G.id, sk = seeker })
end

function Hide:Close()
  local G = self:Current()
  if not self:Live(G) then return nil, "No game is on." end
  if not (MOTA:IsCrown(MOTA.me) or MOTA:IsMe(G.by)) then return nil, "Only " .. MOTA:Short(G.by) .. ", who opened it, or the Crown can end it." end
  return MOTA.Book:Write("hide.close", { id = G.id })
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

local function loaded(folder)
  if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(folder) and true or false end
  return IsAddOnLoaded and IsAddOnLoaded(folder) and true or false
end

-- The first loaded add-on that would give hiders away, or nil.
function Hide:Blocker()
  for _, b in ipairs(self.BLOCKED) do
    if loaded(b.folder) then return b.label or b.folder end
  end
end

function Hide:Join()
  local G = self:Current()
  if self:Stage(G) ~= "lobby" then return nil, "No game is open to join." end
  if G.joined[MOTA.me] then return nil, "You've already joined." end
  local b = self:Blocker()
  if b then return nil, "Turn off " .. b .. " and /reload to join: it shows guild members on the map." end
  return MOTA.Book:Write("hide.join", { id = G.id })
end

function Hide:Leave()
  local G = self:Current()
  if self:Stage(G) ~= "lobby" or not G.joined[MOTA.me] then return nil, "You're not in a game waiting to start." end
  return MOTA.Book:Write("hide.leave", { id = G.id })
end

---------------------------------------------------------------------------
-- Seekers' places (HP: id, world, x, y), heard but never kept
---------------------------------------------------------------------------

Hide.pos = {}

MOTA.Comm:Handle("HP", function(self, sender, channel, f)
  if channel ~= "GUILD" then return end
  local G = Hide:Current()
  if not G or f[1] ~= G.id or not G.seekers[sender] then return end
  local inst, x, y = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
  if inst and x and y then Hide.pos[sender] = { inst = inst, x = x, y = y, at = GetTime() } end
end)

---------------------------------------------------------------------------
-- Hiding names, and the map
---------------------------------------------------------------------------

local function cvar(k) return GetCVar and GetCVar(k) end

-- Turns friendly names off, keeping what was there to put back.
function Hide:HideNames()
  if not SetCVar or InCombatLockdown() then return false end
  if not MOTA.db.hideSaved then
    local saved = {}
    for _, k in ipairs(self.CVARS) do saved[k] = cvar(k) or "1" end
    MOTA.db.hideSaved = saved
  end
  for _, k in ipairs(self.CVARS) do SetCVar(k, "0") end
  self.namesHidden = true
  return true
end

function Hide:RestoreNames()
  local saved = MOTA.db and MOTA.db.hideSaved
  if not saved or not SetCVar or InCombatLockdown() then return false end
  for k, v in pairs(saved) do SetCVar(k, v) end
  MOTA.db.hideSaved = nil
  self.namesHidden = false
  return true
end

-- Names turned back on by hand during the game.
function Hide:NamesShowing()
  for _, k in ipairs(self.CVARS) do
    if cvar(k) == "1" then return true end
  end
  return false
end

-- The world map stays shut for players in a "No map" game, hiding to the end.
function Hide:MapBlocked()
  local G = self:Current()
  local s = self:Stage(G)
  return G ~= nil and G.nmap and (s == "hiding" or s == "seeking") and self:Role(MOTA.me, G) ~= nil and self:Role(MOTA.me, G) ~= "out"
end

local hooked
local function hookMap()
  local map = _G.WorldMapFrame
  if hooked or not map or not map.HookScript then return end
  hooked = true
  map:HookScript("OnShow", function(f)
    if Hide:MapBlocked() and not InCombatLockdown() then
      f:Hide()
      MOTA:Print("No map in this game of Hide and Seek. The play area is on the Games Hall page.")
    end
  end)
end

---------------------------------------------------------------------------
-- The tick: sending, hiding, the edge of the play area
---------------------------------------------------------------------------

Hide.dwell = {}
Hide.outside = 0
Hide.warm = false
local sendWait, lastPhase, flagged, recorded = 0, nil, {}, {}

local function glow(v)
  if MOTA.HuntGlow then MOTA.HuntGlow:Set(v) end
end

-- Distance from the play area's middle, or nil in another world.
function Hide:FromCentre(G, inst, x, y)
  if inst ~= G.inst then return nil end
  return math.sqrt((x - G.cx) ^ 2 + (y - G.cy) ^ 2)
end

-- The organiser's add-on writes the result once the game is over.
local function record(G)
  if recorded[G.id] or not MOTA:IsMe(G.by) or not MOTA.Games then return end
  for _, e in ipairs(MOTA.Games:Log()) do
    if e.g == "hide" and e.name == G.name and e.t >= G.t then recorded[G.id] = true return end
  end
  local places, at = Hide:Places(G)
  recorded[G.id] = true
  if #places > 0 then MOTA.Games:Record("hide", G.name, places, at) end
end

function Hide:Tick(dt)
  local G = self:Current()
  local stage = self:Stage(G)
  if stage ~= lastPhase then
    local was = lastPhase
    lastPhase = stage
    self.dwell, self.outside, self.warm = {}, 0, false
    glow(0)
    if stage == "seeking" and was == "hiding" and self:Role(MOTA.me, G) then
      MOTA:Print(MOTA:Color("leaf", "Hide and Seek:"), "ready or not, the seekers are coming!")
    end
    MOTA:Fire("HIDE_CHANGED")
  end
  if not G then return end
  if stage == "done" then
    if self.namesHidden or MOTA.db.hideSaved then self:RestoreNames() end
    record(G)
    return
  end
  if stage ~= "hiding" and stage ~= "seeking" then
    if MOTA.db.hideSaved then self:RestoreNames() end
    return
  end
  local role = self:Role(MOTA.me, G)
  if not role or role == "out" then
    if MOTA.db.hideSaved then self:RestoreNames() end
    return
  end

  -- Names off, and noticed if they're turned back on.
  if G.nm then
    if not self.namesHidden then self:HideNames()
    elseif self:NamesShowing() and not flagged[G.id] then
      flagged[G.id] = true
      MOTA.Book:Write("hide.flag", { id = G.id, f = "names" })
    end
  end

  local inst, x, y = self:Where()
  if not x then return end

  -- The edge of the play area.
  if not self:Inside(G, inst, x, y) then
    local before = self.outside
    self.outside = self.outside + dt
    local left = math.ceil(self.OUT_GRACE - self.outside)
    if left > 0 and (math.floor(before) ~= math.floor(self.outside) or before == 0) then
      MOTA:Print(MOTA:Color("leaf", "Out of bounds:"), left .. "s to get back in.")
    end
    if self.outside >= self.OUT_GRACE then
      self.outside = 0
      MOTA.Book:Write("hide.out", { id = G.id })
      MOTA:Print("You left the play area, so you're out of", G.name .. ".")
      return
    end
  elseif self.outside > 0 then
    self.outside = 0
    MOTA:Print("Back inside the play area.")
  end

  if stage ~= "seeking" then return end
  if role == "seeker" then
    sendWait = sendWait - dt
    if sendWait <= 0 then
      sendWait = self.SEND_EVERY
      MOTA.Comm:Send(MOTA.Comm:Pack("HP", G.id, inst, string.format("%.1f", x), string.format("%.1f", y)), "GUILD")
    end
    return
  end

  -- A hider: is a seeker on top of me?
  local nearest
  local t = GetTime()
  for name, p in pairs(self.pos) do
    if G.seekers[name] and t - p.at <= self.STALE and p.inst == inst then
      local dist = math.sqrt((x - p.x) ^ 2 + (y - p.y) ^ 2)
      if dist <= G.fr then
        self.dwell[name] = (self.dwell[name] or 0) + dt
        if self.dwell[name] >= G.dw then
          self.dwell = {}
          glow(0)
          MOTA.Book:Write("hide.found", { id = G.id, by = name })
          MOTA:Print(MOTA:Color("leaf", "Found!"), MOTA:Short(name), "found you. You're a seeker now.")
          return "found"
        end
      else
        self.dwell[name] = nil
      end
      nearest = (not nearest or dist < nearest) and dist or nearest
    else
      self.dwell[name] = nil
    end
  end
  local warm = nearest ~= nil and nearest <= self.WARM
  glow(warm and (0.3 + 0.7 * (self.WARM - nearest) / self.WARM) or 0)
  if warm ~= self.warm then
    self.warm = warm
    MOTA:Fire("HIDE_CHANGED")
  end
end

local ticker
local function startTicking()
  hookMap()
  if ticker or not C_Timer or not C_Timer.NewTicker then return end
  ticker = C_Timer.NewTicker(Hide.TICK, function()
    Hide:Tick(Hide.TICK)
    local G = Hide:Current()
    if not Hide:Live(G) and not (MOTA.db and MOTA.db.hideSaved) then
      ticker:Cancel()
      ticker = nil
    end
  end)
end
Hide.StartTicking = startTicking

---------------------------------------------------------------------------
-- Lines, heralds, listening
---------------------------------------------------------------------------

local function clock(s)
  s = math.max(0, math.floor(s))
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
Hide.Clock = clock

function Hide:Line(G)
  G = G or self:Current()
  local s = self:Stage(G)
  if not s then return "No game has been opened yet." end
  if s == "lobby" then return #G.players .. " joined · waiting for " .. MOTA:Short(G.by) .. " to start" end
  if s == "hiding" then return "Hiding · " .. clock(self:Left(G)) .. " until the seekers set off" end
  if s == "seeking" then return #self:Hidden(G) .. " still hidden · " .. clock(self:Left(G)) .. " left" end
  if s == "closed" then return "Ended with no result." end
  local places = self:Places(G)
  return places[1] and ("Won by " .. MOTA:Short(places[1])) or "Over."
end

local function changed()
  cache = nil
  MOTA:Fire("HIDE_CHANGED")
end

MOTA:Listen("GUILD_READY", function()
  changed()
  C_Timer.After(6, function()
    local G = Hide:Current()
    if Hide:Live(G) or MOTA.db.hideSaved or (G and Hide:Stage(G) == "done") then startTicking() end
  end)
end)
MOTA:Listen("CAUGHT_UP", function()
  changed()
  if Hide:Live() then startTicking() end
end)
MOTA:On("PLAYER_REGEN_ENABLED", function()
  -- Settings wait for combat to end.
  if MOTA.db and MOTA.db.hideSaved and not Hide:Live() then Hide:RestoreNames() end
end)

MOTA:Listen("RECORD_ADDED", function(self, rec)
  if not rec.k:find("^hide%.") then return end
  changed()
  local G = Hide:Current()
  if not G then return end
  if Hide:Live(G) then startTicking() end
  local d = rec.d or {}
  if d.id and d.id ~= G.id and rec.k ~= "hide.open" then return end
  if self.Book.replaying or not self.Herald then return end
  local Hd = self.Herald
  if rec.k == "hide.open" then
    Hd:Announce({ seal = "official", eyebrow = "Hide and Seek", title = tostring(d.name) .. " is open",
      text = "In " .. tostring(d.z) .. ", within " .. tostring(d.rad) .. " yards. Join from the Games Hall before " .. self:Short(rec.a) .. " starts it.",
      button = { label = "Open", style = "blue", page = 8 } })
  elseif rec.k == "hide.start" and G.joined[self.me] then
    local seeking = d.sk == self.me
    Hd:Announce({ seal = "official", eyebrow = "Hide and Seek", title = seeking and "You're the seeker" or "Hide!",
      text = seeking and ("Stay where you are for " .. clock(G.hs) .. " while everyone hides. Then find them: stand right next to a hider for " .. G.dw .. " seconds.")
        or (clock(G.hs) .. " to hide inside the play area. " .. self:Short(d.sk) .. " is seeking. Anyone who's found seeks too."),
      button = { label = "Dismiss", style = "quiet" } })
  elseif rec.k == "hide.found" and d.by == self.me and G.foundBy[rec.a] == d.by then
    self:Print(self:Color("leaf", "Found:"), self:Short(rec.a) .. ". They're seeking with you now.")
  elseif rec.k == "hide.close" then
    self:Print(G.name, "has been ended with no result.")
  end
end)
