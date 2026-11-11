-- Ministry of the Allied: guild members on the maps (ADDON_SPEC.md, section 10.17).
-- A member who runs the add-on and has chosen to share tells the guild where
-- they stand, and everyone else's add-on draws them as a class-coloured dot on
-- the world map and the minimap (UI/Dots.lua draws; this file keeps the facts).
--
-- Sharing is off until the member says yes (the one-time question and the
-- Settings page, UI/Dots.lua). Nothing is ever sent from an instance, a raid or
-- a battleground, and only on the hidden guild channel.
--
-- Messages (kinds on the MOTA prefix, protocol 2: an older copy simply
-- ignores a kind it doesn't know):
--   LP map x y class level   where I am (a map ID, x and y on it from 0 to 1)
--   LS                       I stopped sharing: drop my dot
--   LQ                       I just came online: those who share, say where you are
-- Moving: a message every 10 s; standing still: every 60 s. A dot with no word
-- for 150 s goes. A newer message replaces an older one still waiting to go.

local _, MOTA = ...
local Dots = {}
MOTA.Dots = Dots

local TICK = 2             -- seconds between looks at where I am
local MOVING_EVERY = 10    -- a message this often while moving
local STILL_EVERY = 60     -- ... and this often standing still
local MOVED = 0.002        -- a move this small on a map isn't a move
local GONE_AFTER = 150     -- seconds of silence before a dot goes
local ASK_DELAY = 30       -- seconds after the guild is known before asking who is out there (the hello and the catch-up go first)
local REPLY_MIN, REPLY_MAX = 1, 5 -- a sharer answers a question after this long, spread out so a big guild doesn't flood
local ASK_GAP = 30         -- a question from the same person is answered at most this often
local MAX_DOTS = 500       -- a sanity limit on the dots kept

Dots.TICK, Dots.GONE_AFTER = TICK, GONE_AFTER
Dots.live = {}  -- name -> { map, x, y, class, level, at }: those sharing, as last heard
Dots.sharing = false -- a place has been sent since sharing began (so a stop must be sent when it ends)
Dots.last = { at = -math.huge } -- my place as last sent: map, x, y, at
Dots.pending = nil -- the newest message waiting to go (it replaces an older one)

local function secret(v)
  return issecretvalue and issecretvalue(v) or false
end

---------------------------------------------------------------------------
-- The settings
---------------------------------------------------------------------------

function Dots:Sharing()
  return MOTA.db ~= nil and MOTA.db.settings.dotsShare and true or false
end

function Dots:Showing()
  return MOTA.db ~= nil and MOTA.db.settings.dotsShow and true or false
end

---------------------------------------------------------------------------
-- Where I am
---------------------------------------------------------------------------

-- map, x, y: nil in an instance, a raid or a battleground, or when the game
-- won't say (some maps give no position, and (0, 0) means "not known").
function Dots:Here()
  if IsInInstance() then return nil end
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or secret(map) or type(map) ~= "number" or map <= 0 then return nil end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not ok2 or not pos then return nil end
  local ok3, x, y = pcall(pos.GetXY, pos)
  if not ok3 or secret(x) or secret(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
  if x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then return nil end
  return map, x, y
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function locked()
  return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

-- Holds the newest message; it goes now unless the game has messages locked.
function Dots:Queue(msg)
  self.pending = msg
  self:Flush()
end

function Dots:Flush()
  if not self.pending or locked() then return end
  if not MOTA.guild then return end
  local msg = self.pending
  self.pending = nil
  MOTA.Comm:Send(msg, "GUILD", nil, "bulk")
end

function Dots:Stop()
  if self.sharing then
    self.sharing = false
    self:Queue(MOTA.Comm:Pack("LS"))
  end
  self.last.at = -math.huge
end

-- One look: send my place if it's due. force sends at once.
function Dots:Tick(force)
  self:Flush()
  self:Sweep()
  if not self:Sharing() or not MOTA.guild then return self:Stop() end
  local map, x, y = self:Here()
  if not map then return self:Stop() end
  local last = self.last
  local moved = map ~= last.map or math.abs(x - (last.x or 0)) > MOVED or math.abs(y - (last.y or 0)) > MOVED
  if not force and GetTime() - last.at < (moved and MOVING_EVERY or STILL_EVERY) then return end
  local _, class = UnitClass("player")
  if secret(class) then return end
  last.map, last.x, last.y, last.at = map, x, y, GetTime()
  self.sharing = true
  self:Queue(MOTA.Comm:Pack("LP", map, ("%.4f"):format(x), ("%.4f"):format(y),
    type(class) == "string" and class or "", tonumber(UnitLevel("player")) or 0))
end

-- A switch was changed in Settings, or the question was answered.
function Dots:Changed()
  if self:Sharing() then
    self:Tick(true)
  else
    self:Stop()
  end
  if self:Showing() then self:Ask() end
  MOTA:Fire("DOTS_CHANGED") -- for the OpenMap step-aside (UI/MapCompat.lua)
  MOTA:Fire("DOTS_UPDATED")
end

-- Entering an instance, a raid or a battleground: stop at once, not at the next look.
function Dots:Zoned()
  if self.sharing and IsInInstance() then self:Stop() end
end

-- Asks who is out there (once a session, shortly after login).
function Dots:Ask()
  if self.asked or not MOTA.guild then return end
  self.asked = true
  self:Queue(MOTA.Comm:Pack("LQ"))
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function knownMap(map)
  if not (C_Map and C_Map.GetMapInfo) then return true end
  local ok, info = pcall(C_Map.GetMapInfo, map)
  return ok and info ~= nil
end

local function knownClass(class)
  if type(class) ~= "string" or not class:match("^%u+$") or #class > 20 then return false end
  return RAID_CLASS_COLORS == nil or RAID_CLASS_COLORS[class] ~= nil
end

-- A place heard from name; false when it isn't a place worth keeping.
function Dots:Heard(name, f)
  local map, x, y = tonumber(f[1]), tonumber(f[2]), tonumber(f[3])
  if not (map and x and y) or map ~= math.floor(map) or map <= 0 then return false end
  if x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then return false end
  if not knownClass(f[4]) or not knownMap(map) then return false end
  local level = tonumber(f[5]) or 0
  if level < 0 or level > 255 then level = 0 end
  if not self.live[name] then
    local n = 0
    for _ in pairs(self.live) do n = n + 1 end
    if n >= MAX_DOTS then return false end
  end
  self.live[name] = { map = map, x = x, y = y, class = f[4], level = math.floor(level), at = GetTime() }
  MOTA:Fire("DOTS_UPDATED")
  return true
end

function Dots:Forget(name)
  if self.live[name] then
    self.live[name] = nil
    MOTA:Fire("DOTS_UPDATED")
  end
end

-- Drops a dot that has been silent too long.
function Dots:Sweep()
  local now, gone = GetTime(), false
  for name, p in pairs(self.live) do
    if now - p.at > GONE_AFTER then
      self.live[name] = nil
      gone = true
    end
  end
  if gone then MOTA:Fire("DOTS_UPDATED") end
end

-- The dots to draw: those with the switch on, not in my group (the game draws
-- those itself). Sorted by name so a redraw never shuffles them.
function Dots:List()
  local out = {}
  if not self:Showing() then return out end
  for name, p in pairs(self.live) do
    if not (UnitInParty and UnitInParty(name)) and not (UnitInRaid and UnitInRaid(name)) then
      out[#out + 1] = { name = name, p = p }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

MOTA.Comm:Handle("LP", function(self, sender, channel, f)
  if channel ~= "GUILD" then return end
  Dots:Heard(sender, f)
end)

MOTA.Comm:Handle("LS", function(self, sender, channel)
  if channel ~= "GUILD" then return end
  Dots:Forget(sender)
end)

-- Someone just came online and asks who is out there: answer with my place,
-- after a short random wait, if I share (and not twice for the same person in a row).
local askedAt = {}
MOTA.Comm:Handle("LQ", function(self, sender, channel)
  if channel ~= "GUILD" or not Dots:Sharing() then return end
  local now = GetTime()
  if askedAt[sender] and now - askedAt[sender] < ASK_GAP then return end
  askedAt[sender] = now
  if Dots.replying then return end
  Dots.replying = true
  C_Timer.After(REPLY_MIN + math.random() * (REPLY_MAX - REPLY_MIN), function()
    Dots.replying = false
    if Dots:Sharing() then Dots:Tick(true) end
  end)
end)

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------

MOTA:On("PLAYER_LOGIN", function()
  C_Timer.NewTicker(TICK, function() Dots:Tick() end)
end)

MOTA:On("PLAYER_ENTERING_WORLD", function() Dots:Zoned() end)
MOTA:On("ZONE_CHANGED_NEW_AREA", function() Dots:Zoned() end)

-- A message held back by a lockdown goes as soon as the game allows.
MOTA:On("PLAYER_REGEN_ENABLED", function() Dots:Flush() end)

MOTA:Listen("GUILD_READY", function()
  C_Timer.After(ASK_DELAY, function()
    if Dots:Showing() then Dots:Ask() end
    if Dots:Sharing() then Dots:Tick(true) end
  end)
end)
