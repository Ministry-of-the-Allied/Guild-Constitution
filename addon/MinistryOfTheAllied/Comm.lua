-- Ministry of the Allied: sending and receiving add-on messages.
-- Messages travel on the hidden guild channel (or by whisper), never in chat.
-- AceComm-3.0 splits long messages and joins them back together, and its
-- ChatThrottleLib paces sending so the game never throttles or disconnects
-- the player. Live news goes ahead of background traffic (ADDON_SPEC.md,
-- section 7.5).
--
-- Message format (protocol 2): fields joined by the "unit separator" byte,
--   <protocol> SEP <kind> SEP <field 1> SEP <field 2> ...
-- A record (RC) has one field: the record packed with the game's own
-- C_EncodingUtil (CBOR) and turned into text with Base64.
-- Kinds so far: HI hello, HR hello reply (Hello.lua), RC record (Book.lua),
-- PB limits-test probe (Probe.lua).

local _, MOTA = ...
local Comm = {}
MOTA.Comm = Comm

local SEP = "\031"
local MAX_LEN = 4000 -- a sanity limit; AceComm splits anything over 255 bytes
Comm.SEP = SEP
Comm.MAX_LEN = MAX_LEN

-- Register the prefix at load time, so messages can be received at once.
-- AceComm registers it again below; the game just reports a duplicate.
Comm.prefixResult = C_ChatInfo.RegisterAddonMessagePrefix(MOTA.PREFIX)

LibStub("AceComm-3.0"):Embed(Comm)

---------------------------------------------------------------------------
-- Packing
---------------------------------------------------------------------------

-- Strips control characters (our separator and the forbidden \0 among them).
function Comm:Clean(v)
  if v == nil then return "" end
  return (tostring(v):gsub("[%z\001-\031]", ""))
end

function Comm:Pack(kind, ...)
  local parts = { tostring(MOTA.PROTOCOL), kind }
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

-- A Lua table to channel-safe text and back, with the game's own packer.
-- Big batches (catch-up) are compressed too; a single small record isn't,
-- because compression makes it bigger.
local E = C_EncodingUtil

function Comm:Encode(value, compress)
  local packed = E.SerializeCBOR(value)
  if compress then packed = E.CompressString(packed) end
  return E.EncodeBase64(packed)
end

function Comm:Decode(text, compressed)
  local ok, value = pcall(function()
    local packed = E.DecodeBase64(text)
    if compressed then packed = E.DecompressString(packed) end
    return E.DeserializeCBOR(packed)
  end)
  if ok then return value end
end

function Comm:EncodeRecord(rec)
  return self:Pack("RC", self:Encode({ a = rec.a, n = rec.n, t = rec.t, k = rec.k, d = rec.d or {} }))
end

function Comm:DecodeRecord(f)
  local rec = f[1] and self:Decode(f[1])
  if type(rec) ~= "table" then return nil end
  if type(rec.a) ~= "string" or type(rec.k) ~= "string" or rec.a == "" or rec.k == "" then return nil end
  if type(rec.n) ~= "number" or type(rec.t) ~= "number" then return nil end
  if rec.n < 1 or rec.n ~= math.floor(rec.n) then return nil end
  if type(rec.d) ~= "table" then rec.d = {} end
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

-- Sends one message straight away, bypassing AceComm. Only the limits test
-- uses this, because it measures the game's own limits. Returns ok, result.
function Comm:RawSend(msg, channel, target)
  local r = C_ChatInfo.SendAddonMessage(MOTA.PREFIX, msg, channel, target)
  local ok
  if type(r) == "number" then ok = r == SUCCESS else ok = r ~= false end
  if ok then
    MOTA:Debug("out", channel, target or "", (msg:gsub(SEP, " | ")))
  end
  return ok, r
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- AceComm hands messages to ChatThrottleLib at once, and ChatThrottleLib
-- would drop one sent while the game has add-on messages locked (Midnight-era
-- clients lock them, for example during boss fights). So messages wait here
-- while locked, or while the limits test runs (Comm.paused).
local held = { live = {}, bulk = {} }
local inFlight = 0 -- handed to AceComm, not yet confirmed sent
local ticker

-- Live news uses its own ChatThrottleLib priority, so background catch-up
-- (BULK) never crowds it out.
local PRIORITY = { live = "ALERT", bulk = "BULK" }

function Comm:Waiting()
  return #held.live + #held.bulk + inFlight
end

local function locked()
  return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

-- AceComm calls this as each piece goes out: (item, bytes sent, total, sent?).
local function done(item, sent, total, didSend)
  if item.finished then return end -- a piece already failed; the rest don't count
  if didSend ~= false and sent < total then return end -- more pieces to come
  item.finished = true
  inFlight = inFlight - 1
  if didSend == false then
    MOTA.stats.failed = MOTA.stats.failed + 1
    MOTA:Debug("not sent", item.channel, item.target or "")
  else
    MOTA.stats.sent = MOTA.stats.sent + 1
    MOTA:Debug("out", item.channel, item.target or "", (item.msg:gsub(SEP, " | ")))
  end
end

local function hand(item, priority)
  inFlight = inFlight + 1
  Comm:SendCommMessage(MOTA.PREFIX, item.msg, item.channel, item.target, PRIORITY[priority], done, item)
end

local function pump()
  if not Comm.paused and not locked() then
    for _, priority in ipairs({ "live", "bulk" }) do
      local q = held[priority]
      while #q > 0 do hand(table.remove(q, 1), priority) end
    end
  end
  if #held.live + #held.bulk == 0 and ticker then
    ticker:Cancel()
    ticker = nil
  end
end

-- Hands over anything held, and keeps checking while something waits.
function Comm:Kick()
  pump()
  if not ticker and #held.live + #held.bulk > 0 then
    ticker = C_Timer.NewTicker(0.5, pump)
  end
end

-- priority is "live" (default) or "bulk".
function Comm:Send(msg, channel, target, priority)
  if #msg > MAX_LEN then
    MOTA.stats.failed = MOTA.stats.failed + 1
    MOTA:Debug("not sent, too long:", #msg, "bytes")
    return false
  end
  local q = held[priority or "live"]
  q[#q + 1] = { msg = msg, channel = channel, target = target }
  self:Kick()
  return true
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local kindHandlers = {}

-- fn(MOTA, sender, channel, fields, protocol)
function Comm:Handle(kind, fn)
  kindHandlers[kind] = fn
end

-- HI and HR always keep the version as their first field, whatever the
-- protocol, so an old copy can still read who is newer and ask to update.
local alwaysReadable = { HI = true, HR = true }

-- AceComm calls this with whole messages, already joined back together.
function Comm:OnComm(prefix, text, channel, sender)
  local self = MOTA
  if prefix ~= self.PREFIX then return end
  -- Midnight-era clients can hand add-ons hidden ("secret") values in some
  -- situations; those can't be read, so skip them.
  if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return end
  if not self.guild then self:CheckGuild() end
  if not self.guild then return end

  local own = self:IsMe(sender)
  sender = self:FullName(sender)
  local protocol, kind, fields = Comm:Unpack(text)
  if own or sender == self.me then
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
end

Comm:RegisterComm(MOTA.PREFIX, "OnComm")
