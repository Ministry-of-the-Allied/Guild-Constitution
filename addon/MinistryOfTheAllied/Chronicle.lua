-- Ministry of the Allied: the Chronicle, the realm's permanent dated history
-- (ADDON_SPEC.md, section 10.3). Nothing is written here: it reads the book,
-- whose records are synced to every member and never deleted, so a new member
-- gets the whole history with the rest.
--
--   Chronicle:Line(record)     one record as a line { text, hex, page, group, t }, or nil
--   Chronicle:All(filter)      every line, newest first (no limit), for one filter
--   Chronicle:Months(filter)   the same, grouped by month: { key, label, lines }, newest first
--   Chronicle:Count(filter)    how many lines
--
-- Throne:Decrees (the Throne Room's "Recent decrees") takes its lines from here, so the
-- feed and the Chronicle always say the same thing.
--
-- Laws passed and lapsed and court rulings have no record kinds yet, so they are not
-- in the Chronicle until something writes them (section 10.3).

local _, MOTA = ...
local Chronicle = {}
MOTA.Chronicle = Chronicle

local GEM = { crown = "1B3570", floor = "9E1B22", fail = "6E1712", party = "1F4290", ring = "7A5719" }
Chronicle.GEM = GEM
local NAMES = { sh = "Silverhand", ex = "Exchange" }
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
  "November", "December" }
Chronicle.MONTHS = MONTHS

-- The kind filter on the page, in order. "all" shows everything.
Chronicle.FILTERS = {
  { key = "all", label = "All" },
  { key = "elections", label = "Elections" },
  { key = "parties", label = "Parties" },
  { key = "honours", label = "Honours" },
  { key = "games", label = "Games" },
  { key = "ring", label = "Ring" },
}

local cache = {}
local function forget() cache = {} end
MOTA:Listen("RECORD_ADDED", forget)
MOTA:Listen("GUILD_READY", forget)

local function pages() return MOTA.Throne and MOTA.Throne.PAGES or {} end
local function bold(s) return "|cff2A1F14" .. s .. "|r" end

-- A record as a line of the Chronicle, or nil if it isn't one of the kinds it keeps.
-- group is the filter it sits under; page (and view, its sub-view) is where it opens, if anywhere.
function Chronicle:Line(r)
  local d = r.d or {}
  local PAGES = pages()
  local e
  if r.k == "ballot.result" and d.w and type(d.cands) == "table" and d.cands[d.w] then
    e = { text = bold(MOTA:Short(d.cands[d.w].n)) .. " wins " .. tostring(d.name), hex = GEM.crown, page = PAGES.ballot, group = "elections" }
  elseif r.k == "contest.result" and d.w then
    e = { text = bold(MOTA:Short(d.w)) .. " leads the " .. (NAMES[d.p] or "party"), hex = GEM.party, page = PAGES.parties, view = d.p, group = "parties" }
  elseif r.k == "party.leave" or r.k == "party.remove" then
    local who = r.k == "party.leave" and r.a or d.v
    e = { text = bold(MOTA:Short(who)) .. " crossed the floor", hex = GEM.floor, page = PAGES.parties, group = "parties" }
  elseif r.k == "nc.result" then
    e = { text = "Vote of No Confidence " .. bold(d.passed and "passed" or "failed"), hex = GEM.fail, page = PAGES.ballot, group = "elections" }
  elseif r.k == "election.date" then
    e = { text = (d.kind == "snap" and ("A " .. bold("Snap Election") .. " is called") or ("A " .. bold("General Election") .. " is set for " .. date("%d %b", d.at))),
      hex = GEM.crown, page = PAGES.parties, group = "elections" }
  elseif r.k == "judiciary.appoint" and d.v then
    e = { text = bold(MOTA:Short(d.v)) .. " appointed a Justice", hex = GEM.crown, page = PAGES.statute, view = "court", group = "honours" }
  elseif r.k == "contest.emergency" then
    e = { text = "An " .. bold("emergency contest") .. " moves polling day back", hex = GEM.fail, page = PAGES.parties, group = "elections" }
  elseif r.k == "honour.award" and MOTA.Honours and MOTA.Honours.ORDER[d.o] then
    e = { text = bold(MOTA:Short(d.v)) .. " is made " .. MOTA.Honours.ORDER[d.o].title, hex = GEM.crown, page = PAGES.games, view = "honours", group = "honours" }
  elseif r.k == "game.result" and type(d.places) == "table" and d.places[1] then
    e = { text = bold(MOTA:Short(d.places[1])) .. " wins " .. tostring(d.name), hex = GEM.ring, page = PAGES.games, group = "games",
      view = (d.g == "lottery" or d.g == "hunt") and d.g or "cup" } -- the Cup counts the other games
  elseif r.k == "lottery.open" and type(d.price) == "number" then
    e = { text = bold(tostring(d.name)) .. " is open, tickets " .. MOTA:Money(d.price), hex = GEM.ring, page = PAGES.games, view = "lottery", group = "games" }
  elseif r.k == "ring.result" and d.s == 7 and d.w then
    e = { text = bold(MOTA:Short(d.w)) .. " is champion of the Ring", hex = GEM.ring, page = PAGES.ring, view = "champions", group = "ring" }
  end
  if e then e.t = r.t end
  return e
end

-- Every line, newest first, with no limit. Cached until a record arrives.
function Chronicle:All(filter)
  filter = filter or "all"
  local key = "all:" .. filter
  if cache[key] then return cache[key] end
  local out = {}
  cache[key] = out
  if filter == "all" then
    for _, r in ipairs(MOTA.Book:Latest()) do
      local e = self:Line(r)
      if e then out[#out + 1] = e end
    end
  else
    for _, e in ipairs(self:All("all")) do
      if e.group == filter then out[#out + 1] = e end
    end
  end
  return out
end

function Chronicle:Count(filter)
  return #self:All(filter)
end

-- The lines grouped by calendar month, newest month first: { key = "2026-11", year, month, label = "November 2026", lines }.
function Chronicle:Months(filter)
  filter = filter or "all"
  local key = "months:" .. filter
  if cache[key] then return cache[key] end
  local out, byKey = {}, {}
  cache[key] = out
  for _, e in ipairs(self:All(filter)) do
    local year, month = tonumber(date("%Y", e.t)), tonumber(date("%m", e.t))
    local k = ("%04d-%02d"):format(year, month)
    local g = byKey[k]
    if not g then
      g = { key = k, year = year, month = month, label = MONTHS[month] .. " " .. year, lines = {} }
      byKey[k] = g
      out[#out + 1] = g
    end
    g.lines[#g.lines + 1] = e
  end
  return out
end
