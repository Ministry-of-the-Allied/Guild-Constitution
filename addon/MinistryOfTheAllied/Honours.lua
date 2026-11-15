-- Ministry of the Allied: honours and medals (Duncan, 2026-11-08).
-- Orders are the Crown's to give, by hand. Medals are earned from the games
-- log (Games.lua) and need no record of their own: every copy works them out.
-- Honours are the player's, on all their characters (Account.lua).
--
--   honour.award   Crown   { v, o, why }   admits v to order o
--   honour.revoke  Crown   { v, o }        takes it away again
--
-- An order's letters follow the name, highest first: "Bram KC, SQ".

local _, MOTA = ...
local Honours = {}
MOTA.Honours = Honours

-- The orders, highest first.
Honours.ORDERS = {
  { key = "crown", title = "Knight of the Crown", letters = "KC", text = "the highest honour of the realm" },
  { key = "lion", title = "Order of the Lion", letters = "OL", text = "for valour in battle" },
  { key = "quill", title = "Order of the Silver Quill", letters = "SQ", text = "for service to the Ministry" },
  { key = "star", title = "The Royal Star", letters = "RS", text = "for an outstanding citizen" },
}
-- The medals, earned in the games.
Honours.MEDALS = {
  { key = "laurel", title = "Victor's Laurel", text = "won a guild game" },
  { key = "path", title = "Pathfinder's Medal", text = "first to finish a treasure hunt" },
  { key = "ring", title = "Ring Champion", text = "won The Ring" },
  { key = "finalist", title = "Ring Finalist", text = "fought The Final of The Ring" },
}
-- The current Ring champion's title, until the next tournament crowns another
-- (ADDON_SPEC.md 11.3; decided with Duncan, 2026-11-10).
Honours.GLADIATOR = "Gladiator of Stormwind"
local ORDER, MEDAL, RANK = {}, {}, {}
for i, o in ipairs(Honours.ORDERS) do ORDER[o.key], RANK[o.key] = o, i end
for i, m in ipairs(Honours.MEDALS) do MEDAL[m.key], RANK[m.key] = m, #Honours.ORDERS + i end
Honours.ORDER, Honours.MEDAL = ORDER, MEDAL

local function str(v, max) return type(v) == "string" and v ~= "" and #v <= max end
local function crown(a) return MOTA:IsCrown(a) end
MOTA.Book.rules["honour.award"] = function(a, rec)
  local d = rec and rec.d or {}
  return crown(a) and str(d.v, 40) and ORDER[d.o] ~= nil and (d.why == nil or str(d.why, 80))
end
MOTA.Book.rules["honour.revoke"] = function(a, rec)
  local d = rec and rec.d or {}
  return crown(a) and str(d.v, 40) and ORDER[d.o] ~= nil
end

-- Medals from the games: a lottery is luck, so it earns none.
local MEDAL_FOR = { hunt = "path" }

local cache
local function build()
  -- byName[character] = { [key] = { t, why, by, n } }
  local byName = {}
  local function give(name, key, t, extra)
    byName[name] = byName[name] or {}
    local h = byName[name][key]
    if h then
      h.n = h.n + 1
      if t > h.t then h.t = t end
    else
      byName[name][key] = { key = key, t = t, n = 1, why = extra and extra.why, by = extra and extra.by }
    end
  end
  local list = MOTA.Book:Latest()
  for i = #list, 1, -1 do
    local r = list[i]
    local d = r.d or {}
    if r.k == "honour.award" and ORDER[d.o] and str(d.v, 40) then
      if not (byName[d.v] and byName[d.v][d.o]) then give(d.v, d.o, r.t, { why = d.why, by = r.a }) end
    elseif r.k == "honour.revoke" and byName[d.v] then
      byName[d.v][d.o] = nil
    elseif r.k == "game.result" and type(d.places) == "table" and str(d.places[1], 40) and d.g ~= "lottery" then
      -- Everyone in 1st (Hide and Seek's survivors share it).
      local at = MOTA.Games:ValidAt(d.at, #d.places) and d.at or nil
      for i, who in ipairs(d.places) do
        if (at and at[i] or i) ~= 1 then break end
        if str(who, 40) then give(who, MEDAL_FOR[d.g] or "laurel", r.t) end
      end
    end
  end
  -- The Ring's finished tournaments: the champion and the losing finalist.
  for _, h in ipairs(MOTA.Ring and MOTA.Ring:Hall() or {}) do
    if str(h.champion, 40) then give(h.champion, "ring", h.t or 0) end
    if str(h.runnerUp, 40) then give(h.runnerUp, "finalist", h.t or 0) end
  end
  return byName
end

local function get()
  if not cache then cache = build() end
  return cache
end

-- name's honours, on all their characters, highest first:
-- { key, title, letters, text, t, n (times won), why, by, medal }.
function Honours:Of(name)
  local merged = {}
  for _, n in ipairs(MOTA.Account:Alts(name)) do
    for key, h in pairs(get()[n] or {}) do
      local m = merged[key]
      if m then
        if not ORDER[key] then m.n = m.n + h.n end -- an order is held once; medals add up
        if h.t > m.t then m.t = h.t end
      else
        merged[key] = { key = key, t = h.t, n = h.n, why = h.why, by = h.by }
      end
    end
  end
  local out = {}
  for key, h in pairs(merged) do
    local def = ORDER[key] or MEDAL[key]
    h.title, h.letters, h.text, h.medal = def.title, def.letters, def.text, MEDAL[key] ~= nil
    out[#out + 1] = h
  end
  -- The District Cup's titles (Cup.lua), newest season first, after the medals.
  for _, c in ipairs(MOTA.Cup and MOTA.Cup:TitlesOf(name) or {}) do
    out[#out + 1] = { key = c.key .. ":" .. c.season, cup = true, season = c.season, title = c.title, t = c.t or 0, n = 1,
      text = c.key == "cup" and "scored for the district that won the Cup" or "the most points in the Cup season", medal = true }
  end
  table.sort(out, function(a, b)
    local ra, rb = RANK[a.key] or 99, RANK[b.key] or 99
    if ra ~= rb then return ra < rb end
    if a.cup and b.cup and a.season ~= b.season then return a.season > b.season end
    return a.key < b.key
  end)
  return out
end

-- The current Ring champion: the champion of the latest finished tournament.
function Honours:Gladiator()
  local latest
  for _, h in ipairs(MOTA.Ring and MOTA.Ring:Hall() or {}) do
    if not latest or (h.t or 0) >= (latest.t or 0) then latest = h end
  end
  return latest and latest.champion
end

-- The title shown after a name: "Gladiator of Stormwind" for the current Ring
-- champion, else the newest Cup title ("Season 2 Champion"), or nil.
function Honours:Title(name)
  local glad = self:Gladiator()
  if glad then
    for _, n in ipairs(MOTA.Account and MOTA.Account:Alts(name) or { name }) do
      if n == glad then return self.GLADIATOR end
    end
  end
  local best
  for _, c in ipairs(MOTA.Cup and MOTA.Cup:TitlesOf(name) or {}) do
    if not best or c.season > best.season or (c.season == best.season and c.key == "cup") then best = c end
  end
  return best and best.title
end

-- The letters after a name: "KC, SQ", or nil.
function Honours:Letters(name)
  local out = {}
  for _, h in ipairs(self:Of(name)) do
    if h.letters then out[#out + 1] = h.letters end
  end
  if #out > 0 then return table.concat(out, ", ") end
end

function Honours:Has(name, key)
  for _, h in ipairs(self:Of(name)) do
    if h.key == key then return true end
  end
  return false
end

-- Everyone honoured, one entry per player (by their first character), highest first.
function Honours:Roll()
  local seen, out, names = {}, {}, {}
  for name in pairs(get()) do names[#names + 1] = name end
  -- Cup titles need no medal: anyone who scored in a finished season.
  for _, s in ipairs(MOTA.Cup and MOTA.Cup:Seasons() or {}) do
    if s.done then
      for _, m in ipairs(s.scorers) do names[#names + 1] = m.name end
    end
  end
  for _, name in ipairs(names) do
    local main = MOTA.Account:Alts(name)[1]
    if not seen[main] then
      seen[main] = true
      local list = self:Of(main)
      if #list > 0 then out[#out + 1] = { name = main, list = list } end
    end
  end
  table.sort(out, function(a, b)
    local ra, rb = RANK[a.list[1].key] or 99, RANK[b.list[1].key] or 99
    if ra ~= rb then return (ra or 99) < (rb or 99) end
    if #a.list ~= #b.list then return #a.list > #b.list end
    return a.name < b.name
  end)
  return out
end

-- Finds an order by its key, letters or a word of its title ("lion", "KC").
function Honours:FindOrder(word)
  word = strtrim(tostring(word or "")):lower()
  if word == "" then return nil end
  for _, o in ipairs(self.ORDERS) do
    if o.key == word or o.letters:lower() == word or o.title:lower() == word or o.title:lower():find(word, 1, true) then return o end
  end
end

local function who(name)
  local n = MOTA.District and MOTA.District:Resolve(strtrim(name or "")) or nil
  if n and (MOTA.roster[n] or MOTA:IsMe(n)) then return n end
end

function Honours:Award(name, order, why)
  if not MOTA:IsCrown(MOTA.me) then return nil, "Only the Crown confers honours." end
  local v = who(name)
  if not v then return nil, "There's nobody called " .. tostring(name) .. " in the guild." end
  local o = self:FindOrder(order)
  if not o then return nil, "There's no such order. The orders are: " .. self:OrderNames() .. "." end
  if self:Has(v, o.key) then return nil, MOTA:Short(v) .. " already holds the " .. o.title .. "." end
  why = why and strtrim(why) or ""
  if #why > 80 then return nil, "Keep the citation to 80 letters." end
  return MOTA.Book:Write("honour.award", { v = v, o = o.key, why = why ~= "" and why or nil })
end

function Honours:Revoke(name, order)
  if not MOTA:IsCrown(MOTA.me) then return nil, "Only the Crown takes honours away." end
  local v = who(name)
  if not v then return nil, "There's nobody called " .. tostring(name) .. " in the guild." end
  local o = self:FindOrder(order)
  if not o then return nil, "There's no such order." end
  -- The order may sit on any of their characters.
  for _, n in ipairs(MOTA.Account:Alts(v)) do
    if get()[n] and get()[n][o.key] then return MOTA.Book:Write("honour.revoke", { v = n, o = o.key }) end
  end
  return nil, MOTA:Short(v) .. " doesn't hold the " .. o.title .. "."
end

function Honours:OrderNames()
  local out = {}
  for _, o in ipairs(self.ORDERS) do out[#out + 1] = o.title .. " (" .. o.key .. ")" end
  return table.concat(out, ", ")
end

-- "Bram KC, SQ" for display; the name alone if they hold no order.
function MOTA:Styled(name)
  local letters = Honours:Letters(name)
  return self:Short(name) .. (letters and (" " .. letters) or "")
end

MOTA:Listen("GUILD_READY", function() cache = nil end)
MOTA:Listen("CAUGHT_UP", function() cache = nil end)
MOTA:Listen("ACCOUNT_CHANGED", function() cache = nil end)
MOTA:Listen("CUP_CHANGED", function(self) self:Fire("HONOURS_CHANGED") end)
MOTA:Listen("RING_CHANGED", function(self)
  cache = nil
  self:Fire("HONOURS_CHANGED")
end)
MOTA:Listen("RECORD_ADDED", function(self, rec)
  if rec.k == "game.result" then cache = nil; return end
  if rec.k ~= "honour.award" and rec.k ~= "honour.revoke" then return end
  cache = nil
  self:Fire("HONOURS_CHANGED")
  local d = rec.d or {}
  local o = ORDER[d.o]
  if rec.k ~= "honour.award" or self.Book.replaying or not self.Herald or not o then return end
  self.Herald:Announce({ seal = "crown", eyebrow = "By royal decree",
    title = self:Short(d.v) .. ", " .. o.title,
    text = (d.why and (d.why .. ". ") or "") .. "Conferred by " .. self:Short(rec.a) .. ", " .. o.text .. ".",
    button = { label = "Dismiss", style = "quiet" } })
end)
