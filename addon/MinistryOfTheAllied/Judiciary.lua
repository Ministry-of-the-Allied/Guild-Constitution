-- Ministry of the Allied: the High Judiciary (Charter Part VI).
-- The Crown appoints three Justices. They're independent of the government:
-- the Cabinet appoints none (Duncan, 2026-11-08). A Justice holds no other
-- office, serves two full terms (six months) and may be reappointed once.
--
--   judiciary.appoint  Crown  { v }   seats a Justice (at most three sit)
--   judiciary.remove   Crown  { v }   ends an appointment early
--
-- The Court itself (accusations and rulings) is still to come; its page reads
-- the Justices from here.

local _, MOTA = ...
local Judiciary = {}
MOTA.Judiciary = Judiciary

Judiciary.SEATS = 3
Judiciary.TERM_MONTHS = 6 -- two full government terms
Judiciary.MAX_TIMES = 2   -- appointed, then reappointed once

local function crown(author) return MOTA:IsCrown(author) end
MOTA.Book.rules["judiciary.appoint"] = crown
MOTA.Book.rules["judiciary.remove"] = crown

local cache

local function build()
  local out = { seats = {}, times = {} }
  local list = MOTA.Book:Latest()
  for i = #list, 1, -1 do
    local r = list[i]
    local d = r.d or {}
    local v = d.v
    if type(v) == "string" then
      -- Appointments that have run their course leave their seats.
      for name, s in pairs(out.seats) do
        if r.t >= s.ends then out.seats[name] = nil end
      end
      if r.k == "judiciary.appoint" and not out.seats[v] then
        local n = 0
        for _ in pairs(out.seats) do n = n + 1 end
        if n < Judiciary.SEATS and (out.times[v] or 0) < Judiciary.MAX_TIMES then
          out.times[v] = (out.times[v] or 0) + 1
          out.seats[v] = { name = v, at = r.t, ends = MOTA.Elect:AddMonths(r.t, Judiciary.TERM_MONTHS) }
        end
      elseif r.k == "judiciary.remove" then
        out.seats[v] = nil
      end
    end
  end
  return out
end

local function get()
  if not cache then cache = build() end
  return cache
end

-- The Justices sitting now, oldest appointment first: { name, at, ends }.
function Judiciary:Justices()
  local out, now = {}, GetServerTime()
  for _, s in pairs(get().seats) do
    if now < s.ends then out[#out + 1] = s end
  end
  table.sort(out, function(a, b)
    if a.at ~= b.at then return a.at < b.at end
    return a.name < b.name
  end)
  return out
end

function Judiciary:IsJustice(name)
  local s = name and get().seats[name]
  return s ~= nil and GetServerTime() < s.ends
end

-- Any other office: Prime Minister, a party's leader or front bench, a Representative.
function Judiciary:OfficeOf(name)
  local gov = MOTA.Elect and MOTA.Elect:Government()
  if gov and gov.name == name then return "Prime Minister" end
  local p = MOTA.Party:Of(name)
  if p then
    if MOTA.Bench:IsLeader(name, p) then return "party leader" end
    for _, post in ipairs(MOTA.Bench.POSTS) do
      if MOTA.Bench:Holder(p, post) == name then return MOTA.Bench.TITLES[post] end
    end
  end
  if MOTA.District then
    for code in pairs(MOTA.District.byCode) do
      if MOTA.District:Rep(code) == name then return "a district's Representative" end
    end
  end
end

function Judiciary:Appoint(name)
  if not MOTA:IsCrown(MOTA.me) then return nil, "Only the King and the Crown appoint Justices." end
  name = MOTA.District and MOTA.District:Resolve(name) or name
  if not name or not MOTA.roster[name] then return nil, "They aren't on the guild roster." end
  if MOTA:IsCrown(name) then return nil, "The Crown can't sit as a Justice." end
  if self:IsJustice(name) then return nil, MOTA:Short(name) .. " already sits." end
  if #self:Justices() >= self.SEATS then return nil, "All three seats are filled." end
  if (get().times[name] or 0) >= self.MAX_TIMES then return nil, MOTA:Short(name) .. " has already been reappointed once (Charter 6.1)." end
  local office = self:OfficeOf(name)
  if office then return nil, MOTA:Short(name) .. " holds another office (" .. office .. "). A Justice may hold none." end
  return MOTA.Book:Write("judiciary.appoint", { v = name })
end

function Judiciary:Remove(name)
  if not MOTA:IsCrown(MOTA.me) then return nil, "Only the King and the Crown remove Justices." end
  name = MOTA.District and MOTA.District:Resolve(name) or name
  if not self:IsJustice(name) then return nil, "They don't sit on the High Judiciary." end
  return MOTA.Book:Write("judiciary.remove", { v = name })
end

-- "A, B and C", for the Court's page.
function Judiciary:Line()
  local names = {}
  for _, s in ipairs(self:Justices()) do names[#names + 1] = MOTA:Short(s.name) end
  if #names == 0 then return "No Justices have been appointed yet." end
  local last = table.remove(names)
  return "The High Judiciary: " .. (#names > 0 and (table.concat(names, ", ") .. " and ") or "") .. last .. "."
end

MOTA:Listen("GUILD_READY", function() cache = nil end)
MOTA:Listen("RECORD_ADDED", function(self, rec)
  if rec.k:sub(1, 10) ~= "judiciary." then return end
  cache = nil
  self:Fire("JUDICIARY_CHANGED")
  if self.Book.replaying or not self.Herald or rec.k ~= "judiciary.appoint" or not Judiciary:IsJustice(rec.d.v) then return end
  self.Herald:Announce({ seal = "crown", eyebrow = "By the Crown", title = self:Short(rec.d.v) .. " is appointed a Justice",
    text = "A seat on the High Judiciary, independent of the government, until " .. date("%d %b %Y", get().seats[rec.d.v].ends) .. ".",
    button = { label = "Dismiss", style = "quiet" } })
end)
