-- Ministry of the Allied: the games log (Duncan, 2026-11-08).
-- Every guild game's result is written to the book, so the District Cup can
-- count it (Cup.lua) and the winners are honoured (Honours.lua).
--
--   game.result  the Crown or the Minister of Games
--                { g = kind, name, places = { first, second, ... }, ds = { district of each },
--                  at = { place of each } }  (optional: shared places, as { 1, 1, 2, 3 })
--
-- Results come from the games themselves (the treasure hunt and the lottery,
-- later) or are written by hand for games run in the world:
--   /mota games result <title>: <first>, <second>, <third>
-- Each place keeps the district its player lived in on the day, for the Cup.

local _, MOTA = ...
local Games = {}
MOTA.Games = Games

Games.KINDS = {
  hunt = "Treasure hunt",
  lottery = "Lottery",
  hide = "Hide and seek",
  race = "Race",
  quiz = "Quiz",
  other = "Game",
}
Games.MAX_PLACES = 20 -- a quiz's top three teams of four, with ties

local function str(v, max) return type(v) == "string" and v ~= "" and #v <= max end

-- The government's Minister of Games (Bench.lua), if there's a government.
function Games:Minister()
  local gov = MOTA.Elect and MOTA.Elect:Government()
  return gov and gov.p and MOTA.Bench:Holder(gov.p, "games")
end

-- The Crown and the Minister of Games run the guild's games.
function Games:CanRun(name)
  if not name then return false end
  return MOTA:IsCrown(name) or name == self:Minister()
end

-- Shared places: one rank per name, starting at 1, never going down.
function Games:ValidAt(at, n)
  if type(at) ~= "table" or #at ~= n or at[1] ~= 1 then return false end
  for i, v in ipairs(at) do
    if type(v) ~= "number" or v < 1 or v > n or (i > 1 and v < at[i - 1]) then return false end
  end
  return true
end

-- The place of the i-th name in a result.
function Games:PlaceOf(e, i)
  return type(e.at) == "table" and e.at[i] or i
end

MOTA.Book.rules["game.result"] = function(a, rec)
  local d = rec and rec.d or {}
  if not Games:CanRun(a) or not Games.KINDS[d.g] or not str(d.name, 60) then return false end
  if type(d.places) ~= "table" or #d.places < 1 or #d.places > Games.MAX_PLACES then return false end
  for _, n in ipairs(d.places) do
    if not str(n, 40) then return false end
  end
  if d.at ~= nil and not Games:ValidAt(d.at, #d.places) then return false end
  return true
end

local cache
local function build()
  local out = {}
  for _, r in ipairs(MOTA.Book:Latest()) do
    -- Who may write one was checked as it arrived (a past Minister of Games'
    -- results stand after they leave the post), so only the shape is checked here.
    if r.k == "game.result" and type(r.d) == "table" and type(r.d.places) == "table" and r.d.places[1] then
      local d = r.d
      out[#out + 1] = { t = r.t, by = r.a, g = d.g, name = d.name, places = d.places, ds = d.ds or {}, at = Games:ValidAt(d.at, #d.places) and d.at or nil }
    end
  end
  return out
end

-- Every result, newest first.
function Games:Log()
  if not cache then cache = build() end
  return cache
end

-- Writes a result. places are names, first place first; at (optional) gives
-- each name's place, for ties.
function Games:Record(kind, name, places, at)
  if not self:CanRun(MOTA.me) then return nil, "Only the Crown and the Minister of Games record the guild's games." end
  kind = self.KINDS[kind] and kind or "other"
  name = name and strtrim(name) or ""
  if name == "" then return nil, "Give the game a title." end
  if #name > 60 then return nil, "That title is too long." end
  if type(places) ~= "table" or #places == 0 then return nil, "Name at least the winner." end
  if #places > self.MAX_PLACES then return nil, "Up to " .. self.MAX_PLACES .. " places." end
  local clean, ds, seen = {}, {}, {}
  for i, n in ipairs(places) do
    local who = MOTA.District and MOTA.District:Resolve(strtrim(n)) or MOTA:Bare(n)
    if not who or not (MOTA.roster[who] or MOTA:IsMe(who)) then return nil, "There's nobody called " .. tostring(n) .. " in the guild." end
    if seen[who] then return nil, MOTA:Short(who) .. " is named twice." end
    seen[who] = true
    clean[i] = who
    local district = MOTA.District and MOTA.District:Of(who)
    ds[i] = district and district.code or ""
  end
  if at ~= nil and not self:ValidAt(at, #clean) then return nil, "Those places don't add up." end
  return MOTA.Book:Write("game.result", { g = kind, name = name, places = clean, ds = ds, at = at })
end

-- One line per result, for /mota games.
function Games:Line(e)
  local shown = {}
  for i, n in ipairs(e.places) do
    local p = self:PlaceOf(e, i)
    if p > 3 then break end
    shown[#shown + 1] = ({ "1st", "2nd", "3rd" })[p] .. " " .. MOTA:Short(n)
  end
  return date("%d %b", e.t) .. " · " .. e.name .. " (" .. (self.KINDS[e.g] or "Game") .. ") · " .. table.concat(shown, ", ")
end

MOTA:Listen("GUILD_READY", function() cache = nil end)
MOTA:Listen("CAUGHT_UP", function() cache = nil end)
MOTA:Listen("RECORD_ADDED", function(self, rec)
  if rec.k == "party.post" or rec.k == "ballot.result" then cache = nil end
  if rec.k ~= "game.result" then return end
  cache = nil
  self:Fire("GAMES_CHANGED")
  local d = rec.d or {}
  if self.Book.replaying or not self.Herald or type(d.places) ~= "table" or not d.places[1] then return end
  local firsts, rest = {}, {}
  for i = 1, #d.places do
    local p = Games:PlaceOf(d, i)
    if p == 1 then firsts[#firsts + 1] = MOTA:Short(d.places[i])
    elseif p <= 3 and #rest < 2 then rest[#rest + 1] = MOTA:Short(d.places[i]) end
  end
  local who = #firsts > 1 and (table.concat(firsts, ", ", 1, #firsts - 1) .. " and " .. firsts[#firsts] .. " share") or (firsts[1] .. " wins")
  self.Herald:Announce({ seal = "official", eyebrow = "The Games",
    title = who .. " " .. tostring(d.name),
    text = #rest > 0 and ("Then " .. table.concat(rest, ", then ") .. ". Well played, all.") or "Well played, all.",
    button = { label = "Dismiss", style = "quiet" } })
end)
