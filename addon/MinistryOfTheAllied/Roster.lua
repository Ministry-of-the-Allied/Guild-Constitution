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
  local myGUID = UnitGUID("player")
  for i = 1, total do
    local name, rankName, rankIndex, level, _, _, _, _, isOnline, _, class = GetGuildRosterInfo(i)
    local guid = select(17, GetGuildRosterInfo(i))
    if guid and guid == myGUID then MOTA:LearnMe(name) end
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

-- Who is online, by office (the minimap seal's tooltip, UI/OnlineTip.lua).
-- Returns the number online and the sections, highest office first, empty
-- ones left out; Citizens (every other rank) last. A section is
-- { title, people = { { name, class, main }, ... } }, names in order.
-- main is the main of an alt, once alt links exist (spec 10.1); until then nil.
function MOTA:OnlineSections()
  local byRank, sections = {}, {}
  for i, office in ipairs(self.CONST.OFFICES) do
    sections[i] = { title = office.title, people = {} }
    for rank in pairs(office.ranks) do byRank[rank] = sections[i] end
  end
  local citizens = { title = self.CONST.CITIZENS_TITLE, people = {} }
  sections[#sections + 1] = citizens
  local count = 0
  for name, r in pairs(roster) do
    if r.online then
      count = count + 1
      local into = byRank[r.rank] or citizens
      into.people[#into.people + 1] = { name = name, class = r.class, main = self.MainOf and self:MainOf(name) or nil }
    end
  end
  local out = {}
  for _, s in ipairs(sections) do
    if #s.people > 0 then
      table.sort(s.people, function(a, b) return a.name < b.name end)
      out[#out + 1] = s
    end
  end
  return count, out
end

-- A class's colour as r, g, b (the game's own, or the table in Data.lua).
function MOTA:ClassColor(class)
  local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return self:RGB(self.CONST.CLASS_COLORS[class] or "E5CF92")
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
