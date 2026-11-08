-- Ministry of the Allied: the Treasure Hunt (Duncan, 2026-11-08).
-- The Crown or the Minister of Games stands at real places in the world and
-- marks each one with a riddle. Hunters solve the riddles and stand on the
-- spots: within 24 yards they're told they're close, within 10 the spot is
-- found and the next riddle opens. The first to find the last spot wins, and
-- the hunt closes. Glory only: the games log, the Pathfinder's Medal, and
-- (later) points for the District Cup.
--
--   hunt.open   the Crown or the Minister of Games  { name, salt, clues = { { z, h, w, e } } }
--   hunt.found  a hunter                             { id, i }   found spot i
--   hunt.close  the organiser or the Crown           { id }      ends it with no winner
--
-- Keeping the spots secret: a spot is never written down, only two
-- fingerprints of it (SHA-256, Sha256.lua): h, of the 7-yard square it's in,
-- and w, of the 16-yard square. A hunter's add-on fingerprints the squares
-- round where they stand and compares. Each riddle after the first is sealed
-- (e) with a key made from the spot before it, so riddle 3 can only be read by
-- someone who has stood on spot 2. Clue 1's riddle is open (e is plain text).
-- z is the zone's name, shown with each riddle.
--
-- Positions come from UnitPosition, in yards; the game gives none inside
-- dungeons and raids, so spots are outdoors. Each player's add-on is trusted
-- about where they stood, as with every other record.

local _, MOTA = ...
local Hunt = {}
MOTA.Hunt = Hunt

Hunt.FINE, Hunt.WARM = 7, 16 -- square sizes in yards: with the squares round, about 10 and 24
Hunt.MIN_CLUES, Hunt.MAX_CLUES = 2, 10
Hunt.MAX_RIDDLE = 140
Hunt.TICK = 2 -- seconds between looks at where you stand

local function str(v, max) return type(v) == "string" and v ~= "" and #v <= max end
local function canRun(name) return MOTA.Games and MOTA.Games:CanRun(name) end
local sha = function(t) return MOTA.Sha256(t) end

---------------------------------------------------------------------------
-- Squares, fingerprints and sealing
---------------------------------------------------------------------------

-- Where the player stands: the world (instance) and x, y in yards, or nil.
function Hunt:Where()
  if not UnitPosition then return nil end
  local y, x, _, inst = UnitPosition("player")
  if not x or not y then return nil end
  return inst or 0, x, y
end

local function square(x, y, size) return math.floor(x / size), math.floor(y / size) end

function Hunt:SpotPrint(salt, inst, cx, cy) return sha("spot|" .. salt .. "|" .. inst .. "|" .. cx .. "," .. cy):sub(1, 16) end
function Hunt:WarmPrint(salt, inst, cx, cy) return sha("near|" .. salt .. "|" .. inst .. "|" .. cx .. "," .. cy):sub(1, 16) end
local function keyFor(salt, inst, cx, cy) return sha("key|" .. salt .. "|" .. inst .. "|" .. cx .. "," .. cy) end

-- Seals or opens text with a key (the same XOR both ways), as hex.
local function stream(key, n)
  local out, block = {}, 0
  while #out < n do
    local h = sha(key .. "#" .. block)
    for i = 1, 63, 2 do out[#out + 1] = tonumber(h:sub(i, i + 1), 16) end
    block = block + 1
  end
  return out
end
function Hunt:Seal(text, key)
  local ks, out = stream(key, #text), {}
  for i = 1, #text do out[i] = string.format("%02x", MOTA.ByteXor(text:byte(i), ks[i])) end
  return table.concat(out)
end
function Hunt:Open(hex, key)
  if type(hex) ~= "string" or #hex % 2 ~= 0 then return nil end
  local n = #hex / 2
  local ks, out = stream(key, n), {}
  for i = 1, n do
    local b = tonumber(hex:sub(i * 2 - 1, i * 2), 16)
    if not b then return nil end
    out[i] = string.char(MOTA.ByteXor(b, ks[i]))
  end
  return table.concat(out)
end

---------------------------------------------------------------------------
-- The record rules and the hunts, from the book
---------------------------------------------------------------------------

MOTA.Book.rules["hunt.open"] = function(a, rec)
  local d = rec and rec.d or {}
  if not canRun(a) or not str(d.name, 40) or not str(d.salt, 40) or type(d.clues) ~= "table" then return false end
  if #d.clues < Hunt.MIN_CLUES or #d.clues > Hunt.MAX_CLUES then return false end
  for _, c in ipairs(d.clues) do
    if type(c) ~= "table" or not str(c.h, 16) or not str(c.w, 16) or not str(c.z, 60) or not str(c.e, Hunt.MAX_RIDDLE * 2) then return false end
  end
  return true
end
MOTA.Book.rules["hunt.found"] = function(a, rec)
  local d = rec and rec.d or {}
  return str(d.id, 60) and type(d.i) == "number"
end
MOTA.Book.rules["hunt.close"] = function(a, rec)
  local d = rec and rec.d or {}
  return str(d.id, 60) and (MOTA:IsCrown(a) or d.id:match("^(.-)#%d+$") == a)
end

local cache
local function build()
  local out = { all = {} }
  local byId = {}
  local list = MOTA.Book:Latest()
  for i = #list, 1, -1 do -- oldest first
    local r = list[i]
    local d = r.d or {}
    if r.k == "hunt.open" and type(d.clues) == "table" and #d.clues >= Hunt.MIN_CLUES then
      local H = { id = r.a .. "#" .. r.n, by = r.a, t = r.t, name = d.name, salt = d.salt, clues = d.clues,
        progress = {}, found = {} }
      byId[H.id] = H
      out.all[#out.all + 1] = H
    elseif r.k == "hunt.found" and byId[d.id] then
      local H = byId[d.id]
      -- In order, one spot at a time, never by the organiser, and only until someone finishes.
      local k = MOTA.Account:Key(r.a)
      if not H.ended and not MOTA.Account:Same(r.a, H.by) and d.i == (H.progress[k] or 0) + 1 and d.i <= #H.clues then
        H.progress[k] = d.i
        H.found[k] = { name = r.a, t = r.t }
        if d.i == #H.clues then H.winner, H.ended = r.a, { t = r.t, won = true } end
      end
    elseif r.k == "hunt.close" and byId[d.id] and not byId[d.id].ended then
      byId[d.id].ended = { t = r.t, by = r.a }
    end
  end
  out.cur = out.all[#out.all]
  return out
end

local function get()
  if not cache then cache = build() end
  return cache
end

function Hunt:Current() return get().cur end
function Hunt:All() return get().all end

-- "running", "won", "closed", or nil.
function Hunt:Stage(H)
  H = H or self:Current()
  if not H then return nil end
  if H.ended then return H.ended.won and "won" or "closed" end
  return "running"
end

-- How many spots a player has found (on any of their characters).
function Hunt:Progress(name, H)
  H = H or self:Current()
  if not H then return 0 end
  return H.progress[MOTA.Account:Key(name)] or 0
end

-- Everyone who has found at least one spot, furthest first: { name, n, t }.
function Hunt:Hunters(H)
  H = H or self:Current()
  local out = {}
  if not H then return out end
  for k, n in pairs(H.progress) do
    out[#out + 1] = { name = H.found[k].name, n = n, t = H.found[k].t }
  end
  table.sort(out, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.t < b.t -- reached it sooner
  end)
  return out
end

---------------------------------------------------------------------------
-- Riddles: the first is open; the rest open as their spots are found
---------------------------------------------------------------------------

local function opened()
  MOTA.db.huntRiddles = MOTA.db.huntRiddles or {} -- account-wide, so alts keep them
  return MOTA.db.huntRiddles
end

-- The riddle of clue i, if this player can read it, and its zone.
function Hunt:Riddle(i, H)
  H = H or self:Current()
  local c = H and H.clues[i]
  if not c then return nil end
  if i == 1 then return c.e, c.z end
  local mine = opened()[H.id]
  if mine and mine[i] then return mine[i], c.z end
  -- The organiser wrote them, so their add-on keeps them.
  local draft = MOTA.db.huntSet and MOTA.db.huntSet[H.id]
  if draft and draft[i] then return draft[i], c.z end
  return nil, c.z
end

---------------------------------------------------------------------------
-- The organiser: a draft, marked spot by spot, then published
---------------------------------------------------------------------------

function Hunt:Draft()
  MOTA.db.huntDraft = MOTA.db.huntDraft or { name = "", clues = {} }
  return MOTA.db.huntDraft
end

function Hunt:Mark(riddle)
  if not canRun(MOTA.me) then return nil, "Only the Crown and the Minister of Games set hunts." end
  riddle = strtrim(riddle or "")
  if riddle == "" then return nil, "Write the riddle for this spot first." end
  if #riddle > self.MAX_RIDDLE then return nil, "Keep the riddle to " .. self.MAX_RIDDLE .. " letters." end
  local inst, x, y = self:Where()
  if not x then return nil, "The game won't say where you are here. Spots must be outdoors, not in a dungeon or raid." end
  local d = self:Draft()
  if #d.clues >= self.MAX_CLUES then return nil, "A hunt has at most " .. self.MAX_CLUES .. " clues." end
  local zone = GetZoneText and GetZoneText() or ""
  d.clues[#d.clues + 1] = { riddle = riddle, z = zone ~= "" and zone or "Somewhere", inst = inst, x = x, y = y }
  MOTA:Fire("HUNT_CHANGED")
  return d.clues[#d.clues]
end

function Hunt:Unmark()
  local d = self:Draft()
  if #d.clues == 0 then return nil, "No clues marked yet." end
  table.remove(d.clues)
  MOTA:Fire("HUNT_CHANGED")
  return true
end

function Hunt:Discard()
  MOTA.db.huntDraft = nil
  MOTA:Fire("HUNT_CHANGED")
  return true
end

function Hunt:Publish(name)
  if not canRun(MOTA.me) then return nil, "Only the Crown and the Minister of Games set hunts." end
  if self:Stage() == "running" then return nil, "A hunt is already running." end
  local d = self:Draft()
  name = strtrim(name or d.name or "")
  if name == "" then name = "The Treasure Hunt" end
  if #name > 40 then return nil, "Keep the name to 40 letters." end
  if #d.clues < self.MIN_CLUES then return nil, "Mark at least " .. self.MIN_CLUES .. " spots first." end
  local salt = GetServerTime() .. "." .. math.random(100000000, 999999999)
  local clues, keys = {}, {}
  for i, c in ipairs(d.clues) do
    local fx, fy = square(c.x, c.y, self.FINE)
    local wx, wy = square(c.x, c.y, self.WARM)
    keys[i] = keyFor(salt, c.inst, fx, fy)
    clues[i] = { z = c.z, h = self:SpotPrint(salt, c.inst, fx, fy), w = self:WarmPrint(salt, c.inst, wx, wy),
      e = i == 1 and c.riddle or self:Seal(c.riddle, keys[i - 1]) }
  end
  local rec, err = MOTA.Book:Write("hunt.open", { name = name, salt = salt, clues = clues })
  if not rec then return nil, err end
  -- Keep the riddles, so the organiser's page can show them.
  MOTA.db.huntSet = MOTA.db.huntSet or {}
  local mine = {}
  for i, c in ipairs(d.clues) do mine[i] = c.riddle end
  MOTA.db.huntSet[rec.a .. "#" .. rec.n] = mine
  MOTA.db.huntDraft = nil
  return rec
end

function Hunt:Close()
  local H = self:Current()
  if self:Stage(H) ~= "running" then return nil, "No hunt is running." end
  if not (MOTA:IsCrown(MOTA.me) or MOTA:IsMe(H.by)) then return nil, "Only " .. MOTA:Short(H.by) .. ", who set it, or the Crown can end it." end
  return MOTA.Book:Write("hunt.close", { id = H.id })
end

---------------------------------------------------------------------------
-- The hunter: looking where you stand
---------------------------------------------------------------------------

Hunt.warm = false
local last -- the square last looked at, so the same one isn't fingerprinted again

-- Looks round where you stand. Returns "found", "warm", or nil.
function Hunt:Look()
  local H = self:Current()
  if self:Stage(H) ~= "running" or not MOTA.me or MOTA.Account:Same(MOTA.me, H.by) then return nil end
  local i = self:Progress(MOTA.me, H) + 1
  local c = H.clues[i]
  if not c then return nil end
  local inst, x, y = self:Where()
  if not x then return nil end
  local fx, fy = square(x, y, self.FINE)
  local key = H.id .. "|" .. i .. "|" .. inst .. "|" .. fx .. "," .. fy
  if key == last then return self.warm and "warm" or nil end
  last = key
  for dx = -1, 1 do
    for dy = -1, 1 do
      if self:SpotPrint(H.salt, inst, fx + dx, fy + dy) == c.h then
        return self:Found(H, i, keyFor(H.salt, inst, fx + dx, fy + dy))
      end
    end
  end
  local wx, wy = square(x, y, self.WARM)
  local warm = false
  for dx = -1, 1 do
    for dy = -1, 1 do
      if self:WarmPrint(H.salt, inst, wx + dx, wy + dy) == c.w then warm = true end
    end
  end
  if warm ~= self.warm then
    self.warm = warm
    if warm then MOTA:Print(MOTA:Color("leaf", "You're close."), "Clue", i, "is within about 24 yards.") end
    MOTA:Fire("HUNT_CHANGED")
  end
  return warm and "warm" or nil
end

-- Spot i is found: open the next riddle and tell the guild.
function Hunt:Found(H, i, key)
  local nextClue = H.clues[i + 1]
  if nextClue then
    local text = self:Open(nextClue.e, key)
    opened()[H.id] = opened()[H.id] or {}
    opened()[H.id][i + 1] = text
  end
  self.warm, last = false, nil
  MOTA.Book:Write("hunt.found", { id = H.id, i = i })
  return "found"
end

local ticker
local function startTicking()
  if ticker or not C_Timer or not C_Timer.NewTicker then return end
  ticker = C_Timer.NewTicker(Hunt.TICK, function()
    if Hunt:Stage() ~= "running" then
      ticker:Cancel()
      ticker = nil
      return
    end
    Hunt:Look()
  end)
end

---------------------------------------------------------------------------
-- Heralds, the games log, and a line for the Throne Room
---------------------------------------------------------------------------

function Hunt:Line(H)
  H = H or self:Current()
  local stage = self:Stage(H)
  if not stage then return "No hunt has been set yet." end
  if stage == "won" then return "Won by " .. MOTA:Short(H.winner) end
  if stage == "closed" then return "Ended with no winner." end
  local n = self:Progress(MOTA.me, H)
  return #H.clues .. " clues · you've found " .. n .. " · first to finish wins"
end

-- The organiser's add-on puts the result in the games log: the winner, then
-- everyone else by how far they got.
local function record(H)
  if not H.winner or not MOTA:IsMe(H.by) or not MOTA.Games then return end
  for _, e in ipairs(MOTA.Games:Log()) do
    if e.g == "hunt" and e.name == H.name and e.t >= H.t then return end -- already there
  end
  local places = {}
  for _, h in ipairs(Hunt:Hunters(H)) do
    if #places < MOTA.Games.MAX_PLACES then places[#places + 1] = h.name end
  end
  MOTA.Games:Record("hunt", H.name, places)
end

local function changed()
  cache, last = nil, nil
  MOTA:Fire("HUNT_CHANGED")
end
MOTA:Listen("GUILD_READY", function()
  changed()
  C_Timer.After(6, function()
    if Hunt:Stage() == "running" then startTicking() end
    local H = Hunt:Current()
    if H and Hunt:Stage(H) == "won" then record(H) end
  end)
end)
MOTA:Listen("CAUGHT_UP", changed)
MOTA:Listen("ACCOUNT_CHANGED", changed)

MOTA:Listen("RECORD_ADDED", function(self, rec)
  if rec.k ~= "hunt.open" and rec.k ~= "hunt.found" and rec.k ~= "hunt.close" then
    if rec.k == "party.post" or rec.k == "ballot.result" then cache = nil end
    return
  end
  changed()
  local H = Hunt:Current()
  if not H then return end
  if Hunt:Stage(H) == "running" then startTicking() end
  if self.Book.replaying or not self.Herald then return end
  local d = rec.d or {}
  local Hd = self.Herald
  if rec.k == "hunt.open" then
    Hd:Announce({ seal = "official", eyebrow = "The Treasure Hunt", title = tostring(d.name) .. " begins",
      text = #H.clues .. " clues, the first in " .. tostring(H.clues[1].z) .. ". First to stand on the last spot wins. See the Games Hall.",
      button = { label = "Open", style = "blue", page = 8 } })
  elseif rec.k == "hunt.found" and d.id == H.id then
    if H.winner and rec.a == H.winner and d.i == #H.clues then
      local mine = self:IsMe(rec.a)
      Hd:Announce({ seal = "official", eyebrow = "The Treasure Hunt",
        title = mine and "You found the treasure!" or (self:Short(rec.a) .. " wins " .. H.name),
        text = (mine and "You" or self:Short(rec.a)) .. " stood on all " .. #H.clues .. " spots first. The Pathfinder's Medal is " .. (mine and "yours." or "theirs."),
        button = { label = "Dismiss", style = "quiet" } })
      record(H)
    elseif self:IsMe(rec.a) then
      local text = Hunt:Riddle(d.i + 1, H)
      Hd:Announce({ seal = "official", eyebrow = "The Treasure Hunt", title = "Clue " .. d.i .. " found!",
        text = "Clue " .. (d.i + 1) .. ", in " .. tostring(H.clues[d.i + 1] and H.clues[d.i + 1].z) .. ": " .. tostring(text or "?"),
        button = { label = "Dismiss", style = "quiet" } })
    end
  elseif rec.k == "hunt.close" and d.id == H.id then
    self:Print(H.name, "has been ended with no winner.")
  end
end)
