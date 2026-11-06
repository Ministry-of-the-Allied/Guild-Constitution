-- Ministry of the Allied: sending and receiving add-on messages.
-- Messages travel on the hidden guild channel (or by whisper), never in chat.
-- Everything goes out through one queue that stays under the game's limits,
-- with live news ahead of background traffic (Core/Sync plan, section 3).
--
-- Message format (protocol 1): fields joined by the "unit separator" byte,
--   <protocol> SEP <kind> SEP <field 1> SEP <field 2> ...
-- Kinds so far: HI hello, HR hello reply (Hello.lua), RC record (Book.lua),
-- PB limits-test probe (Probe.lua).

local _, MotA = ...
local Comm = {}
MotA.Comm = Comm

local SEP = "\031"
local MAX_LEN = 255 -- bytes per message, the documented maximum (checked by /mota probe limits)
Comm.SEP = SEP
Comm.MAX_LEN = MAX_LEN

-- Register the prefix at load time, so messages can be received at once.
Comm.prefixResult = C_ChatInfo.RegisterAddonMessagePrefix(MotA.PREFIX)

---------------------------------------------------------------------------
-- Packing
---------------------------------------------------------------------------

-- Strips control characters (our separator and the forbidden \0 among them).
function Comm:Clean(v)
  if v == nil then return "" end
  return (tostring(v):gsub("[%z\001-\031]", ""))
end

function Comm:Pack(kind, ...)
  local parts = { tostring(MotA.PROTOCOL), kind }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = self:Clean((select(i, ...)))
  end
  return table.concat(parts, SEP)
end

-- Returns protocol, kind and a table of the remaining fields.
function Comm:Unpack(msg)
  local parts = { strsplit(SEP, msg) }
  local protocol = tonumber(parts[1])
  local kind = parts[2]
  local fields = {}
  for i = 3, #parts do fields[#fields + 1] = parts[i] end
  return protocol, kind, fields
end

-- A record's details are stored as key, value pairs. Each value carries a
-- one-letter type: n number, b true/false, s text.
function Comm:EncodeRecord(rec)
  local fields = { rec.a, rec.n, rec.t, rec.k }
  local keys = {}
  for k in pairs(rec.d or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = rec.d[k]
    fields[#fields + 1] = k
    if type(v) == "number" then
      fields[#fields + 1] = "n" .. v
    elseif type(v) == "boolean" then
      fields[#fields + 1] = v and "b1" or "b0"
    else
      fields[#fields + 1] = "s" .. tostring(v)
    end
  end
  return self:Pack("RC", unpack(fields))
end

function Comm:DecodeRecord(f)
  local rec = { a = f[1], n = tonumber(f[2]), t = tonumber(f[3]), k = f[4], d = {} }
  if not (rec.a and rec.n and rec.t and rec.k) or rec.a == "" or rec.k == "" then return nil end
  if rec.n < 1 or rec.n ~= math.floor(rec.n) then return nil end
  for i = 5, #f - 1, 2 do
    local key, raw = f[i], f[i + 1]
    local tag, body = raw:sub(1, 1), raw:sub(2)
    if tag == "n" then
      rec.d[key] = tonumber(body)
    elseif tag == "b" then
      rec.d[key] = body == "1"
    else
      rec.d[key] = body
    end
  end
  return rec
end

---------------------------------------------------------------------------
-- Result codes. Newer clients return a code from SendAddonMessage
-- (Enum.SendAddonMessageResult), older ones true or false.
---------------------------------------------------------------------------

function Comm:EnumName(enum, value)
  if type(value) == "boolean" then return value and "ok" or "refused" end
  if value == nil then return "no answer" end
  if enum then
    for name, v in pairs(enum) do
      if v == value then return name end
    end
  end
  return tostring(value)
end

function Comm:ResultName(r)
  return self:EnumName(Enum.SendAddonMessageResult, r)
end

local SUCCESS = Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0

local function isThrottle(r)
  local E = Enum.SendAddonMessageResult
  return E and (r == E.AddonMessageThrottle or r == E.ChannelThrottle)
end

-- Sends straight away, without the queue. Returns ok, result code.
function Comm:RawSend(msg, channel, target)
  local r = C_ChatInfo.SendAddonMessage(MotA.PREFIX, msg, channel, target)
  local ok
  if type(r) == "number" then ok = r == SUCCESS else ok = r ~= false end
  if ok then
    MotA:Debug("out", channel, target or "", (msg:gsub(SEP, " | ")))
  end
  return ok, r
end

---------------------------------------------------------------------------
-- The send queue
---------------------------------------------------------------------------

-- Kept well under the game's reported budget (a burst of about 10, then about
-- one a second) until /mota probe limits has measured Forever's real limits.
local MAX_TOKENS = 5
local REFILL_PER_SECOND = 1
local MAX_TRIES = 5

local queues = { live = {}, bulk = {} }
local tokens, lastRefill = MAX_TOKENS, GetTime()
local ticker

function Comm:Waiting()
  return #queues.live + #queues.bulk
end

local function refill()
  local now = GetTime()
  tokens = math.min(MAX_TOKENS, tokens + (now - lastRefill) * REFILL_PER_SECOND)
  lastRefill = now
end

local function pump()
  refill()
  if Comm.paused then return end
  -- Midnight-era clients can lock add-on messages (for example during boss
  -- fights). If so, wait; the queue keeps everything until it's allowed.
  if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
  while tokens >= 1 do
    local q = (#queues.live > 0 and queues.live) or (#queues.bulk > 0 and queues.bulk)
    if not q then break end
    local item = q[1]
    local ok, r = Comm:RawSend(item.msg, item.channel, item.target)
    if ok then
      table.remove(q, 1)
      tokens = tokens - 1
      MotA.stats.sent = MotA.stats.sent + 1
    else
      -- Throttled: just wait. Any other refusal counts as a failed try.
      if not isThrottle(r) then item.tries = item.tries + 1 end
      if item.tries >= MAX_TRIES then
        table.remove(q, 1)
        MotA.stats.failed = MotA.stats.failed + 1
        MotA:Debug("gave up sending", item.channel, Comm:ResultName(r))
      end
      tokens = 0 -- back off until the next refill
      break
    end
  end
  if Comm:Waiting() == 0 and ticker then
    ticker:Cancel()
    ticker = nil
  end
end

-- Starts the queue ticking if anything is waiting.
function Comm:Kick()
  if not ticker and self:Waiting() > 0 then
    ticker = C_Timer.NewTicker(0.25, pump)
  end
  pump()
end

-- priority is "live" (default) or "bulk".
function Comm:Send(msg, channel, target, priority)
  if #msg > MAX_LEN then
    MotA.stats.failed = MotA.stats.failed + 1
    MotA:Debug("not sent, too long:", #msg, "bytes")
    return false
  end
  local q = queues[priority or "live"]
  q[#q + 1] = { msg = msg, channel = channel, target = target, tries = 0 }
  self:Kick()
  return true
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local kindHandlers = {}

-- fn(MotA, sender, channel, fields, protocol)
function Comm:Handle(kind, fn)
  kindHandlers[kind] = fn
end

-- HI and HR always keep the version as their first field, whatever the
-- protocol, so an old copy can still read who is newer and ask to update.
local alwaysReadable = { HI = true, HR = true }

MotA:On("CHAT_MSG_ADDON", function(self, _, prefix, text, channel, sender)
  if prefix ~= self.PREFIX then return end
  -- Midnight-era clients can hand add-ons hidden ("secret") values in some
  -- situations; those can't be read, so skip them.
  if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return end
  if not self.guild then self:CheckGuild() end
  if not self.guild then return end

  sender = self:FullName(sender)
  local protocol, kind, fields = Comm:Unpack(text)
  if sender == self.me then
    -- Our own guild messages come back to us. Only the limits test wants them.
    if kind == "PB" and kindHandlers.PB then kindHandlers.PB(self, sender, channel, fields, protocol) end
    return
  end
  self.stats.received = self.stats.received + 1
  self:Debug("in", channel, sender, (text:gsub(SEP, " | ")))

  if not protocol or not kind or not kindHandlers[kind] then
    self.stats.ignored = self.stats.ignored + 1
    return
  end
  if channel ~= "GUILD" and channel ~= "WHISPER" then return end
  -- Whispers are only taken from guild members.
  if channel == "WHISPER" and not self:IsGuildMember(sender) then
    self.stats.ignored = self.stats.ignored + 1
    return
  end
  if protocol > self.PROTOCOL then
    self.outdated = true
    if not alwaysReadable[kind] then
      self.stats.ignored = self.stats.ignored + 1
      return
    end
  end
  kindHandlers[kind](self, sender, channel, fields, protocol)
end)
