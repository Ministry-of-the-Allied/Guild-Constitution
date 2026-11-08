-- Ministry of the Allied: guild members without the add-on (Duncan, 2026-11-08).
-- The add-on is a requirement of the guild, so the Crown sees who hasn't got
-- it yet, newest to the guild first, to reach out to them.
--
-- Someone has the add-on if their copy has said hello to this one, or they've
-- written any record in the shared book. Every citizen's add-on writes one on
-- first use (its district placement, District.lua), and records reach every
-- copy, so this works even if the two never met online.
--
-- When each member was first seen on the roster is kept on this computer only
-- (MOTA.guild.firstSeen); nothing here is sent.

local _, MOTA = ...
local Outreach = {}
MOTA.Outreach = Outreach

function Outreach:HasAddon(name)
  if MOTA:IsMe(name) then return true end
  local g = MOTA.guild
  return g ~= nil and (g.peers[name] ~= nil or (g.records[name] ~= nil and next(g.records[name]) ~= nil))
end

-- { { name, since, online, days } }, newest to the guild first.
function Outreach:Missing()
  local out = {}
  local g = MOTA.guild
  if not g then return out end
  local seen = g.firstSeen or {}
  for name, r in pairs(MOTA.roster) do
    if not self:HasAddon(name) then
      out[#out + 1] = { name = name, since = seen[name], online = r.online, days = r.days }
    end
  end
  table.sort(out, function(a, b)
    if (a.since or 0) ~= (b.since or 0) then return (a.since or 0) > (b.since or 0) end
    return a.name < b.name
  end)
  return out
end

-- Notes when each roster member was first seen, so new joiners show first.
MOTA:Listen("ROSTER_UPDATED", function(self)
  local g = self.guild
  if not g then return end
  g.firstSeen = g.firstSeen or {}
  local now = GetServerTime()
  for name in pairs(self.roster) do
    if not g.firstSeen[name] then g.firstSeen[name] = now end
  end
end)

-- A line per member, for /mota missing.
function Outreach:Lines()
  local lines = {}
  for _, e in ipairs(self:Missing()) do
    local when = e.since and ("first seen " .. date("%d %b", e.since)) or "first seen before this list began"
    local where = e.online and MOTA:Color("leaf", "online now") or (e.days and (e.days == 0 and "online today" or ("last online " .. e.days .. (e.days == 1 and " day" or " days") .. " ago")) or "")
    lines[#lines + 1] = MOTA:Short(e.name) .. " · " .. when .. (where ~= "" and (" · " .. where) or "")
  end
  return lines
end

-- At login, the Crown hears how many are missing it.
MOTA:Listen("GUILD_READY", function(self)
  C_Timer.After(30, function()
    if not self.me or not self:IsCrown(self.me) then return end
    local n = #Outreach:Missing()
    if n > 0 then
      self:Print(n, n == 1 and "guild member doesn't" or "guild members don't", "have the add-on yet. /mota missing lists them, newest first.")
    end
  end)
end)
