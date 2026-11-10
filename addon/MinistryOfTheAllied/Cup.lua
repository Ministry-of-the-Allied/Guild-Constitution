-- Ministry of the Allied: the District Cup (Duncan, 2026-11-10).
-- Worked out from the book like the Games log, so nothing new is written.
--
-- Players score, districts win. Every placing earns its player points:
--   1st 10, 2nd 6, 3rd 3. No points for taking part.
--   Every game in the Games log counts, except the lottery (it's luck).
--   A Ring tournament counts too: champion 10, runner-up 6, the two losing
--   semi-finalists 3 each.
-- A district's total is its members' points, in the district each lived in on
-- the day of the game. The Crown belongs to no district and isn't on the board.
--
-- Seasons follow the election cycle: a season ends when a General or Snap
-- Election is declared, and the points start again. Season 1 is everything
-- before the first declared election.
--
-- Honours (Honours.lua), once a season ends:
--   "Season n Champion"   every member of the winning district who scored in it
--   "Season n Top Scorer" the player with the most points (ties share it)

local _, MOTA = ...
local Cup = {}
MOTA.Cup = Cup

Cup.POINTS = { 10, 6, 3 }
local NO_POINTS = { lottery = true }
local GOVERNS = { general = true, snap = true, runoff = true } -- as Elect.lua

local byCode = {}
for _, d in ipairs(MOTA.CONST.DISTRICTS) do byCode[d.code] = d end

-- A saved district: a code, or (results written before 0.8.9) the whole entry.
local function codeOf(v)
  if type(v) == "table" then v = v.code end
  return type(v) == "string" and byCode[v] and v or nil
end

local cache

local function build()
  local list = MOTA.Book:Latest()
  local ends = {}       -- the time each season ended, in order
  local placed = {}     -- [who] = { { t, code }, ... } oldest first
  local scores = {}     -- { t, who, pts, code? }
  for i = #list, 1, -1 do -- oldest first
    local r = list[i]
    local d = r.d or {}
    if r.k == "ballot.result" and GOVERNS[d.kind] and d.w and type(d.cands) == "table" and d.cands[d.w] then
      ends[#ends + 1] = r.t
    elseif r.k == "citizen.district" and byCode[d.d] and type(d.who) == "string" then
      -- As District.lua: a citizen's own placement counts only the first time.
      local h = placed[d.who]
      if MOTA:IsCrown(r.a) or (r.a == d.who and not h) then
        placed[d.who] = h or {}
        table.insert(placed[d.who], { t = r.t, code = d.d })
      end
    elseif r.k == "game.result" and not NO_POINTS[d.g] and type(d.places) == "table" then
      local ds = type(d.ds) == "table" and d.ds or {}
      for p = 1, #Cup.POINTS do
        local who = d.places[p]
        if type(who) == "string" and who ~= "" then
          scores[#scores + 1] = { t = r.t, who = who, pts = Cup.POINTS[p], code = codeOf(ds[p]) }
        end
      end
    end
  end
  -- The Ring's finished tournaments.
  for _, h in ipairs(MOTA.Ring and MOTA.Ring:Hall() or {}) do
    local function add(who, pts)
      if type(who) == "string" and who ~= "" then scores[#scores + 1] = { t = h.t, who = who, pts = pts } end
    end
    add(h.champion, Cup.POINTS[1])
    add(h.runnerUp, Cup.POINTS[2])
    for _, s in ipairs(h.semis or {}) do add(s, Cup.POINTS[3]) end
  end

  local function seasonAt(t)
    for i, e in ipairs(ends) do
      if t < e then return i end
    end
    return #ends + 1
  end
  local function districtAt(who, t)
    local code
    for _, p in ipairs(placed[who] or {}) do
      if p.t <= t then code = p.code end
    end
    return code
  end

  local seasons = {}
  for n = 1, #ends + 1 do
    seasons[n] = { n = n, ends = ends[n], done = ends[n] ~= nil, districts = {}, players = {} }
  end
  for _, s in ipairs(scores) do
    if not MOTA:IsCrown(s.who) then
      local season = seasons[seasonAt(s.t)]
      local code = s.code or districtAt(s.who, s.t)
      local pl = season.players[s.who] or { name = s.who, pts = 0, by = {} }
      season.players[s.who] = pl
      pl.pts = pl.pts + s.pts
      if code then
        pl.by[code] = (pl.by[code] or 0) + s.pts
        season.districts[code] = (season.districts[code] or 0) + s.pts
      end
    end
  end

  for _, season in ipairs(seasons) do
    -- The board: every district, most points first.
    local board = {}
    for _, d in ipairs(MOTA.CONST.DISTRICTS) do
      board[#board + 1] = { code = d.code, name = d.name, short = d.short, pts = season.districts[d.code] or 0 }
    end
    table.sort(board, function(a, b)
      if a.pts ~= b.pts then return a.pts > b.pts end
      return a.name < b.name
    end)
    season.board = board
    -- Players, joined across alts, most points first.
    local mains, order = {}, {}
    for who, pl in pairs(season.players) do
      local main = MOTA.Account and MOTA.Account:Alts(who)[1] or who
      local m = mains[main]
      if not m then
        m = { name = main, pts = 0, by = {}, chars = {} }
        mains[main] = m
        order[#order + 1] = m
      end
      m.pts = m.pts + pl.pts
      m.chars[who] = true
      for code, pts in pairs(pl.by) do m.by[code] = (m.by[code] or 0) + pts end
    end
    table.sort(order, function(a, b)
      if a.pts ~= b.pts then return a.pts > b.pts end
      return a.name < b.name
    end)
    season.scorers = order
    -- The winners, once the season is over (ties share).
    season.champions, season.top = {}, {}
    if season.done and board[1].pts > 0 then
      for _, b in ipairs(board) do
        if b.pts == board[1].pts then season.champions[b.code] = true end
      end
      for _, m in ipairs(order) do
        if m.pts == order[1].pts then season.top[#season.top + 1] = m.name end
      end
    end
  end
  return seasons
end

local function get()
  if not cache then cache = build() end
  return cache
end

-- Every season, oldest first: { n, ends, done, board, scorers, champions = { [code] = true }, top }.
function Cup:Seasons()
  return get()
end

-- The season now being played.
function Cup:Current()
  local s = get()
  return s[#s]
end

-- The Cup titles a player holds, on all their characters, oldest first:
-- { { season, key = "cup" | "scorer", title, t } }.
function Cup:TitlesOf(name)
  local out = {}
  local alts = {}
  for _, n in ipairs(MOTA.Account and MOTA.Account:Alts(name) or { name }) do alts[n] = true end
  for _, s in ipairs(get()) do
    if s.done then
      for _, m in ipairs(s.scorers) do
        local mine = false
        for c in pairs(m.chars) do mine = mine or alts[c] end
        if mine then
          -- Champion: scored for the winning district.
          for code in pairs(s.champions) do
            if (m.by[code] or 0) > 0 then
              out[#out + 1] = { season = s.n, key = "cup", title = "Season " .. s.n .. " Champion", t = s.ends }
              break
            end
          end
          for _, top in ipairs(s.top) do
            if top == m.name then
              out[#out + 1] = { season = s.n, key = "scorer", title = "Season " .. s.n .. " Top Scorer", t = s.ends }
            end
          end
        end
      end
    end
  end
  return out
end

local function forget()
  cache = nil
end
MOTA:Listen("GUILD_READY", forget)
MOTA:Listen("CAUGHT_UP", forget)
MOTA:Listen("ACCOUNT_CHANGED", forget)
local MATTERS = { ["game.result"] = true, ["ballot.result"] = true, ["citizen.district"] = true }
MOTA:Listen("RECORD_ADDED", function(self, rec)
  if MATTERS[rec.k] or rec.k:find("^ring%.") then
    cache = nil
    self:Fire("CUP_CHANGED")
  end
end)
