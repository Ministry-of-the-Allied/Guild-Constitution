-- Ministry of the Allied: the districts (ADDON_SPEC.md 10, CONSTITUENCIES.md).
-- Every citizen belongs to one of five districts, placed there by the Crown
-- (Max's answer A5). Worked out from the book of records, like the party roll,
-- so everyone holding the same records sees the same districts.
--
--   citizen.district  Crown  { who, d }   puts a citizen in district d
--   district.rep      Crown  { d, who }   names a district's Representative
--                                         (who = "" leaves the seat vacant)
--
-- The newest record for a citizen (or a district's seat) wins. Elections for
-- Representatives stay manual for now: the Crown records the result.
-- Shown on the Districts page (UI/Districts.lua) and the world map (UI/WorldMap.lua).

local _, MOTA = ...
local District = {}
MOTA.District = District

local byCode = {}
for _, d in ipairs(MOTA.CONST.DISTRICTS) do byCode[d.code] = d end
District.byCode = byCode

local function str(v, max) return type(v) == "string" and v ~= "" and #v <= max end

local rules = MOTA.Book.rules
rules["citizen.district"] = function(a, rec)
  return MOTA:IsCrown(a) and rec ~= nil and str(rec.d.who, 80) and byCode[rec.d.d] ~= nil
end
rules["district.rep"] = function(a, rec)
  return MOTA:IsCrown(a) and rec ~= nil and byCode[rec.d.d] ~= nil
    and type(rec.d.who) == "string" and #rec.d.who <= 80
end

local cache

local function build()
  local out = { of = {}, rep = {} }
  local list = MOTA.Book:Latest()
  for i = #list, 1, -1 do -- oldest first, so the newest record wins
    local r = list[i]
    local d = r.d or {}
    if r.k == "citizen.district" and byCode[d.d] and type(d.who) == "string" then
      out.of[d.who] = d.d
    elseif r.k == "district.rep" and byCode[d.d] and type(d.who) == "string" then
      out.rep[d.d] = d.who ~= "" and d.who or nil
    end
  end
  return out
end

local function state()
  if not cache then cache = build() end
  return cache
end

-- A person's district: the entry from CONST.DISTRICTS, or nil if the Crown
-- hasn't placed them.
function District:Of(name)
  local code = name and state().of[name]
  return code and byCode[code] or nil
end

function MOTA:DistrictOf(name)
  return District:Of(name)
end

-- Citizens placed in a district who are still in the guild (everyone, while the
-- roster hasn't loaded).
function District:Members(code)
  local out, loaded = {}, next(MOTA.roster) ~= nil
  for who, c in pairs(state().of) do
    if c == code and (not loaded or MOTA.roster[who]) then out[#out + 1] = who end
  end
  table.sort(out)
  return out
end

function District:Size(code)
  return #self:Members(code)
end

-- { [code] = size } for all five, and how many are placed in total.
function District:Sizes()
  local sizes, total = {}, 0
  for _, d in ipairs(MOTA.CONST.DISTRICTS) do
    sizes[d.code] = self:Size(d.code)
    total = total + sizes[d.code]
  end
  return sizes, total
end

-- A district's Representative's name, or nil for a vacant seat.
function District:Rep(code)
  return state().rep[code]
end

-- The name as the roster spells it, matched without regard to capitals.
function District:Resolve(name)
  if type(name) ~= "string" or name == "" then return nil end
  if MOTA.roster[name] then return name end
  local lower = name:lower()
  for who in pairs(MOTA.roster) do
    if who:lower() == lower then return who end
  end
end

-- A district code from what a person typed: the code, or any part of a name.
function District:Code(word)
  if type(word) ~= "string" or word == "" then return nil end
  local up = word:upper()
  if byCode[up] then return up end
  local lower, found = word:lower(), nil
  for _, d in ipairs(MOTA.CONST.DISTRICTS) do
    if d.short:lower():find(lower, 1, true) or d.place:lower():find(lower, 1, true) then
      if found then return nil end -- more than one fits
      found = d.code
    end
  end
  return found
end

-- The Crown places a citizen. Returns the record, or nil and why not.
function District:Assign(name, code)
  if not MOTA.me or not MOTA:IsCrown(MOTA.me) then return nil, "Only the Crown places citizens in districts." end
  if not byCode[code] then return nil, "There is no district with that code." end
  local who = self:Resolve(name)
  if not who then return nil, "That name isn't on the guild roster." end
  if MOTA:IsCrown(who) then return nil, "The Crown belongs to no district." end
  if state().of[who] == code then return nil, who .. " is already in " .. byCode[code].short .. "." end
  return MOTA.Book:Write("citizen.district", { who = who, d = code })
end

-- The Crown names a district's Representative (name nil or "" empties the seat).
function District:SetRep(code, name)
  if not MOTA.me or not MOTA:IsCrown(MOTA.me) then return nil, "Only the Crown names Representatives." end
  if not byCode[code] then return nil, "There is no district with that code." end
  local who = ""
  if name and name ~= "" then
    who = self:Resolve(name)
    if not who then return nil, "That name isn't on the guild roster." end
    if state().of[who] ~= code then return nil, who .. " isn't a citizen of " .. byCode[code].short .. "." end
  end
  return MOTA.Book:Write("district.rep", { d = code, who = who })
end

local function changed()
  cache = nil
  MOTA:Fire("DISTRICT_CHANGED")
end

MOTA:Listen("GUILD_READY", changed)
MOTA:Listen("ROSTER_UPDATED", changed)
MOTA:Listen("RECORD_ADDED", function(_, rec)
  if rec.k == "citizen.district" or rec.k == "district.rep" then changed() end
end)
