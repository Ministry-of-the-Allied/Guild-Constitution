-- Ministry of the Allied: the Treasure Hunt (Duncan, 2026-11-08).
-- The Crown or the Minister of Games stands at real places in the world and
-- marks each one with a riddle. Hunters solve the riddles and stand on the
-- spots: within 50 yards they're told they're getting warmer (and colder as
-- they leave), within 3.5 yards the spot is found and the next riddle opens.
-- The first to find the last spot wins, and the hunt closes. Glory only: the
-- games log, the Pathfinder's Medal, and (later) points for the District Cup.
--
--   hunt.open   the Crown or the Minister of Games  { name, clues = { { z, inst, x, y, r } } }
--   hunt.found  a hunter                             { id, i }   found spot i
--   hunt.close  the organiser or the Crown           { id }      ends it with no winner
--
-- Each spot is kept as it is: the world it's in (inst) and x, y in yards, from
-- where the organiser stood (Max and Duncan, 2026-11-09: true circles rather
-- than hidden squares; reading the spots out of the saved data is cheating,
-- and a matter for the Court). r is the riddle and z the zone's name. The
-- add-on shows riddle 3 only once spot 2 is found.
--
-- Positions come from UnitPosition, in yards and flat (a spot on a bridge also
-- counts underneath it); the game gives none inside dungeons and raids, so
-- spots are outdoors. Each player's add-on is trusted about where they stood.

local _, MOTA = ...
local Hunt = {}
MOTA.Hunt = Hunt

Hunt.FOUND = 3.5 -- yards: stand this close to the spot to find it
Hunt.WARM = 50   -- yards: warmer inside, colder on leaving
Hunt.MIN_CLUES, Hunt.MAX_CLUES = 2, 10
Hunt.MAX_RIDDLE = 140
Hunt.TICK = 0.2 -- seconds between looks at where you stand: on a mount you'd ride over a spot otherwise

local function str(v, max) return type(v) == "string" and v ~= "" and #v <= max end
local function canRun(name) return MOTA.Games and MOTA.Games:CanRun(name) end

-- Where the player stands: the world (instance) and x, y in yards, or nil.
function Hunt:Where()
  if not UnitPosition then return nil end
  local y, x, _, inst = UnitPosition("player")
  if not x or not y then return nil end
  return inst or 0, x, y
end

-- Yards from where you stand to a clue's spot, or nil if it's in another world.
function Hunt:Distance(c, inst, x, y)
  if not c or c.inst ~= inst then return nil end
  return math.sqrt((x - c.x) ^ 2 + (y - c.y) ^ 2)
end

---------------------------------------------------------------------------
-- The record rules and the hunts, from the book
---------------------------------------------------------------------------

MOTA.Book.rules["hunt.open"] = function(a, rec)
  local d = rec and rec.d or {}
  if not canRun(a) or not str(d.name, 40) or type(d.clues) ~= "table" then return false end
  if #d.clues < Hunt.MIN_CLUES or #d.clues > Hunt.MAX_CLUES then return false end
  for _, c in ipairs(d.clues) do
    if type(c) ~= "table" or type(c.x) ~= "number" or type(c.y) ~= "number" or type(c.inst) ~= "number"
      or not str(c.z, 60) or not str(c.r, Hunt.MAX_RIDDLE) then return false end
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
    -- Hunts from before 0.8.5 kept their spots hidden; they can't be played now.
    if r.k == "hunt.open" and type(d.clues) == "table" and #d.clues >= Hunt.MIN_CLUES and type(d.clues[1].x) == "number" then
      local H = { id = r.a .. "#" .. r.n, by = r.a, t = r.t, name = d.name, clues = d.clues,
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

-- The riddle of clue i, if this player may see it yet, and its zone: the first
-- for everyone, the next once the spot before it is found, all for the organiser.
function Hunt:Riddle(i, H)
  H = H or self:Current()
  local c = H and H.clues[i]
  if not c then return nil end
  if i == 1 or MOTA.Account:Same(MOTA.me, H.by) or self:Progress(MOTA.me, H) >= i - 1 or H.ended then
    return c.r, c.z
  end
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
  local clues = {}
  for i, c in ipairs(d.clues) do
    -- To a tenth of a yard: plenty, and short.
    clues[i] = { z = c.z, inst = c.inst, x = math.floor(c.x * 10 + 0.5) / 10, y = math.floor(c.y * 10 + 0.5) / 10, r = c.riddle }
  end
  local rec, err = MOTA.Book:Write("hunt.open", { name = name, clues = clues })
  if not rec then return nil, err end
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

-- Warmer and colder share one herald: a new one takes the place of the last
-- rather than waiting behind it.
local temp
local function herald(title, text)
  local Hd = MOTA.Herald
  if not Hd then return end
  if temp and Hd:IsShowing(temp) then
    temp.title, temp.text = title, text
    Hd:Update(temp)
    Hd:HideLater(5)
    return
  end
  if temp then Hd:Close(temp) end
  temp = { seal = "official", eyebrow = "The Treasure Hunt", title = title, text = text, stay = 5, noFanfare = true,
    button = { label = "Dismiss", style = "quiet" } }
  Hd:Announce(temp)
end

-- Looks where you stand. Returns "found", "warm", or nil.
function Hunt:Look()
  local H = self:Current()
  if self:Stage(H) ~= "running" or not MOTA.me or MOTA.Account:Same(MOTA.me, H.by) then return nil end
  local i = self:Progress(MOTA.me, H) + 1
  local c = H.clues[i]
  if not c then return nil end
  local inst, x, y = self:Where()
  if not x then return nil end
  local dist = self:Distance(c, inst, x, y)
  if dist and dist <= self.FOUND then return self:Found(H, i) end
  local warm = dist ~= nil and dist <= self.WARM
  -- Each time you come into the warm circle, warmer; each time you leave it, colder.
  if warm ~= self.warm then
    self.warm = warm
    if warm then
      herald("You're getting warmer", "Clue " .. i .. " is within 50 yards. Stand on the spot itself to find it.")
    else
      herald("You're getting colder", "You've moved away from clue " .. i .. ". Turn back the way you came.")
    end
    MOTA:Fire("HUNT_CHANGED")
  end
  return warm and "warm" or nil
end

-- Spot i is found: tell the guild, and the next riddle shows.
function Hunt:Found(H, i)
  self.warm = false
  if DoEmote then DoEmote("CHEER") end -- found it!
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
  cache = nil
  MOTA:Fire("HUNT_CHANGED")
end

-- Someone logging in while a hunt runs hears of it once a session: the hunt
-- may have begun while they were away, and records caught up on raise no herald.
local reminded
function Hunt:Remind()
  local H = self:Current()
  if reminded or self:Stage(H) ~= "running" or not MOTA.Herald or not MOTA.me then return end
  reminded = H.id
  startTicking()
  if MOTA.Account:Same(MOTA.me, H.by) then
    local n = #self:Hunters(H)
    MOTA:Print("Your hunt", H.name, "is running:", n, n == 1 and "hunter has" or "hunters have", "found a spot so far.")
    return
  end
  local found = self:Progress(MOTA.me, H)
  local text, zone = self:Riddle(found + 1, H)
  MOTA.Herald:Announce({ seal = "official", eyebrow = "The Treasure Hunt", title = H.name .. " is on",
    text = (found > 0 and ("You've found " .. found .. " of " .. #H.clues .. ". ") or (#H.clues .. " clues. First to stand on the last spot wins. "))
      .. "Clue " .. (found + 1) .. ", in " .. tostring(zone) .. (text and (": " .. text) or "."),
    button = { label = "Open", style = "blue", page = 8 } })
end

MOTA:Listen("GUILD_READY", function()
  changed()
  C_Timer.After(6, function()
    if Hunt:Stage() == "running" then startTicking() end
    local H = Hunt:Current()
    if H and Hunt:Stage(H) == "won" then record(H) end
  end)
  -- After the first catch-up, so a hunt set while away is known.
  C_Timer.After(25, function() Hunt:Remind() end)
end)
MOTA:Listen("CAUGHT_UP", function()
  changed()
  C_Timer.After(2, function() Hunt:Remind() end)
end)
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
    reminded = H.id
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
