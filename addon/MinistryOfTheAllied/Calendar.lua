-- Ministry of the Allied: the calendar (decided with Duncan, 14 Nov 2026).
--
-- Everything dated in the life of the realm, for the Calendar view on the Throne Room
-- (UI/CalendarPage.lua), and the bridge to the game's own guild calendar:
--
--   Election stages  the leadership contests (opening, voting, results), the campaign,
--                    polling day and the polls closing 2 hours later (Charter 3.3, 3.6)
--   Term dates       the Prime Minister taking office, the 48 hours to name the Cabinet,
--                    the term's end (Charter 2.3)
--   Past elections   every declared result, from the record book
--   Guild events     what the guild already has in the game's calendar (raids and the like)
--
-- The Crown can post the coming election dates to the game's guild calendar as guild
-- announcements, so players see them without opening the add-on. Nothing new is written to
-- the record book: the dates are worked out from election.date and ballot.result
-- (Contest.lua, Elect.lua, Ballot.lua). What has been posted is kept in the guild's saved
-- data (guild.calPosted), and a date whose title is already in the game's calendar is not
-- posted twice.
--
--   Calendar:Events(from, to)   { t, key, title, text, hex, src, post } sorted by time;
--                               src "mota" | "past" | "wow"
--   Calendar:ForDay(t)          that local day's events
--   Calendar:ToPost()           the coming dates the Crown hasn't posted yet
--   Calendar:CanPost()          true, or nil and why not
--   Calendar:PostAll()          posts them one after another
--   Calendar:LoadMonth(y, m)    asks the game for that month's guild events

local _, MOTA = ...
local Calendar = {}
MOTA.Calendar = Calendar

local DAY, HOUR = 86400, 3600
local POLL_HOURS = 2 -- Charter 3.3: the polls stay open 2 hours
local TAG = "[MOTA] "  -- the start of every title the add-on posts to the game's calendar

Calendar.HEX = {
  contest = "7A5719", -- gold: the leadership contests
  campaign = "1B3570", -- blue: the campaign
  poll = "8B2A1E",    -- red: polling day
  term = "2E5E3A",    -- green: the government's term
  past = "5E4B33",    -- brown: what's done
  wow = "5A3D7A",     -- purple: the guild's own events
}
local HEX = Calendar.HEX

---------------------------------------------------------------------------
-- Realm time
---------------------------------------------------------------------------

-- The game's calendar is in realm time; the add-on's dates are server timestamps shown in
-- local time. The difference, to the quarter hour (0 when the game doesn't say).
function Calendar:RealmShift()
  local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
  if not now or not now.year then return 0 end
  local realm = time({ year = now.year, month = now.month, day = now.monthDay, hour = now.hour, min = now.minute })
  local q = 900
  return math.floor((realm - time()) / q + 0.5) * q
end

-- { year, month, day, hour, min } in realm time for a timestamp.
function Calendar:RealmDate(t)
  return date("*t", t + self:RealmShift())
end

---------------------------------------------------------------------------
-- The add-on's own dates
---------------------------------------------------------------------------

local function add(list, t, key, title, text, hex, src, post)
  if type(t) ~= "number" then return end
  list[#list + 1] = { t = t, key = key, title = title, text = text or "", hex = hex, src = src or "mota", post = post }
end

local function partyName(p)
  if p == "sh" then return "the Silverhand" end
  if p == "ex" then return "the Azeroth Exchange" end
  return "a party"
end

-- The election being prepared or under way, and the government's term.
function Calendar:ElectionEvents()
  local list = {}
  local Contest, Elect = MOTA.Contest, MOTA.Elect
  if not Contest or not Elect then return list end
  local gov = Elect:Government()
  local cur = Contest:Current()

  if gov then
    local who = MOTA:Short(gov.name or "") or ""
    add(list, gov.t, "term.start." .. gov.t, "Prime Minister takes office", who ~= "" and (who .. " forms the government.") or nil, HEX.term, "mota")
    add(list, gov.t + Elect.NAME_WINDOW, "term.bench." .. gov.t, "Cabinet named by now",
      "The 48 hours to name the Cabinet and the shadow cabinet end.", HEX.term, "mota")
    add(list, gov.ends, "term.end." .. gov.ends, "The term ends",
      "Three calendar months from the Prime Minister taking office.", HEX.term, "mota", true)
  end

  if cur and Elect:Pending() then
    local poll = Contest:PollAt() or cur.at
    local name = cur.kind == "snap" and "Snap Election" or "General Election"
    if cur.kind ~= "snap" then
      local open = cur.openedAt or (cur.at - 28 * DAY)
      add(list, open, "contest.open." .. cur.at, "Leadership contests open",
        "Each party chooses its candidate for Prime Minister. Members stand for 4 days.", HEX.contest, "mota", true)
      add(list, open + 4 * DAY, "contest.vote." .. cur.at, "Leadership voting opens",
        "Party members vote for their leader over 7 days.", HEX.contest, "mota")
      add(list, open + 11 * DAY, "contest.count." .. cur.at, "Leadership results",
        "Voting in the leadership contests ends and the results are counted.", HEX.contest, "mota")
      if cur.emergency then
        add(list, cur.emergency.t, "contest.emergency." .. cur.at, "Emergency contest",
          partyName(cur.emergency.p):gsub("^%l", string.upper) .. " has no leader. Polling day moves back 14 days.", HEX.contest, "mota")
      end
    else
      add(list, cur.t, "snap.called." .. cur.at, "Snap Election called", "A 14-day campaign, with no leadership contests.", HEX.campaign, "mota")
    end
    add(list, poll - 14 * DAY, "campaign." .. cur.at, "The campaign begins",
      "Two weeks for the candidates to make their case.", HEX.campaign, "mota", cur.kind ~= "snap")
    add(list, poll, "poll." .. cur.at, "Polling day: " .. name,
      "The polls are open for " .. POLL_HOURS .. " hours. Vote in the Ballot Hall.", HEX.poll, "mota", true)
    add(list, poll + POLL_HOURS * HOUR, "poll.close." .. cur.at, "The polls close",
      "The Crown counts the ballots and declares the result.", HEX.poll, "mota")
  end
  return list
end

-- Every declared election result.
function Calendar:PastEvents()
  local list = {}
  local Ballot = MOTA.Ballot
  if not Ballot or not Ballot.Results then return list end
  for _, b in ipairs(Ballot:Results()) do
    local r = b.result or {}
    local kind = Ballot.KINDS[r.kind] or r.name or "Election"
    local text
    local c = type(r.cands) == "table" and r.w and r.cands[r.w]
    if c and c.n then
      text = c.n .. (c.p and (" of " .. partyName(c.p)) or "") .. " won"
      if type(r.votes) == "table" and r.votes[r.w] and r.total then text = text .. ", " .. r.votes[r.w] .. " of " .. r.total .. " votes" end
      text = text .. "."
    elseif r.tie then
      text = "A tie: a run-off followed."
    end
    add(list, b.resultT, "past." .. b.id, (r.name and r.name ~= "" and r.name or kind) .. ": result", text, HEX.past, "past")
  end
  return list
end

---------------------------------------------------------------------------
-- The game's guild calendar
---------------------------------------------------------------------------

local GUILD_TYPES = { GUILD_EVENT = true, GUILD_ANNOUNCEMENT = true }
local wowMonths = {}   -- "2026-11" -> { events }, filled when the game answers
local loaded           -- the month last asked for, "2026-11"

function Calendar:HasGameCalendar()
  return C_Calendar ~= nil and C_Calendar.GetNumDayEvents ~= nil and C_Calendar.SetAbsMonth ~= nil
end

local function monthKey(y, m) return ("%04d-%02d"):format(y, m) end

-- Reads the month the game's calendar is set to into wowMonths.
local function readMonth(y, m)
  local info = C_Calendar.GetMonthInfo and C_Calendar.GetMonthInfo(0)
  if not info or info.month ~= m or info.year ~= y then return end
  local shift = Calendar:RealmShift()
  local out = {}
  for day = 1, info.numDays or 31 do
    for i = 1, C_Calendar.GetNumDayEvents(0, day) or 0 do
      local e = C_Calendar.GetDayEvent(0, day, i)
      local seq = e and e.sequenceType
      if e and GUILD_TYPES[e.calendarType] and (seq == nil or seq == "" or seq == "START") then
        local s = e.startTime or {}
        local t = time({ year = s.year or y, month = s.month or m, day = s.monthDay or day, hour = s.hour or 0, min = s.minute or 0 }) - shift
        local mine = e.title and e.title:sub(1, #TAG) == TAG
        out[#out + 1] = { t = t, key = "wow." .. day .. "." .. i, title = e.title or "Guild event",
          text = e.calendarType == "GUILD_ANNOUNCEMENT" and "Guild announcement" or "Guild event",
          hex = HEX.wow, src = "wow", mine = mine }
      end
    end
  end
  wowMonths[monthKey(y, m)] = out
  return true
end

-- Asks the game for a month's guild events. The page redraws when they arrive (CALENDAR_CHANGED).
-- Leaves the game's own calendar window alone while it's open.
function Calendar:LoadMonth(y, m)
  if not self:HasGameCalendar() then return end
  if CalendarFrame and CalendarFrame:IsShown() then return end
  loaded = monthKey(y, m)
  if C_Calendar.OpenCalendar and not self.opened then
    self.opened = true
    C_Calendar.OpenCalendar()
  end
  C_Calendar.SetAbsMonth(m, y)
  if readMonth(y, m) then MOTA:Fire("CALENDAR_CHANGED") end
end

function Calendar:GameEvents(y, m)
  return wowMonths[monthKey(y, m)] or {}
end

---------------------------------------------------------------------------
-- All of it
---------------------------------------------------------------------------

local function settings()
  return (MOTA.db and MOTA.db.settings) or {}
end

-- Everything between two timestamps, oldest first.
function Calendar:Events(from, to)
  local out = {}
  local function take(list)
    for _, e in ipairs(list) do
      if e.t >= from and e.t < to then out[#out + 1] = e end
    end
  end
  take(self:ElectionEvents())
  take(self:PastEvents())
  if settings().calendarGuildEvents ~= false then
    local a, b = date("*t", from), date("*t", to - 1)
    local y, m = a.year, a.month
    while y < b.year or (y == b.year and m <= b.month) do
      local list = {}
      for _, e in ipairs(self:GameEvents(y, m)) do
        if not e.mine then list[#list + 1] = e end -- the add-on's own posts are shown as the add-on's
      end
      take(list)
      m = m + 1
      if m > 12 then m, y = 1, y + 1 end
    end
  end
  table.sort(out, function(x, y) if x.t ~= y.t then return x.t < y.t end return x.key < y.key end)
  return out
end

function Calendar:DayStart(t)
  local c = date("*t", t)
  return time({ year = c.year, month = c.month, day = c.day, hour = 0 })
end

function Calendar:ForDay(t)
  local s = self:DayStart(t)
  local e = time({ year = date("*t", s).year, month = date("*t", s).month, day = date("*t", s).day + 1, hour = 0 })
  return self:Events(s, e)
end

-- The next thing coming, from now.
function Calendar:Next()
  local now = GetServerTime()
  local best
  for _, e in ipairs(self:ElectionEvents()) do
    if e.t > now and (not best or e.t < best.t) then best = e end
  end
  return best
end

---------------------------------------------------------------------------
-- Posting to the game's calendar (the Crown)
---------------------------------------------------------------------------

local function posted()
  local g = MOTA.guild
  if not g then return {} end
  g.calPosted = g.calPosted or {}
  return g.calPosted
end

function Calendar:Title(e) return TAG .. e.title end

-- Is a title already in the game's calendar (in a month we've read)?
local function inGame(title)
  for _, list in pairs(wowMonths) do
    for _, w in ipairs(list) do
      if w.title == title then return true end
    end
  end
end

function Calendar:ToPost()
  local now = GetServerTime()
  local out, done = {}, posted()
  for _, e in ipairs(self:ElectionEvents()) do
    if e.post and e.t > now + HOUR and not done[e.key] and not inGame(self:Title(e)) then out[#out + 1] = e end
  end
  table.sort(out, function(x, y) return x.t < y.t end)
  return out
end

function Calendar:CanPost()
  if not MOTA.me or not MOTA:IsCrown(MOTA.me) then return nil, "Only the Crown posts to the guild calendar." end
  if not self:HasGameCalendar() or not C_Calendar.CreateGuildAnnouncementEvent or not C_Calendar.AddEvent then
    return nil, "This game client has no guild calendar."
  end
  if C_Calendar.CanAddEvent and not C_Calendar.CanAddEvent() then
    return nil, "Your guild rank can't add events to the guild calendar."
  end
  return true
end

local queue, inFlight, waiting = {}, nil, nil

local function finish(ok)
  if not inFlight then return end
  if ok then
    posted()[inFlight.key] = true
    MOTA:Print("Posted to the guild calendar: " .. inFlight.title .. ", " .. date("%d %b", inFlight.t) .. ".")
  else
    MOTA:Print("The guild calendar didn't take \"" .. inFlight.title .. "\". Try again from the Calendar.")
    wipe(queue)
  end
  inFlight = nil
  if waiting then waiting:Cancel(); waiting = nil end
  MOTA:Fire("CALENDAR_CHANGED")
  if ok and #queue > 0 then C_Timer.After(1, function() Calendar:PostNext() end) end
end

function Calendar:PostNext()
  if inFlight then return end
  local e = table.remove(queue, 1)
  if not e then return end
  local ok, why = self:CanPost()
  if not ok then MOTA:Print(why); wipe(queue); return end
  local r = self:RealmDate(e.t)
  inFlight = e
  local fine = pcall(function()
    C_Calendar.CreateGuildAnnouncementEvent()
    C_Calendar.EventSetTitle(self:Title(e))
    C_Calendar.EventSetDescription(e.text or "")
    if Enum and Enum.CalendarEventType and C_Calendar.EventSetType then
      C_Calendar.EventSetType(Enum.CalendarEventType.Other)
    end
    C_Calendar.EventSetDate(r.month, r.day, r.year)
    C_Calendar.EventSetTime(r.hour, r.min)
    C_Calendar.AddEvent()
  end)
  if not fine then finish(false); return end
  -- The game says CALENDAR_NEW_EVENT when it's in; give up after 15 seconds.
  waiting = C_Timer.NewTimer(15, function() waiting = nil; finish(false) end)
end

function Calendar:PostAll()
  local ok, why = self:CanPost()
  if not ok then return nil, why end
  if inFlight or #queue > 0 then return nil, "Already posting." end
  local list = self:ToPost()
  if #list == 0 then return nil, "Every coming date is already on the guild calendar." end
  for _, e in ipairs(list) do queue[#queue + 1] = e end
  self:PostNext()
  return #list
end

function Calendar:Posting() return inFlight ~= nil or #queue > 0 end

---------------------------------------------------------------------------
-- The game's events
---------------------------------------------------------------------------

local watch = CreateFrame("Frame")
for _, ev in ipairs({ "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_NEW_EVENT", "CALENDAR_UPDATE_ERROR" }) do
  pcall(watch.RegisterEvent, watch, ev)
end
watch:SetScript("OnEvent", function(_, ev, msg)
  if ev == "CALENDAR_NEW_EVENT" then
    finish(true)
  elseif ev == "CALENDAR_UPDATE_ERROR" then
    if inFlight then MOTA:Print("Guild calendar: " .. tostring(msg or "error")) end
    finish(false)
  end
  if loaded and Calendar:HasGameCalendar() then
    local y, m = loaded:match("^(%d+)-(%d+)$")
    if readMonth(tonumber(y), tonumber(m)) then MOTA:Fire("CALENDAR_CHANGED") end
  end
end)
