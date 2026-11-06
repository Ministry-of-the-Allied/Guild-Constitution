-- Ministry of the Allied: the guild handshake.
-- On login each copy of the add-on says hello on the hidden guild channel, and
-- everyone who hears it answers by whisper. Both carry the add-on version, so
-- an out-of-date copy can be told to update (Core/Sync plan, section 7).
--
-- The answer also says the highest record number the answerer holds from the
-- newcomer. If this computer lost records in a crash, the next record it writes
-- still gets a fresh number instead of reusing one the guild already has.
--
--   HI <version> <records held>     on GUILD, at login and after /reload
--   HR <version> <your top number>  by WHISPER, back to the one who said hello

local _, MotA = ...
local Hello = {}
MotA.Hello = Hello

Hello.heard = {} -- names heard from this session

local HELLO_DELAY = 5 -- seconds after login, so the guild channel is ready

function Hello:Send()
  if not MotA.guild then return end
  local total = MotA.Book:Count()
  MotA.Comm:Send(MotA.Comm:Pack("HI", MotA.VERSION, total), "GUILD")
  self.sentAt = GetServerTime()
end

function Hello:SeePeer(name, version, protocol, count)
  local p = MotA.guild.peers[name] or {}
  MotA.guild.peers[name] = p
  p.v = version
  p.p = protocol
  p.seen = GetServerTime()
  if count then p.c = count end
  self.heard[name] = true
  -- Anyone whose add-on just spoke is online, even if our copy of the roster
  -- hasn't caught up yet; ask the server for a fresh one too.
  local r = MotA.roster[name]
  if r then r.online = true end
  MotA:RequestRoster()

  local newer = (protocol or 0) > MotA.PROTOCOL or MotA:CompareVersions(version, MotA.VERSION) > 0
  if newer and not self.warned then
    self.warned = true
    MotA:Print(MotA:Color("crimson", "A newer version of the Ministry add-on is in use (" .. tostring(version) .. "). Please update."))
  end
end

MotA.Comm:Handle("HI", function(self, sender, channel, f, protocol)
  if channel ~= "GUILD" then return end
  Hello:SeePeer(sender, f[1], protocol, tonumber(f[2]))
  -- Wait a moment at random, so a full guild doesn't all answer in the same instant.
  C_Timer.After(0.5 + math.random() * 2.5, function()
    if not self.guild then return end
    self.Comm:Send(self.Comm:Pack("HR", self.VERSION, self.Book:Top(sender)), "WHISPER", sender)
  end)
end)

MotA.Comm:Handle("HR", function(self, sender, channel, f, protocol)
  if channel ~= "WHISPER" then return end
  Hello:SeePeer(sender, f[1], protocol)
  self.Book:Reserve(self.me, tonumber(f[2]))
end)

MotA:Listen("GUILD_READY", function(self)
  C_Timer.After(HELLO_DELAY, function() Hello:Send() end)
end)

-- Everyone the add-on knows about, newest first: { name, peer, online }.
function Hello:List()
  local list = {}
  if not MotA.guild then return list end
  for name, p in pairs(MotA.guild.peers) do
    local online = (self.heard[name] and MotA:IsOnline(name)) and true or false
    list[#list + 1] = { name = name, peer = p, online = online }
  end
  table.sort(list, function(x, y)
    if x.online ~= y.online then return x.online end
    return (x.peer.seen or 0) > (y.peer.seen or 0)
  end)
  return list
end

function Hello:OnlineCount()
  local n = 0
  for _, entry in ipairs(self:List()) do
    if entry.online then n = n + 1 end
  end
  return n
end
