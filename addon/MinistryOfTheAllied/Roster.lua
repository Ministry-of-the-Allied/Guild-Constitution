-- Ministry of the Allied: the guild roster.
-- Who is in the guild, their rank and whether they're online. The Crown is
-- whoever holds either Crown rank, "The King" or "The Crown"
-- (MOTA.CONST.CROWN_RANK_NAMES, ADDON_SPEC.md section 4), which only the Guild
-- Master can hand out.

local _, MOTA = ...

local roster = {} -- [Name] = { rank, rankIndex, level, class, online, days }
MOTA.roster = roster

-- Days since a member was last online, from the roster (nil if the game
-- doesn't say). The game gives years, months, days and hours.
local function lastOnlineDays(i)
  if not GetGuildRosterLastOnline then return nil end
  local y, m, d, h = GetGuildRosterLastOnline(i)
  if not y and not m and not d and not h then return nil end
  return (y or 0) * 365 + (m or 0) * 30 + (d or 0) + (h or 0) / 24
end

local function scan()
  wipe(roster)
  local total = GetNumGuildMembers()
  for i = 1, total do
    local name, rankName, rankIndex, level, _, _, _, _, isOnline, _, class = GetGuildRosterInfo(i)
    local full = MOTA:FullName(name) -- the name alone (Core.lua, MOTA:Bare)
    if full then
      roster[full] = {
        rank = rankName,
        rankIndex = rankIndex,
        level = level,
        class = class,
        online = isOnline and true or false,
        days = isOnline and 0 or lastOnlineDays(i),
      }
    end
  end
end

MOTA:On("GUILD_ROSTER_UPDATE", function(self)
  scan()
  self:CheckGuild()
  self:Fire("ROSTER_UPDATED")
end)

function MOTA:RequestRoster()
  if IsInGuild() then C_GuildInfo.GuildRoster() end
end

function MOTA:IsGuildMember(fullName)
  return roster[fullName] ~= nil
end

function MOTA:IsOnline(fullName)
  local r = roster[fullName]
  return r and r.online or false
end

function MOTA:RankOf(fullName)
  if fullName == self.me then
    local _, rankName = GetGuildInfo("player")
    return rankName
  end
  local r = roster[fullName]
  return r and r.rank
end

function MOTA:IsCrown(fullName)
  local rank = self:RankOf(fullName)
  return rank ~= nil and self.CONST.CROWN_RANK_NAMES[rank] == true
end

-- Everyone on either Crown rank that the roster shows.
function MOTA:CrownMembers()
  local list = {}
  for name, r in pairs(roster) do
    if r.rank and self.CONST.CROWN_RANK_NAMES[r.rank] then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

-- Active citizens: guild members online now or within ACTIVE_CITIZEN_DAYS
-- (ADDON_SPEC.md 8.4). The turnout of a ballot is counted against this.
-- A member the game gives no last-online time for counts as active.
function MOTA:IsActive(fullName)
  local r = roster[fullName]
  if not r then return false end
  return r.online or r.days == nil or r.days < self.CONST.ACTIVE_CITIZEN_DAYS
end

function MOTA:ActiveCitizens()
  local n = 0
  for name in pairs(roster) do
    if self:IsActive(name) then n = n + 1 end
  end
  return n
end
