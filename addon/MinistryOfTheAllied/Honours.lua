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
}
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
      give(d.places[1], MEDAL_FOR[d.g] or "laurel", r.t)
    end
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
  table.sort(out, function(a, b) return RANK[a.key] < RANK[b.key] end)
  return out
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
  local seen, out = {}, {}
  for name in pairs(get()) do
    local main = MOTA.Account:Alts(name)[1]
    if not seen[main] then
      seen[main] = true
      local list = self:Of(main)
      if #list > 0 then out[#out + 1] = { name = main, list = list } end
    end
  end
  table.sort(out, function(a, b)
    local ra, rb = RANK[a.list[1].key], RANK[b.list[1].key]
    if ra ~= rb then return ra < rb end
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
