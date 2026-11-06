-- Ministry of the Allied: the guild roster.
-- Who is in the guild, their rank and whether they're online. The Crown is
-- whoever holds either Crown rank, "The King" or "The Crown"
-- (MOTA.CONST.CROWN_RANK_NAMES, ADDON_SPEC.md section 4), which only the Guild
-- Master can hand out.

local _, MOTA = ...

local roster = {} -- [Name-Realm] = { rank, rankIndex, level, class, online }
MOTA.roster = roster

local function scan()
  wipe(roster)
  local total = GetNumGuildMembers()
  local myGUID = UnitGUID("player")
  for i = 1, total do
    local name, rankName, rankIndex, level, _, _, _, _, isOnline, _, class = GetGuildRosterInfo(i)
    local guid = select(17, GetGuildRosterInfo(i))
    if guid and guid == myGUID and name and name:find("-", 1, true) then MOTA:LearnMe(name) end
    local full = MOTA:FullName(name)
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
