-- Ministry of the Allied: the guild roster.
-- Who is in the guild, their rank and whether they're online. The Crown is
-- whoever holds the guild rank named "The Crown" (ADDON_SPEC.md, section 4),
-- which only the Guild Master can hand out.

local _, MotA = ...

local roster = {} -- [Name-Realm] = { rank, rankIndex, level, class, online }
MotA.roster = roster

local function scan()
  wipe(roster)
  local total = GetNumGuildMembers()
  for i = 1, total do
    local name, rankName, rankIndex, level, _, _, _, _, isOnline, _, class = GetGuildRosterInfo(i)
    local full = MotA:FullName(name)
    if full then
      roster[full] = {
        rank = rankName,
        rankIndex = rankIndex,
        level = level,
        class = class,
        online = isOnline and true or false,
      }
    end
  end
end

MotA:On("GUILD_ROSTER_UPDATE", function(self)
  scan()
  self:CheckGuild()
  self:Fire("ROSTER_UPDATED")
end)

function MotA:RequestRoster()
  if IsInGuild() then C_GuildInfo.GuildRoster() end
end

function MotA:IsGuildMember(fullName)
  return roster[fullName] ~= nil
end

function MotA:IsOnline(fullName)
  local r = roster[fullName]
  return r and r.online or false
end

function MotA:RankOf(fullName)
  if fullName == self.me then
    local _, rankName = GetGuildInfo("player")
    return rankName
  end
  local r = roster[fullName]
  return r and r.rank
end

function MotA:IsCrown(fullName)
  return self:RankOf(fullName) == self.CROWN_RANK
end

-- Everyone on the Crown rank that the roster shows.
function MotA:CrownMembers()
  local list = {}
  for name, r in pairs(roster) do
    if r.rank == self.CROWN_RANK then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end
