-- Ministry of the Allied: the districts (ADDON_SPEC.md 10, CONSTITUENCIES.md).
-- Every citizen belongs to one of five districts. Worked out from the book of
-- records, like the party roll, so everyone holding the same records sees the
-- same districts.
--
-- Placing (Duncan, 2026-11-08): a citizen's own add-on places them the first
-- time they log in with it, in the smallest district (a random one of those
-- tied), so the districts stay within a few of each other. The Crown can still
-- move anyone.
--
--   citizen.district  Crown, or the citizen once  { who, d }   puts a citizen in district d
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
  if not (rec ~= nil and str(rec.d.who, 80) and byCode[rec.d.d] ~= nil) then return false end
  if MOTA:IsCrown(a) then return true end
  -- Placing yourself: only yourself, and the Crown belongs to no district.
  return rec.d.who == a
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
      -- A citizen's own placement counts only the first time; a move is the Crown's.
      if MOTA:IsCrown(r.a) or (r.a == d.who and not out.of[d.who]) then out.of[d.who] = d.d end
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

-- Is the point inside the polygon (a flat list x1, y1, x2, y2, ...)?
local function inside(pts, x, y)
  local hit, n = false, #pts / 2
  local j = n
  for i = 1, n do
    local xi, yi, xj, yj = pts[2 * i - 1], pts[2 * i], pts[2 * j - 1], pts[2 * j]
    if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then hit = not hit end
    j = i
  end
  return hit
end

-- Which district's outline holds this point, if any. x, y are pixels of the
-- Stormwind City screenshot the shapes were traced on, from the chart's crop
-- corner (Media.lua districts). Used by the Districts page and the world map.
function District:At(x, y)
  local dz = MOTA.Media and MOTA.Media.districts
  if not dz or type(x) ~= "number" or type(y) ~= "number" then return nil end
  for code, pts in pairs(dz.shapes) do
    if inside(pts, x, y) then return code end
  end
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

-- The Crown places or moves a citizen. Returns the record, or nil and why not.
function District:Assign(name, code)
  if not MOTA.me or not MOTA:IsCrown(MOTA.me) then return nil, "Only the Crown moves citizens between districts." end
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

-- The smallest district, a random one if several are tied.
function District:Smallest()
  local sizes = self:Sizes()
  local low, best = math.huge, {}
  for _, d in ipairs(MOTA.CONST.DISTRICTS) do
    local n = sizes[d.code]
    if n < low then low, best = n, { d.code } elseif n == low then best[#best + 1] = d.code end
  end
  return best[math.random(#best)]
end

-- My own add-on places me, the first time, once it has caught up with the guild.
function District:PlaceMe()
  local me = MOTA.me
  if not me or not MOTA.guild or MOTA:IsCrown(me) or state().of[me] then return nil end
  if not MOTA.roster[me] then return nil end
  -- An alt lives where the player's other characters do (Account.lua).
  local code
  for _, n in ipairs(MOTA.Account:Alts(me)) do code = code or state().of[n] end
  code = code or self:Smallest()
  local rec = MOTA.Book:Write("citizen.district", { who = me, d = code })
  if rec then
    local d = byCode[code]
    MOTA:Print("Welcome, citizen. You live in " .. d.name .. ". Its council meets at the " .. d.meet .. ".")
  end
  return rec
end

local function changed()
  cache = nil
  MOTA:Fire("DISTRICT_CHANGED")
end

-- After the first catch-up, so the sizes are the guild's, not a fresh copy's.
District.PLACE_DELAY = 45
MOTA:Listen("GUILD_READY", function()
  C_Timer.After(District.PLACE_DELAY, function() District:PlaceMe() end)
end)

MOTA:Listen("GUILD_READY", changed)
MOTA:Listen("ROSTER_UPDATED", changed)
MOTA:Listen("RECORD_ADDED", function(_, rec)
  if rec.k == "citizen.district" or rec.k == "district.rep" then changed() end
end)
